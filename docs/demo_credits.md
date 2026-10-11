# Paper Front — Credits and license scopes / 制作与许可范围

Paper Front is an independent tabletop RTS. The player package includes its runtime, current audio and the notices applicable to the included files. **There is no repository-wide license for all project source code.** The licenses below apply to their named components and assets.

Project-authored artwork and procedural audio specifically identified in `LICENSES/PROJECT_ASSETS.md` use CC0 1.0. This does not relicense the font, third-party bindings, synthetic speech, provider-generated audio or user-provided reference images.

| Component | Credit and scope | Included record |
|---|---|---|
| Godot Engine | Godot contributors; Juan Linietsky and Ariel Manzur; MIT and dependency-specific notices | `LICENSES/GODOT_LICENSE.txt`, `LICENSES/GODOT_THIRD_PARTY.json` |
| Godot C++ bindings | godot-cpp contributors; pinned commit `e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77`; MIT | `LICENSES/GODOT_CPP_LICENSE.md` |
| Native compiler/runtime portions | GCC/libstdc++/libgcc and, on Windows, MinGW-w64/winpthread; applicable exceptions and notices | `LICENSES/GNU_RUNTIME_LICENSES.txt` (Linux) or `LICENSES/WINDOWS_NATIVE_TOOLCHAIN_LICENSES.txt` (Windows) |
| Noto Sans CJK | Google / Noto CJK contributors; SIL Open Font License 1.1 for the font | `LICENSES/FONT_LICENSE.txt` |
| Creator Hand graphical mesh | MakeHuman Community CC0 graphical basemesh, commit `a8bc2d54ff0ac92e78ff71431b1023eda42bf482`; extracted and re-rigged by the project | `LICENSES/MAKEHUMAN_CC0.md`, `LICENSES/MAKEHUMAN_LICENSE_SCOPE.md`, `PROVENANCE/creator_hand.json` |
| Identified original artwork and procedural audio | Project-authored geometry, illustration and signal generation; CC0 1.0 within the documented scope | `LICENSES/PROJECT_ASSETS.md`, `LICENSES/CC0_1.0_UNIVERSAL.txt` |
| Current Chinese speech | Synthetic outputs using Microsoft MAI, xAI Grok and Qwen; project dialogue; provider terms apply | `PROVENANCE/CURRENT_AUDIO.md`, `PROVENANCE/audio/` |
| Current generated effects and music | ByteDance Seed Audio and Google Lyria outputs; provider terms apply. Individually identified local DSP effects remain CC0 | `PROVENANCE/CURRENT_AUDIO.md`, `PROVENANCE/audio/` |
| English speech | Project dialogue synthesized locally with Kokoro-82M stock voices. Model Apache-2.0 and inference wrapper MIT notices are retained; no CC0 or human-performance claim | `PROVENANCE/ENGLISH_SPEECH.md`, `PROVENANCE/english_speech.json`, `LICENSES/ENGLISH_SPEECH/` |

Chinese and English voices are **synthetic voices, not commissioned human recordings**. The game plays local audio files and needs no speech model, synthesis runtime, API key or network connection. Provider/model/output provenance remains attached to the actual audio manifests; a model or tool license is not a blanket license for unrelated assets.

Legacy Edge-TTS speech and retired eSpeak Chinese radio are not part of the current player audio selection. Historical source/provenance notes may describe those earlier banks; they do not turn current neural voices into eSpeak audio. User-provided reference images and AI map concept references remain in project documentation and are excluded from player packages.

The MakeHuman application itself is not included: only its separately licensed graphical base mesh was used. Noto's Debian packaging-code notices do not change the font's OFL license. Native compiler runtime exceptions and notices apply to their respective runtime portions, without changing the documented licensing of independent project artwork.

## 中文

《纸境战线》为独立桌面模型风格 RTS。发行包保留实际包含的引擎、依赖、素材许可与来源；**项目源码没有覆盖全仓库的统一许可声明**。

项目原创纸模、美术与程序生成音效，仅在 `PROJECT_ASSETS.md` 明确列出的范围内按 CC0 提供。Godot 与 godot-cpp 为 MIT，Noto CJK 字体为 SIL OFL 1.1，创世之手来自 MakeHuman 单独按 CC0 发布的图形基础网格；没有纳入 MakeHuman 应用程序代码。

当前中文语音使用 MAI、Grok 与 Qwen 合成；部分声效与配乐由 Seed Audio、Lyria 生成，按相应服务条款记录，不声明 CC0 或人类实录。英语语音使用本地 Kokoro-82M 固定预置声音合成，保留模型与工具的 Apache-2.0 / MIT 许可说明、来源、哈希和输出清单，也不声明为 CC0 或真人配音。播放仅使用本地音频，无需模型、API 或联网。

历史 Edge-TTS 与已退役的 eSpeak 中文应答不属于当前活动选择。旧来源说明仅用于追溯，不能据此给新版声音改标许可。用户风格参考与 AI 地图概念图保留在文档中，不随玩家包提供。具体范围以包内 `LICENSES/`、`PROVENANCE/` 和音频清单为准。
