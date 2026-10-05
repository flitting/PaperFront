extends SceneTree

var game: Node
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("DOF_TEST " + message)

func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game._flush_render_simulation()
	game.set_process(false)
	game.set_physics_process(false)
	game.audio.muted = true
	game.dof_override = -1
	game.set_graphics_quality("balanced")
	for size: Vector2i in [Vector2i(1920, 1080), Vector2i(3072, 1920), Vector2i(2560, 1080)]:
		root.size = size
		await process_frame
		game.resize_battlefield()
		for zoom: float in [20.0, 40.0, 110.0]:
			game.distance = zoom
			for pitch: float in [20.0, 30.0, 45.0]:
				game.camera_pitch = pitch
				for heading: float in [0.0, 1.57, 3.14]:
					game.yaw = heading
					game.update_camera()
					check_visible_blur("%s zoom=%s pitch=%s yaw=%s" % [size, zoom, pitch, heading])
	# Preset changes must update the checkbox. Explicit player choices survive
	# camera changes, a new match, preset changes and settings reload.
	game.set_graphics_quality("performance")
	check(not game.lens.dof_blur_far_enabled and not game.dof_toggle.button_pressed, "performance preset and checkbox agree")
	game.dof_toggle.button_pressed = true
	game.update_camera()
	check(game.lens.dof_blur_near_enabled and game.lens.dof_blur_far_enabled, "player can enable DOF in performance preset")
	game.set_graphics_quality("balanced")
	game.set_graphics_quality("performance")
	check(game.lens.dof_blur_far_enabled and game.dof_toggle.button_pressed, "explicit on survives preset changes")
	game.start_match("dev", 73026, "rivet", false)
	check(game.lens.dof_blur_far_enabled and game.dof_toggle.button_pressed, "explicit on survives new match")
	game.dof_override = -1
	game.load_preferences()
	check(game.dof_override == 1 and game.lens.dof_blur_far_enabled and game.dof_toggle.button_pressed, "saved on restores actual effect and checkbox")
	game.dof_toggle.button_pressed = false
	game.set_graphics_quality("native")
	game.update_camera()
	check(not game.lens.dof_blur_far_enabled and not game.lens.dof_blur_near_enabled, "explicit off survives preset and camera changes")
	game.dof_override = -1
	game.load_preferences()
	check(game.dof_override == 0 and not game.dof_toggle.button_pressed and not game.lens.dof_blur_far_enabled, "saved off restores actual effect and checkbox")
	# Leave the isolated test preferences at the backward-compatible default.
	game.dof_override = -1
	game.set_graphics_quality("balanced")
	game.save_preferences()
	print("DEPTH_OF_FIELD_TESTS ", JSON.stringify({"checks": checks, "failures": failures}))
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func check_visible_blur(label: String) -> void:
	var target := Vector3(game.focus.x, MapData.height_at(game.sim.map, game.focus), game.focus.y)
	var view: Transform3D = game.camera.get_camera_transform().affine_inverse()
	for height: float in [0.0, 1.0, 2.0, 3.0]:
		var depth: float = -(view * (target + Vector3.UP * height)).z
		check(depth > game.lens.dof_blur_near_distance and depth < game.lens.dof_blur_far_distance, "focused subject stays sharp " + label)
	var plane := Plane(Vector3.UP, target.y + 1.0)
	var viewport_size: Vector2 = game.battlefield_viewport.get_visible_rect().size
	for fraction: float in [0.15, 0.90]:
		var pixel := Vector2(viewport_size.x * 0.5, viewport_size.y * fraction)
		var hit: Variant = plane.intersects_ray(game.camera.project_ray_origin(pixel), game.camera.project_ray_normal(pixel))
		check(hit != null, "visible focus-plane ray " + label)
		if hit == null: continue
		var depth: float = -(view * (hit as Vector3)).z
		check(depth > game.lens.dof_blur_far_distance if fraction < 0.5 else depth < game.lens.dof_blur_near_distance, "visible terrain reaches blur zone " + label)
