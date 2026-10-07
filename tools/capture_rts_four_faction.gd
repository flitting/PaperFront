extends SceneTree
const Fixture = preload("res://tests/rts_regression_fixture.gd")
var output := "res://artifacts/rts_revision_20261007/four_faction"
var fixture
var game
var images: Array[Dictionary] = []
func _initialize() -> void:
	if OS.get_environment("PAPER_FRONT_CAPTURE_OFFSCREEN") != "1":
		root.hide(); printerr("Use tools/run_offscreen_capture.py; visible desktop screenshot windows are disabled."); quit(2); return
	call_deferred("run")
func frames(count := 4) -> void:
	for frame in count: await process_frame
	await RenderingServer.frame_post_draw
func capture(name: String) -> void:
	print("RTS_GPU_CAPTURE_START ",name)
	game.update_camera()
	for frame in 8:
		game.world.sync(.05, game.selected, {})
		await process_frame
	game.hud.refresh(game.sim,game.selected,game.camera,false,"四阵营实际规则回归 · 明确初始设施fixture",0,-1,false)
	game.hud.fps_label.hide()
	game._update_battle_information()
	await frames()
	var image: Image = root.get_texture().get_image()
	var path: String = output.path_join(name + ".png")
	if image != null and not image.is_empty() and image.save_png(path) == OK: images.append({"file":path,"sim_time":fixture.sim.time,"checks":fixture.checks,"failures":fixture.failures.duplicate()})
	else: push_error("Capture failed: " + path)
	image = null
	print("RTS_GPU_CAPTURE_DONE ",name)
func run() -> void:
	if DisplayServer.get_name() == "headless": push_error("GPU renderer required"); quit(2); return
	root.size = Vector2i(1440,900)
	root.title = "RTS 四方验证截图"
	DirAccess.make_dir_recursive_absolute(output)
	game = load("res://main.tscn").instantiate(); root.add_child(game)
	game.set_process(false); game.set_physics_process(false)
	await frames()
	fixture = Fixture.new(); fixture.setup()
	print("RTS_GPU_FIXTURE_READY")
	game.world.queue_free(); await frames()
	game.sim = fixture.sim; game.rules = fixture.sim.rules
	game.audio.configure_units(game.rules); game.audio.commander.reset(game.sim)
	game._create_match_world(); game.world.setup(game.sim,game.camera)
	game.started = true; game.hud.is_started = true
	game.hud.show_entry(false); game.hud.show_menu(false)
	game.hud.mini.invalidate_map()
	game.focus = Vector2(32,32); game.camera_pitch = 45; game.distance = 90
	fixture.produce_phase()
	game.selected = [fixture.ids.iron_tank]
	await capture("actual_four_faction_production")
	fixture.economy_phase()
	game.selected = [int(game.sim.mines[1].get("drill", -1))]
	await capture("actual_drills_and_rail_mining")
	fixture.capture_phase(); fixture.combat_phase()
	game.focus = Vector2(31,32); game.distance = 56
	game.selected = [fixture.ids.capture_tower]
	await capture("actual_four_faction_combat_capture")
	fixture.rail_destruction_phase(); fixture.result_phase()
	var file := FileAccess.open(output.path_join("capture_report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"renderer":RenderingServer.get_current_rendering_method(),"images":images,"regression":fixture.evidence,"scope":"Actual rendered snapshots of the same paid-production, mining, walking-capture and combat four-owner test fixture. Starting infrastructure/funds and tower cooldown are controlled initial conditions; terminal cleanup is explicit deterministic damage, not a claimed naturally completed match."},"  "))
	file.close(); file = null
	print("RTS_FOUR_GPU_CAPTURE ",JSON.stringify({"images":images,"failures":fixture.failures}))
	game.quit_pending = true; game.audio.stop_all()
	await create_timer(.2).timeout
	game.queue_free(); game = null; fixture.sim = null; fixture = null
	await process_frame
	call_deferred("finish")

func finish() -> void:
	await process_frame
	await create_timer(.25).timeout
	quit(0)
