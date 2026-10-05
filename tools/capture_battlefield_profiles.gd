extends SceneTree
## GPU evidence without starting a match or importing the editor project.
## godot --path . --script res://tools/capture_battlefield_profiles.gd -- city
const MAP = preload("res://scripts/map_data.gd")
const SIM = preload("res://scripts/simulation.gd")
const LANDSCAPE = preload("res://scripts/landscape.gd")
const MODELS = preload("res://scripts/city_environment_models.gd")
var viewport: SubViewport
var camera: Camera3D
var scene: Node3D
var landscape: Node3D
func _initialize() -> void:
	call_deferred("run")
func capture(path: String) -> void:
	for frame: int in 8: await process_frame
	RenderingServer.force_draw()
	var error: int = viewport.get_texture().get_image().save_png(path)
	print("PROFILE_CAPTURE ", path, " ", error)
func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var mode: String = args[0] if not args.is_empty() else "city"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/expansion_v5"))
	viewport = SubViewport.new()
	viewport.size = Vector2i(1600, 1000)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(viewport)
	scene = Node3D.new()
	viewport.add_child(scene)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("ddd4bc")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("fff1d0")
	environment.ambient_light_energy = .66
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	scene.add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("fff0d7")
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 420
	sun.rotation_degrees = Vector3(-57, -32, 0)
	scene.add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 1000
	scene.add_child(camera)
	var sim = SIM.new()
	sim.map = MAP.generate(mode, 7, {"players": 3})
	sim.ruins = sim.map.ruins.duplicate(true)
	for mine: Dictionary in sim.map.mines:
		var record: Dictionary = mine.duplicate(true)
		record.pos = Vector2(float(mine.pos[0]), float(mine.pos[1]))
		sim.mines.append(record)
	landscape = LANDSCAPE.build(sim)
	scene.add_child(landscape)
	camera.size = 358
	camera.position = Vector3(160, 385, 406)
	camera.look_at(Vector3(160, 0, 160))
	await capture("res://artifacts/expansion_v5/stage3_%s_overview.png" % mode)
	if mode in ["city", "random_city"]:
		var house: Dictionary = sim.ruins.filter(func(r): return r.has("archetype"))[20]
		var point: Vector2 = house.pos + Vector2(-.5, -2.0)
		camera.size = 30
		camera.position = Vector3(point.x + 16, 27, point.y + 30)
		camera.look_at(Vector3(point.x, 1.2, point.y))
		landscape.sync_environment(9.0)
		await capture("res://artifacts/expansion_v5/stage3_%s_street.png" % mode)
	else:
		var harbor: Dictionary = sim.map.harbors[0]
		var point: Vector2 = harbor.shore_pos
		camera.size = 34
		camera.position = Vector3(point.x + 23, 29, point.y + 29)
		camera.look_at(Vector3(point.x, -1.3, point.y))
		await capture("res://artifacts/expansion_v5/stage3_%s_coast.png" % mode)
	print("PROFILE_RENDER_STATS ", mode, " ", str(landscape.stats))
	scene.queue_free()
	await process_frame
	quit()
