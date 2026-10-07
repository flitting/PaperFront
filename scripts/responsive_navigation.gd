extends RefCounted

## A short local movement intent while the immutable global route is pending.
## Positions stay continuous; actual steps use the normal collision/crush rules.
static func advance(sim, e: Dictionary, goal: Vector2, delta: float) -> bool:
	var radius: float = sim._radius(e)
	var offset: Vector2 = goal - e.pos
	if offset.length() <= maxf(.25, radius * .4):
		e.state = "idle"
		return true
	var direction: Vector2 = offset.normalized()
	var wanted: float = rad_to_deg(direction.angle())
	sim._turn(e, wanted, delta)
	if e.get("provisional_goal", Vector2.INF) != goal:
		e.provisional_goal = goal
		e.provisional_retry_at = 0.0
	if sim.time < float(e.get("provisional_retry_at", 0.0)):
		e.state = "waiting"
		return false
	var error: float = absf(wrapf(wanted - float(e.alpha), -180.0, 180.0))
	# Turning is already a visible command response. Do not drive backwards
	# toward an old heading while the new destination is behind the vehicle.
	if sim._is_ground_vehicle(e) and error > 90.0:
		e.state = "move"
		return false
	var stride: float = minf(float(sim.data_for(e.spec).speed) * delta, offset.length())
	if sim._is_ground_vehicle(e) and error > 10.0: stride *= .45
	if sim._query_is_infantry(int(e.id)):
		for building in sim._building_spatial.get(sim._bucket(e.pos), []):
			if sim.data_for(building.spec).get("role", "") == "barricade" and sim._circle_rect(e.pos, radius, building.pos, Vector2(.5, .5)):
				stride *= .35
				break
	var original: Vector2 = e.pos
	var next: Vector2 = original + direction * stride
	var clear: bool = sim._movement_clear(e, original, next, true)
	if not clear:
		# Reuse the bounded local avoidance service rather than launching a
		# second planner. Every selected step still checks the full footprint.
		var detour: Vector2 = sim._movement_detour(e, original, direction, stride)
		if detour.is_finite(): next = detour; clear = true
	if clear:
		sim._settle_crushing(e, next)
		e.pos = next
		sim._spatial_move(e, original, next)
		e.motion = original.distance_to(next)
		e.state = "move"
		e.stuck = 0.0
		sim.navigation_stats["provisional_steps"] = int(sim.navigation_stats.get("provisional_steps", 0)) + 1
	else:
		e.state = "waiting"
		e.provisional_retry_at = sim.time + .1
	return false


static func join_route(sim, start: Vector2, path: Array, radius: float, id: int) -> Array:
	# Join a nearby point on the checked route rather than steering back to its
	# old origin. Interior segments retain the worker's continuous validation.
	var previous: Vector2 = start
	var best: float = INF
	var join := Vector2.ZERO
	var segment := 0
	for index in range(mini(8, path.size())):
		var point: Vector2 = path[index]
		var candidate: Vector2 = point if index == 0 else Geometry2D.get_closest_point_to_segment(start, previous, point)
		var distance: float = start.distance_squared_to(candidate)
		if distance < best: best = distance; join = candidate; segment = index
		previous = point
	if not sim._segment_static(start, join, radius, id): return []
	var answer: Array = path.slice(segment)
	if start != join and join != answer[0]: answer.push_front(join)
	if not sim._segment_static(start, answer[0], radius, id): return []
	return answer
