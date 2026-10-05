extends SceneTree

# Diagnostic only: normal gameplay/G0 captures remain the visual acceptance.
const Landscape = preload("res://scripts/landscape.gd")

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	root.size = Vector2i(1200, 760)
	root.msaa_3d = Viewport.MSAA_2X
	var scene := Node3D.new()
	root.add_child(scene)
	var landscape = Landscape.new()
	scene.add_child(landscape)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("443329")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b1b8cd")
	environment.ambient_light_energy = 0.20
	environment.ambient_light_sky_contribution = 0.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.ssao_enabled = true
	environment.ssao_radius = 1.1
	environment.ssao_intensity = 1.50
	environment.ssao_power = 1.6
	var world := WorldEnvironment.new()
	world.environment = environment
	scene.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-38, -42, 0)
	light.light_color = Color("ffdbb0")
	light.light_energy = 1.55
	light.shadow_enabled = true
	scene.add_child(light)
	var floor_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(8.8, 0.2, 4.0)
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color("b79b73")
	paper.roughness = 1.0
	box.material = paper
	floor_mesh.mesh = box
	floor_mesh.position.y = -0.1
	scene.add_child(floor_mesh)
	for variant: int in 3:
		var tree := MeshInstance3D.new()
		tree.mesh = landscape._prop_mesh("tree_%d" % variant)
		tree.position.x = (variant - 1) * 2.4
		tree.rotation.y = variant * 0.8
		scene.add_child(tree)
		var trunk := MeshInstance3D.new()
		trunk.mesh = landscape._prop_mesh("trunk")
		trunk.position.x = tree.position.x
		scene.add_child(trunk)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 9.0
	camera.position = Vector3(3.0, 4.8, 9.0)
	scene.add_child(camera)
	camera.look_at(Vector3(0, 0.85, 0))
	camera.current = true
	for frame: int in 8:
		await RenderingServer.frame_post_draw
	var path: String = "res://artifacts/visual_iteration/v44_reference_rebuild/tree_study_b.png"
	var error: Error = root.get_texture().get_image().save_png(path)
	print("TREE_STUDY ", path, " error=", error)
	quit(error)
