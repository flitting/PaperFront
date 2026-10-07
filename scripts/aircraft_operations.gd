extends RefCounted
const Orientation=preload("res://scripts/building_orientation.gd")

const AirNavigation = preload("res://scripts/air_navigation.gd")

## A landed aircraft is a stationary transport. Airfield service remains in the
## simulation; landing here never repairs, rearms, or changes its home airfield.
static func land_error(sim, aircraft: Dictionary, pos: Vector2) -> String:
	if aircraft.get("kind", "") != "unit" or not sim._is_air(aircraft): return "只有飞机可以降落"
	if bool(sim.data_for(aircraft.spec).get("permanent_air",false)): return "该航空单位始终留空，无需降落补给"
	if not pos.is_finite() or not sim._in_bounds(pos): return "降落地点超出地图"
	if not sim._standing(pos, sim._radius(aircraft), int(aircraft.id)): return "降落地点没有足够的空地"
	for other in sim.entities.values():
		if int(other.get("id", -1)) == int(aircraft.id) or other.get("kind", "") != "unit" or float(other.get("hp", 0.0)) <= 0.0 or not sim._is_air(other) or bool(other.get("airborne", true)): continue
		if pos.distance_to(other.pos) < _parking_radius(sim, aircraft) + _parking_radius(sim, other) + 0.18: return "降落地点已被其他飞机占用"
	return ""

## Four concrete apron positions inside the airport footprint.
static func _parking_radius(sim, aircraft: Dictionary) -> float:
	return sim._radius(aircraft)

static func slots(sim, field: Dictionary) -> Array[Vector2]:
	var span: float = minf(1.6, float(sim.data_for(field.spec).size) * .25)
	return [Orientation.point(field,Vector2(-span,-span)),Orientation.point(field,Vector2(span,-span)),Orientation.point(field,Vector2(-span,span)),Orientation.point(field,Vector2(span,span))]

static func production_slot(sim, field: Dictionary) -> Vector2:
	for point in slots(sim, field):
		if _slot_clear(sim, point, -1): return point
	return Vector2.INF

static func service_position(sim, aircraft: Dictionary, field: Dictionary) -> Vector2:
	var old_goal: Vector2 = aircraft.get("service_goal", Vector2.INF)
	var positions: Array[Vector2] = slots(sim, field)
	if old_goal in positions and _slot_clear(sim, old_goal, int(aircraft.id)): return old_goal
	for point in positions:
		if _slot_clear(sim, point, int(aircraft.id)): return point
	return Vector2.INF

static func _slot_clear(sim, point: Vector2, ignore: int) -> bool:
	if not sim._in_bounds(point): return false
	var radius: float = sim._radius(sim.entities[ignore]) if sim.entities.has(ignore) else 1.0
	for other in sim.entities.values():
		if int(other.id) == ignore or other.kind != "unit" or float(other.hp) <= 0 or not sim._is_air(other): continue
		if point.distance_to(other.pos) < sim._radius(other)+radius+.06: return false
		if str(other.get("flight_state", "")) in ["returning", "rearming"]:
			var goal: Vector2 = other.get("service_goal", Vector2.INF)
			if goal.is_finite() and point.distance_to(goal) < sim._radius(other)+radius+.06: return false
	return true

static func _service_clear(sim, aircraft: Dictionary, point: Vector2) -> bool:
	return _slot_clear(sim, point, int(aircraft.id))

## Holding a waypoint means circling that waypoint for fixed-wing aircraft.
## Service traffic and explicit routes retain sole ownership of their movement.
static func step_idle(sim, delta: float) -> void:
	for aircraft in sim.entities.values():
		if aircraft.kind != "unit" or not sim._is_air(aircraft) or str(aircraft.get("flight_state", "")) != "airborne": continue
		var info: Dictionary=sim.data_for(aircraft.spec)
		if bool(info.get("rotorcraft",false)) or bool(info.get("carrier_plane",false)): continue
		if not aircraft.commands.is_empty():
			aircraft.erase("loiter_center")
			aircraft.erase("air_loiter_direction")
			continue
		var weapon: Dictionary=sim.rules.weapons.get(str(info.get("weapon","")),{})
		if not weapon.is_empty() and sim._nearest_enemy(aircraft,float(weapon.range)+2.0)>=0:
			aircraft.erase("loiter_center")
			aircraft.erase("air_loiter_direction")
			continue
		var radius: float=3.4+float(int(aircraft.id)%3)*.6
		if not aircraft.has("loiter_center"):
			var radial:Vector2=Vector2.from_angle(deg_to_rad(float(aircraft.alpha))-PI*.5)
			aircraft.loiter_center=((aircraft.pos as Vector2)-radial*radius).clamp(Vector2.ONE*(radius+1.1),Vector2.ONE*(float(sim.map.size)-radius-1.1))
			aircraft.loiter_phase=((aircraft.pos as Vector2)-(aircraft.loiter_center as Vector2)).angle()
		var phase:float=float(aircraft.get("loiter_phase",0.0))+float(info.speed)*.65/radius*delta
		# Steer along the circuit from our actual position. A clock-driven point
		# can run past a blocked plane and pull it backwards on alternate ticks.
		var radial: Vector2 = (aircraft.pos as Vector2) - (aircraft.loiter_center as Vector2)
		if radial.length_squared() < .0001: radial = Vector2.from_angle(phase) * radius
		var direction: Vector2 = (-radial.normalized().orthogonal() + radial.normalized() * clampf((radius-radial.length())*3.0, -.85, .85)).normalized()
		var waypoint: Vector2 = aircraft.pos + direction * maxf(2.0, float(info.speed)*.4)
		aircraft.loiter_phase=phase
		AirNavigation.fly_to(sim,aircraft,waypoint,delta,true)
		aircraft.air_idle_time=0.0

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
	if not takeoff(sim, aircraft): return true
	return false

static func takeoff(sim, aircraft: Dictionary) -> bool:
	if aircraft.get("flight_state", "") != "landed": return bool(aircraft.get("airborne", true))
	if not AirNavigation.point_clear(sim, aircraft, aircraft.pos):
		aircraft.state = "waiting"
		return false
	aircraft.flight_state = "airborne"
	aircraft.flight_height = float(sim.data_for(aircraft.spec).get("flight_height", 4.0))
	sim._set_airborne(aircraft, true)
	aircraft.state = "move"
	sim.events.append({"kind": "takeoff", "id": aircraft.id, "team": aircraft.team, "pos": aircraft.pos})
	return true

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
		if not bool(aircraft.get("airborne", true)) and not takeoff(sim, aircraft): return false
		if not sim._fly_to(aircraft, goal, delta): return false
	if aircraft.get("flight_state", "") != "landed":
		aircraft.flight_state = "landed"
		aircraft.flight_height = 0.35
		sim._set_airborne(aircraft, false)
		aircraft.motion = 0.0
		aircraft.state = "landed"
		sim.events.append({"kind": "land", "id": aircraft.id, "team": aircraft.team, "pos": aircraft.pos})
	if complete_command: sim._finish_command(aircraft)
	return true
