extends SceneTree

## Exercise real loading transitions; personal settings and saves stay isolated.
var game: Node
var checks := 0
var failures: Array[String] = []
var watching := false
var loading_frames := 0
var visible_loading_frames := 0
var capture_output := ""

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func monitor() -> void:
	while watching:
		if game.loading:
			loading_frames += 1
			if game.performance_overlay.screen.visible or game.hud.fps_label.is_visible_in_tree():
				visible_loading_frames += 1
		await process_frame

func screenshot(label: String) -> void:
	if capture_output.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(capture_output)
	check(root.get_texture().get_image().save_png(capture_output.path_join(label + ".png")) == OK, "real rendered screenshot saves: " + label)

func check_restored(label: String) -> void:
	check(not game.loading and not game.loading_screen.screen.visible, label + " closes loading")
	check(game.performance_overlay.screen.visible and game.hud.fps_label.is_visible_in_tree(), label + " restores the FPS chip")
	check(not game.performance_overlay.update_timer.is_stopped(), label + " resumes its existing timer")
	check(game.find_children("FPS", "Label", true, false).size() == 1, label + " retains one FPS label")

func screenshot_selected_path() -> void:
	if capture_output.is_empty() or DisplayServer.get_name() == "headless": return
	game.sim.ai_enabled = false
	game.sim.vision_enabled = false
	game.focus = Vector2(24,24)
	game.distance = 40.0
	game.camera_pitch = 30.0
	game.update_camera()
	var id: int = game.sim.debug_spawn(0, "rivet_tank", Vector2(17.5,31.5))
	game.sim.issue([id], "move", Vector2(17.5,2.5))
	for tick in range(16):
		game.sim.step(1.0/30.0)
		await process_frame
		if not game.sim.entities[id].path.is_empty(): break
	check(not game.sim.entities[id].path.is_empty(), "actual selected unit has a planned route for the rendered overlay check")
	game.selected = [id]
	# Normal gameplay resumes this render target after a failed load; this
	# fixture freezes automatic processing, so execute that same recovery once.
	game._process(0.0)
	game.world.sync(0.0,game.selected,{})
	game.hud.refresh(game.sim,game.selected,game.camera,true,"",0.0)
	game.overlay.sim = game.sim
	game.overlay.camera = game.camera
	game.overlay.selection = game.selected
	game.overlay.refresh_overlay()
	await screenshot("selected_path_below_hud")

func run() -> void:
	if OS.get_environment("XDG_DATA_HOME").is_empty():
		push_error("loading_fps_tests requires an isolated XDG_DATA_HOME")
		quit(2)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-loading="): capture_output = argument.trim_prefix("--capture-loading=")
	root.size = Vector2i(1600, 900)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.set_process_input(false)
	game.set_process_unhandled_input(false)
	root.gui_disable_input = true
	AudioServer.set_bus_mute(0, true)
	check_restored("startup")
	watching = true
	monitor()
	await game._begin_loading("正在加载战场", "重锤军团 · 开发战场 · 种子 37")
	check(game.loading_screen.screen.visible and game.loading, "actual loading screen opens")
	check(not game.performance_overlay.screen.visible and not game.hud.fps_label.is_visible_in_tree(), "loading hides both label and complete chip")
	check(game.performance_overlay.update_timer.is_stopped(), "loading stops the timer")
	await screenshot("loading_without_fps")
	await create_timer(.6).timeout
	check(not game.hud.fps_label.is_visible_in_tree() and game.performance_overlay.update_timer.is_stopped(), "the old timer interval cannot make loading FPS reappear")
	await game._finish_loading(false)
	check_restored("cancelled loading")
	check(await game.start_match_with_loading("dev", 37, "rivet"), "real small match loads")
	check_restored("new match")
	game.sim.money[0] = 1234.0
	check(game.sim.save_game(game.SAVE_PATH, game.world.export_visual_memory()).is_empty(), "isolated save fixture writes")
	game.sim.money[0] = 4321.0
	await game.load_game_with_loading()
	check(is_equal_approx(float(game.sim.money[0]), 1234.0), "successful load restores its actual snapshot")
	check_restored("successful saved game")
	var invalid := FileAccess.open(game.SAVE_PATH, FileAccess.WRITE)
	invalid.store_var({"format":"unsupported_fixture","version":1},true); invalid.close()
	await game.load_game_with_loading()
	check_restored("invalid saved game")
	await screenshot("battlefield_with_fps")
	await screenshot_selected_path()
	watching = false
	await process_frame
	check(loading_frames > 5 and visible_loading_frames == 0, "every observed loading frame hides FPS across new/load/failure transitions")
	game.audio.stop_all()
	await create_timer(.15).timeout
	game.quit_pending = true
	game.queue_free()
	await process_frame
	game = null
	invalid = null
	# Release completed asynchronous locals before the renderer/audio shutdown.
	call_deferred("finish")

func finish() -> void:
	await process_frame
	await create_timer(.2).timeout
	print("LOADING_FPS ", JSON.stringify({"checks":checks,"failures":failures,"loading_frames":loading_frames,"visible_loading_frames":visible_loading_frames}))
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
