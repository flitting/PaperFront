# 多视图松树与整体沙盘表现 · v44

2026-10-02。本轮依据用户提供的 [松树多视图](references/pine_multiview_user.png) 重建树木，并重新对照 [主要概念目标](preview_design1.png)。用户允许联动调整视觉与音效；已使用3个 `gpt-6.1-sol / high` 子 agent 分担音效、崖桥细节、模型表面及专项检查，主线程负责松树、画面统合、性能与交付。

## 交付与实图

[普通视角](../artifacts/visual_iteration/v44_reference_rebuild/verified_release_gameplay.png) · [G0宽视角](../artifacts/visual_iteration/v44_reference_rebuild/verified_release_g0.png) · [选兵营/人物卡片](../artifacts/visual_iteration/v44_reference_rebuild/verified_release_gameplay_barracks.png) · [同一松树四视图](../artifacts/visual_iteration/v44_reference_rebuild/pine_multiview.png) · [上一版普通视角](../artifacts/visual_iteration/v43_painted_miniatures/final_release_gameplay.png)。均是实际Godot模型/Forward+渲染，未用概念画或修图替代实机。

可运行程序 `artifacts/linux/PaperFront.x86_64` 和分发包 `artifacts/PaperFront-linux-x86_64.tar.gz` 已更新；`tools/run.sh` 启动它。上一程序保存在v44的 `previous_release/`，被修改源码/音频都有备份，最终源码在 `source_retained/`。

## 自审结论与本轮处理

| 与参考的主要差距 | 本轮实际改动 | 仍有的差距 |
| --- | --- | --- |
| 树冠像无细节的圆锥雕塑，三层肩部过整齐 | 暗色封闭内冠支撑30组厚实、下垂、重叠枝叶；正/侧/背/顶都是真实体积。增加短树干、树皮线、外展根和不等大石块；枝端黄绿干刷、冷暖绿块、暗叶背和描边 | 小尺度分枝和自然不规则性仍比AI设定简化，不能称作精确复刻 |
| 林木实例纵向拉伸，使新模型仍变成细杉树 | 原位置和横向占地不变，只把树冠及树干纵向比例限制在横向的1.08倍。新v9清单仅改1332个树/干纵向变换，地图/实体/其它props保持v7 | 布局仍受可玩地图障碍格约束，树林排列没有概念图那么自由 |
| 崖面大片单色、均匀细竖线、完整白唇边 | 增加宽窄不等的碎纸色面、渐细弯折裂隙、断续露纸边和短层缝；水格内添加岸脚石群；连续浅唇边压暗 | 宏观河岸与台地仍较规则，不能仅靠表面细节等同参考的复杂地形 |
| 地面太干净、空平台缺少中小尺度层次 | 不均匀聚簇土屑、更多低矮生态碎片、细纤维与不同尺度涂色；树、土、水形成冷暖分区 | 大片平台留白和局部斜纹仍存在；贴图细节不能替代全部环境布局 |
| 建筑屋顶大块迷彩，门窗像平面贴纸 | 去掉大块掉漆，改为克制干刷；补屋脊、少量接缝、墙角/墙根污迹、深门窗凹口与窗台；车辆只加局部板缝和擦痕 | 墙面/功能结构仍比参考简化，没有把所有建筑重做成高复杂度模型 |
| 桥拱像光滑混凝土洞，单位纸边太亮 | 桥拱和桥墩增加明显砌石线、木板短纹/端钉；单位浅纸边收窄并压暖暗，保留深墨边和选中反馈 | 仍保持原可通行桥几何和单位剪纸设定 |
| 远景虚化较重、场景缺少细微动态 | 稍扩远景清晰范围并降低景深强度；真实蓝军电站烟囱添加少量循环蒸汽 | 没有为静态对比凭空加爆炸；战斗特效仍由真实事件触发 |

## 音效

替换为39个原创CC0、44.1kHz PCM音频，没有外部采样或授权不清的素材。步枪/反坦克/坦克炮/重炮分别有3变体，命中分小中大，毁坏、机械UI和施工声音独立。引擎/履带使用2条无缝聚合音轨，仅统计镜头附近的己方运动车辆；战斗有距离衰减、独立声池和限峰，静音立即停声。

[战场试听](../artifacts/visual_iteration/v44_reference_rebuild/audio/battlefield_audition.wav) · [旧/新交替试听](../artifacts/visual_iteration/v44_reference_rebuild/audio/before_after.wav) · [音频制作与验证报告](../artifacts/visual_iteration/v44_reference_rebuild/audio/AUDIO_REPORT.md)。当前工具没有主观听音能力，因此只确认波形/播放链和映射验证，听感以试听文件为准。

## 性能处理

新松树近景3192三角形，采用离线烘焙的1596及416–630三角形远景LOD；近景position/normal/color/UV逐角保持一致，阴影网格只合并重合顶点。发布版加载烘焙资源，不依赖编辑器的ImporterMesh；源码变化导致烘焙过期时回退程序模型。生成与校验见 `tools/bake_pine_meshes.gd`、`assets/models/pine_meshes.json`，API依据 [Godot 4.6 ImporterMesh](https://docs.godotengine.org/en/4.6/classes/class_importermesh.html)。地表/树木的重复程序噪声改为可过滤的确定性小纹理，避免每像素反复计算。

同机原生1920×1080、100%、256移动单位+32建筑、25秒短压力场：未经LOD约34.54FPS/GPU28.31ms/1653万primitives；最终过滤纹理候选约41.78FPS/GPU23.04ms/365万primitives。同次会话旧v43约50.54FPS/GPU18.77ms。新细节仍有成本，不宣称稳定60FPS；短测并非长时验收。另普通镜头冻结38实体，仅渲染8秒约48.46FPS/p95 22.89ms，明确不是正常玩法帧率。

原始证据：`performance_source.json`、`performance_lod.json`、`performance_filtered.json`、`performance_v43_from_log.json`、`normal_render_profile.json`，均在v44目录。旧程序报告路径未落盘，v43 JSON由其完整BENCHMARK日志无损提取。

## 验证

- 地图/规则65通过，导航62通过；音频专项及39个PCM文件检查通过。真实main帧循环内选择/命令、12次开火、6次命中、实际车辆motion、静音/重开/退出清理通过。
- 三种树的实际base mesh闭合、绕序、法线、占地检查通过（最大半径0.609m，原包络0.62m）；检查器已支持真实ARRAY_INDEX，不降低阈值。LOD保存/重载、索引、AABB、基础属性和精确阴影位置检查通过。
- 崖面128组/16227细节顶点在原facet内；两图11223岸脚石顶点均在水格并避开桥头。桥12组尺寸/方向、38952细节顶点检查通过。树长宽比调整不改变地图、实体或横向占地。
- 地景26通过/2旧高度断言失败，模型5条旧尺寸断言失败。右栏旧测试103通过/27失败；UI旧测试72通过/2失败后因过期fixture中止。这些失败和错误签名已在独立v43旧工程复现；没有把不完整测试写成全套通过，也没有放宽断言。
- 实际导出运行截图、LOD载入元数据、音频资源加载和分发包校验另记录于 `verification.json`；未做长时完整对局或全部平台测试。

## 复现

```bash
godot --headless --path . --script res://tools/bake_pine_meshes.gd
python3 tools/capture_golden.py --name next --views gameplay,g0,gameplay_barracks --output-dir artifacts/visual_iteration/next --baseline artifacts/visual_iteration/v44_reference_rebuild --fixture data/golden_visual_paintedforest_v9.json
godot --path . --script res://tools/capture_pine_views.gd
python3 tools/validate_audio.py
```

旧v43记录：[备份](../artifacts/visual_iteration/v44_reference_rebuild/previous_art_iteration.md)。完整逐轮A/B、资产诊断和日志保存在v44目录。
