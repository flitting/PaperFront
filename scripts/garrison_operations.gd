extends RefCounted

## Neutral houses keep their map identity; occupants remain the actual units.
const Transport = preload("res://scripts/unit_transport.gd")
const InfantrySquads = preload("res://scripts/infantry_squads.gd")
const BASE: int = -100000

static func suitable(ruin: Dictionary) -> bool:
	return str(ruin.get("kind", "")) == "house"

static func capacity(ruin: Dictionary) -> int:
	return 6 if suitable(ruin) else 0

static func loaded(unit: Dictionary) -> bool:
	return int(unit.get("garrison_id", -1)) >= 0

static func active(sim) -> bool:
	for e: Dictionary in sim.entities.values():
		if loaded(e): return true
		for command: Dictionary in e.get("commands", []):
			if command.get("kind", "") == "garrison": return true
	return false

static func hostile(sim, team: int, target: int) -> bool:
	if target > BASE: return false
	var ruin: Dictionary = sim.ruin_by_target(target)
	return not ruin.is_empty() and float(ruin.hp) > 0 and int(ruin.get("garrison_team", -1)) >= 0 and int(ruin.garrison_team) != team and not ruin.get("garrison", []).is_empty()

static func board_error(sim, unit_id: int, target: int) -> String:
	var e: Dictionary = sim.entities.get(unit_id, {})
	var ruin: Dictionary = sim.ruin_by_target(target) if target <= BASE else {}
	if e.is_empty() or e.get("kind", "") != "unit" or float(e.get("hp", 0)) <= 0: return "请选择存活步兵"
	var info: Dictionary = sim.data_for(e.spec)
	if info.get("art", "") == "engineer": return "工程兵不能进驻建筑"
	if info.get("armor_class", "") != "infantry" or info.get("domain", "ground") != "ground" or Transport.is_loaded(e): return "只有未搭载的地面步兵可以进驻"
	if not suitable(ruin): return "只能进驻中立房屋"
	if float(ruin.get("hp", 0)) < float(ruin.get("max_hp", 1)) * .2: return "建筑生命低于20%，不能进驻"
	if hostile(sim, int(e.team), target): return "建筑已被敌方驻军占据"
	if ruin.get("garrison", []).size() >= capacity(ruin): return "建筑驻军已满"
	if ruin.get("garrison", []).size() + InfantrySquads.boarding_count(sim, e, target, "garrison") > capacity(ruin): return "建筑空位不足以进驻整个小队"
	return ""

static func step_board(sim, e: Dictionary, command: Dictionary, delta: float) -> void:
	var target: int = int(command.target)
	var error: String = board_error(sim, int(e.id), target)
	if not error.is_empty():
		sim._finish_command(e)
		if int(e.team) == 0: sim._notice(error)
		return
	var ruin: Dictionary = sim.ruin_by_target(target)
	var point: Vector2 = _door(sim, ruin, e)
	if not point.is_finite():
		e.state = "waiting"
		return
	if (e.pos as Vector2).distance_to(point) > .55:
		sim._move_to(e, point, delta)
		return
	sim._spatial_remove(int(e.id), e.pos)
	Transport._clear_navigation(sim, e)
	e.garrison_id = int(ruin.id)
	e.pos = ruin.pos
	e.state = "garrisoned"
	e.motion = 0.0
	if not ruin.has("garrison"): ruin.garrison = []
	ruin.garrison.append(int(e.id))
	ruin.garrison_team = int(e.team)
	sim.events.append({"kind":"garrison", "id":e.id, "target":target, "pos":ruin.pos, "team":e.team})

static func _door(sim, ruin: Dictionary, e: Dictionary) -> Vector2:
	var best: Vector2 = Vector2.INF
	var distance: float = INF
	var half: Vector2 = ruin.half
	for side in range(4):
		var direction: Vector2 = Vector2.RIGHT.rotated(side * PI * .5)
		var extent: float = half.x if side % 2 == 0 else half.y
		for offset in [0.0, -.65, .65, -1.25, 1.25]:
			var point: Vector2 = ruin.pos + direction * (extent + sim._radius(e) + .18) + direction.orthogonal() * offset
			if not sim._standing(point, sim._radius(e), int(e.id)): continue
			var d: float = point.distance_squared_to(e.pos)
			if d < distance: best = point; distance = d
	return best

## These points match the authored front/flank windows, then rotate with art.
static func windows(ruin: Dictionary) -> Array[Vector3]:
	var result: Array[Vector3] = []
	var city: bool = ruin.has("archetype")
	var scale_xz: float = float(ruin.get("visual_scale_xz", ruin.get("visual_scale", 1.0)))
	var scale_y: float = float(ruin.get("visual_scale_y", ruin.get("visual_scale", 1.0)))
	var local: Array = [Vector3(-1.20,1.35,-2.02),Vector3(1.20,1.35,-2.02),Vector3(2.02,1.35,-1.20),Vector3(2.02,1.35,1.20),Vector3(-1.20,1.35,2.02),Vector3(1.20,1.35,2.02)] if city else [Vector3(-.15,1.08,-1.07),Vector3(.4,1.08,-1.07),Vector3(1.23,1.08,-.22),Vector3(-.15,1.08,-1.07),Vector3(.4,1.08,-1.07),Vector3(1.23,1.08,-.22)]
	for p: Vector3 in local:
		var rotated: Vector3 = Basis(Vector3.UP, float(ruin.get("yaw", 0))) * Vector3(p.x * scale_xz,p.y * scale_y,p.z * scale_xz)
		result.append(rotated)
	return result

static func step(sim, _delta: float) -> void:
	for ruin: Dictionary in sim.ruins:
		if ruin.get("garrison", []).is_empty(): continue
		if float(ruin.hp) < float(ruin.max_hp) * .2:
			unload(sim, BASE-int(ruin.id), true)
			continue
		var ports: Array[Vector3] = windows(ruin)
		var index: int = 0
		for id in ruin.garrison.duplicate():
			if not sim.entities.has(id): ruin.garrison.erase(id); continue
			var e: Dictionary = sim.entities[id]
			if float(e.hp) <= 0: continue
			e.pos = ruin.pos
			e.state = "garrisoned"
			var port: Vector3 = ports[index % ports.size()]
			index += 1
			if float(e.get("cooldown", 0)) > 0: continue
			var proxy: Dictionary = e.duplicate(true)
			proxy.garrison_id = -1
			proxy.pos = (ruin.pos as Vector2) + Vector2(port.x,port.z)
			proxy.garrison_fire_height = port.y
			var weapon_id: String = str(sim.data_for(e.spec).get("weapon", ""))
			var weapon: Dictionary = sim.weapon_for(e, weapon_id) if sim.has_method("weapon_for") else sim.rules.weapons.get(weapon_id, {})
			if weapon.is_empty(): continue
			var target: int = sim._nearest_enemy(proxy, float(weapon.range))
			if target == -1: continue
			proxy.alpha = rad_to_deg((sim._target_position(target) - (proxy.pos as Vector2)).angle())
			proxy.turret_alpha = proxy.alpha
			var event_start: int = sim.events.size()
			var projectile_start: int = sim.projectiles.size()
			sim._launch_shot(proxy, sim._target_position(target), target, false)
			for i in range(event_start,sim.events.size()):
				if sim.events[i].get("kind", "") == "fire": sim.events[i].garrison_fire = true
			for i in range(projectile_start,sim.projectiles.size()): sim.projectiles[i].garrison_fire = true
			e.cooldown = proxy.cooldown
			e.attack_flash = proxy.attack_flash
			e.alpha = proxy.alpha
			# The real shooter keeps kill attribution and veterancy accounting.
			e.garrison_window = index - 1

static func unload(sim, target: int, forced: bool = false, team: int = -1) -> String:
	var ruin: Dictionary = sim.ruin_by_target(target) if target <= BASE else {}
	if ruin.is_empty() or ruin.get("garrison", []).is_empty(): return "建筑内没有驻军"
	if team >= 0 and int(ruin.get("garrison_team", -1)) != team: return "只能撤出己方驻军"
	var blocked: bool = false
	for id in ruin.garrison.duplicate():
		if not sim.entities.has(id): ruin.garrison.erase(id); continue
		var e: Dictionary = sim.entities[id]
		var point: Vector2 = _exit(sim, ruin, e, forced)
		if not point.is_finite(): blocked = true; continue
		ruin.garrison.erase(id)
		e.garrison_id = -1
		e.pos = point
		Transport._clear_navigation(sim,e)
		e.state = "idle"
		sim._spatial_add(int(id), point)
		sim.events.append({"kind":"ungarrison", "id":id, "target":target, "pos":point, "team":e.team,"forced":forced})
	if ruin.garrison.is_empty(): ruin.garrison_team = -1
	return "出口被堵，驻军等待合法空地" if blocked else ""

static func _exit(sim, ruin: Dictionary, e: Dictionary, forced: bool) -> Vector2:
	var radius: float = sim._radius(e)
	var half: Vector2 = ruin.half
	# Search outward along each facade. Standing checks include other evacuees.
	for ring in range(25 if forced else 5):
		for side in range(4):
			var direction: Vector2 = Vector2.RIGHT.rotated(side * PI * .5)
			var extent: float = half.x if side % 2 == 0 else half.y
			for offset in [0.0,-.8,.8,-1.6,1.6]:
				var start: Vector2 = ruin.pos + direction * (extent + radius + .16) + direction.orthogonal() * offset
				var point: Vector2 = start + direction * ring * .55
				if sim._standing(point, radius, int(e.id)) and sim._segment_static(start,point,radius,int(e.id)): return point
	return Vector2.INF

static func remove(sim, e: Dictionary) -> void:
	if not loaded(e): return
	var ruin: Dictionary = sim.ruin_by_target(BASE-int(e.garrison_id))
	if not ruin.is_empty():
		ruin.get("garrison", []).erase(int(e.id))
		if ruin.get("garrison", []).is_empty(): ruin.garrison_team = -1
	e.garrison_id = -1

## Called after the ordinary entity/ruin schema checks. Legacy empty fields
## remain valid; every occupied record must have a reciprocal live unit.
static func validate_snapshot(snapshot: Dictionary) -> String:
	var entities: Dictionary = snapshot.entities
	var ruins: Array = snapshot.get("ruins",snapshot.map.get("ruins",[]))
	var units: Dictionary = snapshot.rules.units
	var seen: Dictionary = {}
	for ruin: Dictionary in ruins:
		if not ruin.get("garrison", []) is Array: return "存档驻军列表无效"
		var occupants: Array = ruin.get("garrison", [])
		var owner: Variant = ruin.get("garrison_team", -1)
		if not owner is int or int(owner) < -1 or int(owner) >= snapshot.factions.size(): return "存档驻军所属势力无效"
		if occupants.size() > capacity(ruin): return "存档驻军建筑或容量无效"
		if occupants.is_empty() and int(owner) != -1: return "存档空建筑驻军归属无效"
		for id: Variant in occupants:
			if not id is int or not entities.has(id) or seen.has(id): return "存档驻军身份重复或缺失"
			var e: Dictionary = entities[id]
			if int(e.get("garrison_id", -1)) != int(ruin.id) or int(e.team) != int(owner): return "存档驻军双向关系无效"
			seen[id] = true
	for id: Variant in entities:
		var e: Dictionary = entities[id]
		var house: Variant = e.get("garrison_id", -1)
		if not house is int or int(house) < -1 or int(house) >= ruins.size(): return "存档驻军建筑编号无效"
		if int(house) < 0:
			if seen.has(id): return "存档驻军缺少反向关系"
			continue
		if not seen.has(id): return "存档驻军没有建筑席位"
		var info: Dictionary = units.get(str(e.spec), {})
		if e.kind != "unit" or info.get("armor_class", "") != "infantry" or info.get("domain", "ground") != "ground" or info.get("art", "") == "engineer": return "存档包含不能驻军的单位"
		if int(e.get("transport_id", -1)) >= 0 or float(e.hp) <= 0 or not e.get("commands", []).is_empty() or not e.get("path", []).is_empty(): return "存档驻军运输或行动状态无效"
		if (e.pos as Vector2).distance_to(ruins[int(house)].pos) > .01: return "存档驻军位置无效"
	return ""
