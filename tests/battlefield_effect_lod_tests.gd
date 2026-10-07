extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const Geometry = preload("res://scripts/battlefield_effect_lod.gd")
const Damage = preload("res://scripts/battlefield_damage.gd")
var failures: Array[String] = []
var checks: int = 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures.append(label)
func sync(world, delta: float=0.0) -> void:
	world.sync(delta,[])
	world.sim.events.clear()
func run() -> void:
	root.size=Vector2i(1280,720)
	var sim=Sim.new();sim.setup(RulesLoader.load_rules(),"dev",7,"rivet",false)
	var camera:=Camera3D.new();root.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=16.0
	camera.position=Vector3(24,24,50);camera.look_at(Vector3(24,0,28))
	var world:=PaperWorld.new();root.add_child(world);world.setup(sim,camera);world.set_destruction_seed(9009)
	for faction: String in ["rivet","kestrel","iron","sky"]:
		var id: int = sim.debug_spawn(0,faction+"_factory",Vector2(24,28))
		sim.entities[id].hp*=.4
		sync(world)
		var part: Dictionary=world.models[id].render_parts[0]
		var counts: Array[int]=[]
		for tier: int in 3: counts.append(Geometry.triangles(part.lod_batches[tier].multi.mesh))
		check(counts[0]>counts[1] and counts[1]>counts[2],"damaged "+faction+" building has independently reduced far and extreme geometry "+str(counts))
		for tier: int in 3:
			world.lod_override=tier;sync(world)
			check(world._batch_transforms(part.lod_batches[tier]).has(part.node.global_transform),"damaged building renderer selects requested tier "+str([faction,tier]))
		sim._kill_entity(id,false);sync(world)
	for tier: int in [1,2]:
		var cheap: Mesh=Geometry.solid(AABB(Vector3(-1,-1,-1),Vector3(2,2,2)),Color.WHITE,tier)
		var raw: Array=cheap.surface_get_arrays(0)
		var vertices: PackedVector3Array=raw[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array=raw[Mesh.ARRAY_NORMAL]
		for face: int in range(0,vertices.size(),3):
			var cross: Vector3=(vertices[face+1]-vertices[face]).cross(vertices[face+2]-vertices[face])
			var center: Vector3=(vertices[face]+vertices[face+1]+vertices[face+2])/3.0
			check(cross.dot(normals[face])<0.0 and center.dot(normals[face])>0.0,"cheap fragment tier has clockwise front faces and outward normals "+str(tier))
	var sphere_counts: Array[int]=[]
	for mesh: Mesh in world.effect_spheres: sphere_counts.append(Geometry.triangles(mesh))
	check(sphere_counts[0]>sphere_counts[1] and sphere_counts[1]>sphere_counts[2] and sphere_counts[2]<=8,"blast and smoke have three actual reduced meshes "+str(sphere_counts))
	world.lod_override=0
	var tank: int=sim.debug_spawn(0,"rivet_tank",Vector2(24,28));sync(world)
	sim._kill_entity(tank,true);sync(world,.37)
	var fragments: Array=world.effects.filter(func(effect):return effect.kind=="debris")
	var triangle_totals: Array[int]=[0,0,0]
	for fragment: Dictionary in fragments:
		check(fragment.lod_batches.size()==3,"every shrapnel piece owns three render tiers")
		for tier: int in 3: triangle_totals[tier]+=Geometry.triangles(fragment.lod_batches[tier].multi.mesh)
	check(triangle_totals[0]>triangle_totals[1] and triangle_totals[1]>triangle_totals[2],"shrapnel tiers reduce actual triangle work "+str(triangle_totals))
	var blast_counts: Array[int]=[]
	for tier: int in 3:
		world.lod_override=tier;sync(world)
		var blast_count: int=0
		var seen: Dictionary={}
		for fragment: Dictionary in fragments:
			check(int(fragment.lod_tier)==tier and world._batch_transforms(fragment.lod_batches[tier]).has(fragment.graphic.global_transform),"occupied shrapnel remains rendered at chosen tier "+str(tier))
		for blast: Dictionary in world.effects:
			if blast.kind=="death_blast":
				var key: int = blast.lod_batches[tier].multi.get_instance_id()
				if not seen.has(key): blast_count+=world._batch_count(blast.lod_batches[tier]); seen[key]=true
		blast_counts.append(blast_count)
	check(blast_counts[0]>blast_counts[1] and blast_counts[1]>blast_counts[2] and blast_counts[2]>0,"distant small blast clusters retain distributed lobes "+str(blast_counts))
	world.lod_override=-1
	var observed: Array[int]=[]
	for size: float in [12.0,70.0,300.0]:
		camera.size=size;sync(world)
		var central: Dictionary=world.effects.filter(func(effect):return bool(effect.get("cluster_primary",false)))[0]
		observed.append(int(central.lod_tier))
	check(observed==[0,1,2],"real camera zoom selects explosion near/far/extreme by projected size "+str(observed))
	world.configure_quality("performance")
	world._spawn_effect(Vector2(24,28),"death",2.0,.8,Vector3(4,2,3))
	world._spawn_smoke(Vector2(24,28),1.0,.3)
	for tier: int in 3:
		world.lod_override=tier;sync(world)
		check(world.data_effects.all(func(effect):return int(effect.lod_tier)==tier),"compact data explosions and smoke retain projected LOD tiers "+str(tier))
	world.free();camera.free();await process_frame
	check(Damage.world_users==0 and Damage.fragment_tasks.is_empty() and Damage.fragment_meshes.is_empty() and Damage.fragment_arrays.is_empty() and Damage.fragment_builds.is_empty() and Damage.damaged_meshes.is_empty(),"last world joins geometry workers and releases all renderer-owned caches")
	print("BATTLEFIELD_EFFECT_LOD ",JSON.stringify({"checks":checks,"fragment_triangles":triangle_totals,"sphere_triangles":sphere_counts,"failures":failures}))
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
