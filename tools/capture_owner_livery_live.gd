extends SceneTree
const Sim=preload("res://tests/rule_test_simulation.gd")
const V=preload("res://scripts/volume_models.gd")
const OUTPUT="res://artifacts/rts_revision"
var sim
var world:PaperWorld
var camera:Camera3D
var light:DirectionalLight3D
var label:Label
var ids:Array[int]=[]
var evidence:Array=[]
func _initialize()->void:call_deferred("run")
func aim(target:Vector3,offset:Vector3,size:float,title:String)->void:
	camera.size=size;camera.position=target+offset;camera.look_at(target);label.text=title
func capture(file:String)->void:
	for i in range(5):world.sync(.016,[]);await process_frame
	RenderingServer.force_draw()
	var pixels:Image=root.get_texture().get_image()
	pixels.save_png(OUTPUT+"/"+file+"_"+RenderingServer.get_current_rendering_method()+".png")
	evidence.append({"file":file,"renderer":RenderingServer.get_current_rendering_method(),"native":world.native_world_sync_enabled,"lod":world.lod_override,"submitted":world._submitted_transforms,"light":str(light.rotation_degrees)})
	print("OWNER_LIVE_CAPTURE ",file)
func spawn(spec:String,pos:Vector2)->int:
	var id:int=sim._spawn(0,spec,pos,true)
	ids.append(id)
	return id
func clear_models(water:bool=false)->void:
	ids.clear()
	sim=Sim.new();sim.setup(RulesLoader.load_rules(),"dev",120+evidence.size(),"kestrel",false,{"vision_enabled":false})
	for id in sim.entities.keys():sim._kill_entity(id,false)
	sim.events.clear()
	for row in sim.map.terrain:row.fill(0)
	for row in sim.map.heights:row.fill(0.0)
	if water:
		for z in range(25,32):
			for x in range(13,36):sim.map.terrain[z][x]=MapData.WATER
	sim.mines.clear();sim.bridges.clear();sim.map.bridges.clear();sim.ruins.clear();sim._refresh_ruin_spatial();sim._prepare_terrain_cache()
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
	for i in range(4):
		var faction:String=["kestrel","rivet","iron","sky"][i]
		for row in range(2):
			var id:int=spawn(faction+"_rifle",Vector2(21+i*2,23+row*2))
			sim.entities[id].alpha=0
			sim.entities[id].state="idle" if row==0 else "attack"
			sim.entities[id].attack_flash=.25 if row else 0.0
	for tier in range(3):
		aim(Vector3(24,.7,24),Vector3(0,7,12),8.7,"LIVE PAPERWORLD / BLUE OWNER / CANON - HAMMER - LONG NAIL - PROVIDENCE / IDLE & COMBAT / LOD "+str(tier))
		world.lod_override=tier
		await capture("owner_blue_four_factions_lod"+str(tier))
	world.lod_override=0
	for index in range(3):
		var offset:Vector3=[Vector3(0,5,10),Vector3(10,5,0),Vector3(0,5,-10)][index]
		aim(Vector3(21,.7,24),offset,4.7,"LIVE CANON / IDLE AND COMBAT / "+["FRONT","SIDE","BACKLIT"][index]+" / ORIGINAL GAME LIGHT + FILMIC")
		light.rotation_degrees=Vector3(-38,-42,0) if index<2 else Vector3(-18,180,0)
		await capture("owner_canon_"+["front","side","backlit"][index])
	light.rotation_degrees=Vector3(-38,-42,0)
	clear_models(true)
	for i in range(4):
		var faction:String=["kestrel","rivet","iron","sky"][i]
		for row in range(3):
			var spec:String=faction+"_"+["tank","fighter","ship_frigate"][row]
			spawn(spec,Vector2(18+i*4,19+row*4))
	aim(Vector3(24,.6,23),Vector3(2,12,18),17,"LIVE BLUE OWNER / FOUR ARMIES / TANK - AIRCRAFT - SHIP / LARGE HULL & DECK COLOR")
	await capture("owner_blue_vehicle_fleet")
	clear_models()
	spawn("rivet_drill",Vector2(19,24));spawn("rivet_zeppelin",Vector2(23,24));spawn("iron_train",Vector2(27,24));spawn("sky_creator_hand",Vector2(31,24))
	aim(Vector3(25,2,24),Vector3(3,10,18),19,"LIVE BLUE OWNER / HEAVY DRILL - ZEPPELIN - ARMORED TRAIN - ANIMATED HAND")
	await capture("owner_blue_specials")
	clear_models()
	for i in range(4):spawn(["kestrel","rivet","iron","sky"][i]+"_hq",Vector2(11+i*9,24))
	aim(Vector3(24.5,1.5,24),Vector3(1,15,20),38,"LIVE BLUE OWNER / ALL FOUR HEADQUARTERS / OWNER WALLS AND ROOFS")
	await capture("owner_blue_headquarters")
	var report:=FileAccess.open(OUTPUT+"/owner_live_manifest_"+RenderingServer.get_current_rendering_method()+".json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"device":RenderingServer.get_video_adapter_name(),"main_game_lighting":true,"entries":evidence},"  "))
	world.free();camera.free();await process_frame
	quit()
