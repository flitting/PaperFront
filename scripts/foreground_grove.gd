extends RefCounted

## A resolved foreground stand, independent of the old map/prop RNG streams.
## Apply once to an explicit map copy; save its returned groups in new fixtures.
const LAND: int = 0
const RAMP: int = 2
const ROAD: int = 3
const BLOCKED: int = 4
const DIRECTIONS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
const ROUTE: Array[Vector2] = [Vector2(68, 109.5), Vector2(70, 113), Vector2(72, 117), Vector2(72, 120), Vector2(69, 124), Vector2(64, 130)]
# One contiguous tapered mass at the outcrop foot. Its three low remnants sit
# on the broken south-west edge; the east face follows the open worn approach.
# Entries: x, z, kind, mesh variant, vertical scale, yaw (radians).
const PLACEMENTS: Array = [
	[64, 116, "tree", 0, 0.72, 0.24],
	[65, 116, "tree", 2, 0.90, 2.32],
	[66, 116, "tree", 1, 0.82, 4.57],
	[63, 117, "tree", 1, 0.77, 3.04],
	[64, 117, "tree", 0, 0.93, 5.27],
	[65, 117, "tree", 2, 1.38, 1.68],
	[66, 117, "tree", 0, 0.89, 4.01],
	[63, 118, "tree", 2, 0.75, 0.83],
	[64, 118, "tree", 0, 0.89, 2.61],
	[65, 118, "tree", 2, 1.54, 4.88],
	[66, 118, "ruin", 0, 1.15, 0.0],
	[63, 119, "tree", 1, 0.68, 2.07],
	[64, 119, "tree", 1, 1.32, 5.67],
	[65, 119, "tree", 2, 1.42, 1.13],
	[66, 119, "ruin", 0, 1.02, PI],
	[63, 120, "tree", 0, 0.83, 5.02],
	[64, 120, "tree", 0, 1.31, 3.74],
	[65, 120, "rock", 1, 1.30, 1.94],
	[63, 121, "tree", 1, 0.85, 0.71],
	[64, 121, "tree", 2, 0.83, 2.92],
	[63, 122, "tree", 0, 0.66, 4.26],
]


## Public API. Mutates only LAND0/LAND2 cells and adds map.foreground_grove.
## protected_points accepts Vector2/[x,z] or {pos, radius, size, buffer}.
## An occupied square size includes its corners, and buffer is at least 2m.
## The whole stand is rejected if any planned cell is unsafe, avoiding scraps.
static func apply_foreground(map: Dictionary, protected_points: Array = []) -> Dictionary:
	var result: Dictionary = {"added_cells": [], "additions": [], "land0_cells": 0, "land2_cells": 0, "minimum_route_clearance": 1000.0}
	if int(map.get("size", 0)) != 160 or not map.get("foreground_grove", []).is_empty():
		return result
	var protected: Dictionary = {}
	for z: int in int(map.size):
		for x: int in int(map.size):
			if int(map.terrain[z][x]) in [RAMP, ROAD, BLOCKED]:
				_protect_rect(map, protected, Rect2i(x - 2, z - 2, 5, 5))
	for mine: Dictionary in map.get("mines", []):
		# The existing crystal crown is within .95m; retain its two-metre apron.
		_protect_point(map, protected, _position(mine.get("pos")), 3.0)
	for start in map.get("starts", []):
		_protect_point(map, protected, _position(start), 11.0)
	for bridge: Dictionary in map.get("bridges", []):
		var bounds: Array = bridge.bounds
		_protect_rect(map, protected, Rect2i(int(bounds[0]) - 2, int(bounds[1]) - 2, int(bounds[2]) + 4, int(bounds[3]) + 4))
		for head in bridge.heads:
			_protect_point(map, protected, _position(head), 2.0)
	for value in protected_points:
		var point: Vector2 = _position(value.get("pos") if value is Dictionary else value)
		var footprint: float = 0.0
		var buffer: float = 2.0
		if value is Dictionary:
			footprint = maxf(float(value.get("radius", 0.0)), float(value.get("size", 0.0)) * 0.707107)
			buffer = maxf(2.0, float(value.get("buffer", 2.0)))
		_protect_point(map, protected, point, maxf(0.0, footprint) + buffer)
	# The whole blocked cell stays at least four metres from every segment of
	# the painted southern approach, including its bend toward the bypass.
	var cells: Dictionary = {}
	for placement: Array in PLACEMENTS:
		var cell := Vector2i(int(placement[0]), int(placement[1]))
		var level: float = float(map.heights[cell.y][cell.x])
		if protected.has(cell) or int(map.terrain[cell.y][cell.x]) != LAND or level not in [0.0, 2.0] or _route_clearance(cell) < 4.0 - 0.00001:
			return result
		cells[cell] = true
		result.minimum_route_clearance = minf(float(result.minimum_route_clearance), _route_clearance(cell))
	for placement: Array in PLACEMENTS:
		var cell := Vector2i(int(placement[0]), int(placement[1]))
		var kind: String = str(placement[2])
		var horizontal: float = 0.90 if kind == "ruin" else 1.0
		var vertical: float = float(placement[4])
		if kind == "tree":
			var edge: bool = false
			for direction: Vector2i in DIRECTIONS:
				edge = edge or not cells.has(cell + direction)
			# .62m tree radius + ink stays below .48m on every exposed edge.
			# Only crowns surrounded by blocked neighbours may touch those cells.
			horizontal = 0.74 if edge else 1.0
			if edge:
				vertical = minf(vertical, 1.0)
		var addition: Dictionary = {"kind": kind, "pos": [float(cell.x) + 0.5, float(cell.y) + 0.5], "variant": int(placement[3]), "scale": [horizontal, vertical, horizontal], "yaw": float(placement[5])}
		var level: float = float(map.heights[cell.y][cell.x])
		result.land0_cells += int(level == 0.0)
		result.land2_cells += int(level == 2.0)
		result.added_cells.append([cell.x, cell.y])
		result.additions.append(addition)
		map.terrain[cell.y][cell.x] = BLOCKED
	map["foreground_grove"] = result.additions.duplicate(true)
	return result


## Preserve every original resolved group, append clearly named new groups.
## Both normal landscape assembly and explicit fixture copying use this API.
static func append_prop_batches(map: Dictionary, resolved_groups: Array, entries_key: String = "foreground_grove", label: String = "foreground_grove") -> Array:
	var result: Array = resolved_groups.duplicate(true)
	var additions: Dictionary = {}
	for addition: Dictionary in map.get(entries_key, []):
		var point: Vector2 = _position(addition.pos)
		var cell := Vector2i(floori(point.x), floori(point.y))
		if int(map.terrain[cell.y][cell.x]) != BLOCKED:
			continue
		var position := Vector3(point.x, float(map.heights[cell.y][cell.x]), point.y)
		var scale_values: Array = addition.scale
		var scale := Vector3(float(scale_values[0]), float(scale_values[1]), float(scale_values[2]))
		var rotation := Basis(Vector3.UP, float(addition.yaw)).scaled(scale)
		var kind: String = str(addition.kind)
		var key: String = "%s_%d" % [kind, int(addition.variant)] if kind in ["tree", "rock"] else kind
		_append(additions, key, Transform3D(rotation, position), label)
		if kind == "tree":
			_append(additions, "trunk", Transform3D(Basis.IDENTITY.scaled(scale), position), label)
		_append(additions, "contact", Transform3D(Basis.IDENTITY, position + Vector3.UP * 0.015), label)
	for group: Dictionary in additions.values():
		result.append(group)
	return result


static func _append(groups: Dictionary, key: String, transform: Transform3D, label: String = "foreground_grove") -> void:
	var name: String = "PropBatch_%s_%s_%d_%d" % [key, label, floori(transform.origin.x / 32.0), floori(transform.origin.z / 32.0)]
	if not groups.has(name):
		groups[name] = {"name": name, "mesh_key": key, "shadow": 0 if key == "contact" else 1, "transforms": []}
	groups[name].transforms.append([transform.basis.x.x, transform.basis.x.y, transform.basis.x.z, transform.basis.y.x, transform.basis.y.y, transform.basis.y.z, transform.basis.z.x, transform.basis.z.y, transform.basis.z.z, transform.origin.x, transform.origin.y, transform.origin.z])


static func _route_clearance(cell: Vector2i) -> float:
	var distance_squared: float = INF
	for mirror: bool in [false, true]:
		for index: int in range(ROUTE.size() - 1):
			var a: Vector2 = ROUTE[index]
			var b: Vector2 = ROUTE[index + 1]
			if mirror:
				a.x = 160.0 - a.x
				b.x = 160.0 - b.x
			distance_squared = minf(distance_squared, _segment_cell_distance_squared(a, b, cell))
	return sqrt(distance_squared)


static func _segment_cell_distance_squared(a: Vector2, b: Vector2, cell: Vector2i) -> float:
	var corners: Array[Vector2] = [Vector2(cell), Vector2(cell) + Vector2.RIGHT, Vector2(cell) + Vector2.ONE, Vector2(cell) + Vector2.DOWN]
	var result: float = INF
	for endpoint: Vector2 in [a, b]:
		var nearest := Vector2(clampf(endpoint.x, cell.x, cell.x + 1), clampf(endpoint.y, cell.y, cell.y + 1))
		result = minf(result, endpoint.distance_squared_to(nearest))
	for index: int in 4:
		if Geometry2D.segment_intersects_segment(a, b, corners[index], corners[(index + 1) % 4]) != null:
			return 0.0
		var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(corners[index], a, b)
		result = minf(result, corners[index].distance_squared_to(nearest))
	return result


static func _position(value: Variant) -> Vector2:
	if value is Vector2 or value is Vector2i:
		return Vector2(value)
	if value is Array and value.size() == 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.INF


static func _protect_rect(map: Dictionary, protected: Dictionary, bounds: Rect2i) -> void:
	for z: int in range(maxi(0, bounds.position.y), mini(int(map.size), bounds.end.y)):
		for x: int in range(maxi(0, bounds.position.x), mini(int(map.size), bounds.end.x)):
			protected[Vector2i(x, z)] = true


static func _protect_point(map: Dictionary, protected: Dictionary, position: Vector2, radius: float) -> void:
	if not position.is_finite():
		return
	for z: int in range(maxi(0, floori(position.y - radius) - 1), mini(int(map.size), ceili(position.y + radius) + 1)):
		for x: int in range(maxi(0, floori(position.x - radius) - 1), mini(int(map.size), ceili(position.x + radius) + 1)):
			var nearest := Vector2(clampf(position.x, float(x), float(x + 1)), clampf(position.y, float(z), float(z + 1)))
			if nearest.distance_squared_to(position) <= radius * radius:
				protected[Vector2i(x, z)] = true
