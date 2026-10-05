# 铁钉与天翼修订验证 · 2026-10-03

用户本轮说明将铁钉调整为结实可靠、认真维护的工业军团，将天翼调整为少量纸盒、纸筒和折板组成的粗简纸模，但保留真实先进武器能力。源工程、生产目录、Wiki 和 Linux 独立程序同步使用该修订。

## 已完成

- 修订两阵营全部 33 种单位的名称、正式型号、说明与对白；保留稳定 ID。额外的 `iron_rig` 作为吊装工程车保留。
- 重绘六种步兵的 30 个纸片状态及其玩家识别遮罩、实体切边；步兵仍为纸片。
- 更新 57 个实体模型：铁钉 15 建筑、14 载具/飞机；天翼 15 建筑、13 载具/飞机。原画质材质、描边、阴影、独立炮塔、枪口、后坐和玩家识别保留。
- 为维修车接入付费目标维修；同目标维修来源取最高速度。拖救护送只作用于存活友军，生命≤60%且撤离时提供不叠加的速度增量。
- 标定需要距离、视线与持续跟踪；蓄能需要资金、电力余量、短窗口与散热，不叠加同类增幅。先进武器增加短暂导轨亮线与紫色能量弹表现。
- 机场维护飞机按实际生命付费。四座运输机在返航补给后停机装卸，支持多名所选步兵一次右键登乘；空中不能装卸，机场外围围墙与地形继续阻挡通行。
- HUD 显示支援状态，Wiki 展示机制参数与操作说明；存档检查接受并验证新增命令和状态。

## 验证结果

| 验证 | 结果 |
|---|---|
| 新机制专项 | 53 项，0 失败；含维修不叠加/资金不足、存亡拖救、标定断视线/跨河观察/高地遮挡、蓄能范围与余电、空运存档及围墙阻挡 |
| 实际操作输入 | 6 项，0 失败；4 人登机、HUD 卸载、维修车右键与拖救车右键 |
| 模型与纸片整合 | 99 个立体模型、13 种纸片步兵；4116 项，0 失败 |
| 原生/脚本实体对照 | 单线程与后台线程各 6002 项，0 失败 |
| 全部回归入口 | `tools/test.sh` 中全部脚本及附加检查均通过；分段日志见下方 |
| 独立模型导出/重载 | 99 模型、13 纸片条目，0 失败 |
| Linux 内嵌资源检查 | 56 单位、56 建筑、4 阵营；新版名称和支援参数存在，正典/铁钉/天翼启动成功，0 失败 |

初次回归发现铁钉矿车型变更使旧 LOD 来源签名失效。已重新烘焙索引并通过来源检查。游戏继续使用完整细节模型；本轮没有重新测量帧率。

日志：[机制](../artifacts/faction_revision/mechanics.log)、[操作](../artifacts/faction_revision/support_input.log)、[模型](../artifacts/faction_revision/visual.log)、[完整回归](../artifacts/faction_revision/regression_passed.log)、[发行资源](../artifacts/faction_revision/exported_factions.log)、[发行 Wiki](../artifacts/faction_revision/exported_wiki.log)。

## 实际显示

单位：[铁钉全单位图](../artifacts/faction_revision/iron_units.png)、[天翼全单位图](../artifacts/faction_revision/sky_units.png)。

实机：[铁钉战场](../artifacts/faction_revision/battle_iron.png)、[天翼战场](../artifacts/faction_revision/battle_sky.png)。Wiki：[磐石坦克](../artifacts/faction_revision/wiki_iron_tank.png)、[试验坦克](../artifacts/faction_revision/wiki_sky_tank.png)、[扳手维修车](../artifacts/faction_revision/wiki_iron_repair_vehicle.png)、[标定车](../artifacts/faction_revision/wiki_sky_designation.png)。截图采用实际 Vulkan Forward+ 渲染，非概念图。

## 运行与边界

使用 `./tools/run.sh` 或 `./artifacts/linux/PaperFront.x86_64`；分发包为 `artifacts/PaperFront-linux-x86_64.tar.gz`。运行时必须保留同目录的原生库。源码/规则/资源身份见 `artifacts/faction_revision/runtime_manifest.json`，程序校验见发行目录的 `BUILD.sha256`。

旧存档保留自身规则快照，新版名称与支援参数需要新开战局。已存在的旧独立进程也需退出后重启。

可选加固/机动改装、额外 EMP/断电/失控、独立侦察揭雾与闸门开闭尚未接入。新增对白是文字与字幕，本轮未增加合成语音录音。单位数值仍属当前基线与机制初值，没有宣称完成长期对战平衡。
