# v7 整合与验收 · 2026-10-05

本轮按最新指令接收现有 Godot 工程修改并统一入口；没有同步到 Rust/Bevy 项目、上传、公开发布或提交商店。真实工程位置 `/home/gc/workspace/paper_war`，本机 ThinkBook，Godot 4.6.2，实际 GPU 为 Intel Arc（MTL）。已有源文件先备份；Git 新建 `main`，保留所有工程内容及旧发布归档。`.godot/`、`artifacts/`、本机私有配置和编译缓存不纳入源码提交。

## 当前行为

| 用户要求 | 实际整合 |
|---|---|
| 单一启动入口 | 根目录 `./run.sh` 永远启动当前源码；`tools/run.sh` 只转发；检测资源变更后导入，避免旧发行程序/音频缓存覆盖新版 |
| 舒缓音乐、各图不同 | 十二首低音区慢节奏原创音乐；六张320地图及教程分别独立主题，另有菜单、通用旧图/试验场及三个结算曲目；1.2秒淡出/淡入 |
| 删除截图四图 | 经典河谷、经典随机、山地盆地、巨型山地不再出现在新局菜单；旧偏好回退森林；历史存档与机械生成器保留 |
| Debug 可选 | 统一设置中默认关闭、可保存；普通对局只看诊断，资金/生成等规则工具明确限制试验场；dev地图仅在用户启用后列出 |
| FPS 常驻 | 唯一 CanvasLayer 7 的角落纸签，0.5秒更新；入口、设置、Wiki、加载、暂停、战局、结算均保留，并且不截获鼠标 |
| 平民2D纸板 | 城市现有三批次换成原创平面剪纸，保留路线和地形定位；随相机朝向保持可读轮廓 |
| 统一设置 | 齿轮直接打开同一个声音/画面/镜头/调试面板；原菜单俯角与debug图形重复控件撤下；Esc保留战局菜单 |
| 有意义的应答 | 四阵营二十条正确普通话音素的短句，字幕与实际词句一致；归零、静音、待应答与混音降低均验证 |
| 明显的无视野区域 | 当前可见区域原像素不变；无视野区域明显深暗、探索过但失去视野为冷灰滤镜；权威视野和敌方最后已知规则不变，探索可存档 |
| 每个建筑扩展 | HQ 24格、分基地20格、其它普通建筑6格、墙/拒马3格；所有60种建筑完工后均有扩展。敌方、死亡、未完工不授权；原6格付费防线延伸、地形/占地/前置/费用保留 |

协作任务显式使用 `gpt-6.1-sol` / `ultra`，文件所有权划分，Godot/GPU检查串行执行。

## 本轮实际证据

- 建造范围635/0；包含全部60类、远程工兵现场施工、实际微圈放置、AI、旧规则快照与费用。`artifacts/revision_v7_integration/final_cpu/construction_range_v7_tests.log`。
- 世界/探索42/0；严格地图模式、尺寸、种子和JSON数值兼容，坏数组/对象字段不改变视野。`final_cpu/world_visual_v7_tests.log`。
- 原生迷雾：24组逐字节全等，另含3阶段公开接口native/fallback一致。报告中的925441计数包含批量比较的字节数，不能解释为同数量独立玩法用例。`fog_native_equivalence.json`。
- 固定320地图、2m RG8、0.2秒刷新、相同查询序列，38/80/150移动观察者单次采样中位数由55.229/114.324/212.526ms降为1.008/1.951/3.526ms；静止零查询。`fog_cpu_before_native.json` / `fog_cpu.json`。这是CPU采样成本，没有据此宣称整局FPS或降低画质。
- 真实Forward+ GPU视觉31/0，1080与1100×700页面、两角度平民、视野对照、实际探索存档恢复。49个清晰样本亮度变化中位数0.0；1186个无视野样本亮度比0.386826。`visual/report.json`、`visual_final.log`及实际PNG。
- 界面/新局/设置/FPS/普通局防作弊/保存重开退出等专项通过；主要日志为`ui/results.json`与`runtime/results.json`，含135/73/143/178/377项的各自范围；未将它们当作一次完整回归。
- 音频专用1334/0，最终32个新PCM/来源673项，全部75个当前PCM格式/峰值检查通过；最终普通话音素与加载stream时长一致。`artifacts/revision_v7_audio/final_summary.json`及独立审查`artifacts/revision_v7_audio_review/REVIEW.md`。
- 实际热混音10/0，独立音量、静音恢复、切歌；Dummy音频驱动，不是扬声器试听。`runtime/demo_audio_mix_tests.log`。
- 建造通道、分基地71、工兵67、规则189、运输世界13、百科12020、海军12、跨岛运输58各自通过；`mechanics/results.json`。跨岛脚本第一轮默认将旧`artifacts/demo_20261004/transport/current.json`更新为本次结果，历史正式归档与冻结证据未改；不把该current路径作为旧版本证据。
- 最终墙连接337/0、原生生命周期、原生实体步进6002/0及菜单178/0复验，严格日志无Script/ERROR/ObjectDB/RID泄漏。`runtime/results.json`。
- 实际主场景源码与Shipping独立程序各45/0，涵盖真实资源、音频、设置、胜败（披露的建筑消除夹具）、返回菜单、重开和退出。`runtime/source_demo_runtime.json`及`artifacts/revision_v7_release/shipping_runtime.json`。
- 本轮实际付费战役教程65/65，AI开启，525.533模拟秒胜利，采矿、现场施工、运输与最终进攻均经真实命令完成；`campaign/live.json`与`campaign/live.log`。
- 独立整合审查已关闭待验事项，校对源码及原生库身份并直接查看新截图：`artifacts/revision_v7_integration_audit/final_audit.md`。

以上为本轮专项与集成检查；没有宣称完整`tools/test.sh`全部运行、96单位窄路稳定或全地图长期平衡。旧Shipping03/v6数值属于历史。

## 发行、来源与边界

独立Linux包位于`artifacts/revision_v7_release/`，需要Linux x86_64、glibc 2.38+及Vulkan。源工程统一入口仍为`./run.sh`。当前native SHA为`22891f08d0129a734a2b0ea3ba8180ad9ea141fe88b8d89b914c52aa21a9faec`，完整编译来源与GNU运行库例外记录在`assets/native/compiler_runtime_provenance.json`。包的二进制/PCK/源码库存身份和归档校验分别留在manifest、PCK审计及BUILD.sha256中。

音乐为原创CC0；普通话应答采用保守GPLv3+分发并附完整对应源、确切Ubuntu1.51+dfsg-12build1官方orig/debian/DSC及项目生成材料。归档摘要与DSC字节数已核验，未声称验证DSC签名或位级重编译引擎。旧EdgeTTS录音与用户参考图排除玩家PCK。Godot/godot-cpp MIT、Noto字体OFL、MakeHuman仅CC0图形及GNU运行库声明均随包；见`assets/LICENSE.md`、`docs/demo_credits.md`与`tools/source_assets/espeak-ng/README.md`。

实际试听仍需用户判断；机械合成应答不是自然真人配音。初版错误中文模式、错误CC0前提、音频QOA导入格式失败、权限错误以及首轮GPU取样坐标失败均保留，最终验证使用修正版。同名PCM已明确重新导入并核对加载时长。

阵营/UI音频测试曾出现退出ObjectDB警告；修正测试在异步校验栈返回后清理，最终377项及严格日志通过。verbose引擎退出仍可见既存11个orphan StringName，未表现为本轮ObjectDB/RID泄漏或运行故障。保持原始记录，不将它们隐藏为音频专用PASS。
