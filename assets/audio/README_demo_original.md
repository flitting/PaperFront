# 项目配乐与中文单位应答（2026-10-05 v7）

> 本页保留 v7 的历史来源记录。2026-10-06 起，游戏已移除旧机械应答及更早未启用的在线配音，当前语音、独立声效与菜单／交战新配乐见 [v8 素材说明](revision_v8/README.md)。下文的旧语音数量、播放池和 eSpeak 分发流程不描述当前游戏。

## 配乐

`music/` 有十二首本项目原创循环音乐，总时长约 698.70 秒：菜单、通用战局、胜利、失败、平局，以及 `forest`、`desert`、`snow`、`city`、`random_city`、`islands`、教程 `campaign` 各自的主题。调试 `dev` 和历史存档中的旧地图使用通用战局主题。

各地图分别拥有原创和声、旋律轮廓、节奏位置与速度，采用同一柔和中低音域音色。节拍为 64–80 BPM，旋律最高 E4（329.63 Hz），起音至少 45 ms，没有明亮高音铃声、嘶声或尖锐打击。振荡器与包络、圆周排列的自然尾音及反射完全由 `tools/generate_demo_music.py` 编写，未使用外部录音、样本、预设、现有旋律或第三方音乐服务。1.3 kHz 平滑低通限制高频，独立峰值约 -14 至 -17 dBFS。音乐播放器始终只有一个，地图或场景切换先用 1.2 秒淡出，再换曲淡入。

音乐素材与其生成器以 CC0 1.0 提供；游戏运行时只解码本地 PCM，不执行合成。音乐清单记录每曲 SHA-256、生成器 SHA-256、地图 ID、曲名、节奏、音域、峰值、RMS、高频占比和循环边界。

## 中文应答

`radio/` 现在包含四阵营各五条短普通话句子，共二十条约 39.71 秒的**离线机械合成中文语音**。选择单位说明待命、移动说明前进、攻击说明目标及攻击、生产完成说明就绪、飞机返航说明补给。每条播放的文字与字幕来自同一个清单，字幕仍带实际单位名称。多个单位只选一个代表；短句完整说完，最多保留一条后续命令，避免群体叠声或中途剪断词语。

合成来自本机 **eSpeak NG 1.51（Ubuntu 包 1.51+dfsg-12build1）原生 `cmn-latn-pinyin+m3` Mandarin**，调用系统库 `libespeak-ng.so.1`；不使用 Mbrola、在线语音服务、神经模型，也没有新录制单位对白；但原生普通话合成会使用上游 GPL 辅音波形资源，不把它们误称为本项目原创。生成工具通过 Python `ctypes` 同步写入 PCM，游戏和发行包只播放生成 WAV，**不链接或捆绑 eSpeak 引擎**。四阵营使用较低基频、175 语速和受控音域；另做柔和边缘、响度控制、2 kHz 附近的高频搁架与 4.1 kHz 低通，无无线电嘶声或提示蜂鸣。

这些语音不是自然真人配音。PCM 分析可以证明削波、边缘、响度和频谱预算；**清晰度、普通话读音和舒适度仍需实际试听验收**，不能把静态检查当作听感证明。

**中文应答 PCM 与独立生成器采用 GPL-3.0-or-later，原创短句文本额外采用 CC0。** 配乐仍为本项目原创 CC0；语音 PCM 不标 CC0，也不声称完全由本项目数学信号生成。eSpeak [普通话音素源](https://raw.githubusercontent.com/espeak-ng/espeak-ng/1.51/phsource/ph_cmn)及[音素说明](https://raw.githubusercontent.com/espeak-ng/espeak-ng/1.51/docs/phontab.md)表明，辅音除了 formant 参数还播放存储 WAV 波形。因此采用更保守的 GPL 音频分发方式，将实际波形资源也纳入完整对应源，而不是依赖“程序输出当然不受 GPL”这一推断。

GPL 允许商业再分发，须履行许可和对应源交付条件。游戏只是播放独立 WAV，未链接合成引擎；这一音频分发选择不在此推导或改写整个游戏的许可。完整 GPL、上游版权与 Unicode 声明在 `licenses/`；随音频发行必须附带 `tools/source_assets/espeak-ng/` 的**整个对应源包**，不能仅提供上游链接。

- 本机 `libespeak-ng1`、`espeak-ng-data` 确切版本均为 **1.51+dfsg-12build1**；源包从[官方 Ubuntu 目录](https://archive.ubuntu.com/ubuntu/pool/main/e/espeak-ng/)下载，包含清签名 DSC、完整原始源 tarball 和该版本 Ubuntu/Debian 打包及补丁 tarball。两个 archive 的 SHA-256 和字节数逐项符合 DSC。DSC 原签名保存，但未声称本机已验证其签名；验证记录为 `source_download_manifest.json`。
- 完整对应源含所有字典、formant、音素 WAV、voice 定义及生成引擎代码；源清单额外核实普通话直接引用的十五个 WAV 资源均存在。原始许可及版权完整保留，不按项目原创改标。
- [Mandarin 字典源](https://raw.githubusercontent.com/espeak-ng/espeak-ng/1.51/dictsource/cmn_list)说明常用字读音来自 Unicode Unihan；Unicode 商业数据许可及声明随包保留。
- 源包 `project/` 包含项目生成器、可编辑对白/参数、最终音频清单和直接可修改的二十条原始 PCM。清单还 pin 本机库、字典、phondata、phontab、phonindex、intonations 和两个普通话 voice 配置的 SHA-256。恢复与打包方法见源包 `README.md`。

每条对白先通过本机 `TextToPhonemes` 做普通话音素转换，清单保存逐子句结果；若出现英语切换标记 `(en)`，生成立即失败。这修正了本机默认 `cmn` 模式会把内部拼音及声调数字读成英语的问题。返航用“返航，补充弹药。”避免“补给”中给的多音字误读。音素检查也不替代实际试听。
未使用 Piper `zh_CN-huayan-medium`：其[模型卡](https://huggingface.co/rhasspy/piper-voices/blob/main/zh/zh_CN/huayan/medium/MODEL_CARD)注明数据许可 Unknown；继承的 Lessac 基底又涉及[研究用途语料许可](https://www.cstr.ed.ac.uk/projects/blizzard/2013/lessac_blizzard2013/license.html)。仓库 MIT 标识不能充分证明该声音可商用再分发。

`voices/` 的旧 Microsoft Edge 在线 TTS 文件仍属于历史开发资料，缺少本项目可以确认的商业再分发授权。运行时连其旧文字 manifest 也不读取，不恢复或发布旧语音。发行导出继续排除 `assets/audio/voices/*.wav` 及其音频导入产物；旧源文件保留不修改。

## 本地复现与验证

所有音频均为 22.05 kHz 单声道 signed 16-bit PCM WAV。配乐需要 Python 3 与 NumPy；中文语音另外使用已有 eSpeak NG 系统库及 Mandarin 数据。本工具没有联网或在线降级路径。

```bash
OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 python3 tools/generate_demo_music.py
OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 python3 tools/generate_demo_radio.py
OPENBLAS_NUM_THREADS=1 OMP_NUM_THREADS=1 python3 tests/revision_v7_audio_pcm_tests.py
```

总音量、配乐、音效、应答仍使用独立总线及原线性音量偏好；配乐和音效在应答期间轻微降低，结束后恢复用户设定，静音或应答音量为零时依然显示新命令字幕。`PaperAudio.set_map(map_id)` 为主程序提供地图切换 API，与菜单/战局/胜负状态独立。测试 `tests/demo_audio_tests.gd` 覆盖实际加载、地图主题切换、总线与音量恢复、字幕匹配、生命周期；PCM 证据在 `artifacts/revision_v7_audio/pcm_validation.json`。修改前的音频专属文件逐字节备份及 SHA-256 在 `artifacts/revision_v7_audio/before/`、`backup_manifest.json`。

最终二十条 WAV 已重新导入，并通过 Godot 4.6.2 的 **1334 项音频专用检查**（`godot_audio_final_validation.json`）及 **377 项阵营/UI/音频检查**（`godot_faction_audio_final.log`）。这些检查包含实际导入资源时长与最终清单一致性，以识别旧英语语音缓存。独立最终 PCM、音素与完整源检查为 **673 项 PASS**，全音效目录 **75 文件 PASS**。旧 1308 项报告及启动/导入失败日志保留为历史证据，不充当最终版本验证。试听文件与时间轴在 `artifacts/revision_v7_audio/review/`，覆盖七地图、全部二十语句和旧无词电音/新中文的对照。
