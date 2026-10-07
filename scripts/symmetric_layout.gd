extends RefCounted
class_name SymmetricLayout

## A fixed laboratory battlefield: seeds remain part of match provenance,
## while topology and scenery stay identical across seeds for comparisons.
## Every authored cell and neutral footprint reflects across both map axes.
const SIZE := 192
const LAND := 0
const RAMP := 2
const ROAD := 3
const RUINS = preload("res://scripts/battlefield_ruins.gd")
const DIRECTIONS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

static func generate(seed: int) -> Dictionary:
	var map: Dictionary = {"mode":"symmetric", "seed":seed, "size":SIZE,
		"heights":[], "terrain":[], "starts":[[32.0,96.0],[160.0,96.0]],
		"mines":[], "bridges":[], "decorations":[], "ruins":[],
		"environment_props":[], "civilians":[], "harbors":[], "landing_beaches":[],
		"layout":[], "valid":false, "water_surface_y":-2.65,
		"profile":{"schema":1, "id":"symmetric", "title":"明原对称场", "biome":"meadow",
			"players":2, "layout":"opposed", "routes":"land", "ground":"a0c99e",
			"road":"e0d3b4", "water":"6aa0af", "water_fraction":0.0,
			"symmetry":"mirror_x_and_z", "fixed_layout":true, "design_version":1}}
	for z: int in SIZE:
		var heights: Array[float] = []
		var terrain: Array[int] = []
		var edge_z: int = mini(z, SIZE - 1 - z)
		var height: float = 6.0 if edge_z < 16 else 4.0 if edge_z < 32 else 2.0 if edge_z < 48 else 0.0
		for x: int in SIZE:
			heights.append(height)
			terrain.append(LAND)
		map.heights.append(heights)
		map.terrain.append(terrain)
	# Ten metre ramps join all four terraces. Mirroring authored values rather
	# than evaluating separate curves guarantees exact cell-for-cell equality.
	for center: int in [32,96,160]:
		for level: int in 3:
			for offset: int in 8:
				var z: int = 12 + level * 16 + offset
				var height: float = 6.0 - level * 2.0 - 2.0 * float(offset + 1) / 9.0
				for x: int in range(center - 5, center + 5):
					for target_z: int in [z, SIZE - 1 - z]:
						map.heights[target_z][x] = height
						map.terrain[target_z][x] = RAMP
	# Three broad ground routes remain usable without removing any scenery.
	for rectangle: Rect2i in [Rect2i(20,92,152,8), Rect2i(24,60,144,8), Rect2i(24,124,144,8), Rect2i(28,64,8,64), Rect2i(156,64,8,64)]:
		for z: int in range(rectangle.position.y, rectangle.end.y):
			for x: int in range(rectangle.position.x, rectangle.end.x):
				map.terrain[z][x] = ROAD
	for team: int in 2:
		var start := Vector2(float(map.starts[team][0]), float(map.starts[team][1]))
		map.layout.append({"team":team, "start":start, "inward":Vector2.RIGHT if team == 0 else Vector2.LEFT,
			"outward":Vector2.LEFT if team == 0 else Vector2.RIGHT, "tangent":Vector2.DOWN,
			"near_mines":[], "expansion_mines":[]})
		for point: Vector2 in [Vector2(44,84),Vector2(44,108)]:
			_add_mine(map, point if team == 0 else Vector2(SIZE-point.x,point.y), team, "near", 4000)
		for point: Vector2 in [Vector2(65,64),Vector2(65,128)]:
			_add_mine(map, point if team == 0 else Vector2(SIZE-point.x,point.y), team, "expansion", 6000)
	for z: float in [54.0,138.0]: _add_mine(map, Vector2(SIZE * .5,z), -1, "contested", 6000)
	# Four small neutral cottages are set back from fighting and mining lanes.
	for x: float in [70.0,122.0]:
		for z: float in [38.0,154.0]:
			map.ruins.append({"id":map.ruins.size(), "kind":"house", "archetype":"cottage",
				"height":3.2, "pos":Vector2(x,z), "half":Vector2(2.1,2.1), "yaw":0.0,
				"hp":900.0, "max_hp":900.0, "variant":0})
	var trees: Array[Vector2] = [Vector2(10.5,10.5),Vector2(13.5,11.5),Vector2(11.5,14.5),
		Vector2(52.5,24.5),Vector2(55.5,24.5),Vector2(54.5,27.5),
		Vector2(12.5,56.5),Vector2(15.5,58.5),Vector2(13.5,60.5),
		Vector2(78.5,13.5),Vector2(81.5,16.5),Vector2(79.5,19.5)]
	for index: int in trees.size():
		for x: float in [trees[index].x, SIZE - trees[index].x]:
			for z: float in [trees[index].y, SIZE - trees[index].y]:
				map.decorations.append({"pos":[x,z], "kind":"tree", "variant":index % 3, "yaw":0.0})
	RUINS.register_trees(map)
	return map

static func _add_mine(map: Dictionary, point: Vector2, team: int, tier: String, capacity: int) -> void:
	var index: int = map.mines.size()
	map.mines.append({"pos":[point.x,point.y], "capacity":capacity, "team":team, "tier":tier})
	if team >= 0: map.layout[team]["near_mines" if tier == "near" else "expansion_mines"].append(index)

static func validate(map: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if int(map.get("size", 0)) != SIZE or not map.get("heights") is Array or not map.get("terrain") is Array:
		return ["symmetric: invalid battlefield dimensions or grid"]
	if map.heights.size() != SIZE or map.terrain.size() != SIZE:
		return ["symmetric: invalid grid row count"]
	if not map.get("profile") is Dictionary or int(map.profile.get("players", 0)) != 2:
		return ["symmetric: exactly two players are required"]
	for z: int in SIZE:
		if not map.heights[z] is Array or not map.terrain[z] is Array or map.heights[z].size() != SIZE or map.terrain[z].size() != SIZE:
			return ["symmetric: malformed grid row"]
	for z: int in SIZE:
		for x: int in SIZE:
			var height: float = float(map.heights[z][x])
			var kind: int = int(map.terrain[z][x])
			if not is_finite(height) or height < 0.0 or height > 6.0 or kind not in [LAND,RAMP,ROAD]:
				return ["symmetric: only finite land, roads and ramps are allowed"]
			if height != float(map.heights[z][SIZE-1-x]) or height != float(map.heights[SIZE-1-z][x]) or kind != int(map.terrain[z][SIZE-1-x]) or kind != int(map.terrain[SIZE-1-z][x]):
				return ["symmetric: terrain or height differs across a mirror axis"]
	if not map.get("starts") is Array or map.starts.size() != 2:
		return ["symmetric: exactly two real starts are required"]
	for start: Variant in map.starts:
		if not start is Array or start.size() != 2 or not _inside(_point(start)):
			return ["symmetric: malformed start"]
	var first: Vector2 = _point(map.starts[0])
	var second: Vector2 = _point(map.starts[1])
	if first.x + second.x != SIZE or first.y != second.y or first.y != SIZE * .5:
		return ["symmetric: starts must be exact opposing mirrors"]
	for start: Vector2 in [first,second]:
		if start.x < 21.0 or start.x > SIZE-21.0: return ["symmetric: insufficient headquarters apron"]
		for z: int in range(floori(start.y)-10,floori(start.y)+11):
			for x: int in range(floori(start.x)-10,floori(start.x)+11):
				if int(map.terrain[z][x]) not in [LAND,ROAD] or float(map.heights[z][x]) != 0.0:
					return ["symmetric: headquarters needs a clear flat apron"]
	if not map.get("bridges") is Array or not map.bridges.is_empty(): return ["symmetric: land-only map has no bridges"]
	if not map.get("mines") is Array or map.mines.size() != 10: return ["symmetric: expected ten mirrored ore deposits"]
	for mine: Variant in map.mines:
		if not mine is Dictionary or not mine.get("pos") is Array or mine.pos.size() != 2 or not _inside(_point(mine.pos)) or float(mine.get("capacity",0)) <= 0.0:
			return ["symmetric: malformed ore deposit"]
	for mine: Dictionary in map.mines:
		var point: Vector2 = _point(mine.pos)
		for reflected: Vector2 in [Vector2(SIZE-point.x,point.y),Vector2(point.x,SIZE-point.y)]:
			var expected_team: int = 1-int(mine.team) if reflected.x != point.x and int(mine.team) >= 0 else int(mine.team)
			if not map.mines.any(func(other): return _point(other.pos) == reflected and int(other.get("team",-2)) == expected_team and other.get("tier") == mine.get("tier") and other.get("capacity") == mine.capacity):
				return ["symmetric: ore distance, capacity or ownership lacks a mirror"]
	for team: int in 2:
		for tier: String in ["near","expansion"]:
			if map.mines.filter(func(m): return int(m.get("team",-1)) == team and str(m.get("tier","")) == tier).size() != 2:
				return ["symmetric: each player needs two near and two expansion deposits"]
	if not map.get("ruins") is Array: return ["symmetric: missing neutral footprints"]
	for index: int in map.ruins.size():
		var ruin: Variant = map.ruins[index]
		if not ruin is Dictionary or int(ruin.get("id",-1)) != index or not ruin.get("pos") is Vector2 or not ruin.get("half") is Vector2 or not _inside(ruin.pos) or str(ruin.get("kind","")) not in ["tree","house"]:
			return ["symmetric: malformed neutral footprint or ID"]
	for ruin: Dictionary in map.ruins:
		if ruin.pos.distance_to(first) < 26.0 or ruin.pos.distance_to(second) < 26.0: return ["symmetric: scenery intrudes into base construction space"]
		for reflected: Vector2 in [Vector2(SIZE-ruin.pos.x,ruin.pos.y),Vector2(ruin.pos.x,SIZE-ruin.pos.y)]:
			if not map.ruins.any(func(other): return other.pos == reflected and other.kind == ruin.kind and other.half == ruin.half and other.get("hp") == ruin.get("hp") and other.get("variant") == ruin.get("variant") and other.get("archetype") == ruin.get("archetype")):
				return ["symmetric: neutral footprint lacks an identical mirror"]
	var reachable: PackedByteArray = flood(map, Vector2i(floori(first.x),floori(first.y)))
	if reachable[floori(second.y)*SIZE+floori(second.x)] == 0: errors.append("symmetric: starts lack a permanent land route")
	var layers: Dictionary = {}
	for z: int in SIZE:
		for x: int in SIZE:
			if reachable[z*SIZE+x] == 1: layers[float(map.heights[z][x])] = true
	for height: float in [0.0,2.0,4.0,6.0]:
		if not layers.has(height): errors.append("symmetric: a terrace lacks a usable ramp route")
	for mine: Dictionary in map.mines:
		var point: Vector2 = _point(mine.pos)
		if reachable[floori(point.y)*SIZE+floori(point.x)] == 0: errors.append("symmetric: ore lacks permanent access")
	return errors

static func _point(raw: Array) -> Vector2:
	return Vector2(float(raw[0]),float(raw[1]))

static func _inside(point: Vector2) -> bool:
	return point.is_finite() and point.x >= 0.0 and point.y >= 0.0 and point.x < SIZE and point.y < SIZE

static func flood(map: Dictionary, start: Vector2i) -> PackedByteArray:
	var visited := PackedByteArray()
	visited.resize(SIZE*SIZE)
	var queue: Array[Vector2i] = [start]
	visited[start.y*SIZE+start.x] = 1
	var cursor: int = 0
	while cursor < queue.size():
		var here: Vector2i = queue[cursor]
		cursor += 1
		for direction: Vector2i in DIRECTIONS:
			var next: Vector2i = here + direction
			if next.x < 0 or next.y < 0 or next.x >= SIZE or next.y >= SIZE or visited[next.y*SIZE+next.x] != 0: continue
			if int(map.terrain[next.y][next.x]) not in [LAND,RAMP,ROAD] or absf(float(map.heights[here.y][here.x])-float(map.heights[next.y][next.x])) > .75: continue
			visited[next.y*SIZE+next.x] = 1
			queue.append(next)
	return visited
