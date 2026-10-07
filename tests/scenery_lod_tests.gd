extends SceneTree

const LOD = preload("res://scripts/scenery_mesh_lod.gd")
const MESH_LOD = preload("res://scripts/offline_mesh_lod.gd")
const MODEL_LOD = preload("res://scripts/model_lod.gd")
const CATALOG = preload("res://scripts/battlefield_catalog.gd")
const PAPER_CIVILIANS = preload("res://assets/civilians/paper_civilians.gd")
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func fixture(mode: String, seed: int = 7) -> WarSimulation:
	var sim := WarSimulation.new()
	sim.rules = RulesLoader.load_rules()
	sim.map = MapData.generate(mode, seed)
	sim.ruins = sim.map.ruins.duplicate(true)
	for mine: Dictionary in sim.map.mines:
		sim.mines.append({"pos": Vector2(mine.pos[0], mine.pos[1]), "capacity": mine.capacity, "amount": mine.capacity})
	for bridge: Dictionary in sim.map.bridges:
		var live: Dictionary = bridge.duplicate(true)
		live.alive = true
		sim.bridges.append(live)
	return sim

func check_mesh(source: Mesh, label: String) -> void:
	var tiers: Array[Mesh] = LOD.variants(source)
	check(tiers[0] == source and LOD.has_bake(source), "full/source and bake coverage " + label)
	for tier: int in [1, 2]:
		var mesh: Mesh = tiers[tier]
		check(mesh.get_surface_count() == source.get_surface_count() and mesh.get_aabb() == source.get_aabb(), "surfaces and conservative bounds " + label + str(tier))
		for surface: int in source.get_surface_count():
			var original: Array = source.surface_get_arrays(surface)
			var actual: Array = mesh.surface_get_arrays(surface)
			check(mesh.surface_get_material(surface) == source.surface_get_material(surface), "authored material " + label + str(tier))
			var same_attributes: bool = actual[Mesh.ARRAY_VERTEX] == original[Mesh.ARRAY_VERTEX] and actual[Mesh.ARRAY_COLOR] == original[Mesh.ARRAY_COLOR] and actual[Mesh.ARRAY_TEX_UV] == original[Mesh.ARRAY_TEX_UV]
			if bool(mesh.get_meta("scenery_coherent_normals", false)):
				var authored: Dictionary = {}
				for index: int in original[Mesh.ARRAY_VERTEX].size(): authored[[original[Mesh.ARRAY_VERTEX][index], original[Mesh.ARRAY_COLOR][index], original[Mesh.ARRAY_TEX_UV][index]]] = true
				same_attributes = true
				for index: int in actual[Mesh.ARRAY_VERTEX].size():
					if not authored.has([actual[Mesh.ARRAY_VERTEX][index], actual[Mesh.ARRAY_COLOR][index], actual[Mesh.ARRAY_TEX_UV][index]]): same_attributes = false; break
			check(same_attributes, "authored positions/paint/UVs " + label + str(tier))
			var full: PackedInt32Array = MESH_LOD.source_indices(source, surface)
			var indices: PackedInt32Array = MESH_LOD.source_indices(mesh, surface)
			var same_envelope: bool = true
			for direction: Vector3 in MESH_LOD._directions():
				var expected: float = -INF
				var observed: float = -INF
				for index: int in full: expected = maxf(expected, original[Mesh.ARRAY_VERTEX][index].dot(direction))
				for index: int in indices: observed = maxf(observed, actual[Mesh.ARRAY_VERTEX][index].dot(direction))
				if absf(expected - observed) > 0.0001: same_envelope = false
			check(indices.size() <= full.size() and same_envelope, "valid topology preserves exact support silhouette " + label + str(tier))
			if bool(mesh.get_meta("scenery_coherent_normals", false)):
				var coherent: bool = true
				for offset: int in range(0, indices.size(), 3):
					var a: int = indices[offset]
					var b: int = indices[offset + 1]
					var c: int = indices[offset + 2]
					var cross: Vector3 = (actual[Mesh.ARRAY_VERTEX][b] - actual[Mesh.ARRAY_VERTEX][a]).cross(actual[Mesh.ARRAY_VERTEX][c] - actual[Mesh.ARRAY_VERTEX][a])
					if cross.length_squared() < 0.0000000001: continue
					for index: int in [a, b, c]:
						if cross.dot(actual[Mesh.ARRAY_NORMAL][index]) > 0.000001: coherent = false
				check(coherent, "coarse pine clockwise winding and outward normals " + label + str(tier))
			else:
				check(major_faces_covered(original, full, actual, indices), "solid wall/roof/deck surface coverage " + label + str(tier))
				check(new_faces_have_correct_winding(original, full, actual, indices), "coarse opaque faces keep source outward side " + label + str(tier))

func plane_key(a: Vector3, b: Vector3, c: Vector3) -> Vector4:
	var normal: Vector3 = -(b - a).cross(c - a).normalized()
	return Vector4(roundf(normal.x * 1000.0), roundf(normal.y * 1000.0), roundf(normal.z * 1000.0), roundf(normal.dot(a) * 1000.0))

func major_faces_covered(original: Array, full: PackedInt32Array, actual: Array, indices: PackedInt32Array) -> bool:
	var vertices: PackedVector3Array = original[Mesh.ARRAY_VERTEX]
	var reduced_vertices: PackedVector3Array = actual[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = original[Mesh.ARRAY_COLOR] if original[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var largest: float = 0.0
	for offset: int in range(0, full.size(), 3): largest = maxf(largest, (vertices[full[offset + 1]] - vertices[full[offset]]).cross(vertices[full[offset + 2]] - vertices[full[offset]]).length() * 0.5)
	# Main walls/roofs/decks are substantial relative to this model's own
	# largest face. Small window panes, trim and ink may legitimately disappear.
	var minimum_area: float = maxf(0.015, largest * 0.10)
	var planes: Dictionary = {}
	for offset: int in range(0, indices.size(), 3):
		var a: Vector3 = reduced_vertices[indices[offset]]
		var b: Vector3 = reduced_vertices[indices[offset + 1]]
		var c: Vector3 = reduced_vertices[indices[offset + 2]]
		if (b - a).cross(c - a).length_squared() < 0.000000001: continue
		var key: Vector4 = plane_key(a, b, c)
		if not planes.has(key): planes[key] = []
		planes[key].append(PackedVector3Array([a, b, c]))
	for offset: int in range(0, full.size(), 3):
		var ia: int = full[offset]
		var ib: int = full[offset + 1]
		var ic: int = full[offset + 2]
		if not colors.is_empty() and minf(colors[ia].a, minf(colors[ib].a, colors[ic].a)) < 0.95: continue
		var a: Vector3 = vertices[ia]
		var b: Vector3 = vertices[ib]
		var c: Vector3 = vertices[ic]
		var cross: Vector3 = (b - a).cross(c - a)
		if cross.length() * 0.5 < minimum_area: continue
		var candidates: Array = planes.get(plane_key(a, b, c), [])
		if candidates.is_empty(): return false
		var outward: Vector3 = -cross.normalized()
		for weight: Vector3 in [Vector3.ONE / 3.0, Vector3(0.6, 0.2, 0.2), Vector3(0.2, 0.6, 0.2), Vector3(0.2, 0.2, 0.6)]:
			var point: Vector3 = a * weight.x + b * weight.y + c * weight.z
			var covered: bool = false
			for triangle: PackedVector3Array in candidates:
				var hit: Variant = Geometry3D.ray_intersects_triangle(point + outward * 0.02, -outward, triangle[0], triangle[1], triangle[2])
				if hit != null and (hit as Vector3).distance_squared_to(point) < 0.00000001: covered = true; break
			if not covered: return false
	return true

func new_faces_have_correct_winding(original: Array, full: PackedInt32Array, actual: Array, indices: PackedInt32Array) -> bool:
	if actual[Mesh.ARRAY_NORMAL] == null: return true
	var original_faces: Dictionary = {}
	for offset: int in range(0, full.size(), 3): original_faces[MESH_LOD._triangle_key(full, offset)] = true
	var vertices: PackedVector3Array = actual[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = actual[Mesh.ARRAY_NORMAL]
	for offset: int in range(0, indices.size(), 3):
		if original_faces.has(MESH_LOD._triangle_key(indices, offset)): continue
		var a: int = indices[offset]
		var b: int = indices[offset + 1]
		var c: int = indices[offset + 2]
		var cross: Vector3 = (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
		if cross.length_squared() < 0.000000001: continue
		if cross.dot(normals[a] + normals[b] + normals[c]) > cross.length() * 0.0002: return false
	return true

func check_view_switch(scene: PaperLandscape, camera: Camera3D, record: Dictionary) -> void:
	var center: Vector3 = record.node.global_transform * record.center
	var original_shadow: int = record.node.cast_shadow
	var original_multi: MultiMesh = record.node.multimesh if record.node is MultiMeshInstance3D else null
	for pair: Array in [[90.0, 0], [40.0, 1], [10.0, 2], [90.0, 0]]:
		var depth: float = record.diameter * MODEL_LOD.view(camera).scale / float(pair[0]) + float(record.spread)
		camera.position = center + Vector3(0, 0, depth)
		camera.look_at(center, Vector3.UP)
		scene.sync_lods(camera)
		check(record.tier == int(pair[1]), "projected-size tier " + str(record.node.name) + str(pair[1]))
		var selected: Mesh = record.node.multimesh.mesh if original_multi != null else record.node.mesh
		check(selected == record.meshes[int(pair[1])] and record.node.cast_shadow == original_shadow, "same draw identity/material/shadow " + str(record.node.name))
		if original_multi != null: check(record.node.multimesh == original_multi, "same destruction slots and multimesh " + str(record.node.name))

func check_civilian_integration(scene: PaperLandscape, sim: WarSimulation, camera: Camera3D) -> void:
	var world := PaperWorld.new()
	world.landscape = scene
	world.sim = sim
	world.camera = camera
	world._configure_civilian_paper()
	check(scene._civilian_batches.all(func(group: Dictionary): return group.multi.mesh == PAPER_CIVILIANS.mesh(int(group.people[0].get("variant", 0)))), "paper civilians initially display their exact authored near mesh")
	for group: Dictionary in scene._civilian_batches:
		var variant: int = int(group.people[0].get("variant", 0))
		var paper: Mesh = PAPER_CIVILIANS.mesh(variant)
		var matches: Array = scene.lod_records.filter(func(record: Dictionary): return record.node is MultiMeshInstance3D and record.node.multimesh == group.multi)
		check(matches.size() == 1 and matches[0].source == paper and matches[0].meshes[0] == paper, "actual authored paper civilians register as the near source")
		if matches.size() != 1: continue
		var record: Dictionary = matches[0]
		check(record.meshes.all(func(mesh: Mesh): return mesh.get_surface_count() > 0 and mesh.surface_get_material(0) == PAPER_CIVILIANS.material()), "civilian tiers retain camera-facing painted-paper shader")
		check_view_switch(scene, camera, record)
		camera.position += Vector3(5.0, 0.0, 0.0)
		camera.look_at(record.node.global_transform * record.center, Vector3.UP)
		scene.sync_lods(camera)
		check(group.multi.mesh == record.meshes[int(record.tier)] and record.source == paper, "panning never restores obsolete volumetric pedestrian art")
	world.free()

func run() -> void:
	check(MODEL_LOD.choose(61.0, 0) == 0 and MODEL_LOD.choose(67.0, 1) == 1, "near transition hysteresis")
	check(MODEL_LOD.choose(19.0, 1) == 1 and MODEL_LOD.choose(21.0, 2) == 2, "extreme transition hysteresis")
	var probe_builder := PaperLandscape.new()
	var pine: Mesh = probe_builder._prop_mesh("tree_0")
	var bad: Array = pine.surface_get_arrays(0).duplicate(true)
	var bad_vertices: PackedVector3Array = bad[Mesh.ARRAY_VERTEX]
	bad_vertices.append(Vector3.ZERO)
	bad[Mesh.ARRAY_VERTEX] = bad_vertices
	check(LOD.build_mesh(pine, [MESH_LOD.source_indices(pine, 0)], [bad]) == pine, "malformed repaired arrays retain complete source before upload")
	var edited := ArrayMesh.new()
	var changed: Array = pine.surface_get_arrays(0).duplicate(true)
	var changed_vertices: PackedVector3Array = changed[Mesh.ARRAY_VERTEX]
	changed_vertices[0] += Vector3(0.003, 0.0, 0.0)
	changed[Mesh.ARRAY_VERTEX] = changed_vertices
	edited.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, changed)
	edited.surface_set_material(0, pine.surface_get_material(0))
	check(not LOD.has_bake(edited) and LOD.variants(edited)[1] == edited and LOD.variants(edited)[2] == edited, "edited geometry rejects stale reduction and retains complete source")
	probe_builder.free()
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.fov = 42.0
	var seen: Dictionary = {}
	var seen_ids: Dictionary = {}
	var coverage: Array[Dictionary] = []
	for mode: String in CATALOG.MODES:
		for seed: int in [7, 31]:
			var sim: WarSimulation = fixture(mode, seed)
			var scene := PaperLandscape.new()
			root.add_child(scene)
			scene._initialize_build(sim)
			scene._build_props()
			scene._build_environment()
			scene._build_mines(sim)
			for ruin: Dictionary in sim.ruins: scene._build_ruin(ruin)
			for bridge: Dictionary in sim.bridges: scene._build_bridge(bridge)
			scene._flush_batches()
			scene.sync_resources(sim)
			var missing: Array[String] = []
			for record: Dictionary in scene.lod_records:
				if not record.baked: missing.append(str(record.node.name))
				if seen_ids.has(record.source.get_instance_id()): continue
				seen_ids[record.source.get_instance_id()] = true
				var signature: String = MESH_LOD.signature(record.source)
				if seen.has(signature) or record.node.name == "CutPaperCrystals" and mode != "forest": continue
				seen[signature] = true
				check_mesh(record.source, mode + "/" + str(record.node.name))
			check(missing.is_empty(), "all scenery types covered " + mode + " seed=" + str(seed) + " missing=" + str(missing))
			coverage.append({"map": mode, "seed": seed, "records": scene.lod_records.size(), "missing": missing})
			if seed == 7:
				for record: Dictionary in scene.lod_records.slice(0, 4): check_view_switch(scene, camera, record)
				if not scene.bridge_visuals.is_empty():
					var bridge: Dictionary = sim.bridges[0]
					bridge.alive = false
					scene.sync_resources(sim)
					var visual: Dictionary = scene.bridge_visuals[int(bridge.id)]
					check(not visual.deck.visible and visual.broken.visible, "bridge destruction survives LOD " + mode)
				if mode == "city": check_civilian_integration(scene, sim, camera)
			scene.free()
	# Small terrain build verifies seed-independent authored tiers and loaded
	# destruction state without repeating a 640-map navigation graph.
	var sim: WarSimulation = fixture("dev", 13)
	var scene: PaperLandscape = PaperLandscape.build(sim)
	root.add_child(scene)
	var terrain: Array = scene.lod_records.filter(func(record: Dictionary): return str(record.node.name).begins_with("Ground_") or str(record.node.name).begins_with("Water_"))
	check(not terrain.is_empty() and terrain.all(func(record: Dictionary): return record.baked and record.meshes.size() == 3), "all procedural terrain chunks have authored tiers")
	for record: Dictionary in terrain:
		check(record.meshes[0] == record.source and record.meshes[1].custom_aabb == record.source.get_aabb() and record.meshes[2].custom_aabb == record.source.get_aabb(), "terrain exact full and conservative bounds " + str(record.node.name))
	var tiles: Array = []
	tiles.resize(PaperLandscape.CHUNK * PaperLandscape.CHUNK)
	for z: int in 3:
		for x: int in 4:
			if x != 1 or z != 1: tiles[z * PaperLandscape.CHUNK + x] = {"height": 4.0, "kind": MapData.LAND}
	var data: Dictionary = scene._data()
	scene._append_coalesced_surface(data, tiles, 0, 0, 4, 3)
	var area: float = 0.0
	var avoids_hole: bool = true
	for offset: int in range(0, data.vertices.size(), 3):
		var a: Vector3 = data.vertices[offset]
		var b: Vector3 = data.vertices[offset + 1]
		var c: Vector3 = data.vertices[offset + 2]
		area += (b - a).cross(c - a).length() * 0.5
		avoids_hole = avoids_hole and not Geometry2D.is_point_in_polygon(Vector2(1.5, 1.5), PackedVector2Array([Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)]))
	check(is_equal_approx(area, 11.0) and avoids_hole, "extreme flat surface exact area preserves holes")
	var tree: Dictionary = sim.ruins.filter(func(ruin: Dictionary): return ruin.kind == "tree")[0]
	scene.sync_lods(camera)
	tree.hp = 0.0
	sim.events.append({"kind": "ruin_destroy", "id": tree.id, "pos": tree.pos})
	scene.sync_resources(sim)
	check(scene.tree_visuals[int(tree.id)].all(func(piece: Dictionary): return piece.current_transform.basis.x.length() == 0.0), "distant-tree destruction keeps the original visual/pick slots")
	scene.free()
	camera.free()
	print("SCENERY_LOD_TEST ", JSON.stringify({"checks": checks, "failures": failures, "unique_sources": seen.size(), "coverage": coverage}))
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
