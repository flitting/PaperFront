extends Node
class_name PaperAudio

signal unit_caption(text: String, duration: float)

# Separate UI/field voices keep crowded combat from swallowing an order click.
# Original PCM assets have >2 dB headroom; the dedicated SFX bus also limits peaks.
const UI_EVENTS := ["select", "command", "produce", "delivery", "build", "sell", "low_power", "result", "error"]
const VARIANT_BANKS := ["fire_rifle", "fire_anti", "fire_cannon", "fire_artillery", "impact_small", "impact_medium", "impact_large", "death"]
const BUS_NAME := "Paper SFX"
const VOICE_BUS := "Paper Voice"
const MASTER_BUS := "Paper Master"
const MUSIC_BUS := "Paper Music"
const MIX_KEYS := ["master", "music", "sfx", "voice"]
const VOICE_MANIFEST := "res://assets/audio/radio/manifest.json"
const RADIO_ACTIONS := ["select", "move", "attack", "ready", "return"]
var music: PaperMusic
var mix := {"master": 0.85, "music": 0.45, "sfx": 0.90, "voice": 0.85}
var radio_bank: Dictionary = {}
var owns_master_bus := false
var owns_music_bus := false
var players: Array[AudioStreamPlayer] = []
var ui_players: Array[AudioStreamPlayer] = []
var field_players: Array[AudioStreamPlayer] = []
var engine_players: Array[AudioStreamPlayer] = []
var bank: Dictionary = {}
var unit_definitions: Dictionary = {}
var speech_clips: Dictionary = {}
var speech_cache: Dictionary = {}
var speech_player: AudioStreamPlayer
var aircraft_player: AudioStreamPlayer
var speech_recent: Dictionary = {}
var last_speech_ms: int = -100000
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
	speech_player = _make_player()
	speech_player.bus = VOICE_BUS
	for family in VARIANT_BANKS:
		var streams: Array[AudioStream] = []
		for index in range(1, 4):
			streams.append(load("res://assets/audio/%s_%d.wav" % [family, index]))
		bank[family] = streams
	for index in range(4):
		ui_players.append(_make_player())
	for index in range(8):
		field_players.append(_make_player())
	for name in ["engine_loop", "tracks_loop"]:
		var player := _make_player()
		var stream: AudioStreamWAV = bank[name].duplicate()
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(round(stream.get_length() * stream.mix_rate))
		player.stream = stream
		player.volume_db = -60.0
		engine_players.append(player)
	if bank.has("aircraft_loop"):
		aircraft_player = _make_player()
		var stream: AudioStreamWAV = bank.aircraft_loop.duplicate()
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = int(round(stream.get_length() * stream.mix_rate))
		aircraft_player.stream = stream
	_load_voice_manifest()
	_load_radio_bank()
	_apply_mix()
	set_scene("menu")

# Public Demo audio controls. Values are linear 0..1; zero truly mutes a bus.
# The SFX duck is applied below this preference, so speech never overwrites it.
func set_mix(values: Dictionary) -> void:
	for key in MIX_KEYS:
		if values.has(key): mix[key] = clampf(float(values[key]), 0.0, 1.0)
	if values.has("muted"): muted = bool(values.muted)
	_apply_mix()

func get_mix() -> Dictionary:
	var values := mix.duplicate()
	values["muted"] = muted
	return values

func _apply_mix() -> void:
	for entry in [[MASTER_BUS, "master"], [MUSIC_BUS, "music"], [BUS_NAME, "sfx"], [VOICE_BUS, "voice"]]:
		var index := AudioServer.get_bus_index(entry[0])
		if index < 0: continue
		var level := float(mix[entry[1]])
		AudioServer.set_bus_mute(index, muted or level <= 0.0)
		var duck: float = effects_duck_db if entry[1] == "sfx" else music_duck_db if entry[1] == "music" else 0.0
		AudioServer.set_bus_volume_db(index, (linear_to_db(level) if level > 0.0 else -80.0) + duck)
	_applied_duck_db = INF
	_applied_music_duck_db = INF
	if speech_player != null and (muted or float(mix.master) <= 0.0 or float(mix.voice) <= 0.0):
		speech_player.stop()
		pending_speech.clear()
		speech_recent.clear()
		last_speech_ms = -100000
	if music != null: music.set_silent(muted or float(mix.master) <= 0.0 or float(mix.music) <= 0.0)

func set_scene(value: String) -> void:
	if music != null: music.set_scene(value)

func set_map(value: String) -> void:
	if music != null: music.set_map(value)

func reset_field(clear_caption: bool = true) -> void:
	for player in players:
		if is_instance_valid(player): player.stop()
	pending_speech.clear()
	speech_recent.clear()
	last_speech_ms = -100000
	recent.clear()
	engine_level = 0.0
	movement_level = 0.0
	aircraft_level = 0.0
	target_engine = 0.0
	target_tracks = 0.0
	target_aircraft = 0.0
	engine_scan = 0.0
	if clear_caption: unit_caption.emit("", 0.0)

func _load_radio_bank() -> void:
	for faction in ["kestrel", "rivet", "iron", "sky"]:
		for action_id in RADIO_ACTIONS:
			var key: String = faction + "/" + action_id
			var path: String = "res://assets/audio/radio/%s_%s.wav" % [faction, action_id]
			if ResourceLoader.exists(path): radio_bank[key] = load(path)

func _make_player() -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = BUS_NAME
	add_child(player)
	players.append(player)
	return player

func play(kind: String) -> void:
	play_event({"kind": kind})

func play_event(event: Dictionary) -> void:
	if muted:
		return
	var kind := str(event.get("kind", ""))
	var family := _event_family(event)
	if not bank.has(family):
		return
	var now := Time.get_ticks_msec()
	var cooldown := 75
	if family == "fire_rifle": cooldown = 105
	elif kind == "death": cooldown = 140
	elif kind == "low_power": cooldown = 1800
	elif kind == "result": cooldown = 1800
	elif kind == "command": cooldown = 95
	if recent.has(family) and now - int(recent[family]) < cooldown:
		return
	var field := kind in ["fire", "impact", "death", "ruin_destroy"]
	var distance_gain := 0.0
	if field and event.has("pos") and camera_focus != Vector2.INF:
		var distance: float = (event.pos as Vector2).distance_to(camera_focus)
		if distance > 70.0:
			return
		distance_gain = -minf(19.0, maxf(0.0, distance - 12.0) * 0.36)
	recent[family] = now
	var pool: Array[AudioStreamPlayer] = field_players if field else ui_players
	var player: AudioStreamPlayer = null
	for candidate in pool:
		if not candidate.playing:
			player = candidate
			break
	if player == null:
		# UI may replace its oldest feedback. Field sounds fade naturally; dropping
		# excess shots avoids chopping long explosion tails during mass combat.
		if field:
			return
		player = pool[0]
		for candidate in pool:
			if int(voice_started.get(candidate, 0)) < int(voice_started.get(player, 0)):
				player = candidate
		player.stop()
	var entry: Variant = bank[family]
	if entry is Array:
		var previous := int(variants.get(family, -1))
		var index := rng.randi_range(0, entry.size() - 2)
		if index >= previous and previous >= 0: index += 1
		variants[family] = index
		player.stream = entry[index]
	else:
		player.stream = entry
	var gain := -16.0 if field else -19.0
	if kind in ["select", "command", "error"]: gain = -21.0
	elif kind == "result": gain = -15.0
	elif kind == "low_power": gain = -21.0
	player.volume_db = gain + distance_gain + (rng.randf_range(-1.0, 0.0) if field else 0.0)
	player.pitch_scale = rng.randf_range(0.97, 1.03) if field else 1.0
	voice_started[player] = now
	player.play()

func _event_family(event: Dictionary) -> String:
	var kind := str(event.get("kind", ""))
	if kind == "ruin_destroy":return "impact_large"
	if kind in ["rearm", "return"]: return "rearm"
	if kind == "fire":
		var weapon := str(event.get("weapon", ""))
		if weapon.ends_with("_fighter"): return "fire_air"
		if weapon.ends_with("_bomber") or weapon.ends_with("_attacker"): return "bomb_release"
		if weapon.ends_with("_aa"): return "fire_anti"
		if weapon.ends_with("_artillery"): return "fire_artillery"
		if weapon.ends_with("_rifle") or weapon == "kestrel_tower": return "fire_rifle"
		if weapon.ends_with("_anti"): return "fire_anti"
		if weapon.ends_with("_assault") or weapon.ends_with("_demolition"): return "fire_artillery"
		return "fire_cannon"
	if kind == "impact":
		var blast := float(event.get("blast", 1.0))
		if blast < 0.65: return "impact_small"
		if blast >= 1.6: return "impact_large"
		return "impact_medium"
	if kind == "death":
		var spec := str(event.get("spec", ""))
		if spec.ends_with("_rifle") or spec.ends_with("_anti") or spec.ends_with("_engineer") or spec.ends_with("_demolition"):
			return "death_soft"
	return kind

# Called with camera ground coordinates. Two aggregated beds only consider nearby
# moving friendly vehicles: an army never creates one engine voice per entity.
func update_battlefield(delta: float, entities: Dictionary, focus: Vector2) -> void:
	camera_focus = focus
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
		for id in entities:
			var entity:Dictionary=entities[id]
			if int(entity.get("team", -1)) != 0 or float(entity.get("hp", 0.0)) <= 0.0 or float(entity.get("motion", 0.0)) <= 0.0001:
				continue
			var spec := str(entity.get("spec", ""))
			var audio_type:int=_audio_type(spec)
			if audio_type<0:continue
			var distance_squared:float=(entity.pos as Vector2).distance_squared_to(focus)
			if distance_squared>=48.0*48.0:continue
			var distance:float=sqrt(distance_squared)
			var weight:float=clampf(1.0-maxf(0.0,distance-12.0)/36.0,0.0,1.0)
			if audio_type==2:
				if float(entity.get("flight_height", 0.0)) > 0.5:
					aircraft+=weight
				continue
			nearby += weight
			heavy += weight * (0.55 if audio_type==1 else 1.0)
		target_engine = minf(1.0, log(1.0 + nearby) / log(5.0))
		target_tracks = minf(1.0, log(1.0 + heavy) / log(5.0))
		target_aircraft = minf(1.0, log(1.0 + aircraft) / log(4.0))
	var blend := 1.0 - exp(-delta * 5.0)
	engine_level = lerpf(engine_level, target_engine, blend)
	movement_level = lerpf(movement_level, target_tracks, blend)
	aircraft_level = lerpf(aircraft_level, target_aircraft, blend)
	if aircraft_player != null:
		if aircraft_level < 0.008:
			if aircraft_player.playing:aircraft_player.stop()
		else:
			aircraft_player.volume_db = -34.0 + linear_to_db(aircraft_level)
			if not aircraft_player.playing: aircraft_player.play()
	for index in range(2):
		var level := engine_level if index == 0 else movement_level
		var player := engine_players[index]
		if level < 0.008:
			if player.playing:player.stop()
			continue
		player.volume_db = (-28.0 if index == 0 else -33.0) + linear_to_db(level)
		player.pitch_scale = 0.96 + engine_level * 0.08
		if not player.playing: player.play()

func _audio_type(spec:String) -> int:
	if not audio_type_cache.has(spec):
		var kind:int=-1
		if unit_definitions.get(spec,{}).get("domain","ground")=="air":kind=2
		elif spec.ends_with("_harvester"):kind=1
		elif spec.ends_with("_tank") or spec.ends_with("_assault"):kind=0
		audio_type_cache[spec]=kind
	return int(audio_type_cache[spec])

func stop_all() -> void:
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
	unit_definitions = rules.get("units", {})
	audio_type_cache.clear()
	speech_recent.clear()
	pending_speech.clear()
	last_speech_ms = -100000
	if speech_player != null: speech_player.stop()
	unit_caption.emit("", 0.0)
	_load_voice_manifest()

func _load_voice_manifest() -> void:
	speech_clips.clear()
	if not FileAccess.file_exists(VOICE_MANIFEST): return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(VOICE_MANIFEST))
	if not manifest is Dictionary: return
	for clip in manifest.get("clips", []):
		var key: String = str(clip.get("faction", "")) + "/" + str(clip.get("action", ""))
		if not speech_clips.has(key): speech_clips[key] = []
		speech_clips[key].append(clip)

# A dedicated speech bus and a single player keep the spoken orders legible.
# Rapid group orders choose one representative and never layer 20 voices.
func play_unit_voice(spec: String, action_id: String) -> bool:
	if speech_player == null: return false
	var key: String = spec + "/" + action_id
	var definitions: Dictionary = unit_definitions.get(spec, {})
	var authored: Array = definitions.get("voices", {}).get(action_id, [])
	if authored.is_empty(): return false
	var faction: String = str(definitions.get("faction", spec.get_slice("_", 0)))
	var radio_key: String = faction + "/" + action_id
	var choices: Array = speech_clips.get(radio_key, [])
	var audible: bool = not muted and float(mix.master) > 0.0 and float(mix.voice) > 0.0
	var now: int = Time.get_ticks_msec()
	if audible and now - int(speech_recent.get(key, -100000)) < 1800: return false
	if audible and speech_player.playing:
		# Finish the short spoken phrase instead of clipping it mid-word. Keep
		# one latest order; background completion cannot replace a player order.
		var pending_action: String = str(pending_speech.get("action", ""))
		if action_id in ["move", "attack"] or (action_id in ["ready", "return"] and pending_action not in ["move", "attack"]):
			pending_speech = {"spec": spec, "action": action_id}
		return false
	if audible and now - last_speech_ms < 650: return false
	var text: String = str(authored[rng.randi_range(0, authored.size() - 1)])
	var clip_duration: float = 0.0
	if not choices.is_empty():
		var clip: Dictionary = choices[rng.randi_range(0, choices.size() - 1)]
		text = str(clip.get("text", text))
		clip_duration = float(clip.get("duration_s", 0.0))
	# Native offline Mandarin words and their exact subtitles share one manifest.
	# The historical online-TTS files and metadata are never loaded at runtime.
	if audible and radio_bank.has(radio_key):
		speech_player.stream = radio_bank[radio_key]
		speech_player.volume_db = -6.0
		speech_player.pitch_scale = 1.0
		speech_player.play()
		speech_recent[key] = now
		last_speech_ms = now
	unit_caption.emit("%s：%s" % [str(definitions.get("name", spec)), text], clampf(maxf(clip_duration + .25, 1.8 + text.length() * .10), 2.3, 5.5))
	return true


func _process(delta: float) -> void:
	var speaking: bool = speech_player != null and speech_player.playing and not muted and float(mix.master) > 0.0 and float(mix.voice) > 0.0
	# Briefly lower battle effects so a nearby firefight does not hide words.
	effects_duck_db = lerpf(effects_duck_db, -5.0 if speaking else 0.0, 1.0 - exp(-delta * 10.0))
	music_duck_db = lerpf(music_duck_db, -3.5 if speaking else 0.0, 1.0 - exp(-delta * 6.0))
	if absf(music_duck_db - (-3.5 if speaking else 0.0)) < .01: music_duck_db = -3.5 if speaking else 0.0
	if absf(effects_duck_db-(-5.0 if speaking else 0.0))<.01:effects_duck_db=-5.0 if speaking else 0.0
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
	if not speaking and not pending_speech.is_empty() and Time.get_ticks_msec() - last_speech_ms >= 650:
		var pending: Dictionary = pending_speech.duplicate()
		pending_speech.clear()
		play_unit_voice(str(pending.spec), str(pending.action))
