extends RefCounted

## Air traffic uses continuous circles and free headings. Its collision layer
## contains aircraft only; terrain, buildings and surface units never enter it.
const CLEARANCE: float = 0.02
const DESTINATION_CLEARANCE: float = 0.06
const STEERING_ANGLE: float = PI / 12.0

static func fly_to(sim, aircraft: Dictionary, requested_goal: Vector2, delta: float, orbit: bool = false) -> bool:
	var goal: Vector2 = sim._air_goal(requested_goal)
	if not goal.is_finite(): return false
	var origin: Vector2 = aircraft.pos
	# Another order can occupy a previously free endpoint. Ordinary movement
	# may finish beside it; landing/service and combat approaches stay exact.
	var commands: Array = aircraft.get("commands", [])
	if aircraft.get("flight_state", "") not in ["returning", "rearming"] and not commands.is_empty() and commands[0].get("kind", "") in ["move", "attack_move", "patrol", "force_move"] and (commands[0].pos as Vector2).distance_squared_to(goal) < 0.000001 and origin.distance_to(goal) < maxf(3.0, sim._radius(aircraft) * 4.0) and not point_clear(sim, aircraft, goal):
		var alternative: Vector2 = destination(sim, aircraft, goal, [])
		if alternative.is_finite():
			commands[0].pos = alternative
			goal = alternative
	var offset: Vector2 = goal - origin
	if offset.length() <= 0.1:
		aircraft.motion = 0.0
		aircraft.state = "idle"
		return true
	var travel: float = minf(offset.length(), float(sim.data_for(aircraft.spec).speed) * maxf(delta, 0.0))
	if orbit: travel *= .65
	var direction: Vector2 = offset.normalized()
	var nearby: Array = _traffic(sim, origin, travel + _maximum_speed(sim) * maxf(delta, 0.0) + sim._radius(aircraft) + float(sim._max_entity_extent) + DESTINATION_CLEARANCE, int(aircraft.id))
	var movement: Vector2 = direction * travel
	if orbit:
		movement = _orbit_step(sim, aircraft, origin, direction, travel, nearby)
	elif not _motion_clear(sim, aircraft, origin, movement, nearby):
		var best: Vector2 = _trim_step(sim, aircraft, origin, movement, nearby)
		var best_progress: float = origin.distance_to(goal) - (origin + best).distance_to(goal)
		var preferred_side: int = int(aircraft.get("air_avoid_side", 1))
		# Both opposing aircraft prefer their own right, so head-on encounters
		# separate consistently instead of choosing the same world-space side.
		for turn in range(1, 12):
			var found: bool = false
			for side in [preferred_side, -preferred_side]:
				var candidate: Vector2 = sim._air_goal(origin + direction.rotated(float(turn * side) * STEERING_ANGLE) * travel) - origin
				if _motion_clear(sim, aircraft, origin, candidate, nearby):
					best = candidate
					aircraft.air_avoid_side = side
					found = true
					break
				var clipped: Vector2 = _trim_step(sim, aircraft, origin, candidate, nearby)
				var progress: float = origin.distance_to(goal) - (origin + clipped).distance_to(goal)
				if progress > best_progress + 0.001:
					best = clipped
					best_progress = progress
			if found: break
		movement = best
	var next: Vector2 = origin + movement
	if bool(sim._in_step):
		# Later aircraft check relative motion against the segment already
		# committed this tick, preventing crossing paths between clear endpoints.
		aircraft.air_motion_from = origin
		aircraft.air_motion_time = float(sim.time)
	aircraft.motion = movement.length() / maxf(delta, 0.001)
	aircraft.pos = next
	if orbit and movement.length_squared() > .000001: aircraft.air_loiter_direction = movement.normalized()
	aircraft.state = "move" if movement.length_squared() > 0.000001 else "waiting"
	if movement.length_squared() > 0.000001: sim._turn(aircraft, rad_to_deg(movement.angle()), delta)
	sim._spatial_move(aircraft, origin, next)
	return next.distance_to(goal) <= 0.1

## Stable tangent steering for idle circuits. Look ahead before touching
## traffic and retain velocity continuity, so avoidance cannot flip the plane
## backwards merely because the ideal point moved to the other side.
static func _orbit_step(sim, aircraft: Dictionary, origin: Vector2, desired: Vector2, travel: float, nearby: Array) -> Vector2:
	var previous: Vector2 = aircraft.get("air_loiter_direction", desired)
	var preferred: int = int(aircraft.get("air_avoid_side", 1))
	var look: float = maxf(travel, float(sim.data_for(aircraft.spec).speed)*.30)
	var best: Vector2 = Vector2.ZERO
	var best_score: float = -INF
	for angle: int in range(-6,7):
		var direction: Vector2 = previous.rotated(float(angle)*STEERING_ANGLE)
		var candidate: Vector2 = sim._air_goal(origin+direction*travel)-origin
		if not _motion_clear(sim,aircraft,origin,candidate,nearby): continue
		var ahead: Vector2 = sim._air_goal(origin+direction*look)-origin
		var clear_fraction: float = _trim_step(sim,aircraft,origin,ahead,nearby).length()/maxf(look,.001)
		var score: float = direction.dot(desired) + direction.dot(previous)*.65 + clear_fraction*1.7
		if angle*preferred<0: score-=.035
		if score>best_score:
			best_score=score
			best=candidate
			if angle!=0:aircraft.air_avoid_side=1 if angle>0 else -1
	return best

## Reserve separate endpoints for multi-aircraft movement commands. These
## points affect final parking only; flight between them remains unrestricted.
static func destination(sim, aircraft: Dictionary, requested: Vector2, reserved: Array) -> Vector2:
	var goal: Vector2 = sim._air_goal(requested)
	if not goal.is_finite(): return Vector2.INF
	var radius: float = sim._radius(aircraft)
	var ignore: int = int(aircraft.id)
	var goals: Array = reserved.duplicate()
	for other in sim.entities.values():
		if int(other.get("id", -1)) == ignore or other.get("kind", "") != "unit" or float(other.get("hp", 0.0)) <= 0.0 or not sim._is_air(other): continue
		for command in other.get("commands", []):
			if command.get("kind", "") in ["move", "attack_move", "patrol", "force_move"] and command.get("pos") is Vector2: goals.append({"pos": command.pos, "radius": sim._radius(other)})
	var point: Vector2 = _free_point(sim, goal, radius, ignore, goals)
	if point.is_finite(): reserved.append({"pos": point, "radius": radius})
	return point

static func spawn_point(sim, spec: String, origin: Vector2) -> Vector2:
	return _free_point(sim, origin, float(sim.data_for(spec).get("radius", 0.65)), -1, [])

static func point_clear(sim, aircraft: Dictionary, point: Vector2) -> bool:
	return _point_clear(sim, point, sim._radius(aircraft), int(aircraft.id), [])

static func _free_point(sim, origin: Vector2, radius: float, ignore: int, reserved: Array) -> Vector2:
	if _point_clear(sim, origin, radius, ignore, reserved): return origin
	var spacing: float = radius * 2.0 + DESTINATION_CLEARANCE
	for ring in range(1, 9):
		for index in range(16 * ring):
			var point: Vector2 = origin + Vector2.from_angle(float(index) * TAU / float(16 * ring)) * spacing * float(ring)
			if _point_clear(sim, point, radius, ignore, reserved): return point
	return Vector2.INF

static func _point_clear(sim, point: Vector2, radius: float, ignore: int, reserved: Array) -> bool:
	if not point.is_finite() or not sim._in_bounds(point): return false
	for other in _traffic(sim, point, radius + float(sim._max_entity_extent) + DESTINATION_CLEARANCE, ignore):
		var combined: float = radius + sim._radius(other) + DESTINATION_CLEARANCE
		if point.distance_squared_to(other.pos) < combined * combined: return false
	for slot in reserved:
		var combined: float = radius + float(slot.radius) + DESTINATION_CLEARANCE
		if point.distance_squared_to(slot.pos) < combined * combined: return false
	return true

static func _traffic(sim, origin: Vector2, reach: float, ignore: int) -> Array:
	var answer: Array = []
	for other in sim._nearby_entities(origin, reach):
		if int(other.id) == ignore or other.get("kind", "") != "unit" or float(other.get("hp", 0.0)) <= 0.0 or int(other.get("transport_id", -1)) > 0 or not sim._is_air(other): continue
		if bool(other.get("airborne", true)) or _moved_this_tick(sim, other): answer.append(other)
	return answer

static func _maximum_speed(sim) -> float:
	var speed: float = 0.0
	if not sim._air_specs.is_empty():
		for spec in sim._air_specs: speed = maxf(speed, float(sim.data_for(spec).get("speed", 0.0)))
	else:
		for info in sim.rules.get("units", {}).values():
			if info.get("domain", "ground") == "air": speed = maxf(speed, float(info.get("speed", 0.0)))
	return speed

static func _moved_this_tick(sim, other: Dictionary) -> bool:
	return bool(sim._in_step) and float(other.get("air_motion_time", -1.0)) == float(sim.time) and other.get("air_motion_from") is Vector2

static func _motion_clear(sim, aircraft: Dictionary, origin: Vector2, movement: Vector2, nearby: Array) -> bool:
	for other in nearby:
		var other_origin: Vector2 = other.air_motion_from if _moved_this_tick(sim, other) else other.pos
		var other_movement: Vector2 = other.pos - other_origin
		var combined: float = sim._radius(aircraft) + sim._radius(other) + CLEARANCE
		if _collision_time(origin - other_origin, movement - other_movement, combined) < 1.0: return false
	return true

static func _trim_step(sim, aircraft: Dictionary, origin: Vector2, movement: Vector2, nearby: Array) -> Vector2:
	var first_hit: float = 1.0
	for other in nearby:
		var other_origin: Vector2 = other.air_motion_from if _moved_this_tick(sim, other) else other.pos
		var relative_step: Vector2 = movement - (other.pos - other_origin)
		first_hit = minf(first_hit, _collision_time(origin - other_origin, relative_step, sim._radius(aircraft) + sim._radius(other) + CLEARANCE))
	var high: float = maxf(0.0, first_hit - 0.001 / maxf(movement.length(), 0.001))
	var candidate: Vector2 = movement * high
	if _motion_clear(sim, aircraft, origin, candidate, nearby): return candidate
	# Shortening our displacement changes relative velocity. Recheck every
	# resulting trajectory rather than clipping a moving-obstacle collision once.
	var low: float = 0.0
	for _probe in range(10):
		var middle: float = (low + high) * 0.5
		if _motion_clear(sim, aircraft, origin, movement * middle, nearby): low = middle
		else: high = middle
	return movement * low

static func _collision_time(relative: Vector2, movement: Vector2, radius: float) -> float:
	var c: float = relative.length_squared() - radius * radius
	var outward: float = relative.dot(movement)
	if c < -0.000001:
		# Legacy/debug deployments can begin overlapped. Permit only separation;
		# a regular legal trajectory can never enter this recovery branch.
		return 1.0 if outward >= -0.000001 and movement.length_squared() > 0.000001 else 0.0
	if outward >= 0.0: return 1.0
	var a: float = movement.length_squared()
	if a <= 0.000001: return 1.0
	var discriminant: float = outward * outward - a * c
	if discriminant <= 0.0: return 1.0
	return clampf((-outward - sqrt(discriminant)) / a, 0.0, 1.0)
