extends "res://tools/capture_owner_livery_live.gd"
func clear_models(water:bool=false)->void:
	super.clear_models(water)
	sim.map.decorations.clear()
	world.setup(sim,camera)

func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	root.size=Vector2i(1600,1000);root.content_scale_size=root.size
	V.configure_player_colors(["#337ddd","#e94b40"])
	sim=Sim.new();sim.setup(RulesLoader.load_rules(),"dev",117,"kestrel",false,{"vision_enabled":false})
	for id in sim.entities.keys():sim._kill_entity(id,false)
	sim.events.clear()
	for row in sim.map.terrain:row.fill(0)
	for row in sim.map.heights:row.fill(0.0)
	sim.mines.clear();sim.bridges.clear();sim.map.bridges.clear();sim.ruins.clear();sim._refresh_ruin_spatial();sim._prepare_terrain_cache()
	var en:=WorldEnvironment.new();var env:=Environment.new()
	env.background_mode=Environment.BG_COLOR;env.background_color=Color("443329")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("b1b8cd");env.ambient_light_energy=.20
	env.ambient_light_sky_contribution=0;env.reflected_light_source=Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC;env.ssao_enabled=true;env.ssao_radius=1.1;env.ssao_intensity=1.5;env.ssao_power=1.6;env.ssao_detail=.55;env.ssao_light_affect=.15
	en.environment=env;root.add_child(en)
	light=DirectionalLight3D.new();light.rotation_degrees=Vector3(-38,-42,0);light.light_color=Color("ffdbb0");light.light_energy=1.55;light.shadow_enabled=true;light.shadow_bias=.06;light.shadow_normal_bias=.85;root.add_child(light)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.current=true;root.add_child(camera)
	var canvas:=CanvasLayer.new();root.add_child(canvas)
	var strip:=ColorRect.new();strip.color=Color("f1e7d6");strip.size=Vector2(1600,72);canvas.add_child(strip)
	label=Label.new();label.position=Vector2(28,18);label.add_theme_font_size_override("font_size",27);label.add_theme_color_override("font_color",Color("332b22"));canvas.add_child(label)
	world=PaperWorld.new();root.add_child(world)
	camera.position=Vector3(24,14,36);camera.look_at(Vector3(24,0,24));world.setup(sim,camera)
	for faction_index in range(4):
		var faction: String = ["kestrel","rivet","iron","sky"][faction_index]
		for row in range(3):
			var id: int = spawn(faction+"_"+["rifle","anti","engineer"][row],Vector2(21+faction_index*1.6,22+row*1.5))
			sim.entities[id].alpha=0
	spawn("kestrel_demolition",Vector2(21,26.5))
	for tier in range(3):
		world.lod_override=tier
		aim(Vector3(23.4,.35,24.2),Vector3(0,5,12),8.2,"RESTORED ORIGINAL PAPER / BLUE OWNER / CANON - HAMMER - IRON - SKY / LOD "+str(tier))
		await capture("v2_original_paper_lod"+str(tier))
	world.lod_override=0
	aim(Vector3(23.4,.35,24.2),Vector3(12,1.5,.4),7.8,"PAPER SIDE / SOLID PLAYER-COLORED CUT EDGE")
	await capture("v2_infantry_side")
	clear_models()
	for faction_index in range(4):
		var faction: String = ["kestrel","rivet","iron","sky"][faction_index]
		spawn(faction+"_tank",Vector2(19+faction_index*3.2,22))
		spawn(faction+"_heavy_tank",Vector2(19+faction_index*3.2,25))
	for tier in range(3):
		world.lod_override=tier
		aim(Vector3(23.8,.4,23.5),Vector3(2,10,15),14.5,"RESTORED FACTION PALETTE / 2x2 VEHICLES / SMALL OWNER INSIGNIA / LOD "+str(tier))
		await capture("v2_original_vehicle_lod"+str(tier))
	world.lod_override=0
	clear_models()
	spawn("sky_creator_hand",Vector2(24,24))
	aim(Vector3(24,1,24),Vector3(2,8,12),8,"CREATOR HAND / NATURAL SKIN / SMALL WRIST IDENTIFICATION")
	await capture("latest_hand_small_mark")
	world.free();camera.free();await process_frame
	quit()
