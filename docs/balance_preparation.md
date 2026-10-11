# 对称地图、对局统计与 Headless

This guide covers the symmetric map, match reports and simulation-only commands. AI experiment options are in [AI balance experiments](ai_balance_experiments.md).

本文介绍对称地图、对局统计与无渲染入口。电脑 AI 和 1v1 实验的完整用法见 [AI 与数值平衡实验](ai_balance_experiments.md)。

## 对称战场

新建战局中选择 **明原对称场**（`symmetric`）。192 × 192 米，固定两方，左右对置。地形、道路、坡道、树木、矿点与中立房屋均按两个轴严格镜像；四级高地通过宽坡连接，没有水面。出生区与经济区保留大块建造空间，中央和两翼都有陆路。

地图布局固定，种子仅作为对局来源信息保存，便于在相同条件下比较结果；不同种子不代表独立地理样本。

## 统计与导出

从开局 0 秒开始，约每个游戏秒记录一次双方状态，并保留结束瞬间。暂停不计入游戏时间。结算页显示资金余额、建筑总量、步兵总量，以及可切换的经济、兵力、资产和伤害曲线；鼠标悬停可查看采样值。

建筑总量包含施工和轨道；原有“存留建筑”指标继续排除轨道。步兵按规则的 infantry 护甲分类，包含运输或驻军中的存活步兵。净投入为初始资金加收入和出售收入减去当前余额，已扣除退款，并非未经退款调整的购买总额。

每次结算自动导出到 `user://match_reports/`，结算页显示实际目录。“导出统计”可再次写入同一局的报告。报告包括完整 JSON，以及时间序列、汇总、关键事件 CSV。JSON 保留地图种子、阵营、完整规则快照及校验值、胜者与淘汰方、采样和完整性说明，便于后续程序分析。

存档包含已采集的曲线。旧存档没有的时间数据不会被补造；界面与导出均注明数据起点。事件日志保留逻辑层的生产、部署、损失、占领等关键事件，不包含画面效果和完整可播放录像。

## 无渲染运行

源码入口：

```sh
./tools/run_headless.sh --map symmetric --seed 42 --factions kestrel,rivet \
  --duration 60 --output /tmp/paper-front-match
```

独立 Linux 文件：

```sh
./tools/build_headless.sh
./artifacts/headless/PaperFrontHeadless.x86_64 --headless --audio-driver Dummy -- \
  --map symmetric --seed 42 --factions kestrel,rivet \
  --duration 60 --output /tmp/paper-front-match
```

该入口仅创建逻辑对象，不加载战场场景、模型、HUD 或播放器。它共用 `simulation.gd`、规则配置、寻路、生产、经济、战斗与统计；为可重复的逻辑测试使用同步寻路。默认步长为 1/30 秒，可用 `--dt` 选择 0.001 至 0.1 秒。

**AI 默认关闭；`--ai both` 可启用双 AI。** AI 关闭时，没有命令输入的双方不会自行建造或出兵。达到 `--duration` 只表示测试时间到，导出 `stop_reason=duration_limit`，不伪造平局；真实结束则导出 `stop_reason=result`。非法参数、规则或命令返回非零退出码，命令执行失败时尽可能保留部分报告。

### 命令脚本

`--commands /path/commands.json` 可输入按时间排序的命令数组，使用绝对游戏秒。命令时间可以落在两个固定步长之间，运行器会切分该步以准确执行。示例：

```json
[
  {"at": 0.125, "team": 1, "action": "produce", "selector": "rivet_hq", "spec": "rivet_rifle"},
  {"at": 20, "team": 0, "action": "sell", "id": 1, "confirmed": true}
]
```

支持 `build`、`place`、`produce`、`issue`、`sell`、`cancel_build`、`cancel_production`、`rally`。使用本方实体 `id` 或实体型号 `selector`；同型号有多个实体时，生产、出售等操作取最小 ID，`issue` 对所有匹配单位下令。位置采用 `pos: [x,z]`。建筑命令可传 `channel`（`auto`、`normal`、`defense`）；工程建筑可传本方工程兵 `builder`。命令遵守正常资金、科技、队列与占地规则，不提供免费生成单位命令。

`--save-final /path/final.pfront` 保存运行结束时的正常游戏存档。`--load /path/final.pfront` 可继续运行；此时 `--duration` 表示额外运行秒数，命令仍使用绝对游戏时间。`--rules /path/rules.json` 可指定经验证的规则配置，便于以后测试候选平衡参数。

库接口为 `scripts/headless_match.gd` 的 `start(options)`、`run_for(duration,dt,commands)` 和 `sim`；AI 与玩家入口共用这份模拟，无需另做战斗规则。

## 验证范围

专项测试在 `tools/test.sh` 中包含 `symmetric_map_tests`、`symmetric_map_navigation_tests`、`match_telemetry_tests`、`settlement_history_ui_tests`、`headless_match_tests` 与 `headless_ai_controls_tests`。实际发行验证以 [release notes](release_notes.md) 为准，历史检查数量不当作当前运行包证据。
