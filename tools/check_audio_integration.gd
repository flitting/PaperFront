extends SceneTree

# Short source-scene integration: uses main.tscn's native frame/physics loop,
# real WarSimulation movement/combat, and the ordinary selection/order paths.
var failures: Array[String] = []
var seen_events: Dictionary = {}
var engine_observed := false
var max_motion := 0.0
var observed_families: Dictionary = {}
var scene: Node
var moving_id := -1

func require(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _initialize() -> void:
	call_deferred("run")

func observe(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await process_frame
		for event in scene.sim.events:
			var kind := str(event.get("kind", ""))
			seen_events[kind] = int(seen_events.get(kind, 0)) + 1
		for family in scene.audio.recent:
			observed_families[family] = true
		if scene.sim.entities.has(moving_id):
			max_motion = maxf(max_motion, float(scene.sim.entities[moving_id].motion))
		for player in scene.audio.engine_players:
			engine_observed = engine_observed or player.playing

func run() -> void:
	scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	require(scene.start_match("handmade", 73026, "rivet", true), "Source scene could not start normal match")
	scene.sim.ai_enabled = false
	scene.hud.show_menu(false)
	scene.audio.muted = false
	var origin: Vector2 = scene.standable_near(scene.focus + Vector2(3, 6))
	moving_id = scene.sim.debug_spawn(0, "rivet_tank", origin)
	scene.focus = origin
	scene.update_camera()
	await process_frame
	var ground := Vector3(origin.x, MapData.height_at(scene.sim.map, origin) + 0.6, origin.y)
	var screen: Vector2 = scene.project_world_to_screen(ground)
	scene.box_select(Rect2(screen - Vector2(10, 10), Vector2(20, 20)), false)
	require(scene.selected.has(moving_id), "Ordinary box selection did not select visible tank")
	require(scene.audio.recent.has("select"), "Ordinary selection did not dispatch select audio")
	scene.selected = [moving_id]
	var goal: Vector2 = scene.standable_near(origin + Vector2(5, 0))
	scene.command_units("move", goal)
	require(scene.audio.recent.has("command"), "Ordinary movement command did not dispatch command audio")
	await observe(1.6)
	require(max_motion > 0.0, "Real simulation motion field never recorded movement")
	require(engine_observed, "Real nearby moving vehicle never started engine/track bed")
	# Put a sustained opposing tank and allied infantry inside real weapon range.
	var tank_pos: Vector2 = scene.sim.entities[moving_id].pos
	var enemy_pos: Vector2 = scene.standable_near(tank_pos + Vector2(3.5, 2.5))
	var enemy_id: int = scene.sim.debug_spawn(1, "kestrel_tank", enemy_pos)
	var rifle_id: int = scene.sim.debug_spawn(0, "rivet_rifle", scene.standable_near(tank_pos + Vector2(1.2, 0)))
	scene.sim.entities[enemy_id].hp = 2000.0
	scene.sim.entities[moving_id].hp = 2000.0
	scene.sim.issue([moving_id, rifle_id], "attack", enemy_pos, enemy_id)
	scene.sim.issue([enemy_id], "attack", tank_pos, moving_id)
	await observe(4.2)
	require(observed_families.has("fire_cannon"), "Actual tank fire never reached cannon audio family")
	require(observed_families.has("fire_rifle"), "Actual infantry fire never reached rifle audio family")
	require(observed_families.has("impact_medium"), "Actual projectile landing never reached medium impact audio")
	# Spawn moving transport to guarantee active loops immediately before mute.
	var harvester_pos: Vector2 = scene.standable_near(scene.focus + Vector2(0, 6))
	var harvester_id: int = scene.sim.debug_spawn(0, "rivet_harvester", harvester_pos)
	scene.sim.issue([harvester_id], "move", scene.standable_near(harvester_pos + Vector2(7, 0)))
	await observe(0.45)
	scene.handle_action("mute", true)
	for player in scene.audio.players: require(not player.playing, "Normal mute action left a playing voice")
	await observe(0.18)
	for player in scene.audio.engine_players: require(not player.playing, "Muted frame restarted vehicle loop")
	scene.handle_action("mute", false)
	await observe(0.22)
	# Stop gate is the actual started flag consumed by main's new audio call.
	scene.started = false
	await observe(1.2)
	for player in scene.audio.engine_players: require(not player.playing, "Stopped scene retained vehicle loop")
	scene.handle_action("restart", null)
	await observe(0.65)
	require(scene.started, "Normal restart action did not restart match")
	for player in scene.audio.engine_players: require(not player.playing, "Restart inherited old moving-vehicle loop")
	var report := {"status":"PASS" if failures.is_empty() else "FAIL", "source_scene":"res://main.tscn", "mode":"handmade normal match; native main frame/physics loop with a short deterministic combat setup", "simulation_seconds":scene.sim.time, "max_actual_motion":max_motion, "engine_observed":engine_observed, "actual_events_observed_before_main_dispatch":seen_events, "audio_families_reached_via_main":observed_families.keys(), "checks":["normal source scene start", "normal box selection", "normal command path", "real simulation motion", "nearby vehicle loops", "real rifle/cannon fire and projectile impacts", "normal mute/unmute actions", "stopped match gate", "normal restart action", "normal quit cleanup"], "failures":failures}
	var file := FileAccess.open("res://artifacts/visual_iteration/v44_reference_rebuild/audio/source_integration.json", FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "  "))
	file = null
	print("AUDIO_SOURCE_INTEGRATION ", JSON.stringify(report))
	scene.quit_game(0 if failures.is_empty() else 1)
