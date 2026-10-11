# 2026-10-04 四阶段扩展验证与交付

> Historical evidence for the dated build/experiment only; not v0.8.0 acceptance. Generated `artifacts/` evidence is local output and is not bundled with the source repository. Current checks: [release notes](release_notes.md).
> 此文仅保留对应日期的实验或旧工具回执，不代表当前发行版验收。

> 本页为此前v5历史验收记录。当前模型、交互和地图重建见[本轮验证](revision_v6_validation.md)；正式linux路径与压缩包同步后会属于新版本，此前日志和runtime_export保留v5证据。

本页区分源码专项、真实图形运行、最终整套回归和独立程序交付。实现路径相对源码工程根目录；日志与截图链接为实际生成的证据。

**当前状态：四阶段扩展与Linux发行完成。** 最终整套回归PASS，包含教程战役AI开启的完整真实通关；源码、Shipping导出程序、压缩包解压程序分别通过88项实机检查。已验收程序同步至`artifacts/linux/PaperFront.x86_64`，完整包为`artifacts/PaperFront-linux-x86_64.tar.gz`。发行日期：**2026-10-04（Australia/Sydney）**。

## 13项要求与实际证据

| 原编号与要求 | 实际实现文件 | 专项和证据 | 当前结论 |
|---|---|---|---|
| 1. 全科技目录可见，前置未满足时锁定 | `scripts/tech_availability.gd`、`scripts/paper_hud.gd` | `tests/tech_visibility_tests.gd`；阶段1完整日志 (`artifacts/expansion_v5/stage1_full_regression.log`)、锁定科技截图 (`artifacts/expansion_v5/stage1_locked_tech.png`) | 常驻目录和真实购买检查共用前置规则；PASS |
| 2. 车辆、飞机统一运输 | `scripts/unit_transport.gd`、`scripts/aircraft_operations.gd`、`scripts/transport_commands.gd` | `tests/unified_transport_tests.gd`、`tests/unified_transport_input_tests.gd`；输入日志 (`artifacts/expansion_v5/stage1_transport_input.log`)、运输控制截图 (`artifacts/expansion_v5/stage1_transport_controls.png`) | 地面步兵含工兵、反甲兵；L降落、U地点卸载、B维修补给停机、合法机坪预约和实际HP收费；PASS |
| 3. 四军战斗、阵营数值 | `data/rules.json`、`tools/faction_balance.py`、`scripts/simulation.gd` | `tests/balance_tests.gd`、`tests/air_superiority_tests.gd`；阶段2完整日志 (`artifacts/expansion_v5/stage2_full_regression.log`) | 固定数值基线52项、制空128项通过；坦克主炮对步兵倍率0.30，四方战机8弹。完整数值见[当前目录](faction_catalog.md) |
| 4. 连墙凸/T/十字形，防御与经济双队列 | `scripts/wall_connections.gd`、`scripts/building_construction.gd`、`scripts/paper_world.gd` | `tests/wall_connection_tests.gd`、`tests/construction_channels_tests.gd`；阶段1日志 (`artifacts/expansion_v5/stage1_full_regression.log`)、围墙路径截图 (`artifacts/expansion_v5/stage1_walls_paths_iron.png`) | 邻接增建、摧毁、占领刷新实体墙；防御队列包含炮台、围墙、拒马；旧单队列防御订单迁移；PASS |
| 5. 海军与群岛运输 | `tools/naval_catalog.py`、`scripts/naval_operations.gd`、`scripts/naval_navigation.gd`、`scripts/naval_models.gd` | `tests/naval_stage3_tests.gd`、`tests/naval_native_combat_tests.gd`、`tests/naval_world_input_tests.gd`、`tests/stage3_shipyard_queue_tests.gd`；阶段3完整日志 (`artifacts/expansion_v5/stage3_full_regression.log`)、群岛海岸截图 (`artifacts/expansion_v5/stage3_islands_coast.png`) | 4船厂、12舰船；连通水域、桥下净空、真实岸边登卸、海陆攻防和在途保存；PASS。`iron_transport`仍为地面运输车 |
| 6. 默认、沙漠、雪原、城市与随机城市资产 | `scripts/battlefield_catalog.gd`、`scripts/battlefield_ruins.gd`、`scripts/landscape.gd`、`tools/bake_environment_assets.gd` | `tests/battlefield_profile_tests.gd`、`tests/battlefield_environment_tests.gd`；阶段3地图日志 (`artifacts/expansion_v5/stage3_map_tests.log`)、环境日志 (`artifacts/expansion_v5/stage3_environment_tests.log`)、城市街景 (`artifacts/expansion_v5/stage3_city_street.png`) | 6种新320地图含群岛，49个环境资源；城市道路、建筑、灯、长椅和行人进入真实场景；地图545项、环境19项PASS |
| 7. 选中单位虚线路线 | `scripts/selection_paths.gd`、`scripts/paper_world.gd` | `tests/selection_path_tests.gd`；阶段1日志 (`artifacts/expansion_v5/stage1_full_regression.log`)、路线截图 (`artifacts/expansion_v5/stage1_walls_paths_sky.png`) | 显示己方选中单位实际剩余路径与后续命令；不显示敌军路线；PASS |
| 8. 同条件经济与矿场HP | `data/rules.json`、`tools/faction_balance.py`、`scripts/simulation.gd` | `tests/economy_parity_tests.gd`、`tests/mining_force_rules_tests.gd`；阶段2经济结果 (`artifacts/expansion_v5/stage2_full_regression.log`) | 四方矿车物理参数一致，精炼厂1600HP；单矿车等条件75秒各收入1500，19项PASS；无限矿柱及跨队伍单车独占采矿保留 |
| 9. 320地图与2—4个真实出生点 | `scripts/battlefield_catalog.gd`、`scripts/map_data.gd`、`scripts/skirmish_setup.gd` | `tests/battlefield_profile_tests.gd`、`tests/skirmish_setup_tests.gd`、`tests/stage3_sim_tests.gd`；参战设置日志 (`artifacts/expansion_v5/stage3_skirmish_tests.log`)、真实四方设置 (`artifacts/expansion_v5/runtime/source/match_settings_four_slots.png`) | 2方对置、3方三角、4方环形；选项传递真实参战槽和出生点；经典地图固定2方；PASS |
| 10. 公平、可分级AI | `scripts/ai_controller.gd`、`scripts/team_vision.gd`、`scripts/simulation.gd` | `tests/stage3_island_ai_tests.gd`、`tests/stage3_sim_tests.gd`；阶段3完整日志 (`artifacts/expansion_v5/stage3_full_regression.log`)、真实运行报告 (`artifacts/expansion_v5/runtime/runtime_report.md`) | AI使用同一资金、购买、生产和视野规则；难度调整决策/战术。群岛困难AI正常资金387模拟秒完成船厂、运输船、登乘、跨岛卸载；PASS |
| 11. 独特机制兵种 | `scripts/faction_traits.gd`、`scripts/faction_support.gd`、`scripts/faction_trait_text.gd`、`data/rules.json` | `tests/faction_trait_tests.gd`、`tests/faction_traits_ui_tests.gd`、`tests/faction_revision_tests.gd`；阶段2机制日志 (`artifacts/expansion_v5/stage2_traits.log`)、完整回归 (`artifacts/expansion_v5/stage2_full_regression.log`) | 正典同域集群、重锤推进首击、铁钉减伤/脱战自愈、天翼EMP及既有维修/拖救/标定/蓄能；结算、显示、存档与原生路径一致；PASS |
| 12. 巨型手掌、max1且可重造 | `scripts/creator_hand_models.gd`、`scripts/unique_unit_rules.gd`、`scripts/simulation.gd`、`tools/creator_hand_catalog.py` | `tests/creator_hand_tests.gd`、`tests/creator_hand_world_tests.gd`、`tests/stage4_core_tests.gd`、`tests/creator_hand_input_tests.gd`；真实输入报告 (`artifacts/expansion_v5/runtime/runtime_report.md`)、正常RTS视角 (`artifacts/creator_hand/rts.png`)、抬手截图 (`artifacts/expansion_v5/runtime/source/creator_slap_windup.png`)、LOD重建 (`artifacts/expansion_v5/stage4_unit_bake.log`) | 20000HP，5指、12关节及13实体网格，无前臂/腕部；0.5秒准备后拍击建筑，活体和排队计入每玩家上限1，死亡后重造；专项PASS |
| 13. 独立教程战役 | `scripts/campaign_map.gd`、`scripts/campaign_controller.gd`、`scripts/campaign_ui.gd`、`scripts/paper_entry_menu.gd` | `tests/campaign_map_tests.gd`、`tests/campaign_flow_tests.gd`、`tests/campaign_ui_tests.gd`、`tests/campaign_real_commands_tests.gd`；最终完整日志 (`artifacts/expansion_v5/final_regression.log`)、入口和存档实机报告 (`artifacts/expansion_v5/runtime/runtime_report.md`)、战役运行截图 (`artifacts/expansion_v5/runtime/source/campaign_runtime.png`) | 唯一正典单关「无字桥补给线」，左上任务面板及定位按钮，7阶段目标由真实模拟事实推进；AI开启完整通关30项PASS，最终全套记录701模拟秒胜利、2次AI压力波、AI武装峰值4、最低AI资金100 |

## 已完成的测量与验证条件

### 经济

`economy_parity_tests.gd`为每个阵营分别建立相同的`dev`地图、seed7、一个精炼厂和一辆矿车，关闭赠车，指定同一矿柱和同样相对位置。矿车速度3、转速120、半径0.75相同；AI关闭，初始资金10000。每例以1/30秒推进75模拟秒，比较实际交付后资金增量，四例均约1500（浮点日志1499.99999999999）。这是同已部署矿车数量、矿点、距离和运输条件的结果，不包含开局造价差异，也不推导所有路线或拥堵情况下的收入完全相等。

### 制空

四个进攻阵营×四个目标阵营×原生/脚本两种调度，共32个移动目标配对。进攻方使用正常攻击指令，目标无机场且每tick横向位移；检查12模拟秒内击落目标，真实发射次数不超过8弹。日志最大为6次。另有8个末弹返航案例，验证弹尽开始返航后已经发射的导弹继续结算。共128项通过；结论限于该单架攻击夹具，不声称所有混合航空战局已经完全平衡。

### 群岛AI

`stage3_island_ai_tests.gd`使用`islands`、seed17、两方：玩家重锤与困难正典AI，双方正常起始资金。AI真实支付建造和生产费用，完成船厂、运输船、登乘并在敌岛卸载，首个成功卸载在387模拟秒；无补钱或免费兵，资金未变负。该结果验证实际跨岛链路，不能替代全部种子、阵营与难度的穷举。

### 原生、脚本、存档与渲染

阶段1—3各自完整回归的结果1 (`artifacts/expansion_v5/stage1_full_regression.result`)、结果2 (`artifacts/expansion_v5/stage2_full_regression.result`)、结果3 (`artifacts/expansion_v5/stage3_full_regression.result`)均为PASS。最终完整回归 (`artifacts/expansion_v5/final_regression.log`)与结果文件 (`artifacts/expansion_v5/final_regression.result`)也为PASS，包含战役AI开启的真实指令流程。阶段4新增手掌后，23个相关既有测试脚本通过；原生单位调度在主线程与工作线程各6002项通过，包含全部单位类型与中途保存/加载。LOD来源3622项通过，172个模板；运行时仍保留完整原网格。

保存校验接受海军目标域和实际有限负水面高度偏移，仍拒绝未知或重复域；唯一单位校验包含活体与预留。已有8方性能夹具接口保留，经典/开发地图默认无迷雾，新profile使用团队视野。四阶段修改前后源备份及分阶段日志位于`artifacts/expansion_v5/`；源码归档不是可运行的Linux包。

## 本次源码真实图形运行与GPU测量

运行报告 (`artifacts/expansion_v5/runtime/runtime_report.md`)与汇总JSON (`artifacts/expansion_v5/runtime/runtime_summary.json`)记录：真实主场景88项源码运行检查通过；手掌原生渲染22项、脚本渲染22项通过，覆盖实际鼠标拾取、移动、两根行走手指、抬手准备与建筑拍击。F5/F9检查保护并恢复已有玩家存档。该运行包含战役入口、任务面板、定位、存档与重开；完整通关另见最终AI开启测试结果。Shipping暂存程序实机检查 (`artifacts/expansion_v5/runtime/verify_expansion_export.json`)也为88项PASS，`debug_build=false`，没有把源码运行当作导出程序运行。

GPU采用预摆压力夹具：初始128单位+24已完成建筑，四个真实出生点，一名玩家与三名普通AI。AI生产、寻路、交战和死亡持续运行，没有固定人口补兵或规则/造价/武器修改。镜头距离85米、俯角34°，聚焦玩家起点+(13,13)；实际可见模型约33—38，**不是128单位同时在屏幕内，也不是普通经济开局**。

硬件为Intel Core Ultra 9 185H / Intel Arc MTL，Godot4.6.2、真实X11桌面、Vulkan Forward+。窗口与战场均1920×1080、balanced、100%渲染比例、完整模型与材质、2×MSAA、SSAO、默认景深及阴影。每图先预热5秒，再测30秒墙钟帧时间；预热不计入结果。

| 320地图 | 平均FPS | 帧时间p95 / p99（ms） | 模拟CPU平均 / p95（ms） | World CPU平均 / p95（ms） | 实际报告 |
|---|---:|---:|---:|---:|---|
| 翠林盆地 | 48.61 | 22.47 / 37.27 | 4.35 / 6.09 | 2.59 / 3.79 | forest JSON (`artifacts/expansion_v5/runtime/performance_forest.json`) |
| 纸城街区 | 52.46 | 21.12 / 21.80 | 4.29 / 5.80 | 2.48 / 2.97 | city JSON (`artifacts/expansion_v5/runtime/performance_city.json`) |
| 远海群岛 | 79.07 | 14.87 / 24.18 | 3.61 / 4.90 | 0.92 / 1.13 | islands JSON (`artifacts/expansion_v5/runtime/performance_islands.json`) |

这是当前源码在上述硬件、镜头与场景下的实测，不能保证其他机器/人数/地图恒定60FPS。GPU性能数据来自源码运行；独立Shipping程序另行完成88项运行验收。旧`performance_640_results.md`的42.24/34.06FPS来自此前画质与发行配置，只作为历史记录。

## 最终交付验收

| 验收项 | 当前状态 | 实际证据 |
|---|---|---|
| 当前源码最终全套`tools/test.sh` | PASS | 最终日志 (`artifacts/expansion_v5/final_regression.log`)、PASS结果 (`artifacts/expansion_v5/final_regression.result`)；包括原生工作线程、完整模型、全部新增专项 |
| 正典教程AI开启的完整真实通关 | 30项PASS | `campaign_real_commands_tests.gd -- --campaign-ai`，最终全套日志记录701模拟秒、stage7、win；真实付费建设/生产、修桥/运输、60秒守卫和总部反攻；AI武装峰值4、压力波2、最低AI资金100 |
| Linux Shipping重新导出与正式路径同步 | PASS | 4.6.2导出日志 (`artifacts/expansion_v5/stage4_export.log`)；暂存目录`artifacts/expansion_v5/runtime_export/`含二进制和相邻原生库，`debug_build=false` |
| 导出程序实机验收 | 88项PASS | 导出实机JSON (`artifacts/expansion_v5/runtime/verify_expansion_export.json`)、日志 (`artifacts/expansion_v5/runtime/verify_expansion_export.log`)、导出战役截图 (`artifacts/expansion_v5/runtime/export/campaign_runtime.png`)；菜单、四方设置、Wiki巨手、输入拍击、战役、保存读取/重开 |
| 当前manifest、校验与发行包 | PASS | 当前manifest (`artifacts/linux/manifest.json`)、包内文件校验 (`artifacts/linux/BUILD.sha256`)、归档校验 (`artifacts/PaperFront-linux-x86_64.tar.gz.sha256`)；解压后逐文件校验及程序/原生库/manifest一致性核对 |
| 解压后的独立程序 | 88项PASS | 解压实机JSON (`artifacts/expansion_v5/runtime/verify_expansion_archive.json`)、解压运行日志 (`artifacts/expansion_v5/runtime/verify_expansion_archive.log`)；从工程外目录启动，release模式、原生模拟/批渲染/同步全部启用 |
| 最终验收日期 | 2026-10-04 | Australia/Sydney；完整回归、源码/Shipping/解压实机验收与归档校验均通过 |

本次参战设置为本地玩家与AI，不包含真人联机。Windows/macOS、其他GPU与全面长期竞技平衡未在本轮作为已通过项目发布。

## 重新打包已验收的导出

重新打包时先完成导出、运行验收和当前manifest，再运行：

```bash
python3 tools/package_expansion_release.py --binary-dir artifacts/linux \
  --manifest artifacts/linux/manifest.json
```

工具不会执行Godot导出、运行测试、改写脚本/规则/素材，或调用manifest生成器。它复制已经提供的二进制、相邻`assets/native/*.so`、许可、当前Markdown文档与本轮日志/截图；源码归档和开发存档不进入证据目录。输入目录中的旧报告移入`historical_export/`，由`HISTORICAL_REPORTS.md`标明历史；未经显式提供的输入旧manifest也移入该目录。

默认输出为`artifacts/PaperFront-linux-x86_64/`与`artifacts/PaperFront-linux-x86_64.tar.gz`。包内`BUILD.sha256`覆盖除其自身以外的所有文件，tar/gzip元数据固定，相同输入内容重复打包生成相同归档哈希。`--binary-dir artifacts/shipping --name PaperFront-linux-x86_64-shipping`可打包另一个已导出的preset；许可默认从`artifacts/linux`读取，可用`--licenses-dir`指定。

打包流程验证使用`--dry-run --output-dir /tmp/...`：它完整复制、校验和归档，但输出使用`DRY_RUN-`名称，入口说明明确标为流程测试，不能作为游戏发行版。打包完成仅证明文件操作完成，不代表游戏验收通过。

运行源指纹：`d8e7b409f5dd15454762387e25a398d3c67e18f0ac250869fe2e2ff1b163046a`。程序SHA-256：`724f0a93c8a30c95a0cffc97141bc5804421a4a292649913bb5dd4386659d2a2`；原生库SHA-256：`215a09eeeed50f72aca0dc59a2d97323b9aec169d95ef2e9717d3cece0b6a9dc`。包内`BUILD.sha256`记录所有分发文件；归档哈希保存在压缩包旁，避免文档与归档哈希互相引用。
