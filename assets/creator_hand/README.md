# 创世之手模型来源

creator_hand.glb 是从 MakeHuman Community 的 CC0 人体图形基础网格中裁出的左手。生成脚本位于 tools/build_creator_hand.py；可编辑的 Blender 源文件位于 tools/source_assets/creator_hand_source.blend；原始 base.obj 与许可文本位于 tools/source_assets/makehuman/。

生成过程仅取原网格连续手部皮肤，沿腕部截面裁切并以圆润掌根封口，添加 16 骨独立蒙皮、嵌入式指甲材质与游戏坐标。运行时骨骼定位记录在 rig.json。原始完整人体网格不作为游戏运行时资源导入。

来源 commit、原文件校验和与链接见 source_provenance.json。许可副本见 MAKEHUMAN_LICENSE_ASSETS.md 与 MAKEHUMAN_LICENSE.md。
