extends SceneTree

var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func tick(sim, seconds: float) -> void:
	for _frame in range(ceili(seconds * 30.0)): sim.step(1.0 / 30.0)

func nearby_ground(sim, center: Vector2, radius: float, ignore: int = -1) -> Vector2:
	for ring in range(2, 10):
		for direction in range(16):
			var point: Vector2 = center + Vector2.from_angle(float(direction) * TAU / 16.0) * float(ring)
			if sim._standing(point, radius, ignore): return point
	return Vector2.INF

func mouse(game, button: MouseButton, point: Vector2, pressed: bool = true) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = point
	event.pressed = pressed
	game._unhandled_input(event)

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	root.gui_embed_subwindows = true
	game.set_process(false)
	game.set_physics_process(false)
	game.audio.muted = true
	game.start_match("dev", 7, "sky", true)
	game.hud.show_menu(false)
	game.hud.show_entry(false)
	var sim: WarSimulation = game.sim
	sim.ai_enabled = false
	sim.synchronous_path_tests = true
	sim.money[0] = 100000.0
	sim._spawn(0, "sky_power", Vector2(28, 39), true)
	var field: int = sim._spawn(0, "sky_airfield", Vector2(20, 36), true)
	var plane: int = sim._spawn(0, "sky_air_transport", Vector2(30, 42), true)
	sim._set_home_airfield(sim.entities[plane], field)
	sim.entities[plane].hp = 100.0
	sim.issue([plane], "return", Vector2.ZERO)
	tick(sim, 40.0)
	check(not sim.entities[plane].airborne and sim.entities[plane].hp == sim.data_for("sky_air_transport").hp, "Airport returns, repairs and parks an idle transport")
	check((sim.entities[plane].pos as Vector2).distance_to(sim.entities[field].pos) > 3.0, "Airport service parks aircraft beside the building")
	game.selected = [plane]
	game.focus = sim.entities[plane].pos
	game.distance = 26.0
	game.update_camera()
	game.world.sync(0.0, game.selected, {})
	await process_frame
	var plane_screen: Vector2 = game.project_world_to_screen(game.entity_visual_center(sim.entities[plane]))
	check(game.pick_entity(plane_screen) == plane, "Real screen picking selects a parked transport beside its airport")
	mouse(game, MOUSE_BUTTON_LEFT, plane_screen)
	mouse(game, MOUSE_BUTTON_LEFT, plane_screen, false)
	check(game.selected == [plane], "Mouse press and release select the parked aircraft")
	var ground: Vector2 = nearby_ground(sim, sim.entities[plane].pos + Vector2(4, 3), .35)
	var engineer: int = sim._spawn(0, "sky_engineer", ground, true)
	game.selected = [plane]
	game.hud.refresh(sim, game.selected, game.camera, true, "", 0)
	await process_frame
	check(not game.hud.transport_button.disabled and not game.hud.transport_menu.is_item_disabled(0) and game.hud.transport_menu.is_item_disabled(1), "Empty transport enables load and disables unload")
	var button_screen: Vector2 = game.hud.transport_button.get_global_rect().get_center()
	var button_press := InputEventMouseButton.new()
	button_press.button_index = MOUSE_BUTTON_LEFT
	button_press.pressed = true
	button_press.position = button_screen
	root.push_input(button_press, true)
	var button_release: InputEventMouseButton = button_press.duplicate()
	button_release.pressed = false
	root.push_input(button_release, true)
	await process_frame
	check(game.hud.transport_menu.visible and not game.dragging, "Real third command button opens the load/unload menu without a world click")
	game.hud.transport_menu.set_focused_item(0)
	var accept := InputEventKey.new()
	accept.keycode = KEY_ENTER
	accept.pressed = true
	root.push_input(accept, true)
	await process_frame
	check(game.command_mode == "load_transport", "Popup load entry starts the passenger targeting cursor")
	game.world.sync(0.0, game.selected, {})
	var engineer_screen: Vector2 = game.project_world_to_screen(game.entity_visual_center(sim.entities[engineer]))
	check(game.pick_entity(engineer_screen) == engineer, "Passenger is picked at its real screen projection")
	mouse(game, MOUSE_BUTTON_LEFT, engineer_screen)
	check(not sim.entities[engineer].commands.is_empty() and sim.entities[engineer].commands[0].kind == "board", "Load cursor mouse click assigns the engineer to the selected aircraft")
	tick(sim, 15.0)
	check(int(sim.entities[engineer].transport_id) == plane, "Engineer actually enters the selected aircraft")
	game.hud.refresh(sim, [plane], game.camera, true, "", 0)
	check(not game.hud.transport_menu.is_item_disabled(0) and not game.hud.transport_menu.is_item_disabled(1) and game.hud.transport_button.tooltip_text.contains("搭载 1/4"), "Partly loaded aircraft offers both loading additional passengers and unloading")
	var specialist_ground: Vector2 = nearby_ground(sim, sim.entities[plane].pos, .35)
	var specialist: int = sim._spawn(0, "sky_anti", specialist_ground, true)
	game.selected = [specialist]
	game.hud.refresh(sim, game.selected, game.camera, true, "", 0)
	game.handle_action("load_transport", null)
	plane_screen = game.project_world_to_screen(game.entity_visual_center(sim.entities[plane]))
	mouse(game, MOUSE_BUTTON_LEFT, plane_screen)
	check(not sim.entities[specialist].commands.is_empty() and sim.entities[specialist].commands[0].kind == "board" and int(sim.entities[specialist].commands[0].target) == plane, "Passenger-first load cursor can target an already occupied carrier")
	tick(sim, 15.0)
	check(int(sim.entities[specialist].transport_id) == plane and sim.entities[plane].passengers.size() == 2, "Aircraft accepts the additional specialist")
	game.selected = [plane]
	game.hud.refresh(sim, game.selected, game.camera, true, "", 0)
	await process_frame
	await process_frame
	check(not game.hud.selection_panel.get_global_rect().intersects(game.hud.command_panel.get_global_rect()), "Loaded-aircraft controls fit above the combat command panel")
	check(not game.hud.status_label.get_global_rect().intersects(game.hud.production_panel.get_global_rect()), "Command feedback stays above the expanded technology catalog")
	var unload_shortcut := InputEventKey.new()
	unload_shortcut.keycode = KEY_U
	unload_shortcut.pressed = true
	game._unhandled_input(unload_shortcut)
	check(game.command_mode == "unload_move", "Unload action asks for a destination")
	var water: Vector2 = Vector2.INF
	for y in range(sim.map.size):
		for x in range(sim.map.size):
			var cell := Vector2(x + .5, y + .5)
			if not sim._land(cell): water = cell; break
		if water.is_finite(): break
	if water.is_finite():
		check(not game.command_units("unload_move", water), "Aircraft rejects an illegal water unloading destination before issuing the order")
		check(game.command_mode == "unload_move", "Invalid unloading destination preserves targeting mode for a new click")
	var destination: Vector2 = nearby_ground(sim, Vector2(32, 42), sim._radius(sim.entities[plane]), plane)
	game.focus = destination
	game.update_camera()
	var destination_screen: Vector2 = game.project_world_to_screen(Vector3(destination.x, MapData.height_at(sim.map, destination), destination.y))
	mouse(game, MOUSE_BUTTON_LEFT, destination_screen)
	check(not sim.entities[plane].commands.is_empty() and sim.entities[plane].commands[0].kind == "unload_move", "Destination mouse click issues the transport unload order")
	tick(sim, 15.0)
	check(not sim.entities[plane].airborne and sim.entities[plane].passengers.is_empty() and int(sim.entities[engineer].transport_id) < 0 and int(sim.entities[specialist].transport_id) < 0, "Aircraft flies, lands away from its airport and unloads its passenger")
	check((sim.entities[plane].pos as Vector2).distance_to(destination) < .15 and sim._standing(sim.entities[engineer].pos, sim._radius(sim.entities[engineer]), engineer), "Unloading respects the chosen destination and legal terrain")
	game.selected = [specialist]
	game.hud.refresh(sim, game.selected, game.camera, true, "", 0)
	var land_shortcut := InputEventKey.new()
	land_shortcut.pressed = true
	land_shortcut.keycode = KEY_L
	game.selected = [plane]
	game._unhandled_input(land_shortcut)
	check(game.command_mode == "land", "L remains the aircraft landing shortcut")
	game.command_mode = ""
	land_shortcut.keycode = KEY_B
	game._unhandled_input(land_shortcut)
	check(sim.entities[plane].flight_state == "returning" and bool(sim.entities[plane].park_after_service), "B remains the aircraft return shortcut")
	game.queue_free()
	await process_frame
	print("UNIFIED_TRANSPORT_INPUT ", JSON.stringify({"checks": checks, "failures": failures}))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
