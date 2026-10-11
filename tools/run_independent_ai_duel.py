#!/usr/bin/env python3
"""Freeze two strategies and referee a same-faction, side-swapped round."""
from __future__ import annotations
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import shutil
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]

def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def engine_hashes() -> dict[str, str]:
    files = sorted((ROOT / 'scripts').glob('*.gd')) + [ROOT / relative for relative in ['data/rules.json','headless.tscn','project.godot','assets/native/paper_front_kernels.gdextension','assets/native/libpaper_front_kernels.so']]
    return {str(p.relative_to(ROOT)): digest(p) for p in files}

def strategy_signature(item: dict) -> tuple[str,str]:
    # Recorders receive copies and cannot affect strategy/game state.
    return item['sha256'],''


def evaluate_league(rounds: list[dict]) -> dict:
    current = {name:strategy_signature(rounds[-1]['strategies'][name]) for name in ('alpha','beta')} if rounds else {}
    decisive = [game for item in rounds for game in item['games']
                if {name:strategy_signature(item['strategies'][name]) for name in ('alpha','beta')}==current
                and all(g['status']=='completed' for g in item['games'])
                and game['status']=='completed' and game.get('winner') in ('alpha','beta')]
    current_games=[game for item in rounds if {name:strategy_signature(item['strategies'][name]) for name in ('alpha','beta')}==current for game in item['games']]
    actual=[game for game in current_games if game['status']=='completed' and game.get('winner') in ('alpha','beta')]
    recent = decisive[-4:]
    wins = {name:sum(game['winner']==name for game in recent) for name in ('alpha','beta')}
    near = len(recent)==4 and all(0.4<=wins[name]/4<=0.6 for name in wins)
    chain = 0
    incumbent = None
    anchor = None
    previous = None
    for current_round in rounds:
        winner = current_round.get('winner')
        if all(game['status']=='completed' for game in current_round['games']) and current_round['score']['alpha']==current_round['score']['beta'] and current_round['score']['alpha']>0:
            chain=0
            previous=current_round
            continue
        if winner and (winner!=incumbent or current_round['strategies'][winner]['sha256']!=anchor):
            incumbent=winner
            anchor=current_round['strategies'][winner]['sha256']
            chain=0
        elif incumbent and previous:
            challenger='beta' if incumbent=='alpha' else 'alpha'
            unchanged=current_round['strategies'][incumbent]['sha256']==anchor
            revised=previous['strategies'][challenger]['sha256']!=current_round['strategies'][challenger]['sha256']
            allowed=all(game['status'] in ('completed','unfinished') for game in current_round['games'])
            unresolved=sum(game['status']=='unfinished' for game in current_round['games'])
            cannot_win=current_round['score'][challenger]+unresolved<=current_round['score'][incumbent]
            if unchanged and revised and allowed:
                chain=chain+1 if cannot_win else 0
            elif not unchanged:chain=0
        previous=current_round
    return {'stop':near or chain>=4,
            'reason':'near_50_percent' if near else ('four_unsuccessful_revisions' if chain>=4 else 'continue'),
            'decisive_games':len(decisive),'recent_four_wins':wins,
            'consecutive_unsuccessful_revisions':chain,'incumbent':incumbent,
            'completed_games_current_pair':len(actual),
            'unfinished_games_current_pair':sum(game['status']=='unfinished' for game in current_games),
            'current_pair_known_wins':{name:sum(game['winner']==name for game in actual) for name in ('alpha','beta')}}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--alpha', type=Path, default=ROOT / 'ai/duel/alpha.gd')
    parser.add_argument('--beta', type=Path, default=ROOT / 'ai/duel/beta.gd')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--faction', choices=['kestrel','rivet','iron','sky'], default='kestrel')
    parser.add_argument('--seed', type=int, default=733)
    parser.add_argument('--duration', type=float, default=1200)
    parser.add_argument('--godot', default='godot')
    args = parser.parse_args()
    directory = args.output.resolve()
    if directory.exists():
        raise SystemExit('Round directory already exists; preserve immutable evidence and choose a new directory')
    directory.mkdir(parents=True)
    before = engine_hashes()
    frozen = {}
    for name, source in [('alpha',args.alpha.resolve()),('beta',args.beta.resolve())]:
        destination = directory / f'{name}.gd'
        shutil.copy2(source,destination)
        frozen[name] = {'source':str(source),'path':str(destination),'sha256':digest(destination)}
        recorder = source.with_name(source.stem+'_recorder.gd')
        if recorder.exists():
            recorder_copy = directory / f'{name}_recorder.gd'
            shutil.copy2(recorder,recorder_copy)
            frozen[name]['recorder'] = {'source':str(recorder),'path':str(recorder_copy),'sha256':digest(recorder_copy)}
    engine_source = directory / 'engine_source'
    for relative in before:
        target = engine_source / relative
        target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(ROOT / relative,target)
    manifest = {'schema':'paper_front.independent_ai_round','schema_version':1,
        'faction':args.faction,'seeds':[args.seed,args.seed+1],'duration_limit':args.duration,
        'dt':1/30,'strategies':frozen,'engine_sha256':before,
        'rules_sha256':before['data/rules.json'],
        'policy':'Four games: two seeds, each with sides swapped. Only a proven round loser or incumbent challenger mathematically unable to win the round may revise. Unfinished games never count as losses; errors invalidate adjudication.'}
    (directory / 'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    def play(game_config: tuple[str,int]) -> dict:
        side, seed = game_config
        prefix = directory / f'seed{seed}_{side}'
        modules = ','.join(frozen[name]['path'] for name in ['alpha','beta'])
        cmd = [args.godot,'--headless','--audio-driver','Dummy','--path',str(ROOT),
            'res://headless.tscn','--','--map','symmetric','--seed',str(seed),
            '--factions',f'{args.faction},{args.faction}','--ai','both',
            '--ai-modules',modules,'--difficulty','normal','--starts',side,
            '--duration',str(args.duration),'--dt','0.03333333333333333',
            '--output',str(prefix),'--save-final',str(prefix)+'.pfront']
        began = time.monotonic()
        with prefix.with_suffix('.log').open('w') as log:
            try:
                result = subprocess.run(cmd,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,timeout=max(900,args.duration*3))
                code = result.returncode
            except subprocess.TimeoutExpired:
                code = -1
        report_path = prefix.with_suffix('.json')
        row = {'starts':side,'seed':seed,'exit_code':code,'wall_seconds':time.monotonic()-began,'report':str(report_path),'command':cmd}
        if not report_path.exists():
            row.update(status='failed',winner=None)
            return row
        report = json.loads(report_path.read_text())
        headless = report.get('headless',{})
        engine_errors = bool(re.search(r'SCRIPT ERROR:|^ERROR:|HEADLESS_ERROR ', prefix.with_suffix('.log').read_text(), re.M))
        valid = code==0 and not engine_errors and not headless.get('error') and not headless.get('independent_ai',{}).get('error')
        winners = report.get('winner_teams',[])
        completed = bool(report.get('finished')) and bool(report.get('winner_teams_known'))
        row.update(status='completed' if valid and completed else ('unfinished' if valid else 'failed'),
            duration=report.get('duration'),result=report.get('result'),winner=None,
            teams=report.get('teams',[]))
        identities = headless.get('independent_ai',{}).get('identities',[])
        by_team = {item['team']:Path(item['path']).stem for item in identities}
        if row['status']=='completed' and len(winners)==1:
            row['winner'] = by_team.get(winners[0])
        row['slot_strategies'] = by_team
        decisions = headless.get('independent_ai',{}).get('teams',[])
        prefix.with_name(prefix.name+'_decisions.json').write_text(json.dumps(decisions,ensure_ascii=False,indent=2)+'\n')
        for team, name in by_team.items():
            review = {key:value for key,value in report.items() if key!='headless'}
            review['review'] = {'strategy':name,'team':team,'starts':side,'status':row['status'],
                'winner':row['winner'],'source_sha256':frozen[name]['sha256'],
                'own_decisions':next((item for item in decisions if item['team']==team),{})}
            prefix.with_name(prefix.name+'_'+name+'_review.json').write_text(json.dumps(review,ensure_ascii=False,indent=2)+'\n')
        return row
    with ThreadPoolExecutor(max_workers=4) as pool:
        games = list(pool.map(play,[(side,seed) for seed in (args.seed,args.seed+1) for side in ('default','swap')]))
    after = engine_hashes()
    unchanged = before==after and all(digest(Path(item['path']))==item['sha256'] and ('recorder' not in item or digest(Path(item['recorder']['path']))==item['recorder']['sha256']) for item in frozen.values())
    score = {name:sum(game['winner']==name for game in games) for name in frozen}
    eligible = unchanged and all(game['status']=='completed' for game in games)
    winner = max(score,key=score.get) if eligible and score['alpha']!=score['beta'] else None
    loser = ('beta' if winner=='alpha' else 'alpha') if winner else None
    summary = {**manifest,'engine_source_unchanged':unchanged,'games':games,'score':score,'winner':winner,'loser':loser,
        'instruction':'Only '+loser+' may revise from this round; winner source must remain identical.' if loser else 'No unique round loser; both strategies remain frozen.'}
    (directory / 'round.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'round':str(directory),'score':score,'winner':winner,'loser':loser,'engine_source_unchanged':unchanged,'statuses':[game['status'] for game in games]},ensure_ascii=False),flush=True)
    return 0 if unchanged and all(game['status']!='failed' for game in games) else 1

if __name__=='__main__':
    raise SystemExit(main())
