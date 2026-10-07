# 当前音频素材与制作记录（2026-10-07）

这份文档描述当前活动音频素材。文件仍位于 `assets/audio/revision_v8/`，名称保留是为了现有资源路径稳定；最新活动清单是 **381 个音频**：300 条单位语音、2 条系统警报、74 个音效、5 首音乐。历史机械语音已退役，旧地图、结果和菜单曲，以及本轮情绪实验，都不进入活动试听列表。

## 固定演员

每个阵营的步兵、车辆、空军分别使用一个基础演员。每组包含七类普通动作各三句、阵亡四句，共25条；同组所有动作保持同一 voice 参数，运行时 pitch 为1.0。这里的十二种区别来自十二个不同基础演员，不依靠速度或运行时随机音高伪造演员。

| 阵营 | 步兵 | 车辆 | 空军 |
|---|---|---|---|
| 正典 Kestrel | MAI Wei | MAI Bo | MAI Harper |
| 重锤 Rivet | Grok Leo | MAI Grant | Grok Rex |
| 铁钉 Iron | Grok Eve | Qwen Longanlufeng | MAI Lan |
| 天翼 Sky | MAI Mei | Grok Ara | Grok Sal |

保留六组已接受的 MAI 素材，另外六组选择性重制150条，并修正正典步兵两句、重锤车辆两句。原已确认的 v9 修复缓存按当前请求严格匹配复用，防止旧口吃、离题或多字录音重新进入银行。随后对154条进行 ASR，针对发现的三个普通句和三个新演员阵亡片段再做小范围修复。当前所有300条字幕与 `tools/revision_v8_dialogue.py` 的实际制作文本一致。

最初的 Sky 空军 Qwen 女声候选在单文件 A/B 自动听觉复核中仍被认为近似 Iron Lan，因此弃用，换为 Grok Sal。最终同一 WAV 的 Iron Lan / Sky Sal 对照被识别为高音轻女声与低中音男声，可清楚区分。多文件初评存在相互矛盾的性别描述，因此采用单文件、带时间标注的对照做关键复核。报告是模型听觉判断，不能当作人类试听或生物声纹证明；仍建议玩家自行试听。

普通句的低能量长停顿经过保守压缩，当前最长内部停顿 **0.109751秒**，不切分多句批量录音，不改变声调和演员。多音词问题采用明确上下文或替换词句处理，没有把不支持的 SSML 当正文交给模型。正典步兵拖长的阵营名改成『小队集结，听候指令』『步兵小队，准备就绪』；重锤车辆原含多音『重』的两个问题句改为『装甲车组，等你发令』『装甲推进，给我让路』。原『炮弹』易误读的问题句维持已确认的『装填完毕，稳稳命中』修复。

## 音量基准和混音

新默认总音量、音乐、音效、语音均为100%；自定义玩家偏好由游戏保留。为了避免从旧默认滑杆值切到100%造成突然变响，原默认总×分类增益成为固定基准：

| 分类 | 固定线性基准 | 目的 |
|---|---:|---|
| 语音 | 0.85×0.85 = **0.7225** | 保留旧默认有效响度；原普通句素材0.8衰减不重复施加 |
| 音效 | 0.85×0.9 = **0.765** | 当前战斗、建造、移动源再×0.8，因此实际默认战斗音效降低20% |
| 音乐 | 0.85×0.45 = **0.3825** | 保留旧默认音乐参照；新曲再按实际 RMS 标定 |

菜单新曲源 RMS 为旧当前菜单×0.8；新的克制交战曲源 RMS 为旧中间曲×0.6；新危机曲约旧激烈曲×0.9；新的平静曲源 RMS 目标0.065。实际峰值、RMS、使用因子和默认有效 RMS 见 `artifacts/audio_revision_20261007/music_mastering.json`。全部 WAV 具有 PCM 余量，无削波。试听播放器采用相同分类基准、当前玩家分类滑杆和独立0–200%试听滑杆，没有二次变响。

语音仍最多三路，包括应答、交战、受击、阵亡、系统警报。场景音效独立为24路：20普通、1焦点预留、3重型尾音预留，另有发动机、履带、飞机三个聚合移动底层，可听附近双方。总线保留 limiter。焦点优先只在焦点真正发声时压低其他来源；闲置选择不会让整个战场变哑。

群体应答接口 `play_unit_group_voice(spec, action, contexts)` 一次选择一个实际句子和变体，最多三人同句、同演员、pitch1.0，按0、50、100毫秒启动。接受新玩家应答后，它替换两路战斗叙述；slot0正在说玩家命令时则保留当前句，排队下一组。延迟副本共享语音预算，慢帧使用音频播放位置补偿保持相位差；试听、静音、零语音滑杆会清除等待副本。副本不产生额外目录条目。

## 场景音效和音乐

74音效中 **59条为 Seed Audio 生成、15条为原创本地 DSP**。15条包括原始火炮回退、三个循环、建筑电流选中、轻按键、九个新机械纸艺界面提示。九个新提示覆盖 select/command/produce/delivery/sell/low_power/result/error/ui_click，出售使用机械纸板收折而非旧嘟声。天翼能量武器、创世之手分别拥有独立发射/命中三变体，按真实 weaponID/能量元数据路由，不再共用炮弹。新音效覆盖旧银行，目录只展示实际使用资源。

音乐活动来源仅五首：menu、battle_calm、battle_engaged、battle_danger、battle_intense。四首本轮 Lyria 原创制作，已有激烈曲保留。地图无战斗和结果画面共用新平静曲，历史地图、结果曲不再载入。每首新曲约64秒，做两秒循环边界交叉淡化；只有一个音乐播放器，换曲沿用两秒淡出及淡入。

最近十秒内真正开火的存活单位按己方/敌方分开计数，不把目标或建筑计算为额外射手。单次实际交互立即进入克制交战层；己方至少六个射手进入 intense；敌方至少五个、己方零射手进入 danger。第三层一旦选定，数量下降、伤亡或阵营优势变化都不会中途换曲；双方实际开火、命中、交互停止超过五秒后才解除。退出时清除旧射手记忆，避免直接被旧十秒窗口拉回。暂停 API `set_playback_paused(bool)` 冻结真实游标、淡化和战斗时钟，恢复原位置。暂停后开关音频试听页同样保留冻结游标：针对 Godot 暂停时 playing=false 的行为，浏览器保存活动暂停状态，音乐保留待恢复位置，避免退出试听页后从头重播。

全部活动音效和语音都有静音模型场景演示，音乐保持空画布。能量演示使用真实天翼模型及私有蓝色脉冲；创世之手演示使用真实骨骼/皮肤模型拍击。空军阵亡演示使用独立 air_crash：真实飞机带灰烟倾斜下坠，接地后散碎，避免通用车辆火球。演示不发声音、不改模拟、共享网格或音频游标；拖动进度、变速与独立演示时钟互不耦合。

## 情绪试验、费用与来源

独立试验仅四条，位于 `artifacts/audio_revision_20261007/emotion/`：Leo 的 neutral/urgent 与 Rex 的 neutral_air/urgent_air。使用 xAI 官方支持的 `[breath]`、`<loud>`、`<fast>`、`<emphasis>` 标签。自动单段 A/B 认为呼吸、发力、紧急语气有变化，同时保留基础演员，没有读出标签。推荐未来经玩家试听后按需应用这些受控标签；本轮没有把整套阵亡语气替换。报告中的其他建议并未实施，也不意味着其协议已验证。

本轮实际账户用量差 **US$0.4047253**，其中四首音乐为 **US$0.32**，其余包含小批声线候选、选择性 TTS、12音效、ASR及自动听觉复核；余额仍约US$5.034。没有触发余额不足。共享制作工具在402/余额不足时立刻停止新增请求，必须等待用户确认充值，不自动换供应商绕过。

生成语音、音效、音乐不是实录或人类配音，不声称 CC0。各供应商输出按其条款使用；15条本地 DSP 明确 CC0-1.0。manifest 保留真实 provider、model、request/raw/output hash。游戏离线运行，不包含 API key。

当前官方支持经过核实：[OpenRouter TTS](https://openrouter.ai/docs/guides/overview/multimodal/tts)、[xAI TTS 和语气标签](https://docs.x.ai/developers/model-capabilities/audio/text-to-speech)、[Qwen 中文 voice 列表](https://www.alibabacloud.com/help/en/model-studio/qwen-audio-tts-voice-list)、[Qwen 非实时 TTS](https://www.alibabacloud.com/help/en/model-studio/non-realtime-tts-user-guide)。[OpenAI TTS 官方文档](https://developers.openai.com/api/docs/guides/text-to-speech)支持中文与 instructions，但当前本机 OpenRouter 可用列表和实际路由不提供 gpt-4o-mini-tts，因此没有伪称使用。

原始工具 `tools/generate_revision_v8_audio.py` 提供缓存、PCM、暂停与校验能力；当前选择性制作入口为 `tools/revision_audio_20261007.py`，文字及演员源为 `tools/revision_v8_dialogue.py`。质量报告：`final_source_validation.json`、`pcm_validation.log`、`asr_summary.json`、`phrase_repair_asr.json`、`iron_sky_air_single_review.json`、`emotion/review.json`、`billing_final.json`，均在 `artifacts/audio_revision_20261007/`。最终 ASR 的唯一残留标记是非词语力竭呻吟『呃啊』被写为『嗯啊』，并非新增台词；ASR不能独立验证声调或身份。

最终回归见 `artifacts/audio_revision_20261007/test_summary.json`：12项独立进程测试、**16913 checks PASS**，最终日志无 SCRIPT ERROR、ERROR 或资源泄漏。包括 native/GDScript 真实主场景音乐573项，目录9737项，声音路由2014项，静音场景1163项，混音/群体/阈值34项、暂停试听往返9项，以及真实鼠标滚轮和滑杆15项。实际滚轮0→473，试听滑杆145%，进度15.8568秒；二十路场景音效输出 PCM 峰值32392/32767，同时语音保持三路预算。

补充匿名音乐片段听觉复核见 `music_auditory_review.json`（每曲12秒）：没有检出人声；菜单舒缓，平静曲是放松电贝司律动，小规模交战曲轻原声并带轻度紧张，危机曲悬念压迫，激烈曲高密度行动。这是片段模型评估，不是全曲人类试听，也不保证乐器识别完全准确。
