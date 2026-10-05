extends RefCounted

## Tactical support uses existing money, ground navigation and combat rules.
## Each target receives the best provider, never a sum of identical bonuses.
static func vehicle(sim, e: Dictionary) -> bool:
	return e.get("kind") == "unit" and float(e.get("hp", 0.0)) > 0.0 and not sim._is_air(e) and not sim.Transport.is_loaded(e) and sim.data_for(e.spec).get("armor_class", "infantry" if e.crushable else "armored") == "armored"

static func repairer(sim, e: Dictionary, target: Dictionary) -> bool:
	var spec: Dictionary = sim.data_for(e.spec)
	return e.kind == "unit" and e.team == target.team and int(e.id) != int(target.id) and not sim.Transport.is_loaded(e) and (spec.get("art", "") == "engineer" or (float(spec.get("repair_rate", 0.0)) > 0.0 and vehicle(sim, target)))

static func rescue_error(sim, id: int, target_id: int) -> String:
	if not sim.entities.has(id) or not sim.entities.has(target_id): return "拖救车或友方载具已不存在"
	var e: Dictionary = sim.entities[id]
	var target: Dictionary = sim.entities[target_id]
	if float(sim.data_for(e.spec).get("rescue_speed_bonus", 0.0)) <= 0.0: return "该单位没有拖救能力"
	if id == target_id or e.team != target.team or not vehicle(sim, target): return "拖救只接受仍存活的己方地面载具"
	if float(target.hp) >= float(sim.data_for(target.spec).hp): return "载具无需拖救"
	return ""

static func step_rescue(sim, e: Dictionary, command: Dictionary, delta: float) -> void:
	var target_id: int = int(command.target)
	if not rescue_error(sim, int(e.id), target_id).is_empty():
		sim._finish_command(e)
		return
	var target: Dictionary = sim.entities[target_id]
	var reach: float = float(sim.data_for(e.spec).get("rescue_radius", 4.0))
	if (e.pos as Vector2).distance_to(target.pos) > reach * .65:
		var behind: Vector2 = Vector2.LEFT.rotated(deg_to_rad(float(target.alpha)))
		var goal: Vector2 = sim._near_stand(target.pos + behind * reach * .5, sim._radius(e), int(e.id), 3.0, false)
		if goal.is_finite(): sim._move_to(e, goal, delta)
		else: e.state = "unreachable"
	else:
		e.state = "rescue"

static func prepare(sim, delta: float) -> void:
	sim._designation_bonuses.clear()
	sim._overcharge_bonuses.clear()
	sim._support_power.clear()
	var providers: Array[Dictionary] = []
	for e in sim.entities.values():
		e.rescue_speed_scale = 1.0
		if float(e.hp) <= 0.0 or float(e.construct_remaining) > 0.0 or sim.Transport.is_loaded(e) or float(e.get("emp_until", 0.0)) > sim.time: continue
		var spec: Dictionary = sim.data_for(e.spec)
		if spec.has("rescue_radius") or spec.has("designation_radius") or spec.has("overcharge_radius"): providers.append(e)
	for e in providers:
		var spec: Dictionary = sim.data_for(e.spec)
		if spec.has("rescue_radius") and not e.commands.is_empty() and e.commands[0].kind == "rescue":
			var target_id: int = int(e.commands[0].target)
			if rescue_error(sim, int(e.id), target_id).is_empty():
				var target: Dictionary = sim.entities[target_id]
				if float(target.hp) <= float(sim.data_for(target.spec).hp) * .6 and not target.commands.is_empty() and target.commands[0].kind in ["move", "force_move", "patrol"] and (e.pos as Vector2).distance_to(target.pos) <= float(spec.rescue_radius) and sim._segment_static(e.pos, target.pos, .05, int(e.id)):
					target.rescue_speed_scale = maxf(float(target.rescue_speed_scale), 1.0 + float(spec.rescue_speed_bonus))
		if spec.has("designation_radius"): _designation(sim, e, spec, delta)
	# Reserve the electrical headroom for ongoing windows before new activation.
	for e in providers:
		var spec: Dictionary = sim.data_for(e.spec)
		if not spec.has("overcharge_radius"): continue
		e.overcharge_remaining = maxf(0.0, float(e.get("overcharge_remaining", 0.0)) - delta)
		e.overcharge_cooldown = maxf(0.0, float(e.get("overcharge_cooldown", 0.0)) - delta)
		if float(e.overcharge_remaining) > 0.0:
			var energy: Vector2 = sim.power(int(e.team))
			if energy.x - energy.y < float(spec.overcharge_power): e.overcharge_remaining = 0.0
			else: sim._support_power[int(e.team)] = float(sim._support_power.get(int(e.team), 0.0)) + float(spec.overcharge_power)
	for e in providers:
		var spec: Dictionary = sim.data_for(e.spec)
		if spec.has("overcharge_radius"): _overcharge(sim, e, spec)

static func visible(sim, source: Dictionary, target: Dictionary, reach: float) -> bool:
	if source.team == target.team or not vehicle(sim, target) or (source.pos as Vector2).distance_to(target.pos) > reach: return false
	# Observation crosses water; it needs an unobstructed ray, not a walkable
	# path. Cliffs, solid structures and ore still block the sensor line.
	var start: Vector2 = source.pos
	var end: Vector2 = target.pos
	var steps: int = maxi(1, ceili(start.distance_to(end) / .4))
	var eye: float = sim._height(start) + 1.4
	var aim: float = sim._height(end) + 1.0
	for i in range(1, steps + 1):
		var t: float = float(i) / float(steps)
		var point: Vector2 = start.lerp(end, t)
		if sim._height(point) >= lerpf(eye, aim, t) or not sim._building_clear(point, .05, int(source.id)): return false
	return true

static func _designation(sim, e: Dictionary, spec: Dictionary, delta: float) -> void:
	var reach: float = float(spec.designation_radius)
	var target_id: int = int(e.get("designation_target", -1))
	if not sim.entities.has(target_id) or not visible(sim, e, sim.entities[target_id], reach):
		target_id = -1
		var distance: float = reach + .001
		for other in sim._nearby_entities(e.pos, reach):
			var current: float = (e.pos as Vector2).distance_to(other.pos)
			if current < distance and visible(sim, e, other, reach):
				target_id = int(other.id)
				distance = current
		if target_id != int(e.get("designation_target", -1)): e.designation_progress = 0.0
		e.designation_target = target_id
	if target_id < 0:
		e.designation_progress = 0.0
		return
	e.designation_progress = minf(float(spec.designation_track_time), float(e.get("designation_progress", 0.0)) + delta)
	if float(e.designation_progress) >= float(spec.designation_track_time):
		var key := Vector2i(int(e.team), target_id)
		sim._designation_bonuses[key] = maxf(float(sim._designation_bonuses.get(key, 0.0)), float(spec.damage_bonus))

static func _overcharge(sim, e: Dictionary, spec: Dictionary) -> void:
	var nearby: Array = sim._nearby_entities(e.pos, float(spec.overcharge_radius))
	if float(e.overcharge_remaining) <= 0.0 and float(e.overcharge_cooldown) <= 0.0:
		var energy: Vector2 = sim.power(int(e.team))
		var ready: bool = energy.x - energy.y >= float(spec.overcharge_power) and float(sim.money[int(e.team)]) >= float(spec.overcharge_cost)
		var combat: bool = false
		if ready:
			for other in nearby:
				if other.team != e.team or other.kind != "unit" or float(other.hp) <= 0.0 or sim.Transport.is_loaded(other) or (e.pos as Vector2).distance_to(other.pos) > float(spec.overcharge_radius): continue
				var weapon_id: String = str(sim.data_for(other.spec).get("weapon", ""))
				if not weapon_id.is_empty() and sim._nearest_enemy(other, float(sim.rules.weapons[weapon_id].range)) >= 0:
					combat = true
					break
		if combat:
			sim.money[int(e.team)] -= float(spec.overcharge_cost)
			e.overcharge_remaining = float(spec.overcharge_window)
			e.overcharge_cooldown = float(spec.overcharge_recharge) + float(spec.overcharge_window)
			sim._support_power[int(e.team)] = float(sim._support_power.get(int(e.team), 0.0)) + float(spec.overcharge_power)
			sim.events.append({"kind":"overcharge", "id":e.id, "pos":e.pos, "team":e.team})
	if float(e.overcharge_remaining) <= 0.0: return
	for other in nearby:
		if other.team == e.team and other.kind == "unit" and not sim.Transport.is_loaded(other) and float(other.hp) > 0.0 and (e.pos as Vector2).distance_to(other.pos) <= float(spec.overcharge_radius):
			sim._overcharge_bonuses[int(other.id)] = maxf(float(sim._overcharge_bonuses.get(int(other.id), 0.0)), float(spec.damage_bonus))

static func damage_scale(sim, source: Dictionary, target_id: int) -> float:
	var designated: float = float(sim._designation_bonuses.get(Vector2i(int(source.team), target_id), 0.0))
	var charged: float = float(sim._overcharge_bonuses.get(int(source.id), 0.0))
	return (1.0 + designated) * (1.0 + charged)
