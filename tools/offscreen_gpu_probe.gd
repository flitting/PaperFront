extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(64,64)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var rectangle := ColorRect.new()
	rectangle.color = Color.RED; rectangle.size = Vector2(64,64)
	viewport.add_child(rectangle)
	for frame in 5: await process_frame
	await RenderingServer.frame_post_draw
	var pixels: Image = viewport.get_texture().get_image()
	var okay: bool = pixels != null and not pixels.is_empty() and pixels.get_pixel(32,32).r > .95
	print("OFFSCREEN_GPU_PIXELS ",JSON.stringify({"display":DisplayServer.get_name(),"adapter":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"pixels_verified":okay,"private_capture_env":OS.get_environment("PAPER_FRONT_CAPTURE_OFFSCREEN")}))
	pixels = null; viewport.queue_free()
	await process_frame
	call_deferred("finish", okay)
func finish(okay: bool) -> void:
	await process_frame
	quit(0 if okay else 1)
