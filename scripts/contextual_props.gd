extends RefCounted

## Pure resolved-prop composer. Terrain, simulation, and every unselected
## transform remain unchanged; G0 stores the returned groups explicitly.
const MESH_KEYS: Array[String] = ["context_wall_broken", "context_wall_stub", "context_wall_corner_r", "context_wall_corner_l"]
const PLACEMENTS: Array = [
	[70, 104, "context_wall_stub", 0.0],
	[71, 104, "context_wall_broken", 0.0],
	[72, 104, "context_wall_broken", PI],
	[73, 104, "context_wall_broken", 0.0],
	[74, 104, "context_wall_corner_r", 0.0],
	[74, 103, "context_wall_stub", PI * 0.5],
	[90, 104, "context_wall_corner_l", 0.0],
	[91, 104, "context_wall_broken", PI],
	[92, 104, "context_wall_broken", 0.0],
	[93, 104, "context_wall_stub", 0.0],
	[90, 103, "context_wall_stub", PI * 0.5],
]


static func remap_prop_batches(map: Dictionary, resolved_groups: Array) -> Array:
	var source: Array = resolved_groups.duplicate(true)
	if int(map.get("size", 0)) != 160:
		return source
	var layout: Dictionary = {}
	for placement: Array in PLACEMENTS:
		var cell := Vector2i(int(placement[0]), int(placement[1]))
		if int(map.terrain[cell.y][cell.x]) == 4 and is_zero_approx(float(map.heights[cell.y][cell.x])):
			layout[cell] = {"mesh_key": str(placement[2]), "yaw": float(placement[3])}
	var selected: Dictionary = {}
	for group: Dictionary in source:
		if not _primary(str(group.mesh_key)):
			continue
		for values: Array in group.transforms:
			var cell: Vector2i = _cell(values)
			if layout.has(cell):
				selected[cell] = true
	# A different map may lack this stand. Preserve it unless a whole main
	# wall chain is supported, rather than leaving isolated scattered tiles.
	for chain: Array in [[70, 74, 74], [90, 93, 90]]:
		var complete: bool = true
		for x: int in range(int(chain[0]), int(chain[1]) + 1):
			complete = complete and selected.has(Vector2i(x, 104))
		if not complete:
			for x: int in range(int(chain[0]), int(chain[1]) + 1):
				selected.erase(Vector2i(x, 104))
			selected.erase(Vector2i(int(chain[2]), 103))
	if selected.is_empty():
		return source
	var result: Array = []
	for group: Dictionary in source:
		var key: String = str(group.mesh_key)
		var kept: Array = []
		for values: Array in group.transforms:
			var cell: Vector2i = _cell(values)
			if selected.has(cell):
				if _primary(key) or key == "trunk":
					continue
				if key == "contact":
					var position := Vector3(float(cell.x) + 0.5, float(map.heights[cell.y][cell.x]) + 0.015, float(cell.y) + 0.5)
					values[9] = position.x
					values[10] = position.y
					values[11] = position.z
			kept.append(values)
		if not kept.is_empty():
			group.transforms = kept
			result.append(group)
	var additions: Dictionary = {}
	for placement: Array in PLACEMENTS:
		var cell := Vector2i(int(placement[0]), int(placement[1]))
		if not selected.has(cell):
			continue
		var plan: Dictionary = layout[cell]
		var key: String = str(plan.mesh_key)
		var name: String = "PropBatch_%s_%d_%d" % [key, floori(float(cell.x) / 32.0), floori(float(cell.y) / 32.0)]
		if not additions.has(name):
			additions[name] = {"name": name, "mesh_key": key, "shadow": 1, "transforms": []}
		additions[name].transforms.append(_wall_transform(cell, float(map.heights[cell.y][cell.x]), float(plan.yaw)))
	for group: Dictionary in additions.values():
		result.append(group)
	return result


static func _primary(key: String) -> bool:
	return key.begins_with("tree_") or key.begins_with("rock_") or key == "ruin"


static func _cell(values: Array) -> Vector2i:
	return Vector2i(floori(float(values[9])), floori(float(values[11])))


static func _wall_transform(cell: Vector2i, height: float, yaw: float) -> Array:
	var rotation := Basis(Vector3.UP, yaw)
	return [rotation.x.x, rotation.x.y, rotation.x.z, rotation.y.x, rotation.y.y, rotation.y.z, rotation.z.x, rotation.z.y, rotation.z.z, float(cell.x) + 0.5, height, float(cell.y) + 0.5]
