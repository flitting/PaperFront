extends RefCounted

## One inexpensive intent line per selected unit. Navigation geometry and
## queued orders are deliberately not traversed by this display helper.
const MOVE_COMMANDS := ["move", "force_move", "attack_move", "patrol", "attack", "force_attack", "capture", "board", "repair_unit", "repair_building", "rescue", "deploy_outpost", "resume_outpost", "repair_bridge", "land", "unload_move", "return"]

static func selected_routes(entities: Dictionary, selection: Array, rules: Dictionary, viewer_team: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var squads: Dictionary = {}
	for id in selection:
		var entity: Dictionary = entities.get(id, {})
		if entity.is_empty() or str(entity.get("kind", "")) != "unit" or int(entity.get("transport_id", -1)) > 0 or float(entity.get("hp", 1.0)) <= 0.0: continue
		if int(entity.get("team", -1)) != viewer_team: continue
		var squad: int = int(entity.get("squad_id", -1))
		if squad >= 0:
			if squads.has(squad): continue
		var spec: Dictionary = rules.units.get(entity.get("spec", ""), {})
		var routes: Array[Dictionary] = entity_routes(entity, spec, entities)
		if not routes.is_empty() and squad >= 0: squads[squad] = true
		for route in routes:
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
	var destination: Vector2 = Vector2.INF
	if air:
		if str(entity.get("flight_state", "")) == "returning":
			kind = "return"
			destination = _destination({"kind": "return"}, entities, entity)
		elif str(entity.get("flight_state", "")) not in ["rearming", "stranded"] and not commands.is_empty():
			destination = _destination(commands[0], entities, entity)
	else:
		# The current navigation goal can be an approach point near a target.
		# Use it for movement, including autonomous harvesting and naval travel.
		if str(entity.get("state", "")) == "move" or (not commands.is_empty() and kind in MOVE_COMMANDS):
			destination = entity.get("naval_path_goal", Vector2.INF) if str(spec.get("domain", "ground")) == "naval" else entity.get("path_goal", Vector2.INF)
			if not destination.is_finite() and not commands.is_empty(): destination = _destination(commands[0], entities, entity)
	var current := PackedVector2Array([entity.pos])
	_append_distinct(current, destination)
	if current.size() == 2: result.append({"points": current, "kind": kind, "planned": true, "air": air})
	return result

static func _append_distinct(points: PackedVector2Array, point: Vector2) -> void:
	if point.is_finite() and (points.is_empty() or points[points.size() - 1].distance_squared_to(point) > .0001): points.append(point)

static func ground_points(points: PackedVector2Array, map: Dictionary, lift: float = .09, domain: String = "ground") -> PackedVector3Array:
	var result := PackedVector3Array()
	if points.is_empty(): return result
	for point: Vector2 in [points[0], points[points.size() - 1]]:
		result.append(Vector3(point.x, MapData.entity_surface_y(map, point, domain) + lift, point.y))
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
