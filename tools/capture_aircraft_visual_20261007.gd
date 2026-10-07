extends SceneTree

const Sim=preload("res://tests/rule_test_simulation.gd")
const Geometry=preload("res://scripts/battlefield_effect_lod.gd")
const OUTPUT="res://artifacts/aircraft_visual_20261007/visual/"
var world: PaperWorld
var sim
var camera: Camera3D
var stage: Node3D
var rows: Array=[]
func _initialize() -> void: call_deferred("run")
func sync(delta: float=0.0) -> void:
	world.sync(delta,[]);sim.events.clear()
func advance(duration: float) -> void:
	var left: float=duration
	while left>0.00001:
		var step: float=minf(left,1.0/30.0);sync(step);left-=step
func clear_effects() -> void:
	for effect: Dictionary in world.effects: effect.root.queue_free()
	world.effects.clear();world.data_effects.clear();world.craters.clear()
func capture(name: String, time: float) -> void:
	for frame: int in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+name+".png")
	var triangles: int=0;var instances: int=0;var seen: Dictionary={}
	for effect: Dictionary in world.effects:
		var key: int=effect.batch.multi.get_instance_id()
		if seen.has(key): continue
		seen[key]=true
		var count: int=world._batch_count(effect.batch)
		instances+=count;triangles+=count*Geometry.triangles(effect.batch.multi.mesh)
	var bursts: Array=world.effects.filter(func(effect):return effect.kind=="death_blast")
	var shards: Array=world.effects.filter(func(effect):return effect.kind=="debris")
	var smoke_triangles: int=0;var smoke_instances: int=0
	for batch: Dictionary in world._air_crash_smoke_lods:
		var count: int=world._batch_count(batch)
		smoke_instances+=count;smoke_triangles+=count*Geometry.triangles(batch.multi.mesh)
	var crash_models: Array=world.ghosts.filter(func(ghost):return ghost.kind=="air_crash")
	var crash_triangles: int=0
	for crash: Dictionary in crash_models:
		for part: Dictionary in crash.model.render_parts:
			var tier: int=int(crash.model.lod_tier)
			crash_triangles+=Geometry.triangles(part.lod_batches[tier].multi.mesh)
	var flight_heights: Array=[]
	for model: Dictionary in world.models.values():
		if bool(model.get("is_air",false)):flight_heights.append({"visual_y":model.visual_air_y,"logical_height":model.logical_flight_height,"position":str(model.root.position)})
	rows.append({"capture":name,"animation_time":time,"small_blasts":bursts.size(),"shards":shards.size(),"scatter_pattern":world.last_scatter_pattern,"drawn_effect_triangles":triangles,"drawn_effect_instances":instances,"scorch_marks":world.craters.size(),"air_crashes":crash_models.size(),"crash_model_triangles":crash_triangles,"crash_smoke":world.air_crash_smoke.size(),"drawn_crash_smoke_instances":smoke_instances,"drawn_crash_smoke_triangles":smoke_triangles,"live_flight_heights":flight_heights})
func run() -> void:
	if DisplayServer.get_name()=="headless":push_error("Real GPU/display required");quit(1);return
	root.size=Vector2i(1600,900)
	stage=Node3D.new();root.add_child(stage)
	var environment:=WorldEnvironment.new();var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR;settings.background_color=Color("b7ab91")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;settings.ambient_light_color=Color("ece5d5");settings.ambient_light_energy=.75
	environment.environment=settings;stage.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-30,0);light.light_energy=1.15;light.shadow_enabled=true;stage.add_child(light)
	camera=Camera3D.new();stage.add_child(camera);camera.current=true;camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=23
	camera.position=Vector3(24,26,49);camera.look_at(Vector3(24,7,27))
	sim=Sim.new();sim.setup(RulesLoader.load_rules(),"dev",7,"rivet",false)
	for id: int in sim.entities.keys():sim._kill_entity(id,false)
	sim.map.size=128;sim.map.heights=[];sim.map.terrain=[]
	for z: int in 128:
		var heights: Array=[];var terrain: Array=[]
		for x: int in 128:terrain.append(0);heights.append(20.0 if x>=64 and x<85 else 0.0)
		sim.map.heights.append(heights);sim.map.terrain.append(terrain)
	sim._size=128
	sim.ruins.clear();sim.mines.clear();sim.bridges.clear()
	for key: String in ["ruins","mines","bridges","decorations"]:
		if sim.map.has(key):sim.map[key].clear()
	sim._prepare_terrain_cache();sim.events.clear()
	world=PaperWorld.new();stage.add_child(world);world.setup(sim,camera);world.configure_quality("balanced")
	world.set_destruction_seed(9009)
	world.lod_override=0
	var plane: int=sim._spawn(0,"rivet_fighter",Vector2(7,27),true)
	var e: Dictionary=sim.entities[plane];e.airborne=true;e.flight_height=5.0;e.state="move";e.alpha=0.0
	sync(.016)
	for frame: int in 220:
		e.pos+=Vector2(12.0/30.0,0)
		camera.size=30;camera.position=Vector3(e.pos.x+10,44,57);camera.look_at(Vector3(e.pos.x+10,12,27))
		sync(1.0/30.0)
		if frame in [70,106,144,215]:await capture("terrain_flight_"+str(frame),float(frame)/30.0)
	# Demonstrate one real-model crash over the mountain plateau.
	camera.size=23;camera.position=Vector3(70,42,49);camera.look_at(Vector3(70,25,27))
	e.pos=Vector2(68,27);e.flight_height=6.0
	world.models[plane].erase("visual_air_y");world.models[plane].erase("air_motion_pos")
	sync(.016)
	for frame: int in 8:e.pos+=Vector2(.20,0);sync(.025)
	clear_effects();world.air_trails.clear();sim._kill_entity(plane,true);sync(.016)
	await capture("aircraft_crash_first_frame",.016)
	advance(.28);await capture("aircraft_crash_t0_3",.296)
	for tier: int in 3:
		world.lod_override=tier;sync(0);await capture("aircraft_crash_lod_"+["near","far","ultra"][tier],.296)
	world.lod_override=0;advance(.35);await capture("aircraft_crash_t0_65",.646)
	for frame: int in 45:sync(.033333)
	await capture("aircraft_crash_ground_wreck",2.146)
	# Owner-color regions on the actual skinned Creator hand, with both owners.
	clear_effects();world.air_trails.clear();world.air_crash_smoke.clear()
	camera.size=20;camera.position=Vector3(24,23,45);camera.look_at(Vector3(24,3,25))
	var a: int=sim._spawn(0,"sky_creator_hand",Vector2(18,25),true)
	var b: int=sim._spawn(1,"sky_creator_hand",Vector2(29,25),true)
	sim.entities[b].visible_to=255
	for tier: int in 3:
		world.lod_override=tier;sync(.016);await capture("creator_hand_owners_"+["near","far","ultra"][tier],0)
	var report: Dictionary={"revision":"aircraft_visual_20261007","scope":"Real Forward+ terrain overflight, authored smoking aircraft crash and two-team continuous skinned Creator hand. Visual only, no gameplay damage or audio.","seed":9009,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"rows":rows}
	var file:=FileAccess.open(OUTPUT+"capture_report.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("AIRCRAFT_VISUAL_GPU ",JSON.stringify(report))
	stage.free();await process_frame;quit()
