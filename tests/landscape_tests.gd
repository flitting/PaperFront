extends SceneTree

const Sim = preload("res://scripts/simulation.gd")
const Landscape = preload("res://scripts/landscape.gd")
const Rules = preload("res://scripts/rules_loader.gd")
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	var rules: Dictionary = Rules.load_rules()
	for mode: String in ["dev", "handmade"]:
		var sim = Sim.new()
		sim.setup(rules, mode, 24, "rivet", false)
		_check(_ridge_variation(sim.map) >= 3, mode + ": high-ground edges vary by column instead of forming straight horizontal terraces")
		_check(_river_variation(sim.map) >= 2, mode + ": the river bends while preserving its real water-cell topology")
		_check(_clustered_props(sim.map), mode + ": forests contain adjacent real obstacle cells instead of isolated scattered trees")
		var before: Dictionary = {"map": sim.map.duplicate(true), "mines": sim.mines.duplicate(true), "bridges": sim.bridges.duplicate(true)}
		var landscape = Landscape.build(sim)
		root.add_child(landscape)
		_check(sim.map == before.map and sim.mines == before.mines and sim.bridges == before.bridges, mode + ": landscape generation leaves simulation state unchanged")
		_check(int(landscape.stats.terrain_triangles) > int(sim.map.size) * int(sim.map.size) * 2, mode + ": ground includes real cliff and bank faces")
		_check(int(landscape.stats.prop_draws) < int(landscape.stats.prop_instances), mode + ": scenery instances share regional MultiMesh batches")
		var normals_valid: bool = true
		var winding_valid: bool = true
		var top_errors: float = 0.0
		var deepest_water: float = 0.0
		var navigation_top_count: int = 0
		var decorative_top_count: int = 0
		var decorative_top_error: float = 0.0
		var top_ranges_valid: bool = true
		for child: Node in landscape.get_children():
			if not child is MeshInstance3D and not child is MultiMeshInstance3D:
				continue
			var mesh: ArrayMesh = child.mesh if child is MeshInstance3D else child.multimesh.mesh
			for surface: int in mesh.get_surface_count():
				var arrays: Array = mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				var element_count: int = indices.size() if not indices.is_empty() else vertices.size()
				normals_valid = normals_valid and vertices.size() == normals.size()
				for normal: Vector3 in normals:
					normals_valid = normals_valid and normal.is_finite() and absf(normal.length() - 1.0) < 0.001
				for index: int in range(0, element_count, 3):
					var a: int = indices[index] if not indices.is_empty() else index
					var b: int = indices[index + 1] if not indices.is_empty() else index + 1
					var c: int = indices[index + 2] if not indices.is_empty() else index + 2
					var cross: Vector3 = (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
					winding_valid = winding_valid and cross.dot(normals[a]) < 0.0
				if str(child.name).begins_with("Ground_"):
					# Ground batches also contain raised cardboard scree and litter.
					# The renderer records only the actual cell top / ramp triangles.
					var ranges: Array=child.get_meta("navigation_top_ranges",[])
					top_ranges_valid=top_ranges_valid and not ranges.is_empty() and indices.is_empty()
					var real_tops: Dictionary={}
					for interval: Vector2i in ranges:
						top_ranges_valid=top_ranges_valid and interval.x>=0 and interval.y<=element_count and interval.x%3==0 and interval.y%3==0 and interval.y>interval.x
						for index: int in range(interval.x,interval.y,3):
							real_tops[index]=true
							var centre: Vector3=(vertices[index]+vertices[index+1]+vertices[index+2])/3.0
							var expected: float=MapData.height_at(sim.map,Vector2(centre.x,centre.z))
							top_errors=maxf(top_errors,absf(centre.y-expected))
							navigation_top_count+=1
					# Report what the former upward-normal heuristic misclassified.
					for index: int in range(0,element_count,3):
						if normals[index].y>.85 and not real_tops.has(index):
							var centre: Vector3=(vertices[index]+vertices[index+1]+vertices[index+2])/3.0
							var expected: float=MapData.height_at(sim.map,Vector2(centre.x,centre.z))
							decorative_top_error=maxf(decorative_top_error,absf(centre.y-expected))
							decorative_top_count+=1

				elif str(child.name).begins_with("Water_"):
					for vertex: Vector3 in vertices:
						deepest_water = maxf(deepest_water, -vertex.y)
		_check(normals_valid, mode + ": every terrain vertex has a finite unit lighting normal")
		_check(winding_valid, mode + ": clockwise front faces retain exterior lighting normals")
		_check(top_ranges_valid,mode+": actual cell-top vertex ranges are present, aligned and within the visible ground mesh")
		_check(navigation_top_count==_expected_navigation_top_count(sim.map),mode+": every non-water cell top is checked, including both linear halves of ramps")
		_check(top_errors <= 0.012, mode + ": visible land tops reproduce real MapData heights including ramp interpolation (error=%s)" % top_errors)
		_check(deepest_water >= 2.6, mode + ": non-navigable visual water forms a deep cut river valley")
		var mine: Node3D = landscape.mine_visuals[0]
		var full: Vector3 = mine.scale
		sim.mines[0].amount = 0.0
		landscape.sync_resources(sim)
		_check(mine.scale == full, mode + ": infinite ore keeps the physical crystal pillar at its full size even for legacy depleted amounts")
		var bridge_id: int = int(sim.bridges[0].id)
		var arch: MeshInstance3D = landscape.bridge_visuals[bridge_id].deck
		var arch_bottom: float = 0.0
		for vertex: Vector3 in arch.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			arch_bottom = minf(arch_bottom, vertex.y)
		_check(arch_bottom <= -2.6 and is_zero_approx(landscape.bridge_visuals[bridge_id].root.position.y), mode + ": a volume stone arch reaches the valley while the traversable deck stays at its actual height")
		sim.bridges[0].alive = false
		landscape.sync_resources(sim)
		_check(not landscape.bridge_visuals[bridge_id].deck.visible and landscape.bridge_visuals[bridge_id].broken.visible, mode + ": bridge destruction swaps intact deck for physical broken remnants")
		sim.bridges[0].alive = true
		landscape.sync_resources(sim)
		_check(landscape.bridge_visuals[bridge_id].deck.visible and not landscape.bridge_visuals[bridge_id].broken.visible, mode + ": a repaired bridge restores its deck")
		print(mode+" terrain height samples: ",JSON.stringify({"navigation_top_triangles":navigation_top_count,"navigation_max_error":top_errors,"decorative_upward_triangles":decorative_top_count,"decorative_max_offset":decorative_top_error}))
		print(mode + " landscape: ", landscape.stats, ", props: ", sim.map.decorations.size())
		landscape.free()
	print("Landscape checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _ridge_variation(map: Dictionary) -> int:
	var edges: Dictionary = {}
	for x: int in int(map.size):
		var z: int = 0
		while z < int(map.size) and float(map.heights[z][x]) == 6.0:
			z += 1
		edges[z] = true
	return edges.size()


func _river_variation(map: Dictionary) -> int:
	var edges: Dictionary = {}
	for z: int in int(map.size):
		for x: int in int(map.size):
			if int(map.terrain[z][x]) == MapData.WATER:
				edges[x] = true
				break
	return edges.size()


func _clustered_props(map: Dictionary) -> bool:
	var trees: Dictionary = {}
	for decoration: Dictionary in map.decorations:
		if decoration.kind == "tree":
			trees[Vector2i(floori(decoration.pos[0]), floori(decoration.pos[1]))] = true
	var neighbors: int = 0
	for cell: Vector2i in trees:
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			if trees.has(cell + direction):
				neighbors += 1
	return neighbors >= 4


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _expected_navigation_top_count(map: Dictionary) -> int:
	var total: int=0
	for row: Array in map.terrain:
		for terrain: int in row:
			if terrain!=MapData.WATER:total+=4 if terrain==MapData.RAMP else 2
	return total
