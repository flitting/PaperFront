extends SceneTree
## Art-directed in-engine footage. Uses production PaperWorld, rules and assets;
## showcase deployments and camera motion are authored, not a recorded match.
const Sim = preload("res://tests/rule_test_simulation.gd")
const L = preload("res://scripts/localization.gd")
const OUT = "res://artifacts/release_20261011/trailer/raw/"
const FACTIONS: Array[String] = ["kestrel", "rivet", "iron", "sky"]
const FPS = 24
var sim
var world: PaperWorld
var camera: Camera3D
var stage: Node3D
var stills_only: bool
var evidence: Array = []

func checkpoint(message: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var file := FileAccess.open(OUT.get_base_dir().path_join("progress.txt"), FileAccess.WRITE)
	file.store_string(message)
	file.close()
	print("TRAILER_STAGE ", message)

func _initialize() -> void:
	if OS.get_environment("PAPER_FRONT_CAPTURE_OFFSCREEN") != "1":
		root.hide()
		printerr("Use tools/run_offscreen_capture.py; no desktop window is launched.")
		quit(2)
		return
	call_deferred("run")

func clear_world() -> void:
	if world != null:
		world.free()
		world = null
	sim = null
	await process_frame

func fresh_sim(water: bool = false) -> void:
	checkpoint("Preparing lightweight showcase simulation")
	await clear_world()
	sim = Sim.new()
	var starts: Array[Vector2] = [Vector2(8, 8), Vector2(40, 8), Vector2(8, 40), Vector2(40, 40)]
	sim.setup_multiteam(RulesLoader.load_rules(), "symmetric", 117, FACTIONS, false, starts, Callable(), {"vision_enabled":false})
	assert(int(sim.map.size) == 192)
	for id in sim.entities.keys(): sim._kill_entity(id, false)
	for row in sim.map.terrain: row.fill(MapData.WATER if water else MapData.LAND)
	for row in sim.map.heights: row.fill(0.0)
	for key in ["ruins", "mines", "bridges", "decorations", "harbors"]:
		if sim.map.has(key): sim.map[key].clear()
	sim.ruins.clear()
	sim.mines.clear()
	sim.bridges.clear()
	sim.events.clear()
	sim._refresh_ruin_spatial()
	sim._refresh_mine_spatial()
	sim._prepare_terrain_cache()

func create_world() -> void:
	checkpoint("Building current production PaperWorld")
	world = PaperWorld.new()
	stage.add_child(world)
	world.setup(sim, camera)
	world.configure_quality("native")
	world.lod_override = 0
	checkpoint("Production PaperWorld ready")

func deploy(team: int, role: String, point: Vector2) -> int:
	var id: int = sim._spawn(team, FACTIONS[team] + "_" + role, point, true)
	sim.entities[id].visible_to = 255
	sim.entities[id].alpha = -12.0
	return id

func shot(name: String, target: Vector3, offset: Vector3, framing: float, drift: Vector3) -> void:
	checkpoint("Rendering " + name)
	var folder: String = OUT.path_join(name)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = framing
	camera.position = target + offset
	camera.look_at(target)
	world.sync(0.0, [])
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	var frames: int = 1 if stills_only else FPS * 4
	for i in frames:
		var t: float = 0.5 if stills_only else float(i) / float(frames - 1)
		var ease: float = t * t * (3.0 - 2.0 * t)
		var center: Vector3 = target + drift * (ease - 0.5)
		camera.position = center + offset + Vector3(1.1 * (ease - 0.5), 0, 0)
		camera.size = framing * (1.025 - .05 * ease)
		camera.look_at(center)
		world.sync(1.0 / FPS, [])
		sim.events.clear()
		await process_frame
		await RenderingServer.frame_post_draw
		var pixels: Image = root.get_texture().get_image()
		var path: String = folder.path_join("%04d.png" % i)
		if pixels.save_png(path) != OK:
			push_error("Unable to save " + path)
			quit(1)
			return
		if i % 24 == 0: print("TRAILER_FRAME ", name, " ", i, "/", frames)
	assert(int(sim.map.size) != 48)
	evidence.append({"shot":name, "map_mode":str(sim.map.mode), "map_size":int(sim.map.size), "frames":frames, "fps":FPS, "resolution":[1920,1080], "entities":sim.entities.size(), "simulation":"authored deployments, production rendering, camera and visual animation; no match progression"})

func run() -> void:
	checkpoint("Starting showcase")
	stills_only = OS.get_environment("PAPER_FRONT_TRAILER_MOTION") != "1"
	L.initialize("en")
	root.size = Vector2i(1920, 1080)
	root.content_scale_size = root.size
	root.msaa_3d = Viewport.MSAA_2X
	VolumeModels.configure_player_colors(["#347dd0", "#d85140", "#4d977a", "#b982c9"])
	stage = Node3D.new()
	root.add_child(stage)
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("443329")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("b1b8cd")
	settings.ambient_light_energy = .25
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	settings.ssao_enabled = true
	settings.ssao_radius = 1.1
	settings.ssao_intensity = 1.3
	settings.ssao_power = 1.5
	var environment := WorldEnvironment.new()
	environment.environment = settings
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-44, -36, 0)
	sun.light_color = Color("ffdfb3")
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	sun.shadow_bias = .05
	sun.shadow_normal_bias = .8
	sun.directional_shadow_max_distance = 180.0
	stage.add_child(sun)
	camera = Camera3D.new()
	camera.current = true
	camera.far = 500
	stage.add_child(camera)
	camera.make_current()
	checkpoint("Preparing current 320-cell forest battlefield")
	sim = Sim.new()
	sim.setup(RulesLoader.load_rules(), "forest", 73026, "rivet", false, {"vision_enabled":false})
	assert(int(sim.map.size) == 320)
	for id in sim.entities.keys(): sim._kill_entity(id, false)
	var base := Vector2(float(sim.map.starts[0][0]), float(sim.map.starts[0][1]))
	for entry: Array in [["hq", Vector2(-8,-6)], ["power", Vector2(-8,5)], ["factory", Vector2(2,4)], ["repair", Vector2(-2,13)], ["tower", Vector2(12,0)]]:
		sim._spawn(0, "rivet_" + str(entry[0]), base + entry[1], true)
	for point: Vector2 in [Vector2(9,3), Vector2(13,6)]: sim._spawn(0, "rivet_tank", base + point, true)
	for point: Vector2 in [Vector2(7,15), Vector2(12,14), Vector2(17,13)]: sim.debug_spawn_squad(0, "rivet_rifle", base + point, true)
	sim._spawn(0, "rivet_engineer", base + Vector2(4,17), true)
	sim.events.clear()
	create_world()
	var target := Vector3(base.x + 1, MapData.height_at(sim.map, base) + 1, base.y + 3)
	await shot("battlefield", target, Vector3(14, 31, 41), 40, Vector3(4, 0, -1))
	await fresh_sim()
	for team in 4:
		var x: float = 13 + team * 8
		deploy(team, "hq", Vector2(x, 20))
		deploy(team, "tank", Vector2(x - 1.6, 29))
		deploy(team, "heavy_tank", Vector2(x + 1.4, 34))
		sim.debug_spawn_squad(team, FACTIONS[team] + "_rifle", Vector2(x, 39), true)
	create_world()
	await shot("factions", Vector3(25, 1, 29), Vector3(9, 34, 47), 31, Vector3(4, 0, 0))
	await fresh_sim(true)
	deploy(0, "carrier", Vector2(24, 28))
	deploy(1, "ship_frigate", Vector2(36, 24))
	deploy(2, "ship_frigate", Vector2(17, 36))
	deploy(3, "support_ship", Vector2(33, 38))
	for team in [0, 2]:
		var id: int = deploy(team, "helicopter", Vector2(24 + team * 4, 34))
		sim.entities[id].airborne = true
		sim.entities[id].flight_height = 5.0
		sim.entities[id].state = "move"
	create_world()
	await shot("fleet", Vector3(27, 1, 31), Vector3(10, 20, 28), 20, Vector3(-3, 0, 1))
	await fresh_sim()
	for row in 2:
		for col in 3:
			sim.debug_spawn_squad(0, "kestrel_rifle", Vector2(23 + col * 3.6, 24 + row * 3.4), true)
	deploy(0, "tank", Vector2(18, 28))
	deploy(0, "tank", Vector2(35, 25))
	deploy(0, "engineer", Vector2(20, 23))
	deploy(0, "barracks", Vector2(25, 15))
	create_world()
	await shot("squads", Vector3(27, .45, 26), Vector3(5, 15, 26), 17, Vector3(1.8, 0, 0))
	var report := FileAccess.open(OUT.get_base_dir().path_join("capture_manifest.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"renderer":RenderingServer.get_current_rendering_method(),"device":RenderingServer.get_video_adapter_name(),"godot":Engine.get_version_info().string,"scope":"In-engine showcase screenshots; current production PaperWorld with authored deployments and current maps/rules. No AI imagery. No claim of recorded player gameplay.","shots":evidence}, "\t"))
	report.close()
	await clear_world()
	stage.free()
	await process_frame
	quit()
