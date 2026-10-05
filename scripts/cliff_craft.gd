extends RefCounted

# Painted torn-cardboard faces. These are clipped pigment overlays on the
# authoritative wall facets: none of them moves a rim, foot, or walking top.
# A full wall uses v=0 at the rim, v=.5 at the real fold, and v=1 at the foot.
static func decorate(landscape, data: Dictionary, a: Vector3, b: Vector3, middle_a: Vector3, middle_b: Vector3, low_a: Vector3, low_b: Vector3, outside: Vector3, color: Color, x: int, z: int) -> void:
	var salt: float = outside.x * 31.0 + outside.z * 17.0
	var r: float = landscape._static_hash(x, z, 173.0 + salt)
	var r2: float = landscape._static_hash(x, z, 177.0 + salt)
	var walls: Array = [a, b, middle_a, middle_b, low_a, low_b]
	# Unequal broad pigment facets are visible at gameplay scale. A warm face
	# alternates with a dark slender cleft and a pale exposed card splinter;
	# nothing repeats at a fixed column width or at the shared mid-height fold.
	var split: float = 0.17 + r * 0.63
	var tilt: float = (r2 - 0.5) * 0.30
	var wash: Color = color.lerp(Color("c29b69"), 0.32 + r2 * 0.25)
	if r > 0.64:
		wash = color.lerp(Color("806044"), 0.34)
	_wall_patch(landscape, data, walls, [Vector2(0.0, 0.0), Vector2(split, 0.0), Vector2(split + tilt, 0.23), Vector2(split - tilt * 0.3, 0.73), Vector2(split + 0.06, 1.0), Vector2(0.0, 1.0)], outside, wash, 0.003)
	if r2 > 0.28:
		var width: float = 0.13 + landscape._static_hash(x, z, 180.0 + salt) * 0.27
		var centre: float = 0.31 + landscape._static_hash(x, z, 181.0 + salt) * 0.48
		_wall_patch(landscape, data, walls, [Vector2(centre - width * 0.35, 0.08), Vector2(centre + width * 0.56, 0.04), Vector2(centre + width * 0.35, 0.35), Vector2(centre + width * 0.10, 0.72), Vector2(centre - width * 0.46, 0.92), Vector2(centre - width * 0.28, 0.43)], outside, color.lerp(Color("d0ac7d"), 0.43), 0.004)
	# Broad jagged fissures taper, wander and end at different heights. The
	# narrow pale edge reads as the torn thickness beside the dark ink groove.
	if r > 0.19:
		var centre: float = 0.13 + r2 * 0.73
		var width: float = 0.027 + landscape._static_hash(x, z, 183.0 + salt) * 0.061
		var end: float = 0.50 + landscape._static_hash(x, z, 185.0 + salt) * 0.48
		var bend: float = (landscape._static_hash(x, z, 187.0 + salt) - 0.5) * 0.19
		var crack: Array[Vector2] = [Vector2(centre - width, 0.005), Vector2(centre + width * 0.26, 0.005), Vector2(centre + bend + width * 0.28, 0.26), Vector2(centre + bend * 0.25 + width * 0.20, 0.56), Vector2(centre + bend * 0.7, end), Vector2(centre + bend * 0.25 - width * 0.30, 0.56), Vector2(centre + bend - width * 0.65, 0.26)]
		_wall_patch(landscape, data, walls, crack, outside, Color("60452f").lerp(color, r * 0.12), 0.006)
		var edge: Array[Vector2] = [Vector2(centre + width * 0.27, 0.005), Vector2(centre + width * 0.60, 0.015), Vector2(centre + bend + width * 0.48, 0.26), Vector2(centre + bend * 0.25 + width * 0.38, 0.53), Vector2(centre + bend * 0.25 + width * 0.21, 0.56), Vector2(centre + bend + width * 0.29, 0.26)]
		_wall_patch(landscape, data, walls, edge, outside, Color("c6a477"), 0.007)
		# Branching diagonal faults occur on only a few faces.
		if r2 > 0.72:
			_wall_patch(landscape, data, walls, [Vector2(centre + bend, 0.26), Vector2(centre + bend + 0.17, 0.34), Vector2(centre + bend + 0.29, 0.45), Vector2(centre + bend + 0.26, 0.45), Vector2(centre + bend + 0.15, 0.36), Vector2(centre + bend - 0.016, 0.27)], outside, Color("77583b"), 0.006)
	# Fragmented pale rim chips replace a continuous white outline. These
	# descend down the face, and thus imply torn edges without false top dents.
	var chips: int = 1 if r < 0.61 else 2
	for chip: int in range(chips):
		var centre: float = landscape._static_hash(x, z, 191.0 + salt + chip * 3.0)
		var width: float = 0.09 + landscape._static_hash(x, z, 193.0 + salt + chip * 3.0) * 0.24
		var depth: float = 0.035 + landscape._static_hash(x, z, 195.0 + salt + chip * 3.0) * 0.080
		_wall_patch(landscape, data, walls, [Vector2(centre - width * 0.5, 0.0), Vector2(centre + width * 0.5, 0.0), Vector2(centre + width * 0.29, depth * 0.57), Vector2(centre + width * 0.06, depth), Vector2(centre - width * 0.12, depth * 0.19), Vector2(centre - width * 0.36, depth * 0.31)], outside, Color("d7bb8f").lerp(color, 0.15), 0.008)
	# Short separated layer breaks use uneven heights, never a full-width seam.
	if landscape._static_hash(x, z, 201.0 + salt) > 0.67:
		var height: float = 0.36 + landscape._static_hash(x, z, 203.0 + salt) * 0.37
		_wall_patch(landscape, data, walls, [Vector2(0.08, height), Vector2(0.37, height - 0.012), Vector2(0.79, height + 0.018), Vector2(0.68, height + 0.032), Vector2(0.36, height + 0.013), Vector2(0.12, height + 0.020)], outside, Color("7e6041"), 0.006)
	# Dark irregular damp feet tie the face to the bank rather than an even bar.
	if r2 > 0.39:
		_wall_patch(landscape, data, walls, [Vector2(0.0, 0.93), Vector2(0.19, 0.89), Vector2(0.41, 0.95), Vector2(0.67, 0.90), Vector2(1.0, 0.96), Vector2(1.0, 1.0), Vector2(0.0, 1.0)], outside, color.darkened(0.20), 0.004)


static func _wall_patch(landscape, data: Dictionary, walls: Array, polygon: Array, outside: Vector3, color: Color, offset: float) -> void:
	for half: int in range(2):
		var local: Array[Vector2] = []
		for point: Vector2 in polygon:
			local.append(Vector2(point.x, point.y * 2.0 - half))
		if half == 0:
			_facet_patch(landscape, data, walls[0], walls[1], walls[3], walls[2], local, outside, color, offset)
		else:
			_facet_patch(landscape, data, walls[2], walls[3], walls[5], walls[4], local, outside, color, offset)


static func _facet_patch(landscape, data: Dictionary, a: Vector3, b: Vector3, c: Vector3, d: Vector3, polygon: Array[Vector2], outside: Vector3, color: Color, offset: float) -> void:
	# Exact UV clipping against both actual triangles. Merely bilinear mapping
	# would lift broad decals off a non-planar fold and create hanging ribbons.
	var triangles: Array = [[Vector2.ZERO, Vector2.RIGHT, Vector2.ONE], [Vector2.ZERO, Vector2.ONE, Vector2.DOWN]]
	for index: int in range(2):
		var clipped: Array[Vector2] = polygon.duplicate()
		var triangle: Array = triangles[index]
		for edge: int in range(3):
			clipped = _clip(clipped, triangle[edge], triangle[(edge + 1) % 3])
			if clipped.size() < 3:
				break
		if clipped.size() < 3:
			continue
		var normal: Vector3 = landscape._face_normal(a, b if index == 0 else c, c if index == 0 else d, outside)
		var points: Array[Vector3] = []
		for point: Vector2 in clipped:
			points.append(landscape._cliff_quad_point(a, b, c, d, point.x, point.y) + normal * offset)
		for vertex: int in range(1, points.size() - 1):
			landscape._triangle(data, points[0], points[vertex], points[vertex + 1], color, normal)


static func _clip(polygon: Array[Vector2], a: Vector2, b: Vector2) -> Array[Vector2]:
	var clipped: Array[Vector2] = []
	if polygon.is_empty():
		return clipped
	var edge: Vector2 = b - a
	var previous: Vector2 = polygon.back()
	var previous_distance: float = edge.cross(previous - a)
	for point: Vector2 in polygon:
		var distance: float = edge.cross(point - a)
		if (distance >= 0.0) != (previous_distance >= 0.0):
			clipped.append(previous.lerp(point, previous_distance / (previous_distance - distance)))
		if distance >= 0.0:
			clipped.append(point)
		previous = point
		previous_distance = distance
	return clipped


static func append_bank_rocks(landscape, stones: Dictionary) -> void:
	# Small angular clusters sit entirely within water cells, pressed toward
	# the true cliff foot. Bridge decks and their approach aprons stay clear.
	var map: Dictionary = landscape._map
	var anchors: Array[Vector2] = []
	for z: int in range(1, int(map.size) - 1):
		for x: int in range(1, int(map.size) - 1):
			if int(map.terrain[z][x]) != landscape.MAP.WATER:
				continue
			if landscape._static_hash(x, z, 227.0) > 0.27:
				continue
			var shore: Vector2i = Vector2i.ZERO
			for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if int(map.terrain[z + direction.y][x + direction.x]) != landscape.MAP.WATER:
					shore = direction
					break
			if shore == Vector2i.ZERO:
				continue
			var point := Vector2(x + 0.5, z + 0.5)
			if not landscape._water_bridge_clear(point):
				continue
			var separated: bool = true
			for previous: Vector2 in anchors:
				if previous.distance_squared_to(point) < 6.25:
					separated = false
			if not separated:
				continue
			anchors.append(point)
			var toward := Vector2(shore.x, shore.y)
			var tangent := Vector2(-toward.y, toward.x)
			var water_height: float = landscape._surface_height(point.x, point.y, true)
			for rock: int in range(3):
				var along: float = 0.0 if rock == 0 else (-0.24 if rock == 1 else 0.24)
				var centre: Vector2 = point + toward * (0.20 if rock == 0 else 0.12) + tangent * along
				var size: float = 0.63 if rock == 0 else 0.34 + landscape._static_hash(x, z, 229.0 + rock) * 0.13
				var height: float = 0.85 if rock == 0 else 0.40 + landscape._static_hash(x, z, 233.0 + rock) * 0.22
				var angle: float = landscape._static_hash(x, z, 237.0 + rock) * TAU
				landscape._append_water_rock(stones, Vector3(centre.x, water_height - 0.12, centre.y), Vector3(size, height, size), angle, rock % 2)
