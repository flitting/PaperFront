#!/usr/bin/env python3
"""Regenerate individually verified speech outliers with the same managed speaker.
Uses cached paid requests; credit pause follows the main generator's protocol.
"""
import json, re, hashlib, base64, urllib.request, urllib.error, os, time
from pathlib import Path
import generate_revision_v8_audio as audio
from revision_v8_dialogue import PROFILES, specifications
REPAIRS = {
 'iron/air/move/3':'检查完成，前往目标。',
 'kestrel/vehicle/under_attack/2':'敌方来袭，请求掩护。',
 'rivet/infantry/attack/1':'压住目标，开火。',
 'rivet/infantry/attack/3':'目标在前，全力开火。',
 'rivet/infantry/move/1':'迈开步子，跟上。',
 'rivet/infantry/combat/3':'守住阵线，顶住。',
 'rivet/infantry/return/1':'兄弟们，回去检修。',
 'rivet/infantry/select/1':'突击队就位，听候命令。',
 'rivet/infantry/under_attack/1':'敌人开火了，找掩护。',
 'sky/air/attack/3':'进入航线，精准投射。',
}

def transcribe(path):
 if audio.PAUSE.exists():raise audio.CreditPause('Awaiting explicit user recharge')
 payload={'model':'microsoft/mai-transcribe-2','input_audio':{'data':base64.b64encode(path.read_bytes()).decode(),'format':'wav'},'language':'zh','response_format':'json'}
 req=urllib.request.Request('https://openrouter.ai/api/v1/audio/transcriptions',data=json.dumps(payload).encode(),headers={'Authorization':'Bearer '+os.environ['OPENROUTER_API_KEY'],'Content-Type':'application/json'},method='POST')
 for attempt in range(6):
  try:
   with urllib.request.urlopen(req,timeout=60) as result:return json.load(result)
  except urllib.error.HTTPError as error:
   msg=audio.safe_message(json.loads(error.read()).get('error',{}).get('message',''))
   if error.code==402:audio.pause_credit(402,msg)
   if error.code==429 and attempt<5:time.sleep(min(30,3*2**attempt));continue
   raise RuntimeError(f'ASR HTTP {error.code}: {msg[:120]}') from None

def words(text):return re.sub(r'[^\u4e00-\u9fffA-Za-z0-9]','',text)

def main():
 manifest_path=audio.OUT/'radio/manifest.json'
 manifest=json.loads(manifest_path.read_text())
 records={clip['key']:clip for clip in manifest['clips']}
 original_request=audio.request_pcm
 report=[]
 for key,text in REPAIRS.items():
  faction,category,action,variant=key.split('/')
  PROFILES[faction+'/'+category][2][action][int(variant)-1]=text
  spec=next(s for s in specifications() if s['key']==key)
  previous=records[key]
  accepted=False
  for attempt in range(1,4):
   audio.request_pcm=lambda name,payload:original_request(f'repair_v9_{attempt}_'+name,payload)
   row=audio.voice_job(spec)
   path=audio.ROOT/row['file'][6:]
   result=transcribe(path)
   item={'key':key,'attempt':attempt,'expected':text,'transcript':result.get('text',''),'sha256':row['sha256'],'speaker_id':row['speaker_id'],'asr_usage':result.get('usage',{}),'pass':words(text)==words(result.get('text',''))}
   report.append(item);print(json.dumps(item,ensure_ascii=False),flush=True)
   if item['pass']:
    row['provenance']['repair']='Individually checked for correct words and no outtakes; same fixed managed speaker and profile tempo.'
    row['provenance']['previous_sha256']=previous['sha256'];records[key]=row;accepted=True;break
  if not accepted:raise RuntimeError('Repair still has unintended spoken words: '+key)
  manifest['clips']=sorted(records.values(),key=lambda c:c['key']);audio.write_json(manifest_path,manifest)
 audio.request_pcm=original_request
 # Authored dialogue is the single source for all unit captions and future builds.
 source=audio.ROOT/'tools/revision_v8_dialogue.py'
 content=source.read_text()
 old=json.loads((audio.REPORT/'speaker_identity_revision/previous_bank/manifest.json').read_text())
 old_text={c['key']:c['text'] for c in old['clips']}
 for key,text in REPAIRS.items():
  if old_text.get(key)==text:continue
  # Replace exact literals within the matching profile block only.
  faction,category,_,_=key.split('/');profile=faction+'/'+category
  start=content.index("    '"+profile+"':")
  end=content.find("\n    '",start+5)
  if end<0:end=content.index('\n}',start)
  block=content[start:end].replace(repr(old_text[key]),repr(text))
  content=content[:start]+block+content[end:]
 source.write_text(content)
 rules_path=audio.ROOT/'data/rules.json';rules=json.loads(rules_path.read_text())
 for unit in rules['units'].values():
  profile=unit['faction']+'/'+unit['voice_category']
  unit['voices']={a:list(lines) for a,lines in PROFILES[profile][2].items()}
 rules_path.write_text(json.dumps(rules,ensure_ascii=False,indent=2)+'\n')
 audio.write_json(audio.REPORT/'speaker_identity_revision/confirmed_repairs.json',{'repairs':report,'limitation':'Individual ASR checks verify words; stable managed speaker configuration controls identity, with separate perceptual audit.'})
if __name__=='__main__':main()
