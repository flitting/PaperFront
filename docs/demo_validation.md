# Shipping03 当前验收（2026-10-05 UTC，产品冻结）

当前游戏runtime为 `016ba55381d82833016996a2bc81ef821c6b7a12411303a9cb783d362632e73d`；源码/测试/工具为 `338971fb4ffef7d1fef55618b557387d0a273a5a1178e15ec4d45a7b18d3b4d6`；实际Shipping程序为 `e9f0b2ccaf3ba08e65a3d35c8d29a3b0d48762d322d1effa39cf9c2bf3c0f70e`；native为 `0836ac794036f4ed124c8f2048528beff68e1989db497908b36f32a69bbefcd7`。面向Linux x86_64、glibc2.38+、Vulkan。最终 C 包的目录、文件数、BUILD/归档SHA、工程外提取和普通启动闭包以 [最终交付回执](../artifacts/demo_20261004/delivery/DELIVERY.md) 为准；C阶段119文件、93报告，实际提取、两入口普通图形启动已通过；启动后精确闭包详见交付回执。产品冻结，无上传/公开发布/商店提交。

| 本轮实际结果 | 范围与证据 |
| --- | --- |
| Shipping35/35＋125/125；最低1100×700窗口125/125；六320地图72/72 | `runtime/candidate_acceptance_03/`、`ui/minimum_window_03/`、`navigation/load320_shipping03/`；最终报告实际路径/SHA由交付回执列明 |
| 原始115调用三个冻结区段组合覆盖通过 | full7原1–100＋suffix08原101–104＋suffix09原105–115，**非单次完整115 PASS**。raw full7 FAIL101和suffix08 FAIL105保留；只修测试观察器合法碾压权限/body重叠和runner的/tmp XDG隔离。另有音频测试退出清理修正，未改变产品runtime；[三段独审](../artifacts/demo_20261004/regression/composite_100_4_11_independent_review.json)27/27 |
| 实际付费战役教程65/65，528.033模拟秒胜利 | 正常AI、真实经济/修桥/分基地/运输/防守与反攻；[当前paid独审](../artifacts/demo_20261004/regression/suffix08_independent_campaign_review.json)29/29。原实际报告来自suffix08；其paid成功不将该完整区段失败抹成PASS |
| 当前16PNG视觉复核通过 | 普通主菜单/设置/教程/总部，以及持久己方总部投降败局和返回；没有自然胜利/平局像素验收，实际范围不扩成完整人工游玩 |
| 329.596秒源码立体声PCM自动记录/分析通过 | 未改音频类，5首音乐各2次循环、11次切换、最多1播放器；**UNLISTENED，非Shipping录音、非物理扬声器验收**；另实际16.254秒热混音47/47：音量零/全局静音、恢复、SFX与Radio半音量/零音量通过；同样未人工试听 |
| 9份实际许可输入与新PCK排除核对 | 含GNU静态libstdc++/libgcc版权及Runtime Library Exception、Godot/godot-cpp、OFL字体、MakeHuman仅CC0图形、项目原创来源；[许可输入](../artifacts/demo_20261004/delivery/license_inputs_shipping03.json)。玩家资源排除旧在线TTS/导入映射、开发参考、用户参考图与MakeHuman GPL应用代码；最终包notice字节由BUILD/提取另核 |

上述未带链接的证据路径相对 `artifacts/demo_20261004/`；最终回执绑定各实际报告，避免把待完成普通启动或补充报告当成通过。玩家解压后运行`./start.sh`；P暂停/继续、Esc打开菜单后可选择返回主菜单、胜败界面重开、F5保存/F9读取，装载选乘员、卸载选地点。

本轮同画质源码压力FPS为森林46.077548、城市46.933174、群岛80.109039：1920×1080、balanced100%、完整模型/材质、SSAO/DOF/阴影/MSAA2×、128预置单位/24建筑、1名人类＋3个Normal AI。它是固定单轮压力场景，非正常开局、稳定60FPS或性能增益。96窄路三轮62/91/96，对照94/49/63，仍UNSTABLE；不声称改善。碰撞是轮换抽样，局部导航为每tick累计与查询前停止阈值，不能扩成全轨迹/全部wall时限证明。其他硬件及人工听音仍未验收；普通启动/退出的实际StringName与对象/资源/RID范围以当前回执披露。

本机只读模型缓存确认6.1 Sol支持Ultra、6 Astra支持High；Alpha没有可验证映射，未自行替代。缓存不证明当前线程实际运行设置。

---

以下原文均为此前版本或阶段的历史记录，按当时时间与身份保留；其中“当前”“待完成”及单次115结论仅属于各历史版本，不替代上面的Shipping03状态。

# Paper Front Demo 验收记录

更新：2026-10-04 22:24 UTC。截止：2026-10-05 01:00 UTC（Sydney AEDT 12:00）。当前持续迭代；已验收可启动版本保留，尚未宣布整个项目最终交付。

范围沿用现有 Godot 4.6.2、四阵营、六张 320 地图与单关教程。测试使用新配置；玩家包A的两次普通启动曾因测试helper相对XDG路径把缓存写入包目录，原归档与runtime字节正确，启动后目录闭包失败已保留。修正为绝对包外XDG后，包B两次实际启动与启动后52/52文件精确核对通过。原有v6、候选01和用户存档保留。环境中的`.git`没有可用仓库元数据，原始SHA与失败尝试保存在`artifacts/demo_20261004/`。

## 最新可启动版本（22:24 UTC）

`release/PaperFront-Demo-linux-x86_64/`及相邻归档已生成，入口`start.sh`；程序d11ba28a、native0836ac79、runtime05ba0153、source0e4b7f07。包B归档SHA`55ca5944ae83323273c0ffb0ccd94c8dcfc78d84f793a6fabe84e1c0b0fd9212`，52文件；需要glibc2.38+与Vulkan。实际工程外启动6.086948wall秒，tools/run最终路由6.085179秒，均180帧后exit0，绝对独立配置，日志按原SCRIPT ERROR/ERROR/ObjectDB/资源/RID规则干净；verbose仍有11个StringName退出记录。程序/native/内嵌PCK/start.sh从包A至B全同，B启动后发布与外部两个目录均52/52无额外、缺失或修改文件。实际证据`runtime/final_package_B/`及独审`transport/shipping_review/final_package_A_B_independent_review.json`。

对应新source完整原115/115已通过，独审25/25；真实paid教程65/65，538.733333sim胜利，玩家与AI账分别闭合至4760/4320。局部导航1178µs是每tick累计峰值，1000是下次查询前停止阈值，末次查询可跨过；budgets_legal只验证配额与并发。碰撞逐tick轮换抽样，不是所有轨迹证明。Shipping35/125、1100窗口125、六320图72和新版18图像素已通过，三图同画质源码压力45.707/46.994/80.998FPS。96窄路仍五FAIL一PASS，UNSTABLE。完整身份/日志/指标见attempt5、candidate_acceptance_02、minimum_window_02和load320_after_yield_reset。

新玩家整体视觉及离线音频接缝/响度审查继续。当前工具不能可靠地主观试听，不会把PCM或检查数量当作听感判断；拟只补首屏推荐教程及常规开局两阶段放置说明，未合入前不能当最新版已验收。以下早期表格和时间章节均为历史证据，不替代本节所列版本。

## 首阶段已验证结果及边界（历史）

| 项目 | 当前结果 | 证据与边界 |
| --- | --- | --- |
| 主菜单、设置、结算、重开、回首页、真实退出 | 80/80 | `runtime/demo_menu_flow_after_shutdown.log`；真实 GUI 信号、配置持久化与暂停状态恢复，headless 功能验收 |
| 加载 0.98 时退出 | Start 8/8、Load 9/9 | `shutdown/verification.json`；基线 5/8、7/9，修复后真实进程结束，退出期间配置字节不变、音乐流为空、战场不恢复渲染 |
| 源码 Demo 运行检查 | headless 与实际 GPU 均 35/35 | `runtime/demo_source_after_shutdown.json`；实际原生内核调用、PCM 资源和五个播放场景，不代替 Shipping、正常战斗胜利或完整教程 |
| 非默认设置冷启动 | 精确字节保存 | `runtime/preferences_startup_fixed.json`；镜头初始化不再通过滑块信号提前重写画面配置 |
| 音频规则与素材 | 983/983、68 PCM 审计通过 | `audio_headless_validation.json`、`audio_pcm_validation.json`；新增 25 个音频文件和两份清单离线重建字节一致，航空开火首尾点击边缘已修复 |
| 实际引擎混音 | Dummy 及桌面 PulseAudio 驱动均 10/10 | `audio_mix/headless_clean.json`；Master 输出 PCM 验证音量、静音、恢复及场景切换，桌面驱动结果见 `audio_mix/desktop_verification.json`；不证明物理扬声器可听或人工试听 |
| 音频发行排除 | 导出探针 0 禁止项 | `runtime/audio_pck_probe_inspection.json`；Godot v3 PCK 1,945 项，无历史语音音频、导入或映射负载，该探针不是最终构建 |
| 设置与手所属标记视觉 | 独立 GPU QA 通过 | `ui/capture_identity.json` 和 `audit_visual.md`；1100×700、1920×1080、实际全屏 3072×1920，胜败地形完整、四种手所属色可读；未代替最终 Shipping 截图 |
| 固定小型导航控制 | 隔离几何 150/150；实际原生几何 9,372/9,372；首尾各 496 worker 连接合法 | `navigation/geometry_pruned_guard_attempt4.json`、`navigation/control_verification.json`；2 米合法口与 1 米非法口分开，真实 worker、原生/脚本倒退与前车保护，不证明 96 辆拥堵公平性 |
| 真实付费教程 | 65/65 | `campaign_live/verification_attempt2.json`；正常 AI、原时限、541.33 秒模拟胜利，修桥支付 400、分基地支付 900、两队收支残差 <1e-6。首轮测试资金快照引用缺陷已修复并保留原证据 |
| 最新合并版运输与海军 AI | 129/129；AI 原450秒内通过 | `transport/final_20261004/post_coast_fix/`；默认58/84.58s、原生59/82.02s（实际dispatch、脚本实体tick0）、真实worker12/12.99s；原STEP1 AI于415模拟秒实际登船与卸载、资金50。4任务的84项来源SHA全相等且前后无变化，严格日志无错误或泄漏 |
| 测试入口 | 八个假进程控制通过 | `tools/test_runner_selftest.py`；当前清单 115 次 Godot 调用。即使 exit 0，也拒绝 SCRIPT ERROR、ERROR、对象或资源泄漏；完整第一轮停于第6项AI失败；第二轮越过AI后在第8项旧假乘客缺pos被严格捕获，只补回原坐标79/79通过，第三轮通过前32项后，第33项旧worker快照夹具缺字段被严格捕获；只补完整schema后260/260通过，第四轮从第1项重新运行并115/115通过，源码/元数据/helper前后不变 |
| 本轮实际 GPU 功能与同画质压力 | 125/125、35/35；三图完成 | `runtime/source_gpu_attempt2/summary.json`；5 个任务 runtime SHA 完全一致。森林 46.20、城市 46.87、群岛 80.44 FPS，完整模型与材质保留，不宣称稳定 60 FPS或历史比较性能提升 |
| 打包器安全边界 | 58/58 | `packaging/policy_fixture_results_licenses.json`；当前9份许可、27文件；真实小文件测试保留旧目录、tar 与校验文件，覆盖六次 rename 前错误、六次 rename 成功后中断及失败恢复时保留唯一旧备份，不代替实际 Shipping |

上述证据路径相对 `artifacts/demo_20261004/`。每轮 JSON 记录源码、规则及原生库 SHA；历史失败保留，不把来自不同源码的数字合并成一次验收。

## 尚未通过的关键项

固定 48×48、96 辆半径 0.75 米坦克、6 格长障碍带和 2 米宽合法开口，在真实异步 worker、1/30 秒步长、每 tick 1 毫秒 worker yield、600 秒模拟上限下：基线 0/96，第四轮完成 56/96，第五轮完成 44/96、穿口 45/96。连续矩形碰撞与合法 worker 锚点修复后的第六轮完成 71/96、穿口 73/96，62.18 秒 wall。上述三个近期96回归均无插桩、抽样无静态违规或单位重叠且源码前后一致；第六轮虽改善，但仍未达到96/96，本项失败。当前最好完整可重放源码/素材副本保存在 `navigation/best_verified_so_far/source/`，哈希清单在同目录上级，不作为最终玩家包。见 `navigation/narrow_96_pruned_guard_attempt4.json` 和 `navigation/narrow_96_effective_yield_attempt5.json`。有效路点与首步修复只证明此前92项；连续几何一版150项与首尾各496条worker控制通过，不能据此声称群体拥堵改善。1 米非法开口保持不可通行，未减小半径或放松碰撞。路径复用隔离改动退步到48完成/50穿口，已拒绝并恢复71版本。仅裁剪未用naval预热后的第八轮61完成/67穿口，抽样安全为0、原600上限不变；ground数据全SHA相同，不能据单轮数值把波动归因于预热改动。同fc5源码第九轮复测96辆全部完成/穿口，在573.033模拟秒结束、wall56.290秒；该轮严格无错误，抽样重叠/静态违规为0。两轮12项源码/库/起点/目标身份完全相同，但61→96波动明显；不能称为稳定通过，不能删除61轮，也没有证据将下降归因于naval缓存裁剪。当前源码保持冻结、第四轮115/115完整清单通过；原71完整副本与navigation/best_96_single_pass/source均已独立保存，后者三方哈希全等、明确标记UNSTABLE，不能当商业稳定性通过。

补足原格网缺失的合法狭口连接增加了初始化成本。森林固定 seed 73026 的原版 setup 6.24 秒，第一版补点 20.18 秒，裁剪后 9.18 秒；额外节点 55,082→11,230，setup 静态内存 153→109 MB，原版约 91 MB。四阵营真实坦克到附近矿点的 9 项合法路径检查通过，但六图成本和路径 53/54；群岛一个路径合法性汇总失败已定位，四辆仍全部到达：真实矿点圆角擦边可被 0.4 米离散采样漏掉，下一步重新采样后暴露；原生与脚本判断一致。已通过并合入连续圆扫矩形的精确补充，保持实际半径、障碍占地和原预算。实际合并版群岛单图9/9，四车在10.267模拟秒全部完成，路径/位置/移动步合法。整套六图后续已重新运行，结果如下。初始化预热已单独从9裁剪为全部6个配置地面半径，保留巨手1.45，未裁剪阵营或当前未上场单位。六图改动前后各72/72，原20秒时限的24辆坦克实际完成，所有6个地面mask、节点、边和补点位置逐字SHA相同。本次成对setup毫秒：forest9442→7012、desert14191→11970、snow10023→7726、city7010→4540、random7935→5217、islands6664→5489；单次减少15.6%–35.2%，不作为稳定统计或GPU性能收益。原sampler8850对照保留，新的连续几何77项确实收紧旧漏角且没有放松旧false，navigation70/70、原nativegeometry9372/9372与新150/150均通过。这是 headless 初始化与寻路测量，不是渲染帧率提升。

完整付费教程保留正常 AI、真实建造/采矿/修桥/分基地/运输/防守/反攻的原时限，不注入资金、瞬杀敌人或强置阶段。已通过独立复测，费用快照使用实际复制的数组，资金证据和实际事件分开核验；不代替群岛 AI 海军或 96 车压力验收。

全量 `tools/test.sh` 第一轮实际执行到第 6 次调用，群岛 AI 在原 `islands/seed17/hard/450秒` 控制中建船坞、造运输船成功，但没有登船/卸载，因此停止。全部 2,184 项运行文件 SHA 前后一致，失败记录见 `regression/attempt1/summary.json`；本轮没有完整清单通过结论。完整的会话前源码对照也在同一 450 秒断言中失败。实际事件追踪显示 7 次登船请求，船在 361 秒到达选定岸点；步兵到该陆点约 79 米且不可达。选岸代码验证了船的水域连通，却没有验证步兵到岸点的陆域连通；原局部搜索还漏过本岛既存合法岸点。只修改 naval_operations 的陆域筛选和缓存岛屿边界后备搜索，原 D2.97、quarter 地形条件、完整船体、渡岸碰撞、资金和地图保持不变。在冻结隔离源码的原450秒控制中，实际415秒完成登船与卸载，已合入运行版本。见 `transport/ai_islands/causal_analysis_verified.json`；最新导航合并后的四项完整运输/AI专项已通过，见 `transport/final_20261004/post_coast_fix/`；仍不能替代115次全量清单。第三轮最新完整清单在第6项再次通过原450秒AI，前32项全部exit0且严格无错误；第33项手写7×7 worker快照未提供extra_positions/extra_cells/terrain/land，虽然打印256通过，实际脚本错误仍使入口停止。只补齐平地快照schema，保留节点24、三次revision和全部四项重叠断言；定向测试260/260、严格日志与源码SHA通过。原失败、补丁与定向日志分别保存在regression/attempt3、navigation/worker_snapshot_fixture_repair和regression/worker_snapshot_targeted/verified_summary.json；第四轮从第1项完整重跑，在20:26:47 UTC结束，115/115次原始调用全部exit0且严格无错误/泄漏，源码content/metadata与三份helper不变；runtime884f、sourcef42，summary SHA59ea1f94，1317.21秒wall。当前付费教程另以正常AI/liveworker完成65/65胜利、538.40模拟秒、113.97wall，副本保存在regression/attempt4/paid_campaign_actual.json。旧源码隔离后续第7–22项中15次调用PASS、第11项证据输出目录失败只作为历史诊断，不能合并为本轮全量通过。

源码真实 GPU 125 项与 Demo 35 项已通过，同画质三图压力已实测。首轮假入口失败来自验证器只发送坐标而没有移动实际光标，按钮 hover 为空；focus 单变量仍失败，warp 光标单变量后 Wiki 立即正常打开。只修显式验证器的真实鼠标前置，不改游戏按钮或原 125 断言，失败图/日志与三项对照分别保留。待完成完整回归、最终 Linux Shipping 实机运行、最终几何修改后的性能复核、最终 PCK 审计及工程外解压运行。性能条件固定 1920×1080、balanced、100% 3D 清晰度、完整模型/阴影/SSAO/DOF/MSAA 2×、128 单位、24 建筑、4 方 normal AI；本轮森林/城市/群岛分别 46.20/46.87/80.44 FPS，P95 帧时间 23.94/23.82/14.90 ms；此前 45.34/48.89/79.79 FPS 仅为历史同夹具参考，非同一时刻 A/B。全部绑定 bd709/e28 导航版本，后续修复后须复测。

## 素材与发行

新增背景音乐和无线电应答由 `tools/generate_demo_music.py` 与 `tools/generate_demo_radio.py` 原创合成，没有外部录音或样本，使用 CC0 1.0。原项目素材、Godot MIT、godot-cpp MIT、字体 OFL、MakeHuman CC0 图形网格的逐项记录见 [署名与许可](demo_credits.md)。历史在线合成语音没有本项目可确认的商业再分发记录，玩家包排除其音频与导入负载，原创中文文案保留为字幕。

玩家包计划存放于 `artifacts/demo_20261004/release/PaperFront-Demo-linux-x86_64/`，入口 `start.sh`；目录当前尚未成为已验收发行物。打包脚本使用运行资源白名单、当前报告、许可和原创来源记录，拒绝旧语音/开发参考负载并保护旧 v6 路径。最终交付会包含归档 SHA、完整文件 SHA、实际解压/native 加载/启动结果和明确已知问题。本次未公开发布、上传、采购或提交商店。

当前 ELF 只读核对显示原生内核引用 glibc 2.38 符号（`fmodf`、`__isoc23_strtoul`），Godot 主程序引用最高 2.28；整个包因此需要 glibc 2.38 或更新版本。记录在 `runtime/elf_dependencies_pre_final.json`，最终内核重建后还须重验。未进行其他发行版或旧 glibc 兼容验证，不将本机启动当作全平台保证。

新增玩家包检查排除 16 份仅用于开发视觉基准的 `golden_visual*.json` 和两份已合入运行目录的阵营生成中间 JSON。仅修改 Shipping 导出，保留开发构建的视觉工具。此前音频探针虽无旧语音负载，按新增开发数据规则仍有 18 项需排除；最终 PCK 必须按当前规则为 0。真实运行依赖的地形缓存保留。

## 型号只读核对

本机模型缓存与 app 可调用 schema 列出 `gpt-6.1-sol` 支持 `ultra`，`gpt-6-astra` 支持 `high` 等努力级别。没有名为 Alpha 的可验证型号，不能将 Astra 当作 Alpha；未自行替换。缓存只证明本机所列支持能力，不能独立证明当前任务的实际运行设置。原始只读结果在 `model_availability.json`。

最新包许可还补齐实际静态链接的 GNU libstdc++/libgcc 运行库说明与 GCC Runtime Library Exception；本机 GCC13版权文本逐字节保留，编译器应用程序未附入。打包器最新9份许可、27文件实质fixture58/58，见 `packaging/policy_fixture_audit_licenses.md`；当前native0836对应compiler record已刷新并重新核对编译器、准确版权文本、runtime archives和link命令SHA；若之后重编译须再刷新。

## 当前实际候选包进度（20:30 UTC）

Linux Shipping候选已实际导出到`artifacts/demo_20261004/candidate_shipping_01/`。程序SHA1145ac7d…、外置native0836…、内嵌manifest与staging字节相同，runtime884f与115完整回归一致；PCK1930项，历史语音/导入/映射和18项开发JSON禁止项为0，导出日志无警告。实际GPU Demo35/35已通过，release/debug=false/development=false、指定原生库实际调用、默认balanced/100%/SSAO/DOF/MSAA2×和5个music场景均验证；125扩展及同源码3图压力仍在串行验收。此目录不是最终玩家包，尚须完整候选验收、说明/许可打包、工程外解压/校验与普通启动。旧v6保持完整。

## 已可启动的首个玩家候选包

`artifacts/demo_20261004/candidate_release_01/PaperFront-Demo-linux-x86_64/`、相邻tar.gz及sha256已实际生成，34个白名单文件；程序1145ac7d、native0836、runtime884f均与Shipping验收同一字节。目录BUILD校验、归档校验、工程外`/tmp/paperfront-candidate-extracted-01`解压全部文件一致。工程外从`/tmp`调用解压版start.sh，以全新XDG、不带验证/fixture开关正常启动，180帧后引擎退出，6.08秒wall、exit0、严格日志无错误/泄漏；见`runtime/candidate_package_01/`。程序入口/教程/结算/重开/返回/实际GUI退出另由同程序35与125项验证，普通180帧启动不冒充逐项人工操作。当前归档SHA414f8efc…668e0，完整SHA在相邻校验文件及file_verification.json。

同runtime当前三图压力为森林45.10、城市46.34、群岛80.09 FPS；1920×1080、128单位/24建筑、四阵营/3正常AI、全部原模型/材质与balanced100%/SSAO/DOF/阴影/MSAA2×不变，单轮结果不宣称较旧版性能提升。Shipping35/125均严格clean，所有5任务源码/库/manifest/helper前后一致，见`runtime/candidate_acceptance_01/summary.json`。

独立复核完整115原参数、顺序、log SHA和GNU grep严格规则24/24通过；当前付费教程29项独立核查通过，538.4模拟秒胜利、两队账目闭合，玩家4000+10000−7440−400−900=5260，AI4000+8500−8060=4440。AI receipts已计入ordinary step支付，不能再双扣。碰撞仅逐tick轮转最多6单位、95621 position/41351 pair抽样，不声称所有轨迹或每次wall预算上界。见`regression/attempt4_independent_*.json/md`。

最新14张Shipping/同源三图实际PNG已独立逐张复核，无新增明显视觉FAIL；中央反馈字体11logical偏小，已准备仅调14的窄改，尚未应用。本轮后续继续自然两/三车退让因果诊断；首包与96/71完整来源快照均保留，未追加让路补丁。


## 新版当前验收窗口（2026-10-04 21:48 UTC，完整回归进行中）

当前工作区与Shipping02的runtime为`05ba0153f8b865e7520ceea92104f3bb3ba85b1499d9e5b8d04d9bb4542b4aba`，完整源码/测试/工具身份为`0e4b7f07cdcb65648389d8cde4ee530f55750d6479cbf6477dbabce81987a741`。程序`d11ba28a040c73958da08d881dd91a9fe137b94a79819acb4bfd4e9814e207fe`、原生库0836不变，manifest9032。只合入成功让路指令的clock/anchor两字段重置与HUD字号14；launcher优先最终包/已验收候选、中文Esc与结果重开说明同步修正。新source必须使用attempt5完整回归结果，不能借用旧attempt4的115结论。

新版targeted现有4组检查271/271、实际Shipping35/35与125/125、同binary1100窗口125/125、两尺寸font14像素及最新版14图审查通过。独立source三图压力45.707/46.994/80.998FPS，质量/完整模型保持，仅单轮测量。新六图72/72、24坦克原20sim秒内全部完成，路径/位置/步进合法，source/content/metadata前后稳定。证据在`ui/font14_targeted/`、`ui/minimum_window_02/`、`runtime/candidate_shipping_02/`、`runtime/candidate_acceptance_02/`、`navigation/load320_after_yield_reset/`与`audit_visual.md`。

自然让路旧时钟首路线被清机制在原生/脚本各复现一次，隔离两行对照与12小控制通过；原96三轮reset完成62/91/96，control94/49/63，五FAIL一PASS，仍UNSTABLE。源差异、原600/1ms/noTrace与六轮抽样几何0均独审；顺序样本不足以宣称吞吐因果改善。后续相互占用让路目标线索仅只读，尚未证明持久死锁，未叠加新修复。完整115正在冻结source从1运行（attempt5），完成前不声明新版最终通过。已接受candidate01和旧v6均保持原字节，final玩家包与普通启动闭环在完整回归后执行。


## 新版完整115通过（2026-10-04 21:57 UTC）

`regression/attempt5/summary.json`实际PASS115/115，21:33:43.699834–21:55:52.818902UTC，1329.118848wall；runtime05ba0153/source0e4b7f07与Shipping02一致，changed_sources/source_metadata_changes/helper_changes均[]，不是诊断后缀合并。完整summary SHA`212095610d56143916ec3d64a7dd9406407c585b0f62fb9149a9aa4ebfd9a9f2`。新版真实付费教程65/65于538.733333sim实际胜利、114.122651wall，原报告复制到`regression/attempt5/paid_campaign_actual.json`，SHA`97ae94994793f3252768902f64e3aec007a81cf11bc50a4aa28aa965cbd60429`；原群岛AI450sim控制在415sim完成board/unload，本轮合法资金约0浮点余差。独立115与新paid账目审查继续，玩家包与普通外部启动回执仍待完成。字体14实际两尺寸与14图通过，96三轮仍UNSTABLE。
