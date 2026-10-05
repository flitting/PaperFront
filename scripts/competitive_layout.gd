extends RefCounted
class_name CompetitiveLayout

## Reusable layout helpers intentionally do not depend on MapData. Campaign
## maps can author the same roads, beaches, safe pads and harbour records.
const CATALOG = preload("res://scripts/battlefield_catalog.gd")
const BIOME = preload("res://scripts/biome_scenery.gd")
const CITY = preload("res://scripts/city_layout.gd")
const V6_CITY = preload("res://scripts/v6_city_layout.gd")
const V6_NATURAL = preload("res://scripts/v6_natural_layout.gd")
const V6_RANDOM_CITY = preload("res://scripts/v6_random_city_layout.gd")
const V6_ISLANDS = preload("res://scripts/v6_islands_layout.gd")
const LAND = 0
const WATER = 1
const ROAD = 3
const SIZE = 320
const CENTER = Vector2(160, 160)
const DIRECTIONS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

static func generate(mode: String, seed: int, config: Dictionary = {}) -> Dictionary:
	if mode == "city": return V6_CITY.generate(seed, config)
	if mode == "random_city": return V6_RANDOM_CITY.generate(seed, config)
	if mode == "islands": return V6_ISLANDS.generate(seed, config)
	if mode in ["forest", "desert", "snow"]: return V6_NATURAL.generate(mode, seed, config)
	return generate_legacy(mode, seed, config)

static func generate_legacy(mode: String, seed: int, config: Dictionary = {}) -> Dictionary:
	var players: int = clampi(int(config.get("players", 2)), 2, 4)
	var map: Dictionary = {"mode": mode, "seed": seed, "size": SIZE, "heights": [], "terrain": [], "starts": [], "mines": [], "bridges": [], "decorations": [], "ruins": [], "environment_props": [], "civilians": [], "harbors": [], "landing_beaches": [], "profile": CATALOG.profile(mode, players), "layout": [], "valid": false, "water_surface_y": -2.65}
	var islands: Array[Dictionary] = []
	var angles: Array[float] = []
	for team: int in players:
		angles.append(PI + float(team) * TAU / players if players == 2 else -PI * 0.5 + float(team) * TAU / players if players == 3 else -PI * 0.75 + float(team) * TAU / players)
	var home_radius: float = 56.0 if players == 2 else 50.0 if players == 3 else 40.0
	var start_radius: float = 100.0 if mode == "islands" and players == 2 else 108.0 if mode == "islands" else 108.0
	for team: int in players:
		var outward := Vector2.from_angle(angles[team])
		var start: Vector2 = CENTER + outward * start_radius
		map.starts.append([start.x, start.y])
		map.layout.append({"team": team, "start": start, "outward": outward, "inward": -outward, "tangent": outward.orthogonal(), "near_mines": [], "expansion_mines": []})
		if mode == "islands": islands.append({"center": start, "radius": home_radius, "team": team, "role": "home"})
	if mode == "islands":
		islands.append({"center": CENTER, "radius": 32.0, "team": -1, "role": "contested"})
		for team: int in players:
			var expansions: Array[Vector2] = []
			if players == 2:
				expansions.assign([Vector2(126 if team == 0 else 194, 72), Vector2(126 if team == 0 else 194, 248)])
			else:
				for side: float in [-1.0, 1.0]:
					expansions.append(CENTER + Vector2.from_angle(angles[team] + side * (0.7 if players == 3 else 0.55)) * (116.0 if players == 3 else 136.0))
			for index: int in expansions.size():
				islands.append({"center": expansions[index], "radius": 31.0 if players == 2 else 18.0 if players == 3 else 22.0, "team": team, "role": "expansion", "index": index})
	else:
		islands.append({"center": CENTER, "radius": 155.0, "team": -1, "role": "continent"})
	map.profile.islands = islands
	for z: int in SIZE:
		var heights: Array[float] = []
		var terrain: Array[int] = []
		for x: int in SIZE:
			var point := Vector2(x + 0.5, z + 0.5)
			var depth: float = -INF
			for island: Dictionary in islands:
				depth = maxf(depth, float(island.radius) - point.distance_to(island.center))
			terrain.append(LAND if depth >= 0.0 else WATER)
			# Four 60 cm steps meet water only 25 cm below the final beach.
			heights.append(-0.6 * float(clampi(4 - floori(depth), 0, 4)) if depth >= 0.0 else 0.0)
		map.heights.append(heights)
		map.terrain.append(terrain)
	for record: Dictionary in map.layout:
		var start: Vector2 = record.start
		var tangent: Vector2 = record.tangent
		var inward: Vector2 = record.inward
		for side: float in [-1.0, 1.0]:
			add_mine(map, start + inward * 10.0 + tangent * side * 8.0, record.team, "near")
		if mode != "islands":
			for side: float in [-1.0, 1.0]: add_mine(map, start + inward * 54.0 + tangent * side * 22.0, record.team, "expansion")
			road(map, start, CENTER, 5.5)
			var coast: Vector2 = CENTER + record.outward * 155.0
			add_harbor(map, record.team, coast, record.outward, "home")
			road(map, start, coast - record.outward * 7.0, 5.0)
		else:
			# Side-facing coves retain four metres of navigable launch water at
			# the map edge even on the north point of a three-player island.
			var harbor_direction: Vector2 = (record.outward as Vector2).rotated(0.45)
			var coast: Vector2 = start + harbor_direction * home_radius
			add_harbor(map, record.team, coast, harbor_direction, "home")
			road(map, start, coast - harbor_direction * 7.0, 4.0)
	for island: Dictionary in islands:
		if island.role != "expansion": continue
		add_mine(map, island.center, island.team, "expansion")
		var seaward: Vector2 = (CENTER - island.center).normalized()
		add_harbor(map, island.team, island.center + seaward * float(island.radius), seaward, "expansion")
	for mine: Dictionary in map.mines:
		var owner: int = int(mine.team)
		if owner >= 0 and (mine.tier == "near" or mode != "islands"):
			road(map, map.layout[owner].start, Vector2(float(mine.pos[0]), float(mine.pos[1])), 4.0)
	# Contested central ore has equal angular distance from each homeland.
	for team: int in players:
		var point: Vector2 = CENTER + Vector2.from_angle(angles[team]) * 14.0
		add_mine(map, point, -1, "contested")
	if mode in ["city", "random_city"]: CITY.apply(map)
	BIOME.apply(map)
	preload("res://scripts/battlefield_ruins.gd").register_trees(map)
	map.profile.water_fraction = _water_fraction(map)
	return map

static func add_mine(map: Dictionary, point: Vector2, team: int, tier: String) -> void:
	var index: int = map.mines.size()
	map.mines.append({"pos": [point.x, point.y], "capacity": 4000 if tier == "near" else 6000, "team": team, "tier": tier})
	if team >= 0: map.layout[team]["near_mines" if tier == "near" else "expansion_mines"].append(index)

static func add_harbor(map: Dictionary, team: int, coast: Vector2, outward: Vector2, role: String) -> void:
	var land: Vector2 = coast - outward * 9.0
	var water: Vector2 = coast + outward * 4.0
	var harbor: Dictionary = {"team": team, "role": role, "land_pos": land, "water_pos": water, "shore_pos": coast - outward * 0.5, "outward": outward, "radius": 10.0, "protected": true}
	map.harbors.append(harbor)
	map.landing_beaches.append({"team": team, "role": role, "land_pos": coast - outward * 0.5, "water_pos": water, "width": 12.0, "shore_height": -2.4})

static func road(map: Dictionary, from: Vector2, to: Vector2, half_width: float) -> void:
	for z: int in range(maxi(0, floori(minf(from.y, to.y) - half_width)), mini(int(map.size), ceili(maxf(from.y, to.y) + half_width))):
		for x: int in range(maxi(0, floori(minf(from.x, to.x) - half_width)), mini(int(map.size), ceili(maxf(from.x, to.x) + half_width))):
			var point := Vector2(x + 0.5, z + 0.5)
			if int(map.terrain[z][x]) == LAND and point.distance_to(Geometry2D.get_closest_point_to_segment(point, from, to)) <= half_width: map.terrain[z][x] = ROAD

static func clear_of_gameplay(map: Dictionary, point: Vector2, radius: float = 1.0) -> bool:
	if point.x < radius + 2 or point.y < radius + 2 or point.x >= int(map.size) - radius - 2 or point.y >= int(map.size) - radius - 2: return false
	for start: Array in map.starts:
		if point.distance_to(Vector2(start[0], start[1])) < 23.0 + radius: return false
	for mine: Dictionary in map.mines:
		if point.distance_to(Vector2(mine.pos[0], mine.pos[1])) < 5.0 + radius: return false
	for harbor: Dictionary in map.harbors:
		if point.distance_to(harbor.land_pos) < float(harbor.radius) + radius or point.distance_to(harbor.shore_pos) < float(harbor.radius) + radius: return false
	for z: int in range(floori(point.y - radius), ceili(point.y + radius) + 1):
		for x: int in range(floori(point.x - radius), ceili(point.x + radius) + 1):
			if int(map.terrain[z][x]) != LAND or not is_zero_approx(float(map.heights[z][x])): return false
	return true

static func _water_fraction(map: Dictionary) -> float:
	var count: int = 0
	for row: Array in map.terrain:
		for kind: int in row:
			if kind == WATER: count += 1
	return float(count) / float(int(map.size) * int(map.size))

static func flood(map: Dictionary, start: Vector2i, water: bool = false) -> PackedByteArray:
	var size: int = int(map.size)
	# A road-painted bridge deck may cover a water cell in authored maps. The
	# same cell remains land-passable across the deck and water-passable below it.
	# Existing profiles with WATER beneath their bridges retain their topology.
	var bridge_cells: Dictionary = {}
	for bridge: Dictionary in map.get("bridges", []):
		var bounds: Array = bridge.get("bounds", [])
		if bounds.size() != 4: continue
		for z in range(maxi(0, int(bounds[1])), mini(size, int(bounds[1]) + int(bounds[3]))):
			for x in range(maxi(0, int(bounds[0])), mini(size, int(bounds[0]) + int(bounds[2]))):
				bridge_cells[z * size + x] = true
	var visited := PackedByteArray()
	visited.resize(size * size)
	var queue: Array[Vector2i] = [start]
	visited[start.y * size + start.x] = 1
	var cursor: int = 0
	while cursor < queue.size():
		var here: Vector2i = queue[cursor]
		cursor += 1
		for direction: Vector2i in DIRECTIONS:
			var next: Vector2i = here + direction
			if next.x < 0 or next.y < 0 or next.x >= size or next.y >= size or visited[next.y * size + next.x] != 0: continue
			var index: int = next.y * size + next.x
			var kind: int = int(map.terrain[next.y][next.x])
			var water_passable: bool = kind == WATER or (kind == ROAD and bridge_cells.has(index))
			if water and not water_passable: continue
			if not water and (kind == 4 or kind == WATER and not bridge_cells.has(index)): continue
			if not water and absf(float(map.heights[here.y][here.x]) - float(map.heights[next.y][next.x])) > 0.75: continue
			visited[next.y * size + next.x] = 1
			queue.append(next)
	return visited

static func validate(map: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var size: int = int(map.get("size", 0))
	var profile: Dictionary = map.get("profile", {})
	var players: int = int(profile.get("players", 0))
	if profile.has("max_height") and (int(profile.get("design_version", 0)) != 6 or not (profile.max_height is float or profile.max_height is int) or not is_finite(float(profile.max_height)) or float(profile.max_height) < 6.0 or float(profile.max_height) > 18.0):
		return ["profile: invalid authored terrain height cap"]
	if size != SIZE or players not in [2, 3, 4] or not CATALOG.has_profile(str(profile.get("id", ""))) or not map.get("heights") is Array or not map.get("terrain") is Array:
		return ["profile: invalid battlefield dimensions, players or grid"]
	if map.heights.size() != size or map.terrain.size() != size or not map.get("starts") is Array or map.starts.size() != players:
		return ["profile: grid or real spawn count does not match players"]
	if not map.get("mines") is Array or not map.get("harbors") is Array or not map.get("landing_beaches") is Array or not map.get("ruins") is Array:
		return ["profile: missing resources, coast records or neutral geometry"]
	for mine: Variant in map.mines:
		if not mine is Dictionary or not mine.get("pos") is Array or mine.pos.size() != 2: return ["profile: malformed ore position"]
		var point := Vector2(float(mine.pos[0]), float(mine.pos[1]))
		if not point.is_finite() or point.x < 0 or point.y < 0 or point.x >= size or point.y >= size: return ["profile: ore position outside battlefield"]
	for harbor: Variant in map.harbors:
		if not harbor is Dictionary or not harbor.get("land_pos") is Vector2 or not harbor.get("water_pos") is Vector2 or not harbor.get("role") is String or not harbor.has("team"): return ["profile: malformed harbour record"]
		for point: Vector2 in [harbor.land_pos, harbor.water_pos]:
			if not point.is_finite() or point.x < 0 or point.y < 0 or point.x >= size or point.y >= size: return ["profile: harbour outside battlefield"]
	for z: int in size:
		if not map.heights[z] is Array or not map.terrain[z] is Array or map.heights[z].size() != size or map.terrain[z].size() != size: return ["profile: malformed grid row"]
		for x: int in size:
			var h: float = float(map.heights[z][x])
			var kind: int = int(map.terrain[z][x])
			if not is_finite(h) or h < -2.4001 or h > float(profile.get("max_height", 6.0)) or kind not in [LAND, WATER, ROAD, 4]: errors.append("profile: invalid ground or terrain")
			if kind == WATER and not is_zero_approx(h): errors.append("profile: all connected sea cells require the common water level")
	if not errors.is_empty(): return errors
	var sea: PackedByteArray = flood(map, Vector2i.ZERO, true)
	var all_water: int = 0
	var connected_water: int = 0
	for z: int in size:
		for x: int in size:
			if int(map.terrain[z][x]) == WATER:
				all_water += 1
				connected_water += int(sea[z * size + x])
	if connected_water != all_water: errors.append("profile: sea must form one connected navigable component")
	if profile.routes == "naval" and (float(all_water) / float(size * size) < 0.60 or float(all_water) / float(size * size) > 0.70): errors.append("profile: archipelago must contain approximately 65% sea")
	var reference: Array[float] = []
	for team: int in players:
		var start_array: Variant = map.starts[team]
		if not start_array is Array or start_array.size() != 2: return ["profile: malformed spawn"]
		var start := Vector2(float(start_array[0]), float(start_array[1]))
		if start.x < 14.0 or start.y < 14.0 or start.x >= size - 14.0 or start.y >= size - 14.0: return ["profile: spawn outside legal battlefield"]
		var cell := Vector2i(floori(start.x), floori(start.y))
		for z: int in range(cell.y - 10, cell.y + 11):
			for x: int in range(cell.x - 10, cell.x + 11):
				if int(map.terrain[z][x]) not in [LAND, ROAD] or not is_zero_approx(float(map.heights[z][x])): errors.append("profile: headquarters requires a clear 21 metre flat apron")
		var land: PackedByteArray = flood(map, cell)
		if profile.routes == "land":
			for other: Array in map.starts:
				if land[floori(float(other[1])) * size + floori(float(other[0]))] != 1: errors.append("profile: headquarters lack permanent broad land routes")
		var metrics: Array[float] = []
		for tier: String in ["near", "expansion"]:
			var owned: Array = map.mines.filter(func(m): return int(m.get("team", -1)) == team and m.get("tier") == tier)
			if owned.size() != 2: errors.append("profile: each team requires two %s mines" % tier)
			for mine: Dictionary in owned:
				var point := Vector2(float(mine.pos[0]), float(mine.pos[1]))
				var mc := Vector2i(floori(point.x), floori(point.y))
				if int(map.terrain[mc.y][mc.x]) not in [LAND, ROAD] or float(mine.get("capacity", 0)) <= 0: errors.append("profile: ore must occupy legal usable ground")
				if (tier == "near" or profile.routes == "land") and land[mc.y * size + mc.x] != 1: errors.append("profile: resource lacks permanent land access")
				metrics.append(point.distance_to(start))
				metrics.append(float(mine.get("capacity", 0)))
		if team == 0: reference.assign(metrics)
		elif metrics.size() != reference.size(): errors.append("profile: unequal resource counts")
		else:
			for i: int in metrics.size():
				if absf(metrics[i] - reference[i]) > 0.01: errors.append("profile: unequal starting or expansion resource distance/capacity")
		var harbors: Array = map.harbors.filter(func(h): return int(h.team) == team and h.role == "home")
		if harbors.size() != 1: errors.append("profile: each team requires one protected home harbour")
		for harbor: Dictionary in map.harbors:
			if int(harbor.team) != team: continue
			var wet: Vector2 = harbor.water_pos
			var wc := Vector2i(floori(wet.x), floori(wet.y))
			if sea[wc.y * size + wc.x] != 1: errors.append("profile: harbour lacks connected sea access")
			if harbor.role == "home":
				var dry: Vector2 = harbor.land_pos
				if land[floori(dry.y) * size + floori(dry.x)] != 1: errors.append("profile: home harbour lacks a land approach")
	for index: int in map.get("ruins", []).size():
		if not map.ruins[index] is Dictionary: return ["profile: malformed neutral geometry"]
		if int(map.ruins[index].get("id", -1)) != index: errors.append("profile: neutral IDs must remain dense")
	for beach: Dictionary in map.landing_beaches:
		if not beach.get("land_pos") is Vector2 or not beach.get("water_pos") is Vector2: return ["profile: malformed landing beach"]
		var dry: Vector2 = beach.land_pos
		var wet: Vector2 = beach.water_pos
		if dry.x < 0 or dry.y < 0 or dry.x >= size or dry.y >= size or wet.x < 0 or wet.y < 0 or wet.x >= size or wet.y >= size: return ["profile: landing beach outside battlefield"]
		if int(map.terrain[floori(dry.y)][floori(dry.x)]) == WATER or not is_equal_approx(float(map.heights[floori(dry.y)][floori(dry.x)]), -2.4): errors.append("profile: landing beach must meet sea on the lowest usable land step")
		if sea[floori(wet.y) * size + floori(wet.x)] != 1: errors.append("profile: landing beach requires connected sea access")
	return errors
