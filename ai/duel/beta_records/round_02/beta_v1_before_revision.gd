extends RefCounted

## Beta v1: combined arms, a deliberate first muster, and local target choice.
## Only the supplied observation and this seat's memory are used.
const VERSION := "beta_v1_combined_muster"

func decide(observation: Dictionary, memory: Dictionary) -> Dictionary:
	var now: float = float(observation.get("time", 0.0))
	var home: Vector2 = observation.get("home", Vector2.ZERO)
	var enemy_start: Vector2 = observation.get("enemy_start", home)
	var forward: Vector2 = (enemy_start - home).normalized()
	var own: Array = observation.get("own", [])
	var enemies: Array = observation.get("visible_enemies", [])
	var rules: Dictionary = observation.get("rules", {})
	var roles: Dictionary = observation.get("roles", {})
	var army: Array = []
	var army_value: float = 0.0
	var own_infantry: int = 0
	var own_vehicles: int = 0
	var home_threat_value: float = 0.0
	var enemy_infantry: int = 0
	var enemy_armor: int = 0
	var enemy_air: int = 0
	var threat: Dictionary = {}
	var threat_score: float = INF
	for unit: Dictionary in own:
		if not _armed_mobile(unit) or bool(unit.get("emerging", false)) or int(unit.get("loaded_in", -1)) >= 0: continue
		army.append(unit)
		army_value += float(unit.get("cost", 0.0)) * (0.4 + 0.6 * _health(unit))
		if str(unit.get("armor_class", "")) == "infantry": own_infantry += 1
		elif str(unit.get("domain", "ground")) == "ground": own_vehicles += 1
	for enemy: Dictionary in enemies:
		if str(enemy.get("kind", "")) == "building":
			var known: Dictionary = memory.get("known_buildings", {})
			known[str(enemy.id)] = {"pos":enemy.pos,"role":enemy.get("role", ""),"seen":now}
			memory.known_buildings = known
			continue
		if str(enemy.get("domain", "ground")) == "air": enemy_air += 1
		elif str(enemy.get("armor_class", "")) == "infantry": enemy_infantry += 1
		elif not str(enemy.get("weapon", "")).is_empty(): enemy_armor += 1
		if str(enemy.get("weapon", "")).is_empty(): continue
		var distance: float = (enemy.pos as Vector2).distance_to(home)
		var near_asset: bool = distance < 40.0
		for asset: Dictionary in own:
			if str(asset.get("art", "")) == "harvester" or (str(asset.get("kind", "")) == "building" and str(asset.get("role", "")) in ["refinery", "factory", "hq"]):
				if (enemy.pos as Vector2).distance_to(asset.pos) < 16.0: near_asset = true
		if near_asset:
			home_threat_value += float(enemy.get("cost", 0.0)) * (0.4 + 0.6 * _health(enemy))
			if distance < threat_score: threat_score = distance; threat = enemy
	var pressure: bool = home_threat_value > 0.0
	var phase: String = str(memory.get("phase", "muster"))
	var peak: float = maxf(float(memory.get("attack_peak", 0.0)), army_value)
	if phase == "attack" and pressure and home_threat_value > army_value * 0.8:
		phase = "defend"
		memory.recover_until = now + 18.0
	elif phase == "attack" and army_value < peak * 0.42 and army.size() < 5:
		phase = "muster"
		memory.recover_until = now + 18.0
		peak = army_value
	elif not pressure and now >= float(memory.get("recover_until", 0.0)) and (army.size() >= 9 and army_value >= 1900.0 or now >= 150.0 and army.size() >= 6 and army_value >= 1500.0):
		phase = "attack"
	elif pressure and phase != "attack": phase = "defend"
	elif phase == "defend" and not pressure: phase = "muster"
	memory.phase = phase
	memory.attack_peak = peak
	memory.version = VERSION
	var infantry: Array = ["anti", "gunner", "anti", "marksman", "gunner", "anti"]
	if enemy_armor > enemy_infantry:
		infantry = ["anti", "anti", "marksman", "anti", "gunner"]
	elif enemy_infantry >= 5 and enemy_infantry > enemy_armor * 2:
		infantry = ["gunner", "marksman", "gunner", "anti"]
	var tech_ready: bool = not pressure and army.size() >= 12 and int(roles.get("refinery", 0)) >= 2
	var air_ready: bool = not pressure and army.size() >= 18 and float(observation.get("money", 0.0)) >= 1600.0
	var profile: Dictionary = {
		"style":"balanced", "infantry":infantry,
		"vehicles":["tank", "tank", "scout", "tank", "artillery"],
		"air":["attacker", "helicopter"],
		"infantry_limit":24 if enemy_armor > enemy_infantry else 20,
		"factory_share":0.18 if pressure else 0.32,
		"expansion_after":75.0 if not pressure and army.size() >= 5 else 86400.0,
		"tech_after":235.0 if tech_ready else 86400.0,
		"air_after":360.0 if air_ready else 86400.0,
		"factory_after":200.0 if not pressure and army.size() >= 12 else 86400.0,
		"builders":1, "tower_limit":1 if pressure and army.size() >= 6 else 0,
		"wave_scale":1.0, "attack_scale":1.0
	}
	var goal: Vector2 = _objective(enemies, memory, enemy_start, home)
	var rally: Vector2 = home + forward * (23.0 if army.size() >= 5 else 13.0)
	var commands: Array = []
	for unit: Dictionary in army:
		if now < float(unit.get("ai_traffic_until", 0.0)): continue
		var target: Dictionary = _choose_target(unit, enemies, rules)
		if not target.is_empty():
			if not _same_attack(unit, int(target.id)):
				commands.append({"action":"issue", "ids":[int(unit.id)], "kind":"attack", "target":int(target.id), "pos":target.pos})
			continue
		var destination: Vector2 = goal if phase == "attack" else rally
		if pressure and not threat.is_empty() and (unit.pos as Vector2).distance_to(threat.pos) < 48.0:
			destination = threat.pos
		var orders: Array = unit.get("commands", [])
		var needs_order: bool = orders.is_empty()
		if not orders.is_empty():
			var current: Dictionary = orders[0]
			var kind: String = str(current.get("kind", ""))
			if kind == "attack": needs_order = true
			elif kind in ["move", "attack_move", "patrol"]:
				var current_goal: Vector2 = current.get("pos", unit.pos)
				needs_order = current_goal.distance_to(destination) > 8.0
		if needs_order and (unit.pos as Vector2).distance_to(destination) > 4.0:
			commands.append({"action":"issue", "ids":[int(unit.id)], "kind":"attack_move", "pos":destination})
	return {"profile":profile, "settings":{"wave":9,"attack_gap":24.0}, "shared_economy":true, "shared_tactics":false, "commands":commands.slice(0, 96), "reason":"%s %s army=%d value=%.0f inf=%d vehicles=%d visible_i/a/air=%d/%d/%d home_threat=%.0f" % [VERSION,phase,army.size(),army_value,own_infantry,own_vehicles,enemy_infantry,enemy_armor,enemy_air,home_threat_value]}

func _armed_mobile(unit: Dictionary) -> bool:
	return str(unit.get("kind", "")) == "unit" and not str(unit.get("weapon", "")).is_empty() and str(unit.get("art", "")) != "engineer"

func _health(unit: Dictionary) -> float:
	return clampf(float(unit.get("hp", 0.0)) / maxf(1.0, float(unit.get("max_hp", 1.0))), 0.0, 1.0)

func _same_attack(unit: Dictionary, target: int) -> bool:
	var orders: Array = unit.get("commands", [])
	return not orders.is_empty() and str(orders[0].get("kind", "")) == "attack" and int(orders[0].get("target", -1)) == target

func _choose_target(unit: Dictionary, enemies: Array, rules: Dictionary) -> Dictionary:
	var weapon: Dictionary = rules.get("weapons", {}).get(str(unit.get("weapon", "")), {})
	var targets: Array = weapon.get("targets", [])
	var reach: float = float(weapon.get("range", 0.0)) + 1.3
	var best: Dictionary = {}
	var best_score: float = -INF
	for enemy: Dictionary in enemies:
		var domain: String = str(enemy.get("domain", "ground"))
		if domain not in targets: continue
		var distance: float = (unit.pos as Vector2).distance_to(enemy.pos)
		if distance > reach: continue
		var category: String = "building" if str(enemy.get("kind", "")) == "building" else str(enemy.get("armor_class", "armored"))
		var multiplier: float = float(weapon.get("multipliers", {}).get(category, 1.0))
		var score: float = 10.0 * multiplier + (1.0 - _health(enemy)) * 4.0 - distance * 0.2
		if str(enemy.get("kind", "")) == "unit": score += 4.0
		if str(enemy.get("art", "")) == "harvester": score += 2.0
		if str(enemy.get("weapon", "")).is_empty(): score -= 1.0
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
