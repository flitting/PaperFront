# 独立 AI 对抗接口

Headless 可为每个席位加载独立 GDScript 策略模块。模块必须继承 `RefCounted`，提供 `decide(observation: Dictionary, memory: Dictionary) -> Dictionary`。两个席位使用不同实例和各自的持久记忆；模块不接收真实 simulation。这里是可信本地代码的接口隔离，不是进程安全沙箱。

```sh
./tools/run_headless.sh --map symmetric --factions kestrel,kestrel --ai both \
  --ai-modules res://ai/duel/alpha.gd,res://ai/duel/beta.gd \
  --difficulty normal --duration 1200 --dt 0.03333333333333333 \
  --output /tmp/duel --save-final /tmp/duel.pfront
```

`--starts swap` 同时反转阵营、策略风格和模块分配。`builtin` 可作为其中一方模块路径。未使用 `--ai-modules` 的原有玩法保持默认行为。加载含独立 AI 的存档时使用 `--ai both`；路径和 SHA256 必须匹配，修订后的策略应开新局。

## 观察

每 2 秒生成一次独立、深拷贝的观察。双方观察都在执行任一新决策之前产生。执行顺序每次轮换。观察结构：

- `time, team, faction, money, power: Vector2, home: Vector2, enemy_start: Vector2`。
- `own`: 己方实体数组。字段 `id, team, spec, kind, pos: Vector2, hp, max_hp, role, art, domain, armor_class, weapon, cost`；有则提供 `commands, queue, construct_remaining, cargo, state, emerging, loaded_in, ai_attacking, ai_traffic_until, flight_state, harvest_mine`。队列中的项目不计入 `counts`。
- `visible_enemies`: 只含当前可见敌方实体及上述公共实体字段，不含敌方命令、队列、资金、策略记忆。
- `roles, counts`: 己方存活建筑角色数量及所有存活实体 spec 数量，包含未完工建筑。
- `orders.normal/defense`: 己方两条建筑队列。
- `statistics`: 己方累计经济、生产、损失、伤害记录。
- `mines`: 公开矿点 `index, pos`；仅可见矿点提供实际 `amount`。
- `map`: 公知 `mode, size, starts`；`rules`: 双方同一份公开数值，拷贝修改无效。
- `last_commands`: 本方上次显式命令的成功/失败记录。

`memory` 为本席位的独立可变字典，修改后由宿主保存，另一方不可见。可保存阶段、可见敌军历史、攻击计时等。模块应为自包含 `.gd` 文件，不读取外部文件，不使用全局静态记忆，不直接加载 simulation、不读另一方代码。复盘时可读取主 agent 提供的完整对局记录，运行时仍遵守迷雾。

## 决策返回值

以下字段均可选，未知字段或非法参数会停止对局并记录 `ai_error`，不能算正常胜负。

```gdscript
return {
    "profile": {"infantry": ["rifle", "anti"], "vehicles": ["tank", "scout"],
        "infantry_limit": 14, "factory_share": 0.55, "tech_after": 220.0},
    "settings": {"wave": 6, "attack_gap": 32.0},
    "shared_economy": true, "shared_tactics": true,
    "commands": [{"action":"issue", "ids":[unit_id], "kind":"attack_move", "pos":goal}],
    "reason": "本次战略判断及触发依据"
}
```

公共执行层复用 v7 的合法建造、支付、采矿、矿车解堵、铁路恢复和移动避让。策略可以动态决定生产、扩张、作战节奏，也可关闭公共经济或战术并返回自身普通命令。两份 AI 的 `decide` 逻辑、文件和记忆彼此独立。

`profile` 支持：

| 字段 | 合法范围/含义 |
| --- | --- |
| infantry, vehicles, air | 本阵营现有单位的后缀数组，1–32 项；公共适配仍会按可见敌军选择防空/反装甲 |
| infantry_limit | 0–80，活跃/排队武装步兵生产上限 |
| wave_scale, attack_scale | 0.25–4，公共攻击集结和间隔系数 |
| factory_share | 0–1，步兵采购保留的坦克预算比例 |
| tech_after, air_after | 0–86400 秒，科技/机场最早规划时间 |
| expansion_after, factory_after | 0–86400 秒，第二炼矿厂/第二工厂最早规划时间 |
| builders | 1–8，工程兵目标 |
| tower_limit | 0–4，公共防御塔目标 |
| style | balanced / pressure / armor |

`settings.wave` 范围 1–40，`attack_gap` 范围 2–300 秒。反应时间固定 2 秒。公共执行层优先满足必需经济、首辆坦克和施工欠款，所以策略参数不保证立即购买。

显式 `commands` 每次最多 96 条，在公共执行层之后执行，仅能控制己方实体，不能攻击不可见敌方 ID，必须遵守正常支付、建造和移动规则。正在为交通避让的单位暂不接受覆盖命令。支持 `action`: build/place/produce/sell/cancel_build/cancel_production/rally/issue；实体用 `id` 或 `ids`，位置为 Vector2 或 `[x,z]`。不接受 selector。`team` 可省略，宿主按模块席位执行；伪造其他 team 会拒绝。issue 支持 move/attack/attack_move/force_move/stop/hold/harvest/repair/return/return_miner/board/unload_move/capture/garrison/patrol/land。

完整 JSON 导出中 `headless.independent_ai` 提供模块 SHA256、记忆和每次决策的理由、参数、显式命令结果及公共执行计数；原始经济曲线、生产/阵亡事件和终局存档同样保留。运行到时限仍未终局则记为未完成，不冒充平局或胜利。

## 本轮对抗约定

主 agent 负责冻结公共引擎/数值、裁判和调度。Alpha 和 Beta 两个 subagent 各自只修改自己的策略文件和复盘文档。Kestrel 同阵营、对称地图、初始正常 4000 资金、正常难度、1/30 秒步长、相同 1200 秒上限。每轮使用两个固定种子（733、734），每个种子两个出生点互换，共四场，均使用同一对冻结策略。整轮确定败者后仅败者修订，胜者 SHA256 必须保持；平局或未完成导致不能确定胜负时双方保持。每轮冻结源文件，记录规则/引擎哈希、原始对局、双方日志和复盘。此实验用于 AI 逻辑对抗，不应用新的游戏数值。

## 禁止偷看与终止规则

Alpha/Beta 的代码属于各自私有的实验材料。双方 subagent 禁止读取、搜索、导入或请求另一方的当前/历史源码、冻结副本、diff、内部记忆与未公开思考；禁止从对方 agent 获取策略提示。主 agent 是裁判，可以检查双方是否遵守接口和冻结规则。对抗方只能读取自己的源码与复盘、公共接口说明和主 agent 明确提供的对局 JSON/统计/事件/命令日志。对局行为记录可用于反思，但不得绕过目录或通过动态加载检查对方代码。GDScript 模块本身不得读取任何文件、访问网络、加载其他脚本或通过引擎单例查看运行状态。此处通过明确任务约束和主 agent 审核执行；同一工作区的 subagent 不具备操作系统级文件权限隔离。

胜率接近条件：至少完成 4 场有效已结束的换边胜负局，当前同一对冻结策略的最近 4 场有效胜负局中双方胜率均在 40%–60%（4 场时即各胜 2 场）。仅使用固定实验条件下的观察胜率，不宣称统计意义上已达到稳定总体 50%。平局、时限未完成及错误对局单独报告，不加入胜负分母。整轮四局均完成才允许确定该轮败者；整轮 2:2 时双方保持并满足接近条件。不得混用不同 AI 版本的胜负凑出 50%。

追赶失败条件：同一方在连续败北后修订 4 次，仍未赢得对同一份、保持不变的对手源码的配对轮次，即“超过三次迭代还是不行”；此时停止。主 agent 记录每次修订的理由、哈希、结果及胜者哈希不变证据。出现新的轮次胜者后重置相应追赶链。满足任一条件后不再修订，交付结果报告与完整原始记录。

对抗双方复盘只读取裁判生成的 `seed733_default_<本人>_review.json` 等四份本方 review 文件。这些记录保留公共终局统计、经济曲线、产损事件和本方决策；移除原始 `headless` 字段，避免向另一方透露对手私有记忆和策略调试理由。原始完整报告、双方冻结源码仅由主 agent 保管审核。

## 可定制的本方记录模块

用户授权双方修改自己的数据记录模块和对局记录副本。策略旁可放置同名 `_recorder.gd`，例如 `alpha.gd` 配套 `alpha_recorder.gd`，继承 RefCounted 并提供 `record(observation: Dictionary, memory: Dictionary) -> Dictionary`。宿主每 2 秒在决策前传入本方观察的独立副本和独立采集记忆，返回任意诊断字典写入本方决策日志的 `recording`。采集器同样不得读取文件、网络、加载脚本或窥视对手私有状态。

本方 `own` 实体现在额外提供其完整诊断字段，因此可自行记录矿车 cargo/harvest_phase、yield/route/commands、门口等待、施工状态、武器冷却和各类累计时间。敌方字段仍只限当前可见公共数据。采集器可以增加、重组、纠正自己的分析记录；禁止伪造裁判胜负。裁判保留未经修改的原始事件/统计/存档，各方可在 `ai/duel/alpha_records/` 或 `beta_records/` 修改自己的 review 副本及派生报告。败者可以同时修改自己的策略与采集器，胜者的 AI 决策源码保持不变；按用户授权，双方采集器可以在轮次之间改进，单轮内冻结。采集器仅记录信息，不向策略注入命令或影响游戏逻辑。冻结清单同时记录策略和采集器哈希。

若 1200 秒观察窗口结束仍未终局，保留原报告和存档，使用 `tools/extend_independent_ai_round.py artifacts/ai_duel_20261008/round_XX` 在同一份冻结策略/采集器、同一规则和同一局面上续跑。续跑不计新对局；保留 `round_before_continuation_*.json`、原始报告和所有续跑报告，最终胜负仍只来自真实终局。未完成局不当作平局或败局。

## 未完成局与挑战资格的界限

第6轮的换边局从1200秒续跑到2400秒仍无终局，因此保留为未完成。原冠军 Beta 已有2场真实胜利，挑战方 Alpha 0胜，尚有2场未完成；挑战方即使赢下全部未完成局也只能打平，数学上不能赢得整轮。主 agent 可继续授权原败方修订，同时冻结原冠军决策源码；这不等于宣判未完成局失败，也不产生一份新的整轮冠军认定。

“追赶失败”计数可以使用这个胜场上界证据：仅当挑战方已获胜场 + 未完成场次 ≤ 固定对手已获胜场，且挑战方确实修订了策略、对手策略和公共引擎均保持时，才证明这一修订没有赢得整轮。若上界仍可能反超，则不能计为失败。接近50%的停止条件仍严格要求同一对策略的四场真实已结束胜负局。所有未完成局继续单独列示，不计胜率，也不伪造平局或负局。
