#!/usr/bin/env python3
"""Run the current revision acceptance checks with isolated player settings."""
import argparse, json, os, pathlib, re, subprocess, sys, time, hashlib
root=pathlib.Path(__file__).resolve().parents[1]
out=root/'artifacts/rts_revision_v3_20261007/final_checks'
out.mkdir(parents=True,exist_ok=True)
cases=[('rts_v3_visual_tests', []), ('rts_v3_palette_tests', []), ('wiki_ui_tests', []), ('infantry_garrison_v3_tests', []), ('veterancy_v3_tests', []), ('carrier_veterancy_v3_tests', []), ('v3_air_naval_tests', []), ('amphibious_factory_v3_tests', []), ('v3_naval_ai_tests', []), ('iron_engineer_v3_tests', []), ('v3_commands_input_tests', []), ('armor_combat_revision_tests', []), ('refinery_frontdoor_tests', []), ('refinery_queue_tests', []), ('air_navigation_tests', []), ('air_navigation_stall_tests', []), ('naval_integration_tests', []), ('native_unit_tick_tests', ['--', '--threaded-tick-equivalence']), ('native_world_sync_tests', []), ('wiki_catalog_tests', []), ('rts_four_faction_regression', [])]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--only',action='append',choices=[name for name,_ in cases],help='Run a selected case (repeatable).')
args_cli=parser.parse_args()
if args_cli.only: cases=[case for case in cases if case[0] in args_cli.only]
def source_hashes():
 hashes={}
 for folder in ['scripts','native/src','data']:
  for path in sorted((root/folder).glob('*')):
   if path.is_file() and path.suffix in ['.gd','.json','.hpp','.cpp']:
    hashes[str(path.relative_to(root))]=hashlib.sha256(path.read_bytes()).hexdigest()
 test_paths={root/'tests'/ (name+'.gd') for name,_ in cases}
 test_paths.add(root/'tests/rule_test_simulation.gd')
 pending=list(test_paths)
 while pending:
  candidate=pending.pop()
  if not candidate.exists(): continue
  for dep in re.findall(r'res://(tests/[^\"\s]+\.gd)',candidate.read_text()):
   path=root/dep
   if path not in test_paths: test_paths.add(path);pending.append(path)
 for path in sorted(test_paths):
  if path.is_file():hashes[str(path.relative_to(root))]=hashlib.sha256(path.read_bytes()).hexdigest()
 for path in [root/'tools/test_rts_revision_v3.py',*sorted((root/'assets/native').glob('*.so'))]:
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
  count=re.search(r'(\d+) checks|checks[:=]\s*(\d+)|(?:PATH_GEOMETRY_INVALIDATION)\s+(\d+)/\3',log,re.I)
  if count: assertions=int(next(v for v in count.groups() if v is not None))
 result=dict(test=name,exit_code=code,engine_error=bad,passed=code==0 and not bad,seconds=round(time.monotonic()-start,3),checks=assertions)
 results.append(result); print(json.dumps(result),flush=True)
 after=source_hashes()
 manifest=dict(scope='V3 player livery, enlarged train/zeppelin, miner return commands, expanded infantry/garrison/veterancy/air/naval and related regressions. Includes coexisting navigation edits in the shared frozen working tree. Separate live four-faction and 600-second AI reports are not duplicated here. Not the entire historical test suite.',tests=results,passed=all(x['passed'] for x in results),sources_unchanged_during_run=before==after,checks_source_sha256=after,total_checks=sum(x['checks'] or 0 for x in results))
 (out/'summary.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
sys.exit(0 if all(x['passed'] for x in results) and before==source_hashes() else 1)
