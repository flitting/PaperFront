extends RefCounted

const MEMBER_CLEARANCE: float = .08
const GROUP_EDGE_GAP: float = 2.0

static func member_spacing(radius: float) -> float:
	return radius * 2.0 + MEMBER_CLEARANCE

static func slot_offset(slot: int, count: int, radius: float, forward: Vector2, side: Vector2) -> Vector2:
	if count <= 1: return Vector2.ZERO
	var spacing: float = member_spacing(radius)
	return side * (float(slot % 2) - .5) * spacing - forward * (float(slot / 2) - float(ceili(count / 2.0) - 1) * .5) * spacing

## A squad is a command relationship between real soldiers. Each soldier keeps
## its own entity, weapon, health, collision, veterancy and transport seat.
static func size(info: Dictionary) -> int:
	if info.get("armor_class", "") != "infantry" or info.get("domain", "ground") != "ground" or info.get("art", "") == "engineer": return 1
	return clampi(int(info.get("squad_size", 1)), 1, 6)

static func cost(info: Dictionary) -> float:
	return float(info.get("cost", 0.0)) * size(info)

static func training_time(info: Dictionary) -> float:
	return float(info.get("squad_build_time", float(info.get("build_time", 1.0)) * size(info)))

static func identity(e: Dictionary) -> int:
	return int(e.get("squad_id", e.get("id", -1)))

static func available(e: Dictionary) -> bool:
	return e.get("kind", "") == "unit" and float(e.get("hp", 0.0)) > 0.0 and int(e.get("transport_id", -1)) < 0 and int(e.get("garrison_id", -1)) < 0

static func members(sim, id: int, available_only: bool = false) -> Array:
	var source: Dictionary = sim.entities.get(id, {})
	if source.is_empty() or source.get("kind", "") != "unit": return []
	if not source.has("squad_id"):
		return [id] if float(source.get("hp", 0.0)) > 0.0 and (not available_only or available(source)) else []
	var result: Array = []
	for e: Dictionary in sim.entities.values():
		if e.get("kind", "") != "unit" or int(e.get("team", -1)) != int(source.team) or str(e.get("spec", "")) != str(source.spec): continue
		if identity(e) != identity(source) or float(e.get("hp", 0.0)) <= 0.0 or (available_only and not available(e)): continue
		result.append(int(e.id))
	result.sort_custom(func(a, b): return int(sim.entities[a].get("squad_slot", 0)) < int(sim.entities[b].get("squad_slot", 0)))
	return result

static func expand(sim, ids: Array, available_only: bool = false) -> Array:
	var result: Array = []
	var seen: Dictionary = {}
	var seen_groups: Dictionary = {}
	for raw: Variant in ids:
		var id: int = int(raw)
		if seen.has(id): continue
		var e: Dictionary = sim.entities.get(id, {})
		if e.is_empty(): continue
		if e.get("kind", "") != "unit":
			if not seen.has(id): result.append(id); seen[id] = true
			continue
		var group: int = identity(e)
		if seen_groups.has(group): continue
		seen_groups[group] = true
		for member: int in members(sim, id, available_only):
			if not seen.has(member): result.append(member); seen[member] = true
	return result

static func representatives(sim, ids: Array, available_only: bool = true) -> Array:
	var result: Array = []
	var seen: Dictionary = {}
	for raw: Variant in ids:
		var id: int = int(raw)
		var e: Dictionary = sim.entities.get(id, {})
		if e.is_empty() or float(e.get("hp", 0.0)) <= 0.0: continue
		if e.get("kind", "") != "unit":
			if not seen.has(id): result.append(id); seen[id] = true
			continue
		var group: int = identity(e)
		if seen.has(group): continue
		var living: Array = members(sim, id, available_only)
		if living.is_empty(): continue
		seen[group] = true
		result.append(living[0])
	return result

static func assign(e: Dictionary, group: int, slot: int, capacity: int) -> void:
	if capacity <= 1: return
	e.squad_id = group
	e.squad_slot = slot
	e.squad_capacity = capacity

## Keep squad blocks together when several command objects move together.
## Navigation still resolves every member's actual safe destination separately.
static func formation_offsets(sim, ids: Array, forward: Vector2, side: Vector2) -> Dictionary:
	var any_squad: bool = ids.any(func(id): return sim.entities[id].has("squad_id"))
	if not any_squad: return {}
	var groups: Array = []
	var by_group: Dictionary = {}
	var width: float = 1.0
	var depth: float = 1.0
	for id: int in ids:
		var e: Dictionary = sim.entities[id]
		var group: int = identity(e)
		if not by_group.has(group): by_group[group] = []; groups.append(group)
		by_group[group].append(id)
		var count: int = int(e.get("squad_capacity", 1))
		var radius: float = sim._radius(e)
		var spacing: float = member_spacing(radius) if count > 1 else maxf(1.0, radius * 2.8)
		width = maxf(width, (1.0 if count > 1 else 0.0) * spacing + radius * 2.0)
		depth = maxf(depth, (ceili(count / 2.0) - 1.0) * spacing + radius * 2.0)
	groups.sort_custom(func(a, b):
		var ca: Vector2 = Vector2.ZERO
		var cb: Vector2 = Vector2.ZERO
		for member: int in by_group[a]: ca += sim.entities[member].pos
		for member: int in by_group[b]: cb += sim.entities[member].pos
		return (ca / by_group[a].size()).dot(side) < (cb / by_group[b].size()).dot(side))
	var columns: int = ceili(sqrt(float(groups.size())))
	var rows: int = ceili(float(groups.size()) / columns)
	var group_slots: Dictionary = {}
	for column: int in range(columns):
		var lane: Array = groups.slice(column * rows, mini((column + 1) * rows, groups.size()))
		lane.sort_custom(func(a, b):
			var ca: Vector2 = Vector2.ZERO
			var cb: Vector2 = Vector2.ZERO
			for member: int in by_group[a]: ca += sim.entities[member].pos
			for member: int in by_group[b]: cb += sim.entities[member].pos
			return (ca / by_group[a].size()).dot(forward) > (cb / by_group[b].size()).dot(forward))
		for row: int in range(lane.size()): group_slots[lane[row]] = row * columns + column
	var offsets: Dictionary = {}
	for index: int in range(groups.size()):
		var position: int = int(group_slots[groups[index]])
		var anchor: Vector2 = side * (float(position % columns) - float(columns - 1) * .5) * (width + GROUP_EDGE_GAP) - forward * (float(position / columns) - float(rows - 1) * .5) * (depth + GROUP_EDGE_GAP)
		var ordered: Array = by_group[groups[index]].duplicate()
		ordered.sort_custom(func(a, b): return (sim.entities[a].pos as Vector2).dot(side) < (sim.entities[b].pos as Vector2).dot(side))
		var member_count: int = ordered.size()
		var member_rows: int = ceili(member_count / 2.0)
		var member_slots: Dictionary = {}
		for column: int in range(2):
			var lane: Array = ordered.slice(column * member_rows, mini((column + 1) * member_rows, member_count))
			lane.sort_custom(func(a, b): return (sim.entities[a].pos as Vector2).dot(forward) > (sim.entities[b].pos as Vector2).dot(forward))
			for row: int in range(lane.size()): member_slots[lane[row]] = row * 2 + column
		for id: int in by_group[groups[index]]:
			var e: Dictionary = sim.entities[id]
			var count: int = member_count if e.has("squad_id") else 1
			var slot: int = int(member_slots[id])
			var local: Vector2 = slot_offset(slot, count, sim._radius(e), forward, side)
			offsets[id] = anchor + local
	return offsets

## Traffic may temporarily push a parked member aside. Returning to the
## player's last slot keeps squads legible after the final arrival, while all
## actual movement still uses the ordinary independent collision solver.
static func regroup(sim, delta: float) -> void:
	for e: Dictionary in sim.entities.values():
		if not e.has("squad_formation_goal") or not available(e) or bool(e.get("emerging", false)) or not e.get("commands", []).is_empty() or e.get("state", "") != "idle": continue
		if (e.get("yield_goal", Vector2.INF) as Vector2).is_finite() or float(e.get("emp_until", 0.0)) > sim.time: continue
		var goal: Vector2 = e.squad_formation_goal
		if not sim._goal_standing(e, goal, sim._radius(e)):
			goal = sim._near_stand(goal, sim._radius(e), int(e.id), 4.0, false)
			if not goal.is_finite(): continue
			e.squad_formation_goal = goal
		if e.pos.distance_to(goal) > .25:
			sim._move_to(e, goal, delta)
		elif e.pos.distance_to(goal) > .015:
			# The general mover accepts a quarter-metre arrival band. Dense
			# parked rows need the remaining few centimetres to keep the next
			# arrival's slot accessible; settle with the same swept collision.
			var original: Vector2 = e.pos
			var next: Vector2 = original.move_toward(goal, float(sim.data_for(e.spec).speed) * delta)
			if sim._movement_clear(e, original, next):
				e.pos = next
				e.motion = original.distance_to(next)
				e.state = "move"
				sim._spatial_move(e, original, next)

## Reservations count people, including other squads already walking to board.
static func boarding_count(sim, passenger: Dictionary, carrier_id: int, command_kind: String) -> int:
	var own: Array = members(sim, int(passenger.id), true)
	var reserved: int = own.size()
	for e: Dictionary in sim.entities.values():
		if not available(e) or identity(e) == identity(passenger) or e.get("commands", []).is_empty(): continue
		if e.commands.any(func(command): return command.get("kind", "") == command_kind and int(command.get("target", -1)) == carrier_id): reserved += 1
	return reserved

static func validate_snapshot(snapshot: Dictionary) -> String:
	var groups: Dictionary = {}
	for e: Dictionary in snapshot.entities.values():
		if e.has("squad_formation_goal") and (not e.has("squad_id") or not e.squad_formation_goal is Vector2 or not (e.squad_formation_goal as Vector2).is_finite()): return "存档步兵小队集结位置无效"
		if (e.has("squad_slot") or e.has("squad_capacity")) and not e.has("squad_id"): return "存档步兵小队身份缺失"
		if e.has("squad_id"):
			if e.kind != "unit" or not e.squad_id is int or int(e.squad_id) < 1 or int(e.squad_id) >= int(snapshot.next_id) or not e.get("squad_slot") is int or not e.get("squad_capacity") is int: return "存档步兵小队身份无效"
			var capacity: int = int(e.squad_capacity)
			if capacity < 2 or capacity > 6 or int(e.squad_slot) < 0 or int(e.squad_slot) >= capacity or size(snapshot.rules.units[e.spec]) != capacity: return "存档步兵小队编制无效"
			var key: int = int(e.squad_id)
			if not groups.has(key): groups[key] = {"team":e.team,"spec":e.spec,"capacity":capacity,"slots":{}}
			var group: Dictionary = groups[key]
			if group.team != e.team or group.spec != e.spec or int(group.capacity) != capacity or group.slots.has(int(e.squad_slot)): return "存档步兵小队成员关系无效"
			group.slots[int(e.squad_slot)] = true
		for order: Dictionary in e.get("queue", []):
			if (order.has("spawned") or order.has("squad_id")) and not order.has("squad_size"): return "存档步兵小队生产编制缺失"
			if not order.has("squad_size"): continue # Legacy orders produce one soldier.
			if not order.squad_size is int or int(order.squad_size) < 1 or int(order.squad_size) > 6 or not order.get("spawned") is int or int(order.spawned) < 0 or int(order.spawned) >= int(order.squad_size) or not order.get("squad_id") is int: return "存档步兵小队生产订单无效"
			if int(order.squad_size) != size(snapshot.rules.units[order.spec]): return "存档步兵小队生产编制无效"
			if int(order.spawned) > 0 and (int(order.squad_id) < 1 or int(order.squad_id) >= int(snapshot.next_id) or not bool(order.ready)): return "存档步兵小队出厂状态无效"
			if int(order.spawned) > 0 and (float(order.remaining) > 0.0 or not is_equal_approx(float(order.progress), 1.0)): return "存档步兵小队出厂进度无效"
	for key: int in groups:
		if not snapshot.entities.has(key): continue # The original leader may have died.
		var founder: Dictionary = snapshot.entities[key]
		if founder.get("kind", "") != "unit" or int(founder.get("squad_id", -1)) != key or int(founder.get("squad_slot", -1)) != 0: return "存档步兵小队创始身份无效"
	return ""
