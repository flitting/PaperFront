extends SceneTree

## Short camera/lens regression probe. Headless validates focus math; the
## optional --capture flag also records two actual Forward+ development views.
var checks: int = 0
var failures: Array[String] = []
var game: Node3D


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("MINIATURE_PROBE_FAIL " + description)


func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.audio.muted = true
	game.start_match("dev", 73026, "rivet", true)
	game.started = false
	game.set_process(false)
	game.set_physics_process(false)
	game.hud.show_menu(false)
	var default_focus: Vector2 = game.focus
	var focuses: Array[Vector2] = [default_focus]
	# Include each actual plateau, so height changes are exercised by the real
	# game's update_camera rather than a separately reimplemented camera pose.
	for expected_height: float in [0.0, 2.0, 4.0, 6.0]:
		var found: bool = false
		for z: int in range(2, int(game.sim.map.size) - 2):
			for x: int in range(2, int(game.sim.map.size) - 2):
				var point := Vector2(x + 0.5, z + 0.5)
				if int(game.sim.map.terrain[z][x]) != MapData.WATER and is_equal_approx(MapData.height_at(game.sim.map, point), expected_height):
					focuses.append(point)
					found = true
					break
			if found:
				break
		check(found, "dev plateau height=" + str(expected_height))
	var poses: int = 0
	var smallest_margin: float = INF
	for point: Vector2 in focuses:
		game.focus = point
		for zoom: float in [20.0, 40.0, 110.0]:
			game.distance = zoom
			for pitch: float in [20.0, 30.0, 45.0]:
				game.camera_pitch = pitch
				for heading: float in [0.0, 1.57, 3.14]:
					game.yaw = heading
					game.update_camera()
					poses += 1
					var attributes: CameraAttributesPractical = game.lens
					var transform: Transform3D = game.camera.get_camera_transform().affine_inverse()
					var ground := Vector3(point.x, MapData.height_at(game.sim.map, point), point.y)
					var label: String = "focus=%s zoom=%.0f pitch=%.0f yaw=%.2f" % [point, zoom, pitch, heading]
					check(attributes.dof_blur_near_enabled and attributes.dof_blur_far_enabled, "both blur enabled " + label)
					check(attributes.dof_blur_near_transition > 0.0 and attributes.dof_blur_far_transition > 0.0, "gradual transitions " + label)
					for height: float in [0.0, 1.0, 2.0, 3.0]:
						var depth: float = -(transform * (ground + Vector3.UP * height)).z
						var margin: float = minf(depth - attributes.dof_blur_near_distance, attributes.dof_blur_far_distance - depth)
						smallest_margin = minf(smallest_margin, margin)
						check(margin >= 0.0, "subject sharp height=%.0f %s" % [height, label])
					check(game.key_light.directional_shadow_max_distance > -(transform * ground).z, "focus receives directional shadows " + label)
	print("MINIATURE_CAMERA_PROBE ", JSON.stringify({"checks": checks, "failures": failures, "poses": poses, "terrain_focuses": focuses.size(), "smallest_clear_margin_m": smallest_margin, "renderer": RenderingServer.get_current_rendering_method()}))
	if "--capture" in OS.get_cmdline_user_args() and failures.is_empty():
		root.unresizable = true
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1920, 1080)
		root.position = Vector2i(32, 32)
		game.focus = default_focus
		game.camera_pitch = 30.0
		game.yaw = 0.0
		await capture_view(40.0, "v10_dev_default")
		await capture_view(20.0, "v10_dev_close")
	quit(0 if failures.is_empty() else 1)


func capture_view(zoom: float, label: String) -> void:
	game.distance = zoom
	game.update_camera()
	game.world.elapsed = 0.0
	game.world.sync(0.0, game.selected, {})
	game.hud.refresh(game.sim, game.selected, game.camera, true, "微缩镜头探查 · 固定帧", 0.0)
	game.hud.fps_label.text = "镜头探查\n固定帧"
	for frame: int in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var path: String = "res://artifacts/visual_iteration/g0/" + label + ".png"
	var screenshot: Image = root.get_texture().get_image()
	var error: Error = screenshot.save_png(path)
	check(error == OK and screenshot.get_size() == Vector2i(1920, 1080), "capture " + label)
	print("MINIATURE_CAMERA_CAPTURE ", ProjectSettings.globalize_path(path), " error=", error, " pixels=", screenshot.get_size())
