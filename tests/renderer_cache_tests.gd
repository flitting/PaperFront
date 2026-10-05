extends SceneTree

const Sim=preload("res://tests/rule_test_simulation.gd")
const World=preload("res://tests/transport_world_probe.gd")
const Construction=preload("res://scripts/outpost_construction.gd")
var failures:Array[String]=[]
var checks:int=0

func _initialize() -> void:
	call_deferred("run")

func check(ok:bool,message:String) -> void:
	checks+=1
	if not ok:failures.append(message)

func run() -> void:
	var rules:Dictionary=RulesLoader.load_rules()
	var sim=Sim.new()
	sim.setup(rules,"dev",7,"rivet",false)
	var camera:=Camera3D.new()
	root.add_child(camera)
	camera.fov=42
	camera.position=Vector3(12,12,53)
	camera.look_at(Vector3(12,0,39))
	var world=World.new()
	root.add_child(world)
	world.setup(sim,camera)
	world.profile_enabled=true
	var near_id:int=sim.debug_spawn(0,"rivet_tank",Vector2(12.5,39.5))
	var far_id:int=sim.debug_spawn(0,"rivet_tank",Vector2(42.5,45.5))
	world.sync(0.0,[near_id])
	var near_model:Dictionary=world.models[near_id]
	var far_model:Dictionary=world.models[far_id]
	var far_root:Node3D=far_model.root
	check(not near_model.view_culled and far_model.view_culled,"visible units are kept while distant offscreen cosmetics are culled")
	check(int(world.profile_last.uploaded_transforms)>0,"initial visible models upload their batched transforms")
	world.sync(0.0,[near_id])
	check(int(world.profile_last.uploaded_transforms)==0 and int(world.profile_last.submitted_transforms)>0,"identical stationary frame reuses uploaded matrices without dropping render instances")
	sim.entities[near_id].hp=float(rules.units.rivet_tank.hp)*.5
	world.sync(0.0,[near_id])
	check(is_equal_approx(float(near_model.hp_fraction),.5) and int(world.profile_last.uploaded_transforms)>0,"health changes invalidate cached bars")
	sim.entities[far_id].pos=Vector2(41.5,44.5)
	world.sync(0.0,[near_id])
	check(far_model.last_pos==sim.entities[far_id].pos and is_equal_approx(far_root.position.x,41.5),"culled units retain accurate world anchors for picking and event locations")
	camera.position=Vector3(41.5,12,58.5)
	camera.look_at(Vector3(41.5,0,44.5))
	world.sync(0.0,[far_id])
	check(not far_model.view_culled and far_model.root==far_root and int(world.profile_last.uploaded_transforms)>0,"camera movement restores existing offscreen models before rendering")
	var original_root:Node3D=far_model.root
	sim.entities[far_id].team=1
	world.sync(0.0,[far_id])
	check(world.models[far_id].root!=original_root and world.models[far_id].team==1,"ownership changes invalidate visual caches")
	var engineer:int=sim.debug_spawn(0,"rivet_engineer",Vector2(38.5,44.5))
	var outpost:int=sim.debug_spawn(0,"rivet_outpost",Vector2(34.5,39.5))
	Construction.initialize(sim,sim.entities[outpost],engineer)
	world.sync(0.0,[outpost])
	var scaffold:Dictionary=world.models[outpost]
	check(scaffold.scaffold,"construction scaffolds preserve their separate cached model")
	sim.entities[outpost].construction.progress=.4
	world.sync(0.0,[outpost])
	check(is_equal_approx(float(scaffold.last_progress),.4) and scaffold.progress_fill.scale.x>0.0,"construction progress updates cached scaffold sections and progress bars")
	sim.entities[outpost].erase("construction")
	sim.entities[outpost].construct_remaining=0.0
	world.sync(0.0,[outpost])
	check(not world.models[outpost].scaffold and world.models[outpost].root!=scaffold.root,"completion replaces the scaffold cache with the finished building")
	var site:=Vector2(29.5,39.5)
	sim.building_orders[0]={"spec":"rivet_outpost","builder":engineer}
	world.sync(0.0,[],{"spec":"rivet_outpost","pos":site,"valid":true})
	var guide_count:int=world.circle_radii.size()
	world.sync(0.0,[],{"spec":"rivet_outpost","pos":site,"valid":true})
	check(world.circle_radii.size()==guide_count,"stationary placement preview reuses expansion guide geometry")
	world.sync(0.0,[],{"spec":"rivet_outpost","pos":site+Vector2(1,0),"valid":true})
	check(world.circle_radii.size()>guide_count,"moving the placement preview refreshes its guide geometry")
	camera.h_offset=2.0
	camera.v_offset=1.5
	world._cache_view_planes()
	var shifted_view:Transform3D=camera.get_camera_transform()
	check(world._point_in_view(shifted_view.origin-shifted_view.basis.z*5.0,0.0),"frustum culling respects the real camera transform with lens offsets")
	camera.h_offset=0.0
	camera.v_offset=0.0
	world._spawn_effect(Vector2(40.5,44.5),"impact",1.2,.2)
	world._spawn_smoke(Vector2(40.5,44.5),1.2)
	world._spawn_debris(Vector2(40.5,44.5),1.2,.5)
	world.sync(.1,[])
	check(world.effects.all(func(effect):return not effect.graphic.visible),"particle instances use shared batches without duplicate standalone draws")
	var blast_material:StandardMaterial3D=world.material_cache.particle_instances_blast
	check(blast_material.emission_enabled and is_equal_approx(blast_material.emission_energy_multiplier,.35) and blast_material.shading_mode==BaseMaterial3D.SHADING_MODE_PER_PIXEL,"batched fireballs preserve their lighting and emission settings")
	var exact_color:Color=Color("ff9d28").lerp(Color("8b3521"),.1/.38)
	exact_color.a=1.0-.1/.38
	var has_exact_color:bool=false
	for batch in world.batches.values():
		if batch.multi.use_colors:
			for color in world._batch_colors(batch):
				if (color as Color).is_equal_approx(exact_color):has_exact_color=true
	check(has_exact_color,"continuous particle tint and alpha are preserved in instance colors")
	check(world.effects.filter(func(effect):return effect.kind=="debris").map(func(effect):return effect.graphic.mesh.get_instance_id()).duplicate().size()==10 and world.debris_meshes.size()==3,"ten debris pieces retain the same three original size variants")
	print("RENDERER_CACHE ",JSON.stringify({"checks":checks,"failures":failures,"profile":world.profile_last}))
	world.queue_free()
	camera.queue_free()
	await process_frame
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
