extends SceneTree
var output := "res://artifacts/rts_revision_20261007/ui"
var game
var images: Array[String] = []
func _initialize() -> void:
	if OS.get_environment("PAPER_FRONT_CAPTURE_OFFSCREEN") != "1":
		root.hide(); printerr("Use tools/run_offscreen_capture.py; visible desktop screenshot windows are disabled."); quit(2); return
	call_deferred("run")
func frames(count := 4) -> void:
	for frame in count: await process_frame
	await RenderingServer.frame_post_draw
func capture(name: String) -> void:
	await frames()
	game.hud.fps_label.hide()
	var image: Image = root.get_texture().get_image()
	var path: String = output.path_join(name + ".png")
	if image != null and not image.is_empty() and image.save_png(path) == OK: images.append(path)
	else: push_error("UI capture failed: " + path)
func run() -> void:
	if DisplayServer.get_name() == "headless": push_error("GPU display required for screenshots"); quit(2); return
	root.size = Vector2i(1440, 900)
	DirAccess.make_dir_recursive_absolute(output)
	game = load("res://main.tscn").instantiate(); root.add_child(game)
	game.set_process(false); game.set_physics_process(false)
	await frames()
	game.hud.show_entry(false); game.hud.show_menu(true)
	game.hud.select_faction("iron")
	var setup = game.hud.match_setup
	setup.players_option.select(2); setup.players_option.item_selected.emit(2)
	setup.player_color_option.select(1)
	setup.opponent_rows[0].faction.select(0); setup.opponent_rows[0].color.select(1)
	setup.opponent_rows[1].faction.select(2); setup.opponent_rows[1].color.select(4)
	setup.opponent_rows[2].faction.select(3); setup.opponent_rows[2].color.select(5)
	game.hud._request_map_preview()
	await capture("player_color_setup")
	game.hud.show_menu(false)
	game.start_match("dev", 2077, "kestrel", true)
	game.sim.ai_enabled = false
	var own: Array[int] = []
	for e: Dictionary in game.sim.entities.values():
		if e.team == 0 and e.kind == "building" and game.sim.data_for(e.spec).role == "hq": game.focus = e.pos + Vector2(6, 3)
	var p: Vector2 = game.focus
	for pair: Array in [["kestrel_rifle", Vector2(0,0)], ["kestrel_rifle", Vector2(2,0)], ["kestrel_tank", Vector2(5,0)], ["kestrel_scout", Vector2(8,0)], ["kestrel_engineer", Vector2(11,0)]]:
		own.append(game.sim._spawn(0, pair[0], Vector2(16,42) + pair[1], true))
	var enemy: int = game.sim._spawn(1, "rivet_tank", Vector2(31,42), true)
	game.sim._spawn(0, "kestrel_outpost", p + Vector2(0, 7), true)
	game.focus = Vector2(20,37)
	game.selected = own
	for number in range(1,7): game.save_control_group(number)
	game.selected = [own[2]]; game.zoom_target_distance = 30; game.distance = 30
	game.update_camera(); game.world.sync(.01, game.selected, {})
	game.hud.refresh(game.sim,game.selected,game.camera,true,"",0.0,-1,false)
	game.hud.fps_label.hide()
	game.hud.refresh_groups(game.groups); game._update_battle_information()
	var screen: Vector2 = game.project_world_to_screen(game.entity_visual_center(game.sim.entities[enemy]))
	root.warp_mouse(screen)
	await frames()
	game._update_battle_information()
	if game.hovered_entity != enemy:
		game.hovered_entity = game.pick_entity(screen)
		game.hud.show_entity_hover(game.hovered_entity, screen)
	await capture("groups_enemy_identity_bases")
	game.handle_action("settings_open", null)
	await capture("commander_volume_settings")
	var file := FileAccess.open(output.path_join("capture_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"renderer":RenderingServer.get_current_rendering_method(),"images":images,"scope":"Actual rendered main scene and live HUD controls; arranged review fixture, not played battle proof; enemy identity uses actual ray picking from warped mouse."},"  "))
	print("RTS_COMMAND_UI_CAPTURE ",JSON.stringify({"images":images,"hover_id":game.hovered_entity,"enemy_id":enemy}))
	game.quit_pending = true; game.audio.stop_all(); game.queue_free()
	await frames(); quit(0)
