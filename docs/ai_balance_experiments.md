# AI 1v1 与数值平衡实验

批量工具使用真实无渲染游戏逻辑，从标准基地和初始资金开局，不额外赠送矿工、工厂、军队或科技。AI 通过普通建造、生产与命令接口行动。孤立交战诊断的生成单位属于单独实验，不混入正常对局胜负统计。

## 电脑行为与单局入口

陆战 AI 共用建设、经济、情报、防御和进攻流程，`scripts/ai_faction_adapter.gd` 只提供各阵营的兵种、科技和航空偏好。重锤使用付费工程兵与矿脉钻塔，预留脚手架未付费用并接管中断施工；长钉通过正常铁路与矿车建立经济；天翼选择其束流、标定与航空单位；正典采用步兵和装甲混编。三种策略改变预算与进攻节奏，难度改变反应时间，均没有额外资金、减价或视野。

AI 只根据本方单位、公开地图、已看见的敌军与最后观察位置决策。新建筑保留交通间隔，集结点远离矿厂；进攻在歼灭局部目标后继续清理影响胜负的建筑。铁路、围墙和路障不再把进攻部队留在无效残局目标上。正常游戏第零槽位继续由玩家控制，战役与海战保留原有任务行为。

受到可见武装敌军威胁、兵力不足时，暂停可选经济和科技扩张，优先付费补充防守步兵，同时保留脚手架未付款与最后矿车恢复预算。首轮历史结果见 [2026-10-07 对照报告](ai_balance_results_20261007.md)；后续版本的矿车、铁路与故障恢复证据见 [2026-10-08 可靠性报告](ai_reliability_results_20261008.md)。历史对局和开发探针不能代替当前冻结版本的完整数值实验。

```sh
./tools/run_headless.sh --map symmetric --factions kestrel,sky --ai both \
  --ai-styles balanced --difficulty normal --starts swap --duration 900 \
  --dt .05 --output /tmp/kestrel-sky
```

`--ai` 可选 `off`（默认）、`both`、`left`、`right`。`--ai-styles` 可传单个策略，或与请求阵营对应的两个逗号分隔策略；交换出生侧时一起交换阵营及策略。`--starts swap` 仅适用于新开 1v1，不修改已有存档的地图与势力对应关系。

## 经济与故障恢复可靠性

数值对局前先检查 AI 能否持续采矿、出兵，并在矿车、矿厂或铁路遭受单次损失后恢复。可靠性场景使用标准己方 HQ 和 4000 初始资金，只把被动敌方 HQ 的生命值延长以保留观测窗口；它不属于正式胜率对局。故障在第 300 游戏秒移除一个对应实体，收入仍须经过正常采集、矿车入厂、卸货或钻机工作流程。

```sh
godot --headless --audio-driver Dummy --path . \
  --script res://tools/ai_reliability_soak.gd -- \
  --faction iron --side 0 --fault rail_break --duration 900 \
  --dt 0.03333333333333333 --output /tmp/iron-rail-recovery
```

`--fault` 支持 `none`、`miner_loss`、`refinery_loss`、`rail_break`；该阵营没有相应实体时会明确记录不适用。`--side` 支持 0 或 1。此工具读取当前工程规则，不支持数值对局工具的 `--rules` 参数，因此应保留此次工程源码和规则身份，并在冻结逻辑上比较结果。

输出包含正常统计 JSON/CSV、最终存档和 `*_reliability.json`。可靠性检查包括总收入、正常生产、最后 180 秒收入、矿车最长无移动或货量进度时间，以及故障与恢复记录。最近出兵数量为观察项：军队达到数量上限时停止生产可以是正常行为。卸货金额、进厂位置和事件一致性应同时参考可靠性报告中的 delivery audit；累计收入继续增加本身不能证明每一条运输路径都正常。

已修复逻辑后的新批次与旧开发、失败或运行中改源码的批次分别保留。被拒绝的旧批次可用于复盘故障，不能与新批次混合计算候选规则的胜率。

## 批量运行

```sh
python3 tools/run_balance_experiments.py \
  --styles balanced,pressure,armor --duration 600 --workers 4 \
  --output-dir artifacts/ai_balance/baseline
```

完整条件为四阵营两两对阵的六组，各交换出生槽位；另加每阵营同阵营镜像对照。每种策略 16 局，三种策略合计 48 局。镜像对照的双方阵营和策略相同，再交换会完全重复，因此只运行一个朝向。`balanced`、`pressure`、`armor` 分别提供不同兵力与进攻节奏；对局双方使用同一种策略，避免把策略强弱误认为阵营强弱。

`--style-pairing matched` 是上述默认配置，保留已有命令和条件名称。`--style-pairing cross` 测试全部有序策略配对：每组跨阵营对阵为 3 × 3 种策略组合 × 两个出生朝向，六组共 108 局。镜像对照保留三种同策略各一局，三种不同策略的无序组合各交换两侧，共每阵营 9 局、四阵营 36 局；默认合计 144 局。`--controls none` 只运行跨阵营对局。

```sh
python3 tools/run_balance_experiments.py --style-pairing cross \
  --styles balanced,pressure,armor --controls none --duration 1200 \
  --win-rate-report --output-dir artifacts/ai_balance/cross_policy
```

默认每步 0.05 游戏秒。正式结论还需用 `--dt 0.03333333333333333` 重现涉及调整的对阵，检查步长敏感性。`--duration` 是游戏时间上限；`--wall-timeout` 是每个游戏进程的墙钟秒上限，默认 300 秒。并行进程可选 1 至 8 个，默认仍为 4；机器资源足够时可用 `--workers 8` 加速完整交叉策略计划。

地图的几何布局固定；交换操作将阵营和对应策略一起交换到固定地图的另一个槽位，矿点和地图归属保持原有设置。改变种子不代表新的地理样本，确定性复跑也不增加独立样本量。本工具不报告统计显著性或总体胜率置信区间。

小规模验证：

```sh
python3 tools/run_balance_experiments.py --suite smoke --styles balanced \
  --duration 90 --output-dir /tmp/paper-front-ai-smoke
```

定向复验与镜像对照：

```sh
python3 tools/run_balance_experiments.py --styles armor \
  --matchups kestrel:rivet,iron:sky --controls none --duration 600 \
  --output-dir artifacts/ai_balance/armor_recheck

python3 tools/run_balance_experiments.py --styles balanced --controls only \
  --output-dir artifacts/ai_balance/mirrors
```

`--factions kestrel,sky` 可缩小阵营范围。`--max-matches N` 可截取诊断子集，清单会记录所有未执行条件；截取结果不应被描述为完整循环赛。

单一 `balanced` 策略、`--controls none` 的完整循环赛为 12 局，每组阵营只有两个朝向，用于筛选候选和观察长局停滞。扩展为三策略交叉的 108 局后，每阵营参与 54 局，每组阵营参与 18 局。筛选阶段的少量终局不能替代后续完整计划的目标评估。

## 基线、候选与报告

```sh
python3 tools/run_balance_experiments.py --rules /tmp/candidate-rules.json \
  --styles balanced,pressure,armor --duration 600 --workers 4 \
  --baseline artifacts/ai_balance/baseline \
  --output-dir artifacts/ai_balance/candidate
```

每次运行将规则原样复制到实验目录 `rules.json`，全部进程读取这一份冻结文件。清单复用 Headless 导出依赖闭包，记录全部游戏逻辑 GDScript 的 SHA256，包含 AI、阵营适配、矿车停靠、铁路、规则加载和地图生成；不把诊断工具纳入游戏逻辑闭包。完整命令、策略、槽位、步长和时间上限也会保存。导出自身包含模拟实际使用的规则快照和规则校验值。工具检查运行期间这些游戏源码是否变化；正式数值比较要求游戏逻辑相同，先修 AI 或底层机制再重新生成基线。分析工具自身保存起止校验值，若仅分析工具发生变化，会提示重新汇总，不将已完成的游戏逻辑证据作废。

结果目录包括：

- `manifest.json`：实验决定、配置、规则及源码身份、计划与省略的条件。
- `matches/*.json` 和对应 CSV：原始游戏统计，保留逐秒经济、建筑、步兵曲线及生产、伤亡事件。
- `matches/*.run.json` 和日志：单局命令、实际阵营对应关系、返回码、墙钟时间、终止原因及校验。
- `results.json`：逐局结果，按对阵与策略汇总胜负、未结束、进程超时、错误，以及经济、生产、战损、首收入和首单位时间。
- `team_summary.csv`、`report.md`：可表格分析的队伍汇总和便于阅读的报告。

`unfinished` 表示游戏时间耗尽；`wall_timeout` 表示进程运行超时，都不自动判平或按资产判胜。脚本错误、错误日志、错误槽位、赠送开局力量或不完整曲线会标为无效，排除有效对局汇总。未结束对局仍保留实际观测值，跨局经济均值需结合结束时长；缺失的首单位/收入时间表示未观测到该事件。

报告还记录 AI 的决策与进攻波次、战斗单位生产量、距末次收入的时间，以及无伤害/无进攻/无战斗生产的条件数量。这些是实验适用性的观测项，不自动判为失败；敌方压制同样可能中断收入或进攻。正式调数值前，先用镜像对照和存档检查 AI 能否正常采集、扩张、出兵与交战。

候选报告逐一匹配相同实验条件；步长、时间上限、难度或 AI/模拟源码不同会明确标注不能直接作数值因果比较。同阵营镜像主要看槽位胜负和曲线，阵营自身胜负没有阵营强弱含义。

已有报告可重新汇总而不重跑游戏：

```sh
python3 tools/run_balance_experiments.py --analyze-only \
  --output-dir artifacts/ai_balance/candidate \
  --baseline artifacts/ai_balance/baseline
```

## 35% 胜率目标与未结束对局

`results.json` 始终包含 `win_rate_targets`；添加 `--win-rate-report` 会另外导出 `win_rates.md` 和 `win_rates.csv`。已有批次也可只生成胜率报告：

```sh
python3 tools/run_balance_experiments.py --analyze-only --win-rate-report \
  --target-win-rate .35 --min-completion-rate 1 --min-decisive-games 6 \
  --output-dir artifacts/ai_balance/cross_policy
```

主指标按真实分胜负终局计算 `W / (W + L)`。真实平局另列，既不计为胜，也不折算半胜；未结束、运行失败和缺失结果也单列。镜像对照全部排除阵营总体胜率与跨阵营目标。

默认每阵营总体目标为至少 35%，并单独评估每组阵营对阵的双方是否都达到 35%。总体通过不能代替逐对阵通过。统计按已安排的全部策略与出生条件汇总，定向对阵、截取计划或缺少策略条件的子集不能宣布完整循环赛目标已通过。

默认要求 **100% 的已安排对局具有真实终局**，且每个评估行至少包含 6 个真实分胜负结果。`--min-completion-rate` 可显式降低完成率门槛，`--min-decisive-games` 可修改最低终局数量；降低门槛会削弱结论。没有真实胜负时胜率为“未定义”，不会判为达标。大量真实平局也需结合 `W/all` 审阅，不能仅看到排除平局后的胜率。目标未通过不会改变工具原有退出码：运行成功与平衡目标通过是两种不同结果。

若在最终实验开始前明确选择较低的完成率门槛，例如 `--min-completion-rate .85`，可以额外要求每个目标行的 `W/all ≥ .35`。这等价于把全部未知结果都赋为该阵营失败后，其最低胜率仍达标，是比只看已结束子集更保守的条件。现有工具将这项结果单独记为 `all_scheduled_lower_bound_meets_target`；它不自动合入 `target_met`，使用该方案的报告必须明确检查两者及完整覆盖。不能看到未结束结果后再临时放宽门槛。

报告同时给出 `W/all` 及全部已安排对局的赋值上下界：下界 `W/N`，上界 `(W + 未完 + 失败 + 缺失) / N`。这些上下界不是统计置信区间；每个阵营的上界分别计算，双方不能同时赢下同一场未知结果。清单中明确省略、未安排的条件不放入 N，但会令完整覆盖检查失败。

游戏时间上限产生的未完对局不能被当成平局或过滤后宣布达标。工具不自动延长比赛；需要延长 `--duration` 重跑对应条件，或用保留的单局存档继续到真实结算。继续后的结果应替换该条件，不能把相同确定性前缀当作新的独立样本。

少量确定性条件存在明显的胜率粒度：每组对阵只有 6 个真实胜负时，双方都至少 35% 实际要求各胜 3 场；交叉策略 18 个真实胜负时，双方须各至少胜 7 场。报告保存按实际有效终局数量换算的最低胜场数。这些目标只描述所测地图与 AI 策略条件，不能被解释为全部玩家、地图或策略的总体概率。

默认使用源码入口 `tools/run_headless.sh`。`--runner artifacts/headless/PaperFrontHeadless.x86_64` 可使用独立文件；清单会记录该文件的 SHA256。源码哈希本身不能证明独立文件内部包含的版本，独立文件比较应同时保留构建来源并重新构建。

重新构建使用 `./tools/build_headless.sh`；它会自动更新逻辑依赖闭包并生成 `artifacts/headless/build_manifest.json`，随后检查独立入口的脚本加载。排查局内停滞时可给单局加 `--save-final /tmp/checkpoint.pfront`，再使用 `godot --headless --path . --script res://tools/inspect_ai_checkpoint.gd -- /tmp/checkpoint.pfront` 查看实际单位位置、队列与命令。

## 孤立战斗诊断

```sh
godot --headless --audio-driver Dummy --path . \
  --script res://tools/balance_micro_diagnostics.gd -- \
  --rules data/rules.json --suite full --output artifacts/ai_balance/micro
```

该工具在明确标注的平坦实验场直接生成预算封顶的阵容，单独输出实际花费、未花费余额、单位列表、残余价值和交战结果。整数单位费用使实际花费可能不同，比较时须读取该差异；不能把此处的胜者当成完整对局的胜者，也不能从单一兵种镜像推断阵营整体强弱。

工具契约测试：`python3 tools/test_balance_experiments.py`。
