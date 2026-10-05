extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func capture(path: String) -> void:
	for frame in range(8):await process_frame
	# Static entry pages disable the hidden battlefield viewport. Explicitly
	# draw the paper canvas instead of waiting for an unrelated world redraw.
	RenderingServer.force_draw()
	var error:=root.get_texture().get_image().save_png(path)
	print("WIKI_CAPTURE ",path," ",error)

func run() -> void:
	root.size=Vector2i(1600,900)
	var game: Node3D=load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.audio.muted=true
	game.set_process(false);game.set_physics_process(false)
	game.battlefield_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/wiki"))
	await capture("res://artifacts/wiki/entry_menu.png")
	game.handle_action("wiki",null)
	for id in ["kestrel_hq","rivet_bomber","kestrel_rifle"]:
		game.hud.wiki.select_entry(id)
		game.hud.wiki.preview.set_rotation_active(false)
		await capture("res://artifacts/wiki/wiki_%s.png"%id)
	game.hud.wiki.select_entry("rivet_bomber")
	game.hud.wiki.detail_scroll.scroll_vertical=550
	await capture("res://artifacts/wiki/wiki_weapon_table.png")
	root.size=Vector2i(1100,700)
	await capture("res://artifacts/wiki/wiki_small_window.png")
	game.queue_free()
	await process_frame
	quit()
