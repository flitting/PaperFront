#!/usr/bin/env python3
"""Run the current revision acceptance checks with isolated player settings."""
import argparse, json, os, pathlib, re, subprocess, sys, time, hashlib
root=pathlib.Path(__file__).resolve().parents[1]
out=root/'artifacts/rts_revision_latest/final_checks'
out.mkdir(parents=True,exist_ok=True)
cases=[
 ('latest_rules_gameplay_tests',[]),('latest_appearance_revision_tests',[]),
 ('architecture_revision_tests',[]),('architecture_identity_tests',[]),
 ('rts_model_revision_tests',[]),('building_door_revision_tests',[]),
 ('rts_render_integration_tests',[]),('creator_hand_owner_colors_tests',[]),
 ('heavy_crushing_tests',[]),('refinery_frontdoor_tests',[]),('refinery_queue_tests',[]),('player_palette_debug_window_tests',[]),
 ('zeppelin_weapons_tests',[]),('rts_ui_revision_tests',[]),('repair_depot_input_tests',[]),
 ('rts_mechanics_revision_tests',[]),('rts_start_footprint_tests',[]),('rail_network_tests',[]),
 ('navigation_classification_revision_tests',[]),
 ('rts_navigation_geometry_tests',[]),
 ('native_unit_tick_tests',['--','--threaded-tick-equivalence']),
 ('path_geometry_invalidation_tests',[]),
 ('air_navigation_tests',[]),('rts_command_information_tests',[]),
 ('commander_event_audio_tests',[]),('voice_profile_routing_tests',[]),
 ('combat_audio_v8_tests',[]),('skirmish_setup_tests',[]),
 ('wiki_catalog_tests',[]),('naval_integration_tests',[]),
]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--only',action='append',choices=[name for name,_ in cases],help='Run a selected case (repeatable).')
args_cli=parser.parse_args()
if args_cli.only: cases=[case for case in cases if case[0] in args_cli.only]
def source_hashes():
 hashes={}
 for folder in ['scripts','native/src','data','tests']:
  for path in sorted((root/folder).glob('*')):
   if path.is_file() and path.suffix in ['.gd','.json','.hpp','.cpp']:
    hashes[str(path.relative_to(root))]=hashlib.sha256(path.read_bytes()).hexdigest()
 for path in [root/'tools/test_rts_revision.py',*sorted((root/'assets/native').glob('*.so'))]:
  if path.is_file(): hashes[str(path.relative_to(root))]=hashlib.sha256(path.read_bytes()).hexdigest()
 return hashes
before=source_hashes()
results=[]
for name,args in cases:
 env=os.environ.copy();env['XDG_DATA_HOME']='/tmp/paper-front-rts-final-data/'+name;env['XDG_CONFIG_HOME']='/tmp/paper-front-rts-final-config/'+name
 start=time.monotonic()
 cmd=[os.environ.get('PAPER_FRONT_GODOT','godot'),'--headless','--path',str(root),'--script','res://tests/'+name+'.gd',*args]
 try:
  proc=subprocess.run(cmd,cwd=root,env=env,capture_output=True,text=True,timeout=150)
  log=proc.stdout+proc.stderr;code=proc.returncode
 except subprocess.TimeoutExpired as exc:
  log=(exc.stdout or b'').decode()+(exc.stderr or b'').decode();code=124
 (out/(name+'.log')).write_text(log)
 bad=bool(re.search(r'SCRIPT ERROR:|^ERROR:|ObjectDB instances leaked|resources still in use at exit|RID(?:s)? of type .*leaked',log,re.M))
 assertions=None
 for line in log.splitlines():
  if '{' not in line: continue
  try:
   payload=json.loads(line[line.index('{'):])
   if isinstance(payload,dict) and isinstance(payload.get('checks'),(int,float)): assertions=int(payload['checks'])
  except (ValueError,TypeError): pass
 if assertions is None:
  count=re.search(r'(\d+) checks|checks:\s*(\d+) passed',log,re.I)
  if count: assertions=int(count.group(1) or count.group(2))
 result=dict(test=name,exit_code=code,engine_error=bad,passed=code==0 and not bad,seconds=round(time.monotonic()-start,3),checks=assertions)
 results.append(result); print(json.dumps(result),flush=True)
 after=source_hashes()
 manifest=dict(scope='Latest infantry rollback, 1/2-cell footprints, three-color livery, T0–T3, architecture, active repair, dual-weapon Zeppelin and selected regressions. Separate live four-faction and 600-second AI reports are not duplicated here. Not the entire historical test suite.',tests=results,passed=all(x['passed'] for x in results),sources_unchanged_during_run=before==after,checks_source_sha256=after,total_checks=sum(x['checks'] or 0 for x in results))
 (out/'summary.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
sys.exit(0 if all(x['passed'] for x in results) and before==source_hashes() else 1)
