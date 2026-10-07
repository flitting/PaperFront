extends RefCounted
class_name PathTerrainGeometry

# These values describe immutable terrain only. Destroyed bridges remain
# dynamic obstacles in the worker's revisioned collision snapshot.
static func build(data: Dictionary) -> Array[Rect2]:
	var rectangles: Array[Rect2] = []
	var size: int = int(data.size)
	var land: PackedByteArray = data.land
	var heights: PackedFloat32Array = data.heights
	_append_water(rectangles, size, land)
	_append_vertical_cliffs(rectangles, size, land, heights)
	_append_horizontal_cliffs(rectangles, size, land, heights)
	return rectangles


static func _append_water(rectangles: Array[Rect2], size: int, land: PackedByteArray) -> void:
	var active: Dictionary = {}
	for z in range(size):
		var next: Dictionary = {}
		var x: int = 0
		while x < size:
			if land[z * size + x] != 0:
				x += 1
				continue
			var first: int = x
			while x < size and land[z * size + x] == 0: x += 1
			var key := Vector2i(first, x)
			if active.has(key):
				var prior: Rect2 = active[key]
				next[key] = Rect2(prior.position, prior.size + Vector2(0, 1))
			else:
				next[key] = Rect2(Vector2(first, z), Vector2(x - first, 1))
		for key in active:
			if not next.has(key): rectangles.append(active[key])
		active = next
	for rectangle: Rect2 in active.values(): rectangles.append(rectangle)


static func _append_vertical_cliffs(rectangles: Array[Rect2], size: int, land: PackedByteArray, heights: PackedFloat32Array) -> void:
	for x in range(1, size):
		var first: int = -1
		for z in range(size):
			var right: int = z * size + x
			var left: int = right - 1
			var blocked: bool = land[left] != 0 and land[right] != 0 and absf(heights[left] - heights[right]) > .8
			if blocked and first < 0: first = z
			elif not blocked and first >= 0:
				rectangles.append(Rect2(Vector2(x, first), Vector2(0, z - first)))
				first = -1
		if first >= 0: rectangles.append(Rect2(Vector2(x, first), Vector2(0, size - first)))


static func _append_horizontal_cliffs(rectangles: Array[Rect2], size: int, land: PackedByteArray, heights: PackedFloat32Array) -> void:
	for z in range(1, size):
		var first: int = -1
		for x in range(size):
			var below: int = z * size + x
			var above: int = below - size
			var blocked: bool = land[above] != 0 and land[below] != 0 and absf(heights[above] - heights[below]) > .8
			if blocked and first < 0: first = x
			elif not blocked and first >= 0:
				rectangles.append(Rect2(Vector2(first, z), Vector2(x - first, 0)))
				first = -1
		if first >= 0: rectangles.append(Rect2(Vector2(first, z), Vector2(size - first, 0)))
