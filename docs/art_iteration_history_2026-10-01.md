# 美术迭代接续记录

2026-10-01。**目标始终是原始概念图**：[preview_design1.png](preview_design1.png)、[preview_design2.png](preview_design2.png)。现有游戏截图只是基线，不成为新的美术目标。沿用已有纸模模型、玩法、右侧 HUD 与景深成果。

**当前有效源码：v25 旧墙 A + v24 水湾 B + v23 车辆纸边 A + v22 自影修复和此前保留资产**。[普通实机图](../artifacts/visual_iteration/v25_context/props_a_gameplay.png)，[辅助宽视角](../artifacts/visual_iteration/v25_context/props_a_g0.png)。源码快照 `artifacts/visual_iteration/v27_checkpoint/source_retained/`，机器接续 `artifacts/visual_iteration/current.json`。Linux独立程序和分发包已更新到相同保留版，实际release图/哈希见文末。目标保持进行中，不是美术定稿。

```bash
python3 tools/capture_golden.py --name next --views gameplay,g0 --output-dir artifacts/visual_iteration/next --baseline artifacts/visual_iteration/v25_context --fixture data/golden_visual_context_v4.json
```

UI条件图按需加HQ/factory/empty视图。新name/目录，默认自动退出，`.run.json`实命令/路径/状态，PNG+JSON与日志同目录。新场景之后资产轮不加豁免；有意地形/道具变化才分别用 `--allow-scene-change` / `--allow-props-change`，明确指定新fixture，并保持非本轮变量hash、镜头、UI、light/time等一致。

## 用户偏好（待结合实图判断，不是立即执行清单）

- 悬崖现在过于规整；希望更有不规则地景的变化。
- 单位轮廓希望有一层浅纸色空白留边，外层再有深描边，参照概念图剪纸感。
- 坦克希望更 tiny、小巧，棱角更柔和；矿石也应比较当前形状与原图。大小判断以正常 RTS 镜头为准，不从压力场远景推断。
- 树木目前不够精致，希望接近原图丰富的手制感；围墙、沙袋也应统一到同一风格。
- 河流应有流纹、岸礁/石块、宽窄和深浅变化，避免整齐平静的死水。
- 上述是偏好证据，选轮次前仍需看实际游戏图与原图，不能不加判断地全部照做。

## 场景与采集

- `dev` 48×48：资产试验场，仅作局部诊断。
- G0：固定 14 建筑 / 24 单位的中期对局状态，完整正常渲染；原比较镜头 distance54。不是正常付费开局，也不是压力场。
- 正常游玩镜头：正在补充同一固定状态的普通 HUD / distance43 图，作为主要验收。
- `--benchmark` / `--stress`：224 / 256 单位高密度辅助检查，distance110；不作为模型比例依据。

已验证原自动流程：

```bash
python3 tools/capture_golden.py --name v13_resume_baseline --baseline artifacts/visual_iteration/g0/v12_gold_source_final.json
python3 tools/capture_golden.py --name v13_resume_repeat --baseline artifacts/visual_iteration/g0/v13_resume_baseline.json
```

自动启动源码项目、加载完整 fixture、冻结仿真与动画、设定相机、等待8渲染帧并在 `frame_post_draw` 后保存 1920×1080 实际 viewport，PNG/JSON/log 后自动退出。两次独立运行图字节一致，SHA256 `2492580d1461b90590b1c5d7b53be73a5fee1dba6631ff563f3363d591c8d600`。默认不用 `--hold`。新批量命令完成后记录在这里。

## 接手检查点（历史）

接手时源码美术保持 v12 的有效成果。[接手实机基线](../artifacts/visual_iteration/g0/v13_resume_baseline.png) 已实际打开。最大差距仍是大块空地与对象群落缺少连续组织、地形/河岸的直角台阶外轮廓；已有车辆比例和体积基础，不重做全资产。

回退文件：`artifacts/visual_iteration/v13_baseline/source_before/` 保存 landscape.gd、volume_models.gd、fixture 与 project.godot。

下一轮假设：先建立道路、林缘、崖缘的中尺度地表联系。预计同镜头下空地形成有组织的留白；不通过增加模糊或裁图掩盖问题。采集普通游玩镜头基线后再实现，实际看图决定保留。

历史试验详细证据保留于 [visual_gap.md](visual_gap.md)：微弱模型刷色 v05/v05b、平台内小箱 v08 无整图收益，已回退；不要重复加大同一参数。后续只维护此处简短接续状态与轮次结果。

### 用户追加 UI 方向

希望精确参照原图的粗糙纸质面板与布局，当前右栏不如原图。下方建造/生产区按建筑选择出现：总部提供建筑列表，其他生产建筑提供各自可生产内容；没有选中建筑则空。设置按钮右侧加入 Debug 按钮，点击打开调试信息。此项覆盖历史右侧常驻建造栏偏好，安排独立 UI 轮次，真实截图检查纹理、布局与关键交互。

## v13 自动采集通过 / v14 地表（保留局部改善）

新固定命令（单次游戏进程批量两张，自动退出）：

```bash
python3 tools/capture_golden.py --name ground_b --views gameplay,g0 --output-dir artifacts/visual_iteration/v14_ground --baseline artifacts/visual_iteration/v13_baseline
```

`baseline` 与 `repeat` 两次独立运行的 gameplay/G0 各自 PNG 完全一致；完整运行命令、源hash与成功/失败见各目录的 `.run.json`，日志与元数据同目录。普通镜头 focus(73,102)/distance43/pitch30/yaw0.32/h_offset0，G0 distance54；1920×1080，3D1622×1080，右栏248逻辑像素，render scale100%。每个视图在加载/相机/窗口布局生效后等待8次真实 `frame_post_draw`。采集入口只在Godot开发/带development的程序启用。

地表轮未改变fixture、镜头、灯光、实体或碰撞。`ground_a` 实图林缘/岸缘地表联系更明显，浅路变得可追踪，但一段跨高低地边的路被切出尖角；`ground_b` 去除这段并让南向浅路沿真实低地弯行，突兀箭头消失。保留 B 的局部改善：[普通镜头](../artifacts/visual_iteration/v14_ground/ground_b_gameplay.png)、[G0](../artifacts/visual_iteration/v14_ground/ground_b_g0.png)。碎屑仍偏散、空地组织仍薄，不能称整体已达参考。

接下来执行用户明确追加的UI轮次：原图的顶条/底部纸板构图和建筑选择驱动列表；地景不再同时变化，旧布局图保留，明确区分UI取景变化与资产改善。回退文件在 `artifacts/visual_iteration/v15_ui/source_before/`。

## v15 参考纸质 HUD（保留 B）

用户追加的UI要求单独迭代。UI A已实际查看普通/HQ/工厂/空选四张图，布局恢复参考图的顶资源条、顶右时钟/设置/Debug、底左小地图、底中条件卡片和底右六格墨图标。UI B统一卡片与纸板色，减弱硬板阴影/多重方框，改为一条不齐粗墨框与大块浅斑/折痕，小地图填满纸板。B实图纸片感比A清楚，保留；参考的自然磨损仍可继续比较，不称精确风格完全达成。

[普通镜头](../artifacts/visual_iteration/v15_ui/ui_b_gameplay.png)、[选总部](../artifacts/visual_iteration/v15_ui/ui_b_gameplay_hq.png)、[选工厂](../artifacts/visual_iteration/v15_ui/ui_b_gameplay_factory.png)、[空选](../artifacts/visual_iteration/v15_ui/ui_b_gameplay_empty.png)。HQ显示7个现有建筑卡，厂仅本厂产品；空选、单位与非生产建筑无建造卡。保留原队列、取消/退款、就绪放置、修理/出售、保存与菜单。Debug开发构建点击打开，正式构建隐藏。

```bash
python3 tools/capture_golden.py --name ui_b --views gameplay,gameplay_hq,gameplay_factory,gameplay_empty --output-dir artifacts/visual_iteration/v15_ui --baseline artifacts/visual_iteration/v15_ui
```

A第一次使用 `--allow-ui-change` 对比v14，只放开UI/layout，继续核对镜头、fixture、实体、时刻、灯光与摄影。B比A条件完全固定。现在3D全1920×1080，正常镜头不变；原图对象水平位置变化来自全宽布局，**不计作模型/地景提升**。32项相关实机最小检查通过（总部建造付款/取消、生产付款排队、选择能力、Debug/菜单/结果节点、纸板输入隔离），没有全面回归或压力测试。

下一轮：试验崖岸凸角/直边的共享顶点退让，保留原地图规则/崖底/桥头与坡道，仅检验可见轮廓是否减弱格子台阶。UI冻结B；回退源码在 `artifacts/visual_iteration/v16_cliffs/source_before/`。

## v16 崖岸共享顶点（保留 A 的局部改善）

[实机图](../artifacts/visual_iteration/v16_cliffs/cliff_a_gameplay.png) 已打开，与UI B/原图比较。前景左平台与河岸凸角由方直角变成较柔和的削角，上下壁面仍连续，桥头/坡道保持。近岸连续台阶的尖角感减弱，可见收益；长直崖段、凹角与宏观地形仍规整，**未解决整体天然起伏**。保留小步，下一轮不继续放大同参数。地图、实体、相机、UI B、灯光/摄影均未变。

```bash
python3 tools/capture_golden.py --name cliff_a --views gameplay --output-dir artifacts/visual_iteration/v16_cliffs --baseline artifacts/visual_iteration/v15_ui
```

补丁保存在该目录 `cliff_round.patch`；原源码在source_before。凸角对角总退让0.38–0.40m，直边0.08–0.12m，低层/凹角/窄台地/桥头/坡道/道路/土洗锁定。水格、崖底、导航规则不改；新顶面和崖顶共用世界顶点。临时工程解析与少量角型检查通过，主工程实机启动/截图无错误；未全面回归。下一轮优先检验流水的大色块、弯曲流纹与岸脚礁石，再回看单位纸色留边。

## v17 河面（暂保留 B，整体水感仍未定）

A/B均已打开普通与G0实机图。A的深浅蓝和稀疏岸礁增加联系，但长白流纹像一排面条，不保留该流纹形状。B改为短曲波纹、稀疏成组回流及空水间隙，避开均匀长白线，桥拱/通路/部队仍清楚；暂保留B的局部水面改善。现在仍像规则渠道，流纹偏稀、宏观宽窄/水色组织与原图仍有差距，不声称河流完成。

[普通图](../artifacts/visual_iteration/v17_water/water_b_gameplay.png)、[辅助G0](../artifacts/visual_iteration/v17_water/water_b_g0.png)。水/石静态可复现，没有TIME漂移；礁石只占原WATER格、桥附近保护。参数与fixture/camera/UI/lighting/photography全固定。原water A源码留 `landscape_water_a.gd`，原v16源码留source_before。

```bash
python3 tools/capture_golden.py --name water_b --views gameplay,g0 --output-dir artifacts/visual_iteration/v17_water --baseline artifacts/visual_iteration/v17_water
```

接下来先验证步兵的浅纸色留边+外墨线（不替换真实体积车辆/独立炮塔），树冠大形补丁也在准备，未应用。之后回看坦克tiny/柔和形，避免混合缩放与轮廓实验。

## v18 步兵纸色留边（保留 A）

[普通实机图](../artifacts/visual_iteration/v18_infantry/infantry_a_gameplay.png) 已与v17 B和原图实际打开比较。树林边蓝兵/右岸红兵外缘出现温暖浅纸空白，再接外墨线，默认尺度读形更清楚；脚仍贴地、遮挡关系成立，未见明显外侧棕幽灵边。边略偏厚贴纸，先不加大。只改变步兵真实薄卡的扩展面和alpha材质，原图/五动作路径/世界朝向/厚度保留；车辆、建筑、枪口、尺寸与玩法未动。**车辆纸色留边仍未实现**，复杂小闭件白缝风险记录于该目录unit_outline_notes.md。

```bash
python3 tools/capture_golden.py --name infantry_a --views gameplay --output-dir artifacts/visual_iteration/v18_infantry --baseline artifacts/visual_iteration/v17_water
```

front/back容纳0.15m margin，画面内2px纸/总3px墨，底部裁到y>=0；屏幕纹理采样固定、无TIME，实际启动/截图无错误。保留此基础，不靠继续加粗线条逼近原图。下一轮树冠配方；其后单独比较坦克车体/炮塔柔化，保持当前.75缩放先看形。

## v19 树冠 A（回退）

[试验图](../artifacts/visual_iteration/v19_trees/trees_a_gameplay.png) 已打开。浅缺口/双段肩部把树变成较平滑、规整的堆叠圆锥，连续暖边像层圈，浅橄榄色偏塑料；红方林边遮挡略增。虽然代码实现了更多层面和厚纸边，整体未缩小原图差距，**回退本轮**，保留v18树形和所有此前成果。B将重新检验不齐枝梢与断续纸边，不能继续放大圆锥肩面。候选补丁与图保留。

该回退时有效源码 = v18（UI B、地表 B、崖 A、水 B、步兵纸边 A），v19 A不是有效版。下一项车辆局部软形实验，不改缩放/矿车/炮口/材质。

## v20 车辆软形 A（回退）

[普通图](../artifacts/visual_iteration/v20_vehicles/vehicle_a_gameplay.png) 已打开；局部诊断并排图仅用于确认实现，不替代普通镜头验收。两处XY上角的2段圆转在正常图没有明确整体收益，主要深度方向的硬盒感仍在，不继续增大同样切距。**回退A**，保留原车辆模型与.75比例。此结论并不否定用户tiny/柔和偏好，而是当前实现未解决真正的轮廓原因。下一步另验正常镜头下坦克/突击车.70尺寸（矿车/步兵/建筑不动），之后再决定深度方向体块处理与车辆留边。

### v20 尺寸 B（保留） / v21 地形自影诊断

[尺寸B普通实机图](../artifacts/visual_iteration/v20_vehicles/scale_b_gameplay.png) 已打开。仅tank/assault从.75改.70（约小6.7%），正常43镜头下更小巧，履带/车体/炮塔与炮管仍可辨；矿车/步兵/建筑未缩放。枪口、炮塔位置、尺寸、后坐距离通过同一已有bake系数处理，碰撞/规则不改。硬盒感仍在，不把缩放当作形状已经解决。

[地形投影OFF诊断图](../artifacts/visual_iteration/v21_ground_diag/terrain_cast_off_gameplay.png) 已打开：土和水密斜纹几乎同步消失，表明问题主要来自地形/板自身caster链路，不只是ground shader纤维。保持物体投影/地形受影/光照与材质，但崖投水影被关闭，此图acceptance=false，**不作为保留版本**。真实命令、覆写与日志保留同目录。下一候选分离垂直崖面caster与水平top/覆盖物，再自动看图验证是否既除纹又保留空间。

### v19 树冠 B（保留轻微改善）

[普通实机图](../artifacts/visual_iteration/v19_trees/trees_b_gameplay.png) 已打开，且独立图审也实际比较。中央枝层更不齐、深绿稳定，未出现A的圆筒/金环，林边兵车仍可辨；保留为轻微局部改善。原图分枝簇和厚纸折片的构成仍差很多，下一轮应重新定位资产构成，不再准备第三个同类圆锥参数试验。基线为尺寸B，模型/镜头/UI/灯光保持；树位置、冠幅、数量、阻挡不变。

## v22 地形投影分离 A（未保留，继续修正结构）

[普通图](../artifacts/visual_iteration/v22_shadow/shadow_a_gameplay.png) 与[辅助图](../artifacts/visual_iteration/v22_shadow/shadow_a_g0.png) 都已打开。水平地表/水的织纹基本消失，物体影保留；但单独wall caster无法表达完整平台的遮蔽，河面岸影只剩窄尖三角，深谷空间退化。因此A不作有效美术版本。不能用除纹一项成功忽略空间退步。

下一候选：在同一独立caster补回原初terrain top triangles构成平台cap，投影副本向下0.06m，跳过所有paint overlay；可见地表/规则/实体/光照参数保持。仍需实机判断完整岸影与无织纹是否同时成立。当前工作源码临时为v22 A，最近完整有效图为v19树B，所有回退文件保留。

### v22 B（保留）

普通/G0两图已打开。完整平台shadow cap恢复岸影和深水层次，土/水密织纹大幅消退（弱材质细纹仍可见），单位/树/建筑与崖影保留，故保留B。caps只记录初始地形top/ramp三角，副本下移0.06m避自影，不含道路/土洗/碎点等共面片；真实地形、单位、导航、镜头、UI、材质/灯光/AO/景深不变。A仅wall caster的窄尖影方案撤销。实际效果由实机图确认，不只是解析/退出成功。

主要剩余差距：默认画面空地/院落与路径/林缘联系仍薄、宏观河岸/台地仍规则；树需要改变分枝折片构成；车辆纸边和深度方向软形、矿石/围墙沙袋统一还没完成。下一轮从新实图重排最大差距，避免重复无效的圆锥/微刷色/微倒角调参。源工程可正常实机启动；UI最低相关32项通过，未做全面回归或长时性能。

## 可运行独立程序检查点

Linux独立程序与分发包已更新到v22 B，SHA256 `28710164389fec35a83cbc0db03457137a18cc3475d8a3c86dd59e3174568b5b`，未结束原有用户游戏进程，重启会加载新程序。导出无ERROR/WARNING，development入口批量普通/HQ/G0成功并实际看图；镜头/fixture/时钟/光照/UI元数据一致。Source/release全部3D像素一致，只有右下说明文字约250像素的省略尾部不同，未假称整PNG一致。

[程序当前普通图](../artifacts/visual_iteration/v22_shadow/release_checkpoint_gameplay.png)、[程序选总部](../artifacts/visual_iteration/v22_shadow/release_checkpoint_gameplay_hq.png)。编译脚本无法回读全部原始.gd哈希，以source快照与release文件哈希分别记录。`artifacts/.gdignore` 防止源备份/截图被Godot当游戏资源扫描。

下一轮正在准备车辆主形shell纸边，仅在单位外缘实现paper/ink，不对小轮毂/徽章刷白边。仍是候选，尚未进入有效版本；若失败回退v22 B，不能宣称已经完成车辆纸边。

## v23 车辆纸色留边 A（保留）

[普通图](../artifacts/visual_iteration/v23_vehicle_border/border_a_gameplay.png)与[G0](../artifacts/visual_iteration/v23_vehicle_border/border_a_g0.png)已实际打开，并独立图审。车辆外缘paper/ink清楚出现，与步兵纸边统一；本体大面和轮毂未见白缝涂坏。朝向镜头的炮口白圈稍粗、纸边仍比原图更亮，保留为局部改善，不继续加粗。本体geometry/hard normals/涂色、.70/.75比例、炮塔/枪口/后坐不变；新增仅单位主形的平滑shell，2px paper/外总3px墨，真实depth测试且无新增影，ghost/建筑不加。隔离检查原body数组完全相同与transform接口保持；主Forward+实际编译/启动/两图成功。

```bash
python3 tools/capture_golden.py --name border_a --views gameplay,g0 --output-dir artifacts/visual_iteration/v23_vehicle_border --baseline artifacts/visual_iteration/v22_shadow
```

## v24 地形改形（候选，待实际图比较）

新增最小显式fixture入口，不再把不理想地形永久锁死：`--fixture data/golden_visual_landscape_v2.json --allow-scene-change`。只允许map不同；强制non_map_state_hash/prop_batches_hash，以及camera/UI/light/photo/time/selection/分辨率不变。新增哈希字段后的scene_before与v23两张PNG完全相同。新fixture从原snapshot复制，不调用GoldenVisual.build找位，实体、生产/钱/姿态、props字节不变。

可重复builder：

```bash
godot --headless --path . --script tools/build_landscape_fixture.gd -- res://data/golden_visual_v1.json res://data/golden_visual_landscape_v2.json
```

new文件已存在时拒绝覆盖，后续候选另用新路径。详细格变化保存 `_changes.json`。公共MapData.sculpt_battlefield同时作用正常fresh160地图，48试验场保持；肩/湾只改原LAND0且连原台地/河流，保护ROAD/RAMP/BLOCKED邻域、全部38实体占地外2m、矿点与桥。候选实改40格（27肩部、13水湾），MapData.validate与非map字节/实体高度检查通过。这些只证明运行条件，视觉收益仍待真正打开scene_a图。

### v24 B（只保水湾，肩部撤销）

A已看普通/G0并独立图审：水湾有可见河宽变化，左右肩部在默认图变成直角凸指、空顶面+台阶阴影强化积木感，撤销肩部。B仅13个原LAND0→WATER格，实体/props/规则状态/所有原高度不变；原ROAD/RAMP/BLOCKED/桥及矿点保护。普通/G0已真正打开，河面窄→宽与岸脚影变化可读、原南路/部队仍清楚，保留局部河岸改善。空地/院落组织仍未解决，不能称宏观地景完成。

新fixture为 `data/golden_visual_waterbay_v3.json`，独立_changes.json仅13格；旧v1及被撤销的肩部v2均保留作证据。builder验证通过后普通批量采集条件匹配（non_map_state_hash与prop_batches_hash同scene_before），新source MapData共用同waterbay函数于正常160开局；48场不变。source保留快照/current.json已更新。下一轮集中中景旧墙/残基组织，所有地形/镜头/其他资产保持B。

## v25 中景旧墙 A（保留局部改善）

[普通图](../artifacts/visual_iteration/v25_context/props_a_gameplay.png)、[G0](../artifacts/visual_iteration/v25_context/props_a_g0.png)已实际打开。树林南缘变成连续低墙/高残头，蓝厂与炼厂背侧、红方对应区的边界更可读；保留背衬树林，兵车/路口未新增严重遮挡。中景有收益，前景大空地仍未解决，不把旧墙当整图组织完成。11原BLOCKED格替换主形、选格树干移除、contact居中；未选props逐项保持，完整terrain+全部非map状态不变。墙含墨占地<=.83m，高0.71–1.23m，每个堵塞格仍有可读体积。

新fixture `data/golden_visual_context_v4.json` 从waterbay_v3复制，只换resolved props，原地图及state_base64保留。新最小旗标 `--allow-props-change` 保证map_state_hash+non_map_state_hash、镜头、UI、light/time等不变，仅豁免prop/fixture hash。normal CPU生成也调用同pure composer；Golden.apply不暗改。实际命令：

```bash
godot --headless --path . --script tools/build_context_fixture.gd -- res://data/golden_visual_waterbay_v3.json res://data/golden_visual_context_v4.json
python3 tools/capture_golden.py --name props_a --views gameplay,g0 --output-dir artifacts/visual_iteration/v25_context --baseline artifacts/visual_iteration/v25_context --fixture data/golden_visual_context_v4.json --allow-props-change
```

新增工具只为明确map/props变化作窄比较，不扩展成自动化框架。载入/新局重建小地图纹理，避免同seed不同地形旧存档显示旧纹理；固定图字节不变。下一轮比较矿簇：降低整束直立规则晶柱感，保原采矿/矿量/包络，先看资产形。

## v26 矿簇 A/B（回退）

A/B普通与G0四图均已实际打开，并独立复核。A缩短长柱、采用斜片/薄碎片后，满矿簇变成3个主要蓝尖与散纸旗；B加宽中低片并内聚仍未恢复饱满蓝体块。不是矿量逻辑/包络成功就算通过，**整轮回退v25原矿簇**，不做第三次同类参数调整。原矿满矿识别更稳，后续应改变矿峰/底部群构成方法再试，用户tiny/柔和偏好仍保留。候选图/patch/原源码在v26目录。

## 下一轮定位

原始参考仍远于当前：前景大空地、树林的分枝折片构成和规整岩岸最值得继续；单位纸边已清楚但偏亮，车辆仍偏整齐蓝漆硬盒。不要重复微刷色/小箱、树圆锥肩面、XY微倒角或矿石纸旗配方。下次继续用上述确定命令实际看图。当前尚无足以宣布整体视觉完成的证据；最终定稿由用户确认。

## v27 可恢复运行检查点

保留v23车辆纸边、v24水湾B、v25旧墙A；v26矿石A/B全回退。当前Linux程序/分发包更新，未结束其他用户进程。实际release普通/HQ/G0均成功、已打开比较，fixture/map/non-map/props/camera/UI/lighting等元数据匹配。全部3D像素与source v25一致，仅右下提示文字省略尾部250像素不同，未声称整个PNG一致。导出无ERROR/WARNING，相关最小UI32项通过；不做全面回归或长时性能。

[当前程序普通图](../artifacts/visual_iteration/v27_checkpoint/release_v27_gameplay.png)、[选总部图](../artifacts/visual_iteration/v27_checkpoint/release_v27_gameplay_hq.png)。程序SHA256 `3f646217c10314827e081a69e9eef9df2870afc4ecec9151f32e8fb6d375dfda`。source_retained和current.json足以恢复。原始概念图仍是目标，当前大空地、规整岩岸、树折片构成、车体涂色/深度硬盒仍有值得继续差距，整体任务保持active。

## v28 地面群落 A（撤销候选，B重新定位中）

[普通图](../artifacts/visual_iteration/v28_ground_ecology/ecology_a_gameplay.png)与[G0](../artifacts/visual_iteration/v28_ground_ecology/ecology_a_g0.png)已实际打开。新增低草/砾片有可见体块，但完整九边纸底与同类四折草、两列前景站点像小盆景/纸垫，未明显建立原图连续土/草/碎屑关系。**回退A到v27地面**。不能按86岛/10938三角或包络通过判为改善。B将删除实体盆底与等距站点，转几段非等长的渐散土/草/砾边缘联系；若仍成花槽就撤销，不继续加同款岛数量。旧源码/patch/PNG保留v28。

v29树候选将采用不同的构成——三张交错的真实厚纸枝形折片，保持位置/冠幅/高度，实际截图后再决定；不重复圆锥肩面参数。其他已保留资产不变。

## v29 纵向厚纸折片树 A（回退）

普通/G0 PNG已实际打开，与v27及原图比较，林冠变稀，亮边插片和高细针感加重。独立核查未发现面缺失/法线/绕序bug；包络不变但开放纵片深凹口使投影冠面减少约26–36%，中低冠连续深绿块丢失。**回退整轮，不做B**；不能用加宽/加树/加blur挽救。保留此前树冠，后续方法必须保深绿体块与不同朝向的连续冠面，再处理枝形。失败JSON、patch与两图保留v29。

v30只比较车辆纸棕主面/队色局部覆盖，不改外形、paper halo、scale、炮口/塔/材质noise、灯光和场景。

## v30 车辆纸棕覆盖 A（保留）

普通/G0两图已实际打开并独立复核，左前坦克甲板/塔顶和矿车cab更像纸模型；前后蓝面、框边与深履带仍清楚，桥两端蓝红仍可辨。整队色远距醒目度略降，但没有混入土或halo细缝。保留A，不继续改覆盖比例。尺寸/本体包络/shell数组、炮口/塔/alpha/材质/light均不变，只有lit共面纸心/队色框。

## v28 地面群落 B（保留局部联系）

A回退后，B独立从v27地形配方重做，不复用盆底与两列站点。普通/G0真正打开并独立审图：盆栽感消失，林尾、台脚、湾岸碎屑更自然，路仍清楚。保留小收益；仍缺足够中尺度土色，片群之间大块同色空纸面未解决。最高0.212m，实体/props/地形/摄影/光照保持，碎屑低小可踩。

当前源码有效=v30配色A+v28生态B+v27此前成果，程序暂仍v27。v31只准备连续土色域候选，尚未应用。可见前景1014采样量化：moss67%/soil65%贡献为0，forest context全0、rim79%为0，左路肩luma仅低亮地约6%，现局部噪声没连上路/林/崖。下一机制是5–10m domain-warp连续色域与宽场景距离权重，留亮路/亮空地，不改light/blur或网格。仍需实图，不能把采样统计当美术通过。
