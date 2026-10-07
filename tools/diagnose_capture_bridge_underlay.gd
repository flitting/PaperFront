extends "res://tools/capture_owner_livery_live.gd"
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	root.size=Vector2i(1600,1000);root.content_scale_size=root.size
	V.configure_player_colors(["#337ddd","#e94b40"])
	sim=Sim.new();sim.setup(RulesLoader.load_rules(),"dev",117,"kestrel",false,{"vision_enabled":false})
	for id in sim.entities.keys():sim._kill_entity(id,false)
	sim.events.clear()
	for row in sim.map.terrain:row.fill(0)
	for row in sim.map.heights:row.fill(0.0)
	sim.mines.clear();sim.bridges.clear();sim.ruins.clear();sim._refresh_ruin_spatial();sim._prepare_terrain_cache()
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
	for i in range(4):
		var faction:String=["kestrel","rivet","iron","sky"][i]
		for row in range(2):
			var id:int=spawn(faction+"_rifle",Vector2(21+i*2,23+row*2))
			sim.entities[id].alpha=0
			sim.entities[id].state="idle" if row==0 else "attack"
			sim.entities[id].attack_flash=.25 if row else 0.0
	aim(Vector3(24,.7,24),Vector3(0,7,12),8.7,"FIXTURE DIAGNOSIS / BEFORE: AUTHORED BRIDGE METADATA WITHOUT BRIDGE ENTITIES")
	world.lod_override=0
	await capture("bridge_underlay_before")
	var before:Dictionary={"authored_bridges":sim.map.bridges.duplicate(true),"live_bridges":sim.bridges.size(),"fog_visible":world._fog_node.visible,"ghosts":world.ghosts.size(),"bridge_ground_cells":world.landscape._bridge_ground_cells.size(),"hidden_nodes":[]}
	for nodes in world.landscape.bridge_ground_nodes.values():
		for node:MeshInstance3D in nodes:
			if not node.visible:before.hidden_nodes.append({"name":node.name,"bounds":str(node.mesh.get_aabb())})
	# Fix only the controlled fixture: its empty live bridge list must match
	# the authored bridge metadata consumed by terrain construction.
	sim.map.bridges.clear()
	world.setup(sim,camera)
	label.text="FIXTURE DIAGNOSIS / AFTER: EMPTY BRIDGE ENTITIES AND METADATA AGREE"
	await capture("bridge_underlay_after")
	var after:Dictionary={"authored_bridges":sim.map.bridges.size(),"live_bridges":sim.bridges.size(),"fog_visible":world._fog_node.visible,"ghosts":world.ghosts.size(),"bridge_ground_cells":world.landscape._bridge_ground_cells.size(),"underlay_groups":world.landscape.bridge_ground_nodes.size()}
	assert(before.bridge_ground_cells>0 and before.hidden_nodes.size()>0)
	assert(after.bridge_ground_cells==0 and after.underlay_groups==0)
	var report:=FileAccess.open(OUTPUT+"/bridge_underlay_diagnosis.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"cause":"capture cleared sim.bridges but retained sim.map.bridges; bridge-owned ground stayed hidden while no bridge deck existed","product_source_changed":false,"before":before,"after":after},"  "))
	print("BRIDGE_UNDERLAY_DIAGNOSIS ",JSON.stringify({"before":before,"after":after}))
	world.free();camera.free();await process_frame;quit()
