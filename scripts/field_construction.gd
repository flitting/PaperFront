extends RefCounted

## Ground facilities keep their established approach. A water-only shipyard
## exposes the entire perimeter to engineers working from their own shore.
static func approach(sim, engineer: Dictionary, building: Dictionary) -> Vector2:
	var info: Dictionary = sim.data_for(str(building.spec))
	if str(info.get("role", "")) != "shipyard" or str(info.get("domain", "ground")) != "naval":
		return sim._refinery_approach(engineer, building)
	return shore_approach(sim, engineer, info, building.pos)

static func shore_approach(sim, engineer: Dictionary, info: Dictionary, center: Vector2) -> Vector2:
	var component: Dictionary = sim.NavalOperations._boarding_land_component(sim, sim.NavalOperations._nav(sim), engineer.pos)
	if component.is_empty(): return Vector2.INF
	var radius: float = sim._radius(engineer)
	var half: float = float(info.size) * 0.5
	var steps: int = maxi(1, ceili(float(info.size) / 0.25))
	var best: Vector2 = Vector2.INF
	var best_distance: float = INF
	for side: Vector2 in [Vector2.DOWN, Vector2.RIGHT, Vector2.LEFT, Vector2.UP]:
		var tangent := Vector2(-side.y, side.x)
		for index in range(steps + 1):
			var along: float = lerpf(-half, half, float(index) / float(steps))
			var point: Vector2 = center + side * (half + radius + 0.25) + tangent * along
			if not sim.NavalOperations._boarding_same_component(component, point) or not sim._standing(point, radius, int(engineer.id), false): continue
			var distance: float = (engineer.pos as Vector2).distance_squared_to(point)
			if distance < best_distance:
				best = point
				best_distance = distance
	return best
