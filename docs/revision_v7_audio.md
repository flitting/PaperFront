# v7 音频实现与交接

2026-10-05；音频所有者修改范围仅为 `scripts/paper_audio.gd`、`scripts/paper_music.gd`、两个专用生成器、`assets/audio/`、专用音频测试和此记录。修改前五个旧 scene WAV、二十个旧 radio WAV、原代码、清单、导入元数据与专用测试共60文件已逐字节备份，SHA-256 见 `artifacts/revision_v7_audio/backup_manifest.json`。没有覆盖主程序、设置、世界、模拟或地图配置。

## 实现

- 十二首低音域、缓慢、软起音原创配乐；其中七首对应森林、沙漠、雪地、城市、随机城市、海岛和原教程，调试与历史旧图使用通用战局主题。曲名、音域与可复现 SHA 见 `assets/audio/music/manifest.json`。
- 二十条带意义的普通话短应答；本机 eSpeak NG 1.51（Ubuntu 1.51+dfsg-12build1）原生 `cmn-latn-pinyin+m3` 离线合成，四阵营各选择/移动/攻击/就绪/返航五种。播放词句和中文字幕共同使用新 `radio/manifest.json`，字幕保留单位名，覆盖规则中每个可应答单位动作。
- 一次只有一个语音播放器；不在词句中途切断，保留单条待应答命令。应答时降低音效 5 dB、音乐 3.5 dB，偏好值保持不变。独立总音量/音乐/音效/应答静音及恢复行为继续保留。
- `PaperAudio.set_map(value: String)` 转发到音乐。地图切换即使仍是 `battle` 场景也会请求对应曲目；单播放器1.2s淡出换轨淡入。

## 主程序集成

在 `_sync_audio_scene()` 选择战局或结果前调用 `audio.set_map(str(sim.map.get("mode", "")))`（仅在 sim 非空且有 map 时）；新局/读档完成时也可调用同一 API。保留原 `audio.set_scene(menu/battle/win/lose/draw/silent)`。API 本身对相同 ID 是常数时间的早返回。

项目总素材许可 `assets/LICENSE.md`、`docs/demo_credits.md` 已由主任务所有者更新为“十二首低音域独立地图配乐/二十条离线普通话短应答”，并指向新的音频说明；music CC0、radio GPLv3+、独立生成工具与第三方引擎/字典许可范围已分别说明。发行脚本也已加入完整sourcekit交付和源/工具hash检查。

## 授权与验证边界

授权来源、eSpeak GPL输出条款解释、Unicode来源和完整许可见 `assets/audio/README_demo_original.md`、`assets/audio/licenses/`。本项目不恢复缺少授权证明的旧EdgeTTS，也不下载Piper许可不清晰的中文声音。没有在线语音服务、模型或采购操作，游戏无合成引擎依赖。官方Ubuntu对应源下载已成功完成，并按DSC SHA-256与长度核验。配乐与生成器CC0；中文PCM及专用语音工具保守GPLv3+，项目原创短句另可CC0。

静态/PCM检查并非实际听感验收；机械formant中文不是自然真人配音。具体回归检查与结果见 `artifacts/revision_v7_audio/pcm_validation.json`、主程序整合后的独占Godot音频回归报告。

## 授权审查后的修正与发行源包

原生普通话也调用上游辅音WAV资源，不能说全部纯数学原创或无第三方样本。输出采用GPL-3.0-or-later保守分发策略，完整对应源在 `tools/source_assets/espeak-ng/`，包括exact installed包版本的DSC、完整orig与debian补丁archive、完整版权/GPL/Unicode文本、项目生成器、对白参数、最终manifest及可直接修改的原始二十条PCM。普通话直接引用的十五个源WAV在archive内全部核对存在。根任务发行脚本必须把整个sourcekit和 `assets/audio/licenses/` 随游戏交付；恢复生成器的目录结构及source解包方法写在sourcekit README。源download manifest诚实区分DSC摘要核验与未本机验证的DSC签名，不作额外保证，不推断全游戏改为GPL。

音素审计捕获本机默认cmn模式内部pinyin被当成英语读出的问题，全部voice已改cmn-latn-pinyin+m3。每clip的TextToPhonemes结果均保存在manifest，生成工具拒绝(en)英语切换；返航句采用“返航，补充弹药。”，避开补给多音字误读。最终二十句总时长39.706s。讲话中voice/master滑至零时立即停止旧语音和清pending，新命令字幕不受无声旧播放器或冷却限制。

## 验证记录与状态

独立PCM测试报告为 `artifacts/revision_v7_audio/pcm_validation.json`，涵盖最终资产、音素、声音/音乐各自许可、原始WAV与完整对应源一致性。全目录PCM基线检查为 `all_pcm_validation.json`，来源函数边界不证明实际听感。Godot初轮默认user日志写权限导致启动crash，改/tmp XDG后进入脚本；首次七个新地图默认QOA导入被format检查发现，已保留默认metadata备份并改PCM16，无省略失败证据。审查前1308check PASS在retry2日志；审查后的最终二十条WAV已在root授权的独占槽重新import，最终音频1334检查PASS、完整阵营/UI/音频377检查PASS；无并行Godot运行。

最终报告：`godot_audio_final_validation.json` 为1334checks/无失败；`godot_audio_final.log` 无退出泄漏警告；`godot_faction_audio_final.log` 为377checks/无断言失败，但全场景测试末尾有ObjectDB instances leaked警告，已交根任务检查UI场景测试teardown归属。PCM专用673checks/32资产PASS、全音效75文件PASS；独立审查逐20音素与本机API吻合，完整sourcekit校验通过。音频所有者未把这些测试当作自然真人音色或实际听感保证。
