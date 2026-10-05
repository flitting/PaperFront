# 美术迭代接续检查点

2026-10-01。任务active，**尚未定稿**。永久目标：[原图1](preview_design1.png)、[原图2](preview_design2.png)；当前与后续截图仅是基线。用户偏好与此前全部证据见[历史记录](art_iteration_history_2026-10-01.md)。

## 当前有效版本

源码 = v41硬纸壳树A + v40人物原画A + v38功能建筑C + v37敦实履带车A + v35后林翼B + v33前景林簇A + v31连续地表色域A + v28边缘生态B + v30车辆kraft覆盖A + v27此前保留成果（paper HUD/选建筑驱动卡片/单位留边/小巧坦克/完整自影修复/水湾/中景旧墙）。[主图](../artifacts/visual_iteration/v41_rigid_trees/tree_a_gameplay.png)、[辅助宽视角](../artifacts/visual_iteration/v41_rigid_trees/tree_a_g0.png)。Linux程序和分发包已同步v38 C，实机普通/HQ/G0成功并实际打开。

`artifacts/visual_iteration/current.json` 是机器接续状态；完整可恢复源码 `artifacts/visual_iteration/v41_rigid_trees/source_retained/`。

## 直接复用自动命令

```bash
python3 tools/capture_golden.py --name next --views gameplay,gameplay_barracks,g0 --output-dir artifacts/visual_iteration/next --baseline artifacts/visual_iteration/v40_infantry --fixture data/golden_visual_northforest_v7.json --prepare-assets
```

1920×1080实际Forward+、render scale100%、普通focus(73,102)/distance43/pitch30/yaw0.32，G0辅助distance54。每视图恢复固定实体/选择/HUD，仿真135tick/4.5s与视觉0，布局/镜头生效后8次真实frame_post_draw再存viewport PNG+JSON，运行命令/状态/日志同目录，默认自动退出。必须实际打开新图与原图比较，成功输出不是视觉验收。

UI按需加gameplay_hq/factory/empty；不要每輪全部重拍。场景角色：48 dev仅资产诊断，普通43为主，G0宽视角辅助，全224/256压力场仅高密辨识辅助，不从压力远景推断模型比例。

地形/props有意变化才用新fixture与对应--allow-scene-change/--allow-props-change，强制保留非本轮状态hash和camera/UI/light/time等；普通资产轮不用豁免。显式builders为tools/build_landscape_fixture.gd与build_context_fixture.gd，不覆写已有JSON或重新找实体位置。原v1与失败的肩部v2保留；context_v4包含水湾v3与11格旧墙；foreground_v5明确新增21格林簇，builder为tools/build_foreground_fixture.gd；当前northforest_v7再新增相连后林62格，builder为tools/build_north_fixture.gd。失败的north_v6河湾保留作证据；当前河道与v33完全相同。

## 最近实际看图结论

| 轮次 | 实际观察/处理 |
|---|---|
| v28生态A | 完整纸底与两列同类草簇像小盆景，回退。 |
| v29折片树A | 林冠变细针/亮插片，非render丢面；包络不变但冠投影面积少26–36%，回退，不做B。 |
| v30车辆kraftA | 坦克甲板/塔、矿车cab纸棕主体更清楚，蓝红局部面/框仍可辨，保留；shell/外形/alpha/炮口不变。 |
| v28生态B | 删除封闭盆底/等距站点，林尾/台脚/湾岸碎屑关系自然、路清楚，保留小收益；大片空台仍在。 |
| v41硬纸壳树A | 保连续封闭绿冠/原实例，单瓣宽折脊、有限灰纸芯切边、Y印枝。normal前景宽面可见纸壳结构，未交通锥/细针化，保局部收益；尖锥/重复层与原图精致枝片差距仍在。仅本候选，用户新停止条件下不再B。 |
| v40人物A | 35 SVG+对应轮廓选择性更新；57其它SVG/轮廓不变。普通43/兵营卡/G0实拍缩头长腿、弯肘持工具与衣身墨面更自然，脚点/角色工具清楚，保A。5动作/脚锚/三角化/alpha支持最小检查过，硬卡/纸边/点击/规则原样。导入纳入同一自动命令，元数据核对35SVG+contours哈希。 |
| v39主壁成组内凹A | normal/G0实际看图；主墙深度变强，但大V凹折/杯槽像低多边形折壳，顶缘仍规则，下主墙仍宽平，撤回v38。两独立审图意见不同，root按原图/新用户山缘要求判断；不再加深同型凹槽。原map/top/foot/props全保的检查通过不能当美术通过。 |
| v38功能建筑A/B→C | 低厅+大料斗的精炼厂、双低折顶兵营、宽车库门/窗分离工厂在normal更好区分，保C。A/B红factory两高折面像竖纸鳍，降峰/暖大面仍未消除；C恢复旧厂顶，新两类与车库收益仍在，normal/G0实拍保。UI refinery/barracks idle SVG卡图未同步，记录待处理。 |
| v37敦实履带车A | 普通43/G0实拍：tank/assault低腹闭实、厚履带和少数大轮、厚高炮塔更短胖；蓝平冠/红斜冠辨识、tiny与纸边保持，保留。length/.70、harvester、全部场景非本轮变量不变；炮口/独立炮塔/后坐相关最小检查通过。 |
| v36真实台肩削减A | 96格高度降2m（44上台+52外肩），实拍普通43/G0。变化主要在左上后缘，最显眼两段长暗墙未动；新浅凹台/方端头无明确参考收益，撤回v35。不能把4m顶面积少40%当视觉验收。 |
| v35北河湾/后林A→B | A后林将蓝/红塔接到原林缘，保留。A河湾实图生成细长尖嘴和阶梯岸缘，撤25水格；B恢复v33原河道，62树变换与A完全相同，普通43/G0均实际打开，保留仅树林B。height/旧155groups/38实体固定，保护与MapData.validate通过。 |
| v34闭合宽枝A | 实拍普通43/G0绿色体量保持，但宽枝变化很小，树仍是规整分层尖锥，没有明确缩小原图精致枝形差距；撤回v33树mesh。不因包络/闭合/面积检查通过保留额外几何。 |
| v33前景林簇A | 台肩—台脚连续深绿冠面和低残迹成立，亮通路/矿/单位清楚，保留局部构图收益。21格（18树+2ruin+1rock；LAND0=15/LAND2=6），height/旧143props组/38实体全保留，整格距全弯路≥4m。主图和G0均实际打开。 |
| v31连续土色A | 左崖脚/路肩宽暗土更连贯，亮路心保留，没有硬迷彩/条带，保留局部收益。几何/阴影/props/生态/ROAD与RAMP色不变。 |

所有候选PNG/patch/前源码在对应artifacts/visual_iteration版本目录，每张正式图已实际打开；独立审图结论也支持保留/回退。

## 尚存最大差距与下一步

大片规整台地和孤立场景群未形成原图的森林—残迹—通路—岸缘连续组织。前景林簇A已成立，但基地—桥—敌方仍被大空台面分隔，桥北孤立哨塔尤甚。下一宏观轮处理**中远景战区连续组织**，不要继续放大/加密这片前景林。闭合宽枝A已实拍无明确收益并撤回。后林B进一步使哨塔成为林缘节点，但战区间仍有大片规整空地。下一轮重新判断台地/岸缘整体几何，避免再用局部格增减制造薄长指；树形需重新定位，不再靠微拓宽星锥端部。允许明确地形/布景变化，保护桥/坡/永久绕路、实体锚点与合法单位通行，保留前后图，不能靠裁问题/加blur。树需保连续绿色冠量和多朝向体块，再找枝形实现；开放纵片方法已失败。

矿石保持原簇：v26两版变3个纸旗尖，满矿读形退步。不要重复微刷色、小平台箱、圆锥肩面金环、XY微倒角、同型盆景、空纵片或矿纸旗。正常启动/关键交互仅最小验证，视觉定稿前不全面回归/长时性能/无关重构。最终定稿仍由用户确认。

## v32 独立程序验证

[实机普通图](../artifacts/visual_iteration/v32_checkpoint/release_v32_native_gameplay.png)、[选总部图](../artifacts/visual_iteration/v32_checkpoint/release_v32_native_gameplay_hq.png)。release批量普通/HQ/G0全部实际打开，与source全部3D像素相同，只有右下提示省略尾部250像素不同；fixture/camera/light/UI/时间不变量匹配。程序及包更新，SHA256 `c5dae98fadf1e3f7338bfe810c11764f399a8d8fbb85b4ab0bc4024a1b83a031`，未结束其他用户进程。

首次release复拍与旧v27对照均出现两条focus_entered/tree_exited空callable错误，虽PNG真实完整但自动status=failed，未发布。原因对应[Godot已确认导出Popup问题](https://github.com/godotengine/godot/issues/89657)。仅给剩余Option/确认框force_native仍无效；在桌面支持原生子窗时，root viewport关闭gui_embed_subwindows，包含LineEdit内置菜单。真实三图PNG完全不变，自动status恢复success，无ERROR；菜单24次popup循环及确认框检查failures=[]。只做这组阻碍与相关最小验证，不全面回归/长时性能。

失败日志与错误版stage程序仍保留v32目录；最终发布的是native政策版。新非本轮状态/源hash/current.json和source_retained同步，下一轮继续上面的实机闭环。当前大场景组织与树冠/岩岸仍有明确差距，目标active，不是定稿。

## v35 保留版程序检查点

已更新 `artifacts/linux/PaperFront.x86_64` 及分发包，SHA256 `cbcd944ba1d2c2d0f946a495a43905d711629e6de410f6afeb40e80298edd85f`。release一次普通43/选总部/G0自动成功，三张均实际打开；普通/G0除右下帮助省略尾部外其余全部像素与source B相同。总部卡片按所选建筑出现，普通选单位无建造卡。source/fixture/camera/UI/time等运行不变量通过，无ERROR。前v32程序备份在v35目录，不结束其他用户进程。

[修改前v32](../artifacts/visual_iteration/v32_checkpoint/release_v32_native_gameplay.png) → [当前普通43](../artifacts/visual_iteration/v35_north_context/release_v35_gameplay.png)；[选总部](../artifacts/visual_iteration/v35_north_context/release_v35_gameplay_hq.png)。保留前景林簇A及后林翼B，撤闭合宽枝A和北河湾A。任务仍active，**未定稿**；下一轮从当前实图与原图重新判断台地/岸缘整体几何和手绘树枝结构，不能把本检查点当新美术目标。

分发包BUILD.sha256、START_HERE与VALIDATION已同步v35；玩法说明改为选建筑驱动下方卡片，旧性能数据明确标为历史。

## 用户追加偏好（本轮已记录，按实图选取）

山缘以成组凹凸/破碎装饰减轻棱角，可借鉴《红色警戒2》经典山崖；坡道不是首要问题。树要像硬质纸壳剪折而非普通小3D模型。建筑允许按功能夸张大轮廓，提高识别，不必拘泥原图具体建筑外形。车辆希望更敦实，适度增加宽/高、扩大炮塔占比，降低底盘与地面间的镂空；保留坦克读形即可，少现代精密感。人物图像/图标继续对照原图改善。此为最新偏好证据，车辆以改变部件比例与低底盘为重点，不直接整车加大或统一加参数。

v36已撤。下一轮优先检验胖车/大炮塔/低底盘这组可在normal看清的相关问题；山崖下一次直接定位可见主壁的成组折面/凹凸，不继续削被保护区裁剩的后台顶。

v37保留，下一轮只做factory/refinery/barracks三类功能大轮廓。独立正常视角采集，模型改变不以labels或小badge代替；场景沿v7固定。

用户已提供[红警2山崖辅助图](references/ra2_cliffs_user.png)，实际打开并保存原图含水印。只借鉴连续凹凸边线、粗细岩块组与顶部破碎过渡，不能替代两张原概念图的纸模/配色/构图目标。此前Steam画廊检索未找到典型山崖，未以那次检索声称已参考RA2实图；现在直接用用户此图。

人物只读接续建议：tools/generate_art.py:soldier，7spec×5状态共35SVG；当前头盔~81px/短腿/方胸袋姿态较僵，参考人物更小头、长腿/弯肘和有重心的3/4衣身。保384×320、脚285、1.65×1.8m硬卡/纸边。先加仅infantry生成入口，旧contours JSON作META底，只更新35SVG+同名contour，不重建其余57资产；同步5state轮廓语义而不保旧slice索引。PaperHUD复用idle所以同源改善图标。尚未实施。

v39已撤。山缘下一次要重审‘顶缘不规则＋粗细竖岩片连成实体壁’的实现，避免后台顶削减或整面V槽杯化；不在现法上再加深。v38 C仍为有效源码。

## v38可运行保留检查点

程序/包/BUILD.sha256/操作与验证说明同步。SHA256 `872b657a1b9071da8844201d9fad3a28e192c6514419f1df2ccc02c391751ae0`。release普通43/HQ/G0一次成功并实际看图；普通/G0除帮助尾部外全部像素与source C一致，非本轮条件一致。前v35程序备份v38目录。代码/数据/工具/原assets完整保留v38 source_retained，SVG下一次修改可恢复。未做全面回归/长时性能。

[修改前v35](../artifacts/visual_iteration/v35_north_context/release_v35_gameplay.png) → [当前v38普通图](../artifacts/visual_iteration/v38_building_readability/release_v38_gameplay.png)。下一步按记录做35张人物SVG+contour的选择性更新；山缘与硬纸树仍需换实现思路，不把已有代码实现/本检查点宣布为定稿。

用户最新停止条件：尝试完所提各点后结束本次任务，整理总体报告，不再按旧无限闭环追求最终风格。人物A已保；仅剩一轮硬纸壳树候选实拍判保/撤，然后构建保留程序与汇总。整体尚未最终定稿与遗留问题仍如实报告。

所提各点现均有已完成尝试：最新胖车37、建筑38、人物40、硬纸树41有保留；山缘36/39无明确收益已撤，原16轻削角保留；先前UI15、单位18/23、河流17/24、矿石26、布景25/28/31/33/35亦均已实拍处理。现在仅打包与整体汇报，按用户新条件结束，不再启动新美术轮次。
