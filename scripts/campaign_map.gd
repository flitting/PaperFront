extends RefCounted
class_name CampaignMap

## The single canonical mission is authored in world coordinates. Its river,
## industry, residential blocks and approaches are deliberately asymmetric.
const SIZE := 320
const LAND := 0
const WATER := 1
const ROAD := 3
const LAYOUT = preload("res://scripts/competitive_layout.gd")

const PLAYER_START := Vector2(62.5, 170.5)
const ENEMY_START := Vector2(262.5, 169.5)
const WEST_BRIDGE := Vector2(147.5, 160.5)
const EAST_BRIDGE := Vector2(174.5, 160.5)
const EXPANSION := Vector2(199.5, 120.5)
const EAST_ASSEMBLY := Vector2(219.5, 162.5)

static func generate(seed: int = 1) -> Dictionary:
	var map: Dictionary = {
		"mode": "campaign", "seed": seed, "size": SIZE,
		"heights": [], "terrain": [],
		"starts": [[PLAYER_START.x, PLAYER_START.y], [ENEMY_START.x, ENEMY_START.y]],
		"mines": [], "bridges": [], "decorations": [], "ruins": [],
		"environment_props": [], "civilians": [], "harbors": [], "landing_beaches": [],
		"layout": [], "water_surface_y": -2.65,
		"profile": {"schema": 4, "id": "campaign", "title": "无字桥补给线", "biome": "city",
			"size": SIZE, "players": 2, "routes": "campaign", "ground": "a6aa90",
			"road": "858a80", "water": "4b8392", "street_spacing": 24, "street_origin": 11}
	}
	for z: int in SIZE:
		var heights: Array[float] = []
		var terrain: Array[int] = []
		for x: int in SIZE:
			var river_center: float = 160.0 + sin(float(z) * 0.026) * 2.5
			if z >= 153 and z <= 167: river_center = 160.0
			var half_width: float = 7.5 + sin(float(z) * 0.042 + 1.8) * 1.4
			if z >= 153 and z <= 167: half_width = 8.0
			var is_river: bool = z <= 270 and absf(float(x) + .5 - river_center) < half_width
			terrain.append(WATER if is_river else LAND)
			# Two stepped wooded rises frame the northern skyline. Slopes change
			# by at most half a metre per cell and never touch mission pads.
			var eastern_rise: float = minf((float(x) - (244.0 + float(z) * .32)) * .25, (96.0 - float(z)) * .08)
			var western_rise: float = minf((28.0 - float(x)) * .25, (77.0 - float(z)) * .07)
			heights.append(clampf(maxf(eastern_rise, western_rise), 0.0, 2.0) if not is_river else 0.0)
		map.heights.append(heights)
		map.terrain.append(terrain)
	# The intact bridge is 22 by 12 metres. The gap itself stays water in the
	# height/terrain grid; the bridge state supplies the traversable surface.
	map.bridges.append({"id": 1, "bounds": [149, 154, 23, 13],
		"heads": [[WEST_BRIDGE.x, WEST_BRIDGE.y], [EAST_BRIDGE.x, EAST_BRIDGE.y]]})
	# Four distinct route grammars: a military supply axis, riverside service
	# roads, the southern permanent detour, and short urban block streets.
	for pair: Array in [
		[PLAYER_START, Vector2(101, 169), 6.5],
		[Vector2(101, 169), WEST_BRIDGE, 6.5],
		[EAST_BRIDGE, Vector2(222, 169), 6.5],
		[Vector2(222, 169), ENEMY_START, 6.5],
		[Vector2(110, 169), Vector2(110, 278), 5.0],
		[Vector2(110, 278), Vector2(211, 282), 6.0],
		[Vector2(211, 282), Vector2(211, 169), 5.0],
		[Vector2(111, 169), Vector2(111, 111), 4.0],
		[Vector2(111, 111), Vector2(78, 111), 4.0],
		[Vector2(205, 168), EXPANSION, 5.0],
		[EXPANSION, Vector2(245, 109), 4.0],
		[Vector2(244, 109), Vector2(264, 167), 4.0]
	]: LAYOUT.road(map, pair[0], pair[1], pair[2])
	for row_z: int in [48, 75, 101]:
		LAYOUT.road(map, Vector2(24, row_z), Vector2(135, row_z), 3.2)
	for column_x: int in [36, 66, 96, 126]:
		LAYOUT.road(map, Vector2(column_x, 35), Vector2(column_x, 117), 3.0)
	# The ore crescent, contested mine and enemy industry make the two economies
	# visually legible without mirroring resource positions.
	for record: Dictionary in [
		{"pos": Vector2(81.5, 142.5), "team": 0, "tier": "near", "capacity": 4400},
		{"pos": Vector2(79.5, 197.5), "team": 0, "tier": "near", "capacity": 4400},
		{"pos": Vector2(111.5, 224.5), "team": 0, "tier": "expansion", "capacity": 6500},
		{"pos": Vector2(192.5, 117.5), "team": 0, "tier": "expansion", "capacity": 6800},
		{"pos": Vector2(246.5, 141.5), "team": 1, "tier": "near", "capacity": 4400},
		{"pos": Vector2(275.5, 195.5), "team": 1, "tier": "near", "capacity": 4400},
		{"pos": Vector2(243.5, 231.5), "team": 1, "tier": "expansion", "capacity": 6300},
		{"pos": Vector2(204.5, 217.5), "team": -1, "tier": "contested", "capacity": 6100}
	]:
		map.mines.append({"pos": [record.pos.x, record.pos.y], "capacity": record.capacity,
			"team": record.team, "tier": record.tier})
	# The west industrial yard and east forward pad are deliberately open for
	# refinery, barracks, factory and engineer-built outpost footprints.
	_for_each_house_block(map)
	_add_industry(map)
	_add_forest(map)
	_add_waterfront(map)
	map.valid = validate(map).is_empty()
	map.validation_errors = validate(map)
	return map

static func _for_each_house_block(map: Dictionary) -> void:
	var block: int = 0
	for z: int in [59, 86, 113]:
		for x: int in [50, 80, 110, 135]:
			block += 1
			for offset: Vector2 in [Vector2.ZERO, Vector2(6.5, 0), Vector2(0, 7.0), Vector2(6.5, 7.0)]:
				var pos := Vector2(x, z) + offset
				if _scenery_clear(map, pos, 2.7):
					_add_house(map, pos, ["townhouse", "shop", "cottage"][posmod(block + int(offset.x), 3)], block)
			var corner := Vector2(x - 10, z - 9)
			_add_prop(map, corner, "streetlamp", block % 3)
			_add_prop(map, corner + Vector2(0, 3.3), "bench", block % 3)
			for edge: Vector2 in [Vector2(-9, -3), Vector2(11, -3), Vector2(-9, 10), Vector2(11, 10)]:
				_add_prop(map, Vector2(x, z) + edge, "sidewalk", 0)
			if block % 2 == 0:
				var route: Array[Vector2] = [Vector2(x - 8, z - 8), Vector2(x + 12, z - 8), Vector2(x + 12, z + 12), Vector2(x - 8, z + 12)]
				map.civilians.append({"id": map.civilians.size(), "route": route,
					"speed": 0.64 + float(block % 3) * .08, "phase": float(block * 7), "variant": block % 3})

static func _add_industry(map: Dictionary) -> void:
	for record: Dictionary in [
		{"pos": Vector2(121, 138), "kind": "warehouse"},
		{"pos": Vector2(128, 138), "kind": "warehouse"},
		{"pos": Vector2(131, 205), "kind": "warehouse"},
		{"pos": Vector2(184, 203), "kind": "warehouse"},
		{"pos": Vector2(226, 122), "kind": "shop"},
		{"pos": Vector2(233, 122), "kind": "warehouse"},
		{"pos": Vector2(235, 203), "kind": "warehouse"},
		{"pos": Vector2(243, 203), "kind": "warehouse"},
		{"pos": Vector2(224, 239), "kind": "cottage"},
		{"pos": Vector2(260, 226), "kind": "cottage"}
	]:
		if _scenery_clear(map, record.pos, 2.8): _add_house(map, record.pos, record.kind, map.ruins.size())
	for pos: Vector2 in [Vector2(119, 143), Vector2(137, 142), Vector2(129, 197),
		Vector2(184, 210), Vector2(222, 131), Vector2(238, 131)]:
		_add_prop(map, pos, "streetlamp", int(pos.x) % 3)

static func _add_forest(map: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 220904
	for stand: Dictionary in [
		{"center": Vector2(35, 231), "r": Vector2(26, 32)},
		{"center": Vector2(47, 290), "r": Vector2(30, 18)},
		{"center": Vector2(277, 63), "r": Vector2(37, 34)},
		{"center": Vector2(287, 267), "r": Vector2(21, 28)},
		{"center": Vector2(178, 58), "r": Vector2(17, 38)}
	]:
		for i: int in 82:
			var angle: float = rng.randf_range(0.0, TAU)
			var radial: float = sqrt(rng.randf())
			var pos: Vector2 = stand.center + Vector2(cos(angle) * stand.r.x, sin(angle) * stand.r.y) * radial
			pos = Vector2(floorf(pos.x) + .5, floorf(pos.y) + .5)
			if not _scenery_clear(map, pos, 1.4, true): continue
			map.decorations.append({"pos": [pos.x, pos.y], "kind": "tree"})
	preload("res://scripts/battlefield_ruins.gd").register_trees(map)

static func _add_waterfront(map: Dictionary) -> void:
	for z: int in [38, 61, 91, 119, 188, 219, 244]:
		for x: int in [143, 178]:
			var pos := Vector2(x, z)
			if _scenery_clear(map, pos, .8): _add_prop(map, pos, "streetlamp", z % 3)
	for pos: Vector2 in [Vector2(138, 58), Vector2(137, 244), Vector2(183, 70), Vector2(184, 244)]:
		if _scenery_clear(map, pos, 3.0): _add_house(map, pos, "cottage", map.ruins.size())

static func _add_house(map: Dictionary, pos: Vector2, archetype: String, group: int) -> void:
	var height: float = {"cottage": 2.9, "townhouse": 5.1, "shop": 5.9, "warehouse": 3.7}.get(archetype, 3.7)
	map.ruins.append({"id": map.ruins.size(), "group": group, "kind": "house",
		"archetype": archetype, "height": height, "pos": pos, "half": Vector2(2.1, 2.1),
		"yaw": 0.0, "hp": 1400.0, "max_hp": 1400.0, "variant": posmod(group, 3)})

static func _add_prop(map: Dictionary, pos: Vector2, kind: String, variant: int) -> void:
	if pos.x < 3 or pos.y < 3 or pos.x > 316 or pos.y > 316: return
	map.environment_props.append({"pos": pos, "kind": kind, "variant": variant, "yaw": 0.0, "scale": 1.0})

static func _scenery_clear(map: Dictionary, pos: Vector2, radius: float, allow_slope: bool = false) -> bool:
	if pos.x < 5 + radius or pos.y < 5 + radius or pos.x > 315 - radius or pos.y > 315 - radius: return false
	for start: Array in map.starts:
		if pos.distance_to(Vector2(start[0], start[1])) < 26.0 + radius: return false
	for mine: Dictionary in map.mines:
		if pos.distance_to(Vector2(mine.pos[0], mine.pos[1])) < 7.0 + radius: return false
	for reserved: Vector2 in [WEST_BRIDGE, EAST_BRIDGE, EXPANSION, EAST_ASSEMBLY,
		Vector2(98, 160), Vector2(111, 278), Vector2(211, 282)]:
		if pos.distance_to(reserved) < (17.0 if reserved == EXPANSION else 9.0) + radius: return false
	for z: int in range(floori(pos.y - radius), ceili(pos.y + radius) + 1):
		for x: int in range(floori(pos.x - radius), ceili(pos.x + radius) + 1):
			if int(map.terrain[z][x]) != LAND or (not allow_slope and not is_zero_approx(float(map.heights[z][x]))): return false
	for ruin: Dictionary in map.ruins:
		if pos.distance_to(ruin.pos) < (2.0 if ruin.kind == "tree" else 5.5) + radius: return false
	return true

static func validate(map: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if int(map.get("size", 0)) != SIZE or map.get("terrain", []).size() != SIZE or map.get("heights", []).size() != SIZE:
		return ["campaign: expected a 320 by 320 grid"]
	if map.get("starts", []).size() != 2 or map.get("bridges", []).size() != 1:
		return ["campaign: missing command positions or bridge"]
	for z: int in SIZE:
		if map.terrain[z].size() != SIZE or map.heights[z].size() != SIZE: return ["campaign: malformed terrain row"]
		for x: int in SIZE:
			if int(map.terrain[z][x]) not in [LAND, WATER, ROAD] or not is_finite(float(map.heights[z][x])) or float(map.heights[z][x]) < 0.0 or float(map.heights[z][x]) > 2.0:
				return ["campaign: illegal terrain cell"]
	var bridge: Dictionary = map.bridges[0]
	if bridge.id != 1 or bridge.bounds != [149, 154, 23, 13]: errors.append("campaign: bridge geometry changed")
	for pos: Vector2 in [PLAYER_START, ENEMY_START, WEST_BRIDGE, EAST_BRIDGE, EXPANSION, EAST_ASSEMBLY]:
		if int(map.terrain[floori(pos.y)][floori(pos.x)]) == WATER: errors.append("campaign: mission pad under water")
	for start: Array in map.starts:
		var center := Vector2i(floori(float(start[0])), floori(float(start[1])))
		for z: int in range(center.y - 10, center.y + 11):
			for x: int in range(center.x - 10, center.x + 11):
				if int(map.terrain[z][x]) == WATER: errors.append("campaign: HQ apron is blocked"); break
	if map.mines.size() < 8: errors.append("campaign: ore layout incomplete")
	for id: int in map.ruins.size():
		if int(map.ruins[id].id) != id: errors.append("campaign: neutral IDs are not dense"); break
	var detour: PackedByteArray = _flood(map, Vector2i(62, 170))
	if detour[169 * SIZE + 262] == 0: errors.append("campaign: southern bypass is closed")
	if detour[160 * SIZE + 174] == 0: errors.append("campaign: east bridgehead lacks bypass access")
	return errors

static func _flood(map: Dictionary, start: Vector2i) -> PackedByteArray:
	var visited := PackedByteArray()
	visited.resize(SIZE * SIZE)
	var queue: Array[Vector2i] = [start]
	visited[start.y * SIZE + start.x] = 1
	var cursor: int = 0
	while cursor < queue.size():
		var here: Vector2i = queue[cursor]
		cursor += 1
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = here + direction
			if next.x < 0 or next.y < 0 or next.x >= SIZE or next.y >= SIZE: continue
			var index: int = next.y * SIZE + next.x
			if visited[index] != 0 or int(map.terrain[next.y][next.x]) == WATER: continue
			visited[index] = 1
			queue.append(next)
	return visited
