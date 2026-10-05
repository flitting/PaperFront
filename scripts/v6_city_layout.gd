extends RefCounted
class_name V6CityLayout

# Authored from the paired city design references in assets/map_design_v6.
# The four districts share one topology across player counts; only active
# corner pads, resource records and their protected harbours change.
const CATALOG = preload("res://scripts/battlefield_catalog.gd")
const SIZE := 320
const LAND := 0
const WATER := 1
const ROAD := 3
const BRIDGES: Array[int] = [55, 95, 140, 190]
const DISTRICTS: Array[Dictionary] = [
	{"id":"old_town", "center":Vector2(91, 119), "radius":Vector2(61, 69), "style":"terracotta"},
	{"id":"modern", "center":Vector2(207, 119), "radius":Vector2(49, 65), "style":"slate"},
	{"id":"north_residential", "center":Vector2(204, 43), "radius":Vector2(52, 25), "style":"rowhouse"},
	{"id":"southwest_suburb", "center":Vector2(77, 213), "radius":Vector2(47, 39), "style":"terrace"},
	{"id":"civic_park", "center":Vector2(190, 184), "radius":Vector2(31, 34), "style":"garden"},
	{"id":"freight_port", "center":Vector2(246, 215), "radius":Vector2(41, 43), "style":"industrial"},
]

static func generate(seed: int, config: Dictionary = {}) -> Dictionary:
	var players: int = clampi(int(config.get("players", 2)), 2, 4)
	var profile: Dictionary = CATALOG.profile("city", players)
	profile.title = "纸城河港"
	profile.design_version = 6
	profile.ground = "7d8b72"
	profile.road = "646d69"
	profile.water = "194b66"
	profile.street_spacing = 0
	profile.street_origin = 0
	profile.districts = DISTRICTS.duplicate(true)
	var map: Dictionary = {"mode":"city", "seed":seed, "size":SIZE, "heights":[], "terrain":[],
		"starts":[], "mines":[], "bridges":[], "decorations":[], "ruins":[],
		"environment_props":[], "civilians":[], "harbors":[], "landing_beaches":[],
		"profile":profile, "layout":[], "road_mark_cells":{}, "valid":false, "water_surface_y":-2.65}
	_starts(map, players)
	_terrain(map)
	_bridges(map)
	_economy(map)
	_roads(map)
	_landmarks(map)
	_port_district(map)
	_neighborhoods(map)
	_densify(map)
	_park_and_coast(map)
	preload("res://scripts/battlefield_ruins.gd").register_trees(map)
	var wet: int = 0
	for row: Array in map.terrain:
		for kind: int in row:
			if kind == WATER: wet += 1
	map.profile.water_fraction = float(wet) / float(SIZE * SIZE)
	return map

static func _starts(map: Dictionary, players: int) -> void:
	var corners: Array[Vector2] = [Vector2(58.5, 58.5), Vector2(261.5, 58.5),
		Vector2(261.5, 261.5), Vector2(58.5, 261.5)]
	var active: Array[int] = []
	active.assign([0, 2] if players == 2 else [0, 1, 2] if players == 3 else [0, 1, 2, 3])
	for team: int in players:
		var corner: int = active[team]
		var start: Vector2 = corners[corner]
		var outward: Vector2 = Vector2.UP if corner in [0, 1] else Vector2.DOWN
		var inward: Vector2 = -outward
		map.starts.append([start.x, start.y])
		map.layout.append({"team":team, "start":start, "outward":outward,
			"inward":inward, "tangent":Vector2.RIGHT, "near_mines":[], "expansion_mines":[]})

static func _river_x(z: float) -> float:
	var anchors: Array[Vector2] = [Vector2(137, 0), Vector2(137, 42), Vector2(130, 78),
		Vector2(140, 121), Vector2(134, 165), Vector2(144, 205), Vector2(147, 250), Vector2(151, 320)]
	for i: int in range(anchors.size() - 1):
		if z <= anchors[i + 1].y:
			var t: float = clampf((z - anchors[i].y) / (anchors[i + 1].y - anchors[i].y), 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)
			return lerpf(anchors[i].x, anchors[i + 1].x, t)
	return 151.0

static func _inside_city(x: float, z: float) -> bool:
	var west: float = 20.5 + sin(z * .039) * 3.1 + sin(z * .115 + 1.2) * 1.9
	var east: float = 299.5 + sin(z * .043 + .6) * 3.3 + sin(z * .109) * 1.8
	var north: float = 19.5 + sin(x * .047 + .4) * 4.1 + sin(x * .13) * 1.4
	var south: float = 300.0 + sin(x * .047 + 1.3) * 4.4 + sin(x * .118) * 1.9
	return x >= west and x <= east and z >= north and z <= south

static func _water(x: float, z: float) -> bool:
	if not _inside_city(x, z): return true
	var river_half: float = 7.8 + sin(z * .079) * 1.1
	if z > 202.0: river_half += minf(29.0, (z - 202.0) * .35)
	if absf(x - _river_x(z)) <= river_half: return true
	# An east-bank freight basin branches from the river into the port. Its
	# twenty-metre throat and open southern sea let the largest ship turn.
	var basin: Vector2 = Vector2((x - 217.0) / 29.0, (z - 229.0) / 22.0)
	if basin.length_squared() <= 1.0: return true
	var branch_a: Vector2 = Vector2(159, 216)
	var branch_b: Vector2 = Vector2(211, 229)
	if z > 204.0 and z < 246.0 and Vector2(x, z).distance_to(Geometry2D.get_closest_point_to_segment(Vector2(x, z), branch_a, branch_b)) <= 9.5: return true
	return false

static func _terrain(map: Dictionary) -> void:
	var queue: Array[Vector2i] = []
	var distance := PackedInt32Array()
	distance.resize(SIZE * SIZE)
	distance.fill(999)
	for z: int in SIZE:
		var heights: Array[float] = []
		var terrain: Array[int] = []
		for x: int in SIZE:
			var water: bool = _water(x + .5, z + .5)
			terrain.append(WATER if water else LAND)
			heights.append(0.0)
			if water:
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
			if int(map.terrain[z][x]) != WATER:
				map.heights[z][x] = -0.6 * float(maxi(0, 5 - distance[z * SIZE + x]))
	# The reference keeps all four corner construction aprons broad and level.
	for center: Vector2 in [Vector2(58.5, 58.5), Vector2(261.5, 58.5),
		Vector2(261.5, 261.5), Vector2(58.5, 261.5)]:
		for z in range(int(center.y) - 16, int(center.y) + 17):
			for x in range(int(center.x) - 16, int(center.x) + 17):
				if int(map.terrain[z][x]) != WATER: map.heights[z][x] = 0.0

static func _bridges(map: Dictionary) -> void:
	for i: int in BRIDGES.size():
		var z: int = BRIDGES[i]
		var center: float = _river_x(float(z))
		var left: int = floori(center - 12.0)
		var width: int = 25
		map.bridges.append({"id":i + 1, "bounds":[left, z - 4, width, 9],
			"heads":[[float(left) - 2.5, z + .5], [float(left + width) + 2.5, z + .5]],
			"naval_clearance":2.5, "style":"stone_arch"})
		# The bridge deck is at level zero. Raise its immediate bank approaches
		# so the first land sample meets the deck without a 2.4 m beach cliff.
		for row: int in range(z - 5, z + 6):
			for col: int in range(left - 5, left + width + 5):
				if col >= 0 and row >= 0 and col < SIZE and row < SIZE and int(map.terrain[row][col]) != WATER:
					map.heights[row][col] = 0.0

static func _economy(map: Dictionary) -> void:
	for record: Dictionary in map.layout:
		var team: int = int(record.team)
		var start: Vector2 = record.start
		var inward: Vector2 = record.inward
		for side: float in [-1.0, 1.0]:
			_add_mine(map, start + inward * 10.0 + Vector2(side * 8.0, 0), team, "near")
		for side: float in [-1.0, 1.0]:
			_add_mine(map, start + inward * 51.0 + Vector2(side * 20.0, 0), team, "expansion")
		var coast: Vector2 = _coast(map, start, record.outward)
		_add_harbor(map, team, coast, record.outward)
	var contested: Array[Vector2] = [Vector2(111.5, 84.5), Vector2(181.5, 79.5),
		Vector2(180.5, 223.5), Vector2(111.5, 223.5)]
	for team: int in map.layout.size(): _add_mine(map, contested[team], -1, "contested")

static func _add_mine(map: Dictionary, pos: Vector2, team: int, tier: String) -> void:
	var id: int = map.mines.size()
	map.mines.append({"pos":[pos.x, pos.y], "capacity":4000 if tier == "near" else 6000,
		"team":team, "tier":tier})
	if team >= 0: map.layout[team]["near_mines" if tier == "near" else "expansion_mines"].append(id)

static func _coast(map: Dictionary, start: Vector2, outward: Vector2) -> Vector2:
	var last: Vector2 = start
	for step in 65:
		var next: Vector2 = start + outward * float(step + 1)
		if int(map.terrain[floori(next.y)][floori(next.x)]) == WATER: return last
		last = next
	return last

static func _add_harbor(map: Dictionary, team: int, coast: Vector2, outward: Vector2) -> void:
	var land: Vector2 = coast - outward * 9.0
	var water: Vector2 = coast + outward * 4.0
	map.harbors.append({"team":team, "role":"home", "land_pos":land, "water_pos":water,
		"shore_pos":coast, "outward":outward, "radius":10.0, "protected":true})
	map.landing_beaches.append({"team":team, "role":"home", "land_pos":coast,
		"water_pos":water, "width":12.0, "shore_height":-2.4})

static func _road(map: Dictionary, from: Vector2, to: Vector2, half_width: float) -> void:
	var low: Vector2i = Vector2i(maxi(0, floori(minf(from.x, to.x) - half_width)), maxi(0, floori(minf(from.y, to.y) - half_width)))
	var high: Vector2i = Vector2i(mini(SIZE, ceili(maxf(from.x, to.x) + half_width)), mini(SIZE, ceili(maxf(from.y, to.y) + half_width)))
	for z: int in range(low.y, high.y):
		for x: int in range(low.x, high.x):
			if int(map.terrain[z][x]) != LAND: continue
			var distance: float = Vector2(x + .5, z + .5).distance_to(Geometry2D.get_closest_point_to_segment(Vector2(x + .5, z + .5), from, to))
			if distance <= half_width:
				map.terrain[z][x] = ROAD
				if distance < .45 and (x + z) % 5 < 3:
					map.road_mark_cells[Vector2i(x, z)] = "h" if absf(to.x - from.x) >= absf(to.y - from.y) else "v"

static func _polyline(map: Dictionary, points: Array[Vector2], half_width: float) -> void:
	for index: int in range(points.size() - 1): _road(map, points[index], points[index + 1], half_width)

static func _roads(map: Dictionary) -> void:
	# The coastal loop is bent by districts and the freight port. It is neither
	# a regular grid nor a set of equal radial spokes.
	_polyline(map, [Vector2(54, 51), Vector2(43, 81), Vector2(45, 153), Vector2(54, 192),
		Vector2(47, 247), Vector2(61, 271), Vector2(99, 250)], 3.0)
	_polyline(map, [Vector2(260, 50), Vector2(276, 79), Vector2(279, 131), Vector2(269, 174),
		Vector2(279, 213), Vector2(271, 261)], 3.2)
	_polyline(map, [Vector2(55, 55), Vector2(88, 50), Vector2(116, 55),
		Vector2(158, 55), Vector2(207, 55), Vector2(261, 55)], 3.0)
	_polyline(map, [Vector2(57, 262), Vector2(87, 244), Vector2(114, 207), Vector2(146, 190)], 3.3)
	_polyline(map, [Vector2(224, 228), Vector2(261, 261)], 3.3)
	for z: int in BRIDGES:
		if z == 190:
			_polyline(map, [Vector2(44, z), Vector2(104, z + 2), Vector2(120, z),
				Vector2(153, z), Vector2(165, 153), Vector2(226, 151), Vector2(266, z + 4)], 3.6)
		else:
			_polyline(map, [Vector2(44, z), Vector2(104, z + 2), Vector2(120, z),
				Vector2(153, z), Vector2(196, z - 1), Vector2(266, z + 4)], 3.6 if z == 55 else 2.9)
	_polyline(map, [Vector2(73, 75), Vector2(86, 109), Vector2(105, 145), Vector2(113, 181), Vector2(86, 216)], 2.4)
	_polyline(map, [Vector2(171, 62), Vector2(215, 83), Vector2(243, 108), Vector2(236, 150), Vector2(234, 190), Vector2(235, 215)], 3.3)
	_polyline(map, [Vector2(72, 195), Vector2(98, 205), Vector2(109, 231), Vector2(78, 245), Vector2(48, 230)], 2.3)
	# Freight rail and quay paths are visually modelled, while the underlying
	# service lane remains navigable to ground units.
	_polyline(map, [Vector2(263, 76), Vector2(275, 108), Vector2(275, 151),
		Vector2(270, 183), Vector2(277, 211), Vector2(269, 249)], 2.8)
	for record: Dictionary in map.layout:
		var start: Vector2 = record.start
		_road(map, start, record.start + record.inward * 58.0, 3.2)
		_road(map, start, record.start + record.outward * 28.0, 3.2)

static func _landmarks(map: Dictionary) -> void:
	for landmark: Dictionary in [
		{"pos":Vector2(96.5, 111.5), "art":"church", "height":13.8, "district":"old_town"},
		{"pos":Vector2(88.5, 98.5), "art":"clock_tower", "height":18.5, "district":"old_town"},
		{"pos":Vector2(188.5, 127.5), "art":"civic_hall", "height":10.5, "district":"modern"},
		{"pos":Vector2(232.5, 112.5), "art":"office_tower", "height":20.0, "district":"modern"},
		{"pos":Vector2(258.5, 145.5), "art":"rail_station", "height":6.8, "district":"freight_port"},
		{"pos":Vector2(243.5, 215.5), "art":"freight_shed", "height":5.4, "district":"freight_port"},
		{"pos":Vector2(91.5, 205.5), "art":"terrace", "height":4.8, "district":"southwest_suburb"},
	]: _house(map, landmark.pos, str(landmark.art), float(landmark.height), str(landmark.district), true)
	for point: Vector2 in [Vector2(190.5, 183.5), Vector2(193.5, 39.5)]:
		_prop(map, point, "fountain", 0, 1.0)
	for point: Vector2 in [Vector2(71.5, 25.5), Vector2(254.5, 27.5),
		Vector2(222.5, 282.5)]: _prop(map, point, "lighthouse", 0, 1.0)
	for point: Vector2 in [Vector2(250, 221), Vector2(254, 233), Vector2(249, 240)]: _prop(map, point, "harbor_crane", 0, 1.0)
	for point: Vector2 in [Vector2(250, 227), Vector2(256, 228), Vector2(262, 228), Vector2(251, 241), Vector2(258, 242)]: _prop(map, point, "cargo_stack", int(point.x) % 3, 1.0)
	for point: Vector2 in [Vector2(251, 197), Vector2(264, 207), Vector2(249, 216)]:
		_house(map, point, "freight_shed", 5.4, "freight_port", true)
	for point: Vector2 in [Vector2(140, 76), Vector2(137, 119), Vector2(144, 167), Vector2(154, 218), Vector2(218, 229)]:
		if int(map.terrain[floori(point.y)][floori(point.x)]) == WATER:
			map.environment_props.append({"pos":point,"kind":"boat","variant":int(point.y) % 3,
				"yaw":PI * .5,"scale":1.0,"surface_domain":"naval","height_offset":.04})
	for i: int in 20:
		var angle: float = -PI * .48 + float(i) * PI * .95 / 19.0
		var point: Vector2 = Vector2(217 + cos(angle) * 30.5, 229 + sin(angle) * 23.5)
		if int(map.terrain[floori(point.y)][floori(point.x)]) != WATER:
			_prop(map, point, "quay_wall", i % 3, 1.0, angle + PI * .5)

static func _port_district(map: Dictionary) -> void:
	# A straight southern working quay gives the basin an industrial edge.
	for z: int in range(212, 247, 3):
		var point := Vector2(246.5, float(z) + .5)
		if int(map.terrain[z][246]) != WATER:
			_prop(map, point, "quay_wall", z % 3, 1.35, PI * .5)
	for point: Vector2 in [Vector2(255, 187), Vector2(265, 190), Vector2(270, 201), Vector2(271, 217), Vector2(269, 235)]:
		_house(map, point, "warehouse", 4.2, "freight_port", true)
	for z: int in range(185, 243, 2):
		for x: int in [280, 284]:
			if int(map.terrain[z][x]) != WATER:
				_prop(map, Vector2(x + .5, z + .5), "rail_track", 0, 1.0, PI * .5)
	for point: Vector2 in [Vector2(253, 207), Vector2(258, 212), Vector2(262, 220), Vector2(265, 227)]:
		if int(map.terrain[floori(point.y)][floori(point.x)]) != WATER:
			_prop(map, point, "cargo_stack", int(point.x) % 3, 1.7)

static func _house(map: Dictionary, pos: Vector2, art: String, height: float, district: String, force: bool = false) -> bool:
	if not force and not _safe(map, pos, 2.15): return false
	if force:
		for z: int in range(floori(pos.y - 2), ceili(pos.y + 2)):
			for x: int in range(floori(pos.x - 2), ceili(pos.x + 2)):
				if x < 0 or z < 0 or x >= SIZE or z >= SIZE or int(map.terrain[z][x]) == WATER: return false
				map.terrain[z][x] = LAND
	var id: int = map.ruins.size()
	var variant: int = posmod(id * 7 + int(map.seed), 3)
	var scale: float = 1.85 if art == "stone_fort" else 1.42 if art in ["church", "rail_station", "sawmill", "bazaar", "oasis_village", "freight_depot"] else 1.18 if art in ["clock_tower", "ranger_tower", "bell_tower"] else 1.0
	var half: Vector2 = Vector2(10.5, 10.5) if art == "stone_fort" else Vector2(7.3, 7.3) if art == "bell_tower" else Vector2(6.5, 6.5) if art == "sawmill" else Vector2(6.8, 6.8) if art == "mesa_gate" else Vector2(5.5, 5.5) if art == "oasis_village" else Vector2(4.05, 4.05) if art == "civic_hall" else Vector2(2.1, 2.1) * scale
	var ruin: Dictionary = {"id":id, "kind":"house", "archetype":art, "height":height,
		"district":district, "pos":pos, "half":half, "visual_scale":scale,
		"yaw":0.0 if art == "stone_fort" else PI if art in ["civic_hall", "church", "clock_tower", "rail_station"] else float(variant) * PI * .5,
		"hp":1500.0 if art in ["civic_hall", "church", "clock_tower"] else 1100.0,
		"max_hp":1500.0 if art in ["civic_hall", "church", "clock_tower"] else 1100.0,
		"variant":variant}
	if art == "civic_hall":
		ruin.visual_scale_xz = 2.08
		ruin.visual_scale_y = 1.20
	map.ruins.append(ruin)
	return true

static func _safe(map: Dictionary, pos: Vector2, radius: float) -> bool:
	if pos.x < radius + 5 or pos.y < radius + 5 or pos.x > SIZE - radius - 5 or pos.y > SIZE - radius - 5: return false
	var park: Vector2 = Vector2(129, 220) if str(map.mode) == "random_city" else Vector2(190, 184)
	var park_radius: Vector2 = Vector2(43, 33) if str(map.mode) == "random_city" else Vector2(33, 36)
	if pow((pos.x - park.x) / park_radius.x, 2) + pow((pos.y - park.y) / park_radius.y, 2) < 1.0: return false
	for start: Array in map.starts:
		if pos.distance_to(Vector2(start[0], start[1])) < 23.0 + radius: return false
	for mine: Dictionary in map.mines:
		if pos.distance_to(Vector2(mine.pos[0], mine.pos[1])) < 6.0 + radius: return false
	for harbor: Dictionary in map.harbors:
		if pos.distance_to(harbor.land_pos) < 10.0 + radius or pos.distance_to(harbor.shore_pos) < 10.0 + radius: return false
	for ruin: Dictionary in map.ruins:
		var clearance: float = 11.0 if ruin.get("archetype", "") in ["church", "clock_tower", "civic_hall", "rail_station"] else maxf(4.5, radius + 2.2) if ruin.kind == "house" else radius + .8
		if pos.distance_to(ruin.pos) < clearance: return false
	for z: int in range(floori(pos.y - radius), ceili(pos.y + radius) + 1):
		for x: int in range(floori(pos.x - radius), ceili(pos.x + radius) + 1):
			if int(map.terrain[z][x]) != LAND or not is_zero_approx(float(map.heights[z][x])): return false
	return true

static func _neighborhoods(map: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(map.seed) + 120104
	for z: int in range(66, 186, 5):
		for x: int in range(44, 119, 5):
			var point: Vector2 = Vector2(float(x) + sin(float(z) * .12) * 2.1 + rng.randf_range(-.8, .8), float(z) + rng.randf_range(-1.1, 1.1))
			if rng.randf() > .91: continue
			_house(map, point, "old_townhouse" if rng.randf() > .22 else "old_shop", 5.1, "old_town")
	for z: int in range(66, 181, 6):
		for x: int in range(167, 252, 6):
			var point: Vector2 = Vector2(float(x) + rng.randf_range(-1.4, 1.4), float(z) + rng.randf_range(-1.3, 1.3))
			if rng.randf() > .85: continue
			var roll: float = rng.randf()
			var archetype: String = "office_tower" if roll < .31 else "modern_block" if roll < .75 else "modern_shop"
			var height: float = 17.0 if archetype == "office_tower" else 9.5 if archetype == "modern_block" else 5.9
			_house(map, point, archetype, height, "modern")
	for zone: Dictionary in [
		{"from":Vector2i(166, 28), "to":Vector2i(248, 72), "spacing":6, "art":"rowhouse", "height":5.1, "name":"north_residential"},
		{"from":Vector2i(46, 185), "to":Vector2i(116, 247), "spacing":7, "art":"terrace", "height":4.8, "name":"southwest_suburb"},
		{"from":Vector2i(225, 180), "to":Vector2i(277, 247), "spacing":7, "art":"warehouse", "height":4.2, "name":"freight_port"},
	]:
		for z: int in range(zone.from.y, zone.to.y, zone.spacing):
			for x: int in range(zone.from.x, zone.to.x, zone.spacing):
				if rng.randf() > .83: continue
				_house(map, Vector2(x, z) + Vector2(rng.randf_range(-1.2, 1.2), rng.randf_range(-1.2, 1.2)), zone.art, zone.height, zone.name)
	# Lamps, benches and walkers follow district roads without becoming
	# invisible path blockers.
	for z: int in range(45, 251, 17):
		for x: int in range(49, 276, 19):
			var point: Vector2 = Vector2(x + .5, z + .5)
			if not _roadside(map, point): continue
			_prop(map, point, "streetlamp", posmod(x + z, 3), 1.0)
			if (x + z) % 4 == 0: _prop(map, point + Vector2(2.1, 0), "bench", posmod(x, 3), 1.0)
			if (x + z) % 5 == 0:
				map.civilians.append({"id":map.civilians.size(), "route":[point, point + Vector2(7, 0), point + Vector2(7, 5), point + Vector2(0, 5)],
					"speed":.55 + rng.randf() * .2, "phase":rng.randf_range(0, 20), "variant":posmod(x + z, 3)})
	for z: int in [55, 95, 140, 190]:
		for x: int in [64, 85, 184, 209, 238]:
			var point: Vector2 = Vector2(x + .5, z + .5)
			if int(map.terrain[floori(point.y)][floori(point.x)]) == WATER: continue
			map.civilians.append({"id":map.civilians.size(),
				"route":[point, point + Vector2(3.5, 0), point + Vector2(3.5, 1.2), point + Vector2(0, 1.2)],
				"speed":.54 + rng.randf() * .18, "phase":rng.randf_range(0, 20), "variant":posmod(x + z, 3)})

static func _roadside(map: Dictionary, point: Vector2) -> bool:
	if not _safe(map, point, .35): return false
	for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var cell: Vector2i = Vector2i(floori(point.x), floori(point.y)) + direction * 2
		if cell.x >= 0 and cell.y >= 0 and cell.x < SIZE and cell.y < SIZE and int(map.terrain[cell.y][cell.x]) == ROAD: return true
	return false

static func _densify(map: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(map.seed) + 731842
	for zone: Dictionary in [
		{"from":Vector2i(43, 57), "to":Vector2i(123, 185), "step":4.65, "district":"old_town", "chance":.68},
		{"from":Vector2i(163, 60), "to":Vector2i(259, 190), "step":5.40, "district":"modern", "chance":.66},
		{"from":Vector2i(163, 27), "to":Vector2i(250, 67), "step":5.4, "district":"north_residential", "chance":.73},
		{"from":Vector2i(48, 184), "to":Vector2i(119, 248), "step":5.7, "district":"southwest_suburb", "chance":.60},
	]:
		var row: int = 0
		var z: float = float(zone.from.y)
		while z < float(zone.to.y):
			var x: float = float(zone.from.x) + (2.25 if row % 2 == 1 else 0.0)
			while x < float(zone.to.x):
				if rng.randf() < float(zone.chance):
					var point: Vector2 = Vector2(x + rng.randf_range(-.45,.45), z + rng.randf_range(-.45,.45))
					var district: String = str(zone.district)
					var art: String = "old_townhouse" if district == "old_town" else "modern_block" if district == "modern" else "rowhouse" if district == "north_residential" else "terrace"
					var height: float = 5.1 if district in ["old_town", "north_residential"] else 9.5 if district == "modern" else 4.8
					_house(map, point, art, height, district)
				x += float(zone.step)
			z += float(zone.step)
			row += 1

static func _park_and_coast(map: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(map.seed) + 543219
	for i: int in 370:
		var angle: float = rng.randf_range(0.0, TAU)
		var r: float = sqrt(rng.randf())
		var point: Vector2 = Vector2(190, 184) + Vector2(cos(angle) * 29.0, sin(angle) * 31.0) * r
		if point.distance_to(Vector2(190, 184)) < 8.0 or not _tree_safe(map, point): continue
		_add_tree(map, point, i % 3)
	for zone: Dictionary in [
		{"center":Vector2(49, 135), "radius":Vector2(23, 65), "count":430},
		{"center":Vector2(281, 101), "radius":Vector2(21, 61), "count":350},
		{"center":Vector2(57, 223), "radius":Vector2(27, 49), "count":380},
		{"center":Vector2(247, 39), "radius":Vector2(39, 23), "count":260},
		{"center":Vector2(88, 38), "radius":Vector2(35, 22), "count":190},
	]:
		for i: int in zone.count:
			var angle: float = rng.randf_range(0.0, TAU)
			var radial: float = sqrt(rng.randf())
			var point: Vector2 = zone.center + Vector2(cos(angle) * zone.radius.x, sin(angle) * zone.radius.y) * radial
			if _tree_safe(map, point): _add_tree(map, point, i % 3)
	# The rail line traces the eastern edge in the reference panorama.
	var railway: Array[Vector2] = [Vector2(266, 70), Vector2(279, 106), Vector2(281, 151),
		Vector2(272, 180), Vector2(279, 210), Vector2(273, 245)]
	for segment: int in range(railway.size() - 1):
		var length: float = railway[segment].distance_to(railway[segment + 1])
		for index: int in ceili(length / 1.8):
			var t: float = float(index) * 1.8 / length
			var point: Vector2 = railway[segment].lerp(railway[segment + 1], t)
			if int(map.terrain[floori(point.y)][floori(point.x)]) == WATER: continue
			_prop(map, point, "rail_track", 0, 1.0, (railway[segment + 1] - railway[segment]).angle())

static func _add_tree(map: Dictionary, point: Vector2, variant: int) -> void:
	var cell: Vector2i = Vector2i(floori(point.x), floori(point.y))
	map.decorations.append({"pos":[float(cell.x) + .5, float(cell.y) + .5], "kind":"tree", "variant":variant})

static func _tree_safe(map: Dictionary, point: Vector2) -> bool:
	if point.x < 5.0 or point.y < 5.0 or point.x > 315.0 or point.y > 315.0: return false
	var cell: Vector2i = Vector2i(floori(point.x), floori(point.y))
	if int(map.terrain[cell.y][cell.x]) != LAND or not is_zero_approx(float(map.heights[cell.y][cell.x])): return false
	for start: Array in map.starts:
		if point.distance_to(Vector2(start[0], start[1])) < 24.0: return false
	for mine: Dictionary in map.mines:
		if point.distance_to(Vector2(mine.pos[0], mine.pos[1])) < 6.0: return false
	for harbor: Dictionary in map.harbors:
		if point.distance_to(harbor.land_pos) < 12.0 or point.distance_to(harbor.shore_pos) < 12.0: return false
	for ruin: Dictionary in map.ruins:
		if point.distance_to(ruin.pos) < (3.2 if ruin.kind == "house" else 1.45): return false
	return true

static func _prop(map: Dictionary, point: Vector2, kind: String, variant: int, scale: float, yaw: float = 0.0) -> void:
	map.environment_props.append({"pos":point, "kind":kind, "variant":variant, "yaw":yaw, "scale":scale})
