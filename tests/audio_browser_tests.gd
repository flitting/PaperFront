extends SceneTree

const Browser = preload("res://scripts/audio_browser.gd")
var failures: Array[String] = []
var checks := 0
var sound: PaperAudio
var browser: Control
var recorder: AudioEffectRecord
var recorder_index := -1
var pcm: Array[Dictionary] = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func choose(filter: OptionButton, value: String) -> void:
	for index in range(filter.item_count):
		if str(filter.get_item_metadata(index)) == value:
			filter.select(index)
			return
	check(false, "Filter choice exists: " + value)

func capture(label: String, trigger: Callable) -> Dictionary:
	recorder.set_recording_active(false)
	await create_timer(.12).timeout
	recorder.set_recording_active(true)
	trigger.call()
	await create_timer(.23).timeout
	recorder.set_recording_active(false)
	var result := {"label": label, "samples": 0, "peak": 0}
	var stream: AudioStreamWAV = recorder.get_recording()
	if stream != null and stream.format == AudioStreamWAV.FORMAT_16_BITS:
		result.samples = stream.data.size() / 2
		for offset in range(0, stream.data.size() - 1, 2): result.peak = maxi(int(result.peak), absi(stream.data.decode_s16(offset)))
	pcm.append(result)
	return result

func find_row(kind: String, action: String = "") -> Dictionary:
	for row: Dictionary in browser.catalog:
		if str(row.type) == kind and (action.is_empty() or str(row.action) == action): return row
	return {}

func run() -> void:
	root.size = Vector2i(1600, 900)
	var original_buses: int = AudioServer.bus_count
	sound = PaperAudio.new()
	root.add_child(sound)
	await process_frame
	sound.configure_units(RulesLoader.load_rules())
	sound.set_mix({"master": .75, "music": .4, "sfx": .65, "voice": .8, "muted": false})
	sound.set_scene("menu")
	await create_timer(2.4).timeout
	check(sound.music.player.playing, "Normal menu score plays before opening the audio tab")
	var before_position: float = sound.music.player.get_playback_position()
	var initial_mix: Dictionary = sound.get_mix()
	browser = Browser.new()
	browser.hide()
	root.add_child(browser)
	browser.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	browser.configure(sound, RulesLoader.load_rules())
	await process_frame
	var total: int = 300 + 2 + 74 + sound.music.tracks.size()
	browser.show()
	before_position = float(browser._music_snapshot.get("position", before_position))
	check(browser.session_active and sound.preview_active and not sound.music.player.playing and not sound.music.is_processing(), "Entering the tab pauses normal music before any clip plays")
	check(browser.catalog.size() == total and browser.current_entries.size() == total, "Browser has every unique applied game file")
	check(browser.entry_buttons.size() == total, "Every current audio has a native selection button")
	check(browser.get_children().filter(func(child): return child is AudioStreamPlayer).size() == 1, "Browser owns exactly one audition player")
	choose(browser.type_filter, "voice")
	choose(browser.faction_filter, "iron")
	choose(browser.category_filter, "vehicle")
	choose(browser.action_filter, "under_attack")
	browser._rebuild_entries()
	check(browser.current_entries.size() == 3 and browser.current_entries.all(func(row): return row.faction == "iron" and row.category == "vehicle" and row.action == "under_attack"), "Type/faction/class/action filters combine into the three actual variants")
	choose(browser.type_filter, "sfx"); browser.type_filter.item_selected.emit(browser.type_filter.selected)
	check(browser.current_entries.size() == 74 and browser.faction_filter.disabled, "Changing voice to effects clears inapplicable filters and shows applied effects")
	check(browser.action_filter.item_count == 35, "Effect action choices contain current effect families only")
	choose(browser.type_filter, "music"); browser.type_filter.item_selected.emit(browser.type_filter.selected)
	check(browser.current_entries.size() == sound.music.tracks.size() and browser.faction_filter.disabled and browser.category_filter.disabled, "Changing to music clears old voice/effect filters")
	choose(browser.type_filter, ""); browser.type_filter.item_selected.emit(browser.type_filter.selected)
	browser.search.text = "绝不存在的音频"
	browser._rebuild_entries()
	check(browser.current_entries.is_empty() and browser.play_button.disabled, "Empty search disables playback and clears stale selection")
	browser.search.text = ""
	browser._rebuild_entries()
	choose(browser.type_filter, "")
	choose(browser.faction_filter, "")
	choose(browser.category_filter, "")
	choose(browser.action_filter, "")
	browser._rebuild_entries()
	var voice: Dictionary = find_row("voice", "select")
	var effect: Dictionary = find_row("sfx", "fire_cannon")
	var music_row: Dictionary = find_row("music", "menu")
	check(not voice.is_empty() and not effect.is_empty() and not music_row.is_empty(), "All three applied families have selectable rows")
	check(browser.catalog.all(func(row): return row.has("id") and row.has("file")), "Empty search and selection never mutate the applied inventory")
	var imported: AudioStreamWAV = load(str(voice.file))
	check(Browser.imported_clip_valid(voice, imported), "Export-style imported PCM validates without a raw-file hash")
	var wrong: Dictionary = voice.duplicate()
	wrong.duration_s = float(voice.duration_s) + 1.0
	check(not Browser.imported_clip_valid(wrong, imported), "Imported PCM validation rejects an incorrect manifest duration")
	imported = null
	browser.select_entry(str(voice.id))
	browser.play_button.pressed.emit()
	check(browser.preview_player.playing and browser.preview_player.bus == PaperAudio.VOICE_BUS and sound.preview_active, "Native play button auditions the actual voice through its category bus")
	check(not sound.music.player.playing and not sound.music.is_processing(), "Preview freezes and silences the normal music player")
	check(browser.caption_label.text == voice.text and browser.source_label.text.contains(str(voice.file)), "Audition text and source belong to the chosen actual WAV")
	sound.play("select")
	sound.play_unit_voice("rivet_tank", "move")
	sound.update_battlefield(.2, {1:{"team":0,"hp":100,"motion":.2,"spec":"rivet_tank","pos":Vector2(12,12)}}, Vector2(12,12))
	check(sound.players.all(func(player): return not player.playing), "Game effects, speech and engines cannot overlap a debug audition")
	browser.stop_button.pressed.emit()
	check(not browser.preview_player.playing and browser.preview_player.stream == null and sound.preview_active, "Native stop button releases the sole preview while keeping the tab session silent")
	check(not sound.music.player.playing and not sound.music.is_processing(), "Stopping a clip cannot resume background music inside the tab")
	browser.hide()
	check(sound.music.player.playing and sound.music.is_processing() and not sound.preview_active, "Only leaving the tab restores normal music")
	check(absf(sound.music.player.get_playback_position() - before_position) < .3, "Normal music resumes from its saved position")
	browser.show()
	check(sound.get_mix() == initial_mix, "Preview does not change any saved mix preference")
	browser.play_selected(); sound.set_mix({"muted": true}); browser.stop_preview()
	check(not sound.music.player.playing, "Stopping a muted preview still leaves background music paused")
	browser.hide()
	check(sound.music.player.playing and AudioServer.is_bus_mute(AudioServer.get_bus_index(PaperAudio.MASTER_BUS)), "Closing audition while muted preserves the normal music playback position under the muted master")
	sound.set_mix(initial_mix)
	browser.show()
	browser.select_entry(str(music_row.id)); browser.play_selected()
	check(browser.preview_player.bus == PaperAudio.MUSIC_BUS and not sound.music.player.playing, "Music audition uses the same music preference with one foreground cue")
	browser.select_entry(str(effect.id))
	check(not browser.preview_player.playing and not sound.music.player.playing and sound.preview_active, "Changing selection stops audition but holds the background score paused")
	browser.play_selected()
	check(browser.preview_player.bus == PaperAudio.BUS_NAME, "Effect auditions use the actual effects bus")
	choose(browser.type_filter, "music"); browser._rebuild_entries()
	check(not browser.preview_player.playing and sound.preview_active and not sound.music.player.playing, "Changing family filters stops previous audio without leaving the silent tab")
	choose(browser.type_filter, ""); browser._rebuild_entries()
	browser.select_entry(str(music_row.id)); browser.play_selected()
	browser.hide()
	check(not browser.preview_player.playing and not sound.preview_active and sound.music.player.playing, "Hiding or closing the browser stops audition and restores the normal score")
	browser.show(); browser.select_entry(str(music_row.id)); browser.play_selected()
	browser.set_enabled(false)
	check(not browser.preview_player.playing and browser.play_button.disabled and not sound.preview_active, "Disabling the feature stops audio immediately")
	browser.set_enabled(true)
	sound.set_scene("silent")
	recorder = AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	recorder_index = AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, recorder, recorder_index)
	# Let the newly attached record effect reach the audio mix thread before
	# enabling its first capture; later captures reuse the same initialized graph.
	await create_timer(.3).timeout
	browser.select_entry(str(voice.id))
	var audible_voice: Dictionary = await capture("voice_preview", func(): browser.play_selected())
	check(int(audible_voice.samples) > 0 and int(audible_voice.peak) > 0, "Actual preview voice reaches engine-output PCM")
	browser.stop_preview(); sound.set_mix({"voice": 0.0})
	var muted_voice: Dictionary = await capture("voice_slider_zero", func(): browser.play_selected())
	check(int(muted_voice.samples) > 0 and int(muted_voice.peak) == 0, "Voice-zero slider silences preview PCM without changing its caption")
	check(browser.caption_label.text == voice.text, "Silent audition retains the selected phrase text")
	browser.stop_preview(); sound.set_mix({"voice": .8})
	browser.select_entry(str(effect.id))
	var audible_effect: Dictionary = await capture("effect_preview", func(): browser.play_selected())
	check(int(audible_effect.peak) > 0, "Actual effect preview reaches engine-output PCM")
	browser.stop_preview(); sound.set_mix({"sfx": 0.0})
	var muted_effect: Dictionary = await capture("sfx_slider_zero", func(): browser.play_selected())
	check(int(muted_effect.peak) == 0, "Effects-zero slider silences actual effect preview PCM")
	browser.stop_preview(); sound.set_mix({"sfx": .65})
	browser.select_entry(str(music_row.id))
	var audible_music: Dictionary = await capture("music_preview", func(): browser.play_selected())
	check(int(audible_music.peak) > 0, "Actual music preview reaches its category's engine-output PCM")
	browser.stop_preview(); sound.set_mix({"music": 0.0})
	var muted_music: Dictionary = await capture("music_slider_zero", func(): browser.play_selected())
	check(int(muted_music.peak) == 0, "Music-zero slider silences the audition score")
	browser.stop_preview(); sound.set_mix({"music": .4})
	browser.select_entry(str(effect.id))
	browser.stop_preview(); sound.set_mix({"master": 0.0})
	var muted_master: Dictionary = await capture("master_slider_zero", func(): browser.play_selected())
	check(int(muted_master.peak) == 0, "Master-zero slider immediately silences audition PCM")
	browser.stop_preview(); sound.set_mix({"master": .75, "muted": true})
	var muted_all: Dictionary = await capture("total_mute", func(): browser.play_selected())
	check(int(muted_all.peak) == 0, "Total mute remains authoritative in the browser")
	browser.stop_preview(); browser.hide(); sound.set_mix(initial_mix)
	await create_timer(.4).timeout
	sound.recent.clear()
	sound.play("select")
	check(sound.ui_players.any(func(player): return player.playing), "Ordinary game effects resume after closing preview mode")
	check(sound.play_unit_voice("rivet_tank", "attack"), "Ordinary unit acknowledgements resume after preview mode")
	browser.stop_preview()
	recorder.set_recording_active(false)
	AudioServer.remove_bus_effect(0, recorder_index)
	recorder = null
	browser.queue_free()
	sound.stop_all()
	await create_timer(.25).timeout
	sound.queue_free()
	await process_frame
	check(AudioServer.bus_count == original_buses, "Browser and game sound release all owned buses")
	call_deferred("finish")

func finish() -> void:
	await process_frame
	await create_timer(.3).timeout
	print("AUDIO_BROWSER ", JSON.stringify({"checks":checks,"failures":failures,"pcm":pcm,"scope":"actual applied inventory, native filters/play/stop, one preview, reversible background suspension, category/master mute and output-only PCM; no microphone"}))
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
