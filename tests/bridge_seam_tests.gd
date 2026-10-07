extends SceneTree

const CRAFT = preload("res://scripts/bridge_craft.gd")
const CACHE = preload("res://scripts/terrain_resource_cache.gd")
var failures: Array[String] = []
var checks: int = 0
var records: Array[Dictionary] = []

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func fixture(mode: String, seed: int = 7) -> WarSimulation:
	var sim := WarSimulation.new()
	sim.rules = RulesLoader.load_rules()
	sim.map = MapData.generate(mode, seed)
	sim.ruins = sim.map.ruins.duplicate(true)
	for bridge: Dictionary in sim.map.bridges:
		var live: Dictionary = bridge.duplicate(true)
		live.alive = true
		sim.bridges.append(live)
	return sim

func tier(scene: PaperLandscape, value: int) -> void:
	for record: Dictionary in scene.lod_records:
		if record.node is MultiMeshInstance3D: record.node.multimesh.mesh = record.meshes[value]
		else: record.node.mesh = record.meshes[value]
		record.tier = value

func upward_faces(mesh: Mesh, transform: Transform3D) -> Array[PackedVector3Array]:
	var result: Array[PackedVector3Array] = []
	for surface: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			indices.resize(vertices.size())
			for index: int in indices.size(): indices[index] = index
		for offset: int in range(0, indices.size(), 3):
			var a: Vector3 = transform * vertices[indices[offset]]
			var b: Vector3 = transform * vertices[indices[offset + 1]]
			var c: Vector3 = transform * vertices[indices[offset + 2]]
			if -(b-a).cross(c-a).normalized().y > .95: result.append(PackedVector3Array([a,b,c]))
	return result

func visible_ground_faces(scene: PaperLandscape) -> Array[PackedVector3Array]:
	var result: Array[PackedVector3Array] = []
	for node: Node in scene.get_children():
		if node is MeshInstance3D and str(node.name).begins_with("Ground_") and node.visible: result.append_array(upward_faces(node.mesh, node.global_transform))
	return result

func hit_plane(faces: Array[PackedVector3Array], point: Vector3) -> bool:
	for face: PackedVector3Array in faces:
		var hit: Variant = Geometry3D.ray_intersects_triangle(point+Vector3.UP, Vector3.DOWN, face[0], face[1], face[2])
		if hit != null and absf((hit as Vector3).y-point.y) < .0001: return true
	return false

func check_board_geometry() -> void:
	var builder := PaperLandscape.new()
	for length: float in [.2,.58,.62,1.0,5.0,6.0,10.0,23.0,25.0,27.0,29.0]:
		var segments: Array[Vector2] = CRAFT.plank_segments(length)
		check(is_equal_approx(segments[0].x,-length*.5) and is_equal_approx(segments.back().y,length*.5), "boards exactly meet both bridge endpoints " + str(length))
		check(segments.all(func(segment: Vector2): return segment.x >= -length*.5-.00001 and segment.y <= length*.5+.00001 and segment.y > segment.x), "tail never overhangs declared footprint " + str(length))
		for heading: float in [0.0,PI*.5]:
			var turn := Basis(Vector3.UP, heading)
			var detail: Dictionary = builder._data()
			CRAFT.planks(builder, detail, length, 2.0, turn)
			var supported: bool = true
			for vertex: Vector3 in detail.vertices:
				var local: Vector3 = turn.inverse() * vertex
				if not is_equal_approx(local.y, CRAFT.OFFSET) or absf(local.z) > 1.00001: supported = false
				if not segments.any(func(segment: Vector2): return local.x >= segment.x-.00001 and local.x <= segment.y+.00001): supported = false
			check(supported, "all grain/nails stay on clipped board tops " + str(length) + "/" + str(heading))
	builder.free()

func run() -> void:
	check_board_geometry()
	for mode: String in ["forest","desert","snow","city","random_city","campaign","dev"]:
		var sim: WarSimulation = fixture(mode)
		var bridge: Dictionary = sim.bridges[0]
		var id: int = int(bridge.id)
		var map_before: int = hash([sim.map.terrain,sim.map.heights,sim.map.bridges])
		var bounds: Array = bridge.bounds
		var center := Vector2(float(bounds[0])+float(bounds[2])*.5,float(bounds[1])+float(bounds[3])*.5)
		var deck_height: float = MapData.height_at(sim.map,center)
		var scene := PaperLandscape.new()
		root.add_child(scene)
		scene._initialize_build(sim)
		scene._prepare_terrain_geometry()
		for cz: int in range(floori(float(bounds[1])/scene.CHUNK)*scene.CHUNK, int(bounds[1])+int(bounds[3]), scene.CHUNK):
			for cx: int in range(floori(float(bounds[0])/scene.CHUNK)*scene.CHUNK, int(bounds[0])+int(bounds[2]), scene.CHUNK): scene._build_terrain_chunk(cx,cz,int(sim.map.size))
		for live: Dictionary in sim.bridges: scene._build_bridge(live)
		scene.sync_resources(sim)
		var bank_points: Array[Vector3] = []
		var water_points: Array[Vector3] = []
		for cell: Vector2i in scene._bridge_ground_cells:
			if int(scene._bridge_ground_cells[cell]) == id: bank_points.append(Vector3(cell.x+.5,deck_height,cell.y+.5))
		for z: int in range(int(bounds[1]),int(bounds[1])+int(bounds[3])):
			for x: int in range(int(bounds[0]),int(bounds[0])+int(bounds[2])):
				if int(sim.map.terrain[z][x]) == MapData.WATER: water_points.append(Vector3(x+.5,deck_height,z+.5))
		check(not bank_points.is_empty() and not water_points.is_empty(), "real fixture has both covered bank and open water " + mode)
		var visual: Dictionary = scene.bridge_visuals[id]
		var substrate: AABB = visual.substrate.mesh.get_aabb()
		check(substrate.position.y >= -.14001 and substrate.end.y < -.02, "backing remains within old deck thickness/naval envelope " + mode)
		var state_results: Array[Dictionary] = []
		for alive: bool in [true,false,true]:
			bridge.alive = alive
			scene.sync_resources(sim)
			check(visual.deck.visible == alive and visual.substrate.visible == alive and visual.broken.visible != alive, "deck/backing/debris follow destroy and repair " + mode + str(alive))
			check(scene.bridge_ground_nodes[id].all(func(node: MeshInstance3D): return node.visible != alive), "only original bank returns after destruction " + mode + str(alive))
			for value: int in 3:
				tier(scene,value)
				var faces: Array[PackedVector3Array] = visible_ground_faces(scene)
				check(bank_points.all(func(point: Vector3): return hit_plane(faces,point) != alive), "one coplanar surface owner across all LODs " + mode + str(alive) + "/" + str(value))
				check(water_points.all(func(point: Vector3): return not hit_plane(faces,point)), "destroy never restores land over water " + mode + "/" + str(value))
				if alive:
					var backing_faces: Array[PackedVector3Array] = upward_faces(visual.substrate.mesh,visual.substrate.global_transform)
					check(bank_points.all(func(point: Vector3): return hit_plane(backing_faces, point-Vector3.UP*.025)), "continuous backing prevents empty plank joints " + mode + "/" + str(value))
				state_results.append({"alive":alive,"tier":value})
		check(map_before == hash([sim.map.terrain,sim.map.heights,sim.map.bridges]), "navigation grid/bridge bounds/clearance remain unchanged " + mode)
		# Serialize the retained terrain layers and restore under an already dead
		# bridge. Warm caches must consult current state, not saved node visibility.
		tier(scene,0)
		scene._finish_terrain_build({"size":int(sim.map.size),"signature":hash(sim.map),"disk_key":""})
		var cached: Dictionary = PaperLandscape._terrain_cache
		var key: String = "bridge_" + mode
		var error: int = CACHE.store_entry(key,cached,"user://bridge_seam_test_cache",0)
		var loaded: Dictionary = CACHE.load_entry(key,"user://bridge_seam_test_cache")
		check(error == OK and not loaded.is_empty(), "cold/warm layer resources serialize " + mode)
		bridge.alive = false
		var restored := PaperLandscape.new()
		root.add_child(restored)
		restored._initialize_build(sim)
		for record: Dictionary in loaded.get("nodes",[]): restored._restore_terrain_node(record)
		check(restored.bridge_ground_nodes.has(id) and restored.bridge_ground_nodes[id].all(func(node: MeshInstance3D): return node.visible), "warm cache restores current destroyed-bank state " + mode)
		for value: int in 3:
			tier(restored,value)
			var faces: Array[PackedVector3Array] = visible_ground_faces(restored)
			check(bank_points.all(func(point: Vector3): return hit_plane(faces,point)) and water_points.all(func(point: Vector3): return not hit_plane(faces,point)), "cached all-tier land/water ownership exact " + mode + "/" + str(value))
		DirAccess.remove_absolute("user://bridge_seam_test_cache/"+key+".res")
		restored.free()
		records.append({"map":mode,"bridge_id":id,"coplanar_land_cells":bank_points.size(),"water_cells":water_points.size(),"states":state_results})
		scene.free()
	print("BRIDGE_SEAM_TEST ",JSON.stringify({"checks":checks,"failures":failures,"fixtures":records}))
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
