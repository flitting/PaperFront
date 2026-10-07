extends RefCounted

const DEFENSE_ROLES := ["tower", "wall", "barricade", "rail", "rail_junction"]

static func channel_for(info: Dictionary) -> String:
	return "defense" if str(info.get("role", "")) in DEFENSE_ROLES else "normal"

## Radius is owned by the match's rules, including a loaded historical snapshot.
## Snapshots without the role table keep the original expands/one-radius policy.
static func radius_for(sim: RefCounted, info: Dictionary) -> float:
	return radius_in_rules(sim.rules, info)

static func radius_in_rules(rules: Dictionary, info: Dictionary) -> float:
	if rules.factions.get(str(info.get("faction", "")), {}).get("building_method", "") == "engineer" and info.get("role", "") not in ["hq", "barracks"]: return 0.0
	if info.has("construction_radius"): return float(info.construction_radius)
	var radii: Dictionary = rules.economy.get("construction_radii", {})
	if radii.is_empty():
		return float(rules.economy.get("build_radius", 12)) if bool(info.get("expands", false)) else 0.0
	return float(radii.get(str(info.get("role", "")), radii.get("default", 0.0)))

static func is_range_source(building: Dictionary, team: int) -> bool:
	return int(building.get("team", -1)) == team and building.get("kind", "") == "building" and float(building.get("hp", 0.0)) > 0.0 and float(building.get("construct_remaining", 0.0)) <= 0.0 and building.get("construction", {}).is_empty()

static func zones(sim: RefCounted, team: int) -> Array[Dictionary]:
	var answer: Array[Dictionary] = []
	for building: Dictionary in sim._building_entities:
		if not is_range_source(building, team): continue
		if sim.rules.factions.get(sim.factions[team], {}).get("building_method", "") == "engineer" and sim.data_for(building.spec).get("role", "") not in ["hq", "barracks"]: continue
		var info: Dictionary = sim.data_for(building.spec)
		var radius: float = radius_for(sim, info)
		if radius > 0.0:
			answer.append({"id": int(building.id), "pos": building.pos, "radius": radius, "role": str(info.get("role", ""))})
	return answer

static func covers(sim: RefCounted, team: int, pos: Vector2) -> bool:
	for building: Dictionary in sim._building_entities:
		if not is_range_source(building, team): continue
		if sim.rules.factions.get(sim.factions[team], {}).get("building_method", "") == "engineer" and sim.data_for(building.spec).get("role", "") not in ["hq", "barracks"]: continue
		var radius: float = radius_for(sim, sim.data_for(building.spec))
		if radius > 0.0 and (building.pos as Vector2).distance_squared_to(pos) <= radius * radius:
			return true
	return false

static func order_for(sim: RefCounted, team: int, channel: String = "normal") -> Dictionary:
	if team < 0 or team >= sim.factions.size(): return {}
	if channel not in ["normal", "defense"]: return {}
	return sim.defense_orders[team] if channel == "defense" else sim.building_orders[team]

static func advance(sim: RefCounted, team: int, channel: String, delta: float, multiplier: float) -> void:
	var order: Dictionary = order_for(sim, team, channel)
	if order.is_empty(): return
	if order.has("builder") and not sim._builder_valid(team, int(order.builder)):
		sim.cancel_build(team, channel)
		return
	if bool(order.ready) or (not sim._has_construction_base(team) and not order.has("builder")): return
	order.remaining = maxf(0.0, float(order.remaining) - delta * multiplier)
	order.progress = 1.0 - float(order.remaining) / maxf(float(order.total), 0.001)
	if float(order.remaining) <= 0.0:
		order.ready = true
		if team == 0: sim._notice("建筑就绪：" + str(sim.data_for(order.spec).name))
		sim.events.append({"kind":"building_ready", "team":team, "spec":order.spec, "pos":sim._team_start(team)})

static func refund(order: Dictionary) -> float:
	return float(order.get("cost", 0.0)) * float(order.get("remaining", 0.0)) / maxf(float(order.get("total", 0.0)), 0.001)
