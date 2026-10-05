# 入口菜单与军团 Wiki

2026-10-02。入口菜单为全屏纸板桌面，提供开始战局、Wiki、读取存档、声音及退出。开始战局进入原有阵营/地图设置；进行中的战局也可返回入口继续。

## Wiki 浏览

- 当前正典与重锤共49项资料：23单位、26建筑；阵营、单位/建筑分类和名称/型号/用途搜索可组合。
- 上方为独立旋转展台：42个真实体积模型，7个原纸片步兵。保留原有纸片厚边、两队识别色与最新建筑体量，不在Wiki中替换资产。
- 模型可自动旋转、拖动、暂停、复位和切换识别色；相机按真实几何边界和完整旋转范围自动取景。
- 下方有介绍及按主题分组的属性—数值表，滚动查看全部数据，包括武器倍率、弹药、机场容量、生产前置、经济/维修参数与语音文本。
- 数值直接来自当前规则文件，未知新增数值或布尔字段亦会收录；文件路径等内部资源配置不进入介绍表。
- 空搜索释放旧模型并显示提示；关闭或隐藏预览停止渲染。局内浏览临时暂停模拟，关闭后恢复此前暂停状态，鼠标和键盘不会穿透到战场。

## 验证

数据覆盖4087项、预览6244项、入口/表格/筛选/状态恢复637项检查通过。预览覆盖49条目、两种识别色、三种比例和八个角度；实际GPU渲染55张预览图无空白或裁切。

旧UI86项、视口130项、航空UI/音频414项也通过。新增模块没有修改战斗规则或模型几何。本工程此前记录的一项自动遭遇战长时间未结算问题仍单独保留，不用本轮Wiki专项结果替代该记录。

[入口截图](../artifacts/wiki/entry_menu.png) · [建筑页面](../artifacts/wiki/wiki_kestrel_hq.png) · [航空页面](../artifacts/wiki/wiki_rivet_bomber.png) · [纸片步兵](../artifacts/wiki/wiki_kestrel_rifle.png) · [武器数值表](../artifacts/wiki/wiki_weapon_table.png) · [小窗口](../artifacts/wiki/wiki_small_window.png)

实现位于 `paper_entry_menu.gd`、`paper_wiki.gd`、`wiki_catalog.gd`、`wiki_model_preview.gd`。数据与模型预览都不依赖战局模拟；页面采用原生Godot控件、已有纸板绘制层和独立SubViewport。

```sh
godot --headless --path . --script res://tests/wiki_catalog_tests.gd
godot --headless --path . --script res://tests/wiki_preview_tests.gd
godot --headless --path . --script res://tests/wiki_ui_tests.gd
godot --path . --script res://tools/capture_wiki.gd
./artifacts/linux/PaperFront.x86_64 --headless -- --verify-wiki
```
