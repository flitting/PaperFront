#!/usr/bin/env python3
"""Apply the requested gain edits to existing active music, without generation.

Idempotent revision marker plus retained before hashes identify actual PCM edits.
The original composer's generator remains the source of the unadjusted baseline.
"""
import hashlib,json,wave
from pathlib import Path
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
REVISION='v10-menu-minus5-calm-plus3-battle-minus3'
REPORT=ROOT/'artifacts/revision_v8_audio/level_revision_v10'

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def write_json(path,data):path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')

def main():
    REPORT.mkdir(parents=True,exist_ok=True);records=[]
    for manifest_path in [ROOT/'assets/audio/music/manifest.json',ROOT/'assets/audio/revision_v8/music/manifest.json']:
        manifest=json.load(open(manifest_path))
        for track in manifest['tracks']:
            name=track.get('id',track.get('scene',''))
            new=manifest_path.parent.name=='music' and 'revision_v8' in manifest_path.as_posix()
            gain=-5.0 if new and name=='menu' else -3.0 if name in ['battle_engaged','battle_intense'] else 3.0 if not new and (name=='battle' or name.startswith('battle_')) else 0.0
            if gain==0 or track.get('level_revision',{}).get('id')==REVISION:continue
            path=ROOT/track.get('file',track.get('path'))[6:];before=digest(path)
            backup=REPORT/(('new_' if new else 'map_')+path.name)
            if not backup.exists():backup.write_bytes(path.read_bytes())
            with wave.open(str(path)) as wav:
                rate=wav.getframerate();channels=wav.getnchannels();width=wav.getsampwidth();data=np.frombuffer(wav.readframes(wav.getnframes()),dtype='<i2').astype(float)/32768
            if channels!=1 or width!=2:raise RuntimeError('Unexpected music PCM format')
            out=np.rint(data*(10**(gain/20))*32768).astype('<i2')
            peak=float(np.max(np.abs(data*10**(gain/20))))
            if peak>.79:raise RuntimeError('Requested gain exceeds source headroom')
            with wave.open(str(path),'wb') as wav:
                wav.setnchannels(1);wav.setsampwidth(2);wav.setframerate(rate);wav.writeframes(out.tobytes())
            signal=out.astype(float)/32768
            track['sha256']=digest(path);track['duration_s']=round(len(out)/rate,6)
            track['peak_dbfs']=round(20*np.log10(max(float(np.max(abs(signal))),1e-12)),4)
            track['rms_dbfs']=round(20*np.log10(max(float(np.sqrt(np.mean(signal**2))),1e-12)),4)
            track['level_revision']={'id':REVISION,'gain_db':gain,'source_sha256':before,'tool':'tools/rebalance_audio_v10.py','tool_sha256':digest(Path(__file__))}
            records.append({'id':name,'file':'res://'+path.relative_to(ROOT).as_posix(),'gain_db':gain,'before_sha256':before,'after_sha256':track['sha256'],'peak':peak,'wrap_step':float(abs(signal[0]-signal[-1]))})
        manifest.setdefault('post_processing',{})['level_revision']=REVISION
        write_json(manifest_path,manifest)
    write_json(REPORT/'validation.json',{'status':'PASS','edited_existing_tracks':len(records),'new_music_generation':False,'records':records})
    print('PASS existing music gain edits',len(records),'tracks; no new generation')

if __name__=='__main__':main()
