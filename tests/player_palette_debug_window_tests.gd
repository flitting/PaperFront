extends SceneTree
var checks := 0
var failures: Array[String] = []
var settings_before = null
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func visible_windows() -> int:
	var count := 0
	for child in root.find_children("*", "Window", true, false):
		if child.visible: count += 1
	return count
func key(game, code: int) -> void:
	var event := InputEventKey.new(); event.keycode = code; event.pressed = true
	game._unhandled_input(event)
func run() -> void:
	settings_before = FileAccess.get_file_as_bytes("user://settings.cfg") if FileAccess.file_exists("user://settings.cfg") else null
	var game = load("res://main.tscn").instantiate(); root.add_child(game)
	game.set_process(false); game.set_physics_process(false)
	await process_frame
	var setup = game.hud.match_setup
	check(setup.player_color_option.item_count == 16, "human player has sixteen actual color choices")
	for row: Dictionary in setup.opponent_rows: check(row.color.item_count == 16, "every opponent has the same sixteen-color palette")
	var original: Array[String] = ["e7ad42","41c7c6","af80d1","9bb85a","6498df","df7860","d68eb5","e2d478"]
	for index in 8: check(str(setup.player_color_option.get_item_metadata(index)) == original[index], "historical palette index and old save hex remain unchanged")
	var distinct: Dictionary = {}
	for index in setup.player_color_option.item_count:
		setup.player_color_option.select(index)
		check(setup.options("kestrel").slots[0].color == str(setup.player_color_option.get_item_metadata(index)), "every selectable color is emitted as a concrete player color")
		distinct[str(setup.player_color_option.get_item_metadata(index))] = true
		setup.opponent_rows[0].color.select(index)
		var pair: Dictionary = setup.options("kestrel")
		check(pair.slots[0].color == pair.slots[1].color, "every old and new palette option can be shared across different factions")
	check(distinct.size() == 16, "sixteen choices are sixteen distinct actual RGB colors")
	setup.players_option.select(2); setup.players_option.item_selected.emit(2)
	setup.player_color_option.select(15)
	for index in 3: setup.opponent_rows[index].color.select(14-index)
	var expected: Dictionary = setup.options(game.hud.selected_faction())
	game.set_debug_enabled(true)
	game.audio.set_mix({"commander":.31})
	game.save_preferences()
	setup.player_color_option.select(0)
	for row: Dictionary in setup.opponent_rows: row.color.select(0)
	game.set_debug_enabled(false); game.audio.set_mix({"commander":.9})
	game.load_preferences()
	check(setup.options(game.hud.selected_faction()) == expected, "all four new owner colors round-trip through saved preferences")
	check(game.debug_available and is_equal_approx(game.audio.mix.commander,.31), "debug preference and independent commander volume survive color restoration")
	check(game.start_match("dev", 703, "kestrel", true), "actual test game starts")
	game.hud.show_entry(false); game.hud.show_menu(false)
	game.set_debug_enabled(true)
	var baseline := visible_windows()
	key(game, KEY_F2)
	check(game.debug_panel.visible and game.debug_panel is PanelContainer and game.debug_panel.get_parent() == game.hud, "F2 opens the actual same-viewport HUD overlay")
	check(visible_windows() == baseline, "F2 creates no visible subwindow")
	check(game.hud.blocks_world_scroll(game.debug_panel.get_global_rect().get_center()), "debug overlay intercepts battlefield mouse and scroll input")
	key(game, KEY_F2)
	check(not game.debug_panel.visible and visible_windows() == baseline, "second F2 hides the overlay without window lifecycle changes")
	game.handle_action("settings_open",null)
	game.hud.settings.changed.emit("audio_mix",{"commander":.47})
	game.handle_action("settings_closed",null)
	check(is_equal_approx(game.audio.mix.commander,.47) and setup.options(game.hud.selected_faction()) == expected, "actual settings changes preserve the selected owner palette")
	game.quit_pending = true; game.audio.stop_all(); await create_timer(.2).timeout
	game.queue_free(); await process_frame; await create_timer(.2).timeout
	print("PLAYER_PALETTE_DEBUG_WINDOW ",JSON.stringify({"checks":checks,"failures":failures,"scope":"actual main scene F2 overlay and visible Window inventory; sixteen real RGB choices, all eight legacy indices preserved, new-owner colors and settings saved round-trip"}))
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
func _finalize() -> void:
	if settings_before == null: DirAccess.remove_absolute("user://settings.cfg")
	else:
		var file := FileAccess.open("user://settings.cfg",FileAccess.WRITE)
		if file != null: file.store_buffer(settings_before); file.close()
