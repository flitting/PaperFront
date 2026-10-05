# 本次美术迭代总体进度

按用户最新要求：所提各点完成尝试并汇报后，结束本次任务。**任务收尾不等于美术最终定稿**，原两张概念图仍是最终风格目标。

原图：[概念图1](preview_design1.png)、[概念图2](preview_design2.png)。[用户红警2山崖图](references/ra2_cliffs_user.png)仅辅助山缘设计，未替代纸模目标。

## 保留结果与回退

| 方向 | 当前处置与实机结果 |
|---|---|
| 纸质UI | 保留参考式顶部资源/时钟、底左小地图、底中条件卡片及底右墨线指令；选总部显示建筑，选兵营/工厂显示本建筑产品，空选/非生产选择无建造卡。Debug在设置右侧。 |
| 单位留边 | 保留步兵与履带车的浅纸色空白及外墨边；硬卡厚度与独立车辆/炮塔变换保持。 |
| 车辆 | 保留较小整体比例，再调整tank/assault宽高、厚炮塔、粗连续履带与低腹闭实；harvester此次未整体重做。微小顶角倒角无正常视角收益，已撤。 |
| 建筑辨识 | 保留精炼厂低厅+大料斗、兵营双低折顶、工厂宽卷帘门/窗分离。两高折厂顶A/B像竖纸鳍，已恢复旧厂顶，不宣称所有建筑都已充分辨识。 |
| 人物/图标 | 保留7兵种×5状态的35张原生SVG更新：较小盔头、长腿、弯肘持工具、斜带/大衣褶与枪托墨块；兵营生产图标同源更新。57张其它资产保持。普通视角脚点、衣身和工具仍清楚。 |
| 硬纸壳树 | 保留本次闭合冠体的单瓣折脊、有限纸芯切边与印绘枝纹；正常前景有可见纸壳面感，绿色林冠未损失。仍有尖锥/重复层形，未达到概念图精致程度。此前圆肩金环、开放折片、微拓枝端均无益或退步，已撤。 |
| 地面/布景 | 保留弯曲浅路、连贯暗土与亮路心、林缘/崖脚/岸边低碎屑，中景断墙、沿台肩至台脚前林及与哨塔相连的后林。没有靠裁图或加重模糊改变验收。 |
| 山崖/岸缘 | 原共享削角、完整阴影保留。后台顶96格削减未击中正常主壁；成组V形内凹像杯槽/低多边形折壳，均撤回。山缘主要规则感仍未解决，红警辅助图已保存。 |
| 河流 | 保留深浅色域、短波纹、岸礁与13格有效小湾。长流纹像面条、北湾扩张成尖嘴/阶梯岸缘，均回退。整体流动与自然河岸感仍有差距。 |
| 矿石 | 两轮低矮碎簇变成稀疏纸旗，整簇读形退步，已恢复原晶矿模型；没有将试验失败写成完成改善。 |

## 实机证据

本批比较：[最新反馈前v35普通图](../artifacts/visual_iteration/v35_north_context/release_v35_gameplay.png) → [本次保留版普通图](../artifacts/visual_iteration/v42_final/final_gameplay.png)。两图正常43镜头/时间/分辨率/界面/实体与地图相同，主要差异是车辆、建筑、人物和树；不从压力场远景推断比例。

[兵营卡片实机](../artifacts/visual_iteration/v42_final/final_gameplay_barracks.png)、[G0宽视角辅助](../artifacts/visual_iteration/v42_final/final_g0.png)。接手最初基线、各轮失败图/patch和运行日志保留在artifacts/visual_iteration与历史记录；UI全宽布局改变单独记录，没有算作模型改善。

每轮实际Forward+运行，场景/相机就绪后8次真实frame_post_draw，仿真135tick/4.5s、视觉时钟0，1920×1080/100%原生；每轮PNG均实际打开再决定保留/回退。只做相关最小启动/接口/轮廓/绘制检查，未用全面回归、长时性能或日志代替美术验收。

## 可重复命令

```bash
python3 tools/capture_golden.py --name review --views gameplay,gameplay_barracks,g0 --output-dir artifacts/visual_iteration/review --baseline artifacts/visual_iteration/v42_final --fixture data/golden_visual_northforest_v7.json --prepare-assets
```

自动完成SVG/资源导入、运行加载固定场景、恢复镜头与选择/UI、等待真实渲染、批量保存PNG+JSON+日志与成功/失败状态、自动退出。重复运行用新name/目录以保留前图。开发入口不作用于正常经济开局，shipping导出不开放Golden入口。

## 仍未定稿的差距

大片平整空台地和规则岸崖、树冠精细枝形、原图的整体密度与手绘磨损仍未完全达到。单位纸边仍偏醒目，远处人物细节很小；精炼厂/兵营静态建筑卡图还应与新世界模型进一步统一。这些列为遗留，不继续新增本次轮次。

代码、原始资产、有效版本与精确命令的接续索引见[art_iteration.md](art_iteration.md)及artifacts/visual_iteration/current.json。本次任务按用户新停止条件结束；后续是否继续和美术定稿由用户决定。

保留程序：artifacts/linux/PaperFront.x86_64；分发包：artifacts/PaperFront-linux-x86_64.tar.gz。最终构建SHA256 `e5c4d5bbfeb49e421e0239f412027d92080bf59310cc9ce4b7aaf521859bb160`，BUILD.sha256已同步。原v38程序备份v42目录；代码与原始资产快照见v41 source_retained。
