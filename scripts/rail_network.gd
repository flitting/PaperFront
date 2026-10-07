extends RefCounted
const Orientation=preload("res://scripts/building_orientation.gd")

## Owner-scoped, acyclic orthogonal rail graph. Every placement path uses the
## same validator; rails are traversable infrastructure, never solid buildings.
const DIRECTIONS := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const OPPOSITE := [2, 3, 0, 1]
var cells: Dictionary = {}
var revision: int = 0
const TARGET_TREE_LIMIT: int = 32
const VALIDATED_ROUTE_LIMIT: int = 1024
# Cached arrays belong to this navigator; callers receive independent arrays
# because movement consumes its route with pop_front(). Radius keys stay floats,
# and infantry/vehicle profiles remain separate even at the same radius.
var _target_trees: Dictionary = {}
var _validated_routes: Dictionary = {}
var _validated_route_count: int = 0
var _validation_revision: int = -1

static func is_rail(info: Dictionary) -> bool:
	return str(info.get("role", "")) in ["rail", "rail_junction"]

static func rail_only(info: Dictionary) -> bool:
	return bool(info.get("rail_only", false)) or (info.get("faction", "") == "iron" and info.get("art", "") == "harvester")

static func key(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x), floori(pos.y))

static func center(cell: Vector2i) -> Vector2:
	return Vector2(cell) + Vector2.ONE * .5

static func ports(role: String, rotation: int) -> int:
	return 15 ^ (1 << ((3 + rotation) % 4)) if role == "rail_junction" else 15

func rebuild(sim) -> void:
	cells.clear()
	revision += 1
	_target_trees.clear()
	_validated_routes.clear()
	_validated_route_count = 0
	_validation_revision = -1
	for e: Dictionary in sim._building_entities:
		var info: Dictionary = sim.data_for(e.spec)
		if not is_rail(info) or float(e.hp) <= 0: continue
		e.rail_ports = ports(str(info.role), int(e.get("rail_rotation", 0)))
		cells[key(e.pos)] = e
	for e: Dictionary in cells.values():
		e.rail_mask = 0
		for direction in range(4):
			var other: Dictionary = cells.get(key(e.pos) + DIRECTIONS[direction], {})
			if linked(e, other, direction): e.rail_mask |= 1 << direction

func linked(a: Dictionary, b: Dictionary, direction: int) -> bool:
	return not b.is_empty() and int(a.team) == int(b.team) and (int(a.rail_ports) & (1 << direction)) != 0 and (int(b.rail_ports) & (1 << OPPOSITE[direction])) != 0

func at(team: int, pos: Vector2) -> Dictionary:
	var rail: Dictionary = cells.get(key(pos), {})
	return rail if not rail.is_empty() and int(rail.team) == team and float(rail.hp) > 0 and float(rail.get("construct_remaining", 0)) <= 0 else {}

func usable(sim, e: Dictionary, pos: Vector2) -> bool:
	return e.get("kind", "") == "unit" and not sim._is_air(e) and not sim._is_naval(e) and not at(int(e.team), pos).is_empty()

func site_error(sim, team: int, info: Dictionary, pos: Vector2, rotation: int = 0, extra: Dictionary = {}) -> String:
	if not sim._in_bounds(pos): return "铁路超出地图边界"
	if not sim._land(pos) or not sim._terrain_clear(pos, .5): return "铁路需要合法地面、斜坡或完整桥面，不能跨海"
	var bridge_id: int = sim.bridge_at(pos)
	if bridge_id >= 0 and not bool(sim._bridge_by_id(bridge_id).get("alive", false)): return "桥梁已毁，不能铺设铁路"
	var cell: Vector2i = key(pos)
	if cells.has(cell) or extra.has(cell): return "此格已有铁路"
	for building: Dictionary in sim._building_entities:
		if is_rail(sim.data_for(building.spec)) or float(building.hp) <= 0: continue
		var half: float = float(sim.data_for(building.spec).size) * .5
		if absf(building.pos.x - pos.x) < half + .5 and absf(building.pos.y - pos.y) < half + .5: return "铁路与建筑占地重叠"
	for mine: Dictionary in sim.mines:
		if sim._circle_rect(pos, .48, mine.pos, sim.MINE_HALF): return "铁路不能覆盖矿物，需连接矿旁"
	for ruin: Dictionary in sim._nearby_ruins(pos, 1):
		if float(ruin.hp) > 0 and sim._circle_rect(pos, .48, ruin.pos, ruin.half): return "铁路位置有障碍"
	var graph: Dictionary = cells.duplicate()
	graph.merge(extra)
	var candidate: Dictionary = {"team":team,"pos":pos,"rail_ports":ports(str(info.role),rotation),"role":str(info.role)}
	var neighbors: Array[Vector2i] = []
	for direction in range(4):
		var other: Dictionary = graph.get(cell + DIRECTIONS[direction], {})
		if other.is_empty(): continue
		if not linked(candidate, other, direction): return "无合法连接的铁路必须至少间隔一格"
		if not sim._segment_terrain(pos, other.pos): return "铁路连接不能穿越陡崖或断桥"
		var other_role: String = str(other.get("role", sim.data_for(str(other.get("spec", ""))).get("role", "rail")))
		if str(info.role) == "rail_junction" and other_role == "rail_junction": return "岔道口之间必须通过普通铁路连接"
		var degree: int = 1
		for index in range(4):
			if linked(other, graph.get(key(other.pos) + DIRECTIONS[index], {}), index): degree += 1
		if degree > (3 if other_role == "rail_junction" else 2): return "普通铁路最多连接两个方向，岔道最多三个端口"
		neighbors.append(cell + DIRECTIONS[direction])
	if neighbors.size() > (3 if str(info.role) == "rail_junction" else 2): return "普通铁路不能形成三叉或四叉"
	# Adding one vertex creates a cycle iff two neighbors already share a component.
	var seen: Dictionary = {}
	for neighbor: Vector2i in neighbors:
		if seen.has(neighbor): return "铁路网络禁止成环（包括经过岔道的环）"
		var pending: Array[Vector2i] = [neighbor]
		while not pending.is_empty():
			var cursor: Vector2i = pending.pop_back()
			if seen.has(cursor): continue
			seen[cursor] = true
			for direction in range(4):
				var next: Vector2i = cursor + DIRECTIONS[direction]
				if not seen.has(next) and linked(graph[cursor], graph.get(next, {}), direction): pending.append(next)
	return ""

func batch_error(sim, team: int, info: Dictionary, points: Array, rotation: int = 0) -> String:
	var proposed: Dictionary = {}
	for pos: Vector2 in points:
		var error: String = site_error(sim, team, info, pos, rotation, proposed)
		if not error.is_empty(): return error
		proposed[key(pos)] = {"team":team,"pos":pos,"rail_ports":ports(str(info.role),rotation),"role":str(info.role)}
	return ""

func path(team: int, start: Vector2, goal: Vector2) -> Array:
	var first: Dictionary = at(team, start)
	var last: Dictionary = at(team, goal)
	if first.is_empty() or last.is_empty(): return []
	var source: Vector2i = key(start)
	var target: Vector2i = key(goal)
	if source == target: return [center(source)]
	# The legal graph is acyclic, so reversing BFS preserves its unique route.
	# One destination tree serves a whole group instead of searching per unit.
	var tree_key := Vector3i(team, target.x, target.y)
	if not _target_trees.has(tree_key):
		if _target_trees.size() >= TARGET_TREE_LIMIT: _target_trees.clear()
		_target_trees[tree_key] = _target_tree(team, target)
	var previous: Dictionary = _target_trees[tree_key]
	if not previous.has(source): return []
	var answer: Array = [center(source)]
	var cell: Vector2i = source
	while cell != target:
		cell = previous[cell]
		answer.append(center(cell))
	return answer

func _target_tree(team: int, target: Vector2i) -> Dictionary:
	var pending: Array[Vector2i] = [target]
	var previous: Dictionary = {target:target}
	var head: int = 0
	while head < pending.size():
		var cell: Vector2i = pending[head]
		head += 1
		for direction in range(4):
			var next: Vector2i = cell + DIRECTIONS[direction]
			if previous.has(next) or not linked(cells[cell], at(team, center(next)), direction): continue
			previous[next] = cell
			pending.append(next)
	return previous

func traversable_path(sim, e: Dictionary, start: Vector2, goal: Vector2) -> Array:
	var geometry_revision: int = int(sim._static_geometry_revision)
	if geometry_revision != _validation_revision or _validated_route_count >= VALIDATED_ROUTE_LIMIT:
		_validated_routes.clear()
		_validated_route_count = 0
		_validation_revision = geometry_revision
	var team: int = int(e.team)
	if at(team, start).is_empty() or at(team, goal).is_empty(): return []
	var radius: float = sim._radius(e)
	var profile_key := Vector2i(team, 1 if sim._query_is_infantry(int(e.id)) else 0)
	if not _validated_routes.has(radius): _validated_routes[radius] = {}
	var profiles: Dictionary = _validated_routes[radius]
	if not profiles.has(profile_key): profiles[profile_key] = {}
	var routes: Dictionary = profiles[profile_key]
	var source: Vector2i = key(start)
	var target: Vector2i = key(goal)
	var route_key := Vector4i(source.x, source.y, target.x, target.y)
	if not routes.has(route_key):
		var candidate: Array = path(team, start, goal)
		var valid: bool = not candidate.is_empty()
		var previous: Vector2 = center(source)
		for point: Vector2 in candidate:
			if not sim._standing(point, radius, int(e.id), false) or not sim._segment_static(previous, point, radius, int(e.id)):
				valid = false
				break
			previous = point
		routes[route_key] = candidate.duplicate() if valid else []
		_validated_route_count += 1
	var route: Array = routes[route_key]
	if route.is_empty(): return []
	# Subcell origins are never covered by a cell-keyed result. Recheck the real
	# start connector for every caller; only immutable center-to-center legs share.
	if not sim._segment_static(start, route[0], radius, int(e.id)): return []
	return route.duplicate()

func carrier_radius(sim, building: Dictionary) -> float:
	var faction: String = str(sim.data_for(building.spec).get("faction", "iron"))
	return float(sim.data_for(faction + "_harvester").get("radius", 1.0))

func mining_reach(sim, building: Dictionary) -> float:
	return carrier_radius(sim, building) + float(sim._eco("harvester_mining_margin", 1.4))

func nearest_connected(sim, e: Dictionary, desired: Vector2, reach: float) -> Vector2:
	var answer := Vector2.INF
	var best: float = INF
	for track: Dictionary in cells.values():
		if int(track.team) != int(e.team) or track.pos.distance_to(desired) > reach: continue
		var route: Array = traversable_path(sim, e, e.pos, track.pos)
		if route.is_empty() or not sim._standing(track.pos, sim._radius(e), int(e.id), false): continue
		var cost: float = float(route.size()) + track.pos.distance_to(desired)
		if cost < best:
			best = cost
			answer = track.pos
	return answer

func exit_cell(sim, building: Dictionary) -> Vector2:
	var half: float = float(sim.data_for(building.spec).size) * .5
	var front: Vector2 = Orientation.front(building)
	var desired: Vector2 = Orientation.point(building,Vector2(0,half+carrier_radius(sim,building)+.15))
	var result: Vector2 = center(key(desired))
	if front.x > .5: result.x=ceilf(desired.x-.5)+.5
	elif front.x < -.5: result.x=floorf(desired.x-.5)+.5
	elif front.y > .5: result.y=ceilf(desired.y-.5)+.5
	else: result.y=floorf(desired.y-.5)+.5
	return result

func spawn_point(sim, building: Dictionary, spec: String) -> Vector2:
	var point: Vector2 = exit_cell(sim, building)
	if not at(int(building.team), point).is_empty() and sim._standing(point, float(sim.data_for(spec).get("radius", 1.0)), -1, false):
		building.erase("rail_waiting")
		building.state = "idle"
		return point
	building.rail_waiting = true
	building.state = "waiting_rail"
	return Vector2.INF

func destroy_bridge(sim, bounds: Array) -> void:
	for e: Dictionary in cells.values():
		if sim._point_bounds(e.pos, bounds): e.hp = 0.0
	rebuild(sim)

func route_for(sim, e: Dictionary, goal: Vector2) -> Array:
	if rail_only(sim.data_for(e.spec)): return traversable_path(sim, e, e.pos, goal)
	if not at(int(e.team), e.pos).is_empty() and key(e.pos) == key(goal): return [goal]
	# Sparse access connectors plus a small boarding/alighting cost favor useful
	# rail journeys without making a unit pause on entering or leaving a track.
	var starts: Array = []
	var ends: Array = []
	for track: Dictionary in cells.values():
		if int(track.team) != int(e.team) or float(track.get("construct_remaining", 0)) > 0: continue
		starts.append(track.pos)
		ends.append(track.pos)
	starts.sort_custom(func(a:Vector2,b:Vector2):return a.distance_squared_to(e.pos)<b.distance_squared_to(e.pos))
	ends.sort_custom(func(a:Vector2,b:Vector2):return a.distance_squared_to(goal)<b.distance_squared_to(goal))
	var best: float = e.pos.distance_to(goal)
	var answer: Array = []
	var transition: float = float(sim._eco("rail_transition_cost", .35))
	var transitions: int = (1 if at(int(e.team), e.pos).is_empty() else 0) + (1 if at(int(e.team), goal).is_empty() else 0)
	for start: Vector2 in starts.slice(0, 5):
		if not sim._segment_static(e.pos, start, sim._radius(e), int(e.id)): continue
		for finish: Vector2 in ends.slice(0, 5):
			if not sim._segment_static(finish, goal, sim._radius(e), int(e.id)): continue
			var route: Array = traversable_path(sim, e, start, finish)
			if route.is_empty(): continue
			var cost: float = e.pos.distance_to(start) + float(route.size() - 1) * .5 + finish.distance_to(goal) + transition * transitions
			if cost + .05 < best:
				best = cost
				answer = route
				if finish.distance_to(goal) > .01: answer.append(goal)
	return answer

func movement(sim, e: Dictionary, goal: Vector2, delta: float) -> Dictionary:
	var restricted: bool = rail_only(sim.data_for(e.spec))
	if cells.is_empty() and not restricted: return {"handled":false}
	if not goal.is_finite(): return {"handled":true,"arrived":false}
	if e.get("rail_goal", Vector2.INF) != goal or int(e.get("rail_revision", -1)) != revision or int(e.get("rail_geometry_revision", -1)) != int(sim._static_geometry_revision):
		e.rail_route = route_for(sim, e, goal)
		e.rail_goal = goal
		e.rail_revision = revision
		e.rail_geometry_revision = int(sim._static_geometry_revision)
	var route: Array = e.get("rail_route", [])
	if route.is_empty():
		if restricted:
			e.state = "waiting_rail"
			return {"handled":true,"arrived":false}
		return {"handled":false}
	var remaining: float = delta
	while remaining > .00001 and not route.is_empty():
		var next_goal: Vector2 = route[0]
		if e.pos.distance_to(next_goal) < .001:
			route.pop_front()
			continue
		var on_rail: bool = not at(int(e.team), e.pos).is_empty()
		var destination_rail: bool = not at(int(e.team), next_goal).is_empty()
		if restricted and (not on_rail or not destination_rail):
			e.rail_revision = -1
			e.state = "waiting_rail"
			return {"handled":true,"arrived":false}
		var cell_delta: Vector2i = key(next_goal) - key(e.pos)
		var fast: bool = on_rail and destination_rail and (absi(cell_delta.x) + absi(cell_delta.y) <= 1)
		if restricted and not fast:
			e.rail_revision = -1
			return {"handled":true,"arrived":false}
		var speed: float = float(sim.data_for(e.spec).speed) * (2.0 if fast else 1.0)
		var distance: float = minf(speed * remaining, e.pos.distance_to(next_goal))
		var next: Vector2 = e.pos.move_toward(next_goal, distance)
		if not sim._movement_clear(e, e.pos, next, true):
			e.state = "waiting"
			return {"handled":true,"arrived":false}
		var original: Vector2 = e.pos
		e.alpha = rad_to_deg((next - original).angle())
		e.pos = next
		e.motion = speed
		e.state = "move"
		sim._spatial_move(e, original, next)
		remaining -= distance / maxf(speed, .001)
		if e.pos.distance_to(next_goal) < .001: route.pop_front()
	var arrived: bool = route.is_empty() and e.pos.distance_to(goal) < .55
	if arrived: e.state = "idle"
	return {"handled":true,"arrived":arrived}

func auto_refinery(sim, building: Dictionary) -> void:
	if str(sim.data_for(building.spec).get("faction", "")) != "iron" or not sim.rules.buildings.has("iron_rail"): return
	if bool(building.get("rail_auto_done", false)) or float(building.get("rail_auto_retry", 0.0)) > float(sim.time): return
	building.rail_auto_done = true
	var start: Vector2 = exit_cell(sim, building)
	var info: Dictionary = sim.data_for("iron_rail")
	var ores: Array = []
	for ore: Dictionary in sim.mines:
		if ore.pos.distance_to(building.pos) <= float(sim._eco("rail_auto_mine_range", 10)) and int(ore.get("drill", -1)) < 0: ores.append(ore)
	var first_error: String = site_error(sim, int(building.team), info, start)
	if not first_error.is_empty() and at(int(building.team), start).is_empty():
		building.rail_auto_done = false
		building.rail_auto_error = first_error
		building.rail_auto_retry = float(sim.time) + 5.0
		sim._notice("处理厂出口无法铺轨：" + first_error)
		return
	if ores.is_empty():
		if at(int(building.team), start).is_empty(): sim._spawn(int(building.team), "iron_rail", start, true)
		return
	# Bounded breadth-first path search; each frontier carries its provisional
	# graph, so even automatic turning/merging obeys the placement validator.
	var pending: Array = [[start]]
	var visited: Dictionary = {key(start):true}
	var route: Array = []
	var head: int = 0
	while head < pending.size() and head < 1600:
		var current: Array = pending[head]
		head += 1
		var end: Vector2 = current.back()
		for ore: Dictionary in ores:
			if end.distance_to(ore.pos) <= mining_reach(sim, building) and sim._standing(end, carrier_radius(sim, building), -1, false): route = current; break
		if not route.is_empty(): break
		if current.size() > 28: continue
		var proposed: Dictionary = {}
		for point: Vector2 in current:
			if not cells.has(key(point)): proposed[key(point)] = {"team":int(building.team),"pos":point,"rail_ports":15,"role":"rail"}
		for direction: Vector2i in DIRECTIONS:
			var next: Vector2 = end + Vector2(direction)
			if visited.has(key(next)) or next.distance_to(building.pos) > 13: continue
			if not site_error(sim, int(building.team), info, next, 0, proposed).is_empty(): continue
			if not sim._standing(next, carrier_radius(sim, building), -1, false) or not sim._segment_static(end, next, carrier_radius(sim, building), -1): continue
			visited[key(next)] = true
			var extended: Array = current.duplicate()
			extended.append(next)
			pending.append(extended)
	if route.is_empty():
		if at(int(building.team), start).is_empty(): sim._spawn(int(building.team), "iron_rail", start, true)
		sim._notice("附近矿脉没有合法自动铁路路线，请手动接轨")
		return
	for point: Vector2 in route:
		if not cells.has(key(point)): sim._spawn(int(building.team), "iron_rail", point, true)

func ai_place_refinery(sim, team: int, channel: String) -> bool:
	var order: Dictionary = sim.order_for_team(team, channel)
	if order.is_empty(): return false
	var candidates: Array = []
	var home: Vector2 = sim._team_start(team)
	var half: float = float(sim.data_for(order.spec).size) * .5
	for ore: Dictionary in sim.mines:
		if int(ore.get("drill", -1)) >= 0: continue
		for distance: float in [half + 2.0, half + 4.0, 9.0]:
			for direction in range(24):
				var point: Vector2 = sim.snap_build_position(team, ore.pos + Vector2.from_angle(float(direction)*TAU/24.0)*distance, channel)
				if point.distance_to(ore.pos) > 10.0: continue
				candidates.append({"pos":point,"score":point.distance_squared_to(home)+point.distance_squared_to(ore.pos)})
	candidates.sort_custom(func(a:Dictionary,b:Dictionary):return float(a.score)<float(b.score))
	for candidate: Dictionary in candidates:
		if sim.placement_error(team, candidate.pos, channel).is_empty():
			var planned: Dictionary = {"spec":order.spec,"pos":candidate.pos,"team":team,"rotation_quarters":Orientation.quarters(order)}
			var outlet: Vector2 = exit_cell(sim, planned)
			if not site_error(sim, team, sim.data_for("iron_rail"), outlet).is_empty() or not sim._standing(outlet, carrier_radius(sim, planned), -1, false): continue
			return sim.place_building(team, candidate.pos, channel).is_empty()
	return false

func ai_connect_factory(sim, building: Dictionary) -> bool:
	var team: int = int(building.team)
	var start: Vector2 = exit_cell(sim, building)
	var targets: Dictionary = {}
	for track: Dictionary in cells.values():
		if int(track.team) != team: continue
		for ore: Dictionary in sim.mines:
			if int(ore.get("drill", -1)) < 0 and track.pos.distance_to(ore.pos) <= mining_reach(sim, building):
				targets[key(track.pos)] = true
	var mover: Dictionary = {"id":-1,"team":team,"radius":carrier_radius(sim, building)}
	for target: Vector2i in targets:
		if not traversable_path(sim, mover, start, center(target)).is_empty(): return true
	if targets.is_empty(): return false
	if float(building.get("rail_ai_retry", 0.0)) > float(sim.time): return false
	building.rail_ai_retry = float(sim.time) + 8.0
	var info: Dictionary = sim.data_for("iron_rail")
	if not cells.has(key(start)) and not site_error(sim, team, info, start).is_empty(): return false
	var pending: Array = [[start]]
	var visited: Dictionary = {key(start):true}
	var route: Array = []
	var head: int = 0
	while head < pending.size() and head < 1800:
		var current: Array = pending[head]
		head += 1
		var end: Vector2 = current.back()
		if targets.has(key(end)): route = current; break
		if current.size() > 45: continue
		var proposed: Dictionary = {}
		for point: Vector2 in current:
			if not cells.has(key(point)): proposed[key(point)] = {"team":team,"pos":point,"rail_ports":15,"role":"rail"}
		var previous: Dictionary = cells.get(key(end), proposed.get(key(end), {}))
		for direction in range(4):
			var next: Vector2 = end + Vector2(DIRECTIONS[direction])
			if visited.has(key(next)): continue
			if not sim._standing(next, carrier_radius(sim, building), -1, false) or not sim._segment_static(end, next, carrier_radius(sim, building), -1): continue
			if cells.has(key(next)):
				if not linked(previous, cells[key(next)], direction): continue
			elif not site_error(sim, team, info, next, 0, proposed).is_empty(): continue
			visited[key(next)] = true
			var extended: Array = current.duplicate()
			extended.append(next)
			pending.append(extended)
	if route.is_empty(): return false
	var cost: float = 0.0
	for point: Vector2 in route:
		if not cells.has(key(point)): cost += float(info.cost)
	if float(sim.money[team]) < cost: return false
	sim.money[team] -= cost
	for point: Vector2 in route:
		if not cells.has(key(point)): sim._spawn(team, "iron_rail", point, true)
	return true
