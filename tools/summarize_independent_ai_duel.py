#!/usr/bin/env python3
"""Summarize immutable referee rounds without mixing AI versions."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import re
from run_independent_ai_duel import evaluate_league

ROOT=Path(__file__).resolve().parents[1]

def main() -> int:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory',type=Path,default=ROOT/'artifacts/ai_duel_20261008')
    parser.add_argument('--report',type=Path)
    args=parser.parse_args()
    directory=args.directory.resolve()
    paths=sorted(directory.glob('round_*/round.json'))
    rounds=[json.loads(path.read_text()) for path in paths]
    if not rounds:
        print(json.dumps({'status':'awaiting_first_round'}));return 0
    violations=[]
    for previous,current in zip(rounds,rounds[1:]):
        winner=previous.get('winner') or previous.get('adjudication',{}).get('incumbent')
        if winner and previous['strategies'][winner]['sha256']!=current['strategies'][winner]['sha256']:
            violations.append('Previous round winner strategy changed')
        if previous['rules_sha256']!=current['rules_sha256'] or previous['engine_sha256']!=current['engine_sha256']:
            violations.append('Shared rules/engine changed between rounds')
    if not all(item['engine_source_unchanged'] for item in rounds):violations.append('Source changed during a round')
    stop=evaluate_league(rounds)
    summary={'schema':'paper_front.independent_ai_league','schema_version':1,
        'rounds':[str(path) for path in paths],'stop':stop,'protocol_violations':violations,
        'total_games':sum(len(item['games']) for item in rounds),
        'rules_sha256':rounds[0]['rules_sha256'],'latest_score':rounds[-1]['score']}
    (directory/'league.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(summary,ensure_ascii=False))
    if not args.report:return 0 if not violations else 1
    if not stop['stop'] or violations:raise SystemExit('Goal stopping condition is not valid; do not write a completion report')
    counts={status:sum(game['status']==status for item in rounds for game in item['games']) for status in ('completed','unfinished','failed')}
    reason='当前同一对冻结策略的四场有效换边对局各胜两场，观察胜率为 50% / 50%。' if stop['reason']=='near_50_percent' else '同一败方连续修订四次仍未赢得对同一冻结对手的轮次，触发“超过三次迭代仍追不上”的终止条件。'
    lines=['# 独立 AI 对抗结果 · 2026-10-08','',reason+'已停止策略迭代与后续对战。','',
        f"共 {len(rounds)} 轮、{summary['total_games']} 场正式对局：{counts['completed']} 场真实终局，{counts['unfinished']} 场未完成，{counts['failed']} 场错误。末轮 Alpha {rounds[-1]['score']['alpha']} 胜、Beta {rounds[-1]['score']['beta']} 胜；未完成局不改判。",'',
        '## 实验条件','',
        'Kestrel 同阵营，明原对称场，正常初始 4000 资金和正常难度，固定 1/30 秒步长。每版两个种子（733、734），每个种子交换出生点，各轮四场。第6轮未完成换边局在同一冻结版本下从1200秒存档续跑到2400秒，保留原记录，续跑不计新场次；第7轮保留为1200秒未完成。两个策略每 2 秒同时观察后决策，执行先后交替。原胜方决策源码保持，仅整轮败者或经胜场上界证明不能赢整轮的原挑战方修订策略。双方可改自己的采集器和记录副本，单轮内冻结。','',
        '公共执行层复用 v7 的合法经济、生产、采矿解堵和移动规则。两方独立实现观察驱动策略和战术，分别维护实例、记忆和采集器。本次对抗期间正式游戏数值未改变。','',
        '## 各轮结果','', '| 轮次 | Alpha 版本 | Beta 版本 | Alpha 胜 | Beta 胜 | 判定 |', '| --- | --- | --- | ---: | ---: | --- |']
    def version(item,name):
        source=Path(item['strategies'][name]['path']).read_text()
        match=re.search(r'const VERSION\s*:?=\s*"([^"]+)"',source)
        return match[1] if match else item['strategies'][name]['sha256'][:12]
    for index,item in enumerate(rounds,1):
        label=('败者 '+item['loser']) if item.get('loser') else ('挑战方不能赢整轮；保留未完成' if item.get('adjudication') else '双方保持')
        lines.append(f"| {index} | {version(item,'alpha')} | {version(item,'beta')} | {item['score']['alpha']} | {item['score']['beta']} | {label} |")
    revisions=[]
    for index,path in enumerate(paths,1):
        revision=path.with_name('revision.json')
        if revision.exists():
            item=json.loads(revision.read_text())
            revisions.append((index,item))
    if revisions:
        lines+=['','## 败者修订','', '| 对应轮次 | 修订方 | 记录依据 | 实际修改 |', '| --- | --- | --- | --- |']
        for index,item in revisions:
            lines.append(f"| {index} | {item['revised_strategy']} | {item['evidence']} | {item['change']} |")
    lines+=['','## 对局明细','', '| 轮次 | 种子 | 位置分配 | 时长（秒） | 胜方 | 状态 |', '| --- | ---: | --- | ---: | --- | --- |']
    for index,item in enumerate(rounds,1):
        for game in item['games']:
            positions='Alpha 左 / Beta 右' if game['starts']=='default' else 'Beta 左 / Alpha 右'
            lines.append(f"| {index} | {game.get('seed','')} | {positions} | {game.get('duration',0):.2f} | {game.get('winner') or '—'} | {game['status']} |")
    latest=rounds[-1]
    lines+=['','## 最终冻结版本','',
        f"- Alpha：`{version(latest,'alpha')}`，[策略]({ROOT/'ai/duel/alpha.gd'})、[采集器]({ROOT/'ai/duel/alpha_recorder.gd'})。",
        f"- Beta：`{version(latest,'beta')}`，[策略]({ROOT/'ai/duel/beta.gd'})、[采集器]({ROOT/'ai/duel/beta_recorder.gd'})。",
        f"- [末轮源码哈希与原始记录索引]({paths[-1]})。",'']
    lines+=['','## 实际发现与未完成项','',
        '败者通过各自记录定位并修订了首攻脱节、扩张缺电、矿车采购被挤占、替补坦克预算锁住守军、射程组合及视野丢失等具体问题。版本曾多次反超，后期对固定 Beta v3 的追赶按上述条件评估。','',
        '末轮四场均为左侧获胜，因此2:2不能排除位置效应，也不能证明两套AI在其他条件下等强。Beta v3 仍有残局探索缺口：第6轮换边局续跑到2400秒仍围绕已毁工厂停留，未搜索到最后兵营；第7轮换边局也未完成。这些局保留为未完成，没有改成 Beta 胜利。Alpha 的矿车换厂分支在第4轮未触发；末轮左侧受理过一次合法换厂命令，右侧未触发，不能据此宣称全面矿车可靠性已验证。末轮也未检验航空作战。详见双方复盘及逐次记录。','',
        '## 复盘与记录','',
        f"- [Alpha 复盘]({ROOT/'ai/duel/alpha_reflection.md'})",f"- [Beta 复盘]({ROOT/'ai/duel/beta_reflection.md'})",f"- [实验汇总与终止判定]({directory/'league.json'})",f"- [对抗规则]({ROOT/'ai/duel/RULES.md'})",f"- [接口与运行命令]({ROOT/'docs/independent_ai_duel.md'})",'',
        '每轮目录保存策略/采集器冻结源码、公共引擎与规则快照、SHA256 清单、完整对局 JSON、经济/数量曲线 CSV、事件 CSV、双方自定义记录、最终存档以及分别脱敏的复盘文件。裁判原始记录保留，各方只修改自己的副本。对手源码和私有策略记忆禁止读取；执行约束来自明确任务规则、模块源码审核和裁判分发，工作区没有操作系统级权限隔离。','',
        '## 验证与解释范围','',
        '独立接口/记录器 92 项、AI 规划 100 项、首辆坦克与矿车预算 75 项、原双方控制 17 项、Headless 基础 25 项、终止判定 12 项检查通过；短时端到端导出检查通过。各轮公共引擎/数值哈希一致，胜者决策源码保持，未发现协议违规。','',
        '两个种子在本固定地图的首轮产生完全相同的同侧结果，因此这些重复运行不能当作独立随机样本。这里的胜率仅表示当前地图、同阵营和少量确定性实验条件下的观察结果，不代表四阵营数值平衡、随机对局总体胜率或统计显著性。未完成/错误对局不加入胜负分母，旧 AI 版本的成绩不用于当前版本接近 50% 的判定。若挑战方已获胜场加全部未完成场次仍不超过固定对手的已获胜场，则只能证明挑战方不能赢整轮；可据此继续败者修订或计追赶失败，不会把未完成局改判为败局。','',
        f"正式规则 SHA256：`{summary['rules_sha256']}`。",'']
    destination=args.report.resolve();destination.parent.mkdir(parents=True,exist_ok=True)
    destination.write_text('\n'.join(lines))
    return 0

if __name__=='__main__':raise SystemExit(main())
