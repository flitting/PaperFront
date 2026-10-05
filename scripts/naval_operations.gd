extends RefCounted

const Navigation = preload("res://scripts/naval_navigation.gd")
const LAND_NEIGHBOURS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN, Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
const COMPASS: Array[Vector2] = [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN, Vector2(0.7071068, 0.7071068), Vector2(-0.7071068, 0.7071068), Vector2(0.7071068, -0.7071068), Vector2(-0.7071068, -0.7071068)]

static func initialize(sim) -> void:
	sim._naval_navigation = Navigation.new()
	sim._naval_navigation.configure(sim.map, sim.bridges)

static func is_naval(sim, e: Dictionary) -> bool:
	return e.get("kind", "") == "unit" and str(sim.data_for(str(e.get("spec", ""))).get("domain", "ground")) == "naval"

static func _nav(sim):
	if sim._naval_navigation == null: initialize(sim)
	sim._naval_navigation.refresh_bridges(sim.bridges)
	return sim._naval_navigation

static func _draft(sim, e: Dictionary) -> float:
	return float(sim.data_for(e.spec).get("naval_air_draft", 1.5))

static func debug_spawn_point(sim, desired: Vector2, radius: float) -> Vector2:
	return _nav(sim).near_water(sim, desired, radius, 2.3, -1, 8.0)

static func move_to(sim, e: Dictionary, desired: Vector2, delta: float) -> bool:
	var nav = _nav(sim)
	var radius: float = float(sim.data_for(e.spec).get("radius", 0.9))
	var draft: float = _draft(sim, e)
	var goal: Vector2 = nav.near_water(sim, desired, radius, draft, int(e.id), 8.0, false)
	if not goal.is_finite():
		e.state = "unreachable"
		return false
	if not e.commands.is_empty() and (e.commands[0].pos as Vector2).is_equal_approx(desired) and not goal.is_equal_approx(desired):
		# Only normal movement may rewrite the destination; unload_move stores a
		# land target and needs its original shore coordinate on every tick.
		if str(e.commands[0].kind) not in ["unload_move", "attack"]: e.commands[0].pos = goal
	if (e.pos as Vector2).distance_to(goal) <= maxf(0.26, radius * 0.35):
		e.motion = 0.0
		e.state = "idle"
		return true
	var path_goal: Vector2 = e.get("naval_path_goal", Vector2.INF)
	var route: Array = e.get("naval_path", [])
	if route.is_empty() or not path_goal.is_finite() or path_goal.distance_to(goal) > 0.55 or float(e.get("naval_repath_at", 0.0)) <= sim.time:
		route = nav.path_between(sim, e.pos, goal, radius, draft, int(e.id))
		e.naval_path = route
		e.naval_path_goal = goal
		e.naval_repath_at = sim.time + 1.0 + float(int(e.id) % 5) * 0.07
	if route.is_empty():
		e.state = "unreachable"
		return false
	while route.size() > 1 and (e.pos as Vector2).distance_to(route[0]) <= maxf(0.3, radius * 0.35): route.pop_front()
	if route.is_empty(): return false
	var waypoint: Vector2 = route[0]
	var offset: Vector2 = waypoint - e.pos
	if offset.length() <= 0.2:
		route.pop_front()
		return false
	var wanted: float = rad_to_deg(offset.angle())
	sim._turn(e, wanted, delta)
	var forward: Vector2 = Vector2.from_angle(deg_to_rad(float(e.alpha)))
	var turn_error: float = absf(wrapf(wanted - float(e.alpha), -180.0, 180.0))
	if turn_error > 75.0:
		e.motion = 0.0
		e.state = "move"
		return false
	var speed: float = float(sim.data_for(e.spec).speed) * maxf(0.22, cos(deg_to_rad(turn_error)))
	var stride: float = minf(speed * delta, offset.length())
	var next: Vector2 = (e.pos as Vector2) + offset.normalized() * stride
	if not nav.segment_clear(sim, e.pos, next, radius, draft, int(e.id), true):
		# A ship in the channel has right of way until its bounded retry expires.
		e.state = "waiting"
		e.motion = 0.0
		e.naval_repath_at = minf(float(e.naval_repath_at), sim.time + 0.35)
		return false
	var old: Vector2 = e.pos
	e.pos = next
	e.motion = old.distance_to(next)
	e.state = "move"
	sim._spatial_move(e, old, next)
	if next.distance_to(waypoint) <= 0.22: route.pop_front()
	return next.distance_to(goal) <= maxf(0.26, radius * 0.35)

## New shipyards occupy water cells only. Old saves own their historical rule
## snapshot, whose ground-domain shipyards retain the prior coast footprint.
## Both policies keep physical exits, occupancy and construction authority.
static func shipyard_site_error(sim, team: int, info: Dictionary, pos: Vector2, builder: int = -1) -> String:
	var size: int = int(info.get("size", 4))
	var half: float = float(size) * 0.5
	var origin: Vector2i = Vector2i(roundi(pos.x - half), roundi(pos.y - half))
	var water: int = 0
	var land: int = 0
	var shore_level: float = INF
	var high_level: float = -INF
	var water_built: bool = str(info.get("domain", "ground")) == "naval"
	for z in range(origin.y, origin.y + size):
		for x in range(origin.x, origin.x + size):
			var cell := Vector2(x + 0.5, z + 0.5)
			if not sim._in_bounds(cell): return "船坞超出地图边界"
			var terrain: int = sim._terrain(cell)
			if water_built and terrain != MapData.WATER: return "船坞全部占地必须位于水面"
			if terrain == 1: water += 1
			elif terrain in [0, 3]:
				land += 1
				shore_level = minf(shore_level, sim._height(cell))
				high_level = maxf(high_level, sim._height(cell))
			else: return "船坞需要平缓海岸，不能压在坡道或障碍上"
			if sim.bridge_at(cell) >= 0: return "船坞不能覆盖桥梁"
	if not water_built:
		if water < size or land < size: return "旧式船坞需同时覆盖相邻陆岸和水面"
		if high_level - shore_level > 1.8: return "船坞陆侧高差过大"
	if not _yard_authorized(sim,team,pos,half,water_built,builder): return "超出己方已完成建筑的扩建范围"
	var largest: Vector2 = _largest_hull(sim,team)
	var exit: Vector2 = _yard_exit(sim, pos, size, largest.x, largest.y)
	if not exit.is_finite(): return "船坞水侧没有舰艇航道出口"
	if water_built and not _yard_has_shore_route(sim,pos,size,team): return "船坞会阻断舰艇往返岸边的航道"
	for e: Dictionary in sim.entities.values():
		if float(e.get("hp", 0.0)) <= 0.0 or int(e.get("id", -1)) == builder or int(e.get("transport_id", -1)) > 0: continue
		if e.get("kind", "") == "building":
			var other: float = float(sim.data_for(e.spec).get("size", 1)) * 0.5
			if absf(e.pos.x - pos.x) < half + other and absf(e.pos.y - pos.y) < half + other: return "船坞占地与已有建筑重叠"
		elif not sim._is_air(e) and sim._circle_rect(e.pos, sim._radius(e), pos, Vector2.ONE * half):
			return "单位占据船坞位置"
	for ruin: Dictionary in sim._nearby_ruins(pos, half):
		if float(ruin.hp) > 0.0 and absf(ruin.pos.x-pos.x) < half + ruin.half.x and absf(ruin.pos.y-pos.y) < half + ruin.half.y: return "船坞位置有石墙或废墟"
	for ore: Dictionary in sim.mines:
		if sim._circle_rect(ore.pos, 1.2, pos, Vector2.ONE * half): return "船坞不能覆盖矿点"
	return ""

static func _yard_authorized(sim, team: int, pos: Vector2, half: float, water_built: bool, builder: int) -> bool:
	if builder >= 0: return true
	if sim.in_construction_range(team, pos): return true
	# Headquarters in the island profile sit well inland. Their protected home
	# harbour is an owned construction zone once a real base exists, while an
	# enemy or remote expansion shore never grants free placement.
	if sim._has_construction_base(team):
		for harbor: Dictionary in sim.map.get("harbors", []):
			if int(harbor.get("team", -1)) != team or str(harbor.get("role", "")) != "home" or not bool(harbor.get("protected", false)): continue
			var shore: Vector2 = harbor.get("shore_pos", Vector2.INF)
			var harbor_radius: float = float(harbor.get("radius", 10.0)) + half
			# A fully afloat dock needs room beyond the embarkation apron, rather
			# than consuming the sole passage next to the historical shore dock.
			if water_built: harbor_radius += _largest_hull(sim,team).x * 2.0
			if shore.is_finite() and shore.distance_to(pos) <= harbor_radius: return true
	return false

static func _largest_hull(sim, team: int) -> Vector2:
	var hull := Vector2(0.8,1.35)
	for spec: Dictionary in sim.rules.units.values():
		if spec.get("faction", "") != sim.factions[team] or spec.get("domain", "ground") != "naval": continue
		hull.x = maxf(hull.x,float(spec.get("radius",0.8)))
		hull.y = maxf(hull.y,float(spec.get("naval_air_draft",1.35)))
	return hull

## Query the proposed solid footprint in an isolated local sea grid. The
## actual troop transport must reach its embarkation shore; large warships
## separately retain the whole-hull launch clearance checked above.
static func _yard_has_shore_route(sim, center: Vector2, size: int, team: int) -> bool:
	var carrier_spec: String = sim.factions[team]+"_ship_transport"
	var carrier: Dictionary = sim.data_for(carrier_spec)
	var hull := Vector2(float(carrier.get("radius",2.2)),float(carrier.get("naval_air_draft",1.35)))
	var exit: Vector2 = _yard_exit(sim,center,size,hull.x,hull.y)
	if not exit.is_finite(): return false
	var probe = Navigation.new()
	probe.configure(sim.map,sim.bridges)
	probe.query_footprint = Rect2(center-Vector2.ONE*float(size)*.5,Vector2.ONE*float(size))
	probe.query_region = Rect2i(Vector2i(floori(center.x)-32,floori(center.y)-32),Vector2i(64,64))
	if not probe.water_clear(sim,exit,hull.x,hull.y,-1,false): return false
	var ship: Dictionary = {"id":-1,"kind":"unit","spec":carrier_spec,"pos":exit,"radius":hull.x}
	var targets: Array[Vector2] = []
	for harbor: Dictionary in sim.map.get("harbors",[]):
		if int(harbor.get("team",-1)) == team and center.distance_to(harbor.shore_pos) <= 28.0: targets.append(harbor.land_pos)
	if targets.is_empty(): targets.append(center)
	for target: Vector2 in targets:
		var pair: Dictionary = coast_pair(sim,ship,null,target)
		if pair.is_empty() or not probe.water_clear(sim,pair.water,hull.x,hull.y,-1,false): continue
		var route: Array[Vector2] = probe.path_between(sim,exit,pair.water,hull.x,hull.y,-1)
		if not route.is_empty() and route.back().is_equal_approx(pair.water): return true
	return false

static func _yard_exit(sim, center: Vector2, size: int, radius: float, draft: float, dynamic: bool = false, ignore: int = -1) -> Vector2:
	var nav = _nav(sim)
	var half: float = float(size) * 0.5
	var directions: Array[Vector2] = [Vector2.from_angle(deg_to_rad(shipyard_heading(sim, center)))]
	directions.append_array(COMPASS)
	for ring in range(12):
		var distance: float = half + radius + 0.45 + float(ring) * 0.6
		for side: Vector2 in directions:
			var point: Vector2 = center + side * distance
			if sim._circle_rect(point,radius+.06,center,Vector2.ONE*half): continue
			if not nav.water_clear(sim, point, radius, draft, ignore, dynamic): continue
			# The dock's own footprint is not yet an entity at placement time.
			if point.x > center.x - half and point.x < center.x + half and point.y > center.y - half and point.y < center.y + half: continue
			return point
	return Vector2.INF

static func shipyard_heading(sim, center: Vector2) -> float:
	var closest: float = INF
	var heading: Vector2 = Vector2.RIGHT
	for harbor: Dictionary in sim.map.get("harbors", []):
		var shore: Vector2 = harbor.get("shore_pos", Vector2.INF)
		var outward: Vector2 = harbor.get("outward", Vector2.ZERO)
		if shore.is_finite() and outward.length_squared() > 0.1 and center.distance_to(shore) < closest:
			closest = center.distance_to(shore)
			heading = outward.normalized()
	if closest <= 18.0: return rad_to_deg(heading.angle())
	var best: int = -1
	for direction: Vector2 in COMPASS:
		var score: int = 0
		for distance in [2.0, 3.0, 4.0]:
			if _nav(sim).is_water(center + direction * distance): score += 1
		if score > best:
			best = score
			heading = direction
	return rad_to_deg(heading.angle())

static func spawn_point(sim, shipyard: Dictionary, unit_spec: String) -> Vector2:
	var info: Dictionary = sim.data_for(unit_spec)
	var radius: float = float(info.get("radius", 1.0))
	var draft: float = float(info.get("naval_air_draft", 1.5))
	return _yard_exit(sim,shipyard.pos,int(sim.data_for(shipyard.spec).get("size",4)),radius,draft,true,int(shipyard.get("id",-1)))

## Return a physically adjacent land/water pair. The land point is a real
## standing spot and the water point clears the entire hull. This also rejects
## high cliffs, walls, bridges and unloading through impassable shore objects.
static func coast_pair(sim, ship: Dictionary, passenger: Variant = null, desired_land: Vector2 = Vector2.INF) -> Dictionary:
	var nav = _nav(sim)
	var radius: float = float(sim.data_for(ship.spec).get("radius", 0.85))
	var draft: float = _draft(sim, ship)
	var land_radius: float = 0.35 if passenger == null else sim._radius(passenger)
	var origin: Vector2 = desired_land if desired_land.is_finite() else passenger.pos if passenger != null else ship.pos
	if not origin.is_finite(): return {}
	var boarding_component: Dictionary = _boarding_land_component(sim, nav, passenger.pos) if passenger != null else {}
	if passenger != null and boarding_component.is_empty(): return {}
	var best: Dictionary = {}
	var best_score: float = INF
	var anchors: Array[Vector2] = [origin]
	if passenger != null or desired_land.is_finite():
		var landmarks: Array[Vector2] = []
		for beach: Dictionary in sim.map.get("landing_beaches", []):
			landmarks.append(beach.get("land_pos", Vector2.INF))
		for harbor: Dictionary in sim.map.get("harbors", []):
			landmarks.append(harbor.get("shore_pos", Vector2.INF))
		landmarks.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(origin) < b.distance_squared_to(origin))
		for marker: Vector2 in landmarks:
			if marker.is_finite(): anchors.append(marker)
	for anchor: Vector2 in anchors:
		if anchor.distance_to(origin) > best_score + 2.0: break
		for ring in range(17):
			var distance: float = float(ring) * 0.75
			var steps: int = 1 if ring == 0 else maxi(16, ring * 8)
			for step in range(steps):
				var land: Vector2 = anchor + Vector2.from_angle(float(step) * TAU / float(steps)) * distance
				if passenger != null and not _boarding_same_component(boarding_component, land): continue
				if not sim._standing(land, land_radius, int(passenger.id) if passenger != null else -1, false): continue
				for direction: Vector2 in COMPASS:
					var water: Vector2 = land + direction * (land_radius + radius + 0.42)
					if not nav.water_clear(sim, water, radius, draft, int(ship.id), false): continue
					if absf(sim._height(land) - MapData.water_surface_y(sim.map, water)) > 1.25: continue
					# The near half of the crossing must remain on land, the far half
					# on water; a wall or deep channel cannot be skipped by embarkation.
					var shoreline: Vector2 = land.lerp(water, 0.5)
					if not sim._land(land.lerp(shoreline, 0.5)): continue
					if not nav.is_water(water.lerp(shoreline, 0.5)): continue
					if not _crossing_clear(sim, land, water, land_radius, int(passenger.id) if passenger != null else -1): continue
					var water_distance: float = (ship.pos as Vector2).distance_to(water)
					var score: float = water_distance * 2.0 + land.distance_to(origin) * 0.05 if passenger == null and not desired_land.is_finite() else land.distance_to(origin) + water_distance * 0.035
					if score < best_score:
						if not nav.connected(sim,ship.pos,water,radius,draft,int(ship.id)): continue
						best_score = score
						best = {"land": land, "water": water}
			if not best.is_empty() and distance > best_score + 1.0: break
	if best.is_empty() and passenger != null:
		best = _boarding_shore_fallback(sim, nav, ship, passenger, boarding_component, origin)
	return best

## Boarding cannot send infantry to a shore on a different island. This is
## a conservative terrain topology filter, not a claim that a radius-aware
## route is clear: heights, footprints and traffic remain the ground planner's
## responsibility. Diagonal neighbours avoid rejecting valid diagonal ground
## paths. Live bridge decks connect land; destroyed decks do not. Cache only
## immutable map terrain and bridge state on this map's naval navigator.
static func _boarding_land_component(sim, nav, start: Vector2) -> Dictionary:
	var size: int = int(sim.map.size)
	if not sim._land(start): return {}
	var revision: String = nav._bridge_key()
	var data: Dictionary = nav.get_meta("boarding_ground_topology", {})
	if data.is_empty() or str(data.revision) != revision:
		var fresh := PackedInt32Array()
		fresh.resize(size * size)
		data = {"revision": revision, "labels": fresh, "next": 1, "size": size, "coasts": {}}
		nav.set_meta("boarding_ground_topology", data)
	var labels: PackedInt32Array = data.labels
	var cell := Vector2i(floori(start.x), floori(start.y))
	var index: int = cell.y * size + cell.x
	if labels[index] == 0:
		var label: int = int(data.next)
		data.next = label + 1
		labels[index] = label
		var queue: Array[Vector2i] = [cell]
		var coasts: Array[Vector2] = []
		var cursor: int = 0
		while cursor < queue.size():
			var here: Vector2i = queue[cursor]
			cursor += 1
			var shore: bool = false
			for offset: Vector2i in LAND_NEIGHBOURS:
				var next: Vector2i = here + offset
				if next.x < 0 or next.y < 0 or next.x >= size or next.y >= size: continue
				if int(sim.map.terrain[next.y][next.x]) == MapData.WATER: shore = true
				var next_index: int = next.y * size + next.x
				if labels[next_index] != 0 or not sim._land(Vector2(next) + Vector2(.5, .5)): continue
				labels[next_index] = label
				queue.append(next)
			if shore: coasts.append(Vector2(here) + Vector2(.5, .5))
		data.labels = labels
		data.coasts[label] = coasts
	return {"labels": labels, "label": labels[index], "size": size, "coasts": data.coasts.get(labels[index], [])}

static func _boarding_same_component(component: Dictionary, point: Vector2) -> bool:
	if not point.is_finite(): return false
	var size: int = int(component.size)
	var cell := Vector2i(floori(point.x), floori(point.y))
	if cell.x < 0 or cell.y < 0 or cell.x >= size or cell.y >= size: return false
	return int(component.labels[cell.y * size + cell.x]) == int(component.label)

## Landmark rings cover only twelve metres around each authored beach. A
## valid shore elsewhere on the passenger's island must not be replaced with
## a different island. Search the cached boundary cells only when those rings
## find no pair. Quarter-cell standing samples catch narrow legal shore strips;
## every endpoint, crossing, hull and connection test is the original rule.
static func _boarding_shore_fallback(sim, nav, ship: Dictionary, passenger: Dictionary, component: Dictionary, origin: Vector2) -> Dictionary:
	var land_radius: float = sim._radius(passenger)
	var radius: float = float(sim.data_for(ship.spec).get("radius", 0.85))
	var draft: float = _draft(sim, ship)
	var best: Dictionary = {}
	var best_score: float = INF
	for center: Vector2 in component.coasts:
		for offset: Vector2 in [Vector2.ZERO, Vector2(-.25, 0), Vector2(.25, 0), Vector2(0, -.25), Vector2(0, .25)]:
			var land: Vector2 = center + offset
			if not sim._standing(land, land_radius, int(passenger.id), false): continue
			for direction: Vector2 in COMPASS:
				var water: Vector2 = land + direction * (land_radius + radius + .42)
				if not nav.water_clear(sim, water, radius, draft, int(ship.id), false): continue
				if absf(sim._height(land) - MapData.water_surface_y(sim.map, water)) > 1.25: continue
				var shoreline: Vector2 = land.lerp(water, .5)
				if not sim._land(land.lerp(shoreline, .5)): continue
				if not nav.is_water(water.lerp(shoreline, .5)): continue
				if not _crossing_clear(sim, land, water, land_radius, int(passenger.id)): continue
				var score: float = land.distance_to(origin) + (ship.pos as Vector2).distance_to(water) * .035
				if score < best_score and nav.connected(sim, ship.pos, water, radius, draft, int(ship.id)):
					best_score = score
					best = {"land": land, "water": water}
	return best

static func pair_clear(sim, ship: Dictionary, passenger: Variant, pair: Dictionary) -> bool:
	if pair.is_empty() or not pair.has("land") or not pair.has("water"): return false
	var land: Vector2 = pair.land
	var water: Vector2 = pair.water
	var land_radius: float = 0.35 if passenger == null else sim._radius(passenger)
	var passenger_id: int = -1 if passenger == null else int(passenger.id)
	if land.distance_to(water) > land_radius + sim._radius(ship) + 0.8: return false
	if not sim._standing(land, land_radius, passenger_id, false): return false
	if passenger != null:
		var component: Dictionary = _boarding_land_component(sim, _nav(sim), passenger.pos)
		if component.is_empty() or not _boarding_same_component(component, land): return false
	if not _nav(sim).water_clear(sim, water, sim._radius(ship), _draft(sim, ship), int(ship.id), false): return false
	if absf(sim._height(land) - MapData.water_surface_y(sim.map, water)) > 1.25: return false
	var shoreline: Vector2 = land.lerp(water, 0.5)
	if not sim._land(land.lerp(shoreline, 0.5)) or not _nav(sim).is_water(water.lerp(shoreline, 0.5)): return false
	return _crossing_clear(sim, land, water, land_radius, passenger_id)

static func _crossing_clear(sim, land: Vector2, water: Vector2, radius: float, ignore: int) -> bool:
	# Footprint obstacles are checked across the short embarkation corridor,
	# including the exact shoreline. Terrain changes domain only once along it.
	for n in range(7):
		var point: Vector2 = land.lerp(water, float(n) / 6.0)
		if not sim._building_clear(point, radius, ignore): return false
	return true
