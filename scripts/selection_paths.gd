extends RefCounted

## Read the remaining authoritative route. Queued legs express command intent
## only; this helper never asks navigation to plan a path or mutates an order.
const MOVE_COMMANDS := ["move", "force_move", "attack_move", "patrol", "attack", "force_attack", "capture", "board", "repair_unit", "repair_building", "rescue", "deploy_outpost", "resume_outpost", "repair_bridge", "land", "unload_move", "return"]

static func selected_routes(entities: Dictionary, selection: Array, rules: Dictionary, viewer_team: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in selection:
		var entity: Dictionary = entities.get(id, {})
		if entity.is_empty() or str(entity.get("kind", "")) != "unit" or int(entity.get("transport_id", -1)) > 0 or float(entity.get("hp", 1.0)) <= 0.0: continue
		if int(entity.get("team", -1)) != viewer_team: continue
		var spec: Dictionary = rules.units.get(entity.get("spec", ""), {})
		for route in entity_routes(entity, spec, entities):
			route.id = int(id)
			route.team = int(entity.get("team", 0))
			route.domain = str(spec.get("domain", "ground"))
			result.append(route)
	return result

static func _destination(command: Dictionary, entities: Dictionary, entity: Dictionary = {}) -> Vector2:
	var kind: String = str(command.get("kind", ""))
	if kind not in MOVE_COMMANDS: return Vector2.INF
	if kind == "return": return entity.get("service_goal", entities.get(int(entity.get("home_airfield", -1)), {}).get("pos", Vector2.INF))
	var target: int = int(command.get("target", -1))
	if kind in ["attack", "force_attack", "capture", "board", "repair_unit", "repair_building", "rescue", "resume_outpost"] and target > 0:
		return entities.get(target, {}).get("pos", Vector2.INF)
	return command.get("pos", Vector2.INF)

static func entity_routes(entity: Dictionary, spec: Dictionary, entities: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var commands: Array = entity.get("commands", [])
	var air: bool = str(spec.get("domain", "ground")) == "air"
	var kind: String = str(commands[0].get("kind", "move")) if not commands.is_empty() else "move"
	var returning: bool = air and str(entity.get("flight_state", "")) == "returning"
	var servicing: bool = air and str(entity.get("flight_state", "")) == "rearming"
	var current := PackedVector2Array([entity.pos])
	if air:
		if returning:
			kind = "return"
			_append_distinct(current, _destination({"kind": "return"}, entities, entity))
		elif str(entity.get("flight_state", "")) not in ["rearming", "stranded"] and not commands.is_empty():
			_append_distinct(current, _destination(commands[0], entities, entity))
	else:
		for point in entity.get("path", []):
			if point is Vector2: _append_distinct(current, point)
	if current.size() > 1: result.append({"points": current, "kind": kind, "planned": true, "air": air})
	# The first command is already represented by the remaining path. Following
	# destinations have no planned geometry yet, so use a lighter dashed leg.
	var anchor: Vector2 = current[current.size() - 1] if returning or servicing else _destination(commands[0], entities, entity) if not commands.is_empty() else entity.pos
	if not anchor.is_finite(): anchor = current[current.size() - 1]
	for index in range(0 if returning or servicing else 1, commands.size()):
		var destination: Vector2 = _destination(commands[index], entities, entity)
		if not destination.is_finite(): continue
		var points := PackedVector2Array([anchor])
		_append_distinct(points, destination)
		if points.size() > 1: result.append({"points": points, "kind": str(commands[index].kind), "planned": false, "air": air})
		anchor = destination
	return result

static func _append_distinct(points: PackedVector2Array, point: Vector2) -> void:
	if point.is_finite() and (points.is_empty() or points[points.size() - 1].distance_squared_to(point) > .0001): points.append(point)

static func ground_points(points: PackedVector2Array, map: Dictionary, lift: float = .09, domain: String = "ground") -> PackedVector3Array:
	var result := PackedVector3Array()
	if points.is_empty(): return result
	for index in range(points.size() - 1):
		var start: Vector2 = points[index]
		var finish: Vector2 = points[index + 1]
		# Sample through terrain cells: ramps and intermediate plateaus must stay
		# grounded, even when the navigator smoothed a long straight segment.
		var steps: int = maxi(1, ceili(start.distance_to(finish) / .45))
		for step in range(steps):
			var point: Vector2 = start.lerp(finish, float(step) / float(steps))
			result.append(Vector3(point.x, MapData.entity_surface_y(map, point, domain) + lift, point.y))
	var last: Vector2 = points[points.size() - 1]
	result.append(Vector3(last.x, MapData.entity_surface_y(map, last, domain) + lift, last.y))
	return result

static func dashed_segments(points: PackedVector2Array, dash: float = 8.0, gap: float = 5.0) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var phase: float = 0.0
	var period: float = maxf(dash + gap, .01)
	for index in range(points.size() - 1):
		var start: Vector2 = points[index]
		var difference: Vector2 = points[index + 1] - start
		var length: float = difference.length()
		if length < .001: continue
		var cursor: float = 0.0
		while cursor < length - .001:
			var remaining: float = (dash - phase) if phase < dash else (period - phase)
			if remaining < .001:
				phase = dash if phase < dash else 0.0
				continue
			var end: float = minf(cursor + remaining, length)
			if phase < dash and end > cursor:
				result.append(PackedVector2Array([start + difference * (cursor / length), start + difference * (end / length)]))
			phase = fposmod(phase + end - cursor, period)
			cursor = end
	return result
