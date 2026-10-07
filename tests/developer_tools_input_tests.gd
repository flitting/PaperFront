extends SceneTree

var game
var checks: int = 0
var failures: Array[String] = []
var settings_before = null

func _initialize() -> void: call_deferred("run")
func check(value: bool,message: String) -> void:
	checks += 1
	if not value: failures.append(message)
func frames(count: int = 3) -> void:
	for index: int in count: await process_frame
func click(control: Control) -> void:
	var parent: Node = control.get_parent()
	while parent != null:
		if parent is ScrollContainer: parent.ensure_control_visible(control)
		parent = parent.get_parent()
	await frames()
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.position = control.get_global_rect().get_center()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event,true)
	await frames()
func button_named(text: String) -> Button:
	for button: Button in game.debug_tools.find_children("","Button",true,false):
		if button.text == text: return button
	return null

func run() -> void:
	settings_before = FileAccess.get_file_as_bytes("user://settings.cfg") if FileAccess.file_exists("user://settings.cfg") else null
	root.size = Vector2i(1600,900)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	await frames()
	check(game.start_match("dev",73026,"kestrel",true),"real scene starts dev100")
	game.hud.show_entry(false)
	game.hud.show_menu(false)
	game.set_debug_enabled(true)
	var key := InputEventKey.new()
	key.keycode = KEY_F2
	key.pressed = true
	root.push_input(key,true)
	await frames()
	check(game.debug_panel.visible,"actual F2 opens same-window debug panel")
	check(game.sim.map.size == 100 and game.sim.map.valid,"actual scene uses valid100 map")
	check(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(game.debug_panel.get_global_rect()),"debug controls fit the main viewport")
	var initial_count: int = game.sim.entities.size()
	await click(button_named("一键生成本阵营所有建筑"))
	check(game.sim.entities.size() > initial_count and game.debug_building_report.text.contains("失败 0"),"mouse click generates real full building catalog and report")
	var yard: int = game.DeveloperTools._owned(game.sim,0,"kestrel_shipyard")
	var ship: int = game.sim.debug_spawn(0,"kestrel_ship_transport",Vector2(40,80))
	game.focus = Vector2(38,76)
	game.update_camera()
	for native: bool in [false,true]:
		game.sim.entities[ship].pos += Vector2(.1,0)
		game.world.native_world_sync_enabled = native
		game.world.sync(0.0,[],{})
		for id: int in [yard,ship]:
			var model: Dictionary = game.world.models.get(id,{})
			check(not model.is_empty() and is_equal_approx(float(model.root.position.y),MapData.water_surface_y(game.sim.map,game.sim.entities[id].pos)),("native" if native else "script")+" dock and vessel sit on the same developer water sheet")
	await click(game.debug_instant_toggle)
	check(game.debug_instant_build and bool(game.sim.match_options.developer_instant_build),"mouse click enables instant construction")
	var factory: int = game.DeveloperTools._owned(game.sim,0,"kestrel_factory")
	game.sim.money[0] = 10000
	check(game.sim.produce(factory,"kestrel_tank").is_empty(),"real factory accepts paid tank order")
	game.sim.step(1.0/30.0)
	check(game.sim.entities[factory].queue.is_empty() and game.sim.money[0] < 10000,"actual instant toggle completes paid production in one tick")
	# Select the fourth entry using the native popup's keyboard routing.
	await click(game.debug_faction_picker)
	for code: int in [KEY_DOWN,KEY_DOWN,KEY_DOWN,KEY_ENTER]:
		for pressed: bool in [true,false]:
			var event := InputEventKey.new()
			event.keycode = code
			event.pressed = pressed
			root.push_input(event,true)
		await frames()
	var chosen_faction: String = str(game.debug_faction_picker.get_item_metadata(game.debug_faction_picker.selected))
	await click(button_named("切换并重置"))
	check(chosen_faction != "kestrel" and game.sim.factions[0] == chosen_faction and game.debug_building_report.text.contains("失败 0"),"actual picker and reset button switch to chosen faction's full building catalog")
	game.set_debug_enabled(false)
	check(not game.debug_panel.visible and not bool(game.sim.match_options.developer_instant_build),"turning debug off disables instant cheat and hides tools")
	check(game.start_match("handmade",73026,"sky",true),"ordinary battle still starts")
	game.set_debug_enabled(true)
	game.set_debug_visible(true)
	await frames()
	check(not game.debug_tools.visible and not game.debug_tools_scroll.visible and not game.DeveloperTools.instant_enabled(game.sim),"ordinary battle has metrics only and no cheats")
	game.quit_pending = true
	game.audio.stop_all()
	await create_timer(.2).timeout
	game.queue_free()
	await frames()
	print("Developer tools input checks: %d passed, %d failed" % [checks-failures.size(),failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _finalize() -> void:
	if settings_before == null: DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	else:
		var file := FileAccess.open("user://settings.cfg",FileAccess.WRITE)
		if file != null: file.store_buffer(settings_before);file.close()
