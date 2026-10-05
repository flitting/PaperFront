"""Validate delivered PCM files and write review evidence; requires numpy only."""
from pathlib import Path
import argparse
import json
import wave
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output',type=Path,default=ROOT/'artifacts/demo_20261004/audio/pcm_validation.json')
parser.add_argument('--compare-historical',action='store_true',help='Also create the old v44 before/after review if its original backups exist.')
args=parser.parse_args()
REPORT=args.output.parent
REPORT.mkdir(parents=True,exist_ok=True)
SR=44100

def read(path):
    with wave.open(str(path),'rb') as f:
        meta={'sample_rate':f.getframerate(),'channels':f.getnchannels(),'sample_width':f.getsampwidth(),'frames':f.getnframes()}
        pcm=np.frombuffer(f.readframes(f.getnframes()),dtype='<i2').astype(float)/32768
    return meta,pcm

results={};failures=[]
asset_paths=list((ROOT/'assets/audio').glob('*.wav'))
for directory in ['music','radio']:asset_paths.extend((ROOT/'assets/audio'/directory).glob('*.wav'))
for path in sorted(asset_paths):
    m,x=read(path)
    f=np.fft.rfftfreq(len(x),1/m['sample_rate']);power=abs(np.fft.rfft(x))**2
    peak=float(np.max(abs(x)))
    stats={**m,'duration_s':round(len(x)/m['sample_rate'],4),
           'peak_dbfs':round(20*np.log10(peak),3),'rms_dbfs':round(20*np.log10(np.sqrt(np.mean(x*x))),3),
           'clipped_samples':int(np.count_nonzero(abs(x)>=32767/32768)),
           'dc_offset':round(float(np.mean(x)),7),
           'energy_above_4khz_percent':round(float(np.sum(power[f>=4000])/np.sum(power)*100),4)}
    if m['sample_rate'] not in [22050,44100] or m['channels']!=1 or m['sample_width']!=2:failures.append(path.name+': invalid PCM format')
    if peak>.79 or stats['clipped_samples']:failures.append(path.name+': insufficient headroom')
    if abs(stats['dc_offset'])>.001:failures.append(path.name+': DC offset')
    if '_loop' in path.stem or path.parent.name=='music':
        wrap=abs(x[0]-x[-1]);steps=abs(np.diff(x))
        stats['wrap_step']=round(float(wrap),6)
        stats['ordinary_step_p99']=round(float(np.quantile(steps,.99)),6)
        if wrap>np.quantile(steps,.99):failures.append(path.name+': loop boundary discontinuity')
    elif x[0]!=0 or x[-1]!=0:failures.append(path.name+': missing edge fade')
    results[str(path.relative_to(ROOT/'assets/audio'))]=stats
reviews={}
for path in sorted(REPORT.glob('*audition.wav')):
    m,x=read(path);reviews[path.name]={'peak_dbfs':round(float(20*np.log10(max(np.max(abs(x)),1e-12))),3),'duration_s':round(len(x)/SR,3),'clipped_samples':int(np.count_nonzero(abs(x)>=32767/32768))}
    if reviews[path.name]['clipped_samples']:failures.append(path.name+': review clipped')
# Direct before/after at original runtime gains. Old assets are resampled only
# for this review; source backups remain byte-for-byte intact.
if args.compare_historical:
    sequence=[]
    for old,new in [('fire','fire_cannon_1'),('impact','impact_medium_1'),('build','build'),('select','select')]:
        m,x=read(ROOT/'artifacts/visual_iteration/v44_reference_rebuild/audio_before/assets/audio'/f'{old}.wav')
        resampled=np.interp(np.arange(round(len(x)*SR/m['sample_rate']))*m['sample_rate']/SR,np.arange(len(x)),x)
        sequence.extend([resampled*10**(-19/20),np.zeros(round(.45*SR))])
        _,x=read(ROOT/'assets/audio'/f'{new}.wav')
        sequence.extend([x*10**((-16 if old in ('fire','impact') else -19 if old=='build' else -21)/20),np.zeros(round(.8*SR))])
    comparison=np.concatenate(sequence)
    with wave.open(str(REPORT/'before_after.wav'),'wb') as f:
        f.setnchannels(1);f.setsampwidth(2);f.setframerate(SR);f.writeframes(np.round(comparison*32767).astype('<i2').tobytes())
report={'status':'PASS' if not failures else 'FAIL','asset_count':len(results),'failures':failures,'assets':results,'review_mixes':reviews}
args.output.write_text(json.dumps(report,indent=2)+'\n')
print(f'{report["status"]}: {len(results)} PCM files; no clipping, valid format, headroom, edge fades and seamless loop boundary checks.')
for failure in failures:print(failure)
raise SystemExit(bool(failures))
