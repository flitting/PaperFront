extends SceneTree
func _init() -> void:call_deferred("run")
func run() -> void:
	var game=load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	await RenderingServer.frame_post_draw
	print("WINDOW size=",root.size," content_scale_size=",root.content_scale_size," factor=",root.content_scale_factor," mode=",root.content_scale_mode," texture=",root.get_texture().get_size()," image=",root.get_texture().get_image().get_size()," visible=",root.get_visible_rect().size)
	quit()
