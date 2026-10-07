extends SceneTree

const Sim=preload("res://tests/rule_test_simulation.gd")
const Geometry=preload("res://scripts/battlefield_effect_lod.gd")
const OUTPUT="res://artifacts/feedback_v10_20261006/visual/"
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
	var cloud_triangles: int=0;var cloud_instances: int=0
	for patch: Dictionary in world.cloud_shadows:
		for batch: Dictionary in patch.batches:
			var count: int=world._batch_count(batch)
			cloud_instances+=count;cloud_triangles+=count*Geometry.triangles(batch.multi.mesh)
	var trail_triangles: int=0;var trail_instances: int=0
	for batch: Dictionary in world._air_trail_batches:
		var count: int=world._batch_count(batch)
		trail_instances+=count;trail_triangles+=count*Geometry.triangles(batch.multi.mesh)
	rows.append({"capture":name,"animation_time":time,"small_blasts":bursts.size(),"shards":shards.size(),"scatter_pattern":world.last_scatter_pattern,"drawn_effect_triangles":triangles,"drawn_effect_instances":instances,"scorch_marks":world.craters.size(),"air_trails":world.air_trails.size(),"fall_corpses":world.ghosts.filter(func(ghost):return ghost.kind=="infantry_fall").size(),"sell_folds":world.ghosts.filter(func(ghost):return ghost.kind=="sell_fold").size(),"cloud_shadow_patches":world.cloud_shadows.size(),"cloud_shadow_triangles":cloud_triangles,"cloud_shadow_instances":cloud_instances,"air_trail_triangles":trail_triangles,"air_trail_instances":trail_instances})
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
	clear_effects();world.lod_override=0;world.set_destruction_seed(9010)
	var rifle: int=sim._spawn(0,"rivet_rifle",Vector2(24,29),true);sync(.016)
	sim._kill_entity(rifle,true)
	for event: Dictionary in sim.events:
		if event.kind=="death" and int(event.id)==rifle:event.death_style="infantry_fall"
	sync(.016);await capture("infantry_fall_first_frame",.016)
	sync(.65);await capture("infantry_fallen",.666)
	sync(.95);await capture("infantry_fade",1.616)
	sync(1.0);clear_effects()
	rifle=sim._spawn(0,"rivet_rifle",Vector2(24,29),true);sync(.016)
	sim._kill_entity(rifle,true)
	for event: Dictionary in sim.events:
		if event.kind=="death" and int(event.id)==rifle:event.death_style="infantry_shatter"
	sync(.1);await capture("infantry_paper_shatter",.1)
	sync(.6);await capture("infantry_paper_shatter_landed",.7)
	clear_effects()
	var factory: int=sim._spawn(0,"rivet_factory",Vector2(24,29),true);sync(.016)
	sim._kill_entity(factory,false);sync(.18);await capture("building_sell_fold",.18)
	sync(.28);await capture("building_sell_fold_mid",.46)
	sync(.55);clear_effects()
	camera.size=20;camera.position=Vector3(24,28,53);camera.look_at(Vector3(24,4,29))
	var plane: int=sim._spawn(0,"rivet_fighter",Vector2(16,29),true)
	var entity: Dictionary=sim.entities[plane]
	entity.airborne=true;entity.flight_height=5.0;entity.state="move";entity.alpha=0
	sync(.016)
	for frame: int in 36:entity.pos+=Vector2(.40,0);sync(.035)
	for tier: int in 3:
		world.lod_override=tier;sync(0);await capture("aircraft_trail_"+["near","far","ultra"][tier],1.26)
	sim._kill_entity(plane,false);sync(.016);world.air_trails.clear()
	camera.size=34;camera.position=Vector3(24,30,54);camera.look_at(Vector3(24,0,24));world.lod_override=0
	world.elapsed=0.0;sync(0);await capture("cloud_shadow_t0",0)
	world.elapsed=18.0;sync(0);await capture("cloud_shadow_t18",18)
	for tier: int in 3:
		world.lod_override=tier;sync(0);await capture("cloud_shadow_lod_"+["near","far","ultra"][tier],18)
	var report: Dictionary={"revision":"v10","scope":"Real Forward+ infantry fall/shatter, quiet sell fold and airborne trails; no real audio/simulation ticks.","seed":9009,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"rows":rows}
	var file:=FileAccess.open(OUTPUT+"lifecycle_capture_report.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("DESTRUCTION_V9_GPU ",JSON.stringify(report))
	stage.free();await process_frame;quit()
