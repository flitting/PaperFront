# 原创素材许可与来源

`cards/*.svg`、`cards/contours.json`、`icon.svg`、`pitch_knob.svg` 是本项目通过 `tools/generate_art.py` 和独立图形代码制作的原创插画与轮廓数据，未下载第三方模型或商用游戏素材。现有地面与界面 `audio/*.wav` 是 `tools/generate_audio.py` 独立制作的原创分层声音：步枪、反坦克、坦克炮、重炮各三种开火变体，小/中/大爆炸与载具毁坏变体，机械操作与建筑、交付、完成、出售、低电、胜负反馈，以及无缝车辆引擎/履带循环。源信号来自确定性振荡器、带限噪声、瞬态包络和延迟反射；没有使用外部录音、音库、商业游戏或第三方样本。全部采用 44.1 kHz、单声道、16-bit PCM WAV，生成源代码可复现。

`scripts/volume_models.gd` 与 `scripts/landscape.gd` 中的纸模建筑/载具、纸张纹理 shader、体积森林、岩石、晶矿及桥梁设计由本项目制作。巨手的连续人手基础网格来源见下述单独记录。

上述本项目原创素材按 CC0 1.0 提供，可自由使用、修改和再分发，无强制署名要求。CC0 说明：<https://creativecommons.org/publicdomain/zero/1.0/>。

Godot Engine 为 MIT 许可，版权属于其作者及贡献者。引擎与第三方依赖版权可在 Godot 的 About / License 中查看；源工程不修改引擎。界面捆绑 Noto Sans CJK Regular 字体集合，使用简体中文面。该字体来自本机公开 Debian/Ubuntu fonts-noto-cjk 包，按 SIL Open Font License 1.1 分发；完整来源、版权和许可保留在 `fonts/LICENSE.txt`，字体不属于上述原创 CC0 素材。

`docs/preview_design1.png`、`docs/preview_design2.png` 和 `docs/concept_3d_reference.png` 是用户提供的风格参考，保留在文档目录，不作为游戏素材打包；本项目不对它们声明上述原创或许可。

2026-10-04 地图重建的 `assets/map_design_v6/*_minimap.png` 与 `*_panorama.png` 共12张概念图由内置 `image_gen` 生成，用于设计及独立视觉对照；需求、完整提示词和图片校验记录在 `docs/map_design_v6/`。这些图片随交付文档保存，不作为游戏地形贴图或背景替代真实场景。对应3D地形、建筑、植被和附属模型由本项目代码制作。`docs/revision_v6/hand_reference_walk.png`、`hand_reference_attack.png` 是用户本轮提供的造型参考，不属于本项目原创CC0素材。


`audio/fire_air.wav`、`audio/bomb_release.wav`、`audio/rearm.wav`、`audio/aircraft_loop.wav` 由 `tools/generate_unit_voices.py` 使用确定性振荡器、噪声及包络独立合成，属于上述 CC0 原创音效；格式为 22.05 kHz、单声道、16-bit PCM WAV。

历史 `audio/voices/*.wav` 来自 Microsoft Edge 在线中文语音合成服务，通过开源 `edge-tts` 客户端和 FFmpeg 制作，不是本项目真人配音。该银行及旧 `audio/radio/` 应答已于2026-10-06从活动游戏资源移除，来源和许可记录仅保留为历史资料。

上述历史合成语音与供应商模型、服务不属于本项目原创 CC0 音效；原服务条款见 <https://www.microsoft.com/servicesagreement>，客户端来源见 <https://github.com/rany2/edge-tts>。当前游戏不加载或打包该旧银行，也不回退到旧机械应答。

## 当前配音、声效与菜单／交战配乐（v8）

`audio/revision_v8/` 当前活动清单为381项：300条单位语音、2条系统语音、74个声效和5首配乐。语音使用经 OpenRouter 制作的 Microsoft MAI、xAI Grok 与 Qwen 十二个固定基础演员；59个声效通过 Seed Audio 制作，五首活动配乐通过 Google Lyria 制作。供应商生成素材按相应服务条款使用，不宣称 CC0 或真人录音。15条本地DSP声效、项目作者编写的台词及生成工具属于项目原创 CC0；旧地图/结果音乐和实验声音不进入活动试听清单。每个素材的实际来源、模型、提示词及 SHA-256 在对应清单记录，完整说明见 [音频来源](audio/revision_v8/README.md)。下列历史许可不会重新给新版素材改标。

## Demo 配乐与单位应答（v7，历史）

`audio/music/*.wav` 共十二首原创低音区配乐：菜单、通用战局、六张现有地图、战役教程，以及胜利、失败和平局。`tools/generate_demo_music.py` 独立制作旋律、和声、软起音与纸盒节奏，没有外部歌曲、录音或样本；音乐 PCM 按 CC0 1.0 提供。

`audio/radio/*.wav` 为四阵营二十条简短普通话应答。项目自写文本由本机 eSpeak NG 1.51 的 Mandarin 音素模式离线合成，再柔化边缘、低通和调整音量。eSpeak 除 formant 参数外还使用储存的辅音波形，因此不把这些 PCM 标为完全无第三方样本的 CC0。采用保守分发路径：二十条中文应答音频与专用生成工具均按 **GPL-3.0-or-later** 提供，允许商业分发并随包保留许可及完整对应源；项目自写对白仍可按 CC0 提供。

实际合成配置、词句、参数、SHA-256 与来源边界见 [音频来源记录](audio/README_demo_original.md) 和两个目录的 `manifest.json`。`tools/source_assets/espeak-ng/` 保存本机确切 Ubuntu `1.51+dfsg-12build1` 官方源码包、Debian补丁、版权、Unicode记录与项目再生成材料；归档按官方 DSC 字节数及 SHA-256 核验。玩家发行目录保留该完整来源于 `SOURCE/espeak-ng/`。游戏仅加载预生成 WAV，不依赖或执行语音合成库。二十条语音的 GPL 范围不对其它独立素材重新声明许可；旧 Edge TTS 音频继续排除发行包。中文字幕与实际词句一致，静音时仍可显示。

`assets/civilians/paper_civilians.gd` 的三种平面剪纸人物、纸面 shader，以及 `assets/fog/battlefield_fog.gdshader` 的视野滤镜由本项目代码制作，无第三方素材，沿用上述原创素材 CC0。

`cards/*_portrait.png` 为 `tools/render_faction_icons.gd` 对本项目原创真实模型直接渲染的透明生产图标；`cards/*_identity.svg` 为纸片步兵明确编绘的所属标记遮罩。新双阵营图形及对应 `tools/generate_faction_cards.py`、`scripts/faction_building_models.gd` 的原创几何沿用本项目原创素材的 CC0 许可。


## Native performance kernels

`assets/native/libpaper_front_kernels.so` contains project-authored numeric kernels and the MIT-licensed Godot C++ bindings (`godot-cpp`, commit `e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77`). The binding license is included at `assets/native/GODOT_CPP_LICENSE.md`; the pinned build sources are in `native/vendor/`, with `tools/build_native.sh` for reproduction. Godot's copyright and license remain applicable to the engine itself. No native kernel code changes third-party licensing for game artwork.

## 连续人手基础网格

本轮巨手返工采用MakeHuman Community的核心图形basemesh，固定来源commit `a8bc2d54ff0ac92e78ff71431b1023eda42bf482`，裁出单只手、封闭腕端、雕修与重新绑定参考姿态。仅使用其图形资产，没有引入MakeHuman应用程序代码。官方[许可说明](https://github.com/makehumancommunity/makehuman/blob/master/LICENSE.md)将核心图形basemesh/assets列为CC0；原始文件头也明确2020年CC0发布。原素材及SHA-256记录在`tools/source_assets/makehuman/`，随运行包的资产许可与来源副本在`assets/creator_hand/MAKEHUMAN_LICENSE.md`、`MAKEHUMAN_PROVENANCE.json`。


## English speech revision (2026-10-09)

English unit acknowledgements, combat calls, commander reports and spoken power alerts are synthetic project dialogue rendered locally with stock Kokoro-82M voices. Original Chinese recordings remain separate. Model weights and the generation runtime are not shipped; playback uses local PCM WAV files. Model and wrapper attribution, checksum-pinned provenance, generation instructions and output scope are recorded in [the English speech notes](audio/english/README.md) and [provenance](audio/english/provenance.json). Upstream Apache-2.0 and MIT notices are preserved under `audio/english/licenses/`. These assets are not claimed to be human recordings or CC0.
