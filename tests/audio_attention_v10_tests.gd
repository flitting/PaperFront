extends SceneTree
var checks:=0
var failures:Array[String]=[]
var caption:=""
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func hold(player:AudioStreamPlayer)->void:
	var stream:AudioStreamWAV=player.stream.duplicate();stream.loop_mode=AudioStreamWAV.LOOP_FORWARD;stream.loop_end=roundi(stream.get_length()*stream.mix_rate)
	player.stream=stream;player.play()
func run()->void:
	var sound:=PaperAudio.new(); sound.voice_language = "zh_CN";root.add_child(sound);await process_frame
	sound.set_process(false);sound.configure_units(RulesLoader.load_rules());sound.set_scene("silent")
	sound.unit_caption.connect(func(text:String,_duration:float):caption=text)
	sound.camera_focus=Vector2(10,10)
	sound.set_attention([1],Vector2(10,10))
	sound.play_event({"kind":"fire","id":2,"team":1,"weapon":"rivet_rifle","pos":Vector2(10,10)})
	sound.play_event({"kind":"fire","id":1,"team":1,"weapon":"rivet_rifle","pos":Vector2(10,10)})
	check(sound.field_players[0].playing and sound.field_players[20].playing,"A distant source cannot consume the selected source's family cooldown/focus slot")
	check(sound.field_players[20].volume_db>sound.field_players[0].volume_db,"Selected source has a local accent over the same weapon elsewhere")
	sound._process(.2)
	check(sound.field_players[0].volume_db<PaperAudio.catalog_gain({"action":"fire_rifle"})-2.0,"Other battle sources yield while the attended source actually sounds")
	sound.reset_field()
	sound.play_event({"kind":"fire","id":2,"team":1,"weapon":"rivet_rifle","pos":Vector2(10,10)})
	check(is_equal_approx(sound.field_players[0].volume_db,PaperAudio.catalog_gain({"action":"fire_rifle"})),"An idle selection does not suppress ordinary battlefield sound")
	sound.reset_field()
	for index in range(20):
		sound.play_event({"kind":"fire","id":index+20,"team":1,"weapon":"rivet_rifle","pos":Vector2(10,10)})
		hold(sound.field_players[index])
	sound.play_event({"kind":"fire","id":1,"team":1,"weapon":"rivet_tank","pos":Vector2(10,10)})
	check(sound.field_players[20].playing,"Selected cannon remains audible under twenty sustained ordinary shot tails")
	sound.play_event({"kind":"death","id":55,"team":1,"spec":"rivet_tank","pos":Vector2(10,10),"destroyed":true})
	sound.play_event({"kind":"impact","id":66,"team":1,"blast":2.0,"pos":Vector2(10,10)})
	var tail:AudioStream=sound.field_players[21].stream
	check(sound.field_players[21].playing and sound.field_players[22].playing,"Destruction and large impacts have two protected tail slots")
	sound.play_event({"kind":"fire","id":99,"team":1,"weapon":"rivet_rifle","pos":Vector2(10,10)})
	check(sound.field_players[21].stream==tail and sound.field_players.filter(func(p):return p.playing).size()<=24,"Saturated shots are dropped without replacing an explosion tail")
	sound.reset_field();sound.set_attention([],Vector2(24,24));sound.camera_focus=Vector2(20,20)
	sound.play_event({"kind":"fire","id":6,"team":1,"weapon":"rivet_tank","pos":Vector2(25,25)})
	check(sound.field_players[20].playing,"Without selection, pointer-nearby sources receive the focus accent")
	sound.reset_field();sound.set_attention([1],Vector2.INF)
	sound.play_event({"kind":"impact","source_id":1,"target":8,"blast":1.0,"pos":Vector2(10,10)})
	check(sound.field_players[20].playing,"Shell impact retains its selected shooter attribution")
	sound.reset_field()
	for pair:Array in [["ui_key",sound._available_family("ui_key","command")],["ui_click",sound._available_family("ui_click","command")],["queue_unit",sound._available_family("ui_click","command")],["queue_build",sound._available_family("ui_click","command")],["select_building","select_power"]]:
		check(sound._event_family({"kind":pair[0]})==pair[1],"Applied interface cue route: "+str(pair[0]))
	sound.reset_field();sound.play_event({"kind":"command","team":1})
	check(sound.ui_players.all(func(p):return not p.playing),"AI issued orders cannot masquerade as player keyboard feedback")
	check(PaperAudio.catalog_gain({"action":"death_building"})>PaperAudio.catalog_gain({"type":"voice","action":"select"}),"Building destruction gain remains more prominent than ordinary speech")
	check(PaperAudio.catalog_gain({"action":"deploy_building"})>=PaperAudio.catalog_gain({"type":"voice","action":"select"}),"Building deployment is prominent at the applied gain table")
	for key:String in PaperAudio.MIX_KEYS:
		sound.set_mix({key:9.0});check(sound.get_mix()[key]==2.0,"Each existing user mix supports a bounded200%: "+key)
	sound.set_mix({"master":.85,"music":.45,"sfx":.9,"voice":.85})
	sound.reset_field();check(sound.system_clips.size()==2,"Both real team-zero system alert clips load")
	sound.play_event({"kind":"low_power","team":0})
	check(sound.speech_player.playing and caption=="系统："+str(sound.system_clips.low_power.text),"Low-power system voice and exact caption share the actual clip")
	check(sound.active_speech_count()<=3,"System alert uses the existing global narration budget")
	sound.reset_field();caption=""
	sound.play_event({"kind":"power_restored","team":1})
	check(sound.active_speech_count()==0 and caption.is_empty(),"Enemy power transitions cannot produce player system narration")
	sound.set_mix({"voice":0.0});sound.play_event({"kind":"power_restored","team":0})
	check(sound.active_speech_count()==0 and caption=="系统："+str(sound.system_clips.power_restored.text),"Muted narration retains the actual system caption")
	sound.set_mix({"voice":.85});sound.reset_field()
	sound.play_unit_voice("rivet_tank","select",{"id":1,"team":0,"pos":Vector2(10,10)})
	sound.play_unit_voice("rivet_tank","move",{"id":1,"team":0,"pos":Vector2(12,10)})
	check(sound.pending_speech.get("context",{}).get("id")==1,"Deferred unit orders preserve their identity and attention context")
	sound.speech_player.stop();sound.last_speech_ms=-100000;sound._process(.1)
	check(sound.speech_player.playing and sound.speech_slots[sound.speech_player].context.get("id")==1 and sound.speech_slots[sound.speech_player].context.get("pos")==Vector2(12,10),"Actual deferred replay preserves the selected source identity and location")
	hold(sound.speech_player)
	sound.play_event({"kind":"low_power","team":0})
	check(not sound.pending_system.is_empty() and sound.active_speech_count()<=3,"System alert queues behind a current order without adding a fourth speaker")
	sound.begin_preview();caption="";sound.play_event({"kind":"low_power","team":0});sound.play_event({"kind":"fire","id":1,"team":1,"weapon":"rivet_tank","pos":Vector2(10,10)})
	check(sound.players.all(func(p):return not p.playing) and caption.is_empty() and sound.pending_system.is_empty(),"Audio-browser isolation also excludes focus effects and system narration")
	sound.end_preview();sound.reset_field();sound.play("ui_click")
	check(sound.ui_players.any(func(p):return p.playing),"Ordinary interface playback resumes when preview closes")
	tail=null;sound.stop_all();await create_timer(.25).timeout;sound.queue_free();await process_frame;call_deferred("finish")
func finish()->void:
	await process_frame;await create_timer(.3).timeout
	print("AUDIO_ATTENTION_V10 ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure:String in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
