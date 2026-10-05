extends SceneTree

var failures: Array[String] = []

func require(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var sound := PaperAudio.new()
	root.add_child(sound)
	await process_frame
	for family in PaperAudio.VARIANT_BANKS:
		require(sound.bank.has(family) and sound.bank[family].size() == 3, "Missing three-variant bank: " + family)
	for mapping in [["rivet_rifle", "fire_rifle"], ["kestrel_rifle", "fire_rifle"], ["kestrel_tower", "fire_rifle"], ["rivet_anti", "fire_anti"], ["kestrel_anti", "fire_anti"], ["rivet_tank", "fire_cannon"], ["kestrel_tank", "fire_cannon"], ["rivet_tower", "fire_cannon"], ["rivet_assault", "fire_artillery"], ["kestrel_demolition", "fire_artillery"]]:
		require(sound._event_family({"kind": "fire", "weapon": mapping[0]}) == mapping[1], "Wrong weapon family: " + mapping[0])
	for mapping in [[0.35, "impact_small"], [1.0, "impact_medium"], [1.2, "impact_medium"], [1.8, "impact_large"], [2.0, "impact_large"], [3.0, "impact_large"]]:
		require(sound._event_family({"kind": "impact", "blast": mapping[0]}) == mapping[1], "Wrong blast family")
	require(sound._event_family({"kind": "death", "spec": "rivet_rifle"}) == "death_soft", "Infantry must not sound like a vehicle explosion")
	require(sound._event_family({"kind": "death", "spec": "rivet_tank"}) == "death", "Destroyed tank requires explosion")
	var bus := AudioServer.get_bus_index(PaperAudio.BUS_NAME)
	require(bus >= 0 and AudioServer.get_bus_effect_count(bus) == 1, "SFX peak limiter missing")
	for player in sound.engine_players:
		require(player.stream is AudioStreamWAV and player.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "Vehicle loop not seamless WAV playback")
		require(player.stream.loop_end == 88200, "Incorrect vehicle loop sample range")
	# Populated nearby friendly moving vehicles should start only two pooled loops.
	var entities := {1:{"team":0,"hp":100,"motion":0.2,"spec":"rivet_tank","pos":Vector2(10,10)}}
	for index in range(10): sound.update_battlefield(0.16, entities, Vector2(10,10))
	require(sound.engine_players[0].playing and sound.engine_players[1].playing, "Nearby moving vehicle has no engine bed")
	require(sound.engine_players[0].volume_db <= -28.0, "Vehicle volume exceeds budget")
	# Distance, team, infantry, and stationary filtering all must silence the bed.
	entities = {1:{"team":0,"hp":100,"motion":0.2,"spec":"rivet_tank","pos":Vector2(150,150)},2:{"team":1,"hp":100,"motion":0.2,"spec":"kestrel_tank","pos":Vector2(10,10)},3:{"team":0,"hp":100,"motion":0.2,"spec":"rivet_rifle","pos":Vector2(10,10)},4:{"team":0,"hp":100,"motion":0.0,"spec":"rivet_harvester","pos":Vector2(10,10)}}
	for index in range(20): sound.update_battlefield(0.16, entities, Vector2(10,10))
	require(not sound.engine_players[0].playing and not sound.engine_players[1].playing, "Offscreen/enemy/stationary/infantry leak engine audio")
	sound.play_event({"kind":"fire","weapon":"rivet_tank","pos":Vector2(10,10)})
	require(sound.field_players[0].playing, "Valid nearby fire event did not play")
	sound.play("select")
	require(sound.ui_players[0].playing, "UI feedback not reserved during combat")
	sound.muted = true
	for player in sound.players: require(not player.playing, "Mute left active playback")
	sound.muted = false
	sound.recent.clear()
	sound.play_event({"kind":"fire","weapon":"rivet_tank","pos":Vector2(200,200)})
	for player in sound.field_players: require(not player.playing, "Distant fire leaked through attenuation cutoff")
	sound.play_event({"kind":"fire","weapon":"rivet_tank","pos":Vector2(10,10)})
	var previous: AudioStream = sound.field_players[0].stream
	sound.recent.clear()
	sound.play_event({"kind":"fire","weapon":"rivet_tank","pos":Vector2(10,10)})
	require(sound.field_players[1].stream != previous, "Repeated fire chose identical adjacent variant")
	previous = null
	sound.stop_all()
	await create_timer(0.15).timeout
	sound.queue_free()
	await process_frame
	require(AudioServer.get_bus_index(PaperAudio.BUS_NAME) < 0, "Audio bus leaked after scene teardown")
	if failures.is_empty():
		print("audio_tests: 39 assets, ten weapon mappings, six impact mappings, loop ranges, voice pools, locality, mute, variation and teardown PASS")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)
