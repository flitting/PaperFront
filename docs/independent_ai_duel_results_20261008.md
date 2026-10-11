# 独立 AI 对抗结果 · 2026-10-08

> Historical evidence for the dated build/experiment only; not v0.8.0 acceptance. Generated `artifacts/` evidence is local output and is not bundled with the source repository. Current checks: [release notes](release_notes.md).
> 此文仅保留对应日期的实验或旧工具回执，不代表当前发行版验收。

当前同一对冻结策略的四场有效换边对局各胜两场，观察胜率为 50% / 50%。已停止策略迭代与后续对战。

共 9 轮、36 场正式对局：32 场真实终局，4 场未完成，0 场错误。末轮 Alpha 2 胜、Beta 2 胜；未完成局不改判。

## 实验条件

Kestrel 同阵营，明原对称场，正常初始 4000 资金和正常难度，固定 1/30 秒步长。每版两个种子（733、734），每个种子交换出生点，各轮四场。第6轮未完成换边局在同一冻结版本下从1200秒存档续跑到2400秒，保留原记录，续跑不计新场次；第7轮保留为1200秒未完成。两个策略每 2 秒同时观察后决策，执行先后交替。原胜方决策源码保持，仅整轮败者或经胜场上界证明不能赢整轮的原挑战方修订策略。双方可改自己的采集器和记录副本，单轮内冻结。

公共执行层复用 v7 的合法经济、生产、采矿解堵和移动规则。两方独立实现观察驱动策略和战术，分别维护实例、记忆和采集器。本次对抗期间正式游戏数值未改变。

## 各轮结果

| 轮次 | Alpha 版本 | Beta 版本 | Alpha 胜 | Beta 胜 | 判定 |
| --- | --- | --- | ---: | ---: | --- |
| 1 | alpha_v1_measured_combined_arms | beta_v1_combined_muster | 0 | 4 | 败者 alpha |
| 2 | alpha_v2_cohesive_infantry | beta_v1_combined_muster | 4 | 0 | 败者 beta |
| 3 | alpha_v2_cohesive_infantry | beta_v2_supply_formation | 0 | 4 | 败者 alpha |
| 4 | alpha_v3_range_and_circulation | beta_v2_supply_formation | 4 | 0 | 败者 beta |
| 5 | alpha_v3_range_and_circulation | beta_v3_income_defense | 0 | 4 | 败者 alpha |
| 6 | alpha_v4_infantry_budget_screen | beta_v3_income_defense | 0 | 2 | 挑战方不能赢整轮；保留未完成 |
| 7 | alpha_v5_income_before_budget | beta_v3_income_defense | 0 | 2 | 挑战方不能赢整轮；保留未完成 |
| 8 | alpha_v6_protected_spotter | beta_v3_income_defense | 0 | 4 | 败者 alpha |
| 9 | alpha_v7_screened_combined_advance | beta_v3_income_defense | 2 | 2 | 双方保持 |

## 败者修订

| 对应轮次 | 修订方 | 记录依据 | 实际修改 |
| --- | --- | --- | --- |
| 2 | alpha | Alpha 首攻约120–138秒团灭、第二炼矿厂导致约38秒低电、活跃步兵峰值7。 | 实到集结与分段推进、步兵采购预算、付费先补电再扩矿。 |
| 3 | beta | 140–192秒5人小队、资金达1041而兵营工厂空队列；214秒扩矿后约44秒低电；两次小队前压快速损失。 | 工厂完成后本方合法采购调度；七人后补电、九人后扩矿；步兵远程火力与配比、步兵中位位置推进及局部撤退。 |
| 4 | alpha | 首攻可见敌射手而己方短射程部队在284–301秒损10人；左侧满载矿车回厂积压并收入中断；右侧付费飞机无指令。 | 远程兵组合与目标选择、12人9实到集结、前28米集合点、合法换厂恢复、已有航空指令及机场前电力预算。 |
| 5 | beta | 294秒前仅一矿车、扩矿储蓄停产；300秒收入3000/敌5000；左400秒army0时因780替补坦克预留不能买守军。 | 第二矿车预算优先、危急防守解除替补坦克储蓄、更偏射手组合、近期可见接触40秒记忆与局部兵力撤退；采集器增加队形/命令/开火时序。 |
| 6 | alpha | v3整轮未主动advance；304秒对手可见4–5射手而己仅3且已买2坦克/侦察车；306–322秒守军11损对5损，随后经济失守。 | 首坦克后本人付费采购优先射手/穿甲，12步兵前延迟额外装甲；规划早期塔与第二兵营，可见来袭时回缩至保护线，14人11实到进攻。 |
| 7 | alpha | v4第二矿车约212秒、第二炼矿厂307.5秒；塔249.5秒先投入，240秒收入少1000，300秒仅9战斗单位；右续跑2400仍未完成。 | 共享开局经济保持到第二炼矿厂实际完成，再接管普通采购；必要矿车先付款/单独储备，第四矿车延至军队16，其他战术保持。 |
| 8 | alpha | 两侧340秒初战己8损/敌12损已改善；左406.9侦察车阵亡、408仅3敌可见、412敌6射手再现、420只余5兵。 | 专职侦察车保持主队后/侧方不追击，去重优先正常补车；射手提前对当前可见远程威胁下合法attack，经济主体保持。 |
| 9 | alpha | v6左308秒射手留61.2前追72.7机枪，而同队回缩52；307–310四射手先死，首战交换从v5的8/12退步至v6的9/5。 | 恢复防御窄0.65目标获取；专职后方侦察仅用于advance，推进射手余量1.2，取消3米前追；充裕资金时正常替换首坦克，不锁开局收入。 |

## 对局明细

| 轮次 | 种子 | 位置分配 | 时长（秒） | 胜方 | 状态 |
| --- | ---: | --- | ---: | --- | --- |
| 1 | 733 | Alpha 左 / Beta 右 | 1035.97 | beta | completed |
| 1 | 733 | Beta 左 / Alpha 右 | 831.50 | beta | completed |
| 1 | 734 | Alpha 左 / Beta 右 | 1035.97 | beta | completed |
| 1 | 734 | Beta 左 / Alpha 右 | 831.50 | beta | completed |
| 2 | 733 | Alpha 左 / Beta 右 | 1065.23 | alpha | completed |
| 2 | 733 | Beta 左 / Alpha 右 | 449.83 | alpha | completed |
| 2 | 734 | Alpha 左 / Beta 右 | 1065.23 | alpha | completed |
| 2 | 734 | Beta 左 / Alpha 右 | 449.83 | alpha | completed |
| 3 | 733 | Alpha 左 / Beta 右 | 930.60 | beta | completed |
| 3 | 733 | Beta 左 / Alpha 右 | 930.37 | beta | completed |
| 3 | 734 | Alpha 左 / Beta 右 | 930.60 | beta | completed |
| 3 | 734 | Beta 左 / Alpha 右 | 930.37 | beta | completed |
| 4 | 733 | Alpha 左 / Beta 右 | 604.70 | alpha | completed |
| 4 | 733 | Beta 左 / Alpha 右 | 738.00 | alpha | completed |
| 4 | 734 | Alpha 左 / Beta 右 | 604.70 | alpha | completed |
| 4 | 734 | Beta 左 / Alpha 右 | 738.00 | alpha | completed |
| 5 | 733 | Alpha 左 / Beta 右 | 829.50 | beta | completed |
| 5 | 733 | Beta 左 / Alpha 右 | 506.80 | beta | completed |
| 5 | 734 | Alpha 左 / Beta 右 | 829.50 | beta | completed |
| 5 | 734 | Beta 左 / Alpha 右 | 506.80 | beta | completed |
| 6 | 733 | Alpha 左 / Beta 右 | 728.63 | beta | completed |
| 6 | 733 | Beta 左 / Alpha 右 | 2400.00 | — | unfinished |
| 6 | 734 | Alpha 左 / Beta 右 | 728.63 | beta | completed |
| 6 | 734 | Beta 左 / Alpha 右 | 2400.00 | — | unfinished |
| 7 | 733 | Alpha 左 / Beta 右 | 936.23 | beta | completed |
| 7 | 733 | Beta 左 / Alpha 右 | 1200.00 | — | unfinished |
| 7 | 734 | Alpha 左 / Beta 右 | 936.23 | beta | completed |
| 7 | 734 | Beta 左 / Alpha 右 | 1200.00 | — | unfinished |
| 8 | 733 | Alpha 左 / Beta 右 | 470.83 | beta | completed |
| 8 | 733 | Beta 左 / Alpha 右 | 935.30 | beta | completed |
| 8 | 734 | Alpha 左 / Beta 右 | 470.83 | beta | completed |
| 8 | 734 | Beta 左 / Alpha 右 | 935.30 | beta | completed |
| 9 | 733 | Alpha 左 / Beta 右 | 549.07 | alpha | completed |
| 9 | 733 | Beta 左 / Alpha 右 | 693.13 | beta | completed |
| 9 | 734 | Alpha 左 / Beta 右 | 549.07 | alpha | completed |
| 9 | 734 | Beta 左 / Alpha 右 | 693.13 | beta | completed |

## 最终冻结版本

- Alpha：`alpha_v7_screened_combined_advance`，[策略](../ai/duel/alpha.gd)、[采集器](../ai/duel/alpha_recorder.gd)。
- Beta：`beta_v3_income_defense`，[策略](../ai/duel/beta.gd)、[采集器](../ai/duel/beta_recorder.gd)。
- 末轮源码哈希与原始记录索引 (`artifacts/ai_duel_20261008/round_09/round.json`)。


## 实际发现与未完成项

败者通过各自记录定位并修订了首攻脱节、扩张缺电、矿车采购被挤占、替补坦克预算锁住守军、射程组合及视野丢失等具体问题。版本曾多次反超，后期对固定 Beta v3 的追赶按上述条件评估。

末轮四场均为左侧获胜，因此2:2不能排除位置效应，也不能证明两套AI在其他条件下等强。Beta v3 仍有残局探索缺口：第6轮换边局续跑到2400秒仍围绕已毁工厂停留，未搜索到最后兵营；第7轮换边局也未完成。这些局保留为未完成，没有改成 Beta 胜利。Alpha 的矿车换厂分支在第4轮未触发；末轮左侧受理过一次合法换厂命令，右侧未触发，不能据此宣称全面矿车可靠性已验证。末轮也未检验航空作战。详见双方复盘及逐次记录。

## 复盘与记录

- [Alpha 复盘](../ai/duel/alpha_reflection.md)
- [Beta 复盘](../ai/duel/beta_reflection.md)
- 实验汇总与终止判定 (`artifacts/ai_duel_20261008/league.json`)
- [对抗规则](../ai/duel/RULES.md)
- [接口与运行命令](independent_ai_duel.md)

每轮目录保存策略/采集器冻结源码、公共引擎与规则快照、SHA256 清单、完整对局 JSON、经济/数量曲线 CSV、事件 CSV、双方自定义记录、最终存档以及分别脱敏的复盘文件。裁判原始记录保留，各方只修改自己的副本。对手源码和私有策略记忆禁止读取；执行约束来自明确任务规则、模块源码审核和裁判分发，工作区没有操作系统级权限隔离。

## 验证与解释范围

独立接口/记录器 92 项、AI 规划 100 项、首辆坦克与矿车预算 75 项、原双方控制 17 项、Headless 基础 25 项、终止判定 12 项检查通过；短时端到端导出检查通过。各轮公共引擎/数值哈希一致，胜者决策源码保持，未发现协议违规。

两个种子在本固定地图的首轮产生完全相同的同侧结果，因此这些重复运行不能当作独立随机样本。这里的胜率仅表示当前地图、同阵营和少量确定性实验条件下的观察结果，不代表四阵营数值平衡、随机对局总体胜率或统计显著性。未完成/错误对局不加入胜负分母，旧 AI 版本的成绩不用于当前版本接近 50% 的判定。若挑战方已获胜场加全部未完成场次仍不超过固定对手的已获胜场，则只能证明挑战方不能赢整轮；可据此继续败者修订或计追赶失败，不会把未完成局改判为败局。

正式规则 SHA256：`9c7b6bb7aa81c6da29f530f4f9e36ffe2ff2b38a69fb9c756cf23ea53273dfbb`。
