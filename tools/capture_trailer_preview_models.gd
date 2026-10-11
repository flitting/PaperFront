extends SceneTree
## Local-only native 4K in-engine models; no game logic or published media edits.
const Sim = preload("res://tests/rule_test_simulation.gd")
const L = preload("res://scripts/localization.gd")
const OUT = "res://artifacts/trailer_preview_v3_20261011/models/"
const SIZE = Vector2i(3840,2160)
const FPS = 30
const FACTIONS: Array[String] = ["kestrel","rivet","iron","sky"]
var sim
var world: PaperWorld
var camera: Camera3D
var stage: Node3D
var motion: bool
var evidence: Array = []

func _initialize() -> void:
	if OS.get_environment("PAPER_FRONT_CAPTURE_OFFSCREEN") != "1":
		root.hide()
		printerr("Use tools/run_offscreen_capture.py on the private display.")
		quit(2)
		return
	call_deferred("run")

func progress(message: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	FileAccess.open(OUT+"progress.txt",FileAccess.WRITE).store_string(message)
	print("PREVIEW_MODELS ",message)

func clear_world() -> void:
	if world != null: world.free()
	world = null
	sim = null
	await process_frame

func fresh_display(water: bool = false) -> void:
	await clear_world()
	sim = Sim.new()
	var starts: Array[Vector2] = [Vector2(40,40),Vector2(150,40),Vector2(40,150),Vector2(150,150)]
	sim.setup_multiteam(RulesLoader.load_rules(),"symmetric",117,FACTIONS,false,starts,Callable(),{"vision_enabled":false})
	assert(int(sim.map.size)==192)
	for id in sim.entities.keys(): sim._kill_entity(id,false)
	for row in sim.map.terrain: row.fill(MapData.WATER if water else MapData.LAND)
	for row in sim.map.heights: row.fill(0.0)
	for key in ["ruins","mines","bridges","decorations","harbors"]:
		if sim.map.has(key): sim.map[key].clear()
	sim.ruins.clear();sim.mines.clear();sim.bridges.clear();sim.events.clear()
	sim._refresh_ruin_spatial();sim._refresh_mine_spatial();sim._prepare_terrain_cache()

func deploy(team: int, role: String, point: Vector2) -> int:
	var id: int = sim._spawn(team,FACTIONS[team]+"_"+role,point,true)
	assert(id>0)
	sim.entities[id].visible_to=255
	sim.entities[id].alpha=-12.0
	sim.entities[id].turret_alpha=-12.0
	return id

func create_world() -> void:
	progress("Building complete native PaperWorld")
	world=PaperWorld.new();stage.add_child(world);world.setup(sim,camera)
	world.configure_quality("native")
	world.lod_enabled=false
	world.lod_override=0
	world.landscape.scenery_lod_enabled=false

func shot(name: String, target: Vector3, offset: Vector3, framing: float, seconds: float, mode: String) -> void:
	progress("Rendering "+name)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=framing;camera.position=target+offset;camera.look_at(target)
	var transform: Transform3D=camera.global_transform
	var fov: float=camera.fov
	var locked: bool=true
	world.sync(0.0,[])
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	var folder: String=OUT+name+"/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var count: int=roundi(seconds*FPS) if motion else 1
	for i in count:
		world.sync(1.0/FPS,[])
		sim.events.clear()
		locked=locked and camera.global_transform.is_equal_approx(transform) and is_equal_approx(camera.fov,fov) and is_equal_approx(camera.size,framing)
		await process_frame
		await RenderingServer.frame_post_draw
		var pixels: Image=root.get_texture().get_image()
		assert(pixels.get_size()==SIZE)
		assert(pixels.save_png(folder+"%04d.png"%i)==OK)
		if i%30==0: progress("%s %d/%d"%[name,i,count])
	assert(locked and int(sim.map.size)!=48)
	evidence.append({"shot":name,"path":ProjectSettings.globalize_path(folder),"frames":count,"fps":FPS,"duration_seconds":float(count)/FPS,"resolution":[SIZE.x,SIZE.y],"map_mode":sim.map.mode,"map_size":sim.map.size,"scene_role":mode,"terrain_edited":mode=="authored_192_model_display","camera_locked":locked,"camera_transform":var_to_str(transform),"camera_fov":fov,"camera_size":framing,"projection":"orthographic","dof_near":false,"dof_far":false,"render_scale":root.scaling_3d_scale,"msaa":"4x","quality":"native","lod_enabled":world.lod_enabled,"lod_override":world.lod_override,"scenery_lod_enabled":world.landscape.scenery_lod_enabled,"entities":sim.entities.size(),"lod_counts":Array(world._lod_counts),"scope":"Authored model deployments with real production assets and visual animation; no player match or simulation progression is claimed."})

func run() -> void:
	progress("Starting true 4K preview")
	motion=OS.get_environment("PAPER_FRONT_PREVIEW_MODELS_MOTION")=="1"
	L.initialize("en")
	root.size=SIZE;root.content_scale_size=SIZE
	root.msaa_3d=Viewport.MSAA_4X
	root.screen_space_aa=Viewport.SCREEN_SPACE_AA_DISABLED
	root.use_taa=false
	root.scaling_3d_scale=1.0
	VolumeModels.configure_player_colors(["#347dd0","#d85140","#4d977a","#b982c9"])
	stage=Node3D.new();root.add_child(stage)
	var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR;settings.background_color=Color("443329")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color("b1b8cd");settings.ambient_light_energy=.3
	settings.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	settings.ssao_enabled=true;settings.ssao_radius=1.1;settings.ssao_intensity=1.2;settings.ssao_power=1.4
	var environment:=WorldEnvironment.new();environment.environment=settings;stage.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-44,-36,0)
	sun.light_color=Color("ffdfb3");sun.light_energy=1.45;sun.shadow_enabled=true
	sun.shadow_bias=.05;sun.shadow_normal_bias=.8;sun.directional_shadow_max_distance=180
	stage.add_child(sun)
	camera=Camera3D.new();camera.far=600;stage.add_child(camera);camera.make_current()
	var attributes:=CameraAttributesPractical.new()
	attributes.dof_blur_near_enabled=false;attributes.dof_blur_far_enabled=false
	attributes.auto_exposure_enabled=false;camera.attributes=attributes
	sim=Sim.new();sim.setup(RulesLoader.load_rules(),"forest",73026,"rivet",false,{"vision_enabled":false})
	assert(int(sim.map.size)==320)
	var terrain_identity: String=JSON.stringify({"terrain":sim.map.terrain,"heights":sim.map.heights,"bridges":sim.map.bridges,"roads":sim.map.get("road_mark_cells",{})}).sha256_text()
	for id in sim.entities.keys(): sim._kill_entity(id,false)
	var base:=Vector2(float(sim.map.starts[0][0]),float(sim.map.starts[0][1]))
	for entry: Array in [["hq",Vector2(-8,-6)],["power",Vector2(-8,5)],["factory",Vector2(2,4)],["repair",Vector2(-2,13)],["tower",Vector2(12,0)]]:
		sim._spawn(0,"rivet_"+str(entry[0]),base+entry[1],true)
	for point: Vector2 in [Vector2(9,3),Vector2(13,6)]:sim._spawn(0,"rivet_tank",base+point,true)
	for point: Vector2 in [Vector2(7,15),Vector2(12,14)]:sim.debug_spawn_squad(0,"rivet_rifle",base+point,true)
	sim.events.clear();create_world()
	await shot("base",Vector3(base.x+1,MapData.height_at(sim.map,base)+1,base.y+3),Vector3(12,27,38),34,4,"formal_320_forest")
	assert(terrain_identity==JSON.stringify({"terrain":sim.map.terrain,"heights":sim.map.heights,"bridges":sim.map.bridges,"roads":sim.map.get("road_mark_cells",{})}).sha256_text())
	evidence[-1]["map_geometry_sha256"]=terrain_identity;evidence[-1]["geometry_unchanged"]=true
	await fresh_display()
	for team in 4:
		var x: float=84+team*8
		deploy(team,"hq",Vector2(x,88))
		deploy(team,"tank",Vector2(x-1.5,96))
		deploy(team,"heavy_tank",Vector2(x+1.5,100))
	create_world()
	await shot("factions",Vector3(96,1,94),Vector3(6,28,42),25,3,"authored_192_model_display")
	await fresh_display()
	for team in 4:
		var x: float=89+team*4
		deploy(team,"heavy_tank",Vector2(x,94))
		deploy(team,"tank",Vector2(x,99))
	create_world()
	await shot("armor",Vector3(95,0.5,96.5),Vector3(2.5,10,16),10.5,2,"authored_192_model_display")
	await fresh_display(true)
	deploy(0,"carrier",Vector2(92,92))
	deploy(1,"ship_frigate",Vector2(100,90))
	deploy(2,"ship_frigate",Vector2(87,97))
	deploy(3,"support_ship",Vector2(98,100))
	for team in [0,2]:
		var id: int=deploy(team,"helicopter",Vector2(92+team*3,96))
		sim.entities[id].airborne=true;sim.entities[id].flight_height=4.0;sim.entities[id].state="move"
	create_world()
	await shot("fleet",Vector3(94,1,95),Vector3(7,16,24),15.5,4,"authored_192_model_display")
	await fresh_display()
	for point: Vector2 in [Vector2(94,96),Vector2(98,96)]:
		sim.debug_spawn_squad(0,"kestrel_rifle",point,true)
	deploy(0,"tank",Vector2(89,97))
	deploy(0,"engineer",Vector2(91.5,95.5))
	create_world()
	await shot("infantry",Vector3(95,.5,96),Vector3(3,8,14),9.5,3,"authored_192_model_display")
	var manifest: Dictionary={"scope":"Local preview only. Native 3840x2160 in-engine models, formal 320 Forest base plus authored 192 display scenes. No HUD, DOF, camera movement, 48-cell maps or source enlargement.","renderer":RenderingServer.get_current_rendering_method(),"device":RenderingServer.get_video_adapter_name(),"godot":Engine.get_version_info().string,"resolution":[SIZE.x,SIZE.y],"fps":FPS,"mode":"motion" if motion else "stills","shots":evidence}
	FileAccess.open(OUT+("capture_manifest.json" if motion else "stills_manifest.json"),FileAccess.WRITE).store_string(JSON.stringify(manifest,"\t"))
	await clear_world();stage.free();await process_frame;quit()
