extends SceneTree

# Run with graphical rendering and isolated XDG_DATA_HOME / XDG_CONFIG_HOME.
# Export templates do not support --script; use their native menu-smoke checks.
var game: Node
var failures: Array[String] = []
var cases: Array[Dictionary] = []
var active_case: Dictionary = {}
var output_dir: String = ProjectSettings.globalize_path("res://artifacts/ui_loading_fix")
var test_label: String = "source"
var previous_sim_id: int = -1
var previous_sim_time: float = 0.0
var previous_progress: float = -1.0
var last_observed_usec: int = 0
var screenshot_saved: bool = false
var beginning_usec: int = 0

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index in range(args.size() - 1):
		if args[index] == "--test-output": output_dir = args[index + 1]
		if args[index] == "--test-label": test_label = args[index + 1]
	DirAccess.make_dir_recursive_absolute(output_dir)
	root.size = Vector2i(1440, 810)
	RenderingServer.frame_post_draw.connect(_observe_rendered_frame)
	call_deferred("run")

func run() -> void:
	beginning_usec = Time.get_ticks_usec()
	_check(DisplayServer.get_name() != "headless", "Graphical display is required")
	var isolated_data: String = OS.get_environment("XDG_DATA_HOME")
	_check(isolated_data.begins_with("/tmp/") and OS.get_user_data_dir().begins_with(isolated_data), "XDG user data must be isolated under /tmp")
	if not failures.is_empty():
		_finish()
		return
	var scene: PackedScene = load("res://main.tscn")
	if scene == null:
		_check(false, "Main scene could not load")
		_finish()
		return
	game = scene.instantiate()
	root.add_child(game)
	current_scene = game
	await _draw_frames(2)
	if game.get("sim") == null or game.get("hud") == null:
		_check(false, "Main scene did not initialize")
		_finish()
		return
	game.pointer_in_window = false
	game.audio.muted = true
	game.hud.show_entry(false)
	game.hud.show_menu(true)
	_check(game.hud.faction_buttons.size() == 4, "Menu must show four faction cards")
	_check(game.hud.selected_map() == "mountains640", "Fresh menu must default to mountains640")
	await _draw_frames(2)
	_capture("faction_menu")
	for faction: String in ["kestrel", "rivet", "iron", "sky"]:
		game.hud.show_menu(true)
		var card: Button = game.hud.faction_buttons[faction]
		card.pressed.emit()
		_check(game.hud.selected_faction() == faction, "Faction card must select " + faction)
		_check(card.button_pressed, "Chosen faction card must be pressed: " + faction)
		var pressed_count: int = 0
		for button: Button in game.hud.faction_buttons.values():
			if button.button_pressed: pressed_count += 1
		_check(pressed_count == 1, "Exactly one faction card must be selected")
		game.hud.select_map("dev")
		_begin_case("dev_" + faction)
		var success: bool = await game.start_match_with_loading("dev", 73026, game.hud.selected_faction())
		_validate_match(success, "dev", faction, 48)
		_end_case()
		game.pve_paused = true
		await _draw_frames(1)
	_begin_case("restart_dev_sky")
	await game.handle_action("restart", null)
	_validate_match(true, "dev", "sky", 48)
	_end_case()
	game.pve_paused = true
	await _draw_frames(1)
	game.sim.money[0] = 1234.0
	await game.handle_action("save", null)
	_check(FileAccess.file_exists("user://skirmish_v1.pfront"), "Save action must create isolated save file")
	game.sim.money[0] = 4321.0
	_begin_case("load_saved_dev_sky")
	await game.handle_action("load", null)
	_validate_match(true, "dev", "sky", 48)
	_check(is_equal_approx(float(game.sim.money[0]), 1234.0), "Load must restore saved economy")
	_end_case()
	game.pve_paused = true
	await _draw_frames(1)
	game.hud.show_menu(true)
	game.hud.select_map("mountains640")
	game.hud.faction_buttons.rivet.pressed.emit()
	_begin_case("default640_rivet")
	var large_success: bool = await game.start_match_with_loading("mountains640", 73026, game.hud.selected_faction())
	_validate_match(large_success, "mountains640", "rivet", 640)
	active_case.terrain_cache_hit = bool(game.world.landscape.stats.get("terrain_cache_hit", false))
	active_case.terrain_disk_cache_hit = bool(game.world.landscape.stats.get("terrain_disk_cache_hit", false))
	active_case.terrain_cache_source = str(game.world.landscape.stats.get("terrain_cache_source", ""))
	_check(bool(active_case.terrain_cache_hit), "Default640 must reuse the baked terrain cache")
	_end_case()
	game.pve_paused = true
	await _draw_frames(2)
	_capture("default640_ready")
	_finish()

func _begin_case(name: String) -> void:
	active_case = {"name": name, "started_usec": Time.get_ticks_usec(), "rendered_loading_frames": 0, "input_checks": 0, "max_loading_frame_gap_ms": 0.0, "samples": [], "stages": []}
	previous_sim_id = -1
	previous_progress = -1.0
	last_observed_usec = 0
	screenshot_saved = false
	print("LOADING_CASE_BEGIN ", test_label, " ", name)

func _end_case() -> void:
	active_case.duration_ms = float(Time.get_ticks_usec() - int(active_case.started_usec)) / 1000.0
	active_case.erase("started_usec")
	_check(int(active_case.rendered_loading_frames) >= 5, str(active_case.name) + " must render several loading frames")
	_check(active_case.stages.size() >= 4, str(active_case.name) + " must show multiple loading stages")
	_check(previous_progress >= 99.9, str(active_case.name) + " must render 100% progress")
	cases.append(active_case.duplicate(true))
	print("LOADING_CASE_DONE ", JSON.stringify(active_case))
	active_case = {}

func _observe_rendered_frame() -> void:
	if active_case.is_empty() or not is_instance_valid(game) or not bool(game.get("loading")): return
	var screen = game.loading_screen
	_check(screen.screen.visible, str(active_case.name) + " loading screen must be visible")
	var fraction: float = float(screen.progress_bar.value)
	var stage: String = str(screen.stage_label.text)
	_check(fraction + 0.01 >= previous_progress, str(active_case.name) + " progress must be monotonic")
	var now: int = Time.get_ticks_usec()
	if last_observed_usec > 0:
		active_case.max_loading_frame_gap_ms = maxf(float(active_case.max_loading_frame_gap_ms), float(now - last_observed_usec) / 1000.0)
	last_observed_usec = now
	active_case.rendered_loading_frames += 1
	if not active_case.stages.has(stage): active_case.stages.append(stage)
	if not is_equal_approx(fraction, previous_progress):
		active_case.samples.append({"frame": Engine.get_frames_drawn(), "percent": fraction, "stage": stage})
	previous_progress = fraction
	if game.sim != null:
		var sim_id: int = game.sim.get_instance_id()
		var sim_time: float = float(game.sim.time)
		if sim_id == previous_sim_id:
			_check(is_equal_approx(sim_time, previous_sim_time), str(active_case.name) + " simulation must stay frozen during loading")
		previous_sim_id = sim_id
		previous_sim_time = sim_time
		game._physics_process(0.5)
		game._process(0.5)
		_check(is_equal_approx(float(game.sim.time), sim_time), str(active_case.name) + " loading must block simulation processing")
	var was_paused: bool = bool(game.pve_paused)
	var was_dragging: bool = bool(game.dragging)
	var previous_distance: float = float(game.distance)
	var pause_key := InputEventKey.new()
	pause_key.keycode = KEY_P
	pause_key.pressed = true
	game._unhandled_input(pause_key)
	game.handle_action("pause", null)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	mouse.position = Vector2(root.size) * 0.5
	game._unhandled_input(mouse)
	mouse.button_index = MOUSE_BUTTON_WHEEL_UP
	game._unhandled_input(mouse)
	_check(game.pve_paused == was_paused and game.dragging == was_dragging and is_equal_approx(float(game.distance), previous_distance), str(active_case.name) + " loading must block keyboard/mouse/actions")
	active_case.input_checks += 1
	if str(active_case.name) == "default640_rivet" and not screenshot_saved and fraction >= 35.0 and fraction < 94.0:
		_capture("default640_loading")
		screenshot_saved = true

func _validate_match(success: bool, mode: String, faction: String, size: int) -> void:
	_check(success, str(active_case.name) + " match must start successfully")
	_check(not game.loading and not game.loading_screen.screen.visible, str(active_case.name) + " loading screen must close")
	_check(game.started and game.hud.is_started, str(active_case.name) + " match must become active")
	_check(game.world != null and game.world.landscape != null, str(active_case.name) + " world must be initialized")
	_check(str(game.sim.map.mode) == mode and int(game.sim.map.size) == size and int(game.sim.map.seed) == 73026, str(active_case.name) + " map/seed must match the chosen setup")
	_check(str(game.sim.factions[0]) == faction, str(active_case.name) + " simulation faction must match the card")
	var own_hq: bool = false
	for entity: Dictionary in game.sim.entities.values():
		if int(entity.team) == 0 and str(entity.spec) == faction + "_hq": own_hq = true
	_check(own_hq, str(active_case.name) + " chosen faction headquarters must exist")
	_check(game.battlefield_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS, str(active_case.name) + " battlefield rendering must resume")

func _check(condition: bool, message: String) -> void:
	if condition or failures.has(message): return
	failures.append(message)
	print("LOADING_TEST_FAILURE ", message)

func _capture(name: String) -> void:
	var image: Image = root.get_texture().get_image()
	if image == null or image.is_empty():
		_check(false, "Cannot capture " + name)
		return
	_check(image.save_png(output_dir.path_join(test_label + "_" + name + ".png")) == OK, "Cannot save screenshot " + name)

func _draw_frames(count: int) -> void:
	for index in range(count): await RenderingServer.frame_post_draw

func _finish() -> void:
	var report: Dictionary = {"label": test_label, "renderer": RenderingServer.get_current_rendering_method(), "display": DisplayServer.get_name(), "elapsed_ms": float(Time.get_ticks_usec() - beginning_usec) / 1000.0, "user_data_dir": OS.get_user_data_dir(), "cases": cases, "failures": failures, "passed": failures.is_empty()}
	var file: FileAccess = FileAccess.open(output_dir.path_join(test_label + "_loading_integration.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	print("LOADING_INTEGRATION_RESULT ", JSON.stringify(report))
	if is_instance_valid(game): game._flush_render_simulation()
	quit(0 if failures.is_empty() else 1)
