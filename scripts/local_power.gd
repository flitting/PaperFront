extends RefCounted

# Headquarters supply only complete consumers in their own nearby footprint.
# Local reservations are removed from global demand before the global grid is
# evaluated, so an isolated remote factory cannot spend unused headquarters power.
static func summary(sim, team: int) -> Dictionary:
	var global_supply: float = 0.0
	var total_demand: float = 0.0
	var local_supply: float = 0.0
	var local_used: float = 0.0
	var sources: Array[Dictionary] = []
	var consumers: Array[Dictionary] = []
	var local_served: Dictionary = {}
	for entity: Dictionary in sim._building_entities:
		if int(entity.team) != team or not _active(sim, entity): continue
		var info: Dictionary = sim.data_for(entity.spec)
		var value: float = float(info.get("power", 0.0))
		global_supply += maxf(0.0, value)
		var capacity: float = maxf(0.0, float(info.get("local_power", 0.0)))
		var radius: float = maxf(0.0, float(info.get("local_power_radius", 0.0)))
		if capacity > 0.0 and radius > 0.0:
			sources.append({"id":int(entity.id), "pos":entity.pos, "capacity":capacity, "radius":radius})
			local_supply += capacity
		if value < 0.0:
			consumers.append({"id":int(entity.id), "pos":entity.pos, "demand":-value})
			total_demand -= value
	sources.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.id) < int(b.id))
	for source: Dictionary in sources:
		var remaining: float = float(source.capacity)
		var nearby: Array[Dictionary] = []
		for consumer: Dictionary in consumers:
			if local_served.has(int(consumer.id)): continue
			var distance: float = (source.pos as Vector2).distance_squared_to(consumer.pos)
			if distance <= float(source.radius) * float(source.radius):
				nearby.append({"id":int(consumer.id), "demand":float(consumer.demand), "distance":distance})
		nearby.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if float(a.distance) != float(b.distance): return float(a.distance) < float(b.distance)
			return int(a.id) < int(b.id))
		for consumer: Dictionary in nearby:
			# A consumer must fit in full; partial reservations cannot run it.
			if float(consumer.demand) > remaining: continue
			remaining -= float(consumer.demand)
			local_used += float(consumer.demand)
			local_served[int(consumer.id)] = true
	var global_demand: float = maxf(0.0, total_demand - local_used)
	return {"global_supply":global_supply, "global_demand":global_demand,
		"local_supply":local_supply, "local_used":local_used,
		"total_demand":total_demand, "local_served":local_served,
		"global":Vector2(global_supply, global_demand),
		"display":Vector2(global_supply + local_used, total_demand)}

static func is_locally_powered(sim, entity: Dictionary, snapshot: Dictionary = {}) -> bool:
	if not _active(sim, entity): return false
	var info: Dictionary = sim.data_for(entity.spec)
	if float(info.get("local_power", 0.0)) > 0.0: return true
	if snapshot.is_empty(): snapshot = summary(sim, int(entity.team))
	return snapshot.get("local_served", {}).has(int(entity.id))

static func generation(sim, entity: Dictionary) -> float:
	if not _active(sim, entity): return 0.0
	var info: Dictionary = sim.data_for(entity.spec)
	return maxf(0.0, float(info.get("power", 0.0))) + maxf(0.0, float(info.get("local_power", 0.0)))

static func _active(sim, entity: Dictionary) -> bool:
	return str(entity.get("kind", "")) == "building" and float(entity.get("hp", 0.0)) > 0.0 and float(entity.get("construct_remaining", 0.0)) <= 0.0 and float(entity.get("emp_until", 0.0)) <= float(sim.time)
