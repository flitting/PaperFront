extends SceneTree

const Sim=preload("res://tests/rule_test_simulation.gd")
const Geometry=preload("res://scripts/battlefield_effect_lod.gd")
const OUTPUT="res://artifacts/av_revision_v9_20261006/visual/"
var world: PaperWorld
var sim
var camera: Camera3D
var stage: Node3D
var rows: Array=[]
func _initialize() -> void: call_deferred("run")
func sync(delta: float=0.0) -> void:
	world.sync(delta,[]);sim.events.clear()
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
	rows.append({"capture":name,"animation_time":time,"small_blasts":bursts.size(),"shards":shards.size(),"scatter_pattern":world.last_scatter_pattern,"drawn_effect_triangles":triangles,"drawn_effect_instances":instances,"scorch_marks":world.craters.size()})
func run() -> void:
	if DisplayServer.get_name()=="headless":push_error("Real GPU/display required");quit(1);return
	root.size=Vector2i(1600,900)
	stage=Node3D.new();root.add_child(stage)
	var environment:=WorldEnvironment.new();var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR;settings.background_color=Color("b7ab91")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;settings.ambient_light_color=Color("ece5d5");settings.ambient_light_energy=.75
	environment.environment=settings;stage.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-30,0);light.light_energy=1.15;light.shadow_enabled=true;stage.add_child(light)
	camera=Camera3D.new();stage.add_child(camera);camera.current=true;camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=12
	camera.position=Vector3(24,23,52);camera.look_at(Vector3(24,.7,29))
	sim=Sim.new();sim.setup(RulesLoader.load_rules(),"dev",7,"rivet",false)
	for id: int in sim.entities.keys():sim._kill_entity(id,false)
	for z: int in 48:
		for x: int in 48:sim.map.terrain[z][x]=0;sim.map.heights[z][x]=0.0
	sim.ruins.clear();sim.mines.clear();sim.bridges.clear()
	for key: String in ["ruins","mines","bridges","decorations"]:
		if sim.map.has(key):sim.map[key].clear()
	sim._prepare_terrain_cache();sim.events.clear()
	world=PaperWorld.new();stage.add_child(world);world.setup(sim,camera);world.configure_quality("balanced")
	for scenario: String in ["tank","factory"]:
		clear_effects();world.lod_override=0;world.set_destruction_seed(9009)
		var id: int=sim._spawn(0,"rivet_"+scenario,Vector2(24,29),true)
		for frame: int in 100:sync(.016)
		sim._kill_entity(id,true);sync(1.0/60.0)
		await capture(scenario+"_first_frame",1.0/60.0)
		sync(.1-1.0/60.0);await capture(scenario+"_t0_1",.1)
		sync(.4);await capture(scenario+"_t0_5",.5)
		for tier: int in 3:
			world.lod_override=tier;sync(0)
			await capture(scenario+"_lod_"+["near","far","ultra"][tier],.5)
		sync(2.0);await capture(scenario+"_settled_scorch",2.5)
	clear_effects();world.lod_override=-1;world.set_destruction_seed(9009)
	for point: Vector2 in [Vector2(21,29),Vector2(24,29),Vector2(27,29)]:world._spawn_crater(point,1.05,.18)
	sync(0);await capture("soft_flat_scorch_marks",0)
	var report: Dictionary={"revision":"v9","scope":"Real Forward+ frozen fixtures; simultaneous small blast volumes, immediate limited randomized shards; flat soft black scorch, no real audio/simulation ticks.","seed":9009,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"rows":rows}
	var file:=FileAccess.open(OUTPUT+"capture_report.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("DESTRUCTION_V9_GPU ",JSON.stringify(report))
	stage.free();await process_frame;quit()
