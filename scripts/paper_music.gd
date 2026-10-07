extends Node
class_name PaperMusic

# A single PCM player makes scene transitions deterministic and prevents
# overlapping music beds. Fade out, change at silence, then fade in.
const TRACKS := ["menu", "battle", "win", "lose", "draw"]
const MAP_TRACKS := {
	"forest": "battle_calm", "desert": "battle_calm", "snow": "battle_calm",
	"city": "battle_calm", "random_city": "battle_calm", "islands": "battle_calm",
	"campaign": "battle_calm"
}
const APPLIED_TRACKS := ["menu", "battle_calm", "battle_engaged", "battle_intense", "battle_danger"]
const TRANSITION_SECONDS := 2.0
const BASELINE_LINEAR := .3825 # Previous default master .85 x music .45.
const BASELINE_DB := -8.347371
const REVISION_MUSIC_DIR := "res://assets/audio/revision_v8/music/"
const REVISION_MANIFEST := REVISION_MUSIC_DIR + "manifest.json"
const COMBAT_ENTER_SCORE := 2.4
const COMBAT_ENTER_SECONDS := 1.25
const INTENSE_ENTER_SCORE := 7.5
const INTENSE_EXIT_SCORE := 4.0
const INTENSE_ENTER_SOURCES := 6
const INTENSE_EXIT_SOURCES := 0 # Third tiers exit only after the shared quiet timer.
const INTENSE_SUSTAIN_SECONDS := 1.25
const ENGAGED_MINIMUM_SECONDS := 5.0
const DENSITY_CELL_SIZE := 8.0
const DENSITY_SCAN_SECONDS := .16
const RECENT_SHOT_SECONDS := 10.0
const QUIET_EXIT_SECONDS := 5.0
const ENEMY_DANGER_SOURCES := 5
const BATTLE_TRACKS := ["battle_engaged", "battle_intense", "battle_danger"]
var player: AudioStreamPlayer
var tracks: Dictionary = {}
var scene := "silent"
var requested_scene := "silent"
var requested_track := "silent"
var active_track := "silent"
var map_id := ""
var gain := 0.0
var silent := false
var combat_score := 0.0
var combat_active := false
var combat_paused := false
var combat_trigger_time := 0.0
var combat_sources: Dictionary = {}
var recent_shots: Dictionary = {}
var combat_level := 0 # calm, ordinary engagement, dense battle
var combat_level_time := 0.0
var dense_sources := 0
var dense_trigger_time := 0.0
var combat_clock := 0.0
var density_scan := 0.0
var fade_phase := "steady"
var fade_elapsed := 0.0
var fade_start_gain := 0.0
var playback_paused := false
var preview_resume_position := -1.0
var friendly_sources := 0
var enemy_sources := 0
var locked_combat_track := ""
var last_interaction_clock := -100000.0
var shot_teams: Dictionary = {}

func _ready() -> void:
	player = AudioStreamPlayer.new()
	player.bus = "Paper Music"
	add_child(player)
	# Only this five-track score is active. Historical synthesized map/result
	# themes stay as source history and never load or appear in the browser.
	for name: String in APPLIED_TRACKS:
		var path: String = REVISION_MUSIC_DIR + name + ".wav"
		if not ResourceLoader.exists(path): continue
		var source: AudioStreamWAV = load(path)
		if source == null: continue
		var stream: AudioStreamWAV = source.duplicate()
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(round(stream.get_length() * stream.mix_rate))
		tracks[name] = stream
	player.volume_db = -80.0

func set_scene(value: String) -> void:
	var next_scene: String = value if value in TRACKS else "silent"
	if requested_scene != next_scene: reset_combat()
	requested_scene = next_scene
	_refresh_requested_track()

# Map selection is independent of menu/result scenes, so loading a save or
# choosing another battlefield updates its music even while scene == battle.
func set_map(value: String) -> void:
	if map_id == value: return
	map_id = value
	_refresh_requested_track()

func track_for_map(value: String) -> String:
	return "battle_calm"

func _refresh_requested_track() -> void:
	if requested_scene != "battle":
		requested_track = "menu" if requested_scene == "menu" else "silent" if requested_scene == "silent" else "battle_calm"
	else:
		var combat_track: String = locked_combat_track if not locked_combat_track.is_empty() else "battle_engaged"
		requested_track = combat_track if combat_level > 0 and tracks.has(combat_track) else track_for_map(map_id)

func set_combat_paused(value: bool) -> void:
	combat_paused = value

func set_playback_paused(value: bool) -> void:
	playback_paused = value
	if player == null: return
	if not value and preview_resume_position >= 0.0 and player.stream != null:
		player.play(preview_resume_position)
		preview_resume_position = -1.0
	player.stream_paused = value

func get_playback_position() -> float:
	# A stopped paused stream cannot expose its pending seek through Godot's
	# player getter. Keep the cursor while an audition temporarily owns output.
	return preview_resume_position if preview_resume_position >= 0.0 else player.get_playback_position() if player != null else 0.0

func restore_playback(position: float) -> void:
	if player == null or player.stream == null: return
	var cursor: float = fmod(position, maxf(player.stream.get_length(), .001))
	if playback_paused:
		preview_resume_position = cursor
		player.stream_paused = true
	else:
		preview_resume_position = -1.0
		player.play(cursor)
		player.stream_paused = false

func reset_combat() -> void:
	combat_score = 0.0
	combat_active = false
	combat_level = 0
	combat_level_time = 0.0
	combat_trigger_time = 0.0
	combat_sources.clear()
	recent_shots.clear()
	dense_sources = 0
	dense_trigger_time = 0.0
	density_scan = 0.0
	friendly_sources = 0; enemy_sources = 0
	locked_combat_track = ""
	last_interaction_clock = -100000.0
	shot_teams.clear()
	_refresh_requested_track()

func observe_combat(event: Dictionary) -> void:
	if requested_scene != "battle" or combat_paused or playback_paused: return
	var weight := 0.0
	match str(event.get("kind", "")):
		"fire":
			weight = .45
			if int(event.get("id", -1)) > 0:
				combat_sources[int(event.id)] = int(event.get("target", -1))
				recent_shots[int(event.id)] = combat_clock
				shot_teams[int(event.id)] = int(event.get("team", 0))
		"impact": weight = .55 if bool(event.get("projectile", false)) or float(event.get("blast", 0.0)) >= .6 else .15
		"under_attack": weight = .65
		"death":
			combat_sources.erase(int(event.get("id", -1)))
			recent_shots.erase(int(event.get("id", -1)))
			shot_teams.erase(int(event.get("id", -1)))
			if bool(event.get("destroyed", true)): weight = 1.2 if str(event.get("entity_kind", "unit")) == "building" else .65
	if weight <= 0.0: return
	combat_score = minf(40.0, combat_score + weight)
	last_interaction_clock = combat_clock

func update_engagement(simulation) -> void:
	if requested_scene != "battle" or combat_paused or playback_paused: return
	if density_scan <= 0.0:
		density_scan = DENSITY_SCAN_SECONDS
		dense_sources = _measure_density(simulation)

func _measure_density(simulation) -> int:
	friendly_sources = 0; enemy_sources = 0
	for id: int in recent_shots.keys():
		var entity: Dictionary = simulation.entities.get(id, {})
		if combat_clock - float(recent_shots[id]) > RECENT_SHOT_SECONDS or entity.is_empty() or float(entity.get("hp", 0.0)) <= 0.0:
			recent_shots.erase(id); shot_teams.erase(id); combat_sources.erase(id)
			continue
		if str(entity.get("kind", "unit")) != "unit": continue
		var team: int = int(entity.get("team", shot_teams.get(id, -1)))
		if team == 0: friendly_sources += 1
		elif team > 0: enemy_sources += 1
	return friendly_sources + enemy_sources

func _source_engaged(simulation, entity: Dictionary, last_target: int) -> bool:
	if float(entity.get("hp", 0.0)) <= 0.0 or int(entity.get("transport_id", -1)) > 0 or float(entity.get("emp_until", 0.0)) > simulation.time: return false
	var info: Dictionary = simulation.data_for(str(entity.spec))
	var weapon: Dictionary = simulation.rules.weapons.get(str(info.get("weapon", "")), {})
	if weapon.is_empty(): return false
	if entity.kind == "building" and simulation.building_low_power(entity): return false
	if str(info.get("domain", "ground")) == "air" and (int(entity.get("ammo", 1)) <= 0 or str(entity.get("flight_state", "")) in ["returning", "rearming", "stranded"]): return false
	var target: int = int(entity.get("turret_target", -1))
	if target == -1: target = int(entity.get("auto_target", -1))
	var commands: Array = entity.get("commands", [])
	if not commands.is_empty():
		var command: Dictionary = commands[0]
		var kind: String = str(command.get("kind", ""))
		if kind not in ["attack", "force_attack", "attack_move", "patrol"]: return false
		if kind in ["attack", "force_attack"]:
			target = int(command.get("target", -1))
			if target == -1: return (entity.pos as Vector2).distance_to(command.get("pos", Vector2.INF)) <= float(weapon.range)
	if target == -1: target = last_target
	var target_valid: bool = simulation._target_alive(target) and simulation._weapon_can_target(entity, target) and (entity.pos as Vector2).distance_to(simulation._target_position(target)) <= float(weapon.range)
	# Idle foot soldiers acquire during every simulation tick without storing
	# auto_target. A live replacement target during reload is still an engagement.
	if not target_valid and commands.is_empty():
		var replacement: int = int(simulation._nearest_enemy(entity, float(weapon.range)))
		var replacement_valid: bool = replacement >= 0 and simulation._target_alive(replacement) and (entity.pos as Vector2).distance_to(simulation._target_position(replacement)) <= float(weapon.range)
		if replacement_valid and combat_sources.has(int(entity.id)): combat_sources[int(entity.id)] = replacement
		return replacement_valid
	return target_valid

func cease_fire() -> void:
	# Returning to calm requests a normal two-second fade. Only mute/shutdown
	# cuts output immediately; ordinary ceasefire keeps the musical tail.
	reset_combat()

func _advance_combat(delta: float) -> void:
	if requested_scene != "battle" or combat_paused or playback_paused: return
	combat_clock += delta
	density_scan -= delta
	combat_score *= exp(-delta / 5.0)
	combat_level_time += delta
	if combat_clock - last_interaction_clock > QUIET_EXIT_SECONDS:
		if combat_level > 0: cease_fire()
		return
	combat_active = true
	if combat_level == 0: combat_level = 1
	# A chosen third tier stays locked through reloads, casualties or changing
	# headcounts. Only more than five seconds with no actual fire/hit/impact
	# unlocks it; stale ten-second shooter memories cannot immediately re-enter.
	if locked_combat_track.is_empty():
		if friendly_sources >= INTENSE_ENTER_SOURCES:
			locked_combat_track = "battle_intense"; combat_level = 2
		elif enemy_sources >= ENEMY_DANGER_SOURCES and friendly_sources == 0:
			locked_combat_track = "battle_danger"; combat_level = 2
	_refresh_requested_track()

func set_silent(value: bool) -> void:
	# A map changed while muted may have a newly assigned stopped stream.
	# Fade that stream in on restore; an existing playback keeps its position.
	if silent and not value and player != null and not player.playing:
		gain = 0.0
		fade_phase = "in"
		fade_elapsed = 0.0
		fade_start_gain = 0.0
	silent = value
	# Bus muting is immediate. Keep playback position while muted so toggling
	# the preference does not repeatedly restart a musical phrase.

func _process(delta: float) -> void:
	if player == null or playback_paused: return
	_advance_combat(delta)
	if active_track != requested_track:
		if player.stream == null or gain <= .0001:
			_switch_track()
		else:
			if fade_phase != "out":
				fade_phase = "out"
				fade_elapsed = 0.0
				fade_start_gain = gain
			fade_elapsed += delta
			gain = fade_start_gain * (1.0 - smoothstep(0.0, 1.0, clampf(fade_elapsed / TRANSITION_SECONDS, 0.0, 1.0)))
			if fade_elapsed >= TRANSITION_SECONDS: _switch_track()
	else:
		scene = requested_scene
		if fade_phase == "out":
			fade_phase = "in"
			fade_elapsed = 0.0
			fade_start_gain = gain
		if fade_phase == "in":
			fade_elapsed += delta
			gain = lerpf(fade_start_gain, 1.0 if scene != "silent" else 0.0, smoothstep(0.0, 1.0, clampf(fade_elapsed / TRANSITION_SECONDS, 0.0, 1.0)))
			if fade_elapsed >= TRANSITION_SECONDS: fade_phase = "steady"
		if player.stream != null and not player.playing and not silent: player.play()
	player.volume_db = linear_to_db(gain) + BASELINE_DB if gain > 0.0001 else -80.0

func _switch_track() -> void:
	preview_resume_position = -1.0
	player.stop()
	scene = requested_scene
	active_track = requested_track
	player.stream = tracks.get(active_track, null)
	gain = 0.0
	fade_phase = "in"
	fade_elapsed = 0.0
	fade_start_gain = 0.0
	if player.stream != null and not silent: player.play()
	player.stream_paused = playback_paused

func stop_all() -> void:
	preview_resume_position = -1.0
	reset_combat()
	requested_scene = "silent"
	requested_track = "silent"
	active_track = "silent"
	scene = "silent"
	gain = 0.0
	fade_phase = "steady"
	fade_elapsed = 0.0
	if player != null:
		player.stop()
		player.stream = null
