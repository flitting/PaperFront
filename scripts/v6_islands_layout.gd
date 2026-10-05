extends RefCounted
class_name V6IslandsLayout

# A central crescent atoll, four playable home islands and eight small islets
# replace the old circular islands. All water is connected around the atoll.
const CITY = preload("res://scripts/v6_city_layout.gd")
const CATALOG = preload("res://scripts/battlefield_catalog.gd")
const SIZE := 320
const LAND := 0
const WATER := 1
const ROAD := 3
const CENTER := Vector2(160, 160)
const HOMES: Array[Vector2] = [Vector2(64.5, 64.5), Vector2(255.5, 64.5),
	Vector2(255.5, 255.5), Vector2(64.5, 255.5)]
const EXPANSIONS: Array[Vector2] = [Vector2(144.5, 64.5), Vector2(64.5, 144.5),
	Vector2(175.5, 64.5), Vector2(255.5, 144.5), Vector2(175.5, 255.5),
	Vector2(255.5, 175.5), Vector2(144.5, 255.5), Vector2(64.5, 175.5)]

static func generate(seed: int, config: Dictionary = {}) -> Dictionary:
	var players: int = clampi(int(config.get("players", 2)), 2, 4)
	var profile: Dictionary = CATALOG.profile("islands", players)
	profile.title = "远海群岛"
	profile.design_version = 6
	profile.max_height = 13.0
	profile.ground = "7d9668"
	profile.road = "a99a72"
	profile.water = "185c78"
	profile.islands = []
	var map: Dictionary = {"mode":"islands", "seed":seed, "size":SIZE, "heights":[], "terrain":[],
		"starts":[], "mines":[], "bridges":[], "decorations":[], "ruins":[],
		"environment_props":[], "civilians":[], "harbors":[], "landing_beaches":[],
		"profile":profile, "layout":[], "road_mark_cells":{}, "valid":false, "water_surface_y":-2.65}
	_starts(map, players)
	_terrain(map)
	_economy(map)
	_tracks(map)
	_landmarks(map)
	_scenery(map)
	preload("res://scripts/battlefield_ruins.gd").register_trees(map)
	var wet: int = 0
	for row: Array in map.terrain:
		for kind: int in row:
			if kind == WATER: wet += 1
	map.profile.water_fraction = float(wet) / float(SIZE * SIZE)
	return map

static func _starts(map: Dictionary, players: int) -> void:
	var active: Array[int] = []
	active.assign([0, 2] if players == 2 else [0, 1, 2] if players == 3 else [0, 1, 2, 3])
	for team: int in players:
		var corner: int = active[team]
		var start: Vector2 = HOMES[corner]
		var outward: Vector2 = (start - CENTER).normalized()
		map.starts.append([start.x, start.y])
		map.layout.append({"team":team, "corner":corner, "start":start, "outward":outward,
			"inward":-outward, "tangent":outward.orthogonal(), "near_mines":[], "expansion_mines":[]})
	for i: int in HOMES.size(): map.profile.islands.append({"center":HOMES[i],"radius":46.0,"team":active.find(i),"role":"home"})
	map.profile.islands.append({"center":CENTER,"radius":54.0,"team":-1,"role":"contested"})
	for point: Vector2 in EXPANSIONS: map.profile.islands.append({"center":point,"radius":10.0,"team":-1,"role":"expansion"})

static func _home_depth(point: Vector2, center: Vector2, index: int, seed: int) -> float:
	var offset: Vector2 = point - center
	var angle: float = offset.angle()
	var phase: float = float(index) * 1.41 + float(posmod(seed, 97)) * .006
	var radius: float = 46.0 + 3.8 * sin(angle * 3.0 + phase) + 2.6 * cos(angle * 5.0 - phase * .7) + 1.5 * sin(angle * 8.0 + phase)
	return radius - offset.length()

static func _atoll_depth(point: Vector2) -> float:
	var offset: Vector2 = point - CENTER
	var angle: float = offset.angle()
	var outer: float = 53.0 + sin(angle * 3.0) * 3.6 + cos(angle * 5.0 + .8) * 2.0
	var inner_offset: Vector2 = point - Vector2(170, 170)
	var inner: float = 21.0 + sin(inner_offset.angle() * 4.0) * 1.9
	if absf(wrapf(angle - .44, -PI, PI)) < .33 and offset.length() > 24.0: return -1.0
	return minf(outer - offset.length(), inner_offset.length() - inner)

static func _land_depth(point: Vector2, seed: int) -> float:
	var depth: float = -INF
	for i: int in HOMES.size(): depth = maxf(depth, _home_depth(point, HOMES[i], i, seed))
	depth = maxf(depth, _atoll_depth(point))
	for i: int in EXPANSIONS.size():
		var offset: Vector2 = point - EXPANSIONS[i]
		var angle: float = offset.angle()
		var radius: float = 10.0 + 1.8 * sin(angle * 3.0 + float(i)) + 1.1 * cos(angle * 5.0 - float(i))
		depth = maxf(depth, radius - offset.length())
	return depth

static func _terrain(map: Dictionary) -> void:
	for z: int in SIZE:
		var heights: Array[float] = []
		var terrain: Array[int] = []
		for x: int in SIZE:
			var point: Vector2 = Vector2(x + .5, z + .5)
			var depth: float = _land_depth(point, int(map.seed))
			terrain.append(LAND if depth >= 0.0 else WATER)
			var base: float = -2.4 + minf(depth, 4.0) * .6 if depth >= 0.0 else 0.0
			var hill: float = 0.0
			if depth >= 7.0:
				for island: int in HOMES.size():
					var peak: Vector2 = HOMES[island] + [Vector2(25,-21), Vector2(-23,-22), Vector2(-24,21), Vector2(24,23)][island]
					var home_offset: Vector2 = point - peak
					var width: float = [17.0,19.0,16.0,18.0][island]
					var summit: float = [11.5,13.0,10.5,12.0][island]
					hill = maxf(hill, summit * pow(maxf(0.0, 1.0 - home_offset.length_squared() / (width * width)), 1.35))
				var atoll_offset: Vector2 = point - Vector2(151, 141)
				hill = maxf(hill, 4.2 * pow(maxf(0.0, 1.0 - atoll_offset.length_squared() / (23.0 * 23.0)), 1.7))
			heights.append(clampf(base + hill, -2.4, 13.0))
		map.heights.append(heights)
		map.terrain.append(terrain)
	for center: Vector2 in HOMES:
		for z: int in range(int(center.y) - 16, int(center.y) + 17):
			for x: int in range(int(center.x) - 16, int(center.x) + 17):
				if int(map.terrain[z][x]) != WATER: map.heights[z][x] = 0.0

static func _coast(map: Dictionary, start: Vector2, outward: Vector2) -> Vector2:
	var last: Vector2 = start
	for step: int in 65:
		var next: Vector2 = start + outward * float(step + 1)
		if next.x < 0 or next.y < 0 or next.x >= SIZE or next.y >= SIZE: break
		if int(map.terrain[floori(next.y)][floori(next.x)]) == WATER: return last
		last = next
	return last

static func _economy(map: Dictionary) -> void:
	for record: Dictionary in map.layout:
		var team: int = int(record.team)
		var start: Vector2 = record.start
		for side: float in [-1.0, 1.0]:
			CITY._add_mine(map, start + record.inward * 10.0 + record.tangent * side * 8.0, team, "near")
		var corner: int = int(record.corner)
		for point: Vector2 in [EXPANSIONS[corner * 2], EXPANSIONS[corner * 2 + 1]]:
			CITY._add_mine(map, point, team, "expansion")
			var seaward: Vector2 = (CENTER - point).normalized()
			_add_harbor(map, team, _coast(map, point, seaward), seaward, "expansion")
		var coast: Vector2 = _coast(map, start, record.inward)
		_add_harbor(map, team, coast, record.inward, "home")
	for team: int in map.layout.size():
		var angle: float = (map.layout[team].start as Vector2).angle_to_point(CENTER) + PI
		var point: Vector2 = CENTER + Vector2.from_angle(angle) * 34.0
		CITY._add_mine(map, point, -1, "contested")

static func _add_harbor(map: Dictionary, team: int, coast: Vector2, outward: Vector2, role: String) -> void:
	var land: Vector2 = coast - outward * 9.0
	var water: Vector2 = coast + outward * 4.0
	for step: int in 5:
		var point: Vector2 = coast - outward * float(step)
		var cell: Vector2i = Vector2i(floori(point.x), floori(point.y))
		if cell.x >= 0 and cell.y >= 0 and cell.x < SIZE and cell.y < SIZE and int(map.terrain[cell.y][cell.x]) != WATER:
			map.heights[cell.y][cell.x] = -2.4 + float(step) * .6
	map.heights[floori(coast.y)][floori(coast.x)] = -2.4
	map.harbors.append({"team":team,"role":role,"land_pos":land,"water_pos":water,
		"shore_pos":coast,"outward":outward,"radius":10.0,"protected":true})
	map.landing_beaches.append({"team":team,"role":role,"land_pos":coast,"water_pos":water,
		"width":12.0,"shore_height":-2.4})

static func _tracks(map: Dictionary) -> void:
	for island: Dictionary in map.profile.islands:
		if island.role == "home":
			var center: Vector2 = island.center
			for index: int in 16:
				var a: float = float(index) * TAU / 16.0
				var b: float = float(index + 1) * TAU / 16.0
				CITY._road(map, center + Vector2.from_angle(a) * 23.0, center + Vector2.from_angle(b) * 23.0, 1.35)
			for direction: Vector2 in [Vector2.RIGHT, Vector2.DOWN]: CITY._road(map, center, center + direction * 32.0, 1.50)
		elif island.role == "contested":
			for index: int in 17:
				var a: float = float(index) * TAU / 17.0 + .25
				var b: float = float(index + 1) * TAU / 17.0 + .25
				CITY._road(map, CENTER + Vector2.from_angle(a) * 37.0, CENTER + Vector2.from_angle(b) * 37.0, 1.25)

static func _landmarks(map: Dictionary) -> void:
	for item: Dictionary in [
		{"p":Vector2(89, 45),"art":"fishing_hut","h":4.8},
		{"p":Vector2(221, 93),"art":"lighthouse","h":11.0},
		{"p":Vector2(151, 141),"art":"stone_fort","h":6.5},
		{"p":Vector2(223, 237),"art":"boat_shed","h":4.8},
		{"p":Vector2(93, 244),"art":"shipwreck","h":4.2},
	]:
		if item.art == "lighthouse": CITY._prop(map, item.p, "lighthouse", 0, 1.0)
		else: CITY._house(map, item.p, item.art, item.h, "islands", true)
	for point: Vector2 in [Vector2(99, 88), Vector2(220, 230), Vector2(194, 180), Vector2(130, 124)]:
		if int(map.terrain[floori(point.y)][floori(point.x)]) != WATER: CITY._prop(map, point, "pier", 0, 1.0)
	for point: Vector2 in [Vector2(82, 44),Vector2(94, 48),Vector2(83, 55),Vector2(96, 61)]:
		_scenic_house(map, point, "fishing_hut", 4.8)
	for point: Vector2 in [Vector2(210, 236),Vector2(219, 247),Vector2(231, 229)]:
		_scenic_house(map, point, "boat_shed", 4.8)
	for harbor: Dictionary in map.harbors:
		if harbor.role != "home": continue
		CITY._prop(map, harbor.shore_pos, "pier", int(harbor.team) % 3, 1.0, harbor.outward.angle())
		map.environment_props.append({"pos":harbor.water_pos + harbor.outward * 4.0,
			"kind":"boat","variant":int(harbor.team) % 3,"yaw":harbor.outward.angle(),
			"scale":1.0,"surface_domain":"naval","height_offset":.03})

static func _safe_prop(map: Dictionary, point: Vector2, size: float = .7) -> bool:
	if point.x < 4 or point.y < 4 or point.x > 316 or point.y > 316: return false
	var c: Vector2i = Vector2i(floori(point.x), floori(point.y))
	if int(map.terrain[c.y][c.x]) != LAND: return false
	for start: Array in map.starts:
		if point.distance_to(Vector2(start[0], start[1])) < 23.0: return false
	for mine: Dictionary in map.mines:
		if point.distance_to(Vector2(mine.pos[0], mine.pos[1])) < 6.0: return false
	for harbor: Dictionary in map.harbors:
		if point.distance_to(harbor.land_pos) < 12.0 or point.distance_to(harbor.shore_pos) < 12.0: return false
	for ruin: Dictionary in map.ruins:
		if point.distance_to(ruin.pos) < (3.5 if ruin.kind == "house" else size + .6): return false
	return true

static func _scenery(map: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(map.seed) + 741580
	for island: Dictionary in map.profile.islands:
		var count: int = 360 if island.role == "home" else 460 if island.role == "contested" else 55
		for i: int in count:
			var angle: float = rng.randf_range(0, TAU)
			var distance: float = sqrt(rng.randf()) * float(island.radius)
			var point: Vector2 = island.center + Vector2.from_angle(angle) * distance
			if not _safe_prop(map, point): continue
			var cell: Vector2i = Vector2i(floori(point.x), floori(point.y))
			var center: Vector2 = Vector2(cell) + Vector2.ONE * .5
			var id: int = map.ruins.size()
			map.environment_props.append({"pos":center,"kind":"palm","variant":i % 3,
				"yaw":rng.randf_range(0,TAU),"scale":rng.randf_range(1.25,1.8),"ruin_id":id})
			map.ruins.append({"id":id,"kind":"tree","environment_kind":"palm","pos":center,
				"half":Vector2(.48,.48),"cell":cell,"yaw":0.0,"hp":180.0,"max_hp":180.0,"variant":i % 3})
	for i: int in 220:
		var point: Vector2 = Vector2(rng.randf_range(9,311),rng.randf_range(9,311))
		if _safe_prop(map,point): CITY._prop(map,point,"coastal_rock",i % 3,rng.randf_range(.7,1.5),rng.randf_range(0,TAU))
	for i: int in 42:
		var point: Vector2 = Vector2(rng.randf_range(10,310),rng.randf_range(10,310))
		if int(map.terrain[floori(point.y)][floori(point.x)]) != WATER: continue
		map.environment_props.append({"pos":point,"kind":"buoy" if i % 3 == 0 else "sea_rock",
			"variant":i % 3,"yaw":rng.randf_range(0,TAU),"scale":rng.randf_range(.7,1.3),
			"surface_domain":"naval","height_offset":.03})
	for point: Vector2 in [Vector2(166, 173), Vector2(146, 211), Vector2(107, 96), Vector2(228, 215)]:
		if int(map.terrain[floori(point.y)][floori(point.x)]) == WATER:
			map.environment_props.append({"pos":point,"kind":"boat","variant":rng.randi_range(0,2),
				"yaw":rng.randf_range(0,TAU),"scale":1.0,"surface_domain":"naval","height_offset":.03})

static func _scenic_house(map: Dictionary, point: Vector2, art: String, height: float) -> void:
	var cell: Vector2i = Vector2i(floori(point.x), floori(point.y))
	if cell.x < 3 or cell.y < 3 or cell.x > 316 or cell.y > 316: return
	for z: int in range(cell.y - 2, cell.y + 3):
		for x: int in range(cell.x - 2, cell.x + 3):
			if int(map.terrain[z][x]) != LAND: return
	for ruin: Dictionary in map.ruins:
		if point.distance_to(ruin.pos) < 5.5: return
	var id: int = map.ruins.size()
	map.ruins.append({"id":id,"kind":"house","archetype":art,"height":height,
		"pos":point,"half":Vector2(2.1,2.1),"yaw":float(id % 4) * PI * .5,
		"hp":1100.0,"max_hp":1100.0,"variant":id % 3})
