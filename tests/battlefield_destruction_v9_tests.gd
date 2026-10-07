extends SceneTree

const Sim=preload("res://tests/rule_test_simulation.gd")
var checks: int=0
var failures: Array[String]=[]
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures.append(label)
func clear_effects(world) -> void:
	for effect: Dictionary in world.effects: effect.root.queue_free()
	world.effects.clear();world.data_effects.clear();world._fx_spawned=0
func signature(world) -> Array:
	var result: Array=[]
	for effect: Dictionary in world.effects:
		if effect.kind=="debris": result.append([effect.root.global_transform,effect.world_velocity,effect.spin,int(effect.scatter_pattern)])
	return result
func run() -> void:
	root.size=Vector2i(1280,720)
	var sim=Sim.new();sim.setup(RulesLoader.load_rules(),"dev",7,"rivet",false)
	for z: int in 48:
		for x: int in 48: sim.map.terrain[z][x]=0;sim.map.heights[z][x]=0.0
	sim._prepare_terrain_cache()
	var camera:=Camera3D.new();root.add_child(camera)
	camera.position=Vector3(24,24,50);camera.look_at(Vector3(24,0,29))
	var world:=PaperWorld.new();root.add_child(world);world.setup(sim,camera)
	var id: int=sim._spawn(0,"rivet_tank",Vector2(24,29),true)
	world.sync(.016,[]);sim.events.clear()
	var model: Dictionary=world.models[id]
	var before: Dictionary=sim.entities.duplicate(true)
	world.set_destruction_seed(9009);world._spawn_model_fragments(model)
	var first: Array=signature(world)
	check(first.size()==10,"normal tanks detach ten authored painted shards, rather than twenty-eight")
	check(world.effects.all(func(effect):return effect.kind!="debris" or float(effect.get("delay",0))==0.0),"debris participates in the first explosion frame with no reveal delay")
	world._begin_batches();world._update_effects(.016)
	check(world.effects.any(func(effect):return effect.kind=="debris" and effect.graphic.position.length()>.01),"debris has already moved after the first rendered frame")
	check(sim.entities==before,"fragment previews never change simulation entities or commands")
	clear_effects(world)
	world.set_destruction_seed(9009);world._spawn_model_fragments(model)
	check(signature(world)==first,"seeded capture override reproduces selected geometry, pattern, velocity and spin")
	var patterns: Dictionary={}
	for seed: int in range(1,25):
		clear_effects(world);world.set_destruction_seed(seed);world._spawn_model_fragments(model)
		patterns[world.last_scatter_pattern]=true
		check(world.effects.size()==10 and world.effects.all(func(effect):return effect.has("world_velocity") and effect.world_velocity.y>0),"each randomized pattern preserves a bounded world-gravity launch")
	check(patterns.size()==4,"runtime RNG can choose all four distinct scatter patterns")
	clear_effects(world)
	world.lod_override=0;world.set_destruction_seed(9009)
	world._spawn_effect(Vector2(24,29),"death",2.0,1.0,Vector3(4.1,1.87,3.33))
	var blasts: Array=world.effects.filter(func(effect):return effect.kind=="death_blast")
	check(blasts.size()==24 and blasts.all(func(effect):return effect.delay==0.0 and effect.base.x<1.5 and effect.small_burst),"twenty-four small blasts are born together across the model")
	world._begin_batches();world._update_effects(0.0)
	check(blasts.all(func(effect):return effect.graphic.scale.x>.5 and world._batch_transforms(effect.batch).has(effect.graphic.global_transform)),"every small blast is already visible at time zero")
	var counts: Array=[]
	for tier: int in 3:
		world.lod_override=tier;world._begin_batches();world._update_effects(0.0)
		counts.append(world._batch_count(blasts[0].lod_batches[tier]))
	check(counts==[24,8,4],"near/far/ultra use distributed clusters of 24/8/4 small lobes")
	world.set_destruction_seed(9009)
	world._spawn_crater(Vector2(25,29),1.5,.18)
	world._spawn_crater(Vector2(27,29),1.5,.18)
	var arrays: Array=world.crater_mesh.surface_get_arrays(0)
	check((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()==6 and Array(arrays[Mesh.ARRAY_VERTEX]).all(func(point):return is_zero_approx(point.y)),"scorch uses exactly two flat triangles with no raised lip or pit geometry")
	var material: ShaderMaterial=world.crater_mesh.surface_get_material(0)
	check(material.shader.code.contains("exp(-5.2*r*r)") and material.shader.code.contains("smoothstep(0.76,1.0,r)") and material.shader.code.contains("ALBEDO=vec3(0.008"),"scorch shader is black radial haze with a soft transparent edge")
	check(world.craters[0].transform.basis!=world.craters[1].transform.basis and world.craters[0].seed!=world.craters[1].seed,"persistent scorch marks vary rotation, stretch and streak grain")
	world.configure_quality("performance");clear_effects(world)
	world.set_destruction_seed(9009);world._spawn_effect(Vector2(24,29),"death",2,1,Vector3(4.1,1.87,3.33));world._spawn_model_fragments(model)
	check(world.data_effects.size()==12 and world.data_effects.all(func(effect):return effect.small_burst and effect.base.x<1.5),"performance quality uses a bounded cluster of twelve small blasts")
	check(world.effects.size()==6,"performance quality detaches only six authored shards")
	world.free();camera.free();await process_frame
	print("BATTLEFIELD_DESTRUCTION_V9 ",JSON.stringify({"checks":checks,"failures":failures,"blast_lobes":counts,"patterns":patterns.keys()}))
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
