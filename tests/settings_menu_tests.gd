extends SceneTree

## Actual viewport GUI input against the real main scene. Run in isolated XDG
## directories; also preserve local preference/save bytes for standalone use.
var game
var checks: int = 0
var failures: Array[String] = []
var backups: Dictionary = {}
var capture_output: String = ""

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func frames(count: int = 3) -> void:
	for _frame in range(count): await process_frame
func click(control: Control) -> void:
	var node: Node = control.get_parent()
	while node != null:
		if node.get_parent() is TabContainer:
			node.get_parent().current_tab = node.get_index()
		if node is ScrollContainer: node.ensure_control_visible(control)
		node = node.get_parent()
	await frames()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = control.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
	await frames()
func key(code: Key, echo: bool = false) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		event.echo = echo
		root.push_input(event, true)
	await frames()
func named(panel: Node, caption: String) -> Button:
	for node in panel.find_children("*", "Button", true, false):
		if node.text == caption: return node
	return null
func contents(sheet: PaperSettings) -> Array:
	var result: Array = []
	for node in sheet.find_children("*", "Label", true, false): result.append(node.text)
	for node in sheet.find_children("*", "Button", true, false): result.append(node.text)
	return result
func capture_settings(label: String) -> void:
	if capture_output.is_empty(): return
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(capture_output)
	var image: Image = root.get_texture().get_image()
	check(image.save_png(capture_output.path_join(label + ".png")) == OK, "real rendered settings screenshot writes " + label)
func preserve() -> void:
	for path in ["user://settings.cfg", "user://skirmish_v1.pfront"]:
		backups[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
func restore() -> void:
	for path in backups:
		if backups[path] == null: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		else:
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file != null: file.store_buffer(backups[path]); file.close()

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-settings="): capture_output = argument.trim_prefix("--capture-settings=")
	root.size = Vector2i(1600, 900)
	preserve()
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false); game.set_physics_process(false)
	await frames()
	var sheet: PaperSettings = game.hud.settings
	var original_mix: Dictionary = game.audio.get_mix().duplicate(true)
	var entry_settings: Button = named(game.hud.entry_menu, "设置 · 声音与画面")
	await click(entry_settings)
	check(sheet.visible and game.hud.entry_menu.visible and not game.pve_paused, "entry settings uses the canonical sheet without starting or pausing a match")
	await key(KEY_ESCAPE)
	check(not sheet.visible and game.hud.entry_menu.visible, "Escape returns entry settings to its original entry")
	await click(game.hud.entry_menu.play_button)
	check(game.hud.menu.visible, "new-game setup remains accessible from entry")
	await key(KEY_ESCAPE)
	check(not game.hud.menu.visible and game.hud.entry_menu.visible, "Escape leaves pregame setup for entry")
	check(game.start_match("dev", 17, "rivet", true), "small real match starts")
	game.hud.show_menu(false)
	var gear: Button = game.hud.find_child("SettingsGear", true, false)
	await click(gear)
	await capture_settings("gear")
	var instance: int = sheet.get_instance_id()
	var gear_contents: Array = contents(sheet)
	check(sheet.visible and not game.hud.menu.visible and game.pve_paused, "gear directly opens and pauses the common sheet")
	check(sheet.session_controls.visible and [sheet.save_button,sheet.load_button,sheet.new_game_button,sheet.home_button,sheet.quit_button].all(func(button):return sheet.is_ancestor_of(button)), "common sheet retains save/load/new-game/home/quit actions")
	game.handle_action("settings_open", null)
	check(not game.settings_pause_before, "repeated opening cannot overwrite an unpaused snapshot")
	await key(KEY_ESCAPE, true)
	check(sheet.visible and game.pve_paused, "held Escape echo does not close or reopen the sheet")
	await key(KEY_ESCAPE)
	check(not sheet.visible and not game.pve_paused and not game.settings_session_active, "Escape restores the exact gear pause state")
	await key(KEY_ESCAPE)
	check(sheet.visible and sheet.get_instance_id() == instance and contents(sheet) == gear_contents and not game.hud.menu.visible, "Escape opens the same instance and contents as the gear")
	await capture_settings("escape")
	await click(sheet.close_button)
	check(not sheet.visible and not game.pve_paused, "completion button restores the same pause state")
	await key(KEY_ESCAPE)
	sheet.sliders.sfx.grab_focus()
	await frames()
	await key(KEY_ESCAPE)
	check(not sheet.visible and not game.pve_paused, "Escape closes the common sheet while an audio slider owns GUI focus")
	game.pve_paused = true
	await key(KEY_ESCAPE)
	game.handle_action("settings_open", null)
	await key(KEY_ESCAPE)
	check(game.pve_paused, "an already paused battle stays paused after repeated opens and closing")
	game.pve_paused = false
	game.handle_action("settings_closed", null)
	check(not game.pve_paused, "duplicate close notifications cannot restore a stale pause state")
	game.placing = true
	await key(KEY_ESCAPE)
	check(not game.placing and not sheet.visible and not game.pve_paused, "Escape first cancels placement without opening settings")
	game.command_mode = "attack_move"
	await key(KEY_ESCAPE)
	check(game.command_mode.is_empty() and not sheet.visible, "Escape first cancels command targeting")
	await key(KEY_ESCAPE)
	var before: float = game.sim.time
	game._physics_process(.3)
	check(game.sim.time == before, "the common sheet actually prevents simulation ticks")
	await click(sheet.quality)
	var popup: PopupMenu = sheet.quality.get_popup()
	check(popup.visible, "actual settings option click opens its popup")
	await key(KEY_ESCAPE)
	check(not popup.visible and sheet.visible and game.pve_paused, "Escape closes a settings popup before the common sheet")
	await key(KEY_ESCAPE)
	check(not sheet.visible and not game.pve_paused, "the next Escape after popup closure closes the common sheet")
	await key(KEY_ESCAPE)
	await click(sheet.save_button)
	check(FileAccess.file_exists(game.SAVE_PATH) and sheet.visible and sheet.notice.text.contains("已保存"), "actual settings save action writes the snapshot and reports within the sheet")
	await click(sheet.wiki_button)
	check(game.hud.wiki.visible and not sheet.visible and game.pve_paused, "settings Wiki action enters a paused archive")
	await key(KEY_ESCAPE)
	check(not game.hud.wiki.visible and sheet.visible and game.pve_paused and not game.settings_pause_before, "Escape from settings Wiki returns to the common sheet with original pause snapshot")
	await click(sheet.new_game_button)
	check(game.hud.menu.visible and not sheet.visible, "settings new-game action retains the complete match setup screen")
	before = game.sim.time
	await key(KEY_P)
	game._physics_process(.3)
	check(game.pve_paused and game.sim.time == before, "new-match configuration remains paused even after a physical P key")
	await key(KEY_ESCAPE)
	check(not sheet.visible and not game.hud.menu.visible and not game.pve_paused, "Escape cancels live match setup and restores the original running state")
	for original_pause in [false, true]:
		game.pve_paused = original_pause
		await key(KEY_ESCAPE)
		await click(sheet.new_game_button)
		before = game.sim.time
		game._physics_process(.3)
		check(game.pve_paused and game.sim.time == before, "configuration freezes actual ticks for prior pause=" + str(original_pause))
		await click(named(game.hud.menu, "返回进行中的战局"))
		check(not game.hud.menu.visible and game.pve_paused == original_pause, "actual configuration Resume restores prior pause=" + str(original_pause))
	game.pve_paused = false
	await key(KEY_ESCAPE)
	await click(sheet.home_button)
	check(game.hud.entry_menu.visible and not sheet.visible and game.pve_paused, "settings home action returns to entry and pauses the existing match")
	await key(KEY_ESCAPE)
	check(not game.hud.entry_menu.visible and not game.pve_paused, "entry Escape resumes the original unpaused match")
	await key(KEY_ESCAPE)
	var saved_seed: int = int(game.sim.map.seed)
	await click(sheet.load_button)
	var deadline: int = Time.get_ticks_msec() + 15000
	while game.loading and Time.get_ticks_msec() < deadline: await process_frame
	await frames()
	check(not game.loading and not sheet.visible and not game.settings_session_active and not game.pve_paused and int(game.sim.map.seed) == saved_seed, "actual settings load action resumes its restored match and clears the modal session loading=%s visible=%s session=%s paused=%s seed=%s/%s notice=%s" % [game.loading,sheet.visible,game.settings_session_active,game.pve_paused,game.sim.map.seed,saved_seed,sheet.notice.text])
	check(game.audio.get_mix() == original_mix, "menu navigation never resets or mutes the saved audio mix")
	game.sim.result = "win"
	game.handle_action("entry_home", null)
	await key(KEY_ESCAPE)
	check(game.hud.entry_menu.visible, "Escape cannot resume a finished match from entry")
	game.audio.stop_all(); game.queue_free(); await frames()
	restore()
	print("SETTINGS_MENU ", JSON.stringify({"checks":checks,"failures":failures,"input":"actual root.push_input GUI/keyboard","map":"dev"}))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
