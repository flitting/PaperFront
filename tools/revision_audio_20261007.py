#!/usr/bin/env python3
"""Selective, cached 2026-10-07 audio revision; never remakes the whole death bank.

All paid speech/SFX jobs use the shared OpenRouter insufficient-credit pause.
The nine interface cues are new deterministic original DSP (CC0-1.0).
Inactive emotion experiments live only in artifacts, outside runtime manifests.
"""
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import argparse, hashlib, json, wave
import numpy as np
import generate_revision_v8_audio as a
from revision_v8_dialogue import FIXED_SPEAKERS, VOICE_MODELS, specifications

REPORT=a.ROOT/'artifacts/audio_revision_20261007'
NEW_PROFILES=['rivet/infantry','rivet/air','iron/infantry','iron/vehicle','sky/vehicle','sky/air']
WORD_FIXES=['kestrel/infantry/select/1','kestrel/infantry/ready/3','rivet/vehicle/select/1','rivet/vehicle/move/3']
UI_NAMES=['select','command','produce','delivery','sell','low_power','result','error','ui_click']
NEW_FX={
 'fire_energy':(.8,'One original advanced energy weapon pulse launch: compact electrical pressure snap, coherent rising resonant plasma tone, charged capacitor discharge and a clean airy ion trail. Futuristic but tactile, no gunpowder cannon, no bullet crack, no beeps or melody.'),
 'impact_energy':(1.25,'One coherent energy pulse striking a solid surface: dense electrical snap, a soft deep charged pressure wave, crackling ion filaments diffusing outward with an airy luminous tail. No conventional explosive shell, no rock debris, no music.'),
 'creator_hand_attack':(.95,'One enormous supernatural living hand slaps downward: weighty palm pressure thump, broad low air displacement, soft skin contact and strange deep energy resonance spreading. Powerful grounded tactile impact, no cannon, no mechanical gun or voice.'),
 'creator_hand_impact':(1.5,'One giant mystical palm strike hits earth: broad deep compact ground shock, papery surface crumple, a rippling alien resonant energy wave dispersing into a low soft tail. No conventional shell explosion, no gunshot, no voices or music.'),
}

def read_wav(path):
 with wave.open(str(path)) as w:return np.frombuffer(w.readframes(w.getnframes()),dtype='<i2').astype(float)/32768,w.getframerate()

def profile_table():
 return {k:{'voice':v[0],'speaker_identity':v[0],'speaker_id':v[0]+f'@tempo={v[2]:.3f}', 'speaker_gender':v[1],'tempo':v[2],'model':VOICE_MODELS.get(k,a.TTS_MODEL),'request_strategy':'One fixed managed actor for all actions; no pitch shift or per-action actor prompt'} for k,v in FIXED_SPEAKERS.items()}

def voices(profiles,keys):
 manifest=json.loads((a.OUT/'radio/manifest.json').read_text());bank={c['key']:c for c in manifest['clips']}
 jobs=[s for s in specifications() if s['faction']+'/'+s['category'] in profiles or s['key'] in keys]
 failures=[];generated=[]
 with ThreadPoolExecutor(max_workers=4) as pool:
  futures={pool.submit(a.voice_job,s):s for s in jobs}
  for i,future in enumerate(as_completed(futures),1):
   try:
    c=future.result();bank[c['key']]=c;generated.append(c);print('voice',i,len(jobs),c['key'],flush=True)
   except Exception as e:failures.append(a.safe_message(str(e)));print('FAIL',type(e).__name__,a.safe_message(e),flush=True)
 if failures:raise RuntimeError('Incomplete selective bank; '+str(failures[:3]))
 manifest.update(version=11,profiles=profile_table(),license='Provider-generated output under OpenRouter and the respective Microsoft/xAI/Alibaba service terms; no CC0 claim.',speech_notice='Twelve different managed base actors across Microsoft MAI, xAI Grok and Alibaba Qwen; fixed actor across every action, no human recording or clone.',clips=sorted(bank.values(),key=lambda x:x['key']))
 a.write_json(a.OUT/'radio/manifest.json',manifest);a.write_json(REPORT/'changed_voice_records.json',{'count':len(generated),'records':generated})

def ui_effect(name):
 rate=a.SR_SFX;durations={'select':.14,'command':.17,'produce':.42,'delivery':.36,'sell':.85,'low_power':.4,'result':.55,'error':.21,'ui_click':.12}
 duration=durations[name];t=np.arange(round(rate*duration))/rate;rng=np.random.default_rng(120710+UI_NAMES.index(name));freq=np.fft.rfftfreq(len(t),1/rate)
 noise=np.fft.irfft(np.fft.rfft(rng.standard_normal(len(t)))*np.exp(-(freq/2200)**4),len(t));noise/=max(np.sqrt(np.mean(noise**2)),1e-9)
 x=np.zeros_like(t)
 def tap(delay,pitch,strength,decay=.017):
  nonlocal x
  tt=np.maximum(0,t-delay);env=np.where(t>=delay,(1-np.exp(-tt/.0008))*np.exp(-tt/decay),0)
  x+=strength*(.55*noise+.45*np.sin(2*np.pi*pitch*tt)+.17*np.sin(2*np.pi*pitch*2.7*tt))*env
 def fold(start,length,strength):
  nonlocal x
  tt=t-start;env=np.where((tt>=0)&(tt<length),np.sin(np.pi*np.clip(tt/length,0,1))**2,0)
  x+=strength*(noise*.65+np.sin(2*np.pi*(72*t+18*t*t))*.35)*env*(.8+.2*np.sin(2*np.pi*38*t))
 if name=='select':tap(0,230,.7);tap(.065,360,.23)
 elif name=='command':tap(0,190,.7);fold(.015,.10,.12)
 elif name=='ui_click':tap(0,155,.65);fold(.01,.07,.20)
 elif name=='produce':fold(0,.26,.24);tap(.05,130,.3);tap(.26,220,.7);tap(.32,410,.22)
 elif name=='delivery':fold(0,.26,.22);tap(.10,145,.5);tap(.21,220,.35)
 elif name=='sell':
  fold(.02,.6,.36)
  for delay,pitch in [(.025,150),(.22,120),(.48,105),(.68,90)]:tap(delay,pitch,.4,.028)
 elif name=='low_power':tap(0,100,.7,.035);tap(.14,80,.45,.035);fold(.02,.25,.1)
 elif name=='result':tap(0,180,.4,.065);tap(.10,270,.45,.07);tap(.21,360,.24,.07);fold(.03,.38,.1)
 elif name=='error':tap(0,100,.65);tap(.08,82,.5);fold(.02,.1,.08)
 path=a.OUT/'sfx'/(name+'.wav');a.write_wav(path,a.master(x,rate,.42 if name!='sell' else .52),rate)
 return {'family':name,'kind':name,'variant':1,'loop':False,**a.wav_record(path),'provenance':{'type':'original_dsp','provider':'Local original mechanical paper interface cue','source':'tools/revision_audio_20261007.py','license':'CC0-1.0','seed':120710+UI_NAMES.index(name),'design':'Layered paper friction, damped mechanical key/panel contact; no reused legacy beep.'}}

def effects():
 manifest=json.loads((a.OUT/'sfx/manifest.json').read_text());bank={(c['family'],c['variant']):c for c in manifest['effects']};before=[]
 for key,c in bank.items():
  if c['family'] in UI_NAMES or c['family'] in ['ui_key','select_power']:continue
  if c.get('level_revision',{}).get('id')=='20261007-combat-minus20':continue
  path=a.ROOT/c['file'][6:];x,rate=read_wav(path);old_hash=c['sha256'];before.append({'family':c['family'],'variant':c['variant'],'before_rms':float(np.sqrt(np.mean(x*x)))})
  backup=REPORT/'sfx_before'/path.name;backup.parent.mkdir(parents=True,exist_ok=True)
  if not backup.exists():backup.write_bytes(path.read_bytes())
  a.write_wav(path,x*.8,rate);c.update(a.wav_record(path));c['level_revision']={'id':'20261007-combat-minus20','linear_gain':.8,'source_sha256':old_hash,'runtime_baseline':.765,'effective_relative_to_old_default':.8}
 for name in UI_NAMES:bank[(name,1)]=ui_effect(name)
 jobs=[(family,v,duration,brief) for family,(duration,brief) in NEW_FX.items() for v in range(1,4)]
 with ThreadPoolExecutor(max_workers=4) as pool:
  futures={pool.submit(a.sfx_job,j):j for j in jobs}
  for future in as_completed(futures):
   c=future.result();path=a.ROOT/c['file'][6:];x,rate=read_wav(path);a.write_wav(path,x*.8,rate);c.update(a.wav_record(path));c['level_revision']={'id':'20261007-combat-minus20','linear_gain':.8,'runtime_baseline':.765};bank[(c['family'],c['variant'])]=c;print('sfx',c['family'],c['variant'],flush=True)
 manifest.update(version=11,effects=sorted(bank.values(),key=lambda x:(x['family'],x['variant'])));a.write_json(a.OUT/'sfx/manifest.json',manifest);a.write_json(REPORT/'sfx_mastering.json',{'runtime_baseline':.765,'old_source_gain':.8,'new_interface_count':9,'effects':before,'count':len(bank)})

def emotion():
 # These are documented xAI inline delivery controls, not invented SSML.
 # Never writes into the active radio folder or manifest.
 configs=[('neutral','啊！救我！'),('urgent','<loud><fast>[breath]啊！救我！</fast></loud>'),('neutral_air','Mayday！拉起！'),('urgent_air','<loud>[breath]Mayday！<emphasis>拉起！</emphasis></loud>')];records=[]
 for name,text in configs:
  voice='rex' if 'air' in name else 'leo';payload={'model':'x-ai/grok-voice-tts-1.0','input':text,'voice':voice,'response_format':'pcm','provider':{'options':{'xai':{'language':'zh'}}}}
  raw,meta=a.request_pcm('emotion_20261007_'+name,payload);path=REPORT/'emotion'/f'{name}.wav';a.write_wav(path,a.prepare_raw(raw,meta,a.SR_VOICE,True)*.8,a.SR_VOICE)
  records.append({'name':name,'active':False,'method':'xAI documented inline breath/loud/fast/emphasis tags' if name.startswith('urgent') else 'sameactor plain text control','voice':voice,'payload':payload,**a.wav_record(path),'raw':meta})
 a.write_json(REPORT/'emotion/manifest.json',{'purpose':'Independent 4sample emotion comparison, NOT active bank','records':records})

if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--resume-paid',action='store_true',help='Only after explicit user recharge confirmation');parser.add_argument('--voices',action='store_true');parser.add_argument('--effects',action='store_true');parser.add_argument('--emotion',action='store_true');parser.add_argument('--profiles',nargs='*',default=NEW_PROFILES);parser.add_argument('--keys',nargs='*',default=WORD_FIXES);args=parser.parse_args();REPORT.mkdir(parents=True,exist_ok=True)
 if args.resume_paid and a.PAUSE.exists():a.PAUSE.unlink();a.STOP_PAID.clear()
 if args.voices:voices(args.profiles,args.keys)
 if args.effects:effects()
 if args.emotion:emotion()
