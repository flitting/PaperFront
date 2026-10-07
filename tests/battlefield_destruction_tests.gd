extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const Damage = preload("res://scripts/battlefield_damage.gd")
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)
func sync(world, delta: float = .016) -> void:
	world.sync(delta,[])
	world.sim.events.clear()
func effects_of(world, kind: String) -> Array:
	return world.effects.filter(func(effect): return str(effect.kind)==kind)

func run() -> void:
	var sim = Sim.new()
	sim.setup(RulesLoader.load_rules(),"dev",7,"rivet",false)
	for z: int in 48:
		for x: int in 48:
			sim.map.terrain[z][x]=0
			sim.map.heights[z][x]=0.0
	sim._prepare_terrain_cache()
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position=Vector3(24,25,55)
	camera.look_at(Vector3(24,0,29))
	var world := PaperWorld.new()
	root.add_child(world)
	world.setup(sim,camera)
	world.set_destruction_seed(9009)
	sim.events.clear()
	for faction: String in ["rivet","kestrel","iron","sky"]:
		var id: int = sim.debug_spawn(0,faction+"_power",Vector2(24,29))
		sync(world)
		var e: Dictionary = sim.entities[id]
		var model: Dictionary = world.models[id]
		var source: Mesh = model.render_parts[0].node.mesh
		var healthy_vertices: PackedVector3Array = source.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var healthy_colors: PackedColorArray = source.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		e.hp=float(model.spec.hp)*.49
		sync(world)
		check(model.damage_stage==1 and model.render_parts[0].node.mesh!=source,"low HP visibly damages "+faction+" building")
		check(source.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]==healthy_vertices and source.surface_get_arrays(0)[Mesh.ARRAY_COLOR]==healthy_colors,"damage never mutates shared healthy "+faction+" art")
		check(model.render_parts[0].node.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]!=healthy_colors,"localized scorched paint survives "+faction+" damage")
		var first: Mesh = model.render_parts[0].node.mesh
		e.hp=float(model.spec.hp)*.20
		sync(world)
		check(model.damage_stage==2 and model.render_parts[0].node.mesh!=first,"critical HP increases "+faction+" damage")
		e.hp=float(model.spec.hp)
		sync(world)
		check(model.damage_stage==0 and model.render_parts[0].node.mesh==source,"repair restores exact healthy "+faction+" model")
		var crater_count: int = world.craters.size()
		sim._kill_entity(id,false)
		sync(world)
		check(world.craters.size()==crater_count and world.effects.is_empty(),"selling "+faction+" building creates no death burst")
	check(Damage.damage_stage(.5)==1 and Damage.damage_stage(.25)==2 and Damage.damage_stage(.501)==0,"damage thresholds are explicit and reversible")
	var tank: int = sim.debug_spawn(0,"rivet_tank",Vector2(24,30))
	sync(world)
	var tank_e: Dictionary = sim.entities[tank]
	tank_e.state="move"
	var base: Vector2 = tank_e.pos
	for angle: int in range(0,181,6):
		tank_e.alpha=float(angle)
		sync(world)
	check(world.tracks.size()>70 and tank_e.pos==base,"stationary pivot creates paired circular tread arcs")
	var before: int = world.tracks.size()
	sync(world,8.0)
	check(world.tracks.size()==before,"pivot marks remain visible beyond the old five-second lifetime")
	tank_e.pos += Vector2(.12,0)
	sync(world,.03)
	tank_e.state="idle"
	var state: Dictionary = tank_e.duplicate(true)
	sync(world,.1)
	var tank_model: Dictionary = world.models[tank]
	check(tank_model.art_root.position.x>0.0 and tank_model.art_root.rotation.z<0.0,"arrival gives tank a slight forward brake and nose dip")
	check(tank_e==state and Vector2(tank_model.root.position.x,tank_model.root.position.z)==tank_e.pos,"braking preserves rules position, commands and collision centre")
	sync(world,.7)
	check(tank_model.art_root.position.x==0.0 and tank_model.art_root.rotation.z==0.0,"brake pose settles exactly to rest")
	var dimensions: Vector3 = tank_model.volume.dimensions
	var source_mesh: Mesh = tank_model.render_parts[0].lod_batches[1].multi.mesh
	for piece: Dictionary in Damage.fragments(source_mesh):
		var shard_size: Vector3 = piece.mesh.get_aabb().size
		check(shard_size.x<=source_mesh.get_aabb().size.x/4.0+.001 and shard_size.y<=source_mesh.get_aabb().size.y/2.0+.001 and shard_size.z<=source_mesh.get_aabb().size.z/2.0+.001,"clipped shards cannot retain oversized roof or hull triangles")
	tank_model.volume.body.rotation.x=.32
	tank_model.volume.body.scale=Vector3(1.1,.8,.9)
	sim._kill_entity(tank,true)
	sync(world,.12)
	check(world.ghosts.is_empty() and world.data_corpses.is_empty(),"death no longer wobbles or shrinks an intact model")
	var blasts: Array=effects_of(world,"death_blast")
	check(blasts.size()==24,"one retired tank creates one bounded dense small-blast cluster")
	check(blasts.all(func(blast):return float(blast.delay)==0.0 and bool(blast.small_burst) and blast.base.x<dimensions.x*.4),"all small blasts are born simultaneously without a giant central sphere")
	var spread:=AABB(blasts[0].root.global_position,Vector3.ZERO)
	for blast: Dictionary in blasts: spread=spread.expand(blast.root.global_position)
	check(spread.size.x>dimensions.x*.65 and spread.size.z>dimensions.z*.6,"small blasts cover the model footprint rather than occupying one central bubble")
	var fragments: Array = effects_of(world,"debris")
	check(fragments[0].has("world_velocity"),"detached tilted geometry keeps world-space gravity and velocity")
	sync(world,.25)
	var ballistic_fragment: Dictionary = fragments[0]
	var flight_age: float = minf(maxf(float(ballistic_fragment.age)-float(ballistic_fragment.get("delay",0.0)),0.0),float(ballistic_fragment.settle_age))
	var expected: Vector3 = ballistic_fragment.root.global_position+ballistic_fragment.world_velocity*flight_age+Vector3.DOWN*4.9*flight_age*flight_age
	expected.y=maxf(expected.y,float(ballistic_fragment.world_floor))
	check(ballistic_fragment.graphic.global_position.is_equal_approx(expected),"tilted and scaled fragment poses evaluate ballistic flight in world coordinates")
	check(not fragments.is_empty() and fragments.size()<=10,"death throws a bounded set of actual painted model fragments")
	check(not world.craters.is_empty(),"tank destruction leaves a crater")
	sync(world,2.2)
	fragments=effects_of(world,"debris")
	var settled: Array = []
	for fragment: Dictionary in fragments: settled.append(fragment.graphic.global_position)
	sync(world,1.0)
	for index: int in fragments.size():
		check(fragments[index].graphic.global_position.is_equal_approx(settled[index]),"landed model fragments remain as rubble")
	var crater_count: int = world.craters.size()
	sim.events.append({"kind":"impact","pos":Vector2(25,30),"team":0,"blast":0.0,"height":.18,"projectile":true})
	sync(world,.016)
	check(world.craters.size()==crater_count+1,"zero-splash direct shell leaves a small crater")
	var impact_smoke: Array = effects_of(world,"smoke").filter(func(effect): return float(effect.life)<5.0)
	check(impact_smoke.size()==3 and float(impact_smoke[0].life)>=3.4,"small shell smoke lingers for several seconds")
	sync(world,2.0)
	check(effects_of(world,"smoke").has(impact_smoke[0]),"shell smoke remains after two seconds")
	crater_count=world.craters.size()
	for event: Dictionary in [{"kind":"impact","pos":Vector2(26,30),"team":0,"blast":0.0,"height":.18,"projectile":false},{"kind":"impact","pos":Vector2(26,30),"team":0,"blast":1.0,"height":5.0,"projectile":true}]:
		sim.events.append(event)
		sync(world)
	check(world.craters.size()==crater_count,"bullets and airborne shell hits create no ground crater")
	sim.map.terrain[30][27]=MAP_WATER()
	world._spawn_crater(Vector2(27.5,30.5),1.0,.18)
	check(world.craters.size()==crater_count,"water impacts create no land crater")
	# Naval death effects use the water sheet, rather than terrain height.
	for z: int in range(25,36):
		for x: int in range(20,31): sim.map.terrain[z][x]=MAP_WATER()
	sim._prepare_terrain_cache()
	var ship: int=sim._spawn(0,"rivet_ship_frigate",Vector2(25,30),true)
	sync(world)
	var ship_model: Dictionary=world.models[ship]
	var burst_y: float=ship_model.root.global_position.y+float(ship_model.volume.dimensions.y)*.5
	crater_count=world.craters.size()
	sim._kill_entity(ship,true);sync(world,.12)
	var ship_burst: Dictionary=effects_of(world,"death_blast").filter(func(effect):return bool(effect.get("cluster_primary",false))).back()
	check(is_equal_approx(ship_burst.cluster_origin.y,burst_y),"naval destruction blast stays at the actual ship altitude")
	check(world.craters.size()==crater_count,"destroyed ships do not leave a land crater on water")
	check(effects_of(world,"debris").any(func(effect):return effect.has("world_floor") and float(effect.world_floor)<-1.0),"naval fragments settle on the true water sheet")
	world.configure_quality("performance")
	var building: int = sim.debug_spawn(0,"rivet_factory",Vector2(20,30))
	sync(world)
	sim._kill_entity(building,true)
	sync(world)
	check(not effects_of(world,"debris").is_empty() and not world.data_effects.is_empty(),"performance quality retains destruction fragments, explosion and smoke")
	check(world.effects.size()<=96 and world.craters.size()<=192,"persistent visual budgets remain bounded")
	world.free();camera.free()
	await process_frame
	print("BATTLEFIELD_DESTRUCTION ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func MAP_WATER() -> int: return preload("res://scripts/map_data.gd").WATER
