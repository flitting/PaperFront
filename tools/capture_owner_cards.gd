extends "res://tools/capture_rts_model_revision.gd"
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	root.size=Vector2i(512,512);root.content_scale_size=root.size
	V.configure_player_colors(["#337ddd"])
	for art in ["drill","zeppelin","armored_train","rail","rail_junction"]:
		prepare("",4.6 if art=="drill" else 3.0,Vector3(0,1.8 if art=="drill" else .56,0))
		labels.hide();floor_grid(4,4)
		add_model({"faction":"rivet" if art in ["drill","zeppelin"] else "iron","art":art,"rail_mask":3,"rail_ports":7},"building" if art in ["drill","rail","rail_junction"] else "unit",Vector3.ZERO)
		for i in range(4):await process_frame
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png("res://assets/cards/rts_revision/"+art+".png")
		print("OWNER_CARD ",art)
	scene.free();labels.free();await process_frame;quit()
