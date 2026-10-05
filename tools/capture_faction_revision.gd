extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func capture(path: String) -> void:
	for frame in range(8): await process_frame
	RenderingServer.force_draw()
	var error: Error = root.get_texture().get_image().save_png(path)
	print("REVISION_CAPTURE ",path," ",error)

func run() -> void:
	root.size=Vector2i(1600,900)
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.audio.muted=true
	game.set_process(false)
	game.set_physics_process(false)
	game.battlefield_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	game.handle_action("wiki",null)
	for id in ["iron_tank","sky_tank","iron_repair_vehicle","sky_designation"]:
		game.hud.wiki.select_entry(id)
		game.hud.wiki.preview.set_rotation_active(false)
		await capture("res://artifacts/faction_revision/wiki_"+id+".png")
	game.hud.wiki.close_catalog()
	for faction in ["iron","sky"]:
		game.start_match("dev",7,faction,true)
		game.sim.ai_enabled=false
		game.hud.show_menu(false)
		var roster: Array = ["tank","assault","repair_vehicle","recycler","transport","engineer","rifle"] if faction=="iron" else ["tank","artillery","inspection","designation","pulse","engineer","rifle"]
		var selected: Array=[]
		for i in range(roster.size()):
			var id: int = game.sim.debug_spawn(0,faction+"_"+roster[i],Vector2(12+(i%4)*3,34+(i/4)*4))
			if i==0: selected.append(id)
		game.selected=selected
		game.focus=Vector2(17,35)
		game.distance=26.0
		game.yaw=0.0
		game.update_camera()
		game.world.sync(.016,selected)
		game.hud.refresh(game.sim,selected,game.camera,true,"新阵营单位显示检查",0)
		game.battlefield_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		await capture("res://artifacts/faction_revision/battle_"+faction+".png")
	game.queue_free()
	await process_frame
	quit()
