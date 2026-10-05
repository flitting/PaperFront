extends SceneTree
const CONNECTIONS = preload("res://scripts/wall_connections.gd")
var failures: Array[String] = []
var checks: int = 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)
func _initialize() -> void: call_deferred("run")
func wall(id: int, pos: Vector2, team: int = 0, spec: String = "iron_wall") -> Dictionary:
	return {"id": id, "kind": "building", "pos": pos, "team": team, "spec": spec, "hp": 100.0}
func run() -> void:
	var rules: Dictionary = RulesLoader.load_rules()
	var entities: Dictionary = {1: wall(1, Vector2(10.5, 10.5))}
	var original: Dictionary = entities.duplicate(true)
	for index in range(4): entities[index + 2] = wall(index + 2, entities[1].pos + CONNECTIONS.DIRECTIONS[index])
	var masks: Dictionary = CONNECTIONS.masks(entities, rules)
	check(masks[1] == 15 and masks[2] == CONNECTIONS.WEST and masks[3] == CONNECTIONS.NORTH, "four-way center and reciprocal endpoints")
	entities.erase(4)
	check(CONNECTIONS.masks(entities, rules)[1] == 11, "destroying an adjacent wall changes the junction to a tee")
	entities[2].team = 1
	check(CONNECTIONS.masks(entities, rules)[1] == 10 and CONNECTIONS.masks(entities, rules)[2] == 0, "capture disconnects the hostile edge on both sides")
	entities[2].team = 0
	entities[2].pos += Vector2(.02, 0)
	check(CONNECTIONS.masks(entities, rules)[1] == 10, "off-grid proximity does not connect")
	check(entities[1] == original[1] and not entities[1].has("wall_mask"), "connectivity does not modify authoritative entities")
	for faction in ["rivet", "kestrel", "iron", "sky"]:
		var spec: Dictionary = rules.buildings[faction + "_wall"]
		var baseline: Dictionary = VolumeModels._recipe(spec, "building", 0)
		var original_mesh: ArrayMesh = baseline.body_mesh
		var triangle_count: int = original_mesh.surface_get_array_len(0)
		var geometries: Dictionary = {}
		for mask in range(16):
			var connected: Dictionary = spec.duplicate(true)
			connected.wall_mask = mask
			var recipe: Dictionary = VolumeModels._recipe(connected, "building", 0)
			check(recipe.body_mesh == VolumeModels._recipe(connected, "building", 0).body_mesh, faction + " connection meshes are cached per mask")
			if mask == 0:
				check(recipe.body_mesh == original_mesh, faction + " isolated wall keeps its complete original model")
				continue
			var arrays: Array = recipe.body_mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var valid: bool = vertices.size() == normals.size() and vertices.size() > triangle_count / 3
			for point in vertices: valid = valid and point.is_finite()
			for normal in normals: valid = valid and normal.is_finite() and normal.length() > .9
			check(valid, faction + " connected " + str(mask) + " retains detailed solid lit geometry")
			check(recipe.body_mesh.surface_get_material(0) == original_mesh.surface_get_material(0), faction + " connected pigment uses the original material")
			for direction in range(4):
				if not mask & (1 << direction): continue
				var axis: Vector2 = CONNECTIONS.DIRECTIONS[direction]
				var edge_points: int = 0
				for point in vertices:
					if is_equal_approx(Vector2(point.x, point.z).dot(axis), .5) and point.y > .3: edge_points += 1
				check(edge_points >= 6, faction + " arm reaches shared half-cell boundary " + str(direction))
			geometries[mask] = hash(var_to_bytes(vertices))
		check(geometries[3] != geometries[5] and geometries[7] != geometries[15], faction + " corner, straight, tee and cross have different geometry")
		check(VolumeModels._recipe(spec, "building", 0).body_mesh == original_mesh, faction + " variants leave the baseline recipe intact")
	# Both renderers must refresh cached connectivity after lifecycle changes.
	var sim := WarSimulation.new()
	sim.setup(rules, "dev", 7, "iron", false)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(24, 40, 62)
	camera.look_at(Vector3(24, 0, 28))
	for native in [false, true]:
		var world := PaperWorld.new()
		root.add_child(world)
		world.setup(sim, camera)
		world.native_world_sync_enabled = native
		var first: int = sim._spawn(0, "iron_wall", Vector2(21.5, 28.5), true)
		world.sync(0.0, [])
		check(world.models[first].wall_mask == 0, "renderer starts with isolated wall")
		var next: int = sim._spawn(0, "iron_wall", Vector2(22.5, 28.5), true)
		world.sync(0.0, [])
		check(world.models[first].wall_mask == 1 and world.models[next].wall_mask == 4, "renderer updates existing endpoint after new construction")
		sim.entities[next].team = 1
		world.sync(0.0, [])
		check(world.models[first].wall_mask == 0 and world.models[next].wall_mask == 0 and world.models[next].team == 1, "renderer capture refreshes both connectivity and owner paint")
		sim.entities[next].team = 0
		world.sync(0.0, [])
		sim._kill_entity(next, true)
		world.sync(0.0, [])
		check(world.models[first].wall_mask == 0 and not world.models.has(next), "renderer destruction refreshes the surviving endpoint")
		sim._kill_entity(first, true)
		world.queue_free()
		await process_frame
	camera.queue_free()
	await process_frame
	print("WALL_CONNECTIONS ", JSON.stringify({"checks": checks, "failures": failures}))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
