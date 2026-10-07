extends "res://tools/capture_rts_model_revision.gd"
const OUT = "res://artifacts/architecture_revision_20261007"
const CARDS = "res://assets/cards/architecture_revision"
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CARDS))
	V.configure_player_colors(["#397ac4"])
	root.size = Vector2i(1800,1200); root.content_scale_size = root.size
	for art in ["barracks","factory","refinery","shipyard","tech","repair","hq","advanced_tower","power"]:
		prepare(art.to_upper()+" / CANON · HAMMER · LONG NAIL · PROVIDENCE",24.0,Vector3(0,1.6,0))
		camera.position = Vector3(4,14,24); camera.look_at(Vector3(0,1.6,0))
		floor_grid(34,12)
		for i in range(4):
			var faction: String = ["kestrel","rivet","iron","sky"][i]
			var size: int = 6 if art == "factory" else 5 if art == "refinery" else 8 if art == "hq" else 4 if art in ["shipyard","repair"] else 3
			if art == "power": size = 5 if faction == "iron" else 4 if faction == "sky" else 3
			if art == "tech" and faction == "iron": size = 5
			add_model({"faction":faction,"art":art,"size":size},"building",Vector3(-12.6+i*8.4,0,0),0,{"id":i,"state":"idle","production_door":.70})
		await _save(OUT+"/four_"+art+".png")
	for tier in range(3):
		prepare("FOUR FACTION GATES / "+["NEAR","MEDIUM","FAR"][tier],21.0,Vector3(0,1.5,0))
		camera.position = Vector3(3,11,24); camera.look_at(Vector3(0,1.5,0))
		for i in range(4): add_model({"faction":["kestrel","rivet","iron","sky"][i],"art":"factory","size":6},"building",Vector3(-10.5+i*7,0,0),tier,{"id":i,"production_door":.5,"state":"idle"})
		await _save(OUT+"/gates_lod_"+str(tier)+".png")
	root.size = Vector2i(512,512); root.content_scale_size = root.size
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/rules.json"))
	for id in rules.buildings:
		var spec: Dictionary = rules.buildings[id].duplicate(true)
		if not load("res://scripts/architecture_revision.gd").handles(str(spec.art)): continue
		var recipe: Dictionary = V._recipe(spec,"building",0)
		var dims: Vector3 = recipe.dimensions
		prepare("",maxf(maxf(dims.x,dims.z)*1.40,dims.y*1.5),Vector3(0,dims.y*.43,0))
		labels.hide()
		add_model(spec,"building",Vector3.ZERO)
		await _save(CARDS+"/"+id+".png")
	prepare("",2.65,Vector3(0,.65,0)); labels.hide()
	add_model({"faction":"sky","art":"scout"},"unit",Vector3.ZERO)
	await _save(CARDS+"/sky_scout.png")
	scene.free(); labels.free(); await process_frame
	print("ARCHITECTURE_GPU_RENDERED ",JSON.stringify({"renderer":RenderingServer.get_current_rendering_method(),"device":RenderingServer.get_video_adapter_name(),"models":manifest.size(),"captures":OUT,"cards":CARDS}))
	quit()
func _save(path: String) -> void:
	for frame in range(3): await process_frame
	RenderingServer.force_draw()
	var error: Error = root.get_texture().get_image().save_png(path)
	print("ARCHITECTURE_CAPTURE ",path," ",error)
