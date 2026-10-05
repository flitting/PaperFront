extends SceneTree

# Four native 3D viewports render the same current game mesh and materials.
# No bitmap crops, stitched screenshots, replacement foliage or capture lens.
const LANDSCAPE = preload("res://scripts/landscape.gd")
const OUTPUT: String = "res://artifacts/visual_iteration/v44_reference_rebuild/pine_multiview.png"
const SIZE := Vector2i(1440, 1000)
const PANEL_SIZE := Vector2i(684, 402)
const PAPER := Color("eee0c5")

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		push_error("Pine multiview requires real Godot Forward+ rendering")
		quit(2)
		return
	root.size = SIZE
	root.content_scale_size = SIZE
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.msaa_3d = Viewport.MSAA_4X
	var canvas := Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(canvas)
	var background := ColorRect.new()
	background.color = PAPER
	background.position = Vector2.ZERO
	background.size = Vector2(SIZE)
	canvas.add_child(background)
	_label(canvas, "PAINTED PINE  /  CURRENT GAME ASSET", Vector2(28, 15), Vector2(1384, 36), 24, HORIZONTAL_ALIGNMENT_LEFT)
	_label(canvas, "Same tree_1 + trunk mesh • Orthographic views • Matched key-light angle • Forward+", Vector2(28, 49), Vector2(1384, 25), 15, HORIZONTAL_ALIGNMENT_LEFT)
	var builder = LANDSCAPE.new()
	var canopy: ArrayMesh = builder._prop_mesh("tree_1")
	var trunk: ArrayMesh = builder._prop_mesh("trunk")
	var views: Array = [
		{"name": "FRONT", "direction": Vector3.BACK, "position": Vector2(24, 89)},
		{"name": "SIDE", "direction": Vector3.RIGHT, "position": Vector2(732, 89)},
		{"name": "BACK", "direction": Vector3.FORWARD, "position": Vector2(24, 548)},
		{"name": "TOP", "direction": Vector3.UP, "position": Vector2(732, 548)},
	]
	for view: Dictionary in views:
		_add_view(canvas, view, canopy, trunk)
		_label(canvas, str(view.name), view.position + Vector2(0, PANEL_SIZE.y + 7), Vector2(PANEL_SIZE.x, 32), 20, HORIZONTAL_ALIGNMENT_CENTER)
	# The renderer barrier counts actual completed draws after all meshes,
	# viewport cameras, light and canvas layout have been installed.
	for frame: int in range(8):
		await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image.get_size() != SIZE:
		push_error("Unexpected multiview screenshot dimensions: " + str(image.get_size()))
		builder.free()
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT).get_base_dir())
	var error: Error = image.save_png(OUTPUT)
	print("PINE_MULTIVIEW ", OUTPUT, " size=", image.get_size(), " renderer=", RenderingServer.get_current_rendering_method(), " frame_post_draw=8 result=", error_string(error))
	builder.free()
	quit(0 if error == OK else 1)


func _add_view(canvas: Control, view: Dictionary, canopy: ArrayMesh, trunk: ArrayMesh) -> void:
	var holder := SubViewportContainer.new()
	holder.position = view.position
	holder.size = Vector2(PANEL_SIZE)
	canvas.add_child(holder)
	var viewport := SubViewport.new()
	viewport.size = PANEL_SIZE
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	holder.add_child(viewport)
	var scene := Node3D.new()
	viewport.add_child(scene)
	for mesh: ArrayMesh in [canopy, trunk]:
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		scene.add_child(instance)
	var ground := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.86
	disc.bottom_radius = 0.86
	disc.height = 0.035
	disc.radial_segments = 64
	ground.mesh = disc
	ground.position.y = -0.018
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("c1aa80")
	material.roughness = 0.97
	material.metallic_specular = 0.0
	ground.material_override = material
	scene.add_child(ground)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-38, -42, 0)
	# Keep the game's warm key and cool ambient exposure comparable across
	# front/side/back: only the light azimuth follows each viewing direction.
	if str(view.name) != "TOP":
		var direction: Vector3 = view.direction
		light.rotation_degrees.y += rad_to_deg(atan2(direction.x, direction.z))
	light.light_color = Color("ffdbb0")
	light.light_energy = 1.55
	light.shadow_enabled = true
	light.shadow_bias = 0.018
	light.shadow_normal_bias = 0.36
	light.directional_shadow_max_distance = 24.0
	scene.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = PAPER
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b1b8cd")
	environment.environment.ambient_light_energy = 0.20
	environment.environment.ambient_light_sky_contribution = 0.0
	environment.environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment.ssao_enabled = true
	environment.environment.ssao_radius = 0.35
	environment.environment.ssao_intensity = 0.75
	scene.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.70
	camera.near = 0.05
	camera.far = 30.0
	scene.add_child(camera)
	if str(view.name) == "TOP":
		camera.size = 2.28
		camera.position = Vector3(0, 7.0, 0)
		camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	else:
		var target := Vector3(0, 1.04, 0)
		camera.position = target + (view.direction as Vector3) * 7.0 + Vector3.UP * (7.0 * tan(deg_to_rad(10.0)))
		camera.look_at(target)
	camera.current = true


func _label(canvas: Control, text: String, position: Vector2, size: Vector2, font_size: int, alignment: HorizontalAlignment) -> void:
	var label := Label.new()
	label.text = text
	label.position = position
	label.size = size
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color("4e4536"))
	label.add_theme_font_size_override("font_size", font_size)
	canvas.add_child(label)
