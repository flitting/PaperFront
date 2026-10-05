extends SceneTree

# Small audio-only regression: no main scene, renderer or simulation stress.
var failures: Array[String] = []
var checks := 0
var caption_text := ""

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _initialize() -> void:
	call_deferred("run")

func step_music(sound: PaperAudio, seconds: float) -> void:
	for index in range(int(ceil(seconds / 0.05))): sound.music._process(0.05)

func run() -> void:
	var before_buses := AudioServer.bus_count
	var sound := PaperAudio.new()
	root.add_child(sound)
	await process_frame
	sound.set_process(false)
	sound.music.set_process(false)
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/rules.json"))
	sound.configure_units(rules)
	sound.unit_caption.connect(func(text: String, _duration: float): caption_text = text)
	check(sound.music.tracks.size() == 12, "Five scenes and seven independent map themes load")
	check(sound.radio_bank.size() == 20, "All four factions have five spoken Mandarin events")
	check(sound.music.get_child_count() == 1, "Music owns exactly one player")
	for name in [PaperAudio.MASTER_BUS, PaperAudio.MUSIC_BUS, PaperAudio.BUS_NAME, PaperAudio.VOICE_BUS]:
		check(AudioServer.get_bus_index(name) >= 0, "Dedicated bus exists: " + name)
	for name in [PaperAudio.MUSIC_BUS, PaperAudio.BUS_NAME, PaperAudio.VOICE_BUS]:
		check(AudioServer.get_bus_send(AudioServer.get_bus_index(name)) == PaperAudio.MASTER_BUS, "Bus routes through Demo master: " + name)
	for family in ["music", "radio"]:
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/%s/manifest.json" % family))
		check(manifest.get("license", "") == ("CC0-1.0" if family == "music" else "GPL-3.0-or-later"), family + " has its documented asset license")
		var entries: Array = manifest.get("tracks", manifest.get("clips", []))
		for entry in entries:
			var path: String = str(entry.path)
			var stream: AudioStreamWAV = load(path)
			check(stream != null and stream.mix_rate == 22050 and stream.format == AudioStreamWAV.FORMAT_16_BITS, "Original PCM format: " + path)
			check(FileAccess.get_sha256(path) == str(entry.sha256), "Asset provenance hash: " + path)
			check(absf(stream.get_length() - float(entry.duration_s)) < 0.001, "Imported audio duration matches its final PCM manifest: " + path)
	for name in PaperMusic.TRACKS:
		sound.set_scene(name)
		step_music(sound, 3.0)
		check(sound.music.scene == name and sound.music.player.playing, "Scene track starts: " + name)
		check(sound.music.player.stream == sound.music.tracks[name], "Scene uses its intended asset: " + name)
		var stream: AudioStreamWAV = sound.music.player.stream
		check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_end == int(round(stream.get_length() * stream.mix_rate)), "Complete seamless loop range: " + name)
	for map_id: String in PaperMusic.MAP_TRACKS:
		sound.set_scene("battle")
		sound.set_map(map_id)
		step_music(sound, 3.0)
		var expected: String = str(PaperMusic.MAP_TRACKS[map_id])
		check(sound.music.scene == "battle" and sound.music.active_track == expected, "Battle scene resolves its map theme: " + map_id)
		check(sound.music.player.stream == sound.music.tracks[expected] and sound.music.player.playing, "Changing maps swaps the playing theme: " + map_id)
	sound.set_map("dev")
	step_music(sound, 3.0)
	check(sound.music.active_track == "battle", "Debug and historical maps retain the fallback theme")
	sound.set_scene("menu")
	sound.set_scene("battle")
	sound.set_scene("win")
	step_music(sound, 3.0)
	check(sound.music.scene == "win" and sound.music.get_child_count() == 1, "Rapid scene changes settle on final request with one player")
	sound.set_scene("silent")
	step_music(sound, 1.5)
	check(not sound.music.player.playing and sound.music.player.stream == null, "Silent scene fully releases the music stream")
	sound.set_mix({"master": 2.0, "music": -1.0, "sfx": .31, "voice": .64})
	var saved := sound.get_mix()
	check(saved.master == 1.0 and saved.music == 0.0 and saved.sfx == .31 and saved.voice == .64, "Linear preferences clamp and round-trip")
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index(PaperAudio.MUSIC_BUS)), "Zero music gain mutes its bus")
	sound.set_mix({"music": .45})
	check(not AudioServer.is_bus_mute(AudioServer.get_bus_index(PaperAudio.MUSIC_BUS)), "Restoring music gain unmutes its bus")
	for spec in rules.units:
		var definition: Dictionary = rules.units[spec]
		for action_id in definition.get("voices", {}):
			sound.reset_field()
			check(sound.play_unit_voice(str(spec), str(action_id)), "Authored unit response remains available: " + str(spec) + "/" + str(action_id))
			check(caption_text.begins_with(str(definition.name) + "："), "Response keeps its unit's Chinese caption: " + str(spec))
			var expected_key: String = str(definition.faction) + "/" + str(action_id)
			check(sound.speech_player.stream == sound.radio_bank.get(expected_key), "Response loads only original radio: " + expected_key)
			check(caption_text.ends_with(str(sound.speech_clips[expected_key][0].text)), "Mandarin words and visible subtitle match: " + expected_key)
	check(sound.speech_cache.is_empty(), "Online TTS cache remains empty")
	sound.reset_field()
	sound.play_unit_voice("sky_creator_hand", "select")
	sound._process(.3)
	var effects_bus := AudioServer.get_bus_index(PaperAudio.BUS_NAME)
	check(AudioServer.get_bus_volume_db(effects_bus) < linear_to_db(.31), "Radio ducks battle effects below the selected SFX level")
	var music_bus := AudioServer.get_bus_index(PaperAudio.MUSIC_BUS)
	check(AudioServer.get_bus_volume_db(music_bus) < linear_to_db(.45), "Spoken words briefly duck map music without changing preference")
	sound.set_mix({"sfx": .62})
	sound._process(.1)
	check(absf(AudioServer.get_bus_volume_db(effects_bus) - (linear_to_db(.62) + sound.effects_duck_db)) < .001, "Ducking preserves a newly selected SFX level")
	sound.set_mix({"music": .37})
	sound._process(.1)
	check(sound.get_mix().music == .37 and absf(AudioServer.get_bus_volume_db(music_bus) - (linear_to_db(.37) + sound.music_duck_db)) < .001, "Music ducking preserves a newly selected music level")
	sound.set_mix({"voice": 0.0})
	sound.reset_field()
	check(sound.play_unit_voice("iron_tank", "select") and not caption_text.is_empty(), "Zero voice volume retains Chinese captions")
	check(not sound.speech_player.playing, "Zero voice volume skips radio playback")
	sound.set_mix({"voice": .85})
	sound.reset_field()
	sound.play_unit_voice("kestrel_tank", "select")
	check(sound.speech_player.playing, "Speech starts before a mid-phrase voice slider change")
	sound.set_mix({"voice": 0.0})
	check(sound.play_unit_voice("iron_tank", "move") and caption_text.ends_with(str(sound.speech_clips["iron/move"][0].text)), "Zeroing voice mid-phrase immediately permits the new order caption")
	check(not sound.speech_player.playing and sound.pending_speech.is_empty(), "Voice zero stops speech and clears stale pending words")
	sound.set_mix({"voice": .85})
	sound.reset_field()
	sound.play_unit_voice("kestrel_tank", "select")
	check(sound.speech_player.playing, "Speech starts before a mid-phrase master slider change")
	sound.set_mix({"master": 0.0})
	check(sound.play_unit_voice("iron_tank", "attack") and caption_text.ends_with(str(sound.speech_clips["iron/attack"][0].text)), "Zeroing master mid-phrase immediately permits the new attack caption")
	check(not sound.speech_player.playing and sound.pending_speech.is_empty(), "Master zero stops speech and clears stale pending words")
	sound.set_mix({"master": 1.0})
	sound.set_mix({"muted": true, "voice": .85})
	for name in [PaperAudio.MASTER_BUS, PaperAudio.MUSIC_BUS, PaperAudio.BUS_NAME, PaperAudio.VOICE_BUS]:
		check(AudioServer.is_bus_mute(AudioServer.get_bus_index(name)), "Total mute controls bus: " + name)
	check(sound.play_unit_voice("rivet_tank", "select") and not caption_text.is_empty(), "Total mute retains new command captions")
	check(not sound.speech_player.playing, "Total mute does not start radio playback")
	sound.muted = false
	for name in [PaperAudio.MASTER_BUS, PaperAudio.MUSIC_BUS, PaperAudio.BUS_NAME, PaperAudio.VOICE_BUS]:
		check(not AudioServer.is_bus_mute(AudioServer.get_bus_index(name)), "Legacy mute property restores bus: " + name)
	var entities := {1: {"team": 0, "hp": 100, "motion": 0.2, "spec": "rivet_tank", "pos": Vector2(10, 10)}}
	for index in range(10): sound.update_battlefield(.16, entities, Vector2(10, 10))
	check(sound.engine_players[0].playing and sound.engine_players[1].playing, "Nearby moving vehicles start field loops")
	sound.play_event({"kind": "fire", "weapon": "rivet_tank", "pos": Vector2(10, 10)})
	sound.reset_field()
	for player in sound.players: check(not player.playing, "Loading/new-match reset immediately stops all field voices")
	check(sound.engine_level == 0.0 and sound.target_engine == 0.0 and sound.pending_speech.is_empty(), "Reset clears old movement targets and pending responses")
	sound.set_scene("battle")
	step_music(sound, 3.0)
	sound.stop_all()
	check(not sound.music.player.playing, "Quit stops the music player immediately")
	await create_timer(.15).timeout
	sound.queue_free()
	await process_frame
	check(AudioServer.bus_count == before_buses, "Teardown removes every owned Demo bus")
	var report := {"status": "PASS" if failures.is_empty() else "FAIL", "checks": checks,
		"scope": "audio-only headless; PCM provenance, mix controls, radio/captions, scene transitions, immediate field reset, teardown",
		"failures": failures}
	var args := OS.get_cmdline_user_args()
	if "--audio-report" in args:
		var index := args.find("--audio-report")
		if index + 1 < args.size():
			var output := FileAccess.open(args[index + 1], FileAccess.WRITE)
			if output: output.store_string(JSON.stringify(report, "  "))
	# Return from the async verification stack before quitting, so temporary
	# loaded resource references do not survive until engine teardown.
	call_deferred("finish", report)

func finish(report: Dictionary) -> void:
	# Let the completed verification coroutine release its loaded resources,
	# then give the audio thread a main-loop interval to retire stopped playbacks.
	await process_frame
	await create_timer(.2).timeout
	print("DEMO_AUDIO ", JSON.stringify(report))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
