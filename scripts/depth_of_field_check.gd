extends RefCounted
## Actual rendered on/off regression, usable in both the source and export.
## Frozen development fixture, not a performance measurement.

static func run(game: Node, output: String) -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Depth-of-field image check requires a display")
		game.quit_game(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	game._flush_render_simulation()
	game.set_process(false)
	game.set_physics_process(false)
	game.audio.muted = true
	game.hud.show_entry(false)
	game.hud.show_menu(false)
	game.battlefield_display.show()
	game.battlefield_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	game.set_debug_visible(false)
	game.get_viewport().gui_disable_input = true
	var cases: Array[Dictionary] = []
	var failures: Array[String] = []
	for config in [{"name":"balanced45", "quality":"balanced", "pitch":45.0, "fullscreen":false}, {"name":"native30", "quality":"native", "pitch":30.0, "fullscreen":false}, {"name":"fullscreen45", "quality":"balanced", "pitch":45.0, "fullscreen":true}]:
		game.get_window().mode = Window.MODE_FULLSCREEN if config.fullscreen else Window.MODE_WINDOWED
		if not config.fullscreen: game.get_window().size = Vector2i(1920, 1080)
		for frame in range(3): await RenderingServer.frame_post_draw
		game.resize_battlefield()
		game.dof_override = -1
		game.set_graphics_quality(config.quality)
		game.set_render_scale(1.0)
		game.camera_pitch = config.pitch
		game.distance = 40.0
		game.yaw = 0.0
		game.update_camera()
		game.world.elapsed = 0.0
		game.world.sync(0.0, [], {})
		game.hud.refresh(game.sim, [], game.camera, true, "", 0.0)
		var enabled_image: Image
		var disabled_image: Image
		var enabled_focus: Dictionary
		for enabled: bool in [true, false]:
			game.set_depth_of_field(enabled)
			for frame in range(8): await RenderingServer.frame_post_draw
			var capture: Image = game.get_viewport().get_texture().get_image()
			var filename: String = config.name + ("_on.png" if enabled else "_off.png")
			if capture.save_png(output.path_join(filename)) != OK: failures.append("Cannot save " + filename)
			if enabled:
				enabled_image = capture
				enabled_focus = game.LENS.metadata(game.lens)
			else: disabled_image = capture
		# Static terrain in the near/far bands must visibly change. The centre
		# and opaque HUD must stay sharp; avoid the animated water in the centre.
		var far_delta: float = difference(enabled_image, disabled_image, Rect2(.40, .10, .45, .12))
		var near_delta: float = difference(enabled_image, disabled_image, Rect2(.32, .86, .28, .09))
		var center_delta: float = difference(enabled_image, disabled_image, Rect2(.34, .43, .17, .13))
		var hud_delta: float = difference(enabled_image, disabled_image, Rect2(.03, .025, .28, .035))
		if far_delta < 0.5: failures.append(config.name + " far blur has no visible effect")
		if near_delta < 0.5: failures.append(config.name + " near blur has no visible effect")
		if center_delta > 0.5: failures.append(config.name + " focused scene became blurred")
		if hud_delta > 0.01: failures.append(config.name + " HUD changed when toggling DOF")
		cases.append({"name":config.name, "quality":config.quality, "pitch":config.pitch, "pixels":[enabled_image.get_width(), enabled_image.get_height()], "far_mean_difference_255":far_delta, "near_mean_difference_255":near_delta, "center_mean_difference_255":center_delta, "hud_mean_difference_255":hud_delta, "enabled_focus":enabled_focus})
	var model_cases: Array[Dictionary] = []
	game.get_window().mode = Window.MODE_WINDOWED
	game.get_window().size = Vector2i(1920, 1080)
	for faction: String in ["rivet", "kestrel", "iron", "sky"]:
		game.start_match("dev", 73026, faction, false)
		game.hud.show_entry(false)
		game.hud.show_menu(false)
		game.battlefield_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		game.set_graphics_quality("performance")
		game.set_depth_of_field(false) # Inspect authored details without blur.
		game.resize_battlefield()
		var hq: int = -1
		for entity in game.sim.entities.values():
			if entity.team == 0 and str(entity.spec).ends_with("_hq"): hq = entity.id; break
		if hq < 0: failures.append("Missing " + faction + " headquarters"); continue
		game.focus = game.sim.entities[hq].pos
		game.distance = 20.0
		game.camera_pitch = 30.0
		game.yaw = 0.4
		game.update_camera()
		game.world.sync(0.0, [])
		game.hud.refresh(game.sim, [], game.camera, true, "", 0.0)
		for frame in range(8): await RenderingServer.frame_post_draw
		var model: Dictionary = game.world.models[hq]
		var triangles: int = 0
		var full: bool = true
		for part in model.render_parts:
			full = full and part.performance_batch.multi.mesh == part.node.mesh and part.performance_batch.node.material_override == part.node.material_override
			for surface in range(part.node.mesh.get_surface_count()):
				var indices: int = part.node.mesh.surface_get_array_index_len(surface)
				triangles += (indices if indices > 0 else part.node.mesh.surface_get_array_len(surface)) / 3
		if not full: failures.append(faction + " headquarters lost authored geometry/material")
		if game.get_viewport().get_texture().get_image().save_png(output.path_join("hq_" + faction + ".png")) != OK: failures.append("Cannot save headquarters " + faction)
		model_cases.append({"faction":faction, "quality":"performance", "distance":20, "full_mesh_and_material":full, "triangles":triangles})
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/performance_build_manifest.json"))
	var report := {"passed":failures.is_empty(), "failures":failures, "scope":"Frozen real Forward+ scene, on/off pixels and full headquarters models; not an FPS benchmark", "cases":cases, "model_cases":model_cases, "runtime_identity":manifest.get("runtime_identity", "") if manifest is Dictionary else ""}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("DEPTH_OF_FIELD_RENDER ", JSON.stringify(report))
	game.quit_game(0 if failures.is_empty() else 1)

static func difference(a: Image, b: Image, region: Rect2) -> float:
	var total: float = 0.0
	var samples: int = 0
	for y in range(int(region.position.y * a.get_height()), int(region.end.y * a.get_height()), 2):
		for x in range(int(region.position.x * a.get_width()), int(region.end.x * a.get_width()), 2):
			var left: Color = a.get_pixel(x, y)
			var right: Color = b.get_pixel(x, y)
			total += absf(left.r-right.r) + absf(left.g-right.g) + absf(left.b-right.b)
			samples += 3
	return total * 255.0 / maxi(samples, 1)
