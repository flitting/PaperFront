extends RefCounted

## A landed aircraft is a stationary transport. Airfield service remains in the
## simulation; landing here never repairs, rearms, or changes its home airfield.
static func land_error(sim, aircraft: Dictionary, pos: Vector2) -> String:
	if aircraft.get("kind", "") != "unit" or not sim._is_air(aircraft): return "只有飞机可以降落"
	if not pos.is_finite() or not sim._in_bounds(pos): return "降落地点超出地图"
	if not sim._standing(pos, sim._radius(aircraft), int(aircraft.id)): return "降落地点没有足够的空地"
	return ""

## Aircraft wings extend beyond their navigation radius. Reserve a tabletop
## footprint large enough for every current model while sharing one airport.
static func _parking_radius(sim, aircraft: Dictionary) -> float:
	return maxf(sim._radius(aircraft), 2.25)

## Keep a returning aircraft's first legal apron reservation across ticks.
## Four side-center slots serve a full airport before the wider side slots.
static func service_position(sim, aircraft: Dictionary, field: Dictionary) -> Vector2:
	var half: float = float(sim.data_for(field.spec).get("size", 1)) * 0.5
	var largest_radius: float = _parking_radius(sim, aircraft)
	for other in sim.entities.values():
		if int(other.get("id", -1)) != int(aircraft.id) and int(other.get("home_airfield", -1)) == int(field.id) and other.get("kind", "") == "unit" and float(other.get("hp", 0.0)) > 0.0 and sim._is_air(other):
			largest_radius = maxf(largest_radius, _parking_radius(sim, other))
	var clearance: float = largest_radius + 0.25
	var spacing: float = largest_radius * 2.0 + 0.3
	var old_goal: Vector2 = aircraft.get("service_goal", Vector2.INF)
	var apron_limit: float = half + largest_radius + 3.8
	if old_goal.is_finite() and old_goal.distance_to(field.pos) <= apron_limit and _service_clear(sim, aircraft, old_goal): return old_goal
	var preferred: int = posmod(int(aircraft.id), 4)
	for ring in range(3):
		var distance: float = half + clearance + float(ring) * 0.8
		for candidate in range(12):
			var slot: int = (preferred + candidate) % 12
			var along: float = 0.0 if slot < 4 else (spacing if slot < 8 else -spacing)
			var side: int = slot % 4
			var offset: Vector2
			match side:
				0: offset = Vector2(distance, along)
				1: offset = Vector2(-distance, along)
				2: offset = Vector2(along, distance)
				_: offset = Vector2(along, -distance)
			var point: Vector2 = field.pos + offset
			if _service_clear(sim, aircraft, point): return point
	return Vector2.INF

static func _service_clear(sim, aircraft: Dictionary, point: Vector2) -> bool:
	if not land_error(sim, aircraft, point).is_empty(): return false
	var radius: float = _parking_radius(sim, aircraft)
	for other in sim.entities.values():
		if int(other.get("id", -1)) == int(aircraft.id) or other.get("kind", "") != "unit" or float(other.get("hp", 0.0)) <= 0.0 or not sim._is_air(other): continue
		var other_radius: float = _parking_radius(sim, other)
		if not bool(other.get("airborne", true)) and point.distance_to(other.pos) < radius + other_radius + 0.18: return false
		if other.get("flight_state", "") == "returning":
			var reserved: Vector2 = other.get("service_goal", Vector2.INF)
			if reserved.is_finite() and point.distance_to(reserved) < radius + other_radius + 0.18: return false
	return true

static func step_landed(sim, aircraft: Dictionary) -> bool:
	if aircraft.get("flight_state", "") != "landed": return false
	var commands: Array = aircraft.get("commands", [])
	if commands.is_empty():
		aircraft.state = "landed"
		return true
	var command: Dictionary = commands[0]
	var kind: String = str(command.get("kind", ""))
	if kind in ["land", "unload_move"] and (aircraft.pos as Vector2).distance_to(command.pos) <= 0.1:
		return false
	if kind in ["stop", "hold"]:
		aircraft.state = "landed"
		return true
	takeoff(sim, aircraft)
	return false

static func takeoff(sim, aircraft: Dictionary) -> void:
	if aircraft.get("flight_state", "") != "landed": return
	aircraft.flight_state = "airborne"
	aircraft.flight_height = float(sim.data_for(aircraft.spec).get("flight_height", 4.0))
	aircraft.airborne = true
	aircraft.state = "move"
	sim.events.append({"kind": "takeoff", "id": aircraft.id, "team": aircraft.team, "pos": aircraft.pos})

## complete_command=false lets unload_move land and unload in one order.
static func step_land(sim, aircraft: Dictionary, command: Dictionary, delta: float, complete_command: bool = true) -> bool:
	var goal: Vector2 = command.pos
	var error: String = land_error(sim, aircraft, goal)
	if not error.is_empty():
		aircraft.state = "waiting"
		if not bool(command.get("blocked_notice", false)) and int(aircraft.team) == 0:
			sim._notice(error)
			command.blocked_notice = true
		return false
	if (aircraft.pos as Vector2).distance_to(goal) > 0.1:
		if not bool(aircraft.get("airborne", true)): takeoff(sim, aircraft)
		if not sim._fly_to(aircraft, goal, delta): return false
	if aircraft.get("flight_state", "") != "landed":
		aircraft.flight_state = "landed"
		aircraft.flight_height = 0.35
		aircraft.airborne = false
		aircraft.motion = 0.0
		aircraft.state = "landed"
		sim.events.append({"kind": "land", "id": aircraft.id, "team": aircraft.team, "pos": aircraft.pos})
	if complete_command: sim._finish_command(aircraft)
	return true
