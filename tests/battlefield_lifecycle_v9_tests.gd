extends SceneTree

const Sim=preload("res://tests/rule_test_simulation.gd")
var checks: int=0
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label)
func sync(world,delta: float=.016) -> void:
	world.sync(delta,[]);world.sim.events.clear()
func clear_effects(world) -> void:
	for effect: Dictionary in world.effects:effect.root.queue_free()
	world.effects.clear();world.data_effects.clear()
func run() -> void:
	var sim=Sim.new();sim.setup(RulesLoader.load_rules(),"dev",7,"rivet",false)
	for z: int in 48:
		for x: int in 48:sim.map.terrain[z][x]=0;sim.map.heights[z][x]=0.0
	sim._prepare_terrain_cache()
	var camera:=Camera3D.new();root.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=30
	camera.position=Vector3(24,30,55);camera.look_at(Vector3(24,0,29))
	var world:=PaperWorld.new();root.add_child(world);world.setup(sim,camera);world.set_destruction_seed(9010)
	var rifle: int=sim._spawn(0,"rivet_rifle",Vector2(24,29),true);sync(world)
	var model: Dictionary=world.models[rifle]
	clear_effects(world)
	sim._kill_entity(rifle,true)
	for event: Dictionary in sim.events:
		if event.kind=="death" and int(event.id)==rifle:event.death_style="infantry_fall"
	sync(world)
	check(world.ghosts.size()==1 and world.ghosts[0].kind=="infantry_fall","lethal bullet uses an authored infantry fall corpse")
	check(world.effects.is_empty() and world.craters.is_empty(),"bullet infantry death creates no explosion, smoke burst, debris or scorch")
	check(model.state=="death" and model.graphic.mesh.surface_get_material(0).get_shader_parameter("illustration")==load(world._texture_path(model.spec,"death")),"corpse uses the authored death card rather than reusing an idle pose")
	sync(world,.7)
	check(absf(model.art_root.rotation.x)>1.0 and is_equal_approx(absf(model.art_root.scale.y),1.0),"infantry physically falls over while retaining its model scale")
	check(model.corpse_batches.size()==3 and world._batch_count(model.corpse_batches[int(model.lod_tier)])>0,"fallen infantry remains drawn through its existing three LOD tiers")
	sync(world,1.6)
	check(world.ghosts.is_empty() and not model.root.visible,"fallen corpse fades out and returns its hierarchy to the pool")
	var paper: int=sim._spawn(0,"rivet_rifle",Vector2(24,29),true);sync(world)
	clear_effects(world)
	sim._kill_entity(paper,true)
	for event: Dictionary in sim.events:
		if event.kind=="death" and int(event.id)==paper:event.death_style="infantry_shatter"
	sync(world)
	check(world.ghosts.is_empty() and world.effects.size()==8 and world.effects.all(func(effect):return effect.kind=="debris" and effect.paper_fragment),"explosive infantry kill scatters eight textured paper fragments")
	check(world.effects.all(func(effect):return effect.graphic.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV] is PackedVector2Array) and world.craters.is_empty(),"paper shatter preserves source illustration UVs and adds no second explosion or scorch")
	clear_effects(world)
	var building: int=sim._spawn(0,"rivet_factory",Vector2(24,29),true);sync(world)
	var factory: Dictionary=world.models[building]
	clear_effects(world)
	sim._kill_entity(building,false);sync(world)
	check(world.ghosts.size()==1 and world.ghosts[0].kind=="sell_fold" and world.effects.is_empty(),"selling a building starts a quiet fold ghost")
	check(world.craters.is_empty(),"selling never generates a scorch mark")
	sync(world,.4)
	check(factory.art_root.scale.y>0.0 and factory.art_root.scale.y<.6,"sold building visibly folds down over its short dismantle interval")
	sync(world,.6)
	check(world.ghosts.is_empty() and not factory.root.visible,"sell fold finishes within one second and releases the model")
	var fighter: int=sim._spawn(0,"rivet_fighter",Vector2(20,29),true)
	var aircraft: Dictionary=sim.entities[fighter]
	aircraft.airborne=true;aircraft.flight_height=5.0;aircraft.state="move";aircraft.alpha=0
	sync(world)
	for frame: int in 20:
		aircraft.pos+=Vector2(.3,0);sync(world,.03)
	check(not world.air_trails.is_empty() and world.air_trails.all(func(trail):return trail.pos.y>4.8),"fast airborne aircraft emits pooled exhaust/cloud marks at flight altitude")
	check(world.air_trails.size()<=384,"aircraft trail record budget remains bounded")
	check(world.air_trails.all(func(trail):return trail.has("start") and (trail.pos-trail.start).length()>.01),"air exhaust uses continuous gradient segments rather than dotted sphere stamps")
	for index: int in range(2,world.air_trails.size()):
		check((world.air_trails[index].start-world.air_trails[index-2].pos).length()<.001,"consecutive segments join exactly on each exhaust line")
	var triangle_counts: Array=[]
	for batch: Dictionary in world._air_trail_batches:triangle_counts.append(preload("res://scripts/battlefield_effect_lod.gd").triangles(batch.multi.mesh))
	check(triangle_counts==[8,4,2],"continuous air ribbons own true near/far/ultra mesh reductions")
	var count: int=world.air_trails.size()
	for frame: int in 3:sync(world,.03)
	check(world.air_trails.size()==count,"parked aircraft generates no new trail records")
	for frame: int in 6:
		aircraft.pos+=Vector2(.015,0);sync(world,.03)
	check(world.air_trails.size()==count,"slow aircraft movement generates no trails")
	aircraft.airborne=false;aircraft.flight_height=.35
	aircraft.pos+=Vector2(.9,0);sync(world,.03)
	check(world.air_trails.size()==count,"grounded taxi/parked planes leave no air trail")
	aircraft.airborne=true;aircraft.flight_height=5;aircraft.transport_id=999
	aircraft.pos+=Vector2(.9,0);sync(world,.03)
	check(world.air_trails.size()==count,"loaded aircraft cannot emit trails")
	aircraft.transport_id=-1
	for tier: int in 3:
		world.lod_override=tier;sync(world,0)
		check(world.air_trails.all(func(trail):return int(trail.lod_tier)==tier),"air trails select the real projected sphere LOD tier "+str(tier))
	sync(world,3.0)
	check(world.air_trails.is_empty(),"air trails fade and expire within their short lifetime")
	check(world.cloud_shadows.size()==6,"ground cloud shadows use only six pooled local receiver patches")
	var map_before: Dictionary=sim.map.duplicate(true)
	var time_before: float=float(world.cloud_shadows[0].material.get_shader_parameter("drift_time"))
	sync(world,5.0)
	check(float(world.cloud_shadows[0].material.get_shader_parameter("drift_time"))>time_before and sim.map==map_before,"cloud shadows drift visually without changing authoritative terrain or camera-clearance heights")
	for patch: Dictionary in world.cloud_shadows:
		var counts: Array=[]
		for batch: Dictionary in patch.batches:
			counts.append(preload("res://scripts/battlefield_effect_lod.gd").triangles(batch.multi.mesh))
			var positions: PackedVector3Array=batch.multi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			check(Array(positions).all(func(point):return point.x>=0 and point.z>=0 and point.x<float(sim.map.size) and point.z<float(sim.map.size)),"cloud receivers stay strictly inside actual map bounds")
		check(counts[0]>counts[1] and counts[1]>counts[2],"terrain cloud receivers have real three-tier mesh reductions")
	world.free();camera.free();await process_frame
	print("BATTLEFIELD_LIFECYCLE_V9 ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure: String in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
