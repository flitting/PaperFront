extends "res://tools/capture_rts_model_revision.gd"
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	var rules:Dictionary=RulesLoader.load_rules()
	V.configure_player_colors(["#337ddd"])
	root.size=Vector2i(1600,1000);root.content_scale_size=root.size
	prepare("HEAVY TANKS / CANON - HAMMER - LONG NAIL - PROVIDENCE / 3 AUTHORED LODS",13.0,Vector3(0,.7,0))
	floor_grid(18,14)
	for column in range(4):
		var faction:String=["kestrel","rivet","iron","sky"][column]
		for tier in range(3):add_model(rules.units[faction+"_heavy_tank"],"unit",Vector3(-4.8+column*3.2,0,-3.0+tier*3),tier)
	await capture("heavy_tank_three_lods_forward_plus")
	root.size=Vector2i(512,512);root.content_scale_size=root.size
	for faction in ["kestrel","rivet","iron","sky"]:
		prepare("",3.2,Vector3(0,.55,0));labels.hide();floor_grid(5,5)
		add_model(rules.units[faction+"_heavy_tank"],"unit",Vector3.ZERO)
		for i in range(4):await process_frame
		RenderingServer.force_draw()
		var path:String="res://assets/cards/"+faction+"_heavy_tank_portrait.png"
		root.get_texture().get_image().save_png(path)
		print("HEAVY_TANK_CARD ",path)
	var report:=FileAccess.open(OUTPUT+"/heavy_tank_model_manifest.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"renderer":RenderingServer.get_current_rendering_method(),"device":RenderingServer.get_video_adapter_name(),"entries":manifest},"  "))
	scene.free();labels.free();await process_frame;quit()
