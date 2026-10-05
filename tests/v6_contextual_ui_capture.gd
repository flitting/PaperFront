extends SceneTree

var game
const DIR: String = "res://artifacts/expansion_v6/ui"

func _initialize() -> void:
	call_deferred("run")

func capture(label: String) -> void:
	game.battlefield_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png(DIR + "/" + label + ".png")
	print("UI_CAPTURE ", label)
	if label == "transport_menu": print("POPUP_CAPTURE ", {"position":game.hud.transport_menu.position,"size":game.hud.transport_menu.size,"embedded":game.hud.transport_menu.is_embedded(),"visible":game.hud.transport_menu.visible})

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	root.size = Vector2i(1600, 900)
	root.gui_embed_subwindows = true
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	root.gui_embed_subwindows = true
	game.set_process(false)
	game.set_physics_process(false)
	game.audio.muted = true
	game.start_match("dev", 7, "iron", true)
	game.sim.ai_enabled = false
	game.hud.show_menu(false)
	game.hud.show_entry(false)
	var hq: int = game.sim.entities.values().filter(func(e): return int(e.team) == 0 and game.sim.data_for(e.spec).get("role", "") == "hq")[0].id
	game.focus = game.sim.entities[hq].pos + Vector2(5, 4)
	game.distance = 34.0
	game.update_camera()
	game.selected = []
	game.hud.refresh(game.sim, [], game.camera, false, "点击总部或生产建筑呼出对应建造栏。", 0)
	game.world.sync(0.0, [], {})
	await capture("no_selection")
	game.selected = [hq]
	game.hud.refresh(game.sim, [hq], game.camera, false, "总部只显示当前已解锁建筑。", 0)
	game.world.sync(0.0, game.selected, {})
	await capture("headquarters")
	game.sim.debug_spawn(0, "iron_power", Vector2(26.5, 42.5))
	var engineer: int = game.sim.debug_spawn(0, "iron_engineer", Vector2(20.5, 42.5))
	game.selected = [engineer]
	game.focus = game.sim.entities[engineer].pos
	game.update_camera()
	game.hud.refresh(game.sim, [engineer], game.camera, false, "工兵在右侧部署分基地。", 0)
	game.world.sync(0.0, game.selected, {})
	await capture("engineer")
	game.hud.deploy_outpost_button.pressed.emit()
	game.hud.refresh(game.sim, [engineer], game.camera, false, "可重新选址或取消分基地部署。", 0)
	await capture("engineer_deployment")
	game.handle_action("cancel_build", {"channel": "normal"})
	var carrier: int = game.sim.debug_spawn(0, "iron_transport", Vector2(25.5, 36.5))
	game.sim.entities[carrier].passengers = [engineer]
	game.sim.entities[engineer].transport_id = carrier
	game.selected = [carrier]
	game.focus = game.sim.entities[carrier].pos
	game.update_camera()
	game.hud.refresh(game.sim, [carrier], game.camera, false, "装载可继续补员，卸载指定合法目的地。", 0)
	game.world.sync(0.0, game.selected, {})
	await process_frame
	game.hud.show_transport_menu()
	print("POPUP_OPEN ", {"position":game.hud.transport_menu.position,"size":game.hud.transport_menu.size,"embedded":game.hud.transport_menu.is_embedded(),"visible":game.hud.transport_menu.visible,"button":game.hud.transport_button.get_global_rect(),"root":root.get_visible_rect()})
	await capture("transport_menu")
	game.queue_free()
	await process_frame
	quit()
