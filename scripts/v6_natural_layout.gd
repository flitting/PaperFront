extends RefCounted
class_name V6NaturalLayout

# Forest, desert and snow retain fair four-corner play while the river, lakes,
# ridges and authored landmarks follow their paired concept images.
const CITY = preload("res://scripts/v6_city_layout.gd")
const CATALOG = preload("res://scripts/battlefield_catalog.gd")
const SIZE := 320
const LAND := 0
const WATER := 1
const ROAD := 3
const SPEC := {
	"forest": {"title":"翠林溪谷", "river":[Vector2(144, 0),Vector2(136, 43),Vector2(153, 85),Vector2(142, 117),Vector2(153, 151),Vector2(139, 185),Vector2(153, 217),Vector2(140, 265),Vector2(149, 320)],
		"width":9.0, "bridges":[87, 139, 199, 267], "lake":Vector2(118, 176), "lake_r":Vector2(34, 25), "ground":"70885f", "road":"9f947a", "water":"326b83"},
	"desert": {"title":"金砂峡谷", "river":[Vector2(145, 0),Vector2(148, 65),Vector2(148, 117),Vector2(150, 165),Vector2(141, 218),Vector2(150, 270),Vector2(148, 320)],
		"width":8.0, "bridges":[79, 134, 165, 224], "lake":Vector2(139, 190), "lake_r":Vector2(28, 19), "ground":"c59d65", "road":"a78b68", "water":"2d8b93"},
	"snow": {"title":"白雪冻河", "river":[Vector2(114, 0),Vector2(112, 50),Vector2(120, 103),Vector2(128, 149),Vector2(145, 209),Vector2(145, 265),Vector2(143, 320)],
		"width":9.5, "bridges":[37, 116, 145, 267], "lake":Vector2(145, 195), "lake_r":Vector2(41, 56), "ground":"d4d9d5", "road":"a1aba8", "water":"426b85"},
}

static func generate(mode: String, seed: int, config: Dictionary = {}) -> Dictionary:
	var design: Dictionary = SPEC[mode]
	var players: int = clampi(int(config.get("players", 2)), 2, 4)
	var profile: Dictionary = CATALOG.profile(mode, players)
	profile.title = design.title
	profile.design_version = 6
	profile.max_height = 18.0
	profile.ground = "506b49" if mode == "forest" else "bc8e5d" if mode == "desert" else "b9c7c7"
	profile.road = design.road
	profile.water = "22516b" if mode == "forest" else "277e8e" if mode == "desert" else "2e5b79"
	profile.landmarks = _landmark_records(mode)
	var map: Dictionary = {"mode":mode, "seed":seed, "size":SIZE, "heights":[], "terrain":[],
		"starts":[], "mines":[], "bridges":[], "decorations":[], "ruins":[],
		"environment_props":[], "civilians":[], "harbors":[], "landing_beaches":[],
		"profile":profile, "layout":[], "road_mark_cells":{}, "valid":false, "water_surface_y":-2.65}
	CITY._starts(map, players)
	_terrain(map, mode, design)
	_bridges(map, mode, design)
	_economy(map)
	_flatten_playable_aprons(map)
	_roads(map, mode, design)
	_landmarks(map, mode)
	_ridge_spires(map, mode)
	_scenery(map, mode)
	preload("res://scripts/battlefield_ruins.gd").register_trees(map)
	var wet: int = 0
	for row: Array in map.terrain:
		for kind: int in row:
			if kind == WATER: wet += 1
	map.profile.water_fraction = float(wet) / float(SIZE * SIZE)
	return map

static func _river_x(design: Dictionary, z: float) -> float:
	var anchors: Array = design.river
	for index: int in range(anchors.size() - 1):
		if z <= (anchors[index + 1] as Vector2).y:
			var a: Vector2 = anchors[index]
			var b: Vector2 = anchors[index + 1]
			var t: float = clampf((z - a.y) / (b.y - a.y), 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)
			return lerpf(a.x, b.x, t)
	return (anchors[-1] as Vector2).x

static func _coast_inside(x: float, z: float, mode: String) -> bool:
	var west: float = 17.0 + sin(z * .039 + .7) * 4.5 + sin(z * .101) * 2.3
	var east: float = 303.0 + sin(z * .041 + 1.4) * 4.2 + sin(z * .109) * 2.0
	var north: float = 17.0 + sin(x * .047) * 4.4 + sin(x * .113 + .6) * 1.7
	var south: float = 303.0 + sin(x * .041 + .3) * 4.2 + sin(x * .097 + 1.1) * 2.2
	if mode == "snow":
		west -= 3.0
		east += 3.0
		north -= 3.0
		south += 3.0
	return x > west and x < east and z > north and z < south

static func _water(x: float, z: float, mode: String, design: Dictionary) -> bool:
	if not _coast_inside(x, z, mode): return true
	if mode == "forest" and Vector2(x, z).distance_to(Vector2(111, 177)) <= 5.8: return false
	if mode == "snow" and Vector2(x, z).distance_to(Vector2(122, 203)) <= 7.3: return false
	var river_width: float = float(design.width) + sin(z * .074) * 1.4
	if mode == "forest" and z >= 102.0 and z <= 142.0: river_width += 3.2
	if absf(x - _river_x(design, z)) <= river_width: return true
	var lake: Vector2 = design.lake
	var radius: Vector2 = design.lake_r
	var normalized: Vector2 = Vector2((x - lake.x) / radius.x, (z - lake.y) / radius.y)
	if normalized.length_squared() <= 1.0: return true
	if mode == "snow":
		# The heavy ship must turn from the narrow frozen river into the broad
		# lake without clipping the inside bank between A* grid waypoints.
		var turn: Vector2 = Geometry2D.get_closest_point_to_segment(Vector2(x, z), Vector2(124, 126), Vector2(148, 160))
		if z >= 126.0 and z <= 165.0 and Vector2(x, z).distance_to(turn) <= 13.0: return true
	if mode == "desert":
		var upper: Vector2 = Vector2((x - 146.0) / 20.0, (z - 106.0) / 14.0)
		if upper.length_squared() <= 1.0: return true
	if mode == "forest":
		var creek: Vector2 = Vector2((x - 133.0) / 18.0, (z - 166.0) / 13.0)
		if creek.length_squared() <= 1.0: return true
	return false

static func _relief(x: float, z: float, mode: String) -> float:
	var value: float = 0.0
	# Long shoulders, rather than isolated summits, make the north skyline read
	# from the oblique camera. The river gap remains the natural pass.
	var shoulders: Array[Dictionary]
	match mode:
		"forest": shoulders = [
			{"a":Vector2(26, 30),"b":Vector2(124, 33),"w":19.0,"h":14.8},
			{"a":Vector2(166, 32),"b":Vector2(293, 27),"w":21.0,"h":15.6},
			{"a":Vector2(289, 86),"b":Vector2(290, 205),"w":16.0,"h":10.0}]
		"desert": shoulders = [
			{"a":Vector2(27, 31),"b":Vector2(125, 33),"w":21.0,"h":17.6},
			{"a":Vector2(171, 30),"b":Vector2(294, 32),"w":22.0,"h":17.8},
			{"a":Vector2(289, 86),"b":Vector2(289, 224),"w":20.0,"h":16.7},
			{"a":Vector2(29, 183),"b":Vector2(31, 247),"w":17.0,"h":12.0}]
		_: shoulders = [
			{"a":Vector2(27, 30),"b":Vector2(101, 32),"w":19.0,"h":15.2},
			{"a":Vector2(135, 29),"b":Vector2(292, 30),"w":21.0,"h":17.8},
			{"a":Vector2(291, 89),"b":Vector2(291, 207),"w":17.0,"h":13.0}]
	for shoulder: Dictionary in shoulders:
		var d: float = Vector2(x,z).distance_to(Geometry2D.get_closest_point_to_segment(Vector2(x,z), shoulder.a, shoulder.b))
		var plateau: float = 5.0 if mode == "desert" else 2.0
		var t: float = clampf((d - plateau) / (float(shoulder.w) - plateau), 0.0, 1.0)
		value = maxf(value, float(shoulder.h) * (1.0 - t * t * (3.0 - 2.0 * t)))
	var ridges: Array[Dictionary]
	match mode:
		"forest": ridges = [
			{"p":Vector2(51, 31), "r":Vector2(52, 38), "h":13.5},
			{"p":Vector2(259, 31), "r":Vector2(55, 37), "h":14.5},
			{"p":Vector2(293, 151), "r":Vector2(27, 91), "h":10.5},
			{"p":Vector2(56, 288), "r":Vector2(49, 33), "h":10.0}]
		"desert": ridges = [
			{"p":Vector2(39, 31), "r":Vector2(39, 43), "h":17.5},
			{"p":Vector2(281, 32), "r":Vector2(40, 42), "h":17.5},
			{"p":Vector2(255, 105), "r":Vector2(44, 37), "h":16.5},
			{"p":Vector2(31, 207), "r":Vector2(31, 82), "h":11.0},
			{"p":Vector2(289, 233), "r":Vector2(33, 80), "h":11.5}]
		_: ridges = [
			{"p":Vector2(178, 30), "r":Vector2(71, 40), "h":17.0},
			{"p":Vector2(282, 111), "r":Vector2(39, 81), "h":15.0},
			{"p":Vector2(65, 287), "r":Vector2(44, 38), "h":11.5},
			{"p":Vector2(257, 287), "r":Vector2(45, 40), "h":12.0}]
	for ridge: Dictionary in ridges:
		var scaled: Vector2 = Vector2((x - ridge.p.x) / ridge.r.x, (z - ridge.p.y) / ridge.r.y)
		value = maxf(value, float(ridge.h) * pow(maxf(0.0, 1.0 - scaled.length_squared()), 1.8))
	return value

static func _terrain(map: Dictionary, mode: String, design: Dictionary) -> void:
	var distance := PackedInt32Array()
	distance.resize(SIZE * SIZE)
	distance.fill(999)
	var queue: Array[Vector2i] = []
	for z: int in SIZE:
		var heights: Array[float] = []
		var terrain: Array[int] = []
		for x: int in SIZE:
			var wet: bool = _water(x + .5, z + .5, mode, design)
			terrain.append(WATER if wet else LAND)
			heights.append(0.0)
			if wet:
				queue.append(Vector2i(x, z))
				distance[z * SIZE + x] = 0
		map.terrain.append(terrain)
		map.heights.append(heights)
	var cursor: int = 0
	while cursor < queue.size():
		var here: Vector2i = queue[cursor]
		cursor += 1
		var next_distance: int = distance[here.y * SIZE + here.x] + 1
		if next_distance > 5: continue
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = here + direction
			if next.x < 0 or next.y < 0 or next.x >= SIZE or next.y >= SIZE: continue
			var index: int = next.y * SIZE + next.x
			if next_distance >= distance[index]: continue
			distance[index] = next_distance
			queue.append(next)
	for z: int in SIZE:
		for x: int in SIZE:
			if int(map.terrain[z][x]) == WATER: continue
			var beach: float = -0.6 * float(maxi(0, 5 - distance[z * SIZE + x]))
			var relief: float = _relief(x + .5, z + .5, mode) * smoothstep(5.0, 11.0, float(distance[z * SIZE + x]))
			if mode == "desert" and distance[z * SIZE + x] > 12:
				relief += .27 * sin(float(x) * .19 + float(z) * .035) + .16 * sin(float(x) * .11 - float(z) * .083)
			map.heights[z][x] = clampf(beach + relief, -2.4, float(map.profile.max_height))
	for center: Vector2 in [Vector2(58.5, 58.5), Vector2(261.5, 58.5),
		Vector2(261.5, 261.5), Vector2(58.5, 261.5)]:
		for z: int in range(int(center.y) - 16, int(center.y) + 17):
			for x: int in range(int(center.x) - 16, int(center.x) + 17):
				if int(map.terrain[z][x]) != WATER: map.heights[z][x] = 0.0

static func _bridges(map: Dictionary, mode: String, design: Dictionary) -> void:
	for index: int in design.bridges.size():
		var z: int = int(design.bridges[index])
		var center: float = _river_x(design, float(z))
		var left: int = floori(center)
		while left > 20 and int(map.terrain[z][left]) == WATER: left -= 1
		var right: int = ceili(center)
		while right < 300 and int(map.terrain[z][right]) == WATER: right += 1
		var bounds_left: int = left - 4
		var width: int = right - left + 8
		map.bridges.append({"id":index + 1, "bounds":[bounds_left, z - 4, width, 9],
			"heads":[[float(left) - 2.5, z + .5], [float(right) + 2.5, z + .5]],
			"naval_clearance":2.5, "style":"timber" if mode == "forest" else "stone_arch"})
		for row: int in range(z - 5, z + 6):
			for col: int in range(bounds_left - 5, bounds_left + width + 5):
				if col >= 0 and row >= 0 and col < SIZE and row < SIZE and int(map.terrain[row][col]) != WATER:
					map.heights[row][col] = 0.0

static func _economy(map: Dictionary) -> void:
	for record: Dictionary in map.layout:
		var start: Vector2 = record.start
		for side: float in [-1.0, 1.0]:
			CITY._add_mine(map, start + record.inward * 10.0 + Vector2(side * 8.0, 0), int(record.team), "near")
			CITY._add_mine(map, start + record.inward * 51.0 + Vector2(side * 20.0, 0), int(record.team), "expansion")
		CITY._add_harbor(map, int(record.team), CITY._coast(map, start, record.outward), record.outward)
	var contested: Array[Vector2] = [Vector2(93.5, 124.5), Vector2(207.5, 123.5),
		Vector2(209.5, 228.5), Vector2(93.5, 229.5)]
	for team: int in map.layout.size(): CITY._add_mine(map, contested[team], -1, "contested")

static func _flatten_playable_aprons(map: Dictionary) -> void:
	for record: Dictionary in map.layout:
		var center: Vector2 = record.start
		for z: int in range(maxi(0, floori(center.y - 47)), mini(SIZE, ceili(center.y + 47))):
			for x: int in range(maxi(0, floori(center.x - 47)), mini(SIZE, ceili(center.x + 47))):
				if int(map.terrain[z][x]) == WATER or float(map.heights[z][x]) < 0.0: continue
				var distance: float = Vector2(x + .5,z + .5).distance_to(center)
				if distance < 28.0: map.heights[z][x] = 0.0
				elif distance < 35.0: map.heights[z][x] *= smoothstep(28.0, 35.0, distance)
		for harbor: Dictionary in map.harbors:
			if int(harbor.team) == int(record.team) and harbor.role == "home":
				_flatten_corridor(map, center, harbor.land_pos, 4.2)
	for mine: Dictionary in map.mines:
		if mine.get("tier") != "expansion" or int(mine.get("team", -1)) < 0: continue
		var center: Vector2 = Vector2(float(mine.pos[0]), float(mine.pos[1]))
		var start: Vector2 = map.layout[int(mine.team)].start
		_flatten_corridor(map, start, center, 3.7)
		for z: int in range(maxi(0, floori(center.y - 17)), mini(SIZE, ceili(center.y + 17))):
			for x: int in range(maxi(0, floori(center.x - 17)), mini(SIZE, ceili(center.x + 17))):
				if int(map.terrain[z][x]) == WATER or float(map.heights[z][x]) < 0.0: continue
				var distance: float = Vector2(x + .5,z + .5).distance_to(center)
				if distance < 8.0: map.heights[z][x] = 0.0
				elif distance < 17.0: map.heights[z][x] *= smoothstep(8.0, 17.0, distance)

static func _flatten_corridor(map: Dictionary, from: Vector2, to: Vector2, half_width: float) -> void:
	for z: int in range(maxi(0, floori(minf(from.y,to.y) - half_width - 6.0)), mini(SIZE, ceili(maxf(from.y,to.y) + half_width + 6.0))):
		for x: int in range(maxi(0, floori(minf(from.x,to.x) - half_width - 6.0)), mini(SIZE, ceili(maxf(from.x,to.x) + half_width + 6.0))):
			if int(map.terrain[z][x]) == WATER or float(map.heights[z][x]) < 0.0: continue
			var point: Vector2 = Vector2(x + .5,z + .5)
			var distance: float = point.distance_to(Geometry2D.get_closest_point_to_segment(point, from, to))
			if distance <= half_width: map.heights[z][x] = 0.0
			elif distance <= half_width + 6.0: map.heights[z][x] *= smoothstep(half_width, half_width + 6.0, distance)

static func _roads(map: Dictionary, mode: String, design: Dictionary) -> void:
	CITY._polyline(map, [Vector2(60, 54), Vector2(67, 95), Vector2(53, 136),
		Vector2(64, 171), Vector2(55, 211), Vector2(61, 264)], 3.0)
	CITY._polyline(map, [Vector2(259, 54), Vector2(248, 101), Vector2(267, 147),
		Vector2(251, 195), Vector2(261, 264)], 3.0)
	for index: int in design.bridges.size():
		var z: int = int(design.bridges[index])
		var center: float = _river_x(design, float(z))
		var bend: float = 6.0 if index % 2 == 0 else -6.0
		CITY._polyline(map, [Vector2(60, z + bend), Vector2(98, z - bend * .5),
			Vector2(center - 18.0, z), Vector2(center + 18.0, z),
			Vector2(214, z + bend * .5), Vector2(259, z - bend)], 3.0)
	match mode:
		"forest":
			CITY._polyline(map, [Vector2(69, 139), Vector2(87, 166), Vector2(82, 194), Vector2(108, 221)], 2.0)
			CITY._polyline(map, [Vector2(179, 104), Vector2(204, 129), Vector2(226, 157), Vector2(206, 190)], 2.1)
			CITY._polyline(map, [Vector2(62, 225), Vector2(104, 227), Vector2(160, 238), Vector2(204, 259)], 1.8)
		"desert":
			CITY._polyline(map, [Vector2(68, 123), Vector2(99, 155), Vector2(88, 192), Vector2(67, 216)], 2.5)
			CITY._polyline(map, [Vector2(204, 105), Vector2(223, 147), Vector2(196, 177), Vector2(229, 214)], 2.5)
			CITY._polyline(map, [Vector2(69, 204), Vector2(101, 221), Vector2(185, 226), Vector2(215, 252)], 2.0)
		"snow":
			CITY._polyline(map, [Vector2(68, 107), Vector2(84, 145), Vector2(75, 191), Vector2(68, 226)], 2.8)
			CITY._polyline(map, [Vector2(198, 113), Vector2(217, 148), Vector2(242, 172), Vector2(233, 229)], 2.7)
			CITY._polyline(map, [Vector2(66, 224), Vector2(87, 246), Vector2(211, 247), Vector2(238, 227)], 1.9)
	for record: Dictionary in map.layout:
		CITY._road(map, record.start, record.start + record.inward * 55.0, 3.1)
		CITY._road(map, record.start, record.start + record.outward * 29.0, 3.1)
		for mine: Dictionary in map.mines:
			if int(mine.get("team", -1)) == int(record.team) and mine.get("tier") == "expansion":
				CITY._road(map, record.start, Vector2(float(mine.pos[0]),float(mine.pos[1])), 2.6)

static func _landmark_records(mode: String) -> Array[Dictionary]:
	match mode:
		"forest": return [{"pos":Vector2(86, 171),"art":"ranger_tower"}, {"pos":Vector2(205, 130),"art":"sawmill"}, {"pos":Vector2(208, 259),"art":"forest_camp"}]
		"desert": return [{"pos":Vector2(96, 166),"art":"bazaar"}, {"pos":Vector2(194, 169),"art":"oasis_village"}, {"pos":Vector2(246, 108),"art":"mesa_gate"}, {"pos":Vector2(205, 252),"art":"dig_site"}]
		_: return [{"pos":Vector2(204, 147),"art":"bell_tower"}, {"pos":Vector2(214, 159),"art":"alpine_cabin"}, {"pos":Vector2(234, 246),"art":"freight_depot"}, {"pos":Vector2(250, 108),"art":"snow_ruin"}]

static func _landmarks(map: Dictionary, mode: String) -> void:
	for landmark: Dictionary in map.profile.landmarks:
		var art: String = str(landmark.art)
		var height: float = 14.0 if art in ["ranger_tower", "bell_tower"] else 6.0 if art in ["sawmill", "bazaar", "oasis_village", "freight_depot"] else 4.5
		CITY._house(map, landmark.pos, art, height, mode, true)
	if mode == "forest":
		for i: int in 5: CITY._prop(map, Vector2(198 + i * 3, 137), "log_stack", i % 3, 1.0)
		# One tall curtain descends at the west edge of the north stream mouth.
		# It is visual only, keeping the center of the ship channel clear.
		map.environment_props.append({"pos":Vector2(_river_x(SPEC.forest, 40.0) - float(SPEC.forest.width) + 5.0, 40.0),
			"kind":"waterfall","variant":0,"yaw":PI * .5,"scale":1.3,
			"surface_domain":"naval","height_offset":.4})
		CITY._prop(map, Vector2(111, 177), "moss_boulder", 1, 1.25)
		for point: Vector2 in [Vector2(76, 165), Vector2(79, 178), Vector2(92, 181), Vector2(98, 164), Vector2(204, 143)]:
			_scenic_house(map, point, "alpine_cabin", 4.5, "forest")
	elif mode == "desert":
		CITY._house(map, Vector2(53, 173), "mesa_gate", 4.5, "west_ruin", true)
		for i: int in 8: CITY._prop(map, Vector2(186 + (i % 4) * 5, 177 + int(i / 4) * 5), "market_tent", i % 3, 1.0)
		for point: Vector2 in [Vector2(82, 155),Vector2(88, 179),Vector2(105, 158),Vector2(109, 177),
			Vector2(184, 152),Vector2(191, 156),Vector2(203, 155),Vector2(208, 165),Vector2(185, 182),Vector2(204, 182)]:
			_scenic_house(map, point, "oasis_village" if point.x > 150 else "bazaar", 6.0, "desert")
	else:
		for i: int in 3: CITY._prop(map, Vector2(230 + i * 4, 252), "fuel_tank", i % 3, 1.0)
		CITY._prop(map, Vector2(122, 203), "snow_boulder", 1, 1.25)
		for point: Vector2 in [Vector2(192, 145),Vector2(195, 158),Vector2(203, 165),Vector2(214, 149),
			Vector2(219, 164),Vector2(226, 151),Vector2(228, 239),Vector2(242, 239)]:
			_scenic_house(map, point, "alpine_cabin" if point.y < 200 else "freight_depot", 4.5 if point.y < 200 else 6.0, "snow")

static func _scenic_house(map: Dictionary, point: Vector2, art: String, height: float, district: String) -> void:
	var cell: Vector2i = Vector2i(floori(point.x), floori(point.y))
	if cell.x < 3 or cell.y < 3 or cell.x > 316 or cell.y > 316: return
	for z: int in range(cell.y - 2, cell.y + 3):
		for x: int in range(cell.x - 2, cell.x + 3):
			if int(map.terrain[z][x]) != LAND: return
	for ruin: Dictionary in map.ruins:
		var ruin_half: Vector2 = ruin.get("half", Vector2(2.1, 2.1))
		if point.distance_to(ruin.pos) < maxf(5.3, ruin_half.length() + 2.1): return
	var id: int = map.ruins.size()
	map.ruins.append({"id":id,"kind":"house","archetype":art,"height":height,
		"district":district,"pos":point,"half":Vector2(2.1,2.1),"visual_scale":1.18,
		"yaw":float(id % 4) * PI * .5,"hp":1100.0,"max_hp":1100.0,"variant":id % 3})

static func _scenery(map: Dictionary, mode: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(map.seed) + 718102
	var regions: Array[Dictionary]
	match mode:
		"forest": regions = [
			{"center":Vector2(69, 35),"r":Vector2(55, 37),"n":660},
			{"center":Vector2(246, 39),"r":Vector2(58, 40),"n":690},
			{"center":Vector2(71, 170),"r":Vector2(62, 82),"n":900},
			{"center":Vector2(230, 177),"r":Vector2(67, 86),"n":950},
			{"center":Vector2(172, 279),"r":Vector2(136, 38),"n":760}]
		"desert": regions = [
			{"center":Vector2(146, 82),"r":Vector2(28, 65),"n":420},
			{"center":Vector2(148, 191),"r":Vector2(42, 57),"n":560},
			{"center":Vector2(148, 275),"r":Vector2(27, 40),"n":260},
			{"center":Vector2(70, 159),"r":Vector2(55, 99),"n":330},
			{"center":Vector2(246, 159),"r":Vector2(50, 101),"n":330}]
		_: regions = [
			{"center":Vector2(64, 39),"r":Vector2(51, 42),"n":520},
			{"center":Vector2(247, 35),"r":Vector2(60, 39),"n":600},
			{"center":Vector2(62, 170),"r":Vector2(54, 98),"n":690},
			{"center":Vector2(260, 165),"r":Vector2(55, 97),"n":670},
			{"center":Vector2(152, 282),"r":Vector2(133, 37),"n":690}]
	for region: Dictionary in regions:
		for i: int in int(region.n):
			var angle: float = rng.randf_range(0.0, TAU)
			var radial: float = sqrt(rng.randf())
			var point: Vector2 = region.center + Vector2(cos(angle) * region.r.x, sin(angle) * region.r.y) * radial
			if not _safe_prop(map, point): continue
			var variant: int = rng.randi_range(0, 2)
			if mode == "forest":
				CITY._add_tree(map, point, variant)
			elif mode == "desert":
				_add_environment_tree(map, point, "palm" if point.distance_to(Vector2(_river_x(SPEC.desert, point.y), point.y)) < 29.0 or rng.randf() < .13 else "cactus", variant, rng)
			else:
				_add_environment_tree(map, point, "snow_pine" if rng.randf() < .86 else "birch", variant, rng)
	# Rock groups reinforce reference ridges without turning routes into rubble.
	for i: int in (220 if mode == "desert" else 170):
		var point: Vector2 = Vector2(rng.randf_range(24, 296), rng.randf_range(23, 297))
		if not _safe_prop(map, point): continue
		if _relief(point.x, point.y, mode) < (1.5 if mode == "desert" else 2.0): continue
		CITY._prop(map, point, "sandstone" if mode == "desert" else "snow_boulder" if mode == "snow" else "moss_boulder", i % 3, rng.randf_range(.7, 1.45), rng.randf_range(0, TAU))
	if mode == "snow":
		for i: int in 175:
			var angle: float = rng.randf_range(0.0, TAU)
			var radial: float = rng.randf_range(.74, .97)
			var point: Vector2 = Vector2(145, 195) + Vector2(cos(angle) * 41.0, sin(angle) * 56.0) * radial
			if int(map.terrain[floori(point.y)][floori(point.x)]) == WATER:
				var prop: Dictionary = {"pos":point, "kind":"ice_floe", "variant":i % 3, "yaw":rng.randf_range(0, TAU), "scale":rng.randf_range(1.0, 2.0), "surface_domain":"naval", "height_offset":.05}
				map.environment_props.append(prop)

static func _ridge_spires(map: Dictionary, mode: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(map.seed) + 280417
	var art: String = "moss_spire" if mode == "forest" else "mesa_spire" if mode == "desert" else "snow_spire"
	var desired: int = 28 if mode == "forest" else 38 if mode == "desert" else 32
	var count: int = 0
	for attempt: int in 7600:
		if count >= desired: break
		var point: Vector2 = Vector2(rng.randf_range(23, 297), rng.randf_range(22, 298))
		if _relief(point.x, point.y, mode) < (1.25 if mode == "forest" else 1.55): continue
		if not _safe_prop(map, point): continue
		var id: int = map.ruins.size()
		map.ruins.append({"id":id,"kind":"house","archetype":art,"height":8.5,
			"pos":point,"half":Vector2(2.2,2.2),"yaw":rng.randf_range(0,TAU),
			"hp":2600.0,"max_hp":2600.0,"variant":count % 3})
		count += 1

static func _safe_prop(map: Dictionary, point: Vector2) -> bool:
	if point.x < 4 or point.y < 4 or point.x > 316 or point.y > 316: return false
	var c: Vector2i = Vector2i(floori(point.x), floori(point.y))
	if int(map.terrain[c.y][c.x]) != LAND: return false
	for start: Array in map.starts:
		if point.distance_to(Vector2(start[0], start[1])) < 24.0: return false
	for mine: Dictionary in map.mines:
		if point.distance_to(Vector2(mine.pos[0], mine.pos[1])) < 7.0: return false
	for harbor: Dictionary in map.harbors:
		if point.distance_to(harbor.land_pos) < 12.0 or point.distance_to(harbor.shore_pos) < 12.0: return false
	for bridge: Dictionary in map.bridges:
		var b: Array = bridge.bounds
		if point.x > float(b[0]) - 5 and point.x < float(b[0] + b[2]) + 5 and point.y > float(b[1]) - 6 and point.y < float(b[1] + b[3]) + 6: return false
	for ruin: Dictionary in map.ruins:
		if point.distance_to(ruin.pos) < (3.6 if ruin.kind == "house" else 1.25): return false
	return true

static func _add_environment_tree(map: Dictionary, point: Vector2, kind: String, variant: int, rng: RandomNumberGenerator) -> void:
	var cell: Vector2i = Vector2i(floori(point.x), floori(point.y))
	var center: Vector2 = Vector2(cell) + Vector2.ONE * .5
	var id: int = map.ruins.size()
	var size: float = rng.randf_range(1.45, 1.85) if kind in ["palm", "snow_pine", "birch"] else rng.randf_range(.9, 1.35)
	map.environment_props.append({"pos":center, "kind":kind, "variant":variant,
		"yaw":rng.randf_range(0, TAU), "scale":size, "ruin_id":id})
	map.ruins.append({"id":id, "kind":"tree", "environment_kind":kind, "pos":center,
		"half":Vector2(.48, .48), "cell":cell, "yaw":0.0, "hp":180.0, "max_hp":180.0,
		"variant":variant})
