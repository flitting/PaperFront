extends SceneTree

var game: Node3D

func _initialize() -> void:
	call_deferred("run")

func capture(name: String) -> void:
	game.world.sync(0.0, game.selected, {})
	game.hud.refresh(game.sim, game.selected, game.camera, true, "基础操作与连接检查", 0)
	game.overlay.sim = game.sim
	game.overlay.camera = game.camera
	game.overlay.selection = game.selected
	game.overlay.refresh_overlay()
	for frame in range(8): await process_frame
	RenderingServer.force_draw()
	var path: String = "res://artifacts/expansion_v5/" + name + ".png"
	var error: Error = root.get_texture().get_image().save_png(path)
	print("STAGE1_CAPTURE ", path, " ", error)

func match_fixture(faction: String) -> void:
	game.start_match("dev", 7, faction, true)
	game.sim.ai_enabled = false
	game.sim.synchronous_path_tests = true
	game.hud.show_menu(false)
	game.hud.show_entry(false)
	game.focus = Vector2(25, 38)
	game.distance = 29.0
	game.yaw = 0.0
	game.update_camera()
	game.battlefield_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

func run() -> void:
	root.size = Vector2i(1600, 900)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.audio.muted = true
	game.set_process(false)
	game.set_physics_process(false)
	match_fixture("sky")
	game.hud.select_catalog("air")
	await capture("stage1_locked_tech")
	var sim: WarSimulation = game.sim
	sim.money[0] = 100000.0
	sim._spawn(0, "sky_power", Vector2(28, 39), true)
	var field: int = sim._spawn(0, "sky_airfield", Vector2(20, 36), true)
	var plane: int = sim._spawn(0, "sky_air_transport", Vector2(30, 42), true)
	sim._set_home_airfield(sim.entities[plane], field)
	sim.issue([plane], "return", Vector2.ZERO)
	for frame in range(600): sim.step(1.0 / 30.0)
	var engineer: int = sim._spawn(0, "sky_engineer", sim.entities[plane].pos + Vector2(2.5, 2.5), true)
	sim.issue([engineer], "board", sim.entities[plane].pos, plane)
	for frame in range(450): sim.step(1.0 / 30.0)
	game.selected = [plane]
	game.focus = sim.entities[plane].pos + Vector2(1, 0)
	game.distance = 23.0
	game.update_camera()
	await capture("stage1_transport_controls")
	for faction in ["iron", "sky"]:
		match_fixture(faction)
		for offset in [Vector2(0,0), Vector2(-1,0), Vector2(1,0), Vector2(0,-1), Vector2(0,1), Vector2(4,0), Vector2(5,0), Vector2(4,1), Vector2(8,0), Vector2(9,0), Vector2(10,0), Vector2(8,1), Vector2(8,2), Vector2(9,2), Vector2(10,2)]:
			game.sim._spawn(0, faction + "_wall", Vector2(21.5, 38.5) + offset, true)
		var infantry: int = game.sim._spawn(0, faction + "_rifle", Vector2(19, 43), true)
		game.sim._rebuild_nav()
		game.sim.issue([infantry], "move", Vector2(22, 43))
		game.sim.issue([infantry], "move", Vector2(22, 41), -1, true)
		for frame in range(6): game.sim.step(1.0 / 30.0)
		game.selected = [infantry]
		game.hud.select_catalog("defense")
		await capture("stage1_walls_paths_" + faction)
	game.queue_free()
	await process_frame
	quit()
