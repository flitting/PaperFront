extends SceneTree

## Run: godot --path . --script res://scripts/campaign_capture.gd -- /tmp/campaign
## Writes three real in-engine screenshots for layout and UI review.
func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var prefix: String = args[0] if not args.is_empty() else "user://campaign"
	root.size = Vector2i(1440, 900)
	var error: Error = change_scene_to_file("res://main.tscn")
	if error != OK:
		push_error("Cannot open main scene: " + error_string(error))
		quit(1)
		return
	for frame: int in 3: await process_frame
	var game: Node3D = current_scene
	if not game.start_match("campaign", 1, "kestrel", true):
		push_error("Campaign startup failed")
		quit(2)
		return
	game.sim.ai_enabled = false
	game.hud.show_entry(false)
	game.hud.show_menu(false)
	var views: Array[Dictionary] = [
		{"name":"base", "focus":Vector2(78, 171), "distance":82.0, "yaw":.13},
		{"name":"bridge", "focus":Vector2(160, 158), "distance":92.0, "yaw":.12},
		{"name":"overview", "focus":Vector2(160, 148), "distance":260.0, "yaw":0.0}
	]
	var outputs: Array[String] = []
	for view: Dictionary in views:
		game.focus = view.focus
		game.distance = view.distance
		game.yaw = view.yaw
		game.update_camera()
		for frame: int in 12: await process_frame
		await RenderingServer.frame_post_draw
		var path: String = prefix + "_" + view.name + ".png"
		var result: Error = root.get_texture().get_image().save_png(path)
		if result != OK:
			push_error("Campaign capture failed for " + path + ": " + error_string(result))
			quit(3)
			return
		outputs.append(path)
	print("CAMPAIGN_CAPTURE ", JSON.stringify({"files":outputs,"map_valid":game.sim.map.valid,
		"mission":game.sim.campaign_controller.view_state()}))
	quit(0)
