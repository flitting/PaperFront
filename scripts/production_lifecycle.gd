extends RefCounted
const Squads = preload("res://scripts/infantry_squads.gd")

static func active_members(sim, building: Dictionary) -> Array:
	var members: Array = building.get("production_members", [int(building.get("production_unit", -1))])
	members = members.filter(func(id): return sim.entities.has(id) and bool(sim.entities[id].get("emerging", false)) and int(sim.entities[id].get("production_source", -1)) == int(building.id))
	building.production_members = members
	building.production_unit = int(members[0]) if not members.is_empty() else -1
	if members.is_empty(): building.erase("production_owner_team")
	return members

static func before_capture(sim, building: Dictionary) -> void:
	var members: Array = active_members(sim, building)
	if not members.is_empty(): building.production_owner_team = int(sim.entities[members[0]].team)

static func normalize_legacy(snapshot: Dictionary) -> void:
	if not snapshot.get("entities") is Dictionary: return
	for raw: Variant in snapshot.entities.values():
		if not raw is Dictionary or raw.get("kind", "") != "building" or not bool(raw.get("captured", false)) or raw.has("production_owner_team"): continue
		var members: Variant = raw.get("production_members", [raw.get("production_unit", -1)])
		if not members is Array or members.is_empty(): continue
		var owner: int = -1
		var valid: bool = true
		for id: Variant in members:
			var unit: Variant = snapshot.entities.get(id, {})
			if not id is int or not unit is Dictionary or not unit.get("team") is int or not bool(unit.get("emerging", false)) or unit.get("production_source", -1) != raw.get("id", -2): valid = false; break
			if owner >= 0 and owner != int(unit.team): valid = false; break
			owner = int(unit.team)
		if valid and owner >= 0: raw.production_owner_team = owner

static func pending_batch(building: Dictionary) -> bool:
	if building.get("queue", []).is_empty(): return false
	var order: Dictionary = building.queue[0]
	return bool(order.get("ready", false)) and int(order.get("spawned", 0)) > 0 and int(order.get("spawned", 0)) < int(order.get("squad_size", 1))

static func order_can_advance(sim, building: Dictionary, order: Dictionary) -> bool:
	var members: Array = active_members(sim, building)
	if members.is_empty(): return true
	if int(order.get("squad_size", 1)) <= 1 or int(order.get("spawned", 0)) <= 0: return false
	return members.all(func(id): return int(sim.entities[id].get("squad_id", -1)) == int(order.get("squad_id", -1)))

static func origin(sim, building: Dictionary, spec: String, exit: Vector2) -> Vector2:
	var direction: Vector2 = (exit - (building.pos as Vector2)).normalized()
	var half: float = float(sim.data_for(building.spec).size) * .5
	return building.pos + direction * (half - float(sim.data_for(spec).radius) - float(sim._eco("production_inside_margin", .75)))

static func queued_spawn_point(sim, building: Dictionary, order: Dictionary) -> Vector2:
	if int(order.get("squad_size", 1)) <= 1 or int(order.get("spawned", 0)) <= 0: return sim._spawn_point(building, str(order.spec))
	var radius: float = float(sim.data_for(order.spec).radius)
	var half: float = float(sim.data_for(building.spec).size) * .5
	var exit: Vector2 = sim.BuildingOrientation.point(building, Vector2(0, half + radius + .15))
	var point: Vector2 = origin(sim, building, str(order.spec), exit)
	# The paid remainder waits virtually inside the producer. Materialize one
	# real soldier only when its actual body fits behind the procession.
	if not sim._segment_static(point, point, radius, int(building.id)): return Vector2.INF
	for other: Dictionary in sim._neighbors(point):
		if float(other.hp) <= 0.0: continue
		if (other.pos as Vector2).distance_to(point) < radius + sim._radius(other) + Squads.MEMBER_CLEARANCE - .001: return Vector2.INF
	return exit

## Ground production owns a short checked doorway traversal before normal AI.
static func begin(sim, building: Dictionary, unit: Dictionary, exit: Vector2) -> void:
	if sim._is_air(unit) or sim._is_naval(unit):
		unit.alpha=float(sim.BuildingOrientation.quarters(building))*90.0
		unit.turret_alpha=unit.alpha
	if sim._is_air(unit) and bool(sim.data_for(unit.spec).get("permanent_air", false)):
		preload("res://scripts/air_naval_expansion.gd").initialize_air(sim,unit)
		return
	if sim._is_air(unit):
		sim._set_home_airfield(unit, int(building.id))
		unit.service_goal = exit
		unit.flight_state = "rearming"
		unit.rearm_remaining = 0.0
		unit.park_after_service = true
		unit.flight_height = .35
		sim._set_airborne(unit, false)
		return
	if sim._is_naval(unit) and not (bool(sim.data_for(unit.spec).get("amphibious",false)) and sim.data_for(building.spec).get("role","")=="factory"): return
	var direction: Vector2 = (exit - (building.pos as Vector2)).normalized()
	var half: float = float(sim.data_for(building.spec).size)*.5
	var inside: Vector2 = building.pos + direction*(half-sim._radius(unit)-float(sim._eco("production_inside_margin",.75)))
	var members: Array = active_members(sim, building)
	var continuing: bool = not members.is_empty() or pending_batch(building)
	var original: Vector2 = unit.pos
	unit.pos = inside
	unit.alpha = rad_to_deg(direction.angle())
	unit.turret_alpha = unit.alpha
	unit.emerging = true
	unit.production_source = int(building.id)
	unit.production_exit = exit
	unit.production_origin = inside
	unit.production_elapsed = 0.0
	unit.state = "emerging"
	building.state = "emerging"
	if not continuing: building.production_door = 0.0
	members.append(int(unit.id))
	building.production_members = members
	building.production_unit = int(members[0])
	building.production_owner_team = int(unit.team)
	sim._spatial_move(unit, original, inside)

static func active(sim) -> bool:
	for unit in sim.entities.values():
		if bool(unit.get("emerging", false)): return true
	return false

static func building_step(sim, building: Dictionary, delta: float) -> void:
	var docked: Dictionary=sim.entities.get(int(building.get("dock_unit",-1)),{})
	if not docked.get("refinery_docking",{}).is_empty(): return
	if active_members(sim, building).is_empty() and not pending_batch(building):
		building.production_door = maxf(0, float(building.get("production_door",0))-delta/float(sim._eco("production_door_time",.6)))

static func step_unit(sim, unit: Dictionary, delta: float) -> bool:
	if not bool(unit.get("emerging", false)): return false
	var building: Dictionary = sim.entities.get(int(unit.production_source), {})
	if building.is_empty():
		unit.emerging = false
		return false
	if float(building.get("emp_until", 0)) > sim.time:
		unit.state = "waiting_exit"; return true
	var restricted: bool = sim.RailNetwork.rail_only(sim.data_for(unit.spec))
	if restricted and sim._rail_network.at(int(unit.team), unit.production_exit).is_empty():
		unit.state = "waiting_rail"; building.state = "waiting_rail"; return true
	building.state = "emerging"
	var door_time: float = float(sim._eco("production_door_time", .6))
	building.production_door = minf(1, float(building.get("production_door",0))+delta/door_time)
	if float(building.production_door) < 1: unit.state = "waiting_exit"; return true
	var exit: Vector2 = unit.production_exit
	var travel: float = float(sim.data_for(unit.spec).speed)*delta
	var next: Vector2 = (unit.pos as Vector2).move_toward(exit, travel)
	# Ignore only this producer. All other scenery and buildings retain collision.
	if not sim._segment_static(unit.pos, next, sim._radius(unit), int(building.id)):
		unit.state = "waiting_exit"; return true
	for other in sim._neighbors(next):
		if int(other.id) == int(unit.id): continue
		if restricted and int(other.team) == int(unit.team) and sim._rail_network.usable(sim, other, other.pos): continue
		if (other.pos as Vector2).distance_to(next) < sim._radius(unit)+sim._radius(other)+.02:
			unit.state = "waiting_exit"; return true
	var original: Vector2 = unit.pos
	unit.pos = next
	unit.motion = travel/maxf(delta,.001)
	unit.state = "emerging"
	sim._spatial_move(unit, original, next)
	if next.distance_to(exit) <= .01:
		unit.emerging = false
		unit.state = "idle"
		if active_members(sim, building).is_empty() and not pending_batch(building): building.state = "idle"
	return true

static func validate_snapshot(snapshot: Dictionary) -> String:
	var listed: Dictionary = {}
	for building: Dictionary in snapshot.entities.values():
		if not building.has("production_members"): continue
		if building.kind != "building" or not building.production_members is Array: return "存档小队出厂列表无效"
		var owner: Variant = building.get("production_owner_team", building.team)
		if not owner is int or int(owner) < 0 or int(owner) >= snapshot.factions.size(): return "存档小队出厂所属势力无效"
		if int(owner) != int(building.team) and (not bool(building.get("captured", false)) or building.production_members.is_empty()): return "存档小队出厂设施占领关系无效"
		for id: Variant in building.production_members:
			if not id is int or listed.has(id) or not snapshot.entities.has(id): return "存档小队出厂成员重复或缺失"
			var unit: Dictionary = snapshot.entities[id]
			if unit.kind != "unit" or not bool(unit.get("emerging", false)) or int(unit.get("production_source", -1)) != int(building.id) or int(unit.team) != int(owner): return "存档小队出厂双向关系无效"
			listed[id] = true
		if int(building.get("production_unit", -1)) != (int(building.production_members[0]) if not building.production_members.is_empty() else -1): return "存档小队出厂首位成员无效"
	for unit: Dictionary in snapshot.entities.values():
		if not bool(unit.get("emerging", false)): continue
		if unit.kind != "unit" or not unit.get("production_source") is int or not unit.get("production_exit") is Vector2 or not (unit.production_exit as Vector2).is_finite(): return "存档小队出厂状态无效"
		var source: Dictionary = snapshot.entities.get(int(unit.production_source), {})
		if not source.is_empty() and (source.kind != "building" or int(source.get("production_owner_team", source.team)) != int(unit.team)): return "存档小队出厂设施无效"
		if not source.is_empty() and source.has("production_members") and not listed.has(int(unit.id)): return "存档小队出厂成员缺少反向关系"
	return ""

static func remove(sim, entity: Dictionary) -> void:
	if entity.kind == "building":
		for id: int in active_members(sim, entity):
			# The real body stays where it was when the building disappeared.
			# Its rally command can now walk through the newly cleared space.
			sim.entities[id].emerging = false
			sim.entities[id].state = "idle"
		entity.production_members = []
		entity.production_unit = -1
		entity.erase("production_owner_team")
	elif bool(entity.get("emerging", false)):
		var source: Dictionary = sim.entities.get(int(entity.get("production_source", -1)), {})
		if source.is_empty(): return
		var remaining: Array = active_members(sim, source)
		remaining.erase(int(entity.id))
		source.production_members = remaining
		source.production_unit = int(remaining[0]) if not remaining.is_empty() else -1
		if remaining.is_empty(): source.erase("production_owner_team")
