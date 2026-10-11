extends RefCounted

const VERSION := "alpha_recorder_v1_economy_frontline"

func record(observation: Dictionary, memory: Dictionary) -> Dictionary:
	var now: float = float(observation.time)
	var delta: float = maxf(0.0, now - float(memory.get("time", now)))
	var miners: Array = []
	var producers: Array = []
	var fighters: Array = []
	var buildings: Array = []
	var waiting: int = 0
	var cargo: float = 0.0
	var construction: float = 0.0
	var queue_count: int = 0
	var combat_value: float = 0.0
	var front_distance: float = 0.0
	var home: Vector2 = observation.home
	var forward: Vector2 = (observation.enemy_start - home).normalized()
	var miner_history: Dictionary = memory.get("miners", {})
	var current_miners: Dictionary = {}
	for entity: Dictionary in observation.own:
		if str(entity.art) == "harvester":
			var id: String = str(entity.id)
			var previous: Dictionary = miner_history.get(id, {})
			var distance: float = (entity.pos as Vector2).distance_to(previous.get("pos", entity.pos))
			var stationary: float = float(previous.get("stationary", 0.0)) + delta if distance < 0.3 else 0.0
			var is_waiting: bool = str(entity.get("state", "")) in ["waiting", "waiting_rail", "idle", "unreachable"] or not entity.get("refinery_waiting", {}).is_empty()
			if is_waiting: waiting += 1
			cargo += float(entity.get("cargo", 0.0))
			current_miners[id] = {"pos": entity.pos, "stationary": stationary}
			var item: Dictionary = {"id": entity.id, "pos": entity.pos, "hp": entity.hp, "state": entity.get("state", ""), "cargo": entity.get("cargo", 0.0), "stationary_seconds": stationary}
			for key: String in ["commands", "harvest_mine", "harvest_phase", "refinery_docking", "refinery_waiting", "harvest_route", "yield", "route", "ai_traffic_until", "emerging", "harvest_override", "harvested_total", "unloaded_total", "waiting_time", "ai_miner_safety"]:
				if entity.has(key): item[key] = entity[key]
			miners.append(item)
		elif str(entity.kind) == "building":
			var remaining: float = float(entity.get("construct_remaining", 0.0))
			construction += remaining
			buildings.append({"id": entity.id, "spec": entity.spec, "hp": entity.hp, "pos": entity.pos, "remaining": remaining})
			if str(entity.role) in ["factory", "barracks", "airfield"]:
				var queue: Array = entity.get("queue", [])
				queue_count += queue.size()
				producers.append({"id": entity.id, "role": entity.role, "queue": queue, "remaining": remaining})
		elif not str(entity.weapon).is_empty():
			combat_value += float(entity.cost) * float(entity.hp) / maxf(1.0, float(entity.max_hp))
			front_distance = maxf(front_distance, (entity.pos - home).dot(forward))
			fighters.append({"id": entity.id, "spec": entity.spec, "pos": entity.pos, "hp": entity.hp, "commands": entity.get("commands", []), "attacking": entity.get("ai_attacking", false), "last_attack": entity.get("last_attack_time", -1.0), "traffic_until": entity.get("ai_traffic_until", 0.0)})
	var previous_stats: Dictionary = memory.get("statistics", {})
	var stats: Dictionary = observation.statistics
	var changes: Dictionary = {}
	for key: Variant in stats:
		if stats[key] is float or stats[key] is int:
			changes[key] = float(stats[key]) - float(previous_stats.get(key, stats[key]))
	memory.miners = current_miners
	memory.statistics = stats.duplicate(true)
	memory.time = now
	return {"version": VERSION, "time": now, "money": observation.money, "power": observation.power, "roles": observation.roles, "counts": observation.counts, "statistics": stats, "statistics_delta": changes, "miners": miners, "miner_waiting_count": waiting, "total_cargo": cargo, "producers": producers, "queued_units": queue_count, "construction_remaining": construction, "buildings": buildings, "combat_value_hp_adjusted": combat_value, "front_distance": front_distance, "fighters": fighters, "visible_enemies": observation.visible_enemies, "last_commands": observation.last_commands}
