extends SceneTree

const Sim=preload("res://tests/rule_test_simulation.gd")
const Map=preload("res://scripts/map_data.gd")
const Motion=preload("res://scripts/aircraft_visual_motion.gd")
var checks: int=0
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label)
func sync(world,delta: float=.033333) -> void:
	world.sync(delta,[]);world.sim.events.clear()
func new_world(sim,camera) -> PaperWorld:
	var world:=PaperWorld.new();root.add_child(world);world.setup(sim,camera);world.set_destruction_seed(1007);return world
func clean_effects(world) -> void:
	for effect: Dictionary in world.effects:effect.root.queue_free()
	world.effects.clear();world.data_effects.clear();world.craters.clear()
func run() -> void:
	root.size=Vector2i(1280,720)
	var sim=Sim.new();sim.setup(RulesLoader.load_rules(),"dev",7,"rivet",false)
	for z: int in 48:
		for x: int in 48:
			sim.map.terrain[z][x]=Map.LAND
			sim.map.heights[z][x]=8.0 if x>=24 and x<33 else 0.0
	sim._prepare_terrain_cache()
	var camera:=Camera3D.new();root.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=45
	camera.position=Vector3(24,36,56);camera.look_at(Vector3(24,5,28))
	var world:=new_world(sim,camera)
	var id: int=sim._spawn(0,"rivet_fighter",Vector2(7,28),true)
	var e: Dictionary=sim.entities[id];e.state="move";e.airborne=true;e.flight_height=5.0;e.alpha=0.0
	sync(world)
	var model: Dictionary=world.models[id]
	var previous_y: float=model.art_root.global_position.y
	var rose_before_cliff: bool=false
	var fell_after_cliff: bool=false
	var ys: Array=[]
	for frame: int in 130:
		e.pos+=Vector2(8.0/30.0,0)
		var state: Dictionary=e.duplicate(true)
		sync(world,1.0/30.0)
		var y: float=model.art_root.global_position.y
		ys.append(y)
		check(absf(y-previous_y)<=Motion.CLIMB_RATE/30.0+.01,"world altitude advances continuously across both cliff edges")
		check(y>=Map.height_at(sim.map,e.pos)+2.1,"visual flight retains safe current terrain clearance")
		check(e==state,"visual climb changes no simulation entity height, heading, navigation or state")
		if e.pos.x>18 and e.pos.x<24 and y>6.0:rose_before_cliff=true
		if e.pos.x>34 and y<previous_y:fell_after_cliff=true
		previous_y=y
	check(rose_before_cliff and fell_after_cliff,"terrain look-ahead causes early ascent and a gentle descent after the mountain")
	check(world.air_trails.any(func(trail):return absf(trail.pos.y-trail.start.y)>.01),"continuous exhaust segments follow the actual sloping visual flight altitude")
	check(model.root.global_position.y+float(model.flight_height)==float(model.visual_air_y),"renderer root/art offset composes exactly to cosmetic world altitude")
	var target_id: int=sim._spawn(0,"kestrel_fighter",Vector2(22,28),true)
	var target: Dictionary=sim.entities[target_id];target.airborne=true;target.flight_height=5.0;target.state="move";target.alpha=0.0
	sync(world)
	var target_model: Dictionary=world.models[target_id]
	target_model.visual_air_y=Map.height_at(sim.map,target.pos)+9.0
	target_model.logical_flight_height=5.0
	target_model.flight_height=9.0
	var target_offset: float=world._visual_air_offset(target_id)
	check(is_equal_approx(target_offset,4.0),"air targeting exposes only the cosmetic height offset")
	var shell: Dictionary={"source":id,"target":target_id,"spec":"rivet_fighter","team":0,"start":e.pos,"landing":target.pos,"elapsed":0.0,"duration":.5,"source_height":5.0,"target_height":5.5,"heading":0.0,"body_heading":0.0}
	var snapshot_shell: Dictionary=shell.duplicate(true)
	var source_offset: float=world._projectile_source_air_offset(shell)
	check(is_equal_approx(source_offset,world._visual_air_offset(id)) and shell==snapshot_shell,"projectile launch caches visual climb offset without altering source-height protocol")
	var hit_event: Dictionary={"kind":"impact","pos":target.pos,"team":0,"target":target_id,"height":5.5,"blast":.5,"projectile":true}
	sim.events.append(hit_event);var event_copy: Dictionary=hit_event.duplicate(true)
	world._read_events()
	var impact: Dictionary=world.effects.filter(func(effect):return effect.kind=="blast").back()
	check(is_equal_approx(impact.root.position.y,Map.height_at(sim.map,target.pos)+9.5) and hit_event==event_copy,"air impact uses the rendered target height without changing gameplay event fields")
	sim.events.clear()

	# Prepare a low-ground moving airplane, keeping actual renderer history.
	e.pos=Vector2(10,28);e.flight_height=6.0
	model.erase("visual_air_y");model.erase("air_motion_pos");model.erase("visual_air_velocity")
	sync(world)
	for frame: int in 10:e.pos+=Vector2(.25,0);sync(world,.033333)
	clean_effects(world)
	var aircraft_root: Node3D=model.root
	var start: Vector3=model.art_root.global_position
	var events_before: int=sim.events.size()
	sim._kill_entity(id,true)
	for event: Dictionary in sim.events:
		if event.kind=="death":event.velocity=Vector2(7.5,0);event.heading=0;event.flight_height=6.0;event.airborne=true
	var remaining: Dictionary=sim.entities.duplicate(true)
	var projectiles: Array=sim.projectiles.duplicate(true)
	world.sync(.033333,[])
	check(world.ghosts.any(func(ghost):return ghost.kind=="air_crash"),"lethal airborne hit retains the real authored aircraft model as a crash ghost")
	check(world.effects.is_empty() and world.data_effects.is_empty() and world.craters.is_empty(),"aircraft loss creates no in-place explosion or pre-impact fragments")
	check(not world.air_crash_smoke.is_empty() and world.air_crash_smoke[0].pos.y>3.0,"the falling aircraft starts trailing dense smoke at actual flight altitude")
	var crash: Dictionary=world.ghosts.filter(func(ghost):return ghost.kind=="air_crash")[0]
	check(crash.model.root==aircraft_root and crash.velocity.x>6.0,"crash uses the cached authored model and measured horizontal inertia")
	sim.events.clear()
	sync(world,.25)
	check(model.root.position.x>start.x+1.0 and model.root.position.y<start.y,"aircraft moves forward while descending on its parabolic crash trajectory")
	check(world.effects.is_empty() and not world.ghosts.is_empty(),"debris is deferred until the actual hull reaches the terrain")
	world.configure_quality("performance");sync(world,0)
	check(world.ghosts.any(func(ghost):return ghost.kind=="air_crash" and ghost.model.root==aircraft_root),"switching quality preserves the real airborne crash instead of deleting it")
	world.configure_quality("balanced")
	for tier: int in 3:
		world.lod_override=tier;sync(world,0)
		check(int(model.lod_tier)==tier,"the intact falling aircraft retains its near/far/ultra authored model tiers")
		check(world.air_crash_smoke.all(func(puff):return int(puff.lod_tier)==tier),"crash smoke retains real projected sphere tiers")
	world.lod_override=-1
	var impact_count: int=0
	for frame: int in 100:
		sync(world,.025)
		if not world.ghosts.any(func(ghost):return ghost.kind=="air_crash"):
			impact_count+=1;break
	check(impact_count==1 and world.effects.any(func(effect):return effect.kind=="debris"),"ground contact ends the fall once and produces painted wreck fragments")
	check(not model.root.visible and not world.craters.is_empty(),"grounded wreck pools the aircraft hierarchy and leaves a ground scorch")
	check(sim.entities==remaining and sim.projectiles==projectiles and sim.events.is_empty(),"visual crash contact causes no extra damage, simulation events or projectile impacts")
	var fragments_before: int=world.effects.filter(func(effect):return effect.kind=="debris").size()
	sync(world,.05)
	check(world.effects.filter(func(effect):return effect.kind=="debris").size()==fragments_before,"crash contact cannot emit its debris twice")
	# A water crash follows the real water sheet and cannot leave land scorch.
	clean_effects(world)
	for z: int in range(22,35):
		for x: int in range(5,22):sim.map.terrain[z][x]=Map.WATER
	var water_id: int=sim._spawn(0,"rivet_fighter",Vector2(10,28),true)
	var water_e: Dictionary=sim.entities[water_id];water_e.flight_height=5;water_e.airborne=true;water_e.state="idle"
	sync(world)
	sim._kill_entity(water_id,true);sync(world)
	for frame: int in 130:
		sync(world,.025)
		if not world.ghosts.any(func(ghost):return ghost.kind=="air_crash"):break
	check(world.craters.is_empty() and world.effects.any(func(effect):return effect.kind=="debris"),"water impact produces debris at water height without a land scorch mark")
	# Stress the live-model budget without manufacturing an air contact blast.
	clean_effects(world);world.air_crash_smoke.clear()
	for index: int in 14:
		var stress_id: int=sim._spawn(0,"rivet_fighter",Vector2(10+index*.2,28),true)
		var stress: Dictionary=sim.entities[stress_id];stress.flight_height=20.0;stress.airborne=true
		sync(world,.001);sim._kill_entity(stress_id,true);sync(world,.001)
	check(world.ghosts.filter(func(ghost):return ghost.kind=="air_crash").size()==world.MAX_AIR_CRASHES,"simultaneous real aircraft falls stay within the normal model budget")
	check(world.effects.is_empty() and world.craters.is_empty(),"budget eviction pools quietly and never explodes an aircraft above terrain")
	world.configure_quality("performance");sync(world,.01)
	check(world.ghosts.filter(func(ghost):return ghost.kind=="air_crash").size()==6,"performance mode keeps six falling aircraft instead of clearing all falls")
	camera.position=Vector3(1000,25,1000);camera.look_at(Vector3(1000,0,1020))
	for frame: int in 65:sync(world,.1)
	check(world.ghosts.is_empty(),"offscreen crash physics and contact still expire within their lifetime budget")
	check(world.air_crash_smoke.size()<=96,"performance crash smoke stays inside the bounded pooled data budget")
	for frame: int in 30:sync(world,.1)
	check(world.air_crash_smoke.is_empty(),"lingering crash smoke is reclaimed even outside the camera")
	world.free();camera.free();await process_frame
	print("AIRCRAFT_VISUAL_MOTION ",JSON.stringify({"checks":checks,"failures":failures,"ascent_before_edge":rose_before_cliff,"descent_after_edge":fell_after_cliff,"height_range":[ys.min(),ys.max()]}))
	for failure: String in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
