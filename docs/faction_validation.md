# 首发双阵营与空军验收

当前建筑已经按原始示意图补回完整主体体量；最新22建筑原图/前后对照、545项体量检查、54点屋顶点选和既有遭遇战回归限制见 [本轮建筑修复报告](building_reference_repair.md)。以下首发记录保留其历史验收结果，不代表当前全部自动遭遇战均通过。

依据阵营设定 v4，2026-10-02 制作。正典军团与重锤军团共 23 种单位、26 种建筑；保留历史稳定 ID，实际公共名称、属性和对白在 `data/rules.json`。

## 可查看成果

- [正典完整模型](../artifacts/factions/kestrel_roster.png)
- [重锤完整模型](../artifacts/factions/rivet_roster.png)
- [同阵营的独立玩家识别](../artifacts/factions/player_identification.png)
- [机场生产界面](../artifacts/faction_validation/airfield_production.png)
- [空中单位、返航状态与字幕](../artifacts/faction_validation/aircraft_return_subtitle.png)
- [42 个体积场景与7种纸片步兵索引](../artifacts/faction_models/index.json)
- [全部建筑的同色轮廓对比一](../artifacts/faction_validation/faction_shape_review_1.png)
- [全部建筑的同色轮廓对比二](../artifacts/faction_validation/faction_shape_review_2.png)
- [全部载具的同色轮廓对比](../artifacts/faction_validation/faction_shape_review_3.png)
- [步兵纸片剪影对比](../artifacts/faction_validation/paper_infantry_comparison.png)
- [三视角几何轮廓验收数据](../artifacts/faction_validation/geometry_comparison.json)
- [数值、科技树、用途与对白表](faction_catalog.md)

42个体积模型覆盖建筑与载具，包含可旋转炮塔、履带/车轮与航空厚翼。7种步兵保留纸片、五动作、薄切边和固定80°镜像。正典固定蓝漆，重锤固定暗红漆；两方均可使用橙黄或青色玩家识别板。步兵通过35张同UV专用遮罩，仅更换头盔/肩背所属牌。

除围墙与拒马外，所有对应资产按派系重做轮廓，停止使用demo模型换色归入新阵营。正典使用高斜肩工程坦克、四轮侦察车、细雷达防空、尖长后掠战机、双尾撑攻击机、高斜撑守备塔和拱架工业设备；重锤使用低宽叠甲坦克、六轮侦察车、履带箱式导弹仓、钝宽双动力双尾战机、双巨引擎直翼轰炸机、低装甲炮堡和压梁/夹臂设备。两军步兵分别采用斜帽与长外套、平顶盔与厚方肩甲。

## 专项验收

| 检查 | 结果 | 覆盖内容 |
|---|---|---|
| 阵营目录 | 436 项通过 | 完整目录、名称、说明、数值与科技、动画卡片、35纸片遮罩、单位对白、体积模型 |
| 空军与支援 | 57 项通过 | 直飞越障、空地攻击隔离、移动目标导弹、机位及队列预留、有限弹药、返航与低电补给、机场损失、工兵/维修站付费维修、前哨建设、存档与非法状态拒绝、AI 混合军队与晚期攻坚 |
| 视觉专项 | 2108 项通过 | 42体积+7纸片、固定阵营涂装、玩家牌、35实像素遮罩/材质绑定、纸片状态/镜像/死亡/血条、24组轮廓对比、航空高度/弹道/空爆、两方电站真实蒸汽渲染 |
| 界面与语音 | 414 项通过 | 96 条中文 PCM 语音、来源、对白覆盖、独立播放池、字幕、对白时降低音效、静音、机场卡片与容量、弹药/补给显示、空中点选和框选、地面影子不抢选中 |
| 模型几何 | 42 模型通过 | 336 枪口朝向、12 回弹、法线/体积/缓存与实体朝向，主战坦克真实宽度不超并排间距 |
| 独立场景导出 | 42 个重新加载通过 | 保留 Body、Turret、Muzzle 与玩家/阵营识别元数据；不再导出3D步兵 |

轮廓验收从实际网格三角形和法线生成三个视角的灰度深度图，忽略涂装，并分别归一化整体尺度，防止单纯换色或放大通过检查。24组涵盖全部19组对应建筑/载具、3组对应纸片步兵，以及两军内部截击机与对地机的角色区别；阈值未因模型失败而降低。真实截图另有每对的彩色与同色版本（`artifacts/factions/pairs`，38张）。

语音共 244.85 秒，为机器合成临时配音，游玩时从本地 WAV 播放。manifest 保存每条文本、供应方、客户端版本、时长和 SHA-256；逐条验证文件哈希及非空 PCM。单位语音与既有原创程序化音效的来源、许可分别记录于 `assets/LICENSE.md`。

## 自然 AI 航空发展

两个阵营都在初始总部加 4000 资金的开发地图中，通过真实采矿与付费建设发展出飞机。探针仅提高玩家总部生命以免提前结束，没有给 AI 加钱或免费单位。此前航空预算补丁的观测为正典1418.5秒、重锤1326.5秒；此时间不代表最终版固定时序。记录注明观测阶段，`tools/probe_ai_aviation_growth.gd` 可重新测量。

AI 会预留指挥中心、机场及航空订单资金，避免地面队列持续抢走预算；防空车投入与敌机规模对应，并保留对地攻坚兵力。420 秒后少量对地部队也会继续攻击，避免晚期始终等待五人编制。

## 回归夹具修正

旧 UI 测试仍假设已经移除的固定右栏，现改为检查实际全屏战场、四种窗口尺寸、浮动面板拦截、小地图操作、渲染倍率与准确点选。步兵朝向检查保持纸片80°镜像、原卡片血条及世界朝向。

角落通行测试原本在 30.47 秒因敌总部被自动火力摧毁而结算冻结，未运行足 65 秒。测试将敌总部移离路线，并增加完整运行时长和未结算断言；原来的 30/30 通行门槛及 65 秒时限保留，未修改导航实现。

地面网格含有后续美术版本加入的装饰碎纸石块。地形测试区分真实可行走地面顶面和这些装饰，保持实际地面高度误差的严格要求；不因装饰顶面的抬高整体放宽地形验证。

付费遭遇战控制器使用新科技树、火炮与航空预算，命令遵守武器攻击域，晚期允许少量部队攻坚。胜负仍要求一方全部建筑真实被摧毁，不用强制结算、免费资源或删除敌军来通过测试。

## 复现

```sh
./tools/test.sh
godot --headless --path . --script res://tools/export_faction_models.gd
godot --path . --script res://tools/capture_faction_roster.gd
godot --path . --script res://tools/capture_faction_pairs.gd
godot --path . --script res://tests/faction_ui_audio_tests.gd -- --capture-dir res://artifacts/faction_validation
```

重新制作中文语音需 `ffmpeg` 和 `tools/faction_requirements.txt` 中的可选 Python 依赖；已有配音不依赖网络。新单位数值是首轮基线，长期对战平衡和真人配音尚未开展。本轮不扩展铁钉、天翼、战役脚本或战争迷雾。

导出包可用 `./artifacts/linux/PaperFront.x86_64 --headless -- --verify-factions` 校验嵌入的全部模型、96 条配音、规则与真实开局。release模板不提供编辑器的 `--script` 开关，因此该检查通过实际应用入口执行。

最终完整回归 `tools/test.sh` 退出0；最终补充视觉2108项、真实UI截图416项与导出程序 `--verify-factions` 均通过。日志和摘要位于 `artifacts/faction_validation/`。
