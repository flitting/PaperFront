class_name MapData
extends RefCounted

const LAND: int = 0
const WATER: int = 1
const RAMP: int = 2
const ROAD: int = 3
const BLOCKED: int = 4
const NORTH_CONTEXT = preload("res://scripts/north_context.gd")
const FOREGROUND_GROVE = preload("res://scripts/foreground_grove.gd")
const BATTLEFIELD_CATALOG = preload("res://scripts/battlefield_catalog.gd")
const COMPETITIVE_LAYOUT = preload("res://scripts/competitive_layout.gd")
const NEIGHBOURS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]


## Deterministic maps use the same grid and movement rules in every mode.
## Legacy battlefields start on level zero; mountain headquarters use elevated
## shelves. Four real levels and carved ramps are shared by art and navigation.
static func generate(mode: String, seed: int, config: Dictionary = {}) -> Dictionary:
	var normalized_mode: String = mode.to_lower()
	if normalized_mode == "campaign":
		return preload("res://scripts/campaign_map.gd").generate(seed)
	if BATTLEFIELD_CATALOG.has_profile(normalized_mode):
		var profile_map: Dictionary = COMPETITIVE_LAYOUT.generate(normalized_mode, seed, config)
		var profile_errors: Array[String] = validate(profile_map)
		profile_map.valid = profile_errors.is_empty()
		profile_map.validation_errors = profile_errors
		return profile_map
	if normalized_mode in ["development", "test", "small", "mini"]:
		normalized_mode = "dev"
	if normalized_mode in ["handcrafted", "manual", "hand", "skirmish"]:
		normalized_mode = "handmade"
	if normalized_mode in ["mountain", "large", "mountains320"]:
		normalized_mode = "mountains"
	if normalized_mode in ["mountain640", "huge", "mountains_640"]:
		normalized_mode = "mountains640"
	if normalized_mode not in ["dev", "handmade", "random", "mountains", "mountains640"]:
		normalized_mode = "handmade"
	for attempt: int in range(8):
		var map: Dictionary = _layout(normalized_mode, seed, attempt)
		var problems: Array[String] = validate(map)
		if problems.is_empty():
			map.valid = true
			map["validation_errors"] = []
			return map
	# Remove incidental blockers and restore the guaranteed southern land road.
	var fallback: Dictionary = _layout(normalized_mode, seed, 8)
	fallback.decorations = []
	fallback.erase("foreground_grove")
	fallback.erase("north_context")
	for z: int in int(fallback.size):
		for x: int in int(fallback.size):
			if int(fallback.terrain[z][x]) == BLOCKED:
				fallback.terrain[z][x] = LAND
	var errors: Array[String] = validate(fallback)
	fallback.valid = errors.is_empty()
	fallback["validation_errors"] = errors
	return fallback


## The callback may yield; existing synchronous generation stays compatible.
static func generate_with_progress(mode: String, seed: int, progress: Callable, config: Dictionary = {}) -> Dictionary:
	if progress.is_valid(): await progress.call(0.0, "生成战场布局")
	var generated: Dictionary = generate(mode, seed, config)
	if progress.is_valid(): await progress.call(1.0, "战场布局完成")
	return generated


static func _layout(mode: String, seed: int, attempt: int) -> Dictionary:
	if mode == "mountains640": return _large_mountain_layout(seed, attempt)
	if mode == "mountains": return _mountain_layout(seed, attempt)
	var size: int = 48 if mode == "dev" else 160
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed + attempt * 7919
	var heights: Array = []
	var terrain: Array = []
	var ridge_phase: float = rng.randf_range(-0.45, 0.45) if mode == "random" else 0.15
	var ridge_columns: Array = []
	for x: int in size:
		ridge_columns.append(_ridge_edges(x, size, ridge_phase))
	for z: int in size:
		var h_row: Array[float] = []
		var t_row: Array[int] = []
		for x: int in size:
			var boundaries: Array[int] = ridge_columns[x]
			var height: float = 6.0 if z < boundaries[0] else 4.0 if z < boundaries[1] else 2.0 if z < boundaries[2] else 0.0
			h_row.append(height)
			t_row.append(LAND)
		heights.append(h_row)
		terrain.append(t_row)
	var map: Dictionary = {"mode": mode, "seed": seed, "size": size, "heights": heights, "terrain": terrain, "starts": [], "mines": [], "bridges": [], "decorations": [], "valid": false}
	var ramp_length: int = 4 if size == 48 else 8
	var ramp_width: int = 3 if size == 48 else 6
	var ramp_centres: Array[int] = [int(size * 0.20), int(size * 0.50), int(size * 0.80)]
	for level: int in range(3):
		var high: float = 6.0 - level * 2.0
		for centre: int in ramp_centres:
			var boundary: int = _ridge_edges(centre, size, ridge_phase)[level]
			_carve_ramp(map, centre, boundary, high, ramp_length, ramp_width)
	if size == 160:
		# Two broken, nested outcrops flank the river fighting ground. Their
		# southern ramps lead back to the permanent road without using the bridge.
		for centre_x: int in [52, 107]:
			_outcrop(map, Vector2(centre_x, 111), Vector2(13, 15), 2.0)
			_outcrop(map, Vector2(centre_x, 107), Vector2(6, 7), 4.0)
			_carve_ramp(map, centre_x, 114, 4.0, 6, 5)
			_carve_ramp(map, centre_x, 125, 2.0, 6, 6)
	var start_x: int = 9 if size == 48 else 19
	var start_z: int = 30 if size == 48 else 96
	map.starts = [[start_x + 0.5, start_z + 0.5], [size - start_x - 0.5, start_z + 0.5]]
	var river_width: int = 4 if size == 48 else 6
	var river_x: int = (size - river_width) / 2
	var river_top: int = 21 if size == 48 else 61
	var river_bottom: int = 39 if size == 48 else 128
	if mode == "random":
		river_top += rng.randi_range(-3, 3)
		river_bottom += rng.randi_range(-5, 5)
	for z: int in range(river_top, river_bottom):
		var bend: int = 0
		if abs(z - start_z) > (5 if size == 48 else 7):
			var travel: float = float(z - start_z) / float(river_bottom - river_top)
			bend = roundi(sin(travel * TAU * 1.15) * (2.0 if size == 48 else 6.0))
		for x: int in range(river_x + bend, river_x + bend + river_width):
			map.heights[z][x] = 0.0
			map.terrain[z][x] = WATER
	var road_width: int = 2 if size == 48 else 4
	var bridge_z: int = start_z - road_width / 2
	map.bridges.append({"id": 1, "bounds": [river_x - 1, bridge_z, river_width + 2, road_width], "heads": [[river_x - 1.5, start_z + 0.5], [river_x + river_width + 1.5, start_z + 0.5]]})
	# Centre route uses the bridge. The U-shaped southern road remains legal
	# after bridge destruction, and each northern ramp chain is also reachable.
	_road(map, Rect2i(start_x, bridge_z, size - start_x * 2, road_width))
	var bypass_z: int = river_bottom + (3 if size == 48 else 8)
	_road(map, Rect2i(start_x - road_width / 2, start_z, road_width, bypass_z - start_z + road_width))
	_road(map, Rect2i(size - start_x - road_width / 2 - 1, start_z, road_width, bypass_z - start_z + road_width))
	_road(map, Rect2i(start_x, bypass_z, size - start_x * 2, road_width))
	var near_offsets: Array[Vector2i] = [Vector2i(4, -6), Vector2i(5, 6)]
	if size != 48:
		near_offsets.assign([Vector2i(8, -8), Vector2i(9, 8)])
	for team: int in range(2):
		var start: Vector2 = Vector2(float(map.starts[team][0]), float(map.starts[team][1]))
		for offset: Vector2i in near_offsets:
			var direction: float = 1.0 if team == 0 else -1.0
			map.mines.append({"pos": [start.x + offset.x * direction, start.y + offset.y], "capacity": 3000})
	if size == 160:
		for position: Vector2 in [Vector2(46.5, 57.5), Vector2(113.5, 57.5), Vector2(49.5, 137.5), Vector2(110.5, 137.5), Vector2(62.5, 23.5), Vector2(97.5, 23.5)]:
			map.mines.append({"pos": [position.x, position.y], "capacity": 3000})
	# Compact forest stands leave broad continuous battle lanes. Each prop is
	# an actual blocked cell, never an invisible obstruction or a visual cliff.
	var cluster_count: int = 7 if size == 48 else 30
	for index: int in cluster_count:
		var x: int = rng.randi_range(3, size / 2 - 6)
		var z: int = rng.randi_range(3, size - 4)
		if mode != "random":
			x = 4 + (index * 13 + posmod(seed, 7)) % (size / 2 - 10)
			z = 4 + (index * 19 + posmod(seed, 5)) % (size - 8)
		var radius: int = 2 if size == 48 else 5
		for dz: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				if dx * dx + dz * dz > radius * radius or rng.randf() > 0.67:
					continue
				for reflected_x: int in [x + dx, size - 1 - x - dx]:
					var pos: Vector2 = Vector2(reflected_x + 0.5, z + dz + 0.5)
					if _decoration_safe(map, pos):
						var kind: String = "tree"
						if index % 7 == 0:
							kind = "rock"
						elif index % 11 == 0 and abs(dx) <= 1 and dz == 0:
							kind = "ruin" if index % 2 == 0 else "fence"
						map.decorations.append({"pos": [pos.x, pos.y], "kind": kind})
						map.terrain[z + dz][reflected_x] = BLOCKED
	sculpt_battlefield(map)
	FOREGROUND_GROVE.apply_foreground(map)
	NORTH_CONTEXT.apply_context(map)
	preload("res://scripts/battlefield_ruins.gd").apply_layout(map)
	return map


## Scale the existing basin's topology while retaining metre-sized trees and
## mining machinery. Four trees replace each original forest cell, so content
## density and the permanent road/ramp connectivity survive the larger area.
static func _large_mountain_layout(seed: int, attempt: int) -> Dictionary:
	var source: Dictionary = _mountain_layout(seed, attempt)
	var heights: Array = []
	var terrain: Array = []
	for z in range(640):
		var h_row: Array[float] = []
		var t_row: Array[int] = []
		for x in range(640):
			h_row.append(float(source.heights[z / 2][x / 2]))
			t_row.append(int(source.terrain[z / 2][x / 2]))
		heights.append(h_row)
		terrain.append(t_row)
	var map: Dictionary = {"mode": "mountains640", "seed": seed, "size": 640, "heights": heights, "terrain": terrain, "starts": [[84.5, 126.5], [555.5, 126.5]], "mines": [], "bridges": [], "decorations": [], "valid": false}
	for team in range(2):
		var start := Vector2(map.starts[team][0], map.starts[team][1])
		for offset in [Vector2(8, -8), Vector2(9, 8)]:
			var direction: float = 1.0 if team == 0 else -1.0
			var pos: Vector2 = start + Vector2(offset.x * direction, offset.y)
			map.mines.append({"pos": [pos.x, pos.y], "capacity": 3000})
	# Every remote resource patch becomes a four-pillar cluster. The duplicated
	# metre-scale apron remains clear; pillar claims still apply individually.
	for index in range(4, source.mines.size()):
		var original: Array = source.mines[index].pos
		var center := Vector2(float(original[0]) * 2.0 + (-.5 if float(original[0]) < 160.0 else .5), float(original[1]) * 2.0 - .5)
		for offset in [Vector2(-4, -4), Vector2(4, -4), Vector2(-4, 4), Vector2(4, 4)]:
			var pos: Vector2 = center + offset
			map.mines.append({"pos": [pos.x, pos.y], "capacity": source.mines[index].capacity})
	for bridge in source.bridges:
		var bounds: Array = bridge.bounds
		var heads: Array = []
		for original in bridge.heads:
			heads.append([float(original[0]) * 2.0 + (-.5 if float(original[0]) < 160.0 else .5), float(original[1]) * 2.0 - .5])
		map.bridges.append({"id": bridge.id, "bounds": [int(bounds[0]) * 2, int(bounds[1]) * 2, int(bounds[2]) * 2, int(bounds[3]) * 2], "heads": heads})
	for original in source.decorations:
		if original.kind != "tree": continue
		var cell := Vector2i(floori(float(original.pos[0])), floori(float(original.pos[1])))
		for dz in range(2):
			for dx in range(2):
				var pos := Vector2(cell.x * 2 + dx + .5, cell.y * 2 + dz + .5)
				if not _decoration_safe(map, pos): continue
				map.decorations.append({"pos": [pos.x, pos.y], "kind": "tree"})
				map.terrain[int(pos.y)][int(pos.x)] = BLOCKED
	preload("res://scripts/battlefield_ruins.gd").apply_layout(map)
	return map


## A mirrored mountain basin, four times the area of the 160-cell battlefield.
## Both headquarters occupy broad level-four shelves and descend through
## permanent switchback ramps; the southern road remains usable without bridges.
static func _mountain_layout(seed: int, attempt: int) -> Dictionary:
	var size: int = 320
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + attempt * 7919
	var phase: float = rng.randf_range(-0.3, 0.3)
	var heights: Array = []
	var terrain: Array = []
	var columns: Array = []
	for x in range(size): columns.append(_ridge_edges(x, size, phase))
	for z in range(size):
		var h_row: Array[float] = []
		var t_row: Array[int] = []
		for x in range(size):
			var edges: Array[int] = columns[x]
			h_row.append(6.0 if z < edges[0] else 4.0 if z < edges[1] else 2.0 if z < edges[2] else 0.0)
			t_row.append(LAND)
		heights.append(h_row)
		terrain.append(t_row)
	var map: Dictionary = {"mode": "mountains", "seed": seed, "size": size, "heights": heights, "terrain": terrain, "starts": [[42.5, 63.5], [277.5, 63.5]], "mines": [], "bridges": [], "decorations": [], "valid": false}
	# Preserve many ridge crossings in addition to each headquarters' own ramps.
	for center in [42, 91, 160, 228, 277]:
		var edges: Array[int] = _ridge_edges(center, size, phase)
		for level in range(3): _carve_ramp(map, center, edges[level], 6.0 - float(level) * 2.0, 14, 10)
	# The guaranteed shelves are wider than the starting construction apron.
	for team in range(2):
		var center: int = 42 if team == 0 else 277
		for z in range(43, 89):
			for x in range(center - 24, center + 25):
				map.heights[z][x] = 4.0
				map.terrain[z][x] = LAND
		var north_edge: int = _ridge_edges(center, size, phase)[0]
		_carve_ramp(map, center, north_edge, 6.0, 14, 10)
		# Extend the shelf's southern descent onto the pre-existing level-two band.
		_carve_ramp(map, center, 89, 4.0, 14, 10)
		for offset in [Vector2(8, -8), Vector2(9, 8)]:
			var direction: float = 1.0 if team == 0 else -1.0
			map.mines.append({"pos": [float(center) + 0.5 + offset.x * direction, 63.5 + offset.y], "capacity": 3000})
	# Broken rings and high spurs surround the lower valleys, with two-stage ramps.
	for west in [Vector2(73, 207), Vector2(121, 225), Vector2(96, 284)]:
		for center in [west, Vector2(float(size) - west.x, west.y)]:
			_outcrop(map, center, Vector2(25, 29), 2.0)
			_outcrop(map, center + Vector2(0, -7), Vector2(12, 14), 4.0)
			_carve_ramp(map, int(center.x), int(center.y) + 8, 4.0, 14, 10)
			_carve_ramp(map, int(center.x), int(center.y) + 30, 2.0, 14, 10)
	# A broad central river and paired lakes leave the permanent road untouched.
	for z in range(140, 280):
		var half: int = 4 + roundi((sin(float(z - 140) * 0.065) + 1.0) * 1.0)
		for x in range(160 - half, 160 + half):
			map.heights[z][x] = 0.0
			map.terrain[z][x] = WATER
	for center in [Vector2(20, 226), Vector2(299, 226)]:
		for z in range(int(center.y) - 23, int(center.y) + 24):
			for x in range(int(center.x) - 14, int(center.x) + 15):
				if ((Vector2(x, z) - center) / Vector2(14, 23)).length_squared() < 1.0:
					map.heights[z][x] = 0.0
					map.terrain[z][x] = WATER
	map.bridges.append({"id": 1, "bounds": [153, 171, 14, 6], "heads": [[151.5, 174.5], [168.5, 174.5]]})
	_road(map, Rect2i(42, 171, 236, 6))
	for x in [39, 274]: _road(map, Rect2i(x, 63, 6, 231))
	_road(map, Rect2i(42, 291, 236, 6))
	for west in [Vector2(92.5, 57.5), Vector2(91.5, 157.5), Vector2(72.5, 207.5), Vector2(121.5, 225.5), Vector2(111.5, 264.5), Vector2(137.5, 308.5)]:
		for pos in [west, Vector2(float(size) - west.x, west.y)]:
			map.mines.append({"pos": [pos.x, pos.y], "capacity": 4000})
	for index in range(76):
		var center := Vector2i(rng.randi_range(6, 150), rng.randi_range(6, 312))
		for dz in range(-5, 6):
			for dx in range(-5, 6):
				if dx * dx + dz * dz > 25 or rng.randf() > 0.62: continue
				for x in [center.x + dx, size - 1 - center.x - dx]:
					var pos := Vector2(float(x) + 0.5, float(center.y + dz) + 0.5)
					if not _decoration_safe(map, pos): continue
					map.decorations.append({"pos": [pos.x, pos.y], "kind": "tree"})
					map.terrain[center.y + dz][x] = BLOCKED
	preload("res://scripts/battlefield_ruins.gd").apply_layout(map)
	return map


## Legacy snapshots may still store a tree in the static terrain mask.
## Fresh maps use neutral-entity footprints; their ground never changes on death.
static func clear_destroyed_tree(map: Dictionary, tree: Dictionary) -> bool:
	if tree.get("kind") != "tree" or float(tree.get("hp", 0.0)) > 0.0: return false
	var point: Vector2 = tree.get("pos", Vector2.INF)
	if not _position_inside(map, point): return false
	var c: Vector2i = cell(map, point)
	if int(map.terrain[c.y][c.x]) != BLOCKED: return false
	map.terrain[c.y][c.x] = LAND
	return true


## The same bounded edit is used by fresh maps and explicit copies of G0.
## protected_points accepts Vector2/[x,z], or {pos, radius, size, buffer};
## radius is a footprint radius, size is a square side, buffer is >= 2 metres.
## Never regenerate entities/props when calling this on an existing fixture.
static func sculpt_battlefield(map: Dictionary, protected_points: Array = []) -> Dictionary:
	var result: Dictionary = {"water_cells": [], "protected_cells": 0}
	if int(map.get("size", 0)) != 160:
		return result
	var protected: Dictionary = {}
	for z: int in int(map.size):
		for x: int in int(map.size):
			if int(map.terrain[z][x]) in [RAMP, ROAD, BLOCKED]:
				_sculpt_protect_rect(map, protected, Rect2i(x - 2, z - 2, 5, 5))
	for mine: Dictionary in map.get("mines", []):
		_sculpt_protect_point(map, protected, _sculpt_position(mine.get("pos")), 3.0)
	for start in map.get("starts", []):
		_sculpt_protect_point(map, protected, _sculpt_position(start), 11.0)
	for bridge: Dictionary in map.get("bridges", []):
		var bounds: Array = bridge.bounds
		_sculpt_protect_rect(map, protected, Rect2i(int(bounds[0]) - 2, int(bounds[1]) - 2, int(bounds[2]) + 4, int(bounds[3]) + 4))
		for head in bridge.heads:
			_sculpt_protect_point(map, protected, _sculpt_position(head), 2.0)
	for point in protected_points:
		var position: Vector2 = _sculpt_position(point.get("pos") if point is Dictionary else point)
		var footprint: float = 0.0
		var buffer: float = 2.0
		if point is Dictionary:
			footprint = maxf(float(point.get("radius", 0.0)), float(point.get("size", 0.0)) * 0.707107)
			buffer = maxf(2.0, float(point.get("buffer", 2.0)))
		_sculpt_protect_point(map, protected, position, maxf(0.0, footprint) + buffer)
	result.protected_cells = protected.size()
	# Recess the west bank in three large steps; unchanged rows 110/116 form noses.
	# Only actual LAND0 can become water. Existing water is the connection seed.
	var bay: Dictionary = {}
	var bay_rows: Array = [[111, 82, 82], [112, 81, 82], [113, 79, 82], [114, 79, 82], [115, 80, 81]]
	for row: Array in bay_rows:
		for x: int in range(int(row[1]), int(row[2]) + 1):
			_sculpt_candidate(map, protected, bay, Vector2i(x, int(row[0])))
	var attached_bay: Dictionary = _sculpt_attached(map, bay)
	for point: Vector2i in bay:
		if attached_bay.has(point):
			map.terrain[point.y][point.x] = WATER
			result.water_cells.append([point.x, point.y])
	return result


static func _sculpt_position(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Vector2i:
		return Vector2(value)
	if value is Array and value.size() == 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.INF


static func _sculpt_protect_rect(map: Dictionary, protected: Dictionary, bounds: Rect2i) -> void:
	for z: int in range(maxi(0, bounds.position.y), mini(int(map.size), bounds.end.y)):
		for x: int in range(maxi(0, bounds.position.x), mini(int(map.size), bounds.end.x)):
			protected[Vector2i(x, z)] = true


static func _sculpt_protect_point(map: Dictionary, protected: Dictionary, position: Vector2, radius: float) -> void:
	if not position.is_finite():
		return
	for z: int in range(maxi(0, floori(position.y - radius) - 1), mini(int(map.size), ceili(position.y + radius) + 1)):
		for x: int in range(maxi(0, floori(position.x - radius) - 1), mini(int(map.size), ceili(position.x + radius) + 1)):
			# Distance to the entire cell, not its centre, protects footprint edges.
			var nearest := Vector2(clampf(position.x, float(x), float(x + 1)), clampf(position.y, float(z), float(z + 1)))
			if nearest.distance_squared_to(position) <= radius * radius:
				protected[Vector2i(x, z)] = true


static func _sculpt_candidate(map: Dictionary, protected: Dictionary, candidates: Dictionary, point: Vector2i) -> void:
	if _inside(map, point) and not protected.has(point) and int(map.terrain[point.y][point.x]) == LAND and is_zero_approx(float(map.heights[point.y][point.x])):
		candidates[point] = true


static func _sculpt_attached(map: Dictionary, candidates: Dictionary) -> Dictionary:
	var reference: Dictionary = {}
	# Use only the original river component underneath the original bridge.
	var queue: Array[Vector2i] = []
	for bridge: Dictionary in map.get("bridges", []):
		var bounds: Array = bridge.bounds
		for z: int in range(int(bounds[1]), int(bounds[1]) + int(bounds[3])):
			for x: int in range(int(bounds[0]), int(bounds[0]) + int(bounds[2])):
				var point := Vector2i(x, z)
				if _inside(map, point) and int(map.terrain[z][x]) == WATER and not reference.has(point):
					reference[point] = true
					queue.append(point)
	var cursor: int = 0
	while cursor < queue.size():
		var point: Vector2i = queue[cursor]
		cursor += 1
		for direction: Vector2i in NEIGHBOURS:
			var next: Vector2i = point + direction
			if _inside(map, next) and not reference.has(next) and int(map.terrain[next.y][next.x]) == WATER:
				reference[next] = true
				queue.append(next)
	var attached: Dictionary = {}
	queue.clear()
	for point: Vector2i in candidates:
		for direction: Vector2i in NEIGHBOURS:
			var next: Vector2i = point + direction
			if not _inside(map, next):
				continue
			var touches_reference: bool = reference.has(next)
			if touches_reference:
				attached[point] = true
				queue.append(point)
				break
	cursor = 0
	while cursor < queue.size():
		var point: Vector2i = queue[cursor]
		cursor += 1
		for direction: Vector2i in NEIGHBOURS:
			var next: Vector2i = point + direction
			if candidates.has(next) and not attached.has(next):
				attached[next] = true
				queue.append(next)
	return attached


static func _ridge_edges(x: int, size: int, phase: float) -> Array[int]:
	var folded: float = float(mini(x, size - 1 - x)) / float(size) * TAU
	var scale: float = float(size) / 160.0
	var wave: float = sin(folded * 1.55 + phase) * 7.0 + sin(folded * 3.8) * 3.0
	var shoulder: float = exp(-pow((folded - 1.95) / 0.6, 2.0))
	var first: int = roundi((16.0 + wave * 0.45) * scale)
	var second: int = roundi((32.0 + wave * 0.7 + shoulder * 5.0) * scale)
	var third: int = roundi((48.0 + wave + shoulder * 17.0) * scale)
	if size == 48:
		first += 1
		second += 2
		third += 2
	return [first, second, third]


static func _carve_ramp(map: Dictionary, centre: int, boundary: int, high: float, length: int, width: int) -> void:
	for offset: int in length:
		var z: int = boundary - length / 2 + offset
		for x: int in range(centre - width / 2, centre - width / 2 + width):
			if _inside(map, Vector2i(x, z)):
				map.heights[z][x] = high - 2.0 * float(offset + 1) / float(length + 1)
				map.terrain[z][x] = RAMP


static func _outcrop(map: Dictionary, centre: Vector2, radius: Vector2, high: float) -> void:
	for z: int in range(floori(centre.y - radius.y), ceili(centre.y + radius.y)):
		for x: int in range(floori(centre.x - radius.x), ceili(centre.x + radius.x)):
			var point: Vector2 = (Vector2(x, z) - centre) / radius
			var angle: float = point.angle()
			if point.length_squared() < 1.0 + sin(angle * 5.0) * 0.12 and _inside(map, Vector2i(x, z)):
				map.heights[z][x] = high
				map.terrain[z][x] = LAND


static func _road(map: Dictionary, rect: Rect2i) -> void:
	for z: int in range(maxi(0, rect.position.y), mini(int(map.size), rect.end.y)):
		for x: int in range(maxi(0, rect.position.x), mini(int(map.size), rect.end.x)):
			if int(map.terrain[z][x]) == LAND:
				map.terrain[z][x] = ROAD


static func _decoration_safe(map: Dictionary, pos: Vector2) -> bool:
	if not _position_inside(map, pos):
		return false
	# The development map retains its clear southern combat test range.
	if int(map.size) == 48 and pos.y >= 39.0 and (pos.x < 21.0 or pos.x > 27.0):
		return false
	var c: Vector2i = cell(map, pos)
	if int(map.terrain[c.y][c.x]) != LAND:
		return false
	var clearance: float = 8.0 if int(map.size) == 48 else 20.0
	for start: Array in map.starts:
		if pos.distance_to(Vector2(float(start[0]), float(start[1]))) < clearance:
			return false
	for mine: Dictionary in map.mines:
		if pos.distance_to(Vector2(float(mine.pos[0]), float(mine.pos[1]))) < 3.0:
			return false
	for dz: int in range(-2, 3):
		for dx: int in range(-2, 3):
			var neighbour: Vector2i = c + Vector2i(dx, dz)
			if _inside(map, neighbour) and int(map.terrain[neighbour.y][neighbour.x]) in [RAMP, ROAD, WATER]:
				return false
	return true


static func cell(map: Dictionary, pos: Vector2) -> Vector2i:
	var size: int = int(map.get("size", 1))
	return Vector2i(clampi(int(floor(pos.x)), 0, size - 1), clampi(int(floor(pos.y)), 0, size - 1))


static func terrain_at(map: Dictionary, pos: Vector2) -> int:
	var c: Vector2i = cell(map, pos)
	return int(map.terrain[c.y][c.x])


static func height_at(map: Dictionary, pos: Vector2) -> float:
	var c: Vector2i = cell(map, pos)
	var height: float = float(map.heights[c.y][c.x])
	# Only the ramp axis interpolates. Cliffs retain their full vertical face;
	# sampling a position near a cliff cannot create a false climbable slope.
	if int(map.terrain[c.y][c.x]) == RAMP:
		var fraction: float = pos.y - (c.y + 0.5)
		var next_z: int = c.y + (1 if fraction >= 0.0 else -1)
		if next_z >= 0 and next_z < int(map.size):
			var next_height: float = float(map.heights[next_z][c.x])
			if absf(next_height - height) <= 0.75:
				return lerpf(height, next_height, absf(fraction))
	return height


static func water_surface_y(map: Dictionary, pos: Vector2) -> float:
	return height_at(map, pos) - 2.65


static func entity_surface_y(map: Dictionary, pos: Vector2, domain: String = "ground") -> float:
	return water_surface_y(map, pos) if domain == "naval" else height_at(map, pos)


static func validate(map: Dictionary) -> Array[String]:
	if str(map.get("mode", "")) == "campaign":
		return preload("res://scripts/campaign_map.gd").validate(map)
	if map.has("profile") and not map.profile is Dictionary:
		return ["map: malformed battlefield profile"]
	if map.get("profile", {}).get("schema", 0) == BATTLEFIELD_CATALOG.SCHEMA:
		return COMPETITIVE_LAYOUT.validate(map)
	var problems: Array[String] = []
	var size: int = int(map.get("size", 0))
	if size < 16 or not map.get("heights") is Array or not map.get("terrain") is Array:
		problems.append("map: invalid size or missing terrain/height arrays")
		return problems
	if map.heights.size() != size or map.terrain.size() != size:
		problems.append("map: grid row count does not match size")
		return problems
	var layers: Dictionary = {}
	var ramp_count: int = 0
	for z: int in size:
		if not map.heights[z] is Array or not map.terrain[z] is Array or map.heights[z].size() != size or map.terrain[z].size() != size:
			problems.append("map: grid row %d does not match size" % z)
			return problems
		for x: int in size:
			var h: float = float(map.heights[z][x])
			var t: int = int(map.terrain[z][x])
			if not is_finite(h) or h < 0.0 or h > 6.0 or t < LAND or t > BLOCKED:
				problems.append("map[%d][%d]: invalid height/terrain" % [z, x])
			if t == RAMP:
				ramp_count += 1
			elif h in [0.0, 2.0, 4.0, 6.0]:
				layers[int(h)] = true
	if layers.size() < 4:
		problems.append("map: all four real height levels are required")
	if ramp_count == 0:
		problems.append("map: no traversable ramps")
	if not map.get("starts") is Array or map.starts.size() != 2:
		problems.append("map: expected two spawn positions")
		return problems
	for team: int in range(2):
		if not map.starts[team] is Array or map.starts[team].size() != 2:
			problems.append("map.starts[%d]: expected [x,z]" % team)
			continue
		var pos: Vector2 = Vector2(float(map.starts[team][0]), float(map.starts[team][1]))
		if not _position_inside(map, pos):
			problems.append("map.starts[%d]: position is outside the map" % team)
			continue
		var c: Vector2i = cell(map, pos)
		var radius: int = 4 if size == 48 else 9
		for z: int in range(c.y - radius, c.y + radius + 1):
			for x: int in range(c.x - radius, c.x + radius + 1):
				if not _inside(map, Vector2i(x, z)) or int(map.terrain[z][x]) not in [LAND, ROAD] or not is_equal_approx(float(map.heights[z][x]), float(map.heights[c.y][c.x])):
					problems.append("map.starts[%d]: insufficient flat, clear building space at [%d,%d]" % [team, x, z])
	if not map.get("bridges") is Array or map.bridges.is_empty():
		problems.append("map: expected at least one neutral destructible bridge")
	else:
		var bridge_ids: Dictionary = {}
		for bridge: Dictionary in map.bridges:
			var id: int = int(bridge.get("id", -1))
			if id < 1 or bridge_ids.has(id):
				problems.append("map.bridges: invalid or duplicate bridge ID %d" % id)
			bridge_ids[id] = true
			if not bridge.get("bounds") is Array or bridge.bounds.size() != 4 or not bridge.get("heads") is Array or bridge.heads.size() != 2:
				problems.append("map.bridges[%d]: missing bounds or bridgeheads" % id)
				continue
			var bounds: Rect2i = Rect2i(int(bridge.bounds[0]), int(bridge.bounds[1]), int(bridge.bounds[2]), int(bridge.bounds[3]))
			if bounds.size.x <= 0 or bounds.size.y <= 0 or bounds.position.x < 0 or bounds.position.y < 0 or bounds.end.x > size or bounds.end.y > size:
				problems.append("map.bridges[%d]: invalid map bounds" % id)
				continue
			var water_cells: int = 0
			for z: int in range(bounds.position.y, bounds.end.y):
				for x: int in range(bounds.position.x, bounds.end.x):
					if int(map.terrain[z][x]) == WATER:
						water_cells += 1
			if water_cells == 0:
				problems.append("map.bridges[%d]: bridge does not span water" % id)
			for head: Variant in bridge.heads:
				if not head is Array or head.size() != 2:
					problems.append("map.bridges[%d]: malformed bridgehead position" % id)
					continue
				var pos: Vector2 = Vector2(float(head[0]), float(head[1]))
				if not _position_inside(map, pos) or terrain_at(map, pos) not in [LAND, ROAD]:
					problems.append("map.bridges[%d]: bridgehead must be on legal bank terrain" % id)
	if not problems.is_empty():
		return problems
	var first: Vector2i = cell(map, Vector2(float(map.starts[0][0]), float(map.starts[0][1])))
	var second: Vector2i = cell(map, Vector2(float(map.starts[1][0]), float(map.starts[1][1])))
	# Flood deliberately excludes every bridge. Its connected component is a
	# permanent land guarantee, independent of destructible bridge state.
	var reachable: PackedByteArray = _land_flood(map, first)
	if reachable[second.y * size + second.x] == 0:
		problems.append("map: spawns lack a land route independent of destructible bridges")
	var accessible_layers: Dictionary = {}
	for z: int in size:
		for x: int in size:
			if reachable[z * size + x] == 1:
				var h: float = float(map.heights[z][x])
				if h in [0.0, 2.0, 4.0, 6.0]:
					accessible_layers[int(h)] = true
	if accessible_layers.size() < 4:
		problems.append("map: one or more height layers lack a legal ramp route")
	if not map.get("mines") is Array:
		problems.append("map.mines: missing resource positions")
		return problems
	var near_distances: Array = [[], []]
	for index: int in map.mines.size():
		if not map.mines[index] is Dictionary or not map.mines[index].get("pos") is Array or map.mines[index].pos.size() != 2:
			problems.append("map.mines[%d]: missing [x,z] position" % index)
			continue
		var mine: Dictionary = map.mines[index]
		var pos: Vector2 = Vector2(float(mine.pos[0]), float(mine.pos[1]))
		if not _position_inside(map, pos):
			problems.append("map.mines[%d]: position is outside the map" % index)
			continue
		var c: Vector2i = cell(map, pos)
		if float(mine.get("capacity", 0)) <= 0.0 or reachable[c.y * size + c.x] == 0:
			problems.append("map.mines[%d]: invalid capacity or unreachable resource" % index)
		for team: int in range(2):
			var start: Vector2 = Vector2(float(map.starts[team][0]), float(map.starts[team][1]))
			var distance: float = pos.distance_to(start)
			if distance <= (12.0 if size == 48 else 18.0):
				near_distances[team].append({"distance": distance, "capacity": float(mine.capacity)})
	for team: int in range(2):
		if near_distances[team].size() < 2:
			problems.append("map.starts[%d]: fewer than two reachable near ore patches" % team)
	if near_distances[0].size() != near_distances[1].size():
		problems.append("map: unequal starting resource count")
	else:
		for index: int in near_distances[0].size():
			if absf(float(near_distances[0][index].distance) - float(near_distances[1][index].distance)) > 0.01 or near_distances[0][index].capacity != near_distances[1][index].capacity:
				problems.append("map: unequal starting ore distance or capacity")
	return problems


static func _inside(map: Dictionary, c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < int(map.size) and c.y < int(map.size)


static func _position_inside(map: Dictionary, pos: Vector2) -> bool:
	return is_finite(pos.x) and is_finite(pos.y) and pos.x >= 0.0 and pos.y >= 0.0 and pos.x < float(map.size) and pos.y < float(map.size)


static func _land_flood(map: Dictionary, start: Vector2i) -> PackedByteArray:
	var size: int = int(map.size)
	var visited: PackedByteArray = PackedByteArray()
	visited.resize(size * size)
	visited.fill(0)
	var queue: Array[Vector2i] = [start]
	visited[start.y * size + start.x] = 1
	var cursor: int = 0
	while cursor < queue.size():
		var here: Vector2i = queue[cursor]
		cursor += 1
		for direction: Vector2i in NEIGHBOURS:
			var next: Vector2i = here + direction
			if not _inside(map, next) or visited[next.y * size + next.x] == 1:
				continue
			if int(map.terrain[next.y][next.x]) in [WATER, BLOCKED]:
				continue
			if absf(float(map.heights[here.y][here.x]) - float(map.heights[next.y][next.x])) > 0.75:
				continue
			visited[next.y * size + next.x] = 1
			queue.append(next)
	return visited
