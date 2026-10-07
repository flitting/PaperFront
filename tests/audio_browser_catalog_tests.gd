extends SceneTree

const Catalog = preload("res://scripts/audio_browser_catalog.gd")
const REPORT := "res://artifacts/audio_revision_20261007/audio_browser_catalog_validation.json"
var checks := 0
var failures: Array[String] = []
var type_counts: Dictionary = {}

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func stream_paths(value: Variant, paths: Dictionary) -> void:
	var streams: Array = value if value is Array else [value]
	for stream: AudioStream in streams:
		if stream != null: paths[stream.resource_path] = true

func run() -> void:
	var before_buses: int = AudioServer.bus_count
	var rows: Array[Dictionary] = Catalog.load_catalog()
	check(rows.size() == 366, "inventory contains all current287voices,74effects and5music files after15 obsolete-name retirements")
	check(JSON.stringify(rows) == JSON.stringify(Catalog.load_catalog()), "catalog IDs/order/metadata are deterministic")
	var ids: Dictionary = {}
	var files: Dictionary = {}
	var voice_groups: Dictionary = {}
	var by_type: Dictionary = {"voice": {}, "sfx": {}, "music": {}}
	for row: Dictionary in rows:
		var id: String = str(row.id)
		var path: String = str(row.file)
		check(not ids.has(id) and not files.has(path), "one stable ID and one row for each applied file: " + id)
		ids[id] = true
		files[path] = true
		for field in ["id", "group_id", "file", "title", "text", "duration_s", "sample_rate", "channels", "sample_width", "type", "faction", "category", "action", "provider", "model", "variant", "variants", "sha256"]:
			check(row.has(field), "browser filter/playback metadata exists: " + id + "/" + field)
		check(not path.begins_with("res://assets/audio/radio/") and not path.begins_with("res://assets/audio/voices/"), "retired speech cannot appear: " + id)
		check(ResourceLoader.exists(path) and FileAccess.file_exists(path), "actual selected audio resource exists: " + id)
		check(FileAccess.get_sha256(path) == str(row.sha256), "browser provenance hash matches the actual current file: " + id)
		var stream: AudioStreamWAV = load(path)
		check(stream != null and absf(stream.get_length() - float(row.duration_s)) < .001, "browser duration matches actual imported PCM: " + id)
		check(stream != null and stream.mix_rate == int(row.sample_rate) and stream.stereo == (int(row.channels) == 2) and stream.format == AudioStreamWAV.FORMAT_16_BITS and int(row.sample_width) == 2, "browser imported PCM format matches its metadata: " + id)
		var type: String = str(row.type)
		type_counts[type] = int(type_counts.get(type, 0)) + 1
		by_type[type][path] = true
		if type == "voice":
			if not voice_groups.has(row.group_id): voice_groups[row.group_id] = {"texts": {}, "files": {}}
			voice_groups[row.group_id].texts[row.text] = true
			voice_groups[row.group_id].files[path] = true
			var count: int = int(row.variants)
			check((count == 1 if row.category == "system" else count == 4 if row.action == "death" else count in [2,3]) and not str(row.text).is_empty(), "voice group retains distinct same-actor recordings after obsolete faction-name retirement")
	check(type_counts == {"voice": 287, "sfx": 74, "music": 5}, "current type totals retire15 obsolete faction-name recordings")
	check(voice_groups.size() == 98, "all four faction/three class/eight action groups and two system alerts are available")
	for group: String in voice_groups:
		var count: int = voice_groups[group].texts.size()
		check(voice_groups[group].files.size() == count and (count == 1 if group.begins_with("voice/system/") else count == 4 if group.ends_with("/death") else count in [2,3]), "catalog preserves distinct actual audio/text alternatives: " + group)
	# Ground truth is the current audio node's post-override runtime banks. Generic
	# fallback keys are deliberately absent from the routed-family list below.
	var sound := PaperAudio.new()
	root.add_child(sound)
	await process_frame
	sound.set_process(false)
	sound.music.set_process(false)
	var expected_voices: Dictionary = {}
	for key: String in sound.radio_bank: stream_paths(sound.radio_bank[key], expected_voices)
	for key: String in sound.system_bank: stream_paths(sound.system_bank[key], expected_voices)
	check(by_type.voice == expected_voices, "browser voices equal the actual runtime radio bank")
	var expected_effects: Dictionary = {}
	for family: String in Catalog.EFFECT_NAMES:
		if sound.bank.has(family): stream_paths(sound.bank[family], expected_effects)
	for family: String in PaperAudio.UI_EVENTS:
		if sound.bank.has(family): stream_paths(sound.bank[family], expected_effects)
	check(by_type.sfx == expected_effects and expected_effects.size() == 74, "browser effects equal current routed runtime families after overrides and alias deduplication")
	for row: Dictionary in rows:
		if row.type != "music": continue
		var stream: AudioStreamWAV = load(str(row.file))
		check(sound.music.tracks.has(row.action) and sound.music.tracks[row.action].data == stream.data, "browser score is the actual runtime scene/map music: " + str(row.action))
	check(by_type.music.size() == sound.music.tracks.size(), "all current music-player track options are listed")
	check(not files.has("res://assets/audio/music/menu.wav") and files.has(PaperMusic.REVISION_MUSIC_DIR + "menu.wav"), "new menu replaces the historical menu in the browser")
	for family in ["build", "fire", "impact", "death", "death_soft", "engine_loop", "tracks_loop", "aircraft_loop", "fire_air", "bomb_release", "rearm"]:
		check(not files.has("res://assets/audio/" + family + ".wav"), "shadowed/unused historical effect is excluded: " + family)
	var retired: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/retired_voice_resources.json"))
	for path: String in retired.get("retired_audio_files", []):
		check(not files.has("res://" + path), "removed historical voice is not a playlist option: " + path)
	sound.stop_all()
	await create_timer(.15).timeout
	sound.queue_free()
	await process_frame
	sound = null
	check(AudioServer.bus_count == before_buses, "catalog validation releases its temporary runtime audio buses")
	call_deferred("finish")

func finish() -> void:
	await process_frame
	await create_timer(.3).timeout
	var report := {"checks": checks, "failures": failures, "rows": 366, "type_counts": type_counts,
		"scope": "current canonical runtime banks after overrides, distinct variants, resource hashes and imported durations; no playback or human listening claim"}
	var path: String = ProjectSettings.globalize_path(REPORT)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t") + "\n")
	print("AUDIO_BROWSER_CATALOG ", JSON.stringify(report))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
