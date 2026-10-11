#!/usr/bin/env python3
"""Continue unfinished referee games; retain original evidence and version hashes."""
from concurrent.futures import ThreadPoolExecutor
import argparse
import json
from pathlib import Path
import re
import subprocess
import time
from run_independent_ai_duel import ROOT,engine_hashes,digest


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory',type=Path)
    parser.add_argument('--duration',type=float,default=1200)
    args=parser.parse_args()
    directory=args.directory.resolve()
    summary_path=directory/'round.json'
    summary=json.loads(summary_path.read_text())
    if engine_hashes()!=summary['engine_sha256']:raise SystemExit('Shared engine differs; cannot resume this frozen round')
    for item in summary['strategies'].values():
        if digest(Path(item['path']))!=item['sha256']:raise SystemExit('Strategy snapshot changed')
        if 'recorder' in item and digest(Path(item['recorder']['path']))!=item['recorder']['sha256']:raise SystemExit('Recorder snapshot changed')
    targets=[(index,game) for index,game in enumerate(summary['games']) if game['status']=='unfinished']
    if not targets:raise SystemExit('No unfinished games')
    iteration=1
    while (directory/f'round_before_continuation_{iteration:02}.json').exists():iteration+=1
    (directory/f'round_before_continuation_{iteration:02}.json').write_text(summary_path.read_text())
    def extend(target):
        index,game=target
        previous=Path(game['report'])
        prefix=directory/f"seed{game['seed']}_{game['starts']}_continued_{iteration:02}"
        saved=previous.with_suffix('.pfront')
        command=[game['command'][0],'--headless','--audio-driver','Dummy','--path',str(ROOT),'res://headless.tscn','--',
            '--load',str(saved),'--factions',f"{summary['faction']},{summary['faction']}",'--ai','both',
            '--duration',str(args.duration),'--dt','0.03333333333333333','--output',str(prefix),'--save-final',str(prefix)+'.pfront']
        began=time.monotonic()
        with prefix.with_suffix('.log').open('w') as log:
            process=subprocess.run(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,timeout=max(900,args.duration*3))
        report_path=prefix.with_suffix('.json')
        if not report_path.exists():raise RuntimeError('Continuation failed: '+str(prefix))
        report=json.loads(report_path.read_text());headless=report.get('headless',{})
        errors=bool(re.search(r'SCRIPT ERROR:|^ERROR:|HEADLESS_ERROR ',prefix.with_suffix('.log').read_text(),re.M))
        valid=process.returncode==0 and not errors and not headless.get('error') and not headless.get('independent_ai',{}).get('error')
        complete=bool(report.get('finished')) and bool(report.get('winner_teams_known'))
        row=dict(game)
        row.update(report=str(report_path),status='completed' if valid and complete else ('unfinished' if valid else 'failed'),duration=report.get('duration'),result=report.get('result'),teams=report.get('teams',[]),winner=None)
        row['continuations']=row.get('continuations',[])+[{'previous_report':str(previous),'previous_save':str(saved),'command':command,'wall_seconds':time.monotonic()-began,'exit_code':process.returncode}]
        identities=headless.get('independent_ai',{}).get('identities',[])
        by_team={item['team']:Path(item['path']).stem for item in identities}
        winners=report.get('winner_teams',[])
        if row['status']=='completed' and len(winners)==1:row['winner']=by_team.get(winners[0])
        decisions=headless.get('independent_ai',{}).get('teams',[])
        prefix.with_name(prefix.name+'_decisions.json').write_text(json.dumps(decisions,ensure_ascii=False,indent=2)+'\n')
        for team,name in by_team.items():
            review={key:value for key,value in report.items() if key!='headless'}
            review['review']={'strategy':name,'team':team,'starts':game['starts'],'status':row['status'],'winner':row['winner'],'source_sha256':summary['strategies'][name]['sha256'],'own_decisions':next((item for item in decisions if item['team']==team),{})}
            prefix.with_name(prefix.name+'_'+name+'_review.json').write_text(json.dumps(review,ensure_ascii=False,indent=2)+'\n')
        return index,row
    with ThreadPoolExecutor(max_workers=4) as pool:
        for index,game in pool.map(extend,targets):summary['games'][index]=game
    unchanged=engine_hashes()==summary['engine_sha256']
    summary['engine_source_unchanged']=bool(summary['engine_source_unchanged']) and unchanged
    score={name:sum(game['winner']==name for game in summary['games']) for name in ('alpha','beta')}
    valid=unchanged and all(game['status']=='completed' for game in summary['games'])
    winner=max(score,key=score.get) if valid and score['alpha']!=score['beta'] else None
    summary.update(score=score,winner=winner,loser=('beta' if winner=='alpha' else 'alpha') if winner else None)
    summary['instruction']='Only '+summary['loser']+' may revise; winner source stays unchanged.' if summary['loser'] else 'No unique loser; both remain frozen.'
    summary_path.write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'round':str(directory),'score':score,'winner':winner,'loser':summary['loser'],'statuses':[game['status'] for game in summary['games']]},ensure_ascii=False))
    return 0 if unchanged and all(game['status']!='failed' for game in summary['games']) else 1

if __name__=='__main__':raise SystemExit(main())
