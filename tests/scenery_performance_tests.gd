extends SceneTree

const Landscape = preload("res://scripts/landscape.gd")
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func fixture(mode: String):
	# Render-build diagnosis only: this avoids constructing a second large
	# navigation graph while another probe measures the real game simulation.
	var sim := WarSimulation.new()
	sim.rules = RulesLoader.load_rules()
	sim.map = MapData.generate(mode, 7)
	sim.ruins = sim.map.ruins.duplicate(true)
	for raw in sim.map.mines:
		sim.mines.append({"pos": Vector2(raw.pos[0], raw.pos[1]), "capacity": float(raw.capacity), "amount": float(raw.capacity), "miner": -1})
	for raw in sim.map.bridges:
		sim.bridges.append({"id": raw.id, "bounds": raw.bounds, "heads": raw.heads, "alive": true, "hp": 1200.0, "repair_progress": 0.0})
	for team in range(2): sim.entities[team + 1] = {"kind": "building", "spec": sim.factions[team] + "_hq", "pos": Vector2(sim.map.starts[team][0], sim.map.starts[team][1])}
	return sim

func test_paint_equivalence() -> void:
	var builder = Landscape.new()
	builder._map = MapData.generate("dev", 7)
	builder._map.terrain[40][14] = MapData.BLOCKED
	builder._noise.seed = 7
	builder._noise.frequency = .073
	builder._noise.fractal_octaves = 3
	builder._prepare_battle_marks()
	builder._prepare_terrain_features()
	var same_distance: bool = true
	var same_context: bool = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 7194
	for i in range(200):
		var point := Vector2(rng.randf_range(0, 47.99), rng.randf_range(0, 47.99))
		var level: float = MapData.height_at(builder._map, point)
		var sample := Vector2(floorf(point.x * .5) * 2.0, floorf(point.y * .5) * 2.0)
		builder._terrain_features_ready = false
		builder._ground_contexts.clear()
		builder._ground_paint_samples.clear()
		var distance_before: Vector3 = builder._ground_paint_distance_sample(sample.x, sample.y, level)
		var context_before: Vector2 = builder._ground_context(point.x, point.y)
		builder._terrain_features_ready = true
		builder._ground_contexts.clear()
		builder._ground_paint_samples.clear()
		same_distance = same_distance and distance_before.is_equal_approx(builder._ground_paint_distance_sample(sample.x, sample.y, level))
		same_context = same_context and context_before.is_equal_approx(builder._ground_context(point.x, point.y))
	check(same_distance, "regional paint lookup preserves the original nearest forest/rim/road distances")
	check(same_context, "regional paint lookup preserves the original continuous ground context")
	builder.free()

func test_shadow_cap_union() -> void:
	var builder = Landscape.new()
	var tiles := PackedFloat32Array()
	tiles.resize(Landscape.CHUNK * Landscape.CHUNK)
	tiles.fill(INF)
	for z in range(3):
		for x in range(4):
			if x != 1 or z != 1: tiles[z * Landscape.CHUNK + x] = 4.0
	var data: Dictionary = builder._data()
	builder._append_coalesced_shadow_caps(data, tiles, 0, 0, 4, 3)
	var area: float = 0.0
	var avoids_hole: bool = true
	var same_height: bool = true
	for i in range(0, data.vertices.size(), 3):
		var a: Vector3 = data.vertices[i]
		var b: Vector3 = data.vertices[i + 1]
		var c: Vector3 = data.vertices[i + 2]
		area += (b - a).cross(c - a).length() * .5
		same_height = same_height and absf(a.y - 3.94) < .00001 and absf(b.y - 3.94) < .00001 and absf(c.y - 3.94) < .00001
		avoids_hole = avoids_hole and not Geometry2D.is_point_in_polygon(Vector2(1.5, 1.5), PackedVector2Array([Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)]))
	check(absf(area - 11.0) < .00001 and avoids_hole and same_height, "merged shadow caps preserve the exact plane union, omitted cells and offset")
	check(data.vertices.size() / 3 < 22, "merged flat caps reduce triangles without removing ground coverage")
	builder.free()

func run() -> void:
	test_paint_equivalence()
	test_shadow_cap_union()
	var sim = fixture("dev")
	var landscape = Landscape.build(sim)
	root.add_child(landscape)
	var scans: int = int(landscape.stats.resource_full_scans)
	var updates: int = int(landscape.stats.resource_updates)
	check(not landscape._forest_lods.is_empty(), "pine draws register complete near/far/extreme mesh tiers")
	check(not landscape._trunk_lods.is_empty() and landscape._trunk_lods.all(func(lod): return lod.meshes.size() == 3 and lod.meshes[0] == lod.source and lod.near == lod.node), "trunk tiers retain one original draw and destruction slots")
	var full_trunk: Mesh = landscape._prop_mesh("trunk")
	var far_trunk: Mesh = landscape._prop_mesh("trunk_far")
	check(far_trunk.surface_get_array_len(0) < full_trunk.surface_get_array_len(0) * .25, "subpixel root decorations use less than a quarter of the original distant geometry")
	var distant_trunk:Mesh=landscape._prop_mesh("trunk_distant")
	check(distant_trunk.custom_aabb==far_trunk.get_aabb() and distant_trunk.surface_get_array_len(0)==318 and far_trunk.surface_get_array_len(0)==498,"distant bark drops only sixty ink triangles and retains conservative trunk/root culling bounds")
	var original_arrays:Array=far_trunk.surface_get_arrays(0)
	var distant_arrays:Array=distant_trunk.surface_get_arrays(0)
	var triangles:Dictionary={}
	for offset in range(0,original_arrays[Mesh.ARRAY_VERTEX].size(),3):
		var key:Array=[]
		for attribute in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_COLOR]:
			for corner in range(3):key.append(original_arrays[attribute][offset+corner])
		triangles[key]=int(triangles.get(key,0))+1
	var exact_subset:bool=true
	for offset in range(0,distant_arrays[Mesh.ARRAY_VERTEX].size(),3):
		var key:Array=[]
		for attribute in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_COLOR]:
			for corner in range(3):key.append(distant_arrays[attribute][offset+corner])
		if int(triangles.get(key,0))==0:exact_subset=false
		else:triangles[key]-=1
	check(exact_subset,"remaining distant trunk/root triangles preserve exact positions, normals, paint and winding")
	for policy: String in ["native", "balanced", "performance"]:
		landscape.configure_quality(policy)
		check(landscape._forest_lods.all(func(lod): return lod.meshes[0] == lod.source and lod.near.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON), "near pine paint/geometry/shadow preserved " + policy)
		check(landscape._trunk_lods.all(func(lod): return lod.meshes[1] == far_trunk and lod.meshes[2] == distant_trunk), "two authored distant bark tiers preserved " + policy)

	for i in range(100): landscape.sync_resources(sim)
	check(scans == 1 and landscape.stats.resource_full_scans == scans and landscape.stats.resource_updates == updates, "idle scenery frames do no whole-forest scans or transform updates")
	var tree: Dictionary = sim.ruins.filter(func(e): return e.kind == "tree")[0]
	tree.hp = 0.0
	sim.events.append({"kind": "ruin_destroy", "id": tree.id, "pos": tree.pos})
	landscape.sync_resources(sim)
	check(int(landscape.stats.resource_updates) == updates + 1 and landscape.tree_visuals[tree.id].all(func(piece): return piece.current_transform.basis.x.length() == 0.0), "a destruction event updates only its tree's visible and shadow slots immediately")
	landscape.sync_resources(sim)
	check(int(landscape.stats.resource_updates) == updates + 1, "re-reading a retained event never resubmits unchanged forest transforms")
	var restored = Landscape.build(sim)
	root.add_child(restored)
	check(restored.stats.terrain_cache_hit and restored.stats.terrain_triangles == landscape.stats.terrain_triangles and restored.stats.ground_chunks == landscape.stats.ground_chunks, "rebuilding the same terrain reuses exact static mesh resources")
	check(restored.tree_visuals[tree.id].all(func(piece): return piece.current_transform.basis.x.length() == 0.0), "cached terrain rebuild still reconciles loaded destruction state")
	landscape.queue_free()
	restored.queue_free()
	await process_frame
	print("Scenery performance checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
