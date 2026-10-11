extends RefCounted

## Beta v3: restore early income and avoid replacement-tank budget lock.
const VERSION := "beta_v3_income_defense"

func decide(observation: Dictionary, memory: Dictionary) -> Dictionary:
	var now: float = float(observation.get("time", 0.0))
	var home: Vector2 = observation.get("home", Vector2.ZERO)
	var enemy_start: Vector2 = observation.get("enemy_start", home)
	var forward: Vector2 = (enemy_start - home).normalized()
	var own: Array = observation.get("own", [])
	var enemies: Array = observation.get("visible_enemies", [])
	var rules: Dictionary = observation.get("rules", {})
	var army: Array = []
	var steps: Array = []
	var fallback_steps: Array = []
	var army_value: float = 0.0
	var infantry_count: int = 0
	var enemy_infantry: int = 0
	var enemy_armor: int = 0
	var home_threat_value: float = 0.0
	var threat: Dictionary = {}
	var nearest_threat: float = INF
	var factory_ready: bool = false
	for unit: Dictionary in own:
		if str(unit.get("role", "")) == "factory" and float(unit.get("construct_remaining", 0.0)) <= 0.0: factory_ready = true
		if not _armed_mobile(unit) or bool(unit.get("emerging", false)) or int(unit.get("loaded_in", -1)) >= 0: continue
		army.append(unit)
		army_value += _combat_value(unit)
		var progress: float = ((unit.pos as Vector2) - home).dot(forward)
		if str(unit.get("domain", "ground")) == "ground": fallback_steps.append(progress)
		if str(unit.get("armor_class", "")) == "infantry": steps.append(progress); infantry_count += 1
	if steps.is_empty(): steps = fallback_steps
	steps.sort()
	var anchor: float = float(steps[int(steps.size()/2)]) if not steps.is_empty() else 16.0
	var center: Vector2 = home + forward * anchor
	var contact_value: float = 0.0
	var contacts: Dictionary = memory.get("contacts", {})
	for enemy: Dictionary in enemies:
		if str(enemy.get("kind", "")) == "building": continue
		if str(enemy.get("armor_class", "")) == "infantry": enemy_infantry += 1
		elif str(enemy.get("domain", "ground")) == "ground" and not str(enemy.get("weapon", "")).is_empty(): enemy_armor += 1
		if str(enemy.get("weapon", "")).is_empty(): continue
		contacts[str(enemy.id)] = {"pos":enemy.pos,"value":_combat_value(enemy),"seen":now}
		if (enemy.pos as Vector2).distance_to(center) < 30.0: contact_value += _combat_value(enemy)
		var distance: float = (enemy.pos as Vector2).distance_to(home)
		var near_asset: bool = distance < 40.0
		for asset: Dictionary in own:
			if str(asset.get("art", "")) == "harvester" or (str(asset.get("kind", "")) == "building" and str(asset.get("role", "")) in ["refinery", "factory", "hq"]):
				if (enemy.pos as Vector2).distance_to(asset.pos) < 16.0: near_asset = true
		if near_asset:
			home_threat_value += _combat_value(enemy)
			if distance < nearest_threat: nearest_threat = distance; threat = enemy
	var remembered_contact: float = 0.0
	for id: Variant in contacts.keys():
		var known: Dictionary = contacts[id]
		if now-float(known.seen) > 40.0: contacts.erase(id); continue
		if (known.pos as Vector2).distance_to(center) < 42.0: remembered_contact += float(known.value)
	memory.contacts = contacts
	var local_value: float = 0.0
	for unit: Dictionary in army:
		if (unit.pos as Vector2).distance_to(center) < 28.0: local_value += _combat_value(unit)
	if home_threat_value > 0.0:
		memory.threat_until = now + 8.0
		memory.threat_pos = threat.get("pos", home)
	var pressure: bool = now < float(memory.get("threat_until", 0.0))
	var phase: String = str(memory.get("phase", "muster"))
	var peak: float = maxf(float(memory.get("attack_peak", 0.0)), army_value)
	if phase == "attack" and (army.size() < 6 or army_value < peak * 0.50 or contact_value > maxf(600.0,local_value) * 1.20):
		phase = "muster"
		memory.recover_until = now + 38.0
		peak = army_value
	elif pressure and (phase != "attack" or home_threat_value > army_value * 0.5): phase = "defend"
	elif phase == "defend" and not pressure: phase = "muster"
	elif not pressure and now >= float(memory.get("recover_until", 0.0)) and infantry_count >= 8 and army.size() >= 12 and army_value >= maxf(3200.0,remembered_contact*1.18):
		phase = "attack"
	memory.phase = phase
	memory.attack_peak = peak
	memory.version = VERSION
	var infantry: Array = ["marksman", "marksman", "anti", "gunner"]
	if enemy_armor > enemy_infantry: infantry = ["anti", "marksman", "marksman", "anti"]
	elif enemy_infantry >= 6: infantry = ["marksman", "gunner", "marksman", "anti"]
	var profile: Dictionary = {"style":"balanced", "infantry":infantry,"vehicles":["tank", "tank", "artillery"],"air":["attacker"],"infantry_limit":28,"factory_share":0.15,"expansion_after":86400.0,"tech_after":86400.0,"air_after":86400.0,"factory_after":86400.0,"builders":1,"tower_limit":0}
	var commands: Array = []
	var economy_goal: String = "shared_startup"
	if factory_ready:
		var economy: Dictionary = _economy(observation, memory, army.size(), infantry_count, enemy_infantry, enemy_armor, pressure)
		commands.append_array(economy.commands)
		economy_goal = str(economy.goal)
	var goal: Vector2 = _objective(enemies, memory, enemy_start, home)
	var march: Vector2 = home + forward * minf(anchor + 9.0, home.distance_to(goal))
	if march.distance_to(goal) < 24.0: march = goal
	var rally: Vector2 = home + forward * 19.0
	var claims: Dictionary = {}
	for unit: Dictionary in army:
		if now < float(unit.get("ai_traffic_until", 0.0)): continue
		var position: Vector2 = unit.pos
		var domain: String = str(unit.get("domain", "ground"))
		var art: String = str(unit.get("art", ""))
		var retreating: bool = phase != "attack" and now < float(memory.get("recover_until", 0.0)) and position.distance_to(home) > 39.0
		if retreating:
			_move_if_needed(commands, unit, rally, "move", 6.0)
			continue
		var target: Dictionary = _choose_target(unit, enemies, rules, claims)
		if not target.is_empty():
			var weapon: Dictionary = rules.get("weapons", {}).get(str(unit.get("weapon", "")), {})
			claims[int(target.id)] = float(claims.get(int(target.id), 0.0)) + float(weapon.get("damage", 0.0))
			if not _same_attack(unit, int(target.id)):
				commands.append({"action":"issue", "ids":[int(unit.id)], "kind":"attack", "target":int(target.id), "pos":target.pos})
			continue
		var destination: Vector2 = march if phase == "attack" else rally
		if phase == "attack" and domain == "ground":
			var offset: float = -3.0 if art in ["marksman", "artillery", "scout"] else 0.0
			destination += forward * offset + forward.orthogonal() * float(int(unit.id)%5-2) * 1.6
		elif domain == "air" and phase == "attack": destination = goal
		if pressure and position.distance_to(memory.get("threat_pos", home)) < 48.0: destination = memory.get("threat_pos", rally)
		_move_if_needed(commands, unit, destination, "attack_move", 5.0)
	return {"profile":profile,"settings":{"wave":12,"attack_gap":24.0},"shared_economy":not factory_ready,"shared_tactics":false,"commands":commands.slice(0,96),"reason":"%s %s force=%d infantry=%d value=%.0f anchor=%.1f contact=%.0f remembered=%.0f local=%.0f home_threat=%.0f economy=%s" % [VERSION,phase,army.size(),infantry_count,army_value,anchor,contact_value,remembered_contact,local_value,home_threat_value,economy_goal]}

func _economy(observation: Dictionary, memory: Dictionary, army_count: int, infantry_count: int, enemy_infantry: int, enemy_armor: int, pressure: bool) -> Dictionary:
	var own: Array = observation.get("own", [])
	var rules: Dictionary = observation.get("rules", {})
	var faction: String = str(observation.get("faction", "kestrel"))
	var now: float = float(observation.get("time", 0.0))
	var money: float = float(observation.get("money", 0.0))
	var power: Vector2 = observation.get("power", Vector2.ZERO)
	var roles: Dictionary = observation.get("roles", {})
	var ready_roles: Dictionary = {}
	var counts: Dictionary = {}
	var producers: Array = []
	for entity: Dictionary in own:
		var spec: String = str(entity.spec)
		counts[spec] = int(counts.get(spec,0)) + int(rules.get("units", {}).get(spec, {}).get("squad_size", 1))
		for queued: Dictionary in entity.get("queue", []): counts[str(queued.spec)] = int(counts.get(str(queued.spec),0)) + 1
		if str(entity.get("kind", "")) == "building" and float(entity.get("construct_remaining",0.0)) <= 0.0:
			var role: String = str(entity.get("role", ""))
			ready_roles[role] = int(ready_roles.get(role,0)) + 1
			if role in ["barracks","factory","airfield"] and entity.get("queue",[]).is_empty(): producers.append(entity)
	var income_gap: bool = int(counts.get(faction+"_harvester",0)) < 2
	var goal: String = ""
	if power.x < power.y + 35.0: goal = "power"
	elif int(roles.get("refinery",0)) < 1: goal = "refinery"
	elif int(roles.get("barracks",0)) < 1: goal = "barracks"
	elif not income_gap and not pressure and army_count >= 7 and int(roles.get("refinery",0)) < 2 and power.x < power.y + 95.0: goal = "power"
	elif not income_gap and not pressure and army_count >= 8 and int(roles.get("refinery",0)) < 2: goal = "refinery"
	elif not pressure and army_count >= 11 and int(roles.get("barracks",0)) < 2: goal = "barracks"
	elif not pressure and army_count >= 13 and now >= 320.0 and int(roles.get("tech",0)) < 1: goal = "tech"
	elif not pressure and army_count >= 16 and now >= 500.0 and int(roles.get("factory",0)) < 2 and power.x >= power.y + 135.0: goal = "factory"
	var commands: Array = []
	var reserve: float = 0.0
	var normal: Dictionary = observation.get("orders", {}).get("normal", {})
	if not goal.is_empty() and normal.is_empty():
		var spec: String = faction + "_" + goal
		reserve = float(rules.get("buildings", {}).get(spec, {}).get("cost", 0.0))
		if money >= reserve:
			commands.append({"action":"build","spec":spec})
			money -= reserve
			reserve = 0.0
	var first_tank: bool = int(counts.get(faction+"_tank",0)) < 1
	var prefer_infantry: bool = (pressure and army_count < 8) or (infantry_count < 6 and not first_tank and not income_gap)
	producers.sort_custom(func(a: Dictionary,b: Dictionary): return int(str(a.get("role","")) != "barracks") < int(str(b.get("role","")) != "barracks") if prefer_infantry else int(str(a.get("role","")) != "factory") < int(str(b.get("role","")) != "factory"))
	var miner_target: int = 4 if int(ready_roles.get("refinery",0)) >= 2 and army_count >= 12 and not pressure else 2
	for producer: Dictionary in producers:
		var role: String = str(producer.get("role", ""))
		var suffix: String = ""
		if role == "factory":
			if int(counts.get(faction+"_harvester",0)) < 1: suffix = "harvester"
			elif income_gap and (not pressure or army_count >= 6) and not (first_tank and now < 130.0): suffix = "harvester"
			elif first_tank: suffix = "tank"
			elif int(counts.get(faction+"_harvester",0)) < miner_target: suffix = "harvester"
			elif int(ready_roles.get("tech",0)) > 0 and int(counts.get(faction+"_artillery",0)) < maxi(1, int(army_count/8)): suffix = "artillery"
			elif int(counts.get(faction+"_tank",0)) < maxi(1, int(infantry_count/4)): suffix = "tank"
			elif army_count >= 10 and int(counts.get(faction+"_scout",0)) < 1: suffix = "scout"
		elif role == "barracks" and infantry_count < 28:
			var anti: int = int(counts.get(faction+"_anti",0))
			var marksmen: int = int(counts.get(faction+"_marksman",0))
			var gunners: int = int(counts.get(faction+"_gunner",0))
			if int(counts.get(faction+"_aa_infantry",0)) < 2 and _visible_air(observation) > 0: suffix = "aa_infantry"
			elif enemy_armor > enemy_infantry and anti < maxi(2,int(marksmen*0.75)): suffix = "anti"
			elif marksmen < maxi(2,anti*2): suffix = "marksman"
			elif gunners < maxi(1, int(infantry_count/9)): suffix = "gunner"
			else: suffix = "anti"
		if suffix.is_empty(): continue
		var spec: String = faction + "_" + suffix
		var cost: float = float(rules.get("units", {}).get(spec, {}).get("cost", 0.0)) * int(rules.get("units", {}).get(spec, {}).get("squad_size", 1))
		var production_reserve: float = reserve
		if role == "barracks" and first_tank and now < 130.0 and not pressure: production_reserve = maxf(production_reserve, float(rules.get("units", {}).get(faction+"_tank",{}).get("cost",780.0)))
		if role == "barracks" and income_gap and (not pressure or army_count >= 6): production_reserve = maxf(production_reserve, float(rules.get("units", {}).get(faction+"_harvester",{}).get("cost",510.0)))
		if cost <= 0.0 or money < cost + production_reserve: continue
		commands.append({"action":"produce","id":int(producer.id),"spec":spec})
		money -= cost
		counts[spec] = int(counts.get(spec,0)) + 1
		if suffix == "tank": first_tank = false
		if suffix == "harvester" and int(counts.get(spec,0)) >= 2: income_gap = false
	memory.economy_goal = goal
	return {"commands":commands,"goal":goal if not goal.is_empty() else "army"}

func _visible_air(observation: Dictionary) -> int:
	var result: int = 0
	for enemy: Dictionary in observation.get("visible_enemies", []):
		if str(enemy.get("domain", "ground")) == "air": result += 1
	return result

func _armed_mobile(unit: Dictionary) -> bool:
	return str(unit.get("kind", "")) == "unit" and not str(unit.get("weapon", "")).is_empty() and str(unit.get("art", "")) != "engineer"

func _health(unit: Dictionary) -> float:
	return clampf(float(unit.get("hp", 0.0)) / maxf(1.0, float(unit.get("max_hp", 1.0))), 0.0, 1.0)

func _combat_value(unit: Dictionary) -> float:
	return float(unit.get("cost",0.0)) * (0.4+0.6*_health(unit)) * (1.4 if str(unit.get("armor_class","")) == "infantry" else 0.8)

func _same_attack(unit: Dictionary, target: int) -> bool:
	var orders: Array = unit.get("commands", [])
	return not orders.is_empty() and str(orders[0].get("kind", "")) == "attack" and int(orders[0].get("target", -1)) == target

func _move_if_needed(commands: Array, unit: Dictionary, destination: Vector2, kind: String, tolerance: float) -> void:
	var orders: Array = unit.get("commands", [])
	var needed: bool = orders.is_empty()
	if not orders.is_empty():
		var current: Dictionary = orders[0]
		needed = str(current.get("kind", "")) != kind or (current.get("pos", unit.pos) as Vector2).distance_to(destination) > tolerance
	if needed and (unit.pos as Vector2).distance_to(destination) > 3.0:
		commands.append({"action":"issue","ids":[int(unit.id)],"kind":kind,"pos":destination})
	elif needed and not orders.is_empty() and str(orders[0].get("kind","")) == "attack":
		commands.append({"action":"issue","ids":[int(unit.id)],"kind":"stop"})

func _choose_target(unit: Dictionary, enemies: Array, rules: Dictionary, claims: Dictionary) -> Dictionary:
	var weapon: Dictionary = rules.get("weapons", {}).get(str(unit.get("weapon", "")), {})
	var targets: Array = weapon.get("targets", [])
	var reach: float = float(weapon.get("range", 0.0)) + 0.2
	var best: Dictionary = {}
	var best_score: float = -INF
	for enemy: Dictionary in enemies:
		if str(enemy.get("domain", "ground")) not in targets: continue
		var distance: float = (unit.pos as Vector2).distance_to(enemy.pos)
		if distance > reach: continue
		var category: String = "building" if str(enemy.get("kind", "")) == "building" else str(enemy.get("armor_class", "armored"))
		var multiplier: float = float(weapon.get("multipliers", {}).get(category, 1.0))
		var score: float = 10.0 * multiplier + (1.0-_health(enemy))*3.0-distance*0.15
		if str(enemy.get("kind", "")) == "unit" and not str(enemy.get("weapon","")).is_empty(): score += 5.0
		if str(enemy.get("art", "")) == "anti" and str(unit.get("art", "")) in ["marksman","gunner"]: score += 5.0
		if str(enemy.get("art", "")) == "harvester": score += 1.0
		score -= minf(5.0,float(claims.get(int(enemy.id),0.0))/maxf(1.0,float(enemy.hp))*3.0)
		if score > best_score: best_score = score; best = enemy
	return best

func _objective(enemies: Array, memory: Dictionary, fallback: Vector2, home: Vector2) -> Vector2:
	var result: Vector2 = fallback
	var best: float = INF
	for enemy: Dictionary in enemies:
		if str(enemy.get("kind", "")) != "building" or str(enemy.get("role", "")) in ["rail", "wall", "barricade", "rail_junction"]: continue
		var distance: float = home.distance_to(enemy.pos)
		if distance < best: best = distance; result = enemy.pos
	if is_finite(best): memory.last_objective = result; return result
	return memory.get("last_objective", fallback)
