extends SceneTree

## Real main-scene GUI input, preferences, save replacement and end-screen flow.
## Uses only the small dev map. Existing user files are preserved even if this
## test is run outside the documented isolated XDG test directory.
const Rules = preload("res://scripts/rules_loader.gd")
const Sim = preload("res://tests/rule_test_simulation.gd")

var game
var checks := 0
var failures: Array[String] = []
var actions: Array[Dictionary] = []
var saved_mix: Dictionary = {}
var file_backups: Dictionary = {}
var monitor_active := false
var loading_samples := 0
var loading_audio_errors: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures.append(description)

func frames(count: int = 3) -> void:
	for frame: int in count: await process_frame

func push_click_at(point: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		root.push_input(event, true)

func click_at(point: Vector2) -> void:
	push_click_at(point)
	await frames()

func show_control(control: Control) -> void:
	var ancestor: Node = control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(control)
		ancestor = ancestor.get_parent()
	await frames()

func click(control: Control) -> void:
	await show_control(control)
	await click_at(control.get_global_rect().get_center())

func key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		root.push_input(event, true)
	await frames()

func button_named(panel: Node, caption: String) -> Button:
	for candidate: Node in panel.find_children("", "Button", true, false):
		if candidate.text == caption: return candidate
	return null

func click_named(panel: Node, caption: String) -> void:
	var button := button_named(panel, caption)
	check(button != null, "visible flow exposes action: " + caption)
	if button != null: await click(button)

func check_fps_visible(screen_name: String) -> void:
	var fps: Label = game.hud.fps_label
	check(game.performance_overlay.layer == 7 and game.performance_overlay.is_ancestor_of(fps) and not game.debug_panel.is_ancestor_of(fps), "FPS stays on its independent top overlay: " + screen_name)
	check(fps.is_visible_in_tree() and fps.text.ends_with(" FPS") and root.get_visible_rect().encloses(fps.get_global_rect()), "FPS remains visible within the window: " + screen_name)
	var readouts := 0
	for candidate: Label in game.find_children("", "Label", true, false):
		if candidate.name == "FPS" or candidate.text.contains("FPS"): readouts += 1
	var top_layers := 0
	for candidate: CanvasLayer in game.find_children("", "CanvasLayer", true, false):
		if candidate.layer == 7: top_layers += 1
	check(readouts == 1 and top_layers == 1, "Every screen shares exactly one FPS readout and CanvasLayer 7: " + screen_name)

func check_fps_while_paused() -> void:
	var original_pause: bool = paused
	paused = true
	# Force the next sample to redraw even if the measured integer FPS is stable.
	game.performance_overlay._last_fps = -1
	game.hud.fps_label.text = "__waiting_for_paused_fps__"
	await create_timer(0.7, true, false, true).timeout
	check(game.hud.fps_label.text.ends_with(" FPS"), "The real FPS timer refreshes while the SceneTree is paused")
	check_fps_visible("paused battlefield")
	paused = original_pause

func preserve_file(path: String) -> void:
	file_backups[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null

func restore_files() -> void:
	for path: String in file_backups:
		if file_backups[path] == null:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		else:
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file != null: file.store_buffer(file_backups[path]); file.close()

func new_game() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.hud.action.connect(func(kind: String, value: Variant): actions.append({"kind":kind,"value":value}))
	await frames()

func expect_audio(scene: String) -> void:
	game._process(0.0)
	for step: int in 6: game.audio.music._process(0.5)
	check(game.audio_scene == scene and game.audio.music.requested_scene == scene and game.audio.music.scene == scene, "main flow requests and reaches music scene: " + scene)
	if scene == "silent":
		check(not game.audio.music.player.playing, "silent scene stops PCM playback")
	else:
		var expected_track: String = game.audio.music.track_for_map(str(game.sim.map.mode)) if scene == "battle" else scene
		check(game.audio.music.requested_track == expected_track and game.audio.music.active_track == expected_track and game.audio.music.tracks.has(expected_track) and game.audio.music.player.stream == game.audio.music.tracks.get(expected_track) and game.audio.music.player.playing, "music scene plays its actual bundled map-specific PCM: " + expected_track)

func monitor_loading() -> void:
	while monitor_active:
		if game.loading:
			loading_samples += 1
			if loading_samples == 1: check_fps_visible("loading overlay")
			if game.audio.music.requested_scene != "silent":
				loading_audio_errors.append(str(game.audio.music.requested_scene))
		await process_frame

func check_preferences() -> void:
	check(game.hud.entry_menu.visible and not game.started, "clean startup shows entry before a match")
	check(not game.debug_available and not game.hud.debug_menu_enabled and game.hud.map_option.item_count == 6, "clean startup disables optional debug and hides its dev battlefield")
	check_fps_visible("main entry")
	check(is_equal_approx(game.render_scale, 1.0) and game.graphics_quality == "balanced", "clean startup preserves native 3D scale and default quality")
	check(game.lens.dof_blur_near_enabled and game.key_light.shadow_enabled and game.environment.ssao_enabled, "clean startup keeps default depth, shadows and SSAO")
	expect_audio("menu")
	await click_named(game.hud.entry_menu, "开始战局")
	check(game.hud.menu.visible, "the actual entry action opens new-match setup")
	check_fps_visible("new-match setup")
	await key(KEY_ESCAPE)
	check(game.hud.entry_menu.visible and not game.hud.menu.visible, "Escape returns from new-match setup to the entry")
	await click_named(game.hud.entry_menu, "设置 · 声音与画面")
	check(game.hud.settings is PaperSettings and game.hud.settings.visible, "real entry settings button opens the PaperSettings sheet")
	check_fps_visible("entry settings")
	check(game.hud.settings.resolution.selected == 0, "settings reports 100 percent native rendering by default")
	check(not game.hud.settings.debug_enabled.button_pressed, "the settings sheet reports debug disabled by default")
	for control: Control in [game.hud.settings.quality, game.hud.settings.resolution, game.hud.settings.dof, game.hud.settings.ambient_occlusion, game.hud.settings.shadows, game.hud.settings.fullscreen, game.hud.settings.pitch]:
		check(game.hud.settings.is_ancestor_of(control) and not game.debug_panel.is_ancestor_of(control), "every graphics and camera control belongs to the settings sheet: " + str(control.name))
	await click(game.hud.settings.debug_enabled)
	var debug_preferences := ConfigFile.new()
	check(game.debug_available and game.hud.debug_menu_enabled and game.hud.map_option.item_count == 7, "the actual optional debug toggle exposes the compact dev battlefield")
	check(debug_preferences.load("user://settings.cfg") == OK and bool(debug_preferences.get_value("debug", "enabled", false)), "enabling optional debug persists its preference")
	game.hud.select_map("dev")
	check(game.hud.selected_map() == "dev", "opting into debug makes the dev map selectable")
	game.hud.select_map("forest")
	for id: String in ["master", "music", "sfx", "voice"]:
		var slider: HSlider = game.hud.settings.sliders[id]
		await show_control(slider)
		var before: float = slider.value
		var rectangle: Rect2 = slider.get_global_rect()
		await click_at(Vector2(rectangle.position.x + rectangle.size.x * 0.31, rectangle.get_center().y))
		var mix: Dictionary = game.audio.get_mix()
		check(not is_equal_approx(slider.value, before) and is_equal_approx(float(mix[id]), slider.value / 100.0), "actual slider input reaches audio mix: " + id)
		var settings := ConfigFile.new()
		check(settings.load("user://settings.cfg") == OK and is_equal_approx(float(settings.get_value("audio", id, -1.0)), float(mix[id])), "slider change persists through ConfigFile: " + id)
	await click(game.hud.settings.mute_button)
	check(game.audio.muted and AudioServer.is_bus_mute(AudioServer.get_bus_index(PaperAudio.MASTER_BUS)), "real mute control immediately mutes the Demo master bus")
	await click(game.hud.settings.mute_button)
	check(not game.audio.muted, "real mute control restores audio")
	var fullscreen_actions_before: int = actions.size()
	await click(game.hud.settings.fullscreen)
	check(actions.size() > fullscreen_actions_before and actions.back().kind == "fullscreen" and bool(actions.back().value), "fullscreen control emits an enabled request through the actual HUD")
	await click(game.hud.settings.fullscreen)
	check(actions.back().kind == "fullscreen" and not bool(actions.back().value), "fullscreen control emits a windowed request through the actual HUD")
	# Native window dimensions are outside a headless renderer's scope.
	saved_mix = game.audio.get_mix().duplicate(true)
	await key(KEY_ESCAPE)
	check(not game.hud.settings.visible and not game.pve_paused, "Escape closes entry settings and restores its original pause state")
	check(is_equal_approx(game.render_scale, 1.0) and game.graphics_quality == "balanced", "audio and window controls do not silently reduce rendering quality")
	game.audio.stop_all()
	game.queue_free()
	await frames()
	await new_game()
	check(game.audio.get_mix() == saved_mix, "a fresh actual main scene restores all saved audio preferences")
	check(game.debug_available and game.hud.debug_menu_enabled and game.hud.map_option.item_count == 7, "a fresh actual main scene restores the enabled debug preference")
	check(is_equal_approx(game.render_scale, 1.0) and game.graphics_quality == "balanced", "a fresh main scene restores native rendering quality")
	await click_named(game.hud.entry_menu, "设置 · 声音与画面")
	for id: String in ["master", "music", "sfx", "voice"]:
		check(is_equal_approx(float(game.hud.settings.sliders[id].value), float(saved_mix[id]) * 100.0), "reopened settings displays the restored preference: " + id)
	check(game.hud.settings.debug_enabled.button_pressed, "reopened settings displays the restored debug preference")
	game.hud.select_map("dev")
	await click(game.hud.settings.debug_enabled)
	check(not game.debug_available and not game.debug_panel.visible and game.hud.map_option.item_count == 6 and game.hud.selected_map() == "forest", "disabling optional debug closes diagnostics and safely replaces a dev menu selection")
	check(debug_preferences.load("user://settings.cfg") == OK and not bool(debug_preferences.get_value("debug", "enabled", true)) and str(debug_preferences.get_value("game", "map_mode", "")) == "forest", "disabling debug persists both the off preference and forest fallback")
	game.set_debug_enabled(true)
	game.load_preferences()
	check(not game.debug_available and not game.hud.debug_menu_enabled, "the saved off preference restores through the actual preference loader")
	await click(game.hud.settings.close_button)
	check(not game.hud.settings.visible and game.hud.entry_menu.visible, "settings completion button returns to the original entry")
	await click_named(game.hud.entry_menu, "军团档案  /  Wiki")
	check(game.hud.wiki.visible, "the actual entry action opens the faction archive")
	check_fps_visible("faction archive")
	await key(KEY_ESCAPE)
	check(not game.hud.wiki.visible and game.hud.entry_menu.visible, "Escape returns from the faction archive to the entry")

func check_legacy_menu_preferences() -> void:
	var saved_preferences := FileAccess.get_file_as_bytes("user://settings.cfg")
	var settings := ConfigFile.new()
	check(settings.load("user://settings.cfg") == OK, "saved preferences are available for historical menu migration")
	settings.set_value("debug", "enabled", false)
	for old_mode: String in ["handmade", "random", "mountains", "mountains640", "dev", "unknown-map"]:
		settings.set_value("game", "map_mode", old_mode)
		check(settings.save("user://settings.cfg") == OK, "historical map preference fixture writes: " + old_mode)
		game.hud.select_map("snow")
		game.load_preferences()
		check(game.hud.selected_map() == "forest" and game.hud.map_option.item_count == 6, "the real preference loader falls back to forest for an unavailable new-match mode: " + old_mode)
	settings.erase_section_key("game", "map_mode")
	for old_index: int in 3:
		settings.set_value("game", "map", old_index)
		check(settings.save("user://settings.cfg") == OK, "historical numeric map preference fixture writes: " + str(old_index))
		game.load_preferences()
		check(game.hud.selected_map() == "forest", "historical numeric selections also fall back to forest while debug is off: " + str(old_index))
	var file := FileAccess.open("user://settings.cfg", FileAccess.WRITE)
	check(file != null, "the current preferences reopen after migration checks")
	if file != null:
		file.store_buffer(saved_preferences)
		file.close()
	game.load_preferences()

func check_pause_and_save_replacement() -> void:
	check(game.start_match("dev", 11, "kestrel", true), "small actual dev match starts for menu flow")
	game.hud.show_menu(false)
	expect_audio("battle")
	check_fps_visible("battlefield")
	var gear := game.hud.find_child("SettingsGear", true, false) as Button
	check(gear != null and gear.is_visible_in_tree(), "the live HUD exposes its settings gear")
	if gear != null:
		await click(gear)
		check(game.hud.settings is PaperSettings and game.hud.settings.visible and not game.hud.menu.visible and not game.debug_panel.visible and game.pve_paused, "the actual HUD gear opens PaperSettings directly and pauses the match")
		check_fps_visible("gear settings")
		await key(KEY_ESCAPE)
		check(not game.hud.settings.visible and not game.hud.menu.visible and not game.pve_paused, "Escape from gear settings returns directly to the match and restores its pause state")
	await check_fps_while_paused()
	for initial_pause: bool in [false, true]:
		game.pve_paused = initial_pause
		await key(KEY_ESCAPE)
		check_fps_visible("live match menu")
		await click_named(game.hud.menu, "设置")
		check(game.hud.settings.visible and game.pve_paused, "in-match settings pauses simulation before editing")
		check_fps_visible("live menu settings")
		await key(KEY_ESCAPE)
		check(not game.hud.settings.visible and game.pve_paused == initial_pause, "Escape restores the exact pre-settings PVE state: " + str(initial_pause))
		await key(KEY_ESCAPE)
		check(not game.hud.menu.visible, "Escape returns from live menu to the active battlefield")
	game.pve_paused = false
	var alternate = Sim.new()
	alternate.setup(Rules.load_rules(), "dev", 23, "rivet", false)
	check(alternate.save_game(game.SAVE_PATH).is_empty(), "independent alternate-faction dev snapshot writes")
	game.groups = {3:[1]}
	game.inspected_bridge = 42
	game.inspected_ruin = game.sim.RUIN_TARGET_BASE - 1
	game.feedback.clear()
	game.feedback.append("__old_session_feedback__")
	game.selected = [1]
	game.command_mode = "force_attack"
	game.placing = true
	game.hud.voice_label.show()
	monitor_active = true
	monitor_loading()
	await game.load_game_with_loading()
	monitor_active = false
	await frames()
	check(game.sim.factions[0] == "rivet" and game.sim.map.seed == 23 and game.started and not game.loading, "actual loading route restores the different saved match")
	check(game.groups.is_empty() and game.inspected_bridge == -1 and game.inspected_ruin == -1, "loading another match clears old group and neutral-inspection IDs")
	check(game.selected.is_empty() and game.command_mode.is_empty() and not game.placing and not game.hud.voice_label.visible, "loading another match clears obsolete input and caption state")
	check(not "__old_session_feedback__" in game.feedback, "loading another match removes previous feedback")
	check(loading_samples > 0 and loading_audio_errors.is_empty(), "every observed loading frame requests silent music")
	expect_audio("battle")
	check_fps_visible("restored battlefield")

func set_result_fixture(outcome: String) -> void:
	check(game.start_match("dev", 31, "rivet", true), "new small match starts for actual settlement: " + outcome)
	game.hud.show_menu(false)
	for id: int in game.sim.entities.keys():
		var entity: Dictionary = game.sim.entities[id]
		if entity.kind != "building": continue
		if outcome == "draw" or (int(entity.team) == 0 if outcome == "lose" else int(entity.team) != 0):
			game.sim._kill_entity(id, true)
	game.sim._check_result()
	game.hud.refresh(game.sim, [], game.camera, false, "", 0)
	check(game.sim.result == outcome and game.hud.end_panel.visible, "actual building-elimination result shows settlement: " + outcome)
	check_fps_visible("settlement " + outcome)
	expect_audio(outcome)

func check_end_flow() -> void:
	for outcome: String in ["win", "lose", "draw"]:
		set_result_fixture(outcome)
		if outcome == "win":
			await click_named(game.hud.end_panel, "再战一次")
			var deadline: int = Time.get_ticks_msec() + 30000
			while (game.loading or not game.sim.result.is_empty()) and Time.get_ticks_msec() < deadline: await process_frame
			check(not game.loading and game.sim.result.is_empty() and not game.hud.end_panel.visible and game.sim.counts(0).y == 1, "real settlement restart creates a fresh playable match")
			expect_audio("battle")
		else:
			await click_named(game.hud.end_panel, "返回主菜单")
			check(game.hud.entry_menu.visible and not game.hud.end_panel.visible and not game.hud.entry_menu.resume_button.visible, "real settlement return opens main menu without a finished-match resume action: " + outcome)
			expect_audio("menu")
	set_result_fixture("win")
	var exit_button := button_named(game.hud.end_panel, "退出游戏")
	check(exit_button != null, "visible flow exposes action: 退出游戏")
	if exit_button != null:
		await show_control(exit_button)
		# Restore files and emit the report before yielding to main's quit timer.
		push_click_at(exit_button.get_global_rect().get_center())
	check(game.quit_pending and not game.started, "real settlement exit requests the guarded game shutdown")
	check(not game.audio.music.player.playing and game.audio.music.player.stream == null, "real exit immediately releases active music playback")

func run() -> void:
	root.size = Vector2i(1600, 900)
	preserve_file("user://settings.cfg")
	preserve_file("user://skirmish_v1.pfront")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	await new_game()
	await check_preferences()
	check_legacy_menu_preferences()
	await check_pause_and_save_replacement()
	await check_end_flow()
	restore_files()
	print("DEMO_MENU_FLOW ", JSON.stringify({"checks":checks,"failures":failures,"map":"dev","loading_samples":loading_samples,"loading_audio_errors":loading_audio_errors,"fullscreen_scope":"HUD request parameters only; GPU verification required","actual_exit_requested":game.quit_pending}))
	for failure: String in failures: push_error(failure)
	if not failures.is_empty():
		quit(1)
		return
	# Passing tests let the real game quit path terminate this process.
	var exit_deadline: int = Time.get_ticks_msec() + 800
	while Time.get_ticks_msec() < exit_deadline: await process_frame
	push_error("Real exit request did not terminate the game")
	quit(1)
