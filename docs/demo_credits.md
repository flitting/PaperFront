# 纸境战线 · Paper Front Demo — Credits & licenses

纸境战线是本项目制作的独立纸盒风格 RTS。项目原创纸模、美术与合成音效沿用 `LICENSES/PROJECT_ASSETS.md` 的 CC0 1.0 授权。十二首原创舒缓配乐按 CC0 1.0 提供；四阵营二十条中文应答使用离线 eSpeak NG 合成，包含其储存的辅音波形，采用保守 **GPL-3.0-or-later** 分发。独立语音资产与生成工具的完整对应源、确切版本、参数及许可在 `SOURCE/espeak-ng/` 和 `LICENSES/`，不把它们声明为完全原创 CC0。文件和生成器 SHA 在 `PROVENANCE/`。

Paper Front is an independent cardboard RTS. Project-authored artwork and procedural sound effects use CC0 1.0. The twelve original music tracks also use CC0. Twenty Mandarin acknowledgements are generated offline with eSpeak NG, including its stored consonant waveforms; these audio assets and their generator conservatively use GPL-3.0-or-later. Complete corresponding source and generation records accompany them in `SOURCE/espeak-ng/`. The game loads generated PCM and does not require a synthesizer at runtime.

| Component | Source / credit | License record in this package |
| --- | --- | --- |
| Godot Engine | Godot Engine contributors; Juan Linietsky and Ariel Manzur | `LICENSES/GODOT_LICENSE.txt` (MIT); bundled dependencies in `LICENSES/GODOT_THIRD_PARTY.json` |
| Native Godot C++ bindings | godot-cpp contributors, commit `e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77`; project-authored numeric kernels | `LICENSES/GODOT_CPP_LICENSE.md` (MIT) |
| GNU C++ and compiler runtime portions in the native extension | GNU libstdc++ and libgcc contributors; GCC 13 toolchain | `LICENSES/GNU_RUNTIME_LICENSES.txt` (GPLv3 with GCC Runtime Library Exception 3.1); build record in `PROVENANCE/compiler_runtime_source.json` |
| Noto Sans CJK font | Google Corporation; Noto CJK project; local Debian/Ubuntu fonts-noto-cjk package | `LICENSES/FONT_LICENSE.txt` (SIL Open Font License 1.1 for the font) |
| Creator Hand base graphical mesh | MakeHuman Community graphical basemesh, commit `a8bc2d54ff0ac92e78ff71431b1023eda42bf482`; hand extracted, wrist closed and re-rigged by this project | `LICENSES/MAKEHUMAN_CC0.md`, `LICENSES/MAKEHUMAN_LICENSE_SCOPE.md`; source hashes in `PROVENANCE/creator_hand_source.json` |
| Original project assets | Project generation and model code | `LICENSES/PROJECT_ASSETS.md`, `LICENSES/CC0_1.0_UNIVERSAL.txt` |
| Original Demo music | `tools/generate_demo_music.py` | `PROVENANCE/audio_music_manifest.json` (CC0 1.0) |
| Mandarin acknowledgements and generator | eSpeak NG, exact Ubuntu source `1.51+dfsg-12build1`; project-authored dialogue and generation tool | `LICENSES/ESPEAK_GPL-3.0.txt`, `LICENSES/ESPEAK_DEBIAN_COPYRIGHT.txt`, `LICENSES/UNICODE-LICENSE.txt`, `SOURCE/espeak-ng/` (audio/tool GPLv3+) |

字体许可记录中 `debian/*` 的 GPL 声明适用于上游软件包包装代码；本 Demo 仅嵌入字体，不包含该包装代码。MakeHuman 的应用程序代码许可与图形资产许可分开，本项目仅使用 CC0 图形网格，不纳入其应用程序代码。

The font notice's Debian packaging-code GPL section applies to that packaging code; this Demo includes the font under OFL. The MakeHuman hand is derived from CC0 graphical assets; MakeHuman application code is not included.

原生扩展通过 GCC 13 编译并静态链接 libstdc++ / libgcc，附带本机对应工具链的完整版权与运行库例外文本。编译器应用程序本身没有附入玩家包。适用的运行库例外允许符合条件的独立模块目标代码按其自身许可分发，见 [GNU libstdc++ 官方许可](https://gcc.gnu.org/onlinedocs/libstdc++/manual/license.html)；这不把项目原创代码或美术改为 GPL。

工程内旧 `assets/audio/voices/` 在线合成语音有供应方来源记录，但没有本项目可确认的商业再分发授权证据，因此玩家版应排除其音频与导入资源。现有原创中文文案仍作为字幕使用。用户提供的参考图片、AI 地图概念参考图、历史测试截图、开发存档及源工程保留在工程中，不作为此玩家包附件。

Historical online speech audio has provider provenance but no confirmed commercial redistribution record in this project, so its audio and imported payloads are excluded from the player package. Project-authored Chinese dialogue remains as subtitles. Reference images and developer evidence remain in the project. The packaging tool checks the PCK directory; acceptance reports in `VALIDATION/` determine the shipped build's tested scope.
