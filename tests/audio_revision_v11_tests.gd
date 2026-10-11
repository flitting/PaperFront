extends SceneTree
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)
func fire(music: PaperMusic, id: int, team: int) -> void:
	music.observe_combat({"kind":"fire","id":id,"team":team,"target":99})
func step(music: PaperMusic, seconds: float) -> void:
	for i in range(ceili(seconds/.05)): music._process(.05)
func run() -> void:
	var before := AudioServer.bus_count
	var audio := PaperAudio.new(); audio.voice_language = "zh_CN"; root.add_child(audio); audio.set_process(false); audio.music.set_process(false)
	await process_frame
	audio.configure_units(RulesLoader.load_rules())
	check(audio.mix == {"master":1.0,"music":1.0,"sfx":1.0,"voice":1.0,"commander":.6},"four existing categories stay100% and the new commander defaults to60%")
	check(absf(PaperAudio.catalog_gain({"type":"voice","action":"select"})-(-7+linear_to_db(.7225)))<.001,"voice preserves olddefault .85*.85 effectivebaseline")
	check(absf(PaperAudio.catalog_gain({"type":"sfx","action":"fire_cannon"})-(-9+linear_to_db(.765)))<.001,"SFX preserves old .85*.9 baseline separately fromsource .8 reduction")
	check(absf(PaperAudio.catalog_gain({"type":"music"})-linear_to_db(.3825))<.001,"music audition shares olddefault .85*.45 baseline")
	check(audio.field_players.size()==24 and audio.speech_players.size()==3,"24 field layers are independent of the3speechslots")
	var music: PaperMusic=audio.music
	check(music.tracks.size()==5 and not music.tracks.has("battle_forest") and not music.tracks.has("win"),"only five applied score sources load")
	music.set_scene("battle");step(music,3)
	check(music.active_track=="battle_calm","all quiet maps use newcalm bed")
		# Dictionary entities is sufficient for the pure recent-shooter inventory.
	var fixture := {"entities":{}}
	for id in range(1,12): fixture.entities[id]={"hp":100,"team":0 if id<=6 else 1,"kind":"unit"}
	fixture.entities[99]={"hp":100,"team":1,"kind":"unit"}
	fire(music,1,0);music._measure_density(fixture);music._process(.05)
	check(music.requested_track=="battle_engaged" and music.friendly_sources==1,"first realshot selects restrained engagement immediately")
	for id in range(2,6):fire(music,id,0)
	music._measure_density(fixture);music._process(.05)
	check(music.friendly_sources==5 and music.combat_level==1,"five friendly shooters donottriggerthirdtier orcountvictims")
	fire(music,6,0);music._measure_density(fixture);music._process(.05)
	check(music.friendly_sources==6 and music.locked_combat_track=="battle_intense","six friendly recent-shooters selects intense")
	for id in range(1,7):fixture.entities[id].hp=0
	for id in range(7,12):fire(music,id,1)
	music._measure_density(fixture);music._process(.05)
	check(music.friendly_sources==0 and music.enemy_sources==5 and music.requested_track=="battle_intense","thirdtier retains itschoice after casualties/opposingdensity change")
	step(music,4.9);check(music.combat_level==2,"thirdtier doesnotexit before5quietseconds")
	step(music,.15);check(music.combat_level==0 and music.recent_shots.is_empty() and music.requested_track=="battle_calm","morethan5quietseconds clears stale10secondmemories andunlocks")
	for id in range(7,11):fire(music,id,1)
	music._measure_density(fixture);music._process(.05)
	check(music.combat_level==1,"four enemyshooters alone remainordinary")
	fire(music,11,1);music._measure_density(fixture);music._process(.05)
	check(music.locked_combat_track=="battle_danger","five enemyshooters withzero friendly selects danger")
	music.player.play();await create_timer(.08).timeout
	music.set_playback_paused(true)
	var clock:float=music.combat_clock;var fade:float=music.fade_elapsed;var position:float=music.player.get_playback_position()
	music._process(8.0);music.observe_combat({"kind":"impact"});await create_timer(.1).timeout
	check(music.combat_clock==clock and music.fade_elapsed==fade and absf(music.player.get_playback_position()-position)<.02,"pause freezes cursor combat andtwo-secondfade clocks")
	music.set_playback_paused(false);music._process(.05)
	check(music.combat_clock>clock and not music.player.stream_paused,"resume continues original cursor and clocks")
	music.reset_combat();fixture.entities[1].hp=100;fire(music,1,0)
	for i in range(11):music.observe_combat({"kind":"impact"});step(music,1.0)
	music._measure_density(fixture)
	check(music.friendly_sources==0,"live nonfiring unit expires after10seconds despite other continuedinteractions")
	audio.reset_field();audio.set_mix({"master":1,"voice":1,"sfx":1,"music":0,"muted":false});audio.set_attention([],Vector2.INF)
	var recorder:=AudioEffectRecord.new();recorder.format=AudioStreamWAV.FORMAT_16_BITS
	var recorder_index:int=AudioServer.get_bus_effect_count(0);AudioServer.add_bus_effect(0,recorder,recorder_index);recorder.set_recording_active(true)
	for id in range(20):audio.play_event({"kind":"fire","id":id+200,"team":1,"weapon":"kestrel_tank","spec":"kestrel_tank","pos":Vector2(id*.2,0)})
	var field_count:=0
	for player in audio.field_players:if player.playing:field_count+=1
	check(field_count==20 and audio.active_speech_count()==0,"twenty simultaneous independent gun layers are notspeechcapped")
	await create_timer(.2).timeout;recorder.set_recording_active(false)
	var recorded:AudioStreamWAV=recorder.get_recording();var output_peak:=0
	if recorded!=null:
		for offset in range(0,recorded.data.size()-1,2):output_peak=maxi(output_peak,absi(recorded.data.decode_s16(offset)))
	check(recorded!=null and recorded.data.size()>0 and output_peak>0 and output_peak<32767,"overlapping fieldlayers produce realmixed PCM with limiterheadroom")
	AudioServer.remove_bus_effect(0,recorder_index);recorded=null;recorder=null
	for pair in [["sky_tank","fire_energy"],["sky_creator_hand","creator_hand_attack"],["kestrel_tank","fire_cannon"]]:
		check(audio._event_family({"kind":"fire","weapon":pair[0]})==pair[1],"actualweaponroutes to dedicated firing source:"+pair[0])
	check(audio._event_family({"kind":"impact","weapon":"sky_tank"})=="impact_energy" and audio._event_family({"kind":"impact","weapon":"sky_creator_hand"})=="creator_hand_impact","energy andhand impacts cannotreuse shells")
	audio.reset_field()
	var contexts:Array=[{"id":1,"team":0},{"id":2,"team":0},{"id":3,"team":0},{"id":4,"team":0}]
	for index in [1,2]:
		audio.speech_players[index].stream=audio.radio_bank.values()[0];audio.speech_players[index].play()
	check(audio.play_unit_group_voice("kestrel_rifle","select",contexts),"group acknowledgement accepts ownunits")
	check(audio.last_group_voice.copies==3 and audio.last_group_voice.delays_ms==[0,50,100],"onephrase starts up tothree sameactor copies0/.05/.10seconds")
	check(not audio.speech_players[1].playing and not audio.speech_players[2].playing,"accepted group stops competing fieldreports before reservingcopies")
	var stream:AudioStream=audio.speech_player.stream;var clipkey:String=str(audio.last_spoken_clip.key)
	check(not audio.play_unit_group_voice("kestrel_rifle","move",contexts) and audio.speech_player.stream==stream and audio.pending_speech.get("group_contexts",[]).size()==4,"busyplayerorder queues nextgroup withoutclipping slotzero")
	check(audio.group_voice_queue.size()==2 and audio.group_voice_queue.all(func(q):return q.stream==stream and str(q.clip.key)==clipkey),"queued copies share exactselected variant andwaveform")
	await create_timer(.14).timeout;audio._process(.14)
	check(audio.active_speech_count()==3 and audio.speech_players.all(func(p):return p.stream==stream and p.pitch_scale==1.0),"actual delayed players keep onevariant samepitch andthreespeechbudget")
	check(absf(audio.speech_players[1].volume_db-(PaperAudio.catalog_gain({"type":"voice","action":"select"})-3.0))<.01,"groupcopy gain is notdoubleducked by primaryorder")
	audio.begin_preview();check(audio.group_voice_queue.is_empty() and audio.active_speech_count()==0 and not audio.play_unit_group_voice("kestrel_rifle","move",contexts),"preview silences andguards queuedgroup voices")
	audio.end_preview();audio.reset_field();audio.play_unit_group_voice("kestrel_rifle","move",contexts);audio.set_mix({"voice":0.0})
	await create_timer(.14).timeout;audio._process(.14)
	check(audio.group_voice_queue.is_empty() and audio.active_speech_count()==0,"zero voicevolume prevents deferredcopies")
	fixture.clear();stream=null
	audio.stop_all();await create_timer(.3).timeout;audio.queue_free();music=null;await process_frame;audio=null
	check(AudioServer.bus_count==before,"revision fixture releases audio buses")
	await process_frame;await create_timer(.3).timeout
	var report:Dictionary={"checks":checks,"failures":failures,"field_layers_observed":field_count,"field_mix_output_peak":output_peak,"scope":"real imported players, speechdelay, baseline and deterministic combat classifier; nohumanlisteningclaim"}
	var f:=FileAccess.open("res://artifacts/audio_revision_20261007/runtime_validation.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t")+"\n");f=null
	print("AUDIO_V11 ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
