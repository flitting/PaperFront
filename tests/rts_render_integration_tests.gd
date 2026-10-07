extends SceneTree
const Sim = preload("res://tests/rule_test_simulation.gd")
var checks: int = 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message)
func run() -> void:
	var sim = Sim.new()
	sim.setup(RulesLoader.load_rules(),"dev",7,"sky",false)
	for row in sim.map.terrain:row.fill(0)
	for row in sim.map.heights:row.fill(0.0)
	sim.mines.clear();sim.bridges.clear();sim.ruins.clear();sim._refresh_ruin_spatial();sim._prepare_terrain_cache()
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position=Vector3(28,20,60)
	camera.look_at(Vector3(28,0,28))
	var world := PaperWorld.new()
	root.add_child(world)
	world.setup(sim,camera)
	for spec_id in ["sky_rifle","sky_anti","sky_engineer","kestrel_demolition"]:
		var id: int = sim._spawn(0,spec_id,Vector2(20,25),true)
		world.sync(.01,[])
		var model: Dictionary = world.models[id]
		check(not model.volumetric,"world uses original contour paper card "+spec_id)
		check(model.graphic.mesh.get_surface_count()==3,"original front, cut-paper thickness, and back remain "+spec_id)
		for tier in range(3):
			check(model.paper_lod_batches[tier].multi.mesh.surface_get_material(0).get_shader_parameter("illustration").resource_path.ends_with(spec_id+"_idle.svg"),"all LODs retain original illustration "+spec_id)
		check(not model.graphic.mesh.surface_get_material(0).shader.code.contains("MODELVIEW_MATRIX ="),"paper illustration has no forced billboard "+spec_id)
	var idle_soldier: int = sim._spawn(0,"sky_rifle",Vector2(22,26),true)
	var firing_soldier: int = sim._spawn(0,"sky_rifle",Vector2(24,26),true)
	sim.entities[idle_soldier].state="idle"
	sim.entities[firing_soldier].state="attack"
	sim.entities[firing_soldier].attack_flash=.25
	world.sync(.02,[])
	var idle_model: Dictionary = world.models[idle_soldier]
	var firing_model: Dictionary = world.models[firing_soldier]
	var idle_material: ShaderMaterial = idle_model.paper_lod_batches[0].multi.mesh.surface_get_material(0)
	var firing_material: ShaderMaterial = firing_model.paper_lod_batches[0].multi.mesh.surface_get_material(0)
	check(idle_material!=firing_material,"same-spec idle/firing soldiers retain independent immutable materials")
	for pose in ["idle","move","hit","attack"]:
		sim.entities[firing_soldier].attack_flash=0
		sim.entities[firing_soldier].hit_flash=.2 if pose=="hit" else 0
		sim.entities[firing_soldier].state=pose
		world.sync(.02,[])
		for tier in range(3):
			var texture: Texture2D = firing_model.paper_lod_batches[tier].multi.mesh.surface_get_material(0).get_shader_parameter("illustration")
			check(texture.resource_path.ends_with("_%s.svg" % pose),"live "+pose+" selects original action at LOD "+str(tier))
	check(idle_material.get_shader_parameter("illustration").resource_path.ends_with("_idle.svg"),"one soldier's actions never mutate its idle neighbor's shader")
	for native_mode in [false,true]:
		world.native_world_sync_enabled=native_mode
		sim.entities[idle_soldier].state="move"
		sim.entities[firing_soldier].state="attack"
		sim.entities[firing_soldier].alpha=135
		sim.entities[firing_soldier].hit_flash=0
		world.sync(.02,[])
		check(idle_model.paper_lod_batches[0].multi.mesh.surface_get_material(0).get_shader_parameter("illustration").resource_path.ends_with("_move.svg"),"per-unit move card in "+("native" if native_mode else "script")+" renderer")
		check(firing_model.paper_lod_batches[0].multi.mesh.surface_get_material(0).get_shader_parameter("illustration").resource_path.ends_with("_attack.svg"),"independent simultaneous attack card in "+("native" if native_mode else "script")+" renderer")
		check(is_equal_approx(firing_model.root.rotation.y,-deg_to_rad(135.0)) and firing_model.mirror,"original heading and mirrored face remain in both renderer paths")
	sim._kill_entity(firing_soldier,true)
	world.sync(.02,[])
	check(world.ghosts.any(func(g):return g.model==firing_model),"real unit death enters the paper corpse lifecycle")
	for tier in range(3):
		check(firing_model.corpse_batches[tier].multi.mesh.surface_get_material(0).get_shader_parameter("illustration").resource_path.ends_with("_death.svg"),"actual corpse uses original death drawing at LOD "+str(tier))
	world.ghosts.clear()
	var source: int = sim._spawn(0,"sky_pulse",Vector2(26,29),true)
	var target: int = sim._spawn(1,"rivet_tank",Vector2(32,29),true)
	sim.entities[source].turret_alpha=0
	sim._fire(sim.entities[source],target)
	world.sync(.02,[])
	check(world._beam_channels.size()==1,"continuous channel has one rendered beam")
	var old_end: Vector3 = world._beam_channels[source].beam_end
	sim.entities[target].pos=Vector2(32,31)
	world.sync(.05,[])
	check(world._beam_channels[source].beam_end.z>old_end.z+1.5,"beam follows the live moving target")
	sim.entities[source].emp_until=sim.time+4
	sim.BeamWeapons.step(sim,.05)
	sim.events.clear();world.sync(.05,[])
	check(world._beam_channels.is_empty(),"EMP removes beam immediately with its damage channel")
	sim.entities[source].emp_until=0
	sim.entities[source].cooldown=0
	sim.entities[source].turret_alpha=rad_to_deg((sim.entities[target].pos-sim.entities[source].pos).angle())
	sim._fire(sim.entities[source],target)
	world.sync(.05,[])
	check(world._beam_channels.size()==1,"channel can restart after EMP expires")
	sim.entities[target].pos=Vector2(54,52)
	sim.BeamWeapons.step(sim,.05);sim.events.clear();world.sync(.05,[])
	check(world._beam_channels.is_empty(),"beam cancels visually when target leaves range")
	var rail: int = sim._spawn(1,"iron_rail",Vector2(30.5,37.5),true)
	sim._spawn(1,"iron_rail",Vector2(31.5,37.5),true)
	sim._rail_network.rebuild(sim);world.sync(.01,[])
	var before: Node3D = world.models[rail].root
	sim._spawn(1,"iron_rail",Vector2(30.5,38.5),true)
	sim._rail_network.rebuild(sim);world.sync(.01,[])
	check(world.models[rail].root!=before and int(world.models[rail].spec.rail_mask)==3,"rail connection changes actually replace straight with corner geometry")
	var plane: int = sim._spawn(0,"sky_fighter",Vector2(37,26),true)
	sim.entities[plane].airborne=false
	sim.entities[plane].flight_height=.35
	sim.entities[plane].state="parked"
	world.sync(.01,[])
	check(is_equal_approx(float(world.models[plane].flight_height),.35),"parked aircraft rests at its actual stand height")
	sim.entities[plane].airborne=true
	sim.entities[plane].flight_height=float(sim.rules.units.sky_fighter.flight_height)
	sim.entities[plane].state="move"
	world.sync(.05,[])
	check(float(world.models[plane].flight_height)>.35 and float(world.models[plane].flight_height)<1.0,"takeoff climbs gradually without a first-frame altitude jump")
	for frame in range(40):world.sync(.05,[])
	var flight: float = float(world.models[plane].flight_height)
	sim.entities[plane].airborne=false
	sim.entities[plane].flight_height=.35
	sim.entities[plane].state="parked"
	world.sync(.05,[])
	check(float(world.models[plane].flight_height)>1.0 and float(world.models[plane].flight_height)<flight,"returning aircraft descends before resting instead of snapping to ground")
	for frame in range(80):world.sync(.05,[])
	check(is_equal_approx(float(world.models[plane].flight_height),.35),"landing finishes at the actual stand height")
	print("RTS_RENDER_INTEGRATION ",JSON.stringify({"checks":checks,"failures":failures}))
	world.queue_free();camera.queue_free()
	await process_frame
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
