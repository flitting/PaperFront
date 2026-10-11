# 2026-10-05 模型、交互与地图重建：验收与交付

> Historical evidence for the dated build/experiment only; not v0.8.0 acceptance. Generated `artifacts/` evidence is local output and is not bundled with the source repository. Current checks: [release notes](release_notes.md).
> 此文仅保留对应日期的实验或旧工具回执，不代表当前发行版验收。

**手与六地图独立视觉已PASS；完整功能清单已覆盖，Source与实际Linux Shipping真实GPU全流程各125/125通过。** 本轮新大地标的真实保存/载入缺陷已修复；正式Linux目录已从同一已验收staging完整替换；工程外解压全部文件校验、同核心字节的实际正常GPU启动及正式目录全文件一致性均通过。归档digest只保存在外部 `.tar.gz.sha256`，不嵌入随后被本归档再次复制的报告。v5的88项实机记录及旧帧率是历史结果，不能替代本轮。

## 五项要求与当前状态

| 用户要求 | 实现/证据 | 最终验收范围 |
|---|---|---|
| 巨手按用户两张三视图调整 | 旧13块刚体拼接已撤销。现使用真实解剖连续皮肤 GLB、16骨 Skin / Skeleton3D；CPU/GPU 蒙皮专项日志 (`artifacts/expansion_v6/creator_skinning_gpu.log`)记录17项通过，最大顶点误差约0.0624mm。压碎效果26项及来源元数据7项有各自日志。 | **第二次连续真人手独立复核 PASS**：拇指、两指前伸、另两指内卷和近水平铺压的主要形体均接受；连续皮肤最终审阅 (`artifacts/expansion_v6/hand_reference_review_final.md`)绑定新图片 SHA。静帧复核仅证明可见形体；Source与实际Shipping主场景125项全流程另验证真实鼠标、步行、windup/压碎/恢复及保存载入，均通过。 |
| 右下巡逻格改为装载/卸载 | 两动作菜单、载具/乘员双向点选、续载、空位/人数提示与合法卸载校验已接入。headless 真 GUI 输入 (`artifacts/expansion_v6/ui/transport_input_headless.log`)与GPU 真 GUI 输入 (`artifacts/expansion_v6/ui/transport_input_gpu.log`)各23项通过。 | headless和真实GUI专项通过；Source与Shipping125项全流程均通过，实际记录见下表。 |
| 船坞直接全海面建造 | 全部占地为水，仍有前置/建设权限及出航、岸点通航检查。船坞专项汇总 (`artifacts/expansion_v6/shipyard_v6_summary.json`)记录159项全海船坞、54项真实 Vulkan 输入、旧档/新图 AI 跨岛与大船过桥检查。 | 最后地图回修后109桥航道、159四阵营产船/跨岛/存档通过；Source与Shipping全流程通过。 |
| 建造栏随所选建筑唤起，未解锁隐藏 | 总部/分基地显示已解锁常规与防御，生产设施只显示本设施项目；仅选单位/非生产建筑时隐藏。工兵在右侧独立部署。科技可见日志 (`artifacts/expansion_v6/ui/tech_visibility.log`)19项通过；已有 UI101、海军 HUD57项定向结果。 | Source与Shipping真实鼠标点总部→可造电站→选单位隐藏的实际全流程均通过。 |
| 先 AI 两图，再制作与独立差距校验 | 六地图12张 AI 参考及24张实际 GPU 四视图已生成。提示词/来源见[生成记录](map_design_v6/generation_manifest.json)。 | **最后一轮独立视觉复核PASS**；最终逐图报告 (`artifacts/expansion_v6/map_reference_review_final.md`)绑定当前24实图SHA与参考身份，接受连续地貌、单帘高差瀑布、工坊/钟楼/村落、港区与堡垒主要形体。明确可接受的纸艺细节与布局微差；不声称逐像素复制。旧NO PASS文字/36SHA保留，旧失败24像素未保留。 |

上表专项通过只证明各自记录的输入、模拟或几何检查，不等于外形与参考匹配，不等于所有五项已经正常，也不等于当前可发布。

## 当前操作与建设语义

- 选择己方已完成总部/分基地才呼出常规/防御建造栏，两类订单保留独立队列；选择兵营、工厂、机场或船坞，只显示该设施的单位卡，订单进入所选设施的队列。未选对象、仅选单位或非生产建筑时，下方栏隐藏。
- 科技前置、阵营和生产资格未满足的项目隐藏，总部不可重造。资金暂不足、队列占用或机位暂满时，已解锁卡保留费用与状态。工兵用右侧「部署分基地」选址，退出后可以重新选址/取消；不唤起主建造栏，抵达后施工并随进度付款。
- 右下第三格打开「装载/卸载」两个动作。装载支持选载具点步兵、或选步兵点载具，有空位可继续补员；可载工兵与反甲兵。卸载指定合法空地或登陆海岸。U 保留指定卸载、L 保留运输机降落、B 保留返航补给；也保留步兵右键载具与当前位置卸载。
- 船坞全占地直接在海上建造，需可用出口和往返岸点航道；旧档保留历史岸边船坞及规则快照。运输船在合法海岸登卸步兵。
- 巨手在地面行走，武器当前攻击域为地/空/海，价格、生命、前摇、伤害与前置读取 `data/rules.json`，见[自动生成目录](faction_catalog.md)。当前16骨是美术资产实现，不是玩法限制；不能再以13网格/12关节断言验收新模型。

## 真实手部资产来源

当前 `assets/creator_hand/creator_hand.glb` 从 MakeHuman Community 的 CC0 图形基础网格提取手部、裁闭腕口并重新蒙皮，原完整人体网格不作为运行资源导入。使用的是**图形 mesh，不是 MakeHuman 应用程序代码**。当前连续皮肤与16骨资料见[模型来源说明](../assets/creator_hand/README.md)、[rig.json](../assets/creator_hand/rig.json)、[来源/校验记录](../assets/creator_hand/source_provenance.json)。官方来源提交为 `a8bc2d54ff0ac92e78ff71431b1023eda42bf482`；原始资料位于 `tools/source_assets/makehuman/`，随包的[CC0资产许可](../assets/creator_hand/MAKEHUMAN_LICENSE_ASSETS.md)与[另一CC0全文副本](../assets/creator_hand/MAKEHUMAN_LICENSE.md)均为CC0法律文本。上游仓库的应用程序AGPL/图形资产CC0分界说明及其固定提交哈希保留在 `tools/source_assets/makehuman/LICENSE.md` 与来源记录中；未纳入应用程序代码。

旧分节模型的首次审阅 (`artifacts/expansion_v6/hand_reference_review.md`)与连续皮肤的再次审阅 (`artifacts/expansion_v6/hand_reference_review_final.md`)分别保留；它们审阅的图片身份不同，不能互相替代。后续同名截图被覆盖时也不能沿用旧审阅结论。

## 地图工作流与必须复核的差距

六模式为 `city`、`random_city`、`forest`、`desert`、`snow`、`islands`。用户原始手参考在 `docs/revision_v6/`，六图 AI 小地图/全景在 `assets/map_design_v6/`，生成需求、提示词和记录已齐备，无需重新补造生成过程。以参考图主要水系、分区、地标形状及相对比例指导重建；保留可建出生区、资源公平与运输通道。

首轮图已有城市两岸分区、公园与楼层差异、群岛四主岛与中央月牙岛；实际 panorama 是真正的倾斜3D。仍未达到尽量1:1重建的主要问题如下：

| 模式 | 首轮必须回修的大差距 |
|---|---|
| city | 低宽市政厅/尖塔的形状、紧密旧城街坊、商务楼体差异、独立可辨铁路货港与公园结构。 |
| random_city | 喷泉平台半入河水，稀疏城镇、不同方向桥口、左湾古堡/老城与东南港仓/铁路区。 |
| forest | 北部瀑布、湖内小岛、连续山脊与东岸山壁、自然弯路/溪流，伐木工坊和护林塔结构。 |
| desert | 连续峡谷台地、沙丘和干沟、绿洲围合庭院/小池、西岸门洞遗迹及考古基址。 |
| snow | 大湖树岩岛/连片冰缘、连续雪山脊、尖顶钟楼与村庄、铁路货运点和可读积雪树形。 |
| islands | 中央破损石堡体量、自然岸坡/礁石，四岛不同港湾/岩峰/路径及灯塔/船骸识别点。 |

纸艺描边、小枝叶、水波和岩石微纹可简化；上表的大轮廓、地标类别、空间层次或穿水错误不能按细纹差异接受。最终报告必须绑定新截图/源身份，不能用功能测试或素材数量覆盖视觉 NO PASS。

## headless 完整覆盖与真实问题修复

本轮已按 `tools/test.sh` 清单覆盖 **93个循环测试 + 8个附加测试/工具 = 101项检查**；该脚本另有1次editor import，即102次Godot调用。过程中没有从头重复已经通过的逻辑，失败后保留原始日志、修复对应验收项并从下一项接续。精确逐项覆盖、输出哈希和原始日志见回归汇总 (`artifacts/expansion_v6/runtime/regression_summary.json`)。

- 实际修复：HelpBody顶部已有正确U/L说明，但末尾仍写旧的U当前卸载、L卸载/登陆、船厂跨岸与工程兵旧卡片操作。只修正帮助文字，并验证U指定卸载、L降落、装载/卸载双动作和双队列。修后Faction traits UI39项、UI101项、right dock130项、真装卸输入23项通过。
- 测试适配：森林现在有真实山壁，不能再断言全图没有崖线；新测试同时验证真实山壁、平缓岸面无伪线与真实陡岸。连续手保留1原始MeshInstance3D、16变形绑定和独立Skeleton，不能再套用零GeometryInstance或纸漆身份字段假设。原始单mesh包含皮肤/指甲材质surface，工具逐surface验证全部有限顶点/法线，indexed三角按实际indices统计；其他模型的原材质、身份漆及单surface检查保留。
- 当前结果：手362项、世界Skin15项、压碎26项、metadata7项、全海船坞159项、旧档AI7项、最大船体桥航道109项、native unit tick6002项及threaded6002项全部通过；六图2/3/4方map检查0失败。战役真实命令含AI30项胜利，景深655项、完整模型8292项、阵营视觉4299项通过。
- 几何工具：116模型、159原始surface、1,054,966有限顶点、362,896真实三角、1064炮口案例与38回收案例通过。6份失败尝试日志原样保留（5类首错与一次适配首试），不将历史失败声称为零错误。

该覆盖完成于最后一轮地图视觉返工之前。手、UI、规则与native保持当前已验收内容；地图/环境后续变化须新import并定向重验地图、环境与大船航道。此前运行源身份为 `3a4e2137d508f69b85c0a89f84ff76e618046bb07f69a072a5966811af2f3955`；只修HelpBody后的身份为 `08b3b780c710572cc2d95c93d3d97eb840fdaecd743c3ec0cd60a91dc9249d68`，唯一差异是 `scripts/paper_hud.gd`。它们是阶段证据，不是待发布地图最终身份。

## 最后地图回修后的真实存档修复与定向验收

最后一轮地图回修引入实际较大的堡垒、工坊、钟楼、绿洲村与门洞碰撞占地。定向全海船坞验收发现四阵营与旧岸边快照均无法载入：普通废墟的旧 `half.length() <= 6` 校验拒绝了这些真实大地标，首次该段为158检查/10失败。这是**新增地图造成的实际保存/载入缺陷**，不是旧测试适配；最小诊断 (`artifacts/expansion_v6/runtime/map_save_failure_diagnostic.json`)与首次失败原日志 (`artifacts/expansion_v6/runtime/map_repair_rechecks.log`)保留。

现在普通废墟仍受原6米半径上限约束，仅v6对应模式的已命名house地标按实际每轴上限有界校验：stone_fort10.5、sawmill6.5、bell_tower7.3、mesa_gate6.8、oasis_village5.5。保留有限数、正值、类型和完整旋转占地在地图内的检查；没有缩小真实碰撞half、没有拆虚假代理迁就旧限制。过大、NaN、Inf、未知archetype、错误kind、非法边界及伪造版本类型仍拒。

新专项 (`artifacts/expansion_v6/runtime/map_save_landmarks_v6_tests.log`)105项通过，包括六图2/3/4方18组真实生成快照完整往返。修后环境21、四阵营全海船坞/付费产船/实际跨岛/旧岸边存档159、旧档AI7、原规则189和战役流程34项通过；地图18+legacy、profile545与最大船体109项已针对回修源码通过。完整覆盖现在为原101清单加新存档专项1项，**102检查**；现 `tools/test.sh` 为94循环+8附加，另1次import。见最终定向汇总 (`artifacts/expansion_v6/runtime/post_map_repair_summary.json`)。其余已过手/UI/native没有从头重复。

当前候选运行源身份为 `7bb59958a58fd595199e88183c6e993ba1a0e2bf327dfa470e7b70f305ce8963`，见最新源记录 (`artifacts/expansion_v6/runtime/final_validated_source_manifest.json`)。手、UI、规则及原生库字节保持；最新原生库SHA为 `6c05ef6637f84a0084a7f5c64bde300bf7bd2b23eb7c42e6c752751fb4b61131`。该阶段身份随后只因opt-in验收probe支持真实PoseMesh源而更新为下文最终身份；玩法/美术未再变化。

证据缺口如实保留：原最终NO PASS的24张失败像素在归档指令到达前已被覆盖，只有原报告文字与36个SHA可追溯；`map_repair_first_capture_actual`保存的是第一次新修图，不是旧失败图。最终候选24图和绑定记录见地图回修manifest (`artifacts/expansion_v6/map_repair_final_manifest.md`)。本轮不重建或冒充旧失败图片。

## 实际Source与Shipping验收

最终运行源身份为 `786ad7b03604935c54b7fabce363c6644eb999d4c9037acf0056c434e3f22898`，manifest共2128个实际源/资源文件。根独立只读复核 (`artifacts/expansion_v6/runtime/root_staging_review.json`)逐文件核对本机源hash，并独立检查Source/性能和staging字节；其范围没有冒称当时尚未完成的包验收。

Source首轮102检查有3个失败：probe只接受MeshInstance3D，无法从普通建筑实际PoseMesh/MultiMesh渲染源规划鼠标表面点；手palm/finger真实点击与步行已工作。原json/log/6图保留在 `runtime/source_attempt1*`。只改opt-in probe接受真实PoseMesh源，并核对其原mesh就是实际MultiMesh batch mesh；仍须当前transform、真实EntityPicking/depth和Input事件命中，没有新增验证替身。第二次Source完整125/125通过，Shipping实际ELF完整125/125通过；没有复用v5的88项计数。

| 验收 | 实际结果 | 证据 |
|---|---|---|
| 手/六图独立视觉 | 两者PASS；地图以当前24SHA及主要形体门槛判断 | 手终审 (`artifacts/expansion_v6/hand_reference_review_final.md`)、地图终审 (`artifacts/expansion_v6/map_reference_review_final.md`) |
| 完整headless覆盖及最后变化 | 原101清单+新保存专项1=102检查覆盖；3HUD定向与最后地图/环境/航道/存档检查通过 | 原汇总 (`artifacts/expansion_v6/runtime/regression_summary.json`)、最终定向 (`artifacts/expansion_v6/runtime/post_map_repair_summary.json`) |
| Editor import/单位模型缓存 | 最终import与probe import0错误；GLB后LOD171模板/139缓存、error0 | `runtime/editor_import_final.log`、`runtime/probe_import.log`、`runtime/bake_unit_lod_indices.log` |
| Source实际主场景GPU | 125/125、11截图；schema2/version6、X11/Forward+，native sim/render/worldsync全true；0SCRIPT/ERROR | Source报告 (`artifacts/expansion_v6/runtime/source.json`)、原日志 (`artifacts/expansion_v6/runtime/source.log`) |
| Fresh Linux Shipping导出 | 导出成功0错误，导出前后全部源指纹一致；前两次仅隔离XDG模板路径配置拒绝，日志保留，使用已安装4.6.2模板未改引擎/源 | export日志 (`artifacts/expansion_v6/runtime/export.log`)、manifest (`artifacts/expansion_v6/runtime_export/manifest.json`) |
| 实际staging ELF GPU | 125/125、11截图；debug_build=false、native三标志全true，schema2/version6；0SCRIPT/ERROR | Shipping报告 (`artifacts/expansion_v6/runtime/shipping.json`)、原日志 (`artifacts/expansion_v6/runtime/shipping.log`) |
| 实际ELF内嵌PCK | 2184项；docs/手参考/12AI/artifacts/tests/tools不在PCK；当前manifest、手rig/provenance在PCK | 直接目录审计 (`artifacts/expansion_v6/runtime/shipping_pck_audit.json`) |
| 正式目录/外部归档 | 完整目录替换为已验v6；刷新包430文件全部BUILD校验通过，package/formal/external全部文件路径与SHA一致；同核心字节工程外实际ELF正常GPU启动180帧、exit0/0错误 | 初包原始证据与正常启动日志随包；最终归档后独立记录在源工程 `artifacts/final_v6_archive_validation.json`，digest在外部sidecar |

菜单、六图/2—4方设置、正常开局、真实总部点选与上下文卡栏、仅单位选择隐藏卡栏、连续Skin真实palm/finger拾取、行走、单次windup/目标表面接触/压碎残骸/恢复、战役入口及真实F5/F9保存载入/重开均在Source和实际Shipping流程中完成。战役实机步骤是保存/载入与目标UI烟测，完整胜利另由含AI30项headless真实命令测试证明；不把这两者混写成实机完整通关。

所有程序验证使用独立XDG目录，未读写玩家默认存档目录；helper也保留已有同路径存档的备份/恢复。只读审计新子代理两次因工具线程上限无法创建，没有复用停用模型；根的独立字节/源审计与实际外部解压验收分别记录。

## 新源真实GPU性能

测量为Source Vulkan Forward+ / Intel Arc(MTL)，1920×1080窗口、balanced、100%3D倍率、原始完整模型/材质、MSAA2X、SSAO、近远DOF。四方真实AI/模拟，预置128单位与24已完成建筑，热身5秒、采样30秒；**是压力fixture，不是普通开局，也没有固定人口补回或改规则**。

| 地图 | 平均FPS | 均值ms | p95ms | p99ms | 采样帧 |
|---|---:|---:|---:|---:|---:|
| forest | 45.34 | 22.05 | 24.02 | 24.43 | 1360 |
| city | 48.89 | 20.45 | 23.59 | 24.96 | 1467 |
| islands | 79.79 | 12.53 | 15.14 | 15.55 | 2394 |

三份原json/log/png保存在 `runtime/performance_<map>.*`；条件与汇总 (`artifacts/expansion_v6/runtime/performance_summary.json`)以及根独立复核确认各自实际采样至少29.9秒。保留用户环境中无关历史headless进程共存，未为采样终止它；先前2%是累计观察，不冒称同期负载。以上是本轮实测，不宣称稳定60FPS，不沿用v5成绩。fixture不预置创世之手，其Skin实机输入/动画性能仅由上述功能流程证明，不以普通128单位数据推断大批巨手帧率。

## 已验收staging字节

- `PaperFront.x86_64`：`9738d82a4d056bd3995a697acc31ea415b51ebb7e21c5e5b00e4d6418b4e5d9d`
- `libpaper_front_kernels.so`：`6c05ef6637f84a0084a7f5c64bde300bf7bd2b23eb7c42e6c752751fb4b61131`
- `manifest.json`：`545c22408875b7303d583a9f5c490d37815c31b545d8da22e50faf7f81fba5ed`

Source/Shipping验收、导出指纹复核与实际ELF运行后这些字节未改变；字节记录 (`artifacts/expansion_v6/runtime/staging_accepted_bytes.json`)和根独立SHA核对一致。旧v5 staging逐字节保留，身份见保留校验 (`artifacts/expansion_v6/runtime/v5_stage_preservation.json`)。正式目录与归档须从该staging创建，不能混用旧v5程序。

## 正式目录与归档校验

正式入口为 `artifacts/linux/PaperFront.x86_64`，完整包为 `artifacts/PaperFront-linux-x86_64.tar.gz`，外部校验文件为同名 `.tar.gz.sha256`。目录由完整包逐文件同步，包含已验收的同一ELF、原生库、manifest、便携说明、设计参考/实图、CC0/引擎/字体许可及明确标记的历史记录，没有保留旧v5程序混合运行。

初包已在工程外 `/tmp/paperfront-v6-external-3kq5za7x/PaperFront-linux-x86_64` 解压，`sha256sum -c BUILD.sha256` 425项全通过；ELF/so/manifest与staging上述三SHA逐字节相同。该工程外ELF不用验收flag正常GPU启动180帧，exit0、0SCRIPT/ERROR。说明刷新不改变核心程序字节；刷新归档工程外解压的430个BUILD文件全部校验通过，package、正式linux与外部解压全部文件路径和SHA完全一致，ELF/so/manifest仍是同一已验收staging三SHA。未无意义重跑字节不变的GPU程序。

最终tar摘要不写入会被本次归档再次复制的报告，避免自引用；由外部 `.tar.gz.sha256` 与归档后单独生成的源工程最终校验记录判断。旧 `artifacts/expansion_v5/runtime_export` 未改变，原v5正式目录还在 `.linux-v5-before-v6-20261005` 作为可恢复备份。
