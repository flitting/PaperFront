extends RefCounted

## Two connected extensions of the existing northern woods.
## All cells are resolved before mutation; normal maps and fixture copies share
## the same plan without consuming either legacy random-number stream.
const GROVE = preload("res://scripts/foreground_grove.gd")
const LAND: int = 0
const RAMP: int = 2
const ROAD: int = 3
const BLOCKED: int = 4
const FOREST_ROWS: Array = [
	[79, 61, 65], [80, 61, 66], [81, 61, 67],
	[82, 63, 68], [83, 63, 66], [84, 63, 65],
]


## Public API. Only LAND0 changes, into visible tree blockers.
## Existing BLOCKED cells may join a new wing but are never changed. Reject the
## whole candidate if any cell is unsafe or either wing is detached.
static func apply_context(map: Dictionary, protected_points: Array = []) -> Dictionary:
	var result: Dictionary = {"added_cells": [], "additions": []}
	if int(map.get("size", 0)) != 160 or not map.get("north_context", []).is_empty():
		return result
	var protected: Dictionary = {}
	for z: int in int(map.size):
		for x: int in int(map.size):
			if int(map.terrain[z][x]) in [RAMP, ROAD]:
				GROVE._protect_rect(map, protected, Rect2i(x - 2, z - 2, 5, 5))
	for mine: Dictionary in map.get("mines", []):
		GROVE._protect_point(map, protected, GROVE._position(mine.get("pos")), 3.0)
	for start in map.get("starts", []):
		GROVE._protect_point(map, protected, GROVE._position(start), 11.0)
	for bridge: Dictionary in map.get("bridges", []):
		var bounds: Array = bridge.bounds
		GROVE._protect_rect(map, protected, Rect2i(int(bounds[0]) - 2, int(bounds[1]) - 2, int(bounds[2]) + 4, int(bounds[3]) + 4))
		for head in bridge.heads:
			GROVE._protect_point(map, protected, GROVE._position(head), 2.0)
	for value in protected_points:
		var point: Vector2 = GROVE._position(value.get("pos") if value is Dictionary else value)
		var footprint: float = 0.0
		var buffer: float = 2.0
		if value is Dictionary:
			footprint = maxf(float(value.get("radius", 0.0)), float(value.get("size", 0.0)) * 0.707107)
			buffer = maxf(2.0, float(value.get("buffer", 2.0)))
		GROVE._protect_point(map, protected, point, maxf(0.0, footprint) + buffer)
	var forests: Array[Dictionary] = [_row_cells(FOREST_ROWS), _row_cells(FOREST_ROWS, true)]
	for candidates: Dictionary in forests:
		for cell: Vector2i in candidates:
			if protected.has(cell) or int(map.terrain[cell.y][cell.x]) != LAND or not is_zero_approx(float(map.heights[cell.y][cell.x])):
				result["rejected_cell"] = [cell.x, cell.y]
				return result
	if not _forest_attached(map, forests[0]) or not _forest_attached(map, forests[1]):
		result["rejected_reason"] = "Candidate must remain attached to both original forest wings"
		return result
	for forest: Dictionary in forests:
		for cell: Vector2i in forest:
			map.terrain[cell.y][cell.x] = BLOCKED
			result.added_cells.append([cell.x, cell.y])
	# Grow broad, varied crowns inside the connected woods. Exposed instances
	# remain entirely inside their 1m cells and taper toward the open valley.
	for wing: int in forests.size():
		for cell: Vector2i in forests[wing]:
			var edge: bool = false
			for direction: Vector2i in GROVE.DIRECTIONS:
				var next: Vector2i = cell + direction
				edge = edge or int(map.terrain[next.y][next.x]) != BLOCKED
			var west_x: int = cell.x if wing == 0 else 159 - cell.x
			var variant: int = posmod(west_x + cell.y * 2 + wing, 3)
			var rhythm: float = float(posmod(west_x * 3 + cell.y * 5 + wing * 2, 7)) / 6.0
			var horizontal: float = 0.74 if edge else 1.0
			var vertical: float = 0.74 + rhythm * 0.26 if edge else 1.14 + rhythm * 0.34
			var yaw: float = fposmod(float(west_x) * 2.17 + float(cell.y) * 1.43 + float(wing) * 0.91, TAU)
			result.additions.append({"kind": "tree", "pos": [float(cell.x) + 0.5, float(cell.y) + 0.5], "variant": variant, "scale": [horizontal, vertical, horizontal], "yaw": yaw})
	map["north_context"] = result.additions.duplicate(true)
	result["forest_wings_attached"] = true
	return result


static func append_prop_batches(map: Dictionary, resolved_groups: Array) -> Array:
	return GROVE.append_prop_batches(map, resolved_groups, "north_context", "north_context")


static func _row_cells(rows: Array, mirror: bool = false) -> Dictionary:
	var result: Dictionary = {}
	for row: Array in rows:
		for x: int in range(int(row[1]), int(row[2]) + 1):
			result[Vector2i(159 - x if mirror else x, int(row[0]))] = true
	return result


static func _forest_attached(map: Dictionary, candidates: Dictionary) -> bool:
	var queue: Array[Vector2i] = []
	var visited: Dictionary = {}
	for cell: Vector2i in candidates:
		for direction: Vector2i in GROVE.DIRECTIONS:
			var next: Vector2i = cell + direction
			if int(map.terrain[next.y][next.x]) == BLOCKED:
				visited[cell] = true
				queue.append(cell)
				break
	var cursor: int = 0
	while cursor < queue.size():
		var cell: Vector2i = queue[cursor]
		cursor += 1
		for direction: Vector2i in GROVE.DIRECTIONS:
			var next: Vector2i = cell + direction
			if candidates.has(next) and not visited.has(next):
				visited[next] = true
				queue.append(next)
	return visited.size() == candidates.size()
