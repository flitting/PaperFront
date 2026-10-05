extends RefCounted

const AircraftOperations = preload("res://scripts/aircraft_operations.gd")
const NavalOperations = preload("res://scripts/naval_operations.gd")

## Input routing shares transport eligibility with the authoritative simulation.
## The carrier keeps movement/landing decisions; input only assigns passengers.
static func infantry(sim, ids: Array) -> Array:
	return ids.filter(func(id):
		if not sim.entities.has(id): return false
		var e: Dictionary = sim.entities[id]
		var info: Dictionary = sim.data_for(e.spec)
		return int(e.team) == 0 and float(e.hp) > 0.0 and e.kind == "unit" and info.get("domain", "ground") == "ground" and info.get("armor_class", "") == "infantry" and int(e.get("transport_id", -1)) < 0)

static func carriers(sim, ids: Array, loaded_only: bool = false) -> Array:
	return ids.filter(func(id):
		if not sim.entities.has(id): return false
		var e: Dictionary = sim.entities[id]
		return int(e.team) == 0 and float(e.hp) > 0.0 and e.kind == "unit" and int(e.get("transport_id", -1)) < 0 and int(sim.data_for(e.spec).get("transport_capacity", 0)) > 0 and (not loaded_only or not e.get("passengers", []).is_empty()))

static func free_seats(sim, target: int, replacing: Array = []) -> int:
	if carriers(sim, [target]).is_empty(): return 0
	var carrier: Dictionary = sim.entities[target]
	var reserved: int = 0
	for e: Dictionary in sim.entities.values():
		if int(e.id) in replacing or int(e.get("transport_id", -1)) >= 0: continue
		if e.get("commands", []).any(func(command): return command.get("kind", "") == "board" and int(command.get("target", -1)) == target): reserved += 1
	return maxi(0, int(sim.data_for(carrier.spec).get("transport_capacity", 0)) - carrier.get("passengers", []).size() - reserved)

static func menu_state(sim, ids: Array) -> Dictionary:
	var selected_carriers: Array = carriers(sim, ids)
	var passengers: int = 0
	var capacity: int = 0
	var seats: int = 0
	for id in selected_carriers:
		passengers += sim.entities[id].get("passengers", []).size()
		capacity += int(sim.data_for(sim.entities[id].spec).get("transport_capacity", 0))
		seats += free_seats(sim, int(id))
	var selecting_passengers: bool = not infantry(sim, ids).is_empty() and carriers(sim, sim.entities.keys()).any(func(id): return free_seats(sim, int(id)) > 0)
	return {"enabled": not selected_carriers.is_empty() or selecting_passengers, "load": seats > 0 or selecting_passengers, "unload": passengers > 0, "passengers": passengers, "capacity": capacity, "seats": seats}

static func board(sim, ids: Array, target: int, append: bool) -> Dictionary:
	if carriers(sim, [target]).is_empty(): return {"passengers": [], "error": "请选择己方有搭载能力的运输载具"}
	var carrier: Dictionary = sim.entities[target]
	var seats: int = free_seats(sim, target, ids)
	var passengers: Array = []
	var reason: String = "运输载具已满员"
	for id in infantry(sim, ids):
		var error: String = sim.board_error(int(id), target)
		if not error.is_empty():
			reason = error
		elif passengers.size() < seats:
			passengers.append(int(id))
	if not passengers.is_empty():
		sim.issue(passengers, "board", carrier.pos, target, append)
	return {"passengers": passengers, "error": "" if not passengers.is_empty() else reason}

## Carrier selection targets infantry; infantry selection targets a carrier.
## Both routes use the same simulation boarding checks and seat reservations.
static func load_at(sim, ids: Array, target: int, append: bool) -> Dictionary:
	if not carriers(sim, [target]).is_empty(): return board(sim, infantry(sim, ids), target, append)
	if infantry(sim, [target]).is_empty(): return {"passengers": [], "error": "左键选择己方地面步兵，或选择己方运输载具"}
	var selected_carriers: Array = carriers(sim, ids)
	if selected_carriers.is_empty(): return {"passengers": [], "error": "先选择有空位的己方运输载具"}
	selected_carriers.sort_custom(func(a, b): return sim.entities[a].pos.distance_squared_to(sim.entities[target].pos) < sim.entities[b].pos.distance_squared_to(sim.entities[target].pos))
	var waiting: Array = infantry(sim, ids)
	if target not in waiting: waiting.append(target)
	var boarded: Array = []
	var reason: String = "运输载具已满员"
	for carrier in selected_carriers:
		var result: Dictionary = board(sim, waiting, int(carrier), append)
		boarded.append_array(result.passengers)
		for passenger in result.passengers: waiting.erase(passenger)
		if not str(result.error).is_empty(): reason = str(result.error)
	return {"passengers": boarded, "error": "" if not boarded.is_empty() else reason}

static func destination_error(sim, id: int, pos: Vector2) -> String:
	if carriers(sim, [id], true).is_empty(): return "运输载具没有搭载步兵"
	var carrier: Dictionary = sim.entities[id]
	if not pos.is_finite() or not sim._in_bounds(pos): return "卸载地点超出地图"
	if sim._is_air(carrier): return AircraftOperations.land_error(sim, carrier, pos)
	if NavalOperations.is_naval(sim, carrier):
		var pair: Dictionary = NavalOperations.coast_pair(sim, carrier, null, pos)
		return "" if not pair.is_empty() and (pair.land as Vector2).distance_to(pos) <= 12.5 else "请选择可通行的登陆海岸"
	return "" if sim._standing(pos, sim._radius(carrier), id) else "卸载地点没有足够的可通行空地"
