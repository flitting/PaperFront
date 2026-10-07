extends SceneTree

const Policy = preload("res://scripts/model_lod.gd")
const Sim = preload("res://tests/rule_test_simulation.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func triangles(mesh: Mesh) -> int:
	var count: int = 0
	for surface in range(mesh.get_surface_count()):
		count += (mesh.surface_get_array_index_len(surface) if mesh.surface_get_array_index_len(surface) > 0 else mesh.surface_get_array_len(surface))/3
	return count

func run() -> void:
	root.size = Vector2i(1920,1080)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.fov = 42
	camera.position = Vector3(24,30,70)
	camera.look_at(Vector3(24,0,35))
	for projection: int in [Camera3D.PROJECTION_PERSPECTIVE,Camera3D.PROJECTION_ORTHOGONAL]:
		camera.projection = projection
		for keep_aspect: int in [Camera3D.KEEP_WIDTH,Camera3D.KEEP_HEIGHT]:
			camera.keep_aspect = keep_aspect
			var center: Vector3 = camera.global_position-camera.global_basis.z*50.0
			var first: Vector2 = camera.unproject_position(center-camera.global_basis.y)
			var last: Vector2 = camera.unproject_position(center+camera.global_basis.y)
			check(is_equal_approx(first.distance_to(last),Policy.projected_pixels(camera,center,2.0)),"projected size matches actual camera projection/aspect "+str([projection,keep_aspect]))
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	var sim = Sim.new()
	sim.setup(RulesLoader.load_rules(),"dev",7,"rivet",false)
	var world := PaperWorld.new()
	root.add_child(world)
	world.setup(sim,camera)
	world.profile_enabled = true
	var ids: Array[int] = []
	for spec in ["rivet_tank","kestrel_hq","sky_creator_hand","rivet_rifle"]:
		ids.append(sim._spawn(0,spec,Vector2(24,35),true))
	world.sync(0.0,[])
	var rules_snapshot: Dictionary = sim.entities.duplicate(true)
	for native in [false,true]:
		world.native_world_sync_enabled = native
		for tier in range(3):
			world.lod_override = tier
			world.sync(0.0,[])
			for id in ids:
				var model: Dictionary = world.models[id]
				check(int(model.lod_tier) == tier,"native/script selects the requested model tier "+str([native,tier,model.pool_spec]))
				if model.volumetric:
					for part in model.render_parts:
						var batch: Dictionary = part.lod_batches[tier]
						check(world._batch_transforms(batch).has(part.node.global_transform),"body/turret chosen tier is drawn at the real articulated transform")
					for item in model.get("skinned_lods",[]):
						check(item.node.mesh == item.meshes[tier] and item.node.skin != null,"creator hand swaps geometry while retaining actual skeleton skin")
				else:
					check(world._batch_transforms(model.paper_lod_batches[tier]).has(model.root.global_transform*model.art_root.transform),"paper tier retains the illustrated heading/mirror transform")
		check(sim.entities == rules_snapshot,"LOD selection changes no authoritative unit state native="+str(native))
	var tank: Dictionary = world.models[ids[0]]
	var near_count: int = triangles(tank.render_parts[0].lod_batches[0].multi.mesh)
	var far_count: int = triangles(tank.render_parts[0].lod_batches[1].multi.mesh)
	var extreme_count: int = triangles(tank.render_parts[0].lod_batches[2].multi.mesh)
	check(near_count > far_count and far_count > extreme_count,"rigid body has three genuinely different complexity tiers")
	var paper: Dictionary = world.models[ids[3]]
	check(triangles(paper.paper_lod_batches[0].multi.mesh)>triangles(paper.paper_lod_batches[1].multi.mesh) and triangles(paper.paper_lod_batches[2].multi.mesh)==2,"paper far silhouette and extreme alpha-cut quad reduce geometry")
	check(paper.paper_lod_batches[0].multi.mesh.surface_get_material(0)==paper.paper_lod_batches[2].multi.mesh.surface_get_material(0),"far paper preserves original illustration and owner-mask material")
	world.lod_override = -1
	world.lod_enabled = true
	var center := Vector3(24,0,35)
	var diameter: float = (tank.dimensions as Vector2).length()
	var scale: float = float(Policy.view(camera).scale)
	# Move through the actual projection boundary repeatedly. Tiny changes must
	# not recreate models or switch back and forth while the camera is held near it.
	var expected: Array[int] = [0,0,1,1,1,0,2,2,1]
	var pixels: Array[float] = [80,63,55,65,63,72,17,20,23]
	for index in range(pixels.size()):
		var depth: float = diameter*scale/pixels[index]
		camera.position = center+Vector3(0,0,depth)
		camera.look_at(center)
		world.sync(0.0,[])
		check(int(tank.lod_tier)==expected[index],"real camera motion uses hysteresis at projected size "+str(pixels[index]))
		check(int(world.profile_last.models_created)==0,"camera LOD transitions reuse the existing model hierarchy")
	# Projection changes alter visibility even if camera position stays fixed.
	camera.position = Vector3(0,5,20)
	camera.look_at(Vector3.ZERO)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.0
	world._cache_view_planes()
	check(not world._point_in_view(Vector3(10,0,0),0.0),"small orthographic viewport excludes the side point")
	camera.size = 40.0
	world._cache_view_planes()
	check(world._point_in_view(Vector3(10,0,0),0.0),"orthographic zoom refreshes culling with an unchanged camera pose")
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	for native in [false,true]:
		world.native_world_sync_enabled = native
		camera.position = Vector3(24,40,70)
		camera.look_at(center)
		world.sync(0.0,[])
		var hand: Dictionary = world.models[ids[2]]
		check(hand.root.visible,"visible skinned model restores its actual draw node native="+str(native))
		camera.position = Vector3(3,30,5)
		camera.look_at(Vector3(3,0,0))
		world.sync(0.0,[])
		check(hand.view_culled and not hand.root.visible,"offscreen skinned model is hidden in both renderer paths native="+str(native))
	camera.position = Vector3(24,40,70)
	camera.look_at(center)
	world.lod_override = 0
	var placement: Dictionary = {"spec":"rivet_hq","pos":Vector2(24,35),"valid":true,"builder":-1}
	world.sync(0.0,[],placement)
	var preview_root: Node3D = world.placement_node
	var preview_source: Mesh = world._placement_lod.parts[0].node.mesh
	world.lod_override = 2
	world.sync(0.0,[],placement)
	check(world.placement_node==preview_root and triangles(world._placement_lod.parts[0].node.mesh)<triangles(preview_source),"stationary construction preview responds to a new camera LOD without recreation")
	world.configure_quality("performance")
	world.lod_override = 0
	world.sync(0.0,[])
	sim._kill_entity(ids[0],true)
	world.sync(0.0,[])
	check(world.data_corpses.is_empty() and world.ghosts.is_empty(),"performance destruction replaces the complete model immediately")
	var fragment_triangles: int = 0
	for effect: Dictionary in world.effects:
		if effect.kind=="debris": fragment_triangles+=triangles(effect.graphic.mesh)
	check(fragment_triangles>0 and fragment_triangles<=(far_count+triangles(tank.render_parts[1].lod_batches[1].multi.mesh))*4,"flying fragments retain painted geometry with a bounded far-mesh budget")
	world.queue_free()
	camera.queue_free()
	await process_frame
	print("MODEL_LOD ",JSON.stringify({"checks":checks,"triangles":[near_count,far_count,extreme_count],"failures":failures}))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
