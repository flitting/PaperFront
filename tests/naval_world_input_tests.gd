extends SceneTree

const NavalOperations = preload("res://scripts/naval_operations.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func mouse(game, button: MouseButton, point: Vector2, pressed: bool = true) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = point
	event.pressed = pressed
	game._unhandled_input(event)

func key(game, code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	game._unhandled_input(event)

func focus_on(game, point: Vector2, distance: float = 34.0) -> void:
	game.focus = point
	game.distance = distance
	game.yaw = 0.0
	game.update_camera()

func tick_until(sim, predicate: Callable, maximum: int, delta: float = 0.1) -> int:
	for i in range(maximum):
		sim.step(delta)
		if predicate.call(): return i + 1
	return maximum

func find_yard(sim, team: int, harbor: Dictionary) -> Vector2:
	var spec: Dictionary = sim.data_for(sim.factions[team] + "_shipyard")
	var shore: Vector2 = harbor.water_pos
	for ring in range(21):
		for step in range(24):
			var wanted: Vector2 = shore + Vector2.from_angle(float(step) * TAU / 24.0) * float(ring) * 0.9
			var point: Vector2 = Vector2(roundf(wanted.x), roundf(wanted.y))
			if NavalOperations.shipyard_site_error(sim, team, spec, point).is_empty(): return point
	return Vector2.INF

func _sync_at(game, native: bool, selection: Array = []) -> void:
	game.world.native_world_sync_enabled = native
	game.world.sync(0.0, selection, {})

func _height_and_heading(game, sim, ship: int, yard: int, outward: Vector2, native: bool) -> void:
	_sync_at(game, native, [ship])
	var ship_model: Dictionary = game.world.models.get(ship, {})
	var yard_model: Dictionary = game.world.models.get(yard, {})
	var label: String = "native" if native else "script"
	check(not ship_model.is_empty() and not yard_model.is_empty(), label + " renderer retains both naval models")
	if ship_model.is_empty() or yard_model.is_empty(): return
	var expected_y: float = MapData.water_surface_y(sim.map, sim.entities[ship].pos)
	check(is_equal_approx(float(ship_model.root.position.y), expected_y), label + " ship root rests at true water height")
	check(str(ship_model.get("domain", "")) == "naval", label + " ship model caches naval domain")
	var yard_y: float = MapData.water_surface_y(sim.map, sim.entities[yard].pos)
	check(is_equal_approx(float(yard_model.root.position.y), yard_y), label + " water shipyard root rests at true water height")
	check(str(yard_model.get("domain", "")) == "naval", label + " shipyard model caches water surface domain")
	var angle: float = -deg_to_rad(float(sim.entities[yard].alpha))
	check(absf(wrapf(float(yard_model.root.rotation.y) - angle, -PI, PI)) < 0.01, label + " water shipyard root follows launch heading")
	var forward: Vector3 = yard_model.root.global_basis * Vector3.RIGHT
	var horizontal := Vector2(forward.x, forward.z).normalized()
	check(horizontal.dot(outward.normalized()) > 0.7, label + " physical slipway faces open water")

func _vision_sample(game, sim, enemy_ship: int, enemy_yard: int, native: bool) -> void:
	focus_on(game, sim.entities[enemy_ship].pos, 38.0)
	_sync_at(game, native)
	var label: String = "native" if native else "script"
	var hidden_submissions: int = int(game.world._submitted_transforms)
	var ship_model: Dictionary = game.world.models.get(enemy_ship, {})
	var yard_model: Dictionary = game.world.models.get(enemy_yard, {})
	check(not ship_model.is_empty() and not yard_model.is_empty(), label + " keeps hidden enemy lifecycle models")
	if ship_model.is_empty() or yard_model.is_empty(): return
	check(bool(ship_model.get("fog_hidden", false)) and bool(yard_model.get("fog_hidden", false)), label + " marks unseen ship and shipyard hidden")
	check(bool(ship_model.get("view_culled", false)) and bool(yard_model.get("view_culled", false)), label + " excludes unseen ship and shipyard from draw")
	var ship_screen: Vector2 = game.project_world_to_screen(game.entity_visual_center(sim.entities[enemy_ship]))
	var yard_screen: Vector2 = game.project_world_to_screen(game.entity_visual_center(sim.entities[enemy_yard]))
	check(game.pick_entity(ship_screen) != enemy_ship, label + " screen ray cannot pick unseen ship")
	check(game.pick_entity(yard_screen) != enemy_yard, label + " screen ray cannot pick unseen shipyard")
	# Reveal only these two existing entities. With the same camera and map,
	# their models must add submissions; hiding them removes those submissions.
	sim.entities[enemy_ship].visible_to |= 1
	sim.entities[enemy_yard].visible_to |= 1
	_sync_at(game, native)
	var visible_submissions: int = int(game.world._submitted_transforms)
	check(visible_submissions > hidden_submissions, label + " renderer submits newly visible enemy models")
	sim.entities[enemy_ship].visible_to &= ~1
	sim.entities[enemy_yard].visible_to &= ~1
	_sync_at(game, native)
	check(int(game.world._submitted_transforms) == hidden_submissions, label + " renderer withdraws hidden models without deleting them")

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	var factions: Array[String] = ["rivet", "kestrel"]
	var hq_positions: Array[Vector2] = []
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game.audio.muted = true
	check(game.start_match("islands", 31, "rivet", true, {}, factions, hq_positions, {"vision_enabled": false}), "normal islands match starts")
	game.hud.show_menu(false)
	game.hud.show_entry(false)
	var sim: WarSimulation = game.sim
	sim.ai_enabled = false
	check(not sim.vision_enabled, "transport scenario disables vision explicitly")
	var own: Dictionary = home_harbor(sim,0)
	var enemy: Dictionary = home_harbor(sim,1)
	var yard_pos: Vector2 = find_yard(sim, 0, own)
	check(yard_pos.is_finite(), "real home harbor admits a full-water shipyard")
	if not yard_pos.is_finite():
		_finish(game)
		return
	var yard: int = sim._spawn(0, "rivet_shipyard", yard_pos, true)
	var ship: int = sim.debug_spawn(0, "rivet_ship_transport", NavalOperations.spawn_point(sim,sim.entities[yard],"rivet_ship_transport"))
	var soldier: int = sim.debug_spawn(0, "rivet_rifle", own.land_pos)
	check(ship > 0 and soldier > 0, "transport and infantry spawn on their real harbor surfaces")
	if ship <= 0 or soldier <= 0:
		_finish(game)
		return
	focus_on(game, sim.entities[ship].pos)
	_height_and_heading(game, sim, ship, yard, own.outward, false)
	_height_and_heading(game, sim, ship, yard, own.outward, true)
	await process_frame
	await capture(game,"water_shipyard_native")
	var ship_screen: Vector2 = game.project_world_to_screen(game.entity_visual_center(sim.entities[ship]))
	check(game.battlefield_rect().has_point(ship_screen), "moored ship projects inside the battlefield viewport")
	check(game.pick_entity(ship_screen) == ship, "real screen ray selects moored ship")
	mouse(game, MOUSE_BUTTON_LEFT, ship_screen)
	mouse(game, MOUSE_BUTTON_LEFT, ship_screen, false)
	check(game.selected == [ship], "mouse press and release select naval transport")
	game.selected = [soldier]
	game.hud.refresh(sim, game.selected, game.camera, false, "", 0)
	game.handle_action("load_transport", null)
	check(game.command_mode == "load_transport", "selected infantry enters transport loading cursor")
	mouse(game, MOUSE_BUTTON_LEFT, ship_screen)
	check(not sim.entities[soldier].commands.is_empty() and sim.entities[soldier].commands[0].kind == "board" and int(sim.entities[soldier].commands[0].target) == ship, "load cursor left click on real ship dispatches boarding")
	tick_until(sim, func() -> bool: return int(sim.entities[soldier].get("transport_id", -1)) == ship, 600, 0.1)
	check(int(sim.entities[soldier].get("transport_id", -1)) == ship, "infantry physically reaches shore and boards")
	if int(sim.entities[soldier].get("transport_id", -1)) == ship:
		focus_on(game, sim.entities[ship].pos)
		_sync_at(game, true, [ship])
		ship_screen = game.project_world_to_screen(game.entity_visual_center(sim.entities[ship]))
		mouse(game, MOUSE_BUTTON_LEFT, ship_screen)
		mouse(game, MOUSE_BUTTON_LEFT, ship_screen, false)
		check(game.selected == [ship], "screen click reselects loaded transport")
		game.hud.refresh(sim, [ship], game.camera, false, "", 0)
		check(not game.hud.transport_button.disabled and not game.hud.transport_menu.is_item_disabled(0) and not game.hud.transport_menu.is_item_disabled(1), "partly loaded transport ship offers both additional loading and unloading")
		check(game.hud.transport_button.tooltip_text.contains("搭载 1/7"), "naval menu uses the ship's real passenger capacity")
		key(game, KEY_U)
		check(game.command_mode == "unload_move", "U key enters chosen-shore unloading mode")
		focus_on(game, enemy.land_pos, 38.0)
		var shore_screen: Vector2 = game.project_world_to_screen(Vector3(enemy.land_pos.x, MapData.height_at(sim.map, enemy.land_pos), enemy.land_pos.y))
		check(game.battlefield_rect().has_point(shore_screen), "destination shore projects inside battlefield viewport")
		mouse(game, MOUSE_BUTTON_LEFT, shore_screen)
		check(not sim.entities[ship].commands.is_empty() and sim.entities[ship].commands[0].kind == "unload_move", "destination click dispatches naval unloading order")
		tick_until(sim, func() -> bool: return int(sim.entities[soldier].get("transport_id", -1)) < 0, 2400, 0.1)
		check(int(sim.entities[soldier].get("transport_id", -1)) < 0, "ship sails to far island and unloads infantry")
		if int(sim.entities[soldier].get("transport_id", -1)) < 0:
			check(sim._terrain(sim.entities[soldier].pos) != MapData.WATER and sim.entities[soldier].pos.distance_to(enemy.land_pos) < 22.0, "unloaded infantry stands on requested island")
		_sync_at(game, true, [ship])
		check(is_equal_approx(float(game.world.models[ship].root.position.y), MapData.water_surface_y(sim.map, sim.entities[ship].pos)), "native moving ship root remains on water at destination")
		_sync_at(game, false, [ship])
		check(is_equal_approx(float(game.world.models[ship].root.position.y), MapData.water_surface_y(sim.map, sim.entities[ship].pos)), "script moving ship root remains on water at destination")

	# A fresh match enables authoritative vision. Enemy entities are created at
	# their own distant harbor, then examined through actual camera rays.
	check(game.start_match("islands", 31, "rivet", true, {}, factions, hq_positions, {"vision_enabled": true}), "independent vision-enabled match starts")
	game.hud.show_menu(false)
	game.hud.show_entry(false)
	sim = game.sim
	sim.ai_enabled = false
	check(sim.vision_enabled, "vision scenario is enabled")
	enemy = home_harbor(sim,1)
	var enemy_yard_pos: Vector2 = find_yard(sim, 1, enemy)
	check(enemy_yard_pos.is_finite(), "enemy home harbor admits real shipyard site")
	if enemy_yard_pos.is_finite():
		var enemy_yard: int = sim._spawn(1, "kestrel_shipyard", enemy_yard_pos, true)
		var enemy_ship: int = sim.debug_spawn(1, "kestrel_ship_frigate", enemy.water_pos)
		check(enemy_ship > 0, "enemy frigate spawns offshore")
		if enemy_ship > 0:
			sim.entities[enemy_yard].visible_to = 2
			sim.entities[enemy_ship].visible_to = 2
			_vision_sample(game, sim, enemy_ship, enemy_yard, false)
			_vision_sample(game, sim, enemy_ship, enemy_yard, true)
			var effects_before: int = game.world.effects.size()
			var ghosts_before: int = game.world.ghosts.size()
			var corpses_before: int = game.world.data_corpses.size()
			sim._kill_entity(enemy_ship, true)
			sim._kill_entity(enemy_yard, true)
			_sync_at(game, true)
			check(game.world.effects.size() == effects_before and game.world.ghosts.size() == ghosts_before and game.world.data_corpses.size() == corpses_before, "hidden enemy death creates no visible effects or ghost")
	_finish(game)

func _finish(game) -> void:
	game.queue_free()
	await process_frame
	print("NAVAL_WORLD_INPUT ", JSON.stringify({"checks": checks, "failures": failures}))
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func capture(game, name: String) -> void:
	if DisplayServer.get_name()=="headless":return
	var args:PackedStringArray=OS.get_cmdline_user_args()
	var directory:String=""
	for i in range(args.size()-1):
		if args[i]=="--capture-dir":directory=args[i+1]
	if directory.is_empty():return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	await RenderingServer.frame_post_draw
	check(game.get_viewport().get_texture().get_image().save_png(directory.path_join(name+".png"))==OK,"actual water shipyard screenshot saves")

func home_harbor(sim, team:int)->Dictionary:
	for harbor:Dictionary in sim.map.harbors:
		if int(harbor.get("team",-1))==team and harbor.get("role")=="home":return harbor
	return {}
