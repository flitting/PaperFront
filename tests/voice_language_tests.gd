extends SceneTree

const Localization = preload("res://scripts/localization.gd")
const Browser = preload("res://scripts/audio_browser.gd")
const Catalog = preload("res://scripts/audio_browser_catalog.gd")
var checks: int = 0
var failures: Array[String] = []
var caption: String = ""

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func hold(player: AudioStreamPlayer) -> void:
	var stream: AudioStreamWAV = player.stream.duplicate()
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
	player.stream = stream
	player.play()

func run() -> void:
	Localization.initialize("en")
	check(PaperAudio.voice_language_available("en"), "all English radio, commander, and system audio resources are installed")
	check(PaperAudio.voice_language_available("zh_CN"), "original Chinese voices remain available")
	var audio := PaperAudio.new()
	check(audio.voice_language == "en", "new audio nodes default to actual English speech")
	root.add_child(audio)
	await process_frame
	audio.set_process(false); audio.commander.set_process(false); audio.music.set_process(false)
	audio.configure_units(RulesLoader.load_rules())
	audio.unit_caption.connect(func(text: String, _duration: float): caption = text)
	check(audio.speech_clips.size() == 96 and audio.radio_bank.size() == 300, "English covers four factions, three classes, eight actions, and all 300 variants")
	check(audio.system_clips.size() == 2 and audio.commander.clips.size() == 13, "English includes both existing spoken system cues and all thirteen commander reports")
	check(audio.radio_bank.values().all(func(stream): return stream.resource_path.begins_with("res://assets/audio/english/")), "English selection routes only to real English WAV resources")
	var han := RegEx.new(); han.compile("[\\x{3400}-\\x{9fff}]")
	var actors: Dictionary = {}
	for group: String in audio.speech_clips:
		var clips: Array = audio.speech_clips[group]
		check(clips.size() == (4 if group.ends_with("/death") else 3), "all English action variants exist: " + group)
		for clip: Dictionary in clips:
			check(not str(clip.text).is_empty() and han.search(str(clip.text)) == null, "English recording has an authored English transcript: " + str(clip.key))
			check(not PaperAudio.caption_text(clip).is_empty(), "recording retains semantic source text for independent UI language: " + str(clip.key))
			var stream: AudioStreamWAV = audio.radio_bank[str(clip.key)]
			check(stream != null and not stream.data.is_empty() and stream.mix_rate == 22050 and not stream.stereo and absf(stream.get_length() - float(clip.duration_s)) < .001, "English speech PCM format and duration match metadata: " + str(clip.key))
			check(FileAccess.get_sha256(str(clip.file)) == str(clip.sha256), "English speech waveform matches provenance hash: " + str(clip.key))
			var profile: String = group.get_slice("/", 0) + "/" + group.get_slice("/", 1)
			if not actors.has(profile): actors[profile] = str(clip.speaker_id)
			check(actors[profile] == str(clip.speaker_id), "each faction/class keeps one actor across actions: " + profile)
	var identities: Dictionary = {}
	for identity: String in actors.values(): identities[identity] = true
	check(actors.size() == 12 and identities.size() == 12, "twelve faction/class actor profiles remain distinct")
	var originals: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PaperAudio.VOICE_MANIFEST))
	for original: Dictionary in originals.clips:
		var group: String = str(original.key).get_slice("/", 0) + "/" + str(original.key).get_slice("/", 1) + "/" + str(original.key).get_slice("/", 2)
		var replacement: Array = audio.speech_clips[group].filter(func(clip): return clip.key == original.key)
		check(replacement.size() == 1 and replacement[0].sha256 != original.sha256 and PaperAudio.caption_text(replacement[0]) == original.text, "English uses a new waveform while preserving the original semantic caption: " + str(original.key))
	var recorder := AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	var voice_bus: int = 0
	var record_effect: int = AudioServer.get_bus_effect_count(voice_bus)
	AudioServer.add_bus_effect(voice_bus, recorder, record_effect)
	await create_timer(.15).timeout
	recorder.set_recording_active(true)
	check(audio.play_unit_voice("kestrel_rifle", "select", {"id":1,"team":0}), "English selection starts a real speech clip")
	check(audio.speech_player.playing and audio.speech_player.stream.resource_path.begins_with("res://assets/audio/english/"), "English selection actually reaches the speech player")
	check(han.search(TranslationServer.translate(caption)) == null, "English UI renders an English unit subtitle")
	await create_timer(.8).timeout
	recorder.set_recording_active(false)
	var output: AudioStreamWAV = recorder.get_recording()
	var peak: int = 0
	if output != null:
		for offset in range(0, output.data.size() - 1, 2): peak = maxi(peak, absi(output.data.decode_s16(offset)))
	check(output != null and peak > 0 and peak < 32767, "actual English selection emits nonzero unclipped PCM through the voice bus")
	AudioServer.remove_bus_effect(voice_bus, record_effect)
	output = null; recorder = null
	Localization.set_language("zh_CN")
	check(audio.voice_language == "en" and han.search(TranslationServer.translate(caption)) != null, "Chinese UI can display Chinese subtitles while the English recording keeps playing")
	Localization.set_language("en")
	var browser := Browser.new()
	browser.configure(audio, RulesLoader.load_rules())
	root.add_child(browser)
	await process_frame
	browser.show(); browser.configure(audio, RulesLoader.load_rules())
	var chosen: String = "voice/kestrel/infantry/select/1"
	browser.select_entry(chosen); browser.play_selected()
	check(browser.preview_player.playing and str(browser.selected_entry.file).begins_with("res://assets/audio/english/") and browser.preview_player.stream.data == (load(str(browser.selected_entry.file)) as AudioStreamWAV).data, "browser previews the selected English bank")
	check(audio.set_voice_language("zh_CN"), "Chinese voice selection succeeds independently of English UI")
	check(not browser.preview_player.playing and browser.preview_player.stream == null, "switching voice language stops a stale English audition")
	check(browser.selected_id == chosen and str(browser.selected_entry.file).begins_with("res://assets/audio/revision_v8/radio/"), "browser keeps the selected action and refreshes to its Chinese recording")
	browser.hide(); browser.set_session_active(false)
	check(audio.radio_bank.size() == 285 and audio.commander.voice_language == "zh_CN" and caption.is_empty(), "Chinese switch restores original radio/commander banks and clears old subtitles")
	audio.reset_field()
	audio.play_event({"kind":"fire","team":1,"id":20,"weapon":"kestrel_tank","pos":Vector2.ZERO})
	var field: AudioStreamPlayer = audio.field_players[0]
	hold(field)
	var field_stream: AudioStream = field.stream
	audio.music.set_scene("battle")
	for step in range(40): audio.music._process(.1)
	check(audio.music.player.playing and audio.music.player.stream != null, "fixture has an active instrumental music stream before changing voices")
	var music_stream: AudioStream = audio.music.player.stream
	audio.play_unit_group_voice("kestrel_rifle", "select", [{"id":1,"team":0},{"id":2,"team":0},{"id":3,"team":0}])
	audio.play_unit_voice("kestrel_rifle", "move", {"id":1,"team":0})
	audio.play_system_voice("low_power")
	audio.commander.enabled = true
	audio.commander.request("base_attacked")
	check(not audio.group_voice_queue.is_empty() and not audio.pending_speech.is_empty() and not audio.pending_system.is_empty() and not audio.commander.pending.is_empty(), "fixture has active and queued Chinese speech on all lanes")
	check(audio.set_voice_language("en"), "switching back selects English recordings")
	check(audio.active_speech_count() == 0 and audio.group_voice_queue.is_empty() and audio.pending_speech.is_empty() and audio.pending_system.is_empty() and audio.commander.pending.is_empty() and caption.is_empty(), "language switch clears active speech, queued group copies, pending orders, system reports, commander reports, and subtitles")
	check(field.playing and field.stream == field_stream and audio.music.player.stream == music_stream, "voice switching preserves current sound effects and music")
	audio.commander.request("base_attacked"); audio.commander._process(.01)
	check(audio.commander.player.playing and audio.commander.player.stream.resource_path.begins_with("res://assets/audio/english/commander/"), "new commander reports use the English recording after a live switch")
	audio.commander.clear_playback(); audio.reset_field()
	audio.play_system_voice("power_restored")
	check(audio.speech_player.playing and audio.speech_player.stream.resource_path.begins_with("res://assets/audio/english/system/"), "existing system alerts use the English recording")
	var english_rows: Array[Dictionary] = Catalog.load_catalog("en")
	var chinese_rows: Array[Dictionary] = Catalog.load_catalog("zh_CN")
	check(english_rows.filter(func(row): return row.type == "voice").size() == 302 and chinese_rows.filter(func(row): return row.type == "voice").size() == 287, "browser catalogs reflect the selected language's actual radio/system inventory")
	check(english_rows.filter(func(row): return row.type != "voice") == chinese_rows.filter(func(row): return row.type != "voice"), "voice language never changes sound effects or music metadata")
	browser.queue_free(); audio.stop_all(); audio.queue_free()
	await process_frame
	if failures.is_empty(): print("VOICE_LANGUAGE TESTS PASSED: %d checks" % checks)
	else:
		for failure: String in failures: push_error(failure)
		print("VOICE_LANGUAGE TESTS FAILED: %d/%d" % [failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
