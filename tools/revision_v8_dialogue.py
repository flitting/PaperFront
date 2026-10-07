"""Original Mandarin battlefield dialogue and voice direction for the v8 mix.

Each faction has one shared infantry, vehicle, and air voice set. Lines are
deliberately short so contextual radio calls do not obscure battlefield cues.
"""

PROFILES = {
    'kestrel/infantry': ('Orus', 'Disciplined professional infantry squad leader. Firm and composed, precise phrasing, clear natural Mandarin, brisk military radio delivery.', {
        'select': ['小队集结，听候指令。', '小队就位，请下令。', '队形完整，随时行动。'],
        'move': ['按令前进，保持队形。', '目标确认，小队转移。', '路线收到，稳步推进。'],
        'attack': ['集中火力，执行攻击。', '目标锁定，协同开火。', '按战术推进，压制目标。'],
        'ready': ['小队整备完毕。', '人员到齐，等待任务。', '步兵小队，准备就绪。'],
        'return': ['撤回整备，保持队形。', '返回集结点。', '任务结束，小队归队。'],
        'combat': ['火力覆盖，继续推进！', '交替掩护，稳住阵线！', '目标仍在，保持压制！'],
        'under_attack': ['小队遭袭，请求支援！', '发现敌火，寻找掩体！', '有人受伤，保持队形！'],
        'death': ['小队失守……', '接替我的位置……', '撑住阵线……'],
    }),
    'kestrel/vehicle': ('Iapetus', 'Calm methodical armored vehicle commander. Low steady register, clear concise Mandarin, confident professional radio reports.', {
        'select': ['正典装甲，等待命令。', '车组在线，请指示。', '系统正常，随时出发。'],
        'move': ['引擎启动，按路线行驶。', '车组收到，向目标推进。', '装甲转移，保持间距。'],
        'attack': ['炮口对准，准备射击。', '火控确认，执行攻击。', '装甲协同，集中开火。'],
        'ready': ['装甲整备完毕。', '车组就位，系统正常。', '弹药装填完毕。'],
        'return': ['返回整备区。', '装甲归队，保持间距。', '车组收到，撤回维修。'],
        'combat': ['持续射击，掩护步兵！', '装填下一发！', '火控稳定，继续交战！'],
        'under_attack': ['装甲受击，调整车体！', '敌方来袭，请求掩护。', '车组受损，需要支援！'],
        'death': ['车组撤离！', '装甲失守……', '引擎停了……'],
    }),
    'kestrel/air': ('Kore', 'Professional pilot, crisp confident female voice. Fluent Mandarin, short precise flight radio callouts, controlled energy.', {
        'select': ['正典航空，收到呼叫。', '航线畅通，请下令。', '飞行组待命。'],
        'move': ['航向确认，前往目标。', '调整航线，保持高度。', '按令转向，正在接近。'],
        'attack': ['目标确认，开始攻击。', '进入航线，准备投射。', '航空支援，即刻抵达。'],
        'ready': ['航空整备完毕。', '燃料充足，等待起飞。', '飞行组准备就绪。'],
        'return': ['返航，补充弹药。', '任务完成，返回基地。', '航向基地，准备降落。'],
        'combat': ['正在攻击，保持空域！', '完成一轮，重新接近！', '目标仍在，继续支援！'],
        'under_attack': ['机体受击，规避中！', '遭遇防空火力！', '请求掩护，正在脱离！'],
        'death': ['无法控制，准备跳伞！', '机体失控……', '呼叫基地……'],
    }),
    'rivet/infantry': ('Fenrir', 'Bold direct heavy-assault infantry leader. Rough energetic masculine Mandarin, short punchy phrases, determined and battle-hardened without cartoon screaming.', {
        'select': ['突击队就位，听候命令。', '兄弟们到齐了！', '说吧，往哪儿打？'],
        'move': ['迈开步子，跟上。', '重锤向前，别掉队！', '收到，咱们这就走！'],
        'attack': ['压住目标，开火。', '压过去，给他们重击！', '目标在前，全力开火。'],
        'ready': ['重锤步兵，整装待发！', '装填完成，准备开打！', '队伍到齐，等你发令！'],
        'return': ['兄弟们，回去检修。', '收到，撤回集结！', '先归队，再打下一场！'],
        'combat': ['火力别停，压住他们！', '跟紧我，继续打！', '守住阵线，顶住。'],
        'under_attack': ['敌人开火了，找掩护。', '我们挨打了，帮一把！', '别散开，稳住！'],
        'death': ['兄弟，接替我……', '我撑不住了……', '重锤，继续前进……'],
    }),
    'rivet/vehicle': ('Algenib', 'Heavy armored commander with a deep gravelly masculine voice. Forceful short Mandarin, deliberate heavy rhythm, confident assault character.', {
        'select': ['装甲车组，等你发令。', '钢铁就位，说目标。', '车组在这儿，准备好了。'],
        'move': ['履带转起来，向前压！', '引擎全开，跟上重锤。', '装甲推进，给我让路。'],
        'attack': ['炮口就位，重锤落下！', '正面轰开，开火！', '装填重弹，击碎目标！'],
        'ready': ['重装车组，整备完成。', '钢铁和炮火，都齐了。', '炮弹上膛，准备出击。'],
        'return': ['撤回装填，再来一轮。', '重锤收到，返回阵地。', '回去修整，车组跟紧。'],
        'combat': ['重弹装填，接着轰！', '火力压上去！', '顶着装甲，继续推进！'],
        'under_attack': ['装甲挨了一发！', '车体受损，掩护我们！', '敌炮盯上我们了！'],
        'death': ['车组，快撤！', '重装被击穿了……', '履带停了……'],
    }),
    'rivet/air': ('Charon', 'Assertive combat pilot. Firm low masculine Mandarin with a brisk clipped tactical rhythm, daring and decisive, never theatrical.', {
        'select': ['重锤航空，随时出击。', '空中火力，等你一句话。', '飞行组在线，说目标。'],
        'move': ['航向收到，加速接近。', '拉起机头，直奔目标。', '重锤在空中，跟上航线。'],
        'attack': ['从天上砸下去！', '锁定目标，重锤出击！', '进入攻击航线，开火！'],
        'ready': ['重锤航空，整备完成。', '装填完成，等你发令。', '飞行组到齐了。'],
        'return': ['弹药用完，返航装填。', '这一轮打完，返回基地。', '收队返航，准备再战。'],
        'combat': ['空中重击，正在投射！', '再来一轮，集中火力！', '航线稳定，继续开火！'],
        'under_attack': ['防空盯上我了！', '机体挨打，正在规避！', '给我掩护，脱离火线！'],
        'death': ['机翼断了，跳伞！', '重锤航空，失控……', '基地，接替航线……'],
    }),
    'iron/infantry': ('Algieba', 'Reliable friendly field craftsman turned soldier. Warm steady masculine Mandarin, grounded calm reassurance, practical matter-of-fact phrasing.', {
        'select': ['长钉步兵，随时帮忙。', '队伍齐整，放心交给我。', '装备检查好了，请指示。'],
        'move': ['工具带齐，踏实往前走。', '收到，我们稳稳过去。', '跟好队伍，别落下战友。'],
        'attack': ['瞄准再打，别浪费弹药。', '目标收到，稳稳拿下。', '把阵线钉牢，开火！'],
        'ready': ['装备可靠，人员到齐。', '长钉步兵，准备好了。', '备件和弹药，都检查过了。'],
        'return': ['回去检查装备。', '队伍归队，一个也别落下。', '收到，撤回整备。'],
        'combat': ['稳住阵线，照顾战友！', '别急，瞄准再来！', '长钉扎稳，继续压制！'],
        'under_attack': ['有敌火，先找掩体！', '有人受伤，需要支援！', '装备受损，帮我们掩护！'],
        'death': ['照顾好战友……', '我的位置，交给你……', '工具，替我收好……'],
    }),
    'iron/vehicle': ('Gacrux', 'Mature dependable industrial vehicle mechanic and commander. Warm low register, slow confident practical Mandarin, weighty steady cadence.', {
        'select': ['长钉车组，检查完毕。', '放心，机器很可靠。', '引擎正常，请下令。'],
        'move': ['慢慢起步，稳稳到位。', '收到，履带检查过了。', '向目标行驶，照顾队形。'],
        'attack': ['火控调好了，开始射击。', '装填完毕，稳稳命中。', '把阵地钉牢，车组开火。'],
        'ready': ['长钉装甲，整备完成。', '螺栓拧紧了，放心出发。', '备件齐全，车组就绪。'],
        'return': ['回去检修，再接任务。', '车组归队，慢慢进站。', '返回车间，检查受损部件。'],
        'combat': ['炮管稳定，继续射击！', '换上下一发，别急！', '机器可靠，稳步推进！'],
        'under_attack': ['装甲受损，需要修理！', '车体挨打，帮忙掩护！', '部件受损，车组撑住！'],
        'death': ['车组先撤，快！', '机器撑不住了……', '备件，留给后面的……'],
    }),
    'iron/air': ('Umbriel', 'Easygoing dependable maintenance-minded pilot. Calm natural masculine Mandarin, warm measured pacing, short practical technical reports.', {
        'select': ['长钉航空，检查正常。', '机组在这儿，放心下令。', '航线看好了，请指示。'],
        'move': ['航向收到，稳稳飞过去。', '调整高度，机组跟紧。', '检查完成，前往目标。'],
        'attack': ['瞄准系统正常，开始攻击。', '目标收到，稳稳投射。', '进入航线，准备开火。'],
        'ready': ['长钉航空，整备完成。', '机翼和引擎，都检查好了。', '燃料加满，机组就绪。'],
        'return': ['返航，顺便检查机体。', '回基地补充弹药。', '任务完成，稳稳降落。'],
        'combat': ['瞄准稳定，继续支援！', '再绕一圈，接着打！', '机组协同，稳住航线！'],
        'under_attack': ['机体受损，先避开火力！', '防空来袭，请求掩护！', '引擎受击，需要返航！'],
        'death': ['机组跳伞，快！', '机体撑不住了……', '帮我照顾机组……'],
    }),
    'sky/infantry': ('Leda', 'Young precise advanced-technology infantry specialist. Clear bright female Mandarin, analytical focused tone with restrained conviction and concise observations.', {
        'select': ['天意步兵，感知在线。', '标定完成，等待指令。', '想象就绪，请指示。'],
        'move': ['坐标收到，正在接近。', '调整阵列，前往目标。', '路径确认，轻步前进。'],
        'attack': ['目标标定，集中能量。', '锁定完成，开始攻击。', '让想象成真，开火。'],
        'ready': ['天意步兵，校准完成。', '感知阵列正常。', '标定设备，准备就绪。'],
        'return': ['返回阵列，重新校准。', '收到，撤回集结。', '任务结束，回收设备。'],
        'combat': ['锁定稳定，继续压制！', '能量聚焦，保持阵列！', '目标还在，重新标定！'],
        'under_attack': ['阵列受击，寻找掩体！', '敌火干扰，请求支援！', '设备受损，保持联络！'],
        'death': ['感知信号，中断……', '把坐标传下去……', '想象，还会继续……'],
    }),
    'sky/vehicle': ('Sadaltager', 'Knowledgeable calm advanced vehicle operator. Distinct resonant masculine Mandarin, exact technical diction, quiet focused assurance with deliberate rhythm.', {
        'select': ['天意车组，蓄能正常。', '标定系统在线，请指示。', '装置调整完毕，等待目标。'],
        'move': ['坐标确认，推进装置。', '调整车体，前往标定点。', '能量稳定，开始转移。'],
        'attack': ['标定完成，释放能量。', '锁定目标，准备投射。', '聚焦装置，执行攻击。'],
        'ready': ['天意装甲，校准完成。', '蓄能装置，准备就绪。', '车组在线，系统稳定。'],
        'return': ['回收能量，返回阵地。', '车组返程，准备校准。', '返回整备，补充储能。'],
        'combat': ['蓄能完成，再次投射！', '标定稳定，持续交战！', '聚焦目标，保持输出！'],
        'under_attack': ['外壳受损，调整车体！', '蓄能受扰，请求支援！', '装置受击，需要掩护！'],
        'death': ['储能失稳，车组撤离！', '装置失控……', '标定信号，中断……'],
    }),
    'sky/air': ('Zephyr', 'Bright agile advanced-technology female pilot. Airy clear fluent Mandarin, cool confident precision with a slightly elevated register, concise flight callouts.', {
        'select': ['天意航空，空域在线。', '航线标定，等待指令。', '天空就绪，请下令。'],
        'move': ['航向标定，掠向目标。', '调整高度，沿光前行。', '空域确认，正在接近。'],
        'attack': ['高空锁定，释放能量。', '标定目标，天意出击。', '进入航线，精准投射。'],
        'ready': ['天意航空，校准完成。', '航电就绪，等待起飞。', '天空阵列，准备完毕。'],
        'return': ['返航，重新蓄能。', '回收航线，返回基地。', '任务完成，准备降落。'],
        'combat': ['标定稳定，继续投射！', '调整航线，再次接近！', '天意覆盖，保持锁定！'],
        'under_attack': ['防空干扰，正在规避！', '机体受击，调整高度！', '航电受损，请求掩护！'],
        'death': ['机体失控，准备跳伞！', '空域信号，中断……', '航线，交给你了……'],
    }),
}

ACTION_DIRECTION = {
    'select': 'Responsive acknowledgement, composed and ready.',
    'move': 'Confident immediate movement order acknowledgement.',
    'attack': 'Determined attack acknowledgement, slightly more forceful.',
    'ready': 'Brief proud readiness report.',
    'return': 'Calm brief return or regroup report.',
    'combat': 'Active firefight callout, urgent and forceful but intelligible.',
    'under_attack': 'Alarmed under-fire report, urgent and strained, still intelligible.',
    'death': 'Very short failing final radio call, strained fading voice, do not prolong or add words.',
}

# These managed Mandarin voices have explicit fixed speaker identities. Unlike
# independent generative style prompts, the same voice+tempo is used for every
# action and variant of a profile. Twelve distinct base actors supply twelve category sets;
# every action keeps the same actor without shifting vocal pitch or gender.
FIXED_SPEAKERS = {
    'kestrel/infantry': ('zh-CN-Wei:MAI-Voice-2.1', 'male', 1.02),
    'kestrel/vehicle': ('zh-CN-Bo:MAI-Voice-2.1', 'male', .97),
    'kestrel/air': ('zh-CN-Harper:MAI-Voice-2.1', 'female', 1.05),
    'rivet/infantry': ('leo', 'male', 1.0),
    'rivet/vehicle': ('zh-CN-Grant:MAI-Voice-2.1', 'male', .94),
    'rivet/air': ('rex', 'male', 1.0),
    'iron/infantry': ('eve', 'female', 1.0),
    'iron/vehicle': ('longanlufeng', 'male', 1.0),
    'iron/air': ('zh-CN-Lan:MAI-Voice-2.1', 'female', 1.0),
    'sky/infantry': ('zh-CN-Mei:MAI-Voice-2.1', 'female', 1.02),
    'sky/vehicle': ('ara', 'female', 1.0),
    'sky/air': ('sal', 'neutral', 1.0),
}

VOICE_MODELS = {
    'rivet/infantry':'x-ai/grok-voice-tts-1.0', 'rivet/air':'x-ai/grok-voice-tts-1.0',
    'iron/infantry':'x-ai/grok-voice-tts-1.0', 'sky/vehicle':'x-ai/grok-voice-tts-1.0',
    'iron/vehicle':'qwen/qwen-audio-3.0-tts-plus', 'sky/air':'x-ai/grok-voice-tts-1.0',
}

DEATH_DIALOGUE = {
    'kestrel/infantry': ['呃啊！', '救…救我！', '别…别停…', '快撤！啊！'],
    'kestrel/vehicle': ['啊！车组快撤！', '救我！', '装甲…啊！', '快…跳车！'],
    'kestrel/air': ['Mayday！', 'Pull up！', '失控…啊！', '快…跳伞！'],
    'rivet/infantry': ['啊——！', '兄弟，救我！', '别…丢下我！', '呃！顶…住…'],
    'rivet/vehicle': ['快撤！啊！', '车组…救命！', '穿了…呃啊！', '快…跳车！'],
    'rivet/air': ['Mayday！', 'Pull up！快！', '失控…啊！', '跳！快跳！'],
    'iron/infantry': ['啊！战友…', '救…救我！', '呃…撑不住…', '别…别停…'],
    'iron/vehicle': ['快撤！啊！', '救我！救…', '呃！机器…', '快…跳车！'],
    'iron/air': ['Mayday！', 'Pull up！', '失控…啊！', '快…跳伞！'],
    'sky/infantry': ['啊！信号…', '救…救我！', '呃！别…', '快撤…啊！'],
    'sky/vehicle': ['啊！储能失…', '救命！', '快…跳车！', '呃啊！'],
    'sky/air': ['Mayday！', 'Pull up！啊！', '信号…啊！', '快…跳伞！'],
}

def specifications():
    for key, (voice, direction, actions) in PROFILES.items():
        faction, category = key.split('/')
        voice, gender, tempo = FIXED_SPEAKERS[key]
        if key == 'iron/air':
            direction = 'Dependable maintenance-minded female pilot. Calm clear practical Mandarin reports.'
        assert set(actions) == set(ACTION_DIRECTION)
        for action, lines in actions.items():
            if action == 'death': lines = DEATH_DIALOGUE[key]
            expected = 4 if action == 'death' else 3
            assert len(lines) == expected and len(set(lines)) == expected
            for index, line in enumerate(lines, 1):
                yield {'key': f'{key}/{action}/{index}', 'faction': faction,
                       'category': category, 'action': action, 'variant': index,
                       'text': line, 'voice': voice,
                       'model':VOICE_MODELS.get(key,'microsoft/mai-voice-2.1'),
                       'speaker_id': voice + f'@tempo={tempo:.3f}',
                       'speaker_identity': voice, 'speaker_gender': gender, 'tempo': tempo,
                       'direction': direction,
                       'request_strategy': 'fixed managed speaker; neutral delivery; no per-action style prompt'}
