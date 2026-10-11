extends Node

## A single local recording lane keeps reports calm during mass combat.
## Discovery reads only currently visible enemies; hotspots retain event-time
## positions, never follow an unseen unit through fog.
const MANIFEST := "res://assets/audio/commander/manifest.json"
const BUS := "Paper Commander"
const PRIORITY := {"base_attacked":100,"enemy_base":90,"harvester_attacked":85,"enemy_mass":80,"building_attacked":75,"unit_lost":70,"vehicle_attacked":65,"infantry_attacked":60,"enemy_seen":55,"building_ready":40,"building_complete":35,"unit_ready":30,"combat":20}
const COOLDOWN := {"base_attacked":12.0,"enemy_base":25.0,"harvester_attacked":14.0,"enemy_mass":20.0,"building_attacked":14.0,"unit_lost":12.0,"vehicle_attacked":14.0,"infantry_attacked":14.0,"enemy_seen":18.0,"building_ready":6.0,"building_complete":6.0,"unit_ready":6.0,"combat":20.0}
const INFANTRY := ["rifle","anti","engineer","demolition"]
const HOTSPOT_LIFETIME := 45.0
const MASS_THRESHOLD := 8
var voice_language: String = "en"
var clips: Dictionary = {}
var streams: Dictionary = {}
var pending: Dictionary = {}
var last: Dictionary = {}
var reports: Array[Dictionary] = []
var spotted: Dictionary = {}
var hotspots: Array[Dictionary] = []
var player: AudioStreamPlayer
var audio
var simulation
var scan_clock := 0.0
var report_clock := 0.0
var active_action := ""
var enabled := false:
	set(value):
		enabled = value
		if player != null: player.stream_paused = not value
var _mass_seen := false
var _owns_bus := false
var configuration: Dictionary = {}

func _ready() -> void:
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, BUS)
		AudioServer.add_bus_effect(AudioServer.bus_count - 1, AudioEffectLimiter.new())
		_owns_bus = true
	AudioServer.set_bus_send(AudioServer.get_bus_index(BUS), PaperAudio.MASTER_BUS)
	player = AudioStreamPlayer.new()
	player.bus = BUS
	player.volume_db = -15.0
	add_child(player)
	_load_voice_bank()

func _load_voice_bank() -> void:
	clips.clear(); streams.clear()
	var path: String = PaperAudio.commander_manifest(voice_language)
	if not FileAccess.file_exists(path): return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if manifest is Dictionary:
		for clip: Dictionary in manifest.get("clips", []):
			var key := str(clip.action)
			clips[key] = clip
			streams[key] = load(str(clip.file)) if ResourceLoader.exists(str(clip.file)) else null

func set_voice_language(language: String) -> void:
	clear_playback()
	if player != null: player.stream = null
	last.clear(); reports.clear()
	voice_language = PaperAudio.normalize_voice_language(language)
	if is_node_ready(): _load_voice_bank()

func reset(sim = null) -> void:
	simulation = sim
	configuration = sim.rules.get("commander", {}).duplicate(true) if sim != null else {}
	if player != null: player.stop()
	pending.clear(); last.clear(); reports.clear(); spotted.clear(); hotspots.clear()
	active_action = ""; report_clock = 0.0; scan_clock = 0.0; _mass_seen = false

func clear_playback() -> void:
	if player != null: player.stop()
	pending.clear(); active_action = ""

func request(action: String, context: Dictionary = {}) -> bool:
	if not enabled or not clips.has(action): return false
	if pending.has(action):
		pending[action].count = int(pending[action].count) + 1
		return true
	if report_clock - float(last.get(action, -1000.0)) < float(configuration.get("cooldowns", {}).get(action, COOLDOWN.get(action, 12.0))): return false
	# Reserve cooldown at acceptance, so a busy lane cannot accumulate duplicates.
	last[action] = report_clock
	pending[action] = {"action":action,"count":1,"at":report_clock,"context":context.duplicate(true)}
	return true

func observe_event(event: Dictionary, sim) -> void:
	if not enabled: return
	var kind := str(event.get("kind", ""))
	if kind == "death" and not bool(event.get("destroyed", true)): return
	var team := int(event.get("team", -1))
	var pos: Vector2 = event.get("pos", Vector2.INF)
	var domain: String = "air" if float(event.get("height",0.0)) > 2.0 else "naval" if pos.is_finite() and MapData.terrain_at(sim.map,pos) == MapData.WATER else "ground"
	var visible: bool = team == 0 or (pos.is_finite() and sim.position_visible_to(0, pos, domain))
	if not visible: return
	if kind in ["fire", "under_attack", "damage", "death", "emp"] and pos.is_finite():
		hotspots.append({"pos":pos,"at":float(sim.time),"kind":kind})
		if hotspots.size() > 24: hotspots.pop_front()
	if team != 0: return
	var info: Dictionary = sim.data_for(str(event.get("spec", "")))
	var action := ""
	if kind == "building_ready" or kind == "ready": action = "building_ready"
	elif kind == "deploy": action = "building_complete"
	elif kind == "produce": action = "unit_ready"
	elif kind == "fire": action = "combat"
	elif kind in ["under_attack", "damage"]:
		var role := str(info.get("role", ""))
		if role in ["hq", "outpost"]: action = "base_attacked"
		elif str(event.get("entity_kind", "")) == "building" or sim.rules.buildings.has(str(event.get("spec", ""))): action = "building_attacked"
		elif str(info.get("art", "")) == "harvester": action = "harvester_attacked"
		elif str(info.get("art", "")) in INFANTRY: action = "infantry_attacked"
		else: action = "vehicle_attacked"
	elif kind == "death" and str(event.get("entity_kind", "unit")) == "unit": action = "unit_lost"
	if not action.is_empty(): request(action, event)

func observe_visibility(sim) -> void:
	var units: Array[Vector2] = []
	var new_enemy := false
	for id: int in sim.entities:
		if not sim.entity_visible_to(0, id): continue
		var e: Dictionary = sim.entities[id]
		if int(e.team) <= 0 or float(e.hp) <= 0.0: continue
		if str(e.kind) == "unit": units.append(e.pos)
		if spotted.has(id): continue
		spotted[id] = true
		new_enemy = true
		if str(sim.data_for(e.spec).get("role", "")) in ["hq", "outpost"]: request("enemy_base", {"pos":e.pos,"id":id})
	# Large force means a local concentration, not eight scattered scouts.
	var mass := false
	for point: Vector2 in units:
		var count := 0
		for other: Vector2 in units:
			if point.distance_squared_to(other) <= pow(float(configuration.get("mass_radius",12.0)), 2.0): count += 1
		if count >= int(configuration.get("mass_threshold", MASS_THRESHOLD)):
			mass = true; break
	if mass and not _mass_seen: request("enemy_mass")
	elif new_enemy: request("enemy_seen")
	_mass_seen = mass

func latest_hotspot(sim) -> Vector2:
	for index in range(hotspots.size() - 1, -1, -1):
		var event: Dictionary = hotspots[index]
		if float(sim.time) - float(event.at) <= float(configuration.get("hotspot_lifetime", HOTSPOT_LIFETIME)) and sim._in_bounds(event.pos): return event.pos
	return Vector2.INF

func _process(delta: float) -> void:
	if not enabled or audio == null or audio.preview_active: return
	report_clock += delta
	if simulation != null:
		scan_clock += delta
		if scan_clock >= float(configuration.get("discovery_interval", .6)):
			scan_clock = 0.0; observe_visibility(simulation)
	if audio.muted or float(audio.mix.master) <= 0.0 or float(audio.mix.commander) <= 0.0:
		clear_playback(); return
	var next := ""
	for action: String in pending.keys():
		if report_clock - float(pending[action].at) > float(configuration.get("queue_expiry", 8.0)): pending.erase(action); continue
		if next.is_empty() or _priority(action) > _priority(next): next = action
	if next.is_empty(): return
	if player.playing:
		# Only urgent base alerts interrupt a routine completion report.
		if next != "base_attacked" or _priority(active_action) >= 75: return
		player.stop()
	var entry: Dictionary = pending[next]
	pending.erase(next)
	if streams.get(next) == null: return
	active_action = next
	player.stream = streams[next]
	player.pitch_scale = 1.0
	player.play()
	reports.append(entry)
	if reports.size() > 64: reports.pop_front()
	audio.unit_caption.emit("指挥官：" + PaperAudio.caption_text(clips[next]), float(clips[next].duration_s) + .25)

func _priority(action: String) -> int:
	return int(configuration.get("priorities", {}).get(action, PRIORITY.get(action, 0)))

func _exit_tree() -> void:
	if _owns_bus:
		var index := AudioServer.get_bus_index(BUS)
		if index >= 0: AudioServer.remove_bus(index)
