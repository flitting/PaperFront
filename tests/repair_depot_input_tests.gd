extends SceneTree

const OUTPUT := "res://artifacts/rts_revision_20261007/repair_depot_input.json"
var checks := 0
var failures: Array[String] = []
var game
var tracked_tank := -1
var tracked_depot := -1
var observed := {"entered":false, "service":false, "exited":false, "door_open":false, "healing_only_inside":true}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func frames(count := 3) -> void:
	for _frame in count: await process_frame

func right_click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.position = point
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await frames()

func tick(seconds: float) -> void:
	for _frame in ceili(seconds * 30):
		var previous_hp: float = game.sim.entities[tracked_tank].hp
		var previous_job: Dictionary = game.sim.entities[tracked_tank].get("refinery_docking", {})
		var was_inside: bool = previous_job.get("mode", "") == "repair" and previous_job.get("phase", "") == "unload" and int(previous_job.get("source", -1)) == tracked_depot and (game.sim.entities[tracked_tank].pos as Vector2).distance_to(previous_job.get("inside", Vector2.INF)) < .01
		game.sim.step(1.0 / 30.0)
		var unit: Dictionary = game.sim.entities[tracked_tank]
		var job: Dictionary = unit.get("refinery_docking", {})
		observed.entered = observed.entered or str(job.get("phase", "")) == "enter"
		observed.exited = observed.exited or str(job.get("phase", "")) == "exit"
		observed.service = observed.service or unit.state == "service"
		observed.door_open = observed.door_open or float(game.sim.entities[tracked_depot].get("production_door", 0.0)) > .99
		if float(unit.hp) > previous_hp + .0001:
			# The final heal and the first exit movement share a simulation tick.
			observed.healing_only_inside = observed.healing_only_inside and was_inside

func run() -> void:
	root.size = Vector2i(1440, 900)
	root.gui_embed_subwindows = true
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	await frames()
	check(game.start_match("dev", 7, "kestrel", true), "Loads actual main scene for depot mouse interaction")
	game.audio.set_mix({"muted":true})
	game.hud.show_menu(false)
	game.hud.show_entry(false)
	var sim: WarSimulation = game.sim
	sim.ai_enabled = false
	sim.vision_enabled = false
	sim.synchronous_path_tests = true
	sim.money[0] = 10000.0
	# Documented controlled flat arena, using live simulation and scene picking.
	# This isolates the depot entrance from the development map's cliff maze.
	for y: int in sim.map.size:
		for x: int in sim.map.size:
			sim.map.terrain[y][x] = 0
			sim.map.heights[y][x] = 0.0
	sim.mines.clear()
	sim.ruins.clear()
	sim.bridges.clear()
	sim._refresh_mine_spatial()
	sim._refresh_ruin_spatial()
	sim._prepare_terrain_cache()
	sim._nav_initialized = false
	sim._nav_dirty = true
	sim._spawn(0, "kestrel_power", Vector2(12, 22), true)
	var depot: int = sim._spawn(0, "kestrel_repair", Vector2(24, 22), true)
	var tank: int = sim._spawn(0, "kestrel_tank", Vector2(24, 31), true)
	tracked_tank = tank
	tracked_depot = depot
	var healthy: int = sim._spawn(0, "kestrel_tank", Vector2(28, 31), true)
	var infantry: int = sim._spawn(0, "kestrel_rifle", Vector2(20, 31), true)
	sim.entities[tank].hp = float(sim.data_for("kestrel_tank").hp) - 100.0
	sim._rebuild_spatial()
	game.remove_child(game.world)
	game.world.queue_free()
	game._create_match_world()
	game.world.setup(sim, game.camera)
	game.focus = Vector2(24, 25)
	game.distance = 30
	game.update_camera()
	game.selected = [tank, healthy, infantry]
	game.world.sync(0.0, game.selected, {})
	game.hud.refresh(sim, game.selected, game.camera, false, "", 0.0)
	await frames()
	var point: Vector2 = game.project_world_to_screen(game.entity_visual_center(sim.entities[depot]))
	check(game.pick_entity(point) == depot, "Real main-scene ray picking identifies the repair factory")
	var funds: float = sim.money[0]
	await right_click(point)
	check(not sim.entities[tank].commands.is_empty() and sim.entities[tank].commands[0].kind == "service" and int(sim.entities[tank].commands[0].target) == depot, "Actual right-click issues service command to the selected damaged tank")
	check(sim.entities[healthy].commands.is_empty() and sim.entities[infantry].commands.is_empty(), "Mixed selection excludes healthy tanks and infantry from depot service")
	check(sim.money[0] == funds and sim.entities[tank].hp == float(sim.data_for("kestrel_tank").hp) - 100.0, "Issuing service costs nothing before entering the workshop")
	tick(30.0)
	var hp: float = sim.entities[tank].hp
	var spent: float = funds - float(sim.money[0])
	check(is_equal_approx(hp, float(sim.data_for("kestrel_tank").hp)), "Tank physically reaches workshop and repairs to full health")
	check(observed.entered and observed.service and observed.exited and observed.door_open, "Real simulation observes front door opening, entering, workshop service and exiting")
	check(observed.healing_only_inside, "Every restored health increment occurs inside the reserved repair bay")
	check(is_equal_approx(spent, 100.0 * float(sim.rules.economy.repair_cost)), "Depot charges exactly once for the actual 100 restored health")
	var after: float = sim.money[0]
	tick(6.0)
	check(is_equal_approx(sim.money[0], after), "Full-health vehicle does not keep paying after service")
	check(sim.entities[tank].get("refinery_docking", {}).is_empty() and float(sim.entities[depot].get("production_door", 0.0)) == 0.0, "Completed service releases the bay and closes its front door")
	game.selected = [tank]
	await right_click(point)
	tick(2.0)
	check(is_equal_approx(sim.money[0], after) and sim.entities[tank].commands.is_empty(), "Repeated right-click on a full-health vehicle cannot create charges")
	game.selected = [depot]
	game.hud.refresh(sim, game.selected, game.camera, false, "", 0.0)
	check(game.hud.info_label.text.contains("右键入厂维修") and not game.hud.info_label.text.contains("范围 0"), "Selecting a repair factory explains its active service interaction")
	check(game.hud.spec_tooltip(sim.data_for("kestrel_repair")).contains("进入维修"), "Factory tooltip explains entering the depot rather than an aura")
	var report := {"checks":checks, "failures":failures, "depot":depot, "tank":tank, "final_hp":hp, "money_spent":spent, "observed":observed, "input_route":"root.push_input right mouse -> actual main-scene ray pick -> right_command -> service -> real simulation movement and paid health restoration", "fixture":"Main scene and live rules; controlled flat land arena"}
	DirAccess.make_dir_recursive_absolute(OUTPUT.get_base_dir())
	var file := FileAccess.open(OUTPUT, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	if sim._path_worker != null: sim._path_worker.close()
	game.quit_pending = true
	game.audio.stop_all()
	game.queue_free()
	sim = null
	await frames()
	# Match normal game shutdown: let the audio mixer release its WAV handles.
	await create_timer(.15).timeout
	print("REPAIR_DEPOT_INPUT ", JSON.stringify(report))
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
