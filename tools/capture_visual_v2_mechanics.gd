extends "res://tools/capture_rts_model_revision.gd"
const OUT="res://artifacts/latest_visual_v2"
var failures: Array[String]=[]
func save_image(name: String) -> void:
	for frame in range(4): await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(OUT+"/"+name+".png")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	root.size=Vector2i(1600,1000);root.content_scale_size=root.size
	V.configure_player_colors(["#337ddd"])
	for tier in range(3):
		prepare("SKY / BARRACKS - FACTORY - REPAIR / LOD "+str(tier),15,Vector3(0,1.1,0))
		for index in range(3):
			var art: String=["barracks","factory","repair"][index]
			add_model({"art":art,"faction":"sky","size":6 if art=="factory" else 4},"building",Vector3((index-1)*6.8,0,0),tier)
		await save_image("sky_architecture_lod"+str(tier))
	prepare("SKY PHASE GATE / CLOSED - HALF - OPEN",17,Vector3(0,1,0))
	for index in range(3):
		var model=add_model({"art":"factory","faction":"sky","size":6},"building",Vector3((index-1)*7,0,0),0,{"production_door":float(index)*.5})
		for part in model.parts:
			if part.role=="production_door" and index>0:
				if (part.node.position.x-float(part.rest.x))*float(part.side)<=0: failures.append("gate leaf failed outward motion")
	await save_image("sky_gate_outward")
	var rules:Dictionary=RulesLoader.load_rules()
	for tier in range(3):
		prepare("MINING / CUTTER + FEED FORK + ORE ELEVATOR / LOD "+str(tier),7.4,Vector3(0,.6,0))
		for index in range(3):
			var faction: String=["kestrel","iron","sky"][index]
			var model=add_model(rules.units[faction+"_harvester"],"unit",Vector3((index-1)*3.3,0,0),tier)
			V.update_model(model,{"id":index,"state":"harvest","cargo":200},.37)
			if not is_zero_approx(model.body.position.y) or not is_zero_approx(model.body.rotation.z):failures.append("harvesting shakes chassis")
			if model.parts.filter(func(p):return str(p.role).begins_with("harvest_")).size()<5:failures.append("missing mining equipment")
		await save_image("mining_a_lod"+str(tier))
		for model in models:V.update_model(model,{"id":0,"state":"harvest","cargo":200},.41)
		await save_image("mining_b_lod"+str(tier))
	print("VISUAL_V2_MECHANICS ",JSON.stringify({"failures":failures,"models":manifest,"renderer":RenderingServer.get_current_rendering_method()}))
	quit(0 if failures.is_empty() else 1)
