extends RefCounted
class_name V6RandomCityLayout

const CITY = preload("res://scripts/v6_city_layout.gd")
const CATALOG = preload("res://scripts/battlefield_catalog.gd")
const SIZE := 320
const LAND := 0
const WATER := 1
const ROAD := 3
const CANAL: Array[Vector2] = [Vector2(93, 0), Vector2(105, 47), Vector2(130, 91),
	Vector2(158, 138), Vector2(179, 187), Vector2(202, 243), Vector2(229, 320)]
const BRIDGE_Z: Array[int] = [51, 92, 139, 194, 266]

static func generate(seed: int, config: Dictionary = {}) -> Dictionary:
	var players: int = clampi(int(config.get("players", 2)), 2, 4)
	var profile: Dictionary = CATALOG.profile("random_city", players)
	profile.title = "种子城市"
	profile.design_version = 6
	profile.ground = "718569"
	profile.road = "68716b"
	profile.water = "194d68"
	profile.street_spacing = 0
	profile.street_origin = 0
	profile.districts = [
		{"id":"old_town", "center":Vector2(89, 137), "radius":Vector2(50, 52)},
		{"id":"modern", "center":Vector2(216, 138), "radius":Vector2(42, 50)},
		{"id":"civic_park", "center":Vector2(129, 220), "radius":Vector2(42, 31)},
		{"id":"freight_port", "center":Vector2(248, 196), "radius":Vector2(43, 48)}]
	var map: Dictionary = {"mode":"random_city", "seed":seed, "size":SIZE, "heights":[], "terrain":[],
		"starts":[], "mines":[], "bridges":[], "decorations":[], "ruins":[],
		"environment_props":[], "civilians":[], "harbors":[], "landing_beaches":[],
		"profile":profile, "layout":[], "road_mark_cells":{}, "valid":false, "water_surface_y":-2.65}
	CITY._starts(map, players)
	_terrain(map)
	_bridges(map)
	_economy(map)
	_roads(map)
	_landmarks(map)
	_port_and_fort(map)
	_blocks(map)
	_densify(map)
	_greenery(map)
	preload("res://scripts/battlefield_ruins.gd").register_trees(map)
	var count: int = 0
	for row: Array in map.terrain:
		for kind: int in row:
			if kind == WATER: count += 1
	map.profile.water_fraction = float(count) / float(SIZE * SIZE)
	return map

static func _canal_x(z: float) -> float:
	for i: int in range(CANAL.size() - 1):
		if z <= CANAL[i + 1].y:
			var t: float = clampf((z - CANAL[i].y) / (CANAL[i + 1].y - CANAL[i].y), 0, 1)
			t = t * t * (3.0 - 2.0 * t)
			return lerpf(CANAL[i].x, CANAL[i + 1].x, t)
	return CANAL[-1].x

static func _water(x: float, z: float) -> bool:
	if not CITY._inside_city(x, z): return true
	if absf(x - _canal_x(z)) < 9.2 + sin(z * .067) * 1.1: return true
	var west_bay: Vector2 = Vector2((x - 55.0) / 26.0, (z - 130.0) / 23.0)
	if west_bay.length_squared() < 1.0: return true
	if z > 114.0 and z < 150.0 and x < 55.0 and absf(z - 130.0) < 8.0: return true
	# The freight side basin opens onto the same canal and broad eastern sea.
	var freight: Vector2 = Vector2((x - 250.0) / 20.0, (z - 203.0) / 24.0)
	if freight.length_squared() < 1.0: return true
	if z > 185.0 and z < 217.0 and x > 245.0 and absf(z - 202.0) < 8.0: return true
	return false

static func _terrain(map: Dictionary) -> void:
	var distances := PackedInt32Array()
	distances.resize(SIZE * SIZE)
	distances.fill(999)
	var queue: Array[Vector2i] = []
	for z: int in SIZE:
		var heights: Array[float] = []
		var terrain: Array[int] = []
		for x: int in SIZE:
			var wet: bool = _water(x + .5, z + .5)
			terrain.append(WATER if wet else LAND)
			heights.append(0.0)
			if wet:
				queue.append(Vector2i(x, z))
				distances[z * SIZE + x] = 0
		map.terrain.append(terrain)
		map.heights.append(heights)
	var cursor: int = 0
	while cursor < queue.size():
		var here: Vector2i = queue[cursor]
		cursor += 1
		var next_distance: int = distances[here.y * SIZE + here.x] + 1
		if next_distance > 5: continue
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = here + direction
			if next.x < 0 or next.y < 0 or next.x >= SIZE or next.y >= SIZE: continue
			var index: int = next.y * SIZE + next.x
			if next_distance >= distances[index]: continue
			distances[index] = next_distance
			queue.append(next)
	for z: int in SIZE:
		for x: int in SIZE:
			if int(map.terrain[z][x]) != WATER:
				map.heights[z][x] = -0.6 * float(maxi(0, 5 - distances[z * SIZE + x]))
	for center: Vector2 in [Vector2(58.5, 58.5), Vector2(261.5, 58.5),
		Vector2(261.5, 261.5), Vector2(58.5, 261.5)]:
		for z: int in range(int(center.y) - 16, int(center.y) + 17):
			for x: int in range(int(center.x) - 16, int(center.x) + 17):
				if int(map.terrain[z][x]) != WATER: map.heights[z][x] = 0.0

static func _bridges(map: Dictionary) -> void:
	for id: int in BRIDGE_Z.size():
		var z: int = BRIDGE_Z[id]
		var cx: int = roundi(_canal_x(float(z)))
		var left: int = cx
		while left > 20 and int(map.terrain[z][left]) == WATER: left -= 1
		var right: int = cx
		while right < 300 and int(map.terrain[z][right]) == WATER: right += 1
		var first: int = left - 4
		var width: int = right - left + 8
		map.bridges.append({"id":id + 1, "bounds":[first, z - 4, width, 9],
			"heads":[[float(left) - 2.5, z + .5], [float(right) + 2.5, z + .5]],
			"naval_clearance":2.5, "style":"stone_arch"})
		for row: int in range(z - 5, z + 6):
			for col: int in range(first - 5, first + width + 5):
				if col >= 0 and row >= 0 and col < SIZE and row < SIZE and int(map.terrain[row][col]) != WATER: map.heights[row][col] = 0.0

static func _economy(map: Dictionary) -> void:
	for record: Dictionary in map.layout:
		var start: Vector2 = record.start
		for side: float in [-1.0, 1.0]:
			CITY._add_mine(map, start + record.inward * 10.0 + Vector2(side * 8.0, 0), int(record.team), "near")
			var expansion: Vector2 = start + record.inward * 51.0 + Vector2(side * 20.0, 0)
			if start.x > 200.0 and start.y > 200.0 and side < 0.0:
				# The image's eastern freight basin occupies the straight inward
				# point; preserve the exact 54.78 m start distance on dry east bank.
				expansion = start + Vector2(-35.0, -sqrt(3001.0 - 35.0 * 35.0))
			CITY._add_mine(map, expansion, int(record.team), "expansion")
		CITY._add_harbor(map, int(record.team), CITY._coast(map, start, record.outward), record.outward)
	for team: int in map.layout.size(): CITY._add_mine(map, [Vector2(107, 84),Vector2(208, 84),Vector2(207, 228),Vector2(106, 228)][team], -1, "contested")

static func _roads(map: Dictionary) -> void:
	CITY._polyline(map, [Vector2(58, 58),Vector2(54, 88),Vector2(43, 139),Vector2(55, 192),Vector2(55, 262)], 3.0)
	CITY._polyline(map, [Vector2(262, 58),Vector2(276, 94),Vector2(268, 145),Vector2(276, 204),Vector2(262, 262)], 3.0)
	CITY._polyline(map, [Vector2(59, 59),Vector2(91, 61),Vector2(135, 54),Vector2(188, 54),Vector2(261, 59)], 3.0)
	CITY._polyline(map, [Vector2(58, 260),Vector2(96, 248),Vector2(137, 258),Vector2(191, 258),Vector2(261, 260)], 3.0)
	for z: int in BRIDGE_Z:
		var cx: float = _canal_x(float(z))
		CITY._polyline(map, [Vector2(49, z + 5),Vector2(cx - 21, z),Vector2(cx + 20, z),Vector2(264, z - 3)], 2.9)
	CITY._polyline(map, [Vector2(77, 78),Vector2(101, 111),Vector2(81, 151),Vector2(113, 187),Vector2(105, 220)], 2.3)
	CITY._polyline(map, [Vector2(190, 77),Vector2(215, 112),Vector2(238, 146),Vector2(218, 187),Vector2(244, 218)], 2.7)
	CITY._polyline(map, [Vector2(91, 188),Vector2(130, 198),Vector2(126, 229),Vector2(87, 241)], 2.4)
	for record: Dictionary in map.layout:
		CITY._road(map, record.start, record.start + record.inward * 55.0, 3.0)
		CITY._road(map, record.start, record.start + record.outward * 28.0, 3.0)

static func _landmarks(map: Dictionary) -> void:
	for item: Dictionary in [
		{"p":Vector2(73, 143),"art":"church","h":11.8},
		{"p":Vector2(143, 158),"art":"civic_hall","h":9.2},
		{"p":Vector2(224, 136),"art":"office_tower","h":20.0},
		{"p":Vector2(223, 187),"art":"freight_shed","h":5.4},
		{"p":Vector2(220, 206),"art":"freight_shed","h":5.4},
		{"p":Vector2(272, 180),"art":"rail_station","h":6.8},
		{"p":Vector2(39, 94),"art":"stone_fort","h":6.5},
		{"p":Vector2(60, 96),"art":"clock_tower","h":15.0},
	]: CITY._house(map, item.p, item.art, item.h, "random_city", true)
	CITY._prop(map, Vector2(145, 174), "fountain", 1, 1.0)
	CITY._prop(map, Vector2(126, 217), "fountain", 2, .7)
	for point: Vector2 in [Vector2(22, 21),Vector2(296, 215),Vector2(288, 288)]: CITY._prop(map, point, "lighthouse", 1, 1.0)
	for i: int in 5: CITY._prop(map, Vector2(239 + i * 5, 206), "cargo_stack", i % 3, 1.0)
	for i: int in 3: CITY._prop(map, Vector2(250 + i * 7, 211), "harbor_crane", i % 3, 1.0)
	for point: Vector2 in [Vector2(239,198),Vector2(244,209),Vector2(256,205),Vector2(264,197)]:
		if int(map.terrain[floori(point.y)][floori(point.x)]) != WATER:
			CITY._prop(map, point, "cargo_stack", int(point.x) % 3, 1.0)

static func _port_and_fort(map: Dictionary) -> void:
	# The widened west-bank fort faces the bay; preserve its approach and wall clearance.
	for point: Vector2 in [Vector2(231, 180), Vector2(243, 180), Vector2(265, 174), Vector2(275, 219), Vector2(272, 232)]:
		CITY._house(map, point, "warehouse", 4.2, "freight_port", true)
	for z: int in range(184, 224, 3):
		for x: int in [274, 278]:
			if int(map.terrain[z][x]) != WATER:
				CITY._prop(map, Vector2(x + .5, z + .5), "rail_track", 0, 1.0, PI * .5)
	for z: int in range(184, 219, 3):
		if int(map.terrain[z][229]) != WATER:
			CITY._prop(map, Vector2(229.5, z + .5), "quay_wall", 0, 1.2, PI * .5)

static func _blocks(map: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(map.seed) + 704321
	for zone: Dictionary in [
		{"from":Vector2i(63, 90),"to":Vector2i(130, 188),"step":6,"art":"old_townhouse","height":5.1,"chance":.86},
		{"from":Vector2i(191, 98),"to":Vector2i(249, 177),"step":8,"art":"modern_block","height":9.5,"chance":.75},
		{"from":Vector2i(43, 196),"to":Vector2i(103, 236),"step":9,"art":"rowhouse","height":5.1,"chance":.65},
		{"from":Vector2i(179, 33),"to":Vector2i(241, 81),"step":9,"art":"rowhouse","height":5.1,"chance":.66},
		{"from":Vector2i(229, 174),"to":Vector2i(274, 233),"step":10,"art":"warehouse","height":4.2,"chance":.63},
	]:
		for z: int in range(zone.from.y, zone.to.y, zone.step):
			for x: int in range(zone.from.x, zone.to.x, zone.step):
				if rng.randf() > zone.chance: continue
				var point: Vector2 = Vector2(x + rng.randf_range(-1.3, 1.3), z + rng.randf_range(-1.3, 1.3))
				CITY._house(map, point, zone.art, zone.height, "random_city")
	for z: int in range(54, 262, 15):
		for x: int in range(56, 273, 17):
			var point: Vector2 = Vector2(x + .5, z + .5)
			if CITY._roadside(map, point): CITY._prop(map, point, "streetlamp", (x + z) % 3, 1.0)
	for i: int in 25:
		var point: Vector2 = Vector2(61 + (i % 5) * 39, 57 + int(i / 5) * 43)
		if int(map.terrain[floori(point.y)][floori(point.x)]) == WATER: continue
		map.civilians.append({"id":map.civilians.size(),"route":[point,point + Vector2(4,0),point + Vector2(4,2),point + Vector2(0,2)],"speed":.62,"phase":float(i * 5),"variant":i % 3})

static func _densify(map: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(map.seed) + 179603
	for zone: Dictionary in [
		{"from":Vector2i(55, 86),"to":Vector2i(139, 192),"step":4.9,"art":"old_townhouse","height":5.1,"chance":.69},
		{"from":Vector2i(184, 88),"to":Vector2i(258, 185),"step":5.3,"art":"modern_block","height":9.5,"chance":.64},
		{"from":Vector2i(232, 179),"to":Vector2i(277, 238),"step":6.1,"art":"warehouse","height":4.2,"chance":.57},
	]:
		var z: float = float(zone.from.y)
		var row: int = 0
		while z < float(zone.to.y):
			var x: float = float(zone.from.x) + (float(zone.step) * .48 if row % 2 else 0.0)
			while x < float(zone.to.x):
				if rng.randf() < float(zone.chance):
					CITY._house(map, Vector2(x + rng.randf_range(-.4,.4), z + rng.randf_range(-.4,.4)),
						str(zone.art), float(zone.height), "random_city")
				x += float(zone.step)
			z += float(zone.step)
			row += 1

static func _greenery(map: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(map.seed) + 380517
	for zone: Dictionary in [
		{"p":Vector2(123, 220),"r":Vector2(45, 34),"n":550},
		{"p":Vector2(74, 36),"r":Vector2(55, 34),"n":340},
		{"p":Vector2(275, 72),"r":Vector2(34, 68),"n":330},
		{"p":Vector2(70, 274),"r":Vector2(57, 29),"n":340},
		{"p":Vector2(187, 280),"r":Vector2(92, 30),"n":380},
	]:
		for i: int in int(zone.n):
			var angle: float = rng.randf_range(0, TAU)
			var radial: float = sqrt(rng.randf())
			var point: Vector2 = zone.p + Vector2(cos(angle) * zone.r.x, sin(angle) * zone.r.y) * radial
			if CITY._tree_safe(map, point): CITY._add_tree(map, point, i % 3)
	for segment: int in 5:
		var a: Vector2 = Vector2(281 - segment * 2, 91 + segment * 33)
		var b: Vector2 = a + Vector2(-3, 31)
		for i: int in 16:
			var point: Vector2 = a.lerp(b, float(i) / 16.0)
			if int(map.terrain[floori(point.y)][floori(point.x)]) != WATER: CITY._prop(map, point, "rail_track", 0, 1.0, (b - a).angle())
