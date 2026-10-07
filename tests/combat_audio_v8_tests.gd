extends SceneTree

# Audio-only regressions for real class banks, actual caption/clip pairing,
# field event routing and the global speech limit under an overloaded battle.
var failures: Array[String] = []
var checks := 0
var caption := ""
var caption_duration := 0.0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func allow_next_field(sound: PaperAudio) -> void:
	# A burst can arrive after different wall-clock cooldowns. Keep long phrases
	# active to exercise the pool even when the synthesized source is very short.
	sound.last_speech_ms = -100000
	sound.last_field_speech_ms = -100000

func hold_phrase(player: AudioStreamPlayer) -> void:
	var stream: AudioStreamWAV = player.stream.duplicate()
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = int(round(stream.get_length() * stream.mix_rate))
	player.stream = stream
	player.play()

func run() -> void:
	if not FileAccess.file_exists(PaperAudio.VOICE_MANIFEST):
		check(false, "Revision v8 generated voice manifest is required")
		call_deferred("finish")
		return
	var initial_buses := AudioServer.bus_count
	var sound := PaperAudio.new()
	root.add_child(sound)
	await process_frame
	sound.set_process(false)
	sound.set_scene("silent")
	var rules: Dictionary = RulesLoader.load_rules()
	sound.configure_units(rules)
	sound.unit_caption.connect(func(text: String, duration: float): caption = text; caption_duration = duration)
	check(sound.speech_players.size() == 3, "All speech shares exactly three slots")
	for faction: String in ["kestrel", "rivet", "iron", "sky"]:
		for category: String in PaperAudio.RADIO_CATEGORIES:
			for action: String in PaperAudio.RADIO_ACTIONS:
				var group: String = faction + "/" + category + "/" + action
				var clips: Array = sound.speech_clips.get(group, [])
				var paths: Dictionary = {}
				var texts: Dictionary = {}
				check(clips.size() >= 2 and clips.size() <= 4, "Two to four distinct original variants after obsolete name retirement in " + group)
				for clip: Dictionary in clips:
					paths[str(clip.get("file", clip.get("path", "")))] = true
					texts[str(clip.text)] = true
					check(sound.radio_bank.get(str(clip.key)) is AudioStreamWAV, "Selected manifest variant has PCM " + str(clip.key))
					check(str(sound.radio_bank[str(clip.key)].resource_path).begins_with("res://assets/audio/revision_v8/radio/"), "Only replacement speech assets load at runtime")
				check(paths.size() == clips.size() and texts.size() == clips.size(), "Variants have separate phrases and source files in " + group)
	for pair: Array in [["kestrel_demolition", "infantry"], ["iron_repair_vehicle", "vehicle"], ["iron_rig", "vehicle"], ["sky_inspection", "vehicle"], ["sky_designation", "vehicle"], ["iron_transport", "vehicle"], ["sky_air_transport", "air"], ["sky_recon", "air"], ["kestrel_ship_frigate", "vehicle"]]:
		check(sound.voice_category(pair[0]) == pair[1], "Definition classifies complete roster: " + pair[0])
	var custom: Dictionary = rules.duplicate(true)
	custom.units["renamed_medic"] = {"faction": "iron", "name": "医护兵", "domain": "ground", "movement_type": "foot", "radius": .65}
	custom.units["renamed_truck"] = {"faction": "rivet", "name": "运输车", "domain": "ground", "movement_type": "wheeled", "radius": .8}
	custom.units["unrecorded_unit"] = {"faction": "unrecorded", "name": "无录音单位", "art": "rifle", "domain": "ground", "voices": {"select": ["旧式机械应答"]}}
	custom.units["renamed_flyer"] = {"faction": "sky", "name": "飞行器", "domain": "air", "radius": .7}
	sound.configure_units(custom)
	check(sound.voice_category("renamed_medic") == "infantry" and sound._audio_type("renamed_medic") == -1, "Explicit foot movement overrides radius and name")
	check(sound.voice_category("renamed_truck") == "vehicle" and sound._audio_type("renamed_truck") == 1, "Renamed wheel vehicle retains engine sound")
	check(sound.voice_category("renamed_flyer") == "air" and sound._audio_type("renamed_flyer") == 2, "Renamed aircraft uses air voices and flight loop")
	check(not sound.play_unit_voice("unrecorded_unit", "select") and caption.is_empty(), "A missing new recording skips speech without reviving old rule text or audio")
	var previous_key := ""
	for variant in range(6):
		sound.reset_field()
		check(sound.play_unit_voice("kestrel_tank", "select"), "Player order speaks a class variant")
		check(caption.ends_with(str(sound.last_spoken_clip.text)) and sound.speech_player.stream == sound.radio_bank[str(sound.last_spoken_clip.key)], "Caption exactly matches the actual selected WAV")
		check(caption_duration >= sound.speech_player.stream.get_length(), "Caption stays present for the entire audible phrase")
		check(str(sound.last_spoken_clip.key) != previous_key, "Adjacent phrases vary without changing their caption")
		previous_key = str(sound.last_spoken_clip.key)
	sound.reset_field()
	sound.camera_focus = Vector2(12, 12)
	sound.play_event({"kind": "fire", "team": 0, "spec": "rivet_rifle", "weapon": "rivet_rifle", "pos": Vector2(12, 12)})
	check(sound.active_speech_count() == 1 and str(sound.last_spoken_clip.action) == "combat", "Friendly nearby fire dispatches a combat phrase")
	hold_phrase(sound.speech_players[1])
	allow_next_field(sound)
	sound.play_event({"kind": "under_attack", "team": 0, "spec": "kestrel_tank", "pos": Vector2(12, 12)})
	check(sound.active_speech_count() == 2 and str(sound.last_spoken_clip.action) == "under_attack", "Nearby hit has its own field phrase")
	hold_phrase(sound.speech_players[2])
	allow_next_field(sound)
	check(sound.play_unit_voice("sky_fighter", "attack") and sound.active_speech_count() == 3, "Order slot stays available beside both battlefield reports")
	hold_phrase(sound.speech_player)
	var order_stream: AudioStream = sound.speech_player.stream
	var order_caption: String = caption
	for index in range(120):
		allow_next_field(sound)
		sound.play_event({"kind": "death", "team": 0, "spec": "iron_tank", "destroyed": true, "pos": Vector2(12, 12)})
		check(sound.active_speech_count() <= 3, "Mass casualties stay inside global speech cap")
	check(sound.speech_player.stream == order_stream and caption == order_caption, "Overloaded battle reports preserve the audible order and its subtitle")
	check(not sound.play_unit_voice("rivet_tank", "move") and not sound.pending_speech.is_empty(), "Next player order waits without clipping the current phrase")
	sound.set_mix({"voice": 0.0})
	check(sound.active_speech_count() == 0 and sound.pending_speech.is_empty(), "Voice slider stops every speech slot and stale order immediately")
	check(sound.play_unit_voice("iron_tank", "select") and not caption.is_empty(), "Muted voice retains current order captions")
	sound.set_mix({"voice": .85})
	sound.reset_field()
	for event: Dictionary in [{"kind":"death","team":1,"spec":"iron_tank","pos":Vector2(12,12)}, {"kind":"under_attack","team":0,"spec":"rivet_rifle","pos":Vector2(120,120)}, {"kind":"death","team":0,"spec":"rivet_tank","destroyed":false,"pos":Vector2(12,12)}, {"kind":"fire","team":0,"spec":"kestrel_tower","weapon":"kestrel_tower","pos":Vector2(12,12)}]:
		sound.play_event(event)
		check(sound.active_speech_count() == 0, "Enemy, distant, sold and structure events cannot produce unit speech")
	sound.reset_field()
	for family: String in ["fire_machine_gun", "fire_cannon", "fire_artillery", "deploy_building", "construct_building", "death_building", "death_vehicle", "death_infantry"]:
		check(sound.bank.has(family), "Independently authored effect family is available: " + family)
	for pair: Array in [["rivet_scout", "fire_machine_gun"], ["sky_tower", "fire_energy"], ["iron_tank", "fire_cannon"], ["sky_artillery", "fire_energy"]]:
		check(sound._event_family({"kind":"fire","weapon":pair[0]}) == pair[1], "Ballistic and actual EMP/laser weapons route to their appropriate sounds: " + pair[0])
	check(sound._event_family({"kind":"death","spec":"iron_hq"}) == "death_building" and sound._event_family({"kind":"death","spec":"iron_tank"}) == "death_vehicle", "Buildings and tanks use separate explosion banks")
	check(sound._event_family({"kind":"deploy"}) == "deploy_building" and sound._event_family({"kind":"build", "construction_method":"scaffold"}) == "construct_building", "Completed deploy and actual engineer scaffold work have separate sounds")
	for spec: String in ["iron_repair_vehicle", "iron_rig", "sky_designation", "iron_transport"]:
		check(sound._audio_type(spec) >= 0, "All mobile support vehicles can contribute movement sound: " + spec)
	order_stream = null
	sound.stop_all()
	await create_timer(.2).timeout
	sound.queue_free()
	await process_frame
	check(AudioServer.bus_count == initial_buses, "Audio teardown returns all owned buses")
	call_deferred("finish")

func finish() -> void:
	await process_frame
	await create_timer(.2).timeout
	print("COMBAT_AUDIO_V8 ", JSON.stringify({"checks": checks, "failures": failures}))
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
