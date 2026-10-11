extends Node
class_name PaperAudio

signal unit_caption(text: String, duration: float)
signal voice_language_changed(language: String)

# Separate UI/field voices keep crowded combat from swallowing an order click.
# Original PCM assets have >2 dB headroom; the dedicated SFX bus also limits peaks.
const UI_EVENTS := ["select", "command", "produce", "delivery", "build", "sell", "low_power", "result", "error"]
const VARIANT_BANKS := ["fire_rifle", "fire_anti", "fire_cannon", "fire_artillery", "impact_small", "impact_medium", "impact_large", "death"]
const BUS_NAME := "Paper SFX"
const VOICE_BUS := "Paper Voice"
const MASTER_BUS := "Paper Master"
const MUSIC_BUS := "Paper Music"
const MIX_KEYS := ["master", "music", "sfx", "voice", "commander"]
const VOICE_MANIFEST := "res://assets/audio/revision_v8/radio/manifest.json"
const SYSTEM_MANIFEST := "res://assets/audio/revision_v8/system/manifest.json"
const ENGLISH_VOICE_MANIFEST := "res://assets/audio/english/radio/manifest.json"
const ENGLISH_SYSTEM_MANIFEST := "res://assets/audio/english/system/manifest.json"
const ENGLISH_COMMANDER_MANIFEST := "res://assets/audio/english/commander/manifest.json"
const SFX_MANIFEST := "res://assets/audio/revision_v8/sfx/manifest.json"
const RADIO_ACTIONS := ["select", "move", "attack", "ready", "return", "combat", "under_attack", "death"]
const RADIO_CATEGORIES := ["infantry", "vehicle", "air"]
const ORDER_ACTIONS := ["select", "move", "attack"]
const MAX_SPEECH_VOICES := 3
const MAX_FIELD_SOUNDS := 24
const VOICE_BASELINE := .7225 # Previous default master .85 x voice .85.
const SFX_BASELINE := .765 # Previous default master .85 x effects .90.
const ENERGY_WEAPONS := ["sky_rifle", "sky_anti", "sky_scout", "sky_tank", "sky_artillery", "sky_aa", "sky_disruptor", "sky_pulse", "sky_fighter", "sky_attacker", "sky_tower", "sky_aa_tower", "sky_anti_tower", "sky_ship_frigate", "sky_ship_signature"]
const INFANTRY_ART := ["rifle", "anti", "engineer", "demolition"]
const WHEELED_ART := ["scout", "harvester", "transport", "inspection", "designation", "recycler"]
var voice_language: String = "en"
var music: PaperMusic
var mix := {"master": 1.0, "music": 1.0, "sfx": 1.0, "voice": 1.0, "commander": .6}
var commander
var radio_bank: Dictionary = {}
var preview_active := false
var attention_ids: Dictionary = {}
var attention_point := Vector2.INF
var attention_last_sound_ms := -100000
var field_recent: Dictionary = {}
var field_slots: Dictionary = {}
var system_clips: Dictionary = {}
var system_bank: Dictionary = {}
var pending_system: Dictionary = {}
var system_recent: Dictionary = {}
var _engine_attention := false
var owns_master_bus := false
var owns_music_bus := false
var players: Array[AudioStreamPlayer] = []
var ui_players: Array[AudioStreamPlayer] = []
var field_players: Array[AudioStreamPlayer] = []
var engine_players: Array[AudioStreamPlayer] = []
var bank: Dictionary = {}
var unit_definitions: Dictionary = {}
var building_definitions: Dictionary = {}
var weapon_definitions: Dictionary = {}
var speech_clips: Dictionary = {}
var speech_profile_speakers: Dictionary = {}
var speech_cache: Dictionary = {}
# Slot 0 is reserved for direct player orders; two field slots share the same
# global speech budget. Each slot plays an actual clip, never randomized captions.
var speech_player: AudioStreamPlayer
var speech_players: Array[AudioStreamPlayer] = []
var speech_slots: Dictionary = {}
var last_spoken_clip: Dictionary = {}
var speech_variants: Dictionary = {}
var last_field_speech_ms: int = -100000
var aircraft_player: AudioStreamPlayer
var speech_recent: Dictionary = {}
var last_speech_ms: int = -100000
var group_voice_queue: Array[Dictionary] = []
var last_group_voice: Dictionary = {}
var owns_voice_bus: bool = false
var aircraft_level: float = 0.0
var target_aircraft: float = 0.0
var pending_speech: Dictionary = {}
var effects_duck_db: float = 0.0
var music_duck_db: float = 0.0
var muted := false:
	set(value):
		muted = value
		if value:
			reset_field()
		_apply_mix()
var recent: Dictionary = {}
var variants: Dictionary = {}
var voice_started: Dictionary = {}
var rng := RandomNumberGenerator.new()
var camera_focus := Vector2.INF
var engine_level := 0.0
var movement_level := 0.0
var engine_scan := 0.0
var target_engine := 0.0
var target_tracks := 0.0
var owns_bus := false
var audio_type_cache:Dictionary={}
var _applied_duck_db:float=INF
var _applied_music_duck_db:float=INF

func _ready() -> void:
	rng.randomize()
	if AudioServer.get_bus_index(MASTER_BUS) < 0:
		AudioServer.add_bus()
		var master_index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(master_index, MASTER_BUS)
		AudioServer.add_bus_effect(master_index, AudioEffectLimiter.new())
		owns_master_bus = true
	if AudioServer.get_bus_index(MUSIC_BUS) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, MUSIC_BUS)
		owns_music_bus = true
	if AudioServer.get_bus_index(BUS_NAME) < 0:
		AudioServer.add_bus()
		var bus_index := AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus_index, BUS_NAME)
		AudioServer.add_bus_effect(bus_index, AudioEffectLimiter.new())
		owns_bus = true
	for event in UI_EVENTS + ["fire", "impact", "death", "death_soft", "engine_loop", "tracks_loop"]:
		bank[event] = load("res://assets/audio/%s.wav" % event)
	for event in ["fire_air", "bomb_release", "rearm", "aircraft_loop"]:
		var path: String = "res://assets/audio/%s.wav" % event
		if ResourceLoader.exists(path): bank[event] = load(path)
	if AudioServer.get_bus_index(VOICE_BUS) < 0:
		AudioServer.add_bus()
		var voice_bus: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(voice_bus, VOICE_BUS)
		AudioServer.add_bus_effect(voice_bus, AudioEffectLimiter.new())
		owns_voice_bus = true
	for name in [BUS_NAME, VOICE_BUS, MUSIC_BUS]:
		AudioServer.set_bus_send(AudioServer.get_bus_index(name), MASTER_BUS)
	AudioServer.set_bus_send(AudioServer.get_bus_index(MASTER_BUS), "Master")
	music = PaperMusic.new()
	add_child(music)
	for index in range(MAX_SPEECH_VOICES):
		var voice := _make_player()
		voice.bus = VOICE_BUS
		speech_players.append(voice)
	speech_player = speech_players[0]
	for family in VARIANT_BANKS:
		var streams: Array[AudioStream] = []
		for index in range(1, 4):
			streams.append(load("res://assets/audio/%s_%d.wav" % [family, index]))
		bank[family] = streams
	_load_sfx_manifest()
	# The defaults also support isolated audio nodes, before a match supplies its
	# saved rule set. Match configuration replaces these definitions together.
	var defaults: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/rules.json"))
	if defaults is Dictionary: _configure_definitions(defaults)
	for index in range(4):
		ui_players.append(_make_player())
	for index in range(MAX_FIELD_SOUNDS):
		field_players.append(_make_player())
	for name in ["engine_loop", "tracks_loop"]:
		var player := _make_player()
		var source: Variant = bank[name]
		var stream: AudioStreamWAV = (source[0] if source is Array else source).duplicate()
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(round(stream.get_length() * stream.mix_rate))
		player.stream = stream
		player.volume_db = -60.0
		engine_players.append(player)
	if bank.has("aircraft_loop"):
		aircraft_player = _make_player()
		var source: Variant = bank.aircraft_loop
		var stream: AudioStreamWAV = (source[0] if source is Array else source).duplicate()
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = int(round(stream.get_length() * stream.mix_rate))
		aircraft_player.stream = stream
	_load_voice_manifest()
	_load_radio_bank()
	_load_system_bank()
	commander = preload("res://scripts/commander_voice.gd").new()
	commander.audio = self
	commander.voice_language = voice_language
	add_child(commander)
	_apply_mix()
	set_scene("menu")


# Spoken language is independent of interface locale. English is the default;
# original Chinese banks remain available without a silent language fallback.
static func normalize_voice_language(language: String) -> String:
	return "en" if language.begins_with("en") else "zh_CN"

static func voice_manifest(language: String = "en") -> String:
	return ENGLISH_VOICE_MANIFEST if normalize_voice_language(language) == "en" else VOICE_MANIFEST

static func system_manifest(language: String = "en") -> String:
	return ENGLISH_SYSTEM_MANIFEST if normalize_voice_language(language) == "en" else SYSTEM_MANIFEST

static func commander_manifest(language: String = "en") -> String:
	return ENGLISH_COMMANDER_MANIFEST if normalize_voice_language(language) == "en" else "res://assets/audio/commander/manifest.json"

static func caption_text(clip: Dictionary) -> String:
	# English recordings retain their Chinese semantic source for Godot's UI
	# translator. Subtitles therefore follow interface language, not the actor.
	return str(clip.get("source_text", clip.get("text", "")))

static func voice_language_available(language: String) -> bool:
	for path: String in [voice_manifest(language), system_manifest(language), commander_manifest(language)]:
		if not FileAccess.file_exists(path): return false
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary or parsed.get("clips", []).is_empty(): return false
		for clip: Dictionary in parsed.get("clips", []):
			var file: String = str(clip.get("file", clip.get("path", "")))
			if not file.begins_with("res://"): file = path.get_base_dir().path_join(file)
			if not ResourceLoader.exists(file): return false
	return true

func set_voice_language(language: String) -> bool:
	var chosen: String = normalize_voice_language(language)
	if not voice_language_available(chosen):
		push_warning("Requested voice language assets are unavailable: " + chosen)
		return false
	if chosen == voice_language: return true
	_clear_speech_language()
	voice_language = chosen
	if is_node_ready():
		_load_voice_manifest()
		_load_radio_bank()
		_load_system_bank()
		if commander != null: commander.set_voice_language(chosen)
	voice_language_changed.emit(chosen)
	return true

func _clear_speech_language() -> void:
	for player: AudioStreamPlayer in speech_players:
		player.stop()
		player.stream = null
	pending_speech.clear()
	group_voice_queue.clear()
	pending_system.clear()
	speech_slots.clear()
	speech_recent.clear()
	speech_variants.clear()
	speech_cache.clear()
	system_recent.clear()
	last_spoken_clip.clear()
	last_group_voice.clear()
	last_speech_ms = -100000
	last_field_speech_ms = -100000
	if commander != null: commander.clear_playback()
	unit_caption.emit("", 0.0)
	effects_duck_db = 0.0
	music_duck_db = 0.0
	_apply_mix()

# Public Demo audio controls. Values are linear 0..2; zero truly mutes a bus.
# The SFX duck is applied below this preference, so speech never overwrites it.
func set_mix(values: Dictionary) -> void:
	for key in MIX_KEYS:
		if values.has(key): mix[key] = clampf(float(values[key]), 0.0, 2.0)
	if values.has("muted"): muted = bool(values.muted)
	_apply_mix()

func get_mix() -> Dictionary:
	var values := mix.duplicate()
	values["muted"] = muted
	return values

func _apply_mix() -> void:
	for entry in [[MASTER_BUS, "master"], [MUSIC_BUS, "music"], [BUS_NAME, "sfx"], [VOICE_BUS, "voice"], ["Paper Commander", "commander"]]:
		var index := AudioServer.get_bus_index(entry[0])
		if index < 0: continue
		var level := float(mix[entry[1]])
		AudioServer.set_bus_mute(index, muted or level <= 0.0)
		var duck: float = effects_duck_db if entry[1] == "sfx" else music_duck_db if entry[1] == "music" else 0.0
		AudioServer.set_bus_volume_db(index, (linear_to_db(level) if level > 0.0 else -80.0) + duck)
	_applied_duck_db = INF
	_applied_music_duck_db = INF
	if commander != null and (muted or float(mix.master) <= 0.0 or float(mix.commander) <= 0.0): commander.clear_playback()
	if speech_player != null and (muted or float(mix.master) <= 0.0 or float(mix.voice) <= 0.0):
		for player in speech_players: player.stop()
		pending_speech.clear()
		group_voice_queue.clear()
		pending_system.clear()
		speech_recent.clear()
		last_speech_ms = -100000
		last_field_speech_ms = -100000
		speech_slots.clear()
	if music != null: music.set_silent(muted or float(mix.master) <= 0.0 or float(mix.music) <= 0.0)

# Debug audition shares the actual category buses and master preference. Only
# transient field playback is suspended; battle/music state and saved mix stay.
func begin_preview() -> void:
	if preview_active: return
	preview_active = true
	if commander != null: commander.clear_playback()
	attention_last_sound_ms = -100000
	for player in players:
		if is_instance_valid(player): player.stop()
	pending_speech.clear()
	group_voice_queue.clear()
	pending_system.clear()
	engine_level = 0.0
	movement_level = 0.0
	aircraft_level = 0.0
	target_engine = 0.0
	target_tracks = 0.0
	target_aircraft = 0.0
	effects_duck_db = 0.0
	music_duck_db = 0.0
	_apply_mix()

func end_preview() -> void:
	preview_active = false

func set_scene(value: String) -> void:
	if music != null: music.set_scene(value)

func set_map(value: String) -> void:
	if music != null: music.set_map(value)

func reset_field(clear_caption: bool = true) -> void:
	if commander != null: commander.clear_playback()
	if music != null: music.reset_combat()
	for player in players:
		if is_instance_valid(player): player.stop()
	pending_speech.clear()
	group_voice_queue.clear()
	speech_recent.clear()
	last_speech_ms = -100000
	last_field_speech_ms = -100000
	speech_slots.clear()
	last_spoken_clip.clear()
	recent.clear()
	field_recent.clear()
	field_slots.clear()
	system_recent.clear()
	pending_system.clear()
	attention_last_sound_ms = -100000
	engine_level = 0.0
	movement_level = 0.0
	aircraft_level = 0.0
	target_engine = 0.0
	target_tracks = 0.0
	target_aircraft = 0.0
	engine_scan = 0.0
	if clear_caption: unit_caption.emit("", 0.0)

func _load_radio_bank() -> void:
	radio_bank.clear()
	for group: String in speech_clips:
		for clip: Dictionary in speech_clips[group]:
			var path: String = str(clip.get("file", clip.get("path", "")))
			if not path.begins_with("res://"): path = voice_manifest(voice_language).get_base_dir().path_join(path)
			if ResourceLoader.exists(path): radio_bank[str(clip.key)] = load(path)

func _load_system_bank() -> void:
	system_clips.clear(); system_bank.clear()
	var manifest_path: String = system_manifest(voice_language)
	if not FileAccess.file_exists(manifest_path): return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not manifest is Dictionary: return
	for raw: Dictionary in manifest.get("clips", []):
		var action: String = str(raw.get("action", ""))
		var file: String = str(raw.get("file", ""))
		if action not in ["low_power", "power_restored"] or not ResourceLoader.exists(file): continue
		var clip: Dictionary = raw.duplicate()
		clip["key"] = str(clip.get("key", "system/" + action + "/1"))
		system_clips[action] = clip
		system_bank[str(clip.key)] = load(file)

# One pure gain table keeps the applied field mix and browser audition aligned.
static func catalog_gain(row: Dictionary) -> float:
	var type: String = str(row.get("type", "sfx"))
	return _catalog_intrinsic_gain(row) + (20.0 * log(VOICE_BASELINE) / log(10.0) if type in ["voice", "system"] else PaperMusic.BASELINE_DB if type == "music" else 20.0 * log(SFX_BASELINE) / log(10.0))

static func _catalog_intrinsic_gain(row: Dictionary) -> float:
	var type: String = str(row.get("type", "sfx"))
	var action: String = str(row.get("action", row.get("family", row.get("kind", ""))))
	if type == "music": return 0.0
	if type in ["voice", "system"]: return -7.0 if action in ORDER_ACTIONS or type == "system" or str(row.get("category", "")) == "system" else -10.0
	if action in ["death_building", "death_vehicle", "sell"]: return -6.0
	if action == "deploy_building": return -7.0
	if action == "construct_building": return -8.0
	if action == "impact_large": return -7.0
	if action == "select_power": return -11.0
	if action in ["select", "command", "ui_click", "ui_key", "queue_build", "queue_unit", "error", "low_power"]: return -16.0
	if action == "result": return -12.0
	if action in ["produce", "delivery"]: return -16.0
	if action == "engine_loop": return -24.0
	if action == "tracks_loop": return -27.0
	if action == "aircraft_loop": return -28.0
	return -9.0

func set_attention(ids: Array, point: Vector2) -> void:
	var next: Dictionary = {}
	for id: Variant in ids: next[int(id)] = true
	if next != attention_ids or (next.is_empty() and point.is_finite() and attention_point.is_finite() and point.distance_squared_to(attention_point)>16.0):
		attention_last_sound_ms = -100000
	attention_ids = next
	attention_point = point if point.is_finite() else Vector2.INF

func _is_attention(event: Dictionary) -> bool:
	if not attention_ids.is_empty():
		for key: String in ["id", "source_id", "target"]:
			if attention_ids.has(int(event.get(key, -1))): return true
		return false
	return attention_point != Vector2.INF and event.has("pos") and (event.pos as Vector2).distance_squared_to(attention_point) <= 8.0 * 8.0

func _attention_audible() -> bool:
	return Time.get_ticks_msec() - attention_last_sound_ms < 500

func _field_cooldown_key(event: Dictionary, family: String, focused: bool) -> String:
	var id: int = int(event.get("id", event.get("source_id", -1)))
	var location: Vector2 = event.get("pos", Vector2.ZERO)
	return family + ("/focus/" if focused else "/field/") + (str(id) if id >= 0 else "%d,%d" % [floori(location.x / 6.0), floori(location.y / 6.0)])

func _load_sfx_manifest() -> void:
	if not FileAccess.file_exists(SFX_MANIFEST): return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(SFX_MANIFEST))
	if not manifest is Dictionary: return
	var fresh: Dictionary = {}
	for clip: Dictionary in manifest.get("clips", manifest.get("effects", [])):
		var family: String = str(clip.get("family", ""))
		var path: String = str(clip.get("file", clip.get("path", "")))
		if family.is_empty() or path.is_empty(): continue
		if not path.begins_with("res://"): path = SFX_MANIFEST.get_base_dir().path_join(path)
		if not ResourceLoader.exists(path): continue
		if not fresh.has(family): fresh[family] = []
		fresh[family].append(load(path))
	for family: String in fresh:
		bank[family] = fresh[family]
	# Compatibility names are genuine aliases of the newly authored source bank.
	for pair: Array in [["build", "deploy_building"], ["death", "death_vehicle"], ["death_soft", "death_infantry"]]:
		if fresh.has(pair[1]): bank[pair[0]] = fresh[pair[1]]

func _make_player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = BUS_NAME
	add_child(player)
	players.append(player)
	return player

func play(kind: String) -> void:
	play_event({"kind": kind})

func play_event(event: Dictionary) -> void:
	if preview_active: return
	var kind: String = str(event.get("kind", ""))
	if kind=="command" and event.has("team") and int(event.team)!=0:return
	_dispatch_event_voice(event)
	if muted: return
	var family: String = _event_family(event)
	if not bank.has(family): return
	var now: int = Time.get_ticks_msec()
	var field: bool = kind in ["fire", "impact", "death", "ruin_destroy", "deploy", "construct", "sell"] or (kind == "build" and event.has("pos"))
	var focused: bool = field and _is_attention(event)
	var cooldown: int = 60 if focused else 105 if family in ["fire_rifle", "fire_machine_gun"] else 140 if kind == "death" else 1800 if kind in ["low_power", "result"] else 95 if family == "command" else 75
	var key: String = _field_cooldown_key(event, family, focused) if field else family
	var times: Dictionary = field_recent if field else recent
	if now - int(times.get(key,-100000)) < cooldown: return
	var distance_gain := 0.0
	if field and event.has("pos") and camera_focus != Vector2.INF:
		var distance: float = (event.pos as Vector2).distance_to(camera_focus)
		if distance > 70.0 and not focused: return
		distance_gain = -minf(10.0 if focused else 19.0, maxf(0.0, distance - 12.0) * .36)
	var heavy: bool = kind in ["death", "ruin_destroy", "deploy", "construct", "sell", "build"] or family == "impact_large"
	# Twenty regular field layers, one reserved focus layer and three protected
	# heavy tails. This budget is completely independent of speech's three slots.
	var pool: Array[AudioStreamPlayer] = ui_players
	if field:
		pool = field_players.slice(0, 20)
		if focused: pool.push_front(field_players[20])
		if heavy: pool.append_array(field_players.slice(21, 24))
	var player: AudioStreamPlayer
	for candidate: AudioStreamPlayer in pool:
		if not candidate.playing: player = candidate; break
	if player == null:
		if field: return
		player = pool[0]
		for candidate: AudioStreamPlayer in pool:
			if int(voice_started.get(candidate,0)) < int(voice_started.get(player,0)): player = candidate
		player.stop()
	var entry: Variant = bank[family]
	if entry is Array:
		if entry.is_empty(): return
		var index: int = _variant_index(entry.size(), int(variants.get(family,-1)))
		variants[family] = index; player.stream = entry[index]
	else: player.stream = entry
	times[key] = now; recent[family] = now
	if field_recent.size() > 512:
		for cached: Variant in field_recent.keys():
			if now - int(field_recent[cached]) > 2000: field_recent.erase(cached)
	var gain: float = catalog_gain({"type":"sfx","action":family}) + distance_gain
	player.volume_db = gain + (3.0 if focused else -4.0 if field and _attention_audible() else 0.0)
	player.pitch_scale = rng.randf_range(.98,1.02) if field else 1.0
	voice_started[player] = now
	if field:
		field_slots[player] = {"event":event.duplicate(),"gain":gain,"family":family}
		if focused and float(mix.sfx) > 0.0 and float(mix.master) > 0.0: attention_last_sound_ms = now
	player.play()

func _event_family(event: Dictionary) -> String:
	var kind := str(event.get("kind", ""))
	var weapon_id: String = str(event.get("weapon", ""))
	if kind in ["fire", "impact"] and weapon_id == "sky_creator_hand":
		return "creator_hand_attack" if kind == "fire" else "creator_hand_impact"
	if kind in ["fire", "impact"] and _energy_weapon(weapon_id):
		return "fire_energy" if kind == "fire" else "impact_energy"
	if kind in ["ui_click", "ui_key"]: return _available_family(kind,"command")
	if kind in ["queue_build", "queue_unit"]: return _available_family("ui_click","command")
	if kind == "select_building": return _available_family("select_power", "select")
	if kind == "power_restored": return ""
	if kind == "ruin_destroy": return _available_family("death_building", "impact_large")
	if kind in ["rearm", "return"]: return "rearm"
	if kind == "build" and str(event.get("construction_method", "")) == "scaffold": return _available_family("construct_building", "build")
	if kind in ["build", "deploy"]: return _available_family("deploy_building", "build")
	if kind == "construct": return _available_family("construct_building", "build")
	if kind == "fire":
		var weapon := str(event.get("weapon", ""))
		var source: String = str(event.get("spec", weapon))
		var info: Dictionary = _definition(source)
		var art: String = str(info.get("art", weapon.trim_prefix(weapon.get_slice("_", 0) + "_")))
		var projectile: Dictionary = weapon_definitions.get(weapon, {})
		var domain: String = str(info.get("domain", event.get("domain", "ground")))
		if domain == "air": return "fire_air" if art == "fighter" else "bomb_release"
		if art in ["fighter", "bomber", "attacker"]: return "fire_air" if art == "fighter" else "bomb_release"
		if art in ["aa", "anti", "aa_tower", "anti_tower"]: return "fire_anti"
		if art == "rifle": return "fire_rifle"
		if str(projectile.get("kind", "")) == "instant" or art == "scout" or weapon == "kestrel_tower":
			return _available_family("fire_machine_gun", "fire_rifle")
		if art in ["artillery", "assault", "demolition", "pulse", "naval_signature"]: return "fire_artillery"
		return "fire_cannon"
	if kind == "impact":
		var blast := float(event.get("blast", 1.0))
		if blast < 0.65: return "impact_small"
		if blast >= 1.6: return "impact_large"
		return "impact_medium"
	if kind == "death":
		if not bool(event.get("destroyed", true)): return ""
		var spec := str(event.get("spec", ""))
		if building_definitions.has(spec) or str(event.get("entity_kind", "")) == "building":
			return _available_family("death_building", "death")
		if voice_category(spec) == "infantry": return _available_family("death_infantry", "death_soft")
		return _available_family("death_vehicle", "death")
	return kind

func _energy_weapon(weapon: String) -> bool:
	var definition: Dictionary = weapon_definitions.get(weapon, {})
	return bool(definition.get("energy", false)) or str(definition.get("damage_type", "")) == "energy" or str(definition.get("visual_effect", "")) == "energy" or weapon in ENERGY_WEAPONS

func _available_family(preferred: String, fallback: String) -> String:
	return preferred if bank.has(preferred) else fallback

func _definition(spec: String) -> Dictionary:
	return unit_definitions.get(spec, building_definitions.get(spec, {}))

# Domain and authored movement/art metadata classify the complete roster,
# including support vehicles, transports and units whose identifiers change.
func voice_category(spec: String) -> String:
	var info: Dictionary = _definition(spec)
	var explicit: String = str(info.get("voice_category", ""))
	if explicit in RADIO_CATEGORIES: return explicit
	if str(info.get("domain", "ground")) == "air": return "air"
	var art: String = str(info.get("art", spec.trim_prefix(spec.get_slice("_", 0) + "_")))
	var movement: String = str(info.get("movement_type", info.get("movement", "")))
	if bool(info.get("infantry", false)) or art in INFANTRY_ART or movement in ["foot", "infantry", "walking"]: return "infantry"
	if movement.is_empty() and info.has("radius") and float(info.radius) <= 0.45: return "infantry"
	return "vehicle"

func _dispatch_event_voice(event: Dictionary) -> void:
	if str(event.get("kind", "")) in ["low_power", "power_restored"]:
		play_system_voice(str(event.kind),int(event.get("team",0)));return
	if int(event.get("team", -1)) != 0 or not bool(event.get("destroyed", true)): return
	var spec: String = str(event.get("spec", event.get("weapon", "")))
	if not unit_definitions.has(spec) or str(event.get("entity_kind", "unit")) == "building": return
	if not _is_attention(event) and camera_focus != Vector2.INF and event.has("pos") and (event.pos as Vector2).distance_squared_to(camera_focus) > 48.0 * 48.0: return
	var action: String = ""
	match str(event.get("kind", "")):
		"fire": action = "combat"
		"under_attack", "hit": action = "under_attack"
		"death": action = "death"
	if not action.is_empty(): play_unit_voice(spec, action, event)

func _variant_index(count: int, previous: int) -> int:
	if count <= 1: return 0
	var index: int = rng.randi_range(0, count - 2) if previous >= 0 and previous < count else rng.randi_range(0, count - 1)
	if previous >= 0 and previous < count and index >= previous: index += 1
	return index

# Called with camera ground coordinates. Two aggregated beds only consider nearby
# moving vehicles on every audible side: aggregated beds never consume speech.
func update_battlefield(delta: float, entities: Dictionary, focus: Vector2) -> void:
	camera_focus = focus
	if preview_active: return
	if engine_players.size() != 2:
		return
	if muted:
		for player in engine_players:
			if player.playing:player.stop()
		engine_level = 0.0
		movement_level = 0.0
		aircraft_level = 0.0
		if aircraft_player != null and aircraft_player.playing: aircraft_player.stop()
		return
	engine_scan -= delta
	if engine_scan <= 0.0:
		engine_scan = 0.16
		var nearby := 0.0
		var heavy := 0.0
		var aircraft: float = 0.0
		_engine_attention = false
		for id in entities:
			var entity:Dictionary=entities[id]
			if int(entity.get("team", -1)) < 0 or float(entity.get("hp", 0.0)) <= 0.0 or float(entity.get("motion", 0.0)) <= 0.0001:
				continue
			var spec := str(entity.get("spec", ""))
			var audio_type:int=_audio_type(spec)
			if audio_type<0:continue
			var distance_squared:float=(entity.pos as Vector2).distance_squared_to(focus)
			if distance_squared>=48.0*48.0:continue
			if _is_attention({"id":id,"pos":entity.pos}): _engine_attention = true
			var distance:float=sqrt(distance_squared)
			var weight:float=clampf(1.0-maxf(0.0,distance-12.0)/36.0,0.0,1.0)
			if audio_type==2:
				if float(entity.get("flight_height", 0.0)) > 0.5:
					aircraft+=weight
				continue
			nearby += weight
			heavy += weight if audio_type == 0 else 0.0
		target_engine = minf(1.0, log(1.0 + nearby) / log(5.0))
		target_tracks = minf(1.0, log(1.0 + heavy) / log(5.0))
		target_aircraft = minf(1.0, log(1.0 + aircraft) / log(4.0))
	if _engine_attention and maxf(target_engine,target_aircraft) > .008 and float(mix.sfx) > 0.0: attention_last_sound_ms=Time.get_ticks_msec()
	var blend := 1.0 - exp(-delta * 5.0)
	engine_level = lerpf(engine_level, target_engine, blend)
	movement_level = lerpf(movement_level, target_tracks, blend)
	aircraft_level = lerpf(aircraft_level, target_aircraft, blend)
	if aircraft_player != null:
		if aircraft_level < 0.008:
			if aircraft_player.playing:aircraft_player.stop()
		else:
			aircraft_player.volume_db = catalog_gain({"action":"aircraft_loop"}) + linear_to_db(aircraft_level) + (2.0 if _engine_attention else 0.0)
			if not aircraft_player.playing: aircraft_player.play()
	for index in range(2):
		var level := engine_level if index == 0 else movement_level
		var player := engine_players[index]
		if level < 0.008:
			if player.playing:player.stop()
			continue
		player.volume_db = catalog_gain({"action":"engine_loop" if index == 0 else "tracks_loop"}) + linear_to_db(level) + (2.0 if _engine_attention else 0.0)
		player.pitch_scale = 0.96 + engine_level * 0.08
		if not player.playing: player.play()

func _audio_type(spec: String) -> int:
	if not audio_type_cache.has(spec):
		var info: Dictionary = _definition(spec)
		var kind: int = -1
		if not building_definitions.has(spec) and voice_category(spec) != "infantry":
			var domain: String = str(info.get("domain", "ground"))
			var art: String = str(info.get("art", spec.trim_prefix(spec.get_slice("_", 0) + "_")))
			var movement: String = str(info.get("movement_type", info.get("movement", "")))
			if domain == "air": kind = 2
			elif art != "creator_hand": kind = 1 if domain == "naval" or art in WHEELED_ART or movement in ["wheel", "wheeled", "hover"] else 0
		audio_type_cache[spec] = kind
	return int(audio_type_cache[spec])

func stop_all() -> void:
	if commander != null: commander.clear_playback()
	group_voice_queue.clear()
	muted = true
	if music != null: music.stop_all()
	for player in players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null

func _exit_tree() -> void:
	stop_all()
	bank.clear()
	speech_cache.clear()
	radio_bank.clear()
	system_bank.clear()
	if owns_voice_bus:
		var index: int = AudioServer.get_bus_index(VOICE_BUS)
		if index >= 0: AudioServer.remove_bus(index)
	if owns_bus:
		var index := AudioServer.get_bus_index(BUS_NAME)
		if index >= 0: AudioServer.remove_bus(index)
	if owns_music_bus:
		var index := AudioServer.get_bus_index(MUSIC_BUS)
		if index >= 0: AudioServer.remove_bus(index)
	if owns_master_bus:
		var index := AudioServer.get_bus_index(MASTER_BUS)
		if index >= 0: AudioServer.remove_bus(index)


func configure_units(rules: Dictionary) -> void:
	reset_field()
	_configure_definitions(rules)
	_load_voice_manifest()
	_load_radio_bank()
	_load_system_bank()

func _configure_definitions(rules: Dictionary) -> void:
	unit_definitions = rules.get("units", {})
	building_definitions = rules.get("buildings", {})
	weapon_definitions = rules.get("weapons", {})
	audio_type_cache.clear()

func _load_voice_manifest() -> void:
	speech_clips.clear()
	speech_profile_speakers.clear()
	var manifest_path: String = voice_manifest(voice_language)
	if not FileAccess.file_exists(manifest_path):
		push_warning("Faction/class speech manifest is missing: " + manifest_path)
		return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not manifest is Dictionary:
		push_warning("Faction/class speech manifest is invalid: " + manifest_path)
		return
	for profile: String in manifest.get("profiles", {}):
		var settings: Dictionary = manifest.profiles[profile]
		var speaker: String = str(settings.get("speaker_id", settings.get("voice", "")))
		if not speaker.is_empty(): speech_profile_speakers[profile] = speaker
	for raw_clip: Dictionary in manifest.get("clips", []):
		var category: String = str(raw_clip.get("category", ""))
		if category not in RADIO_CATEGORIES: continue
		var profile: String = str(raw_clip.get("faction", "")) + "/" + category
		var speaker: String = str(raw_clip.get("speaker_id", raw_clip.get("voice", "")))
		if not speaker.is_empty():
			if speech_profile_speakers.has(profile) and str(speech_profile_speakers[profile]) != speaker:
				push_warning("Speech clip has a different speaker from its faction/class profile: " + str(raw_clip.get("file", "")))
				continue
			speech_profile_speakers[profile] = speaker
		var clip: Dictionary = raw_clip.duplicate()
		var group: String = str(clip.get("faction", "")) + "/" + category + "/" + str(clip.get("action", ""))
		if not speech_clips.has(group): speech_clips[group] = []
		clip["key"] = group + "/" + str(int(clip.get("variant", speech_clips[group].size() + 1)))
		speech_clips[group].append(clip)

func speech_profile_key(spec: String) -> String:
	var definitions: Dictionary = _definition(spec)
	return str(definitions.get("faction", spec.get_slice("_", 0))) + "/" + voice_category(spec)

func speech_key(spec: String, action_id: String) -> String:
	return speech_profile_key(spec) + "/" + action_id

func active_speech_count() -> int:
	var count: int = 0
	for player in speech_players:
		if player.playing: count += 1
	return count

func _speech_reserved(player: AudioStreamPlayer) -> bool:
	for item: Dictionary in group_voice_queue:
		if item.player == player: return true
	return false

func play_unit_group_voice(spec: String, action_id: String, contexts: Array) -> bool:
	if preview_active or action_id not in ORDER_ACTIONS: return false
	var valid: Array[Dictionary] = []
	for context: Dictionary in contexts:
		if int(context.get("team", 0)) == 0 and bool(context.get("destroyed", true)): valid.append(context)
	if valid.is_empty(): return false
	var accepted: bool = play_unit_voice(spec, action_id, valid[0])
	if not accepted:
		if not pending_speech.is_empty() and str(pending_speech.get("spec", "")) == spec and str(pending_speech.get("action", "")) == action_id:
			pending_speech["group_contexts"] = valid.duplicate(true)
		return false
	# A newly accepted player order owns the three speech layers. The reserved
	# player-order slot is never interrupted while busy; its pending group waits.
	group_voice_queue.clear()
	for index in range(1, speech_players.size()):
		speech_players[index].stop()
		speech_slots.erase(speech_players[index])
	last_group_voice = {"clip": last_spoken_clip.duplicate(), "copies": 1, "delays_ms": [0]}
	if muted or float(mix.master) <= 0.0 or float(mix.voice) <= 0.0 or not speech_player.playing: return true
	var now: int = Time.get_ticks_msec()
	var copies := 1
	for index in range(1, speech_players.size()):
		if copies >= mini(3, valid.size()): break
		var player: AudioStreamPlayer = speech_players[index]
		if player.playing or _speech_reserved(player): continue
		var delay: int = copies * 50
		group_voice_queue.append({"player": player, "start_ms": now + delay, "stream": speech_player.stream,
			"clip": last_spoken_clip.duplicate(), "spec": spec, "action": action_id, "context": valid[copies].duplicate(),
			"gain": catalog_gain({"type":"voice","action":action_id}) - 3.0})
		copies += 1
		(last_group_voice.delays_ms as Array).append(delay)
	last_group_voice.copies = copies
	return true

# Groups share authored phrases, while the selected unit keeps its own caption.
# Player orders retain a reserved slot; battle reports use at most two others.
# Excess combat calls are discarded instead of forming a stale speech queue.
func play_unit_voice(spec: String, action_id: String, context: Dictionary = {}) -> bool:
	if preview_active or speech_player == null or not unit_definitions.has(spec): return false
	var definitions: Dictionary = unit_definitions[spec]
	var group: String = speech_key(spec, action_id)
	var choices: Array = speech_clips.get(group, [])
	if choices.is_empty(): return false
	var order: bool = action_id in ORDER_ACTIONS
	if not order and not context.is_empty():
		if int(context.get("team", 0)) != 0 or not bool(context.get("destroyed", true)): return false
		if not _is_attention(context) and camera_focus != Vector2.INF and context.has("pos") and (context.pos as Vector2).distance_squared_to(camera_focus) > 48.0 * 48.0: return false
	var audible: bool = not muted and float(mix.master) > 0.0 and float(mix.voice) > 0.0
	if not order and not audible: return false
	var now: int = Time.get_ticks_msec()
	var focused: bool = _is_attention(context)
	var cooldown_key: String = group + ("/focus/" + str(context.get("id",0)) if focused else "")
	var cooldown: int = 1800 if order else 6500 if action_id == "combat" else 5000 if action_id == "under_attack" else 2800
	if audible and now - int(speech_recent.get(cooldown_key, -100000)) < cooldown: return false
	var player: AudioStreamPlayer = speech_player if order else null
	if audible:
		if order and speech_player.playing:
			pending_speech = {"spec": spec, "action": action_id, "queued_ms": now, "context":context.duplicate()}
			return false
		if now - last_speech_ms < (320 if order else 600 if focused else 1000):
			if action_id in ["ready", "return"] and (pending_speech.is_empty() or str(pending_speech.get("action", "")) not in ORDER_ACTIONS):
				pending_speech = {"spec": spec, "action": action_id, "queued_ms": now, "context":context.duplicate()}
			return false
		if not order:
			if now - last_field_speech_ms < (800 if focused else 1400): return false
			for index in range(1, MAX_SPEECH_VOICES):
				if not speech_players[index].playing and not _speech_reserved(speech_players[index]):
					player = speech_players[index]
					break
			if player == null: return false
	var text: String = ""
	var clip: Dictionary = {}
	var stream: AudioStream = null
	var duration: float = 0.0
	if not choices.is_empty():
		var index: int = _variant_index(choices.size(), int(speech_variants.get(group, -1)))
		clip = choices[index]
		stream = radio_bank.get(str(clip.key))
		text = caption_text(clip)
		duration = float(clip.get("duration_s", 0.0))
		if audible and stream == null: return false
		speech_variants[group] = index
	last_spoken_clip = clip.duplicate()
	if audible and stream != null:
		player.stream = stream
		player.volume_db = catalog_gain({"type":"voice","action":action_id}) + (2.0 if focused and not order else 0.0)
		player.pitch_scale = 1.0
		player.play()
		speech_slots[player] = {"group": group, "action": action_id, "started_ms": now, "spec": spec, "clip": clip, "context":context.duplicate(),"gain":catalog_gain({"type":"voice","action":action_id})}
		speech_recent[cooldown_key] = now
		last_speech_ms = now
		if not order: last_field_speech_ms = now
		if focused: attention_last_sound_ms=now
	# An incidental battle report cannot overwrite the player's order subtitle.
	if order or not speech_player.playing:
		unit_caption.emit("%s：%s" % [str(definitions.get("name", spec)), text], maxf(duration + .25, clampf(1.8 + text.length() * .10, 2.3, 5.5)))
	return true


func play_system_voice(action: String, team: int = 0) -> bool:
	if preview_active or team != 0 or not system_clips.has(action): return false
	var now: int = Time.get_ticks_msec()
	if now - int(system_recent.get(action,-100000)) < 4000: return false
	var clip: Dictionary = system_clips[action]
	unit_caption.emit("系统：" + caption_text(clip), maxf(2.5,float(clip.duration_s)+.25))
	var audible: bool = not muted and float(mix.master)>0.0 and float(mix.voice)>0.0
	if not audible: system_recent[action]=now;return true
	if speech_player.playing:
		pending_system={"action":action,"queued_ms":now};return false
	speech_player.stream=system_bank.get(str(clip.key))
	if speech_player.stream==null:return false
	speech_player.volume_db=catalog_gain({"type":"system","action":action});speech_player.pitch_scale=1.0
	speech_player.play()
	system_recent[action]=now;last_speech_ms=now
	last_spoken_clip=clip.duplicate()
	speech_slots[speech_player]={"group":"system/"+action,"action":action,"started_ms":now,"spec":"system","clip":clip,"context":{},"gain":speech_player.volume_db}
	return true

func _process(delta: float) -> void:
	if preview_active: return
	var now: int = Time.get_ticks_msec()
	# Ordered deadlines plus seek offsets preserve the fifty-millisecond phase
	# difference even when a slow frame dispatches both deferred starts together.
	while not group_voice_queue.is_empty() and now >= int(group_voice_queue[0].start_ms):
		var item: Dictionary = group_voice_queue.pop_front()
		if muted or float(mix.master) <= 0.0 or float(mix.voice) <= 0.0: continue
		var player: AudioStreamPlayer = item.player
		if not is_instance_valid(player) or player.playing: continue
		player.stream = item.stream; player.pitch_scale = 1.0; player.volume_db = float(item.gain)
		var offset: float = maxf(0.0, float(now - int(item.start_ms)) / 1000.0)
		if offset >= player.stream.get_length(): continue
		player.play(offset)
		speech_slots[player] = {"group": speech_key(str(item.spec),str(item.action)),"action":item.action,
			"started_ms":int(item.start_ms),"spec":item.spec,"clip":item.clip,"context":item.context,"gain":item.gain,"group_copy":true}
	for player: AudioStreamPlayer in field_slots:
		if player.playing and _is_attention(field_slots[player].event) and float(mix.sfx)>0.0: attention_last_sound_ms=now
	for player: AudioStreamPlayer in speech_slots:
		if player.playing and _is_attention(speech_slots[player].get("context",{})) and float(mix.voice)>0.0: attention_last_sound_ms=now
	for player: AudioStreamPlayer in field_slots:
		if not player.playing: continue
		var slot: Dictionary=field_slots[player]
		var gain: float=float(slot.gain)+(3.0 if _is_attention(slot.event) else -4.0 if _attention_audible() else 0.0)
		player.volume_db=lerpf(player.volume_db,gain,1.0-exp(-delta*14.0))
	for index in range(1,speech_players.size()):
		var voice:AudioStreamPlayer=speech_players[index]
		if not voice.playing:continue
		var slot:Dictionary=speech_slots.get(voice,{})
		var focused:bool=_is_attention(slot.get("context",{}))
		var gain:float=float(slot.get("gain",-10.0)) if bool(slot.get("group_copy",false)) else float(slot.get("gain",-10.0))+(2.0 if focused else 0.0)-(3.0 if speech_player.playing or (_attention_audible() and not focused) else 0.0)
		voice.volume_db=lerpf(voice.volume_db,gain,1.0-exp(-delta*12.0))
	var speaking: bool = active_speech_count() > 0 and not muted and float(mix.master) > 0.0 and float(mix.voice) > 0.0
	# Briefly lower battle effects so a nearby firefight does not hide words.
	effects_duck_db = lerpf(effects_duck_db, -1.0 if speaking else 0.0, 1.0 - exp(-delta * 10.0))
	music_duck_db = lerpf(music_duck_db, -3.5 if speaking else 0.0, 1.0 - exp(-delta * 6.0))
	if absf(music_duck_db - (-3.5 if speaking else 0.0)) < .01: music_duck_db = -3.5 if speaking else 0.0
	if absf(effects_duck_db-(-1.0 if speaking else 0.0))<.01:effects_duck_db=-1.0 if speaking else 0.0
	if effects_duck_db!=_applied_duck_db:
		var effects_bus:int=AudioServer.get_bus_index(BUS_NAME)
		var effects_level: float = float(mix.sfx)
		if effects_bus>=0:AudioServer.set_bus_volume_db(effects_bus,(linear_to_db(effects_level) if effects_level > 0.0 else -80.0)+effects_duck_db)
		_applied_duck_db=effects_duck_db
	if music_duck_db != _applied_music_duck_db:
		var music_bus: int = AudioServer.get_bus_index(MUSIC_BUS)
		var music_level: float = float(mix.music)
		if music_bus >= 0: AudioServer.set_bus_volume_db(music_bus, (linear_to_db(music_level) if music_level > 0.0 else -80.0) + music_duck_db)
		_applied_music_duck_db = music_duck_db
	if not speech_player.playing and not pending_system.is_empty():
		var alert:Dictionary=pending_system.duplicate();pending_system.clear()
		if Time.get_ticks_msec()-int(alert.get("queued_ms",0))<=5000:play_system_voice(str(alert.action))
	if not speech_player.playing and not pending_speech.is_empty() and Time.get_ticks_msec() - last_speech_ms >= 320:
		var pending: Dictionary = pending_speech.duplicate()
		pending_speech.clear()
		if Time.get_ticks_msec() - int(pending.get("queued_ms", 0)) <= (5000 if str(pending.action) in ORDER_ACTIONS else 2200):
			if pending.has("group_contexts"):
				play_unit_group_voice(str(pending.spec), str(pending.action), pending.group_contexts)
			else:
				play_unit_voice(str(pending.spec), str(pending.action), pending.get("context",{}))
