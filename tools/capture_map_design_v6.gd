extends SceneTree

# GPU comparison evidence for each authored battlefield.
# godot --path . --script res://tools/capture_map_design_v6.gd -- city
const MAP = preload("res://scripts/map_data.gd")
const SIM = preload("res://scripts/simulation.gd")
const LANDSCAPE = preload("res://scripts/landscape.gd")
const LANDMARKS := {
	"city": Vector2(188, 128), "random_city": Vector2(169, 166),
	"forest": Vector2(205, 130), "desert": Vector2(194, 169),
	"snow": Vector2(205, 148), "islands": Vector2(151, 141),
}
var viewport: SubViewport
var camera: Camera3D
var scene: Node3D

func _initialize() -> void:
	call_deferred("run")

func _save(path: String) -> void:
	camera.make_current()
	camera.force_update_transform()
	for frame: int in 5: await process_frame
	RenderingServer.force_draw()
	await RenderingServer.frame_post_draw
	var image: Image = viewport.get_texture().get_image()
	var error: Error = image.save_png(path)
	print("V6_CAPTURE ", path, " error=", error, " size=", image.get_size(),
		" camera=", camera.global_transform, " current=", viewport.get_camera_3d() == camera)

func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var mode: String = str(args[0]) if not args.is_empty() else "city"
	var seed: int = int(args[1]) if args.size() > 1 else 7
	var directory: String = "res://artifacts/map_design_v6/%s" % mode
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	viewport = SubViewport.new()
	viewport.size = Vector2i(1600, 1600)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(viewport)
	scene = Node3D.new()
	viewport.add_child(scene)
	var lighting := Environment.new()
	lighting.background_mode = Environment.BG_COLOR
	lighting.background_color = Color("c7d2d0")
	lighting.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	lighting.ambient_light_color = Color("fff2dd")
	lighting.ambient_light_energy = .65
	lighting.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment := WorldEnvironment.new()
	world_environment.environment = lighting
	scene.add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("fff0d7")
	sun.light_energy = 1.45
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 430
	sun.rotation_degrees = Vector3(-57, -32, 0)
	scene.add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 1100
	scene.add_child(camera)
	camera.make_current()
	var sim = SIM.new()
	sim.map = MAP.generate(mode, seed, {"players":4})
	sim.ruins = sim.map.get("ruins", []).duplicate(true)
	for mine: Dictionary in sim.map.get("mines", []):
		var record: Dictionary = mine.duplicate(true)
		record.pos = Vector2(float(mine.pos[0]), float(mine.pos[1]))
		sim.mines.append(record)
	for bridge: Dictionary in sim.map.get("bridges", []):
		sim.bridges.append({"id":int(bridge.id), "bounds":bridge.bounds.duplicate(),
			"heads":bridge.heads.duplicate(), "hp":1200.0, "repair_progress":0.0,
			"alive":true, "naval_clearance":float(bridge.get("naval_clearance", 0.0))})
	var landscape = LANDSCAPE.build(sim)
	scene.add_child(landscape)
	camera.size = 326
	camera.position = Vector3(160, 485, 160)
	camera.look_at(Vector3(160, 0, 160), Vector3(0, 0, -1))
	await _save(directory + "/topdown.png")
	# Keep the full battlefield in frame while showing the sides of its terrain
	# and landmarks. The former steep view read almost like the minimap.
	camera.size = 445
	camera.position = Vector3(420, 350, 440)
	camera.look_at(Vector3(160, 0, 160))
	await _save(directory + "/panorama.png")
	viewport.size = Vector2i(1600, 1000)
	var landmark: Vector2 = LANDMARKS.get(mode, Vector2(160, 160))
	camera.size = 64 if mode == "islands" else 45
	camera.position = Vector3(landmark.x + 35, 43, landmark.y + 46) if mode == "islands" else Vector3(landmark.x + 28, 34, landmark.y + 37)
	camera.look_at(Vector3(landmark.x, 7.0 if mode == "islands" else 3.0, landmark.y))
	await _save(directory + "/landmark.png")
	camera.size = 38 if mode == "islands" else 24
	camera.position = Vector3(landmark.x + 23, 26, landmark.y + 34) if mode == "islands" else Vector3(landmark.x + 13, 15, landmark.y + 24)
	camera.look_at(Vector3(landmark.x, 6.5 if mode == "islands" else 3.5, landmark.y))
	await _save(directory + "/street.png")
	print("V6_CAPTURE_STATS ", mode, " ", str(landscape.stats))
	scene.queue_free()
	await process_frame
	quit()
