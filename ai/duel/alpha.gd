extends RefCounted

## Alpha v7: restore screened fire discipline and support advances with vision and armor.
const VERSION := "alpha_v7_screened_combined_advance"

func decide(observation: Dictionary, memory: Dictionary) -> Dictionary:
	var now: float = float(observation.time)
	var home: Vector2 = observation.home
	var forward: Vector2 = (observation.enemy_start - home).normalized()
	var own: Array = observation.own
	var enemies: Array = observation.visible_enemies
	var fighters: Array = []
	var infantry: int = 0
	var vehicles: int = 0
	var armor_enemies: int = 0
	var infantry_enemies: int = 0
	var air_enemies: int = 0
	var home_threat: float = 0.0
	var nearest_enemy: float = INF
	var army_value: float = 0.0
	var progress: Array = []
	var assets: Array = [home]
	for entity: Dictionary in own:
		if entity.kind == "building" and str(entity.role) in ["hq", "refinery", "factory"]: assets.append(entity.pos)
		if not _fighter(entity) or str(entity.domain) != "ground": continue
		fighters.append(entity)
		army_value += _strength(entity)
		progress.append((entity.pos - home).dot(forward))
		if str(entity.armor_class) == "infantry": infantry += 1
		else: vehicles += 1
	for enemy: Dictionary in enemies:
		if not _fighter(enemy): continue
		nearest_enemy = minf(nearest_enemy, (enemy.pos as Vector2).distance_to(home))
		if str(enemy.domain) == "air": air_enemies += 1
		elif str(enemy.armor_class) == "infantry": infantry_enemies += 1
		else: armor_enemies += 1
		for asset: Vector2 in assets:
			if (enemy.pos as Vector2).distance_to(asset) < 24.0:
				home_threat += _strength(enemy)
				break
	progress.sort()
	var middle: float = float(progress[progress.size() / 2]) if not progress.is_empty() else 0.0
	var roles: Dictionary = observation.roles
	var count: int = fighters.size()
	var refineries: int = int(roles.get("refinery", 0))
	var supplied: bool = int(roles.get("power", 0)) >= 2
	var assault: bool = bool(memory.get("assault", false))
	var rally: Vector2 = home + forward * 28.0
	var gathered: int = 0
	for unit: Dictionary in fighters:
		if (unit.pos as Vector2).distance_to(rally) < 15.0: gathered += 1
	if not assault and count >= 14 and gathered >= 11 and home_threat < army_value * 0.6 and nearest_enemy > 55.0:
		assault = true
		memory.assault_start = now
	if assault and count < 4:
		assault = false
		memory.regroup_at = now
	memory.assault = assault
	memory.version = VERSION
	var phase: String = "advance" if assault else "assemble"
	if home_threat > army_value * 0.55 and home_threat > 250.0: phase = "defend"
	var goal: Vector2 = rally
	if assault:
		# The moving waypoint follows the median fighter, limiting the gap
		# between the infantry screen and freshly emerged rear factory tanks.
		var target_progress: float = clampf(middle + 10.0, 28.0, home.distance_to(observation.enemy_start))
		goal = home + forward * target_progress
		for enemy: Dictionary in enemies:
			if str(enemy.kind) == "building" and str(enemy.role) not in ["rail", "rail_junction", "wall", "barricade"]:
				if (enemy.pos as Vector2).distance_to(goal) < 20.0: goal = enemy.pos
	if phase == "defend" and middle < 45.0: goal = home + forward * 20.0
	elif not assault and nearest_enemy < 55.0:
		phase = "screen"
		goal = home + forward * 20.0
	memory.phase = phase
	memory.goal = goal
	memory.median_progress = middle

	# v1 reserved 374 funds after every infantry purchase; its live infantry
	# never reached eight. Cheap counter units now precede additional tanks.
	var infantry_cycle: Array = ["anti", "gunner", "marksman", "anti", "marksman", "anti", "marksman"]
	if armor_enemies >= infantry_enemies + 2:
		infantry_cycle = ["anti", "anti", "marksman", "anti", "marksman"]
	elif infantry_enemies >= armor_enemies * 2 + 3:
		infantry_cycle = ["marksman", "anti", "marksman", "gunner", "marksman", "anti"]
	var vehicle_cycle: Array = ["tank", "tank", "scout", "tank"]
	if int(observation.counts.get("kestrel_scout", 0)) > 0: vehicle_cycle = ["tank", "tank", "tank", "tank"]
	if int(roles.get("tech", 0)) > 0: vehicle_cycle = ["tank", "artillery", "tank", "heavy_tank"]
	var hold_growth: bool = phase == "defend" and count < 9
	var profile: Dictionary = {
		"style": "balanced", "infantry": infantry_cycle, "vehicles": vehicle_cycle,
		"air": ["helicopter"], "infantry_limit": 24,
		"factory_share": 0.10 if infantry < 12 else 0.42,
		"wave_scale": 1.0, "attack_scale": 1.0,
		"expansion_after": 150.0 if supplied and not hold_growth else now + 90.0,
		"tech_after": 650.0 if refineries >= 2 and count >= 12 and not hold_growth else now + 180.0,
		"air_after": 480.0 if refineries >= 2 and count >= 12 and not hold_growth else now + 180.0,
		"factory_after": 800.0 if count >= 14 else now + 180.0,
		"builders": 1, "tower_limit": 1 if count >= 6 else 0
	}
	if air_enemies > 0: profile.air_after = minf(float(profile.air_after), 440.0)
	var commands: Array = []
	var completed_refineries: int = 0
	for owned: Dictionary in own:
		if str(owned.role) == "refinery" and float(owned.get("construct_remaining", 0.0)) <= 0.0: completed_refineries += 1
	if completed_refineries >= 2: memory.own_budget_active = true
	var economy: bool = not bool(memory.get("own_budget_active", false))
	if not economy:
		commands.append_array(_economy(observation, memory, count, infantry, armor_enemies, air_enemies))
	else:
		var order: Dictionary = observation.orders.get("normal", {})
		# Preserve the validated public miner/factory opening and pay for the
		# second generator before its ordinary second refinery reservation.
		if now >= 140.0 and count >= 5 and not supplied and refineries >= 1 and int(roles.get("factory", 0)) > 0 and order.is_empty() and float(observation.money) >= 360.0:
			commands.append({"action": "build", "spec": "kestrel_power"})
			economy = false
	commands.append_array(_tactics(observation, memory, fighters, goal))
	commands.append_array(_miner_circulation(observation, memory))
	commands.append_array(_air_support(observation, goal))
	return {
		"profile": profile, "settings": {"wave": 12, "attack_gap": 36.0},
		"shared_economy": economy, "shared_tactics": false, "commands": commands,
		"reason": "%s phase=%s fighters=%d inf=%d vehicles=%d gathered=%d median=%.1f home_threat=%.0f money=%.0f power_ready=%s orders=%d" % [VERSION, phase, count, infantry, vehicles, gathered, middle, home_threat, float(observation.money), str(supplied), commands.size()]
	}

func _fighter(entity: Dictionary) -> bool:
	return str(entity.kind) == "unit" and not str(entity.get("weapon", "")).is_empty() and str(entity.get("art", "")) != "engineer" and int(entity.get("loaded_in", -1)) < 0 and not bool(entity.get("emerging", false))

func _strength(entity: Dictionary) -> float:
	return float(entity.get("cost", 100.0)) * (0.35 + 0.65 * clampf(float(entity.hp) / maxf(1.0, float(entity.max_hp)), 0.0, 1.0))

func _tactics(observation: Dictionary, memory: Dictionary, fighters: Array, goal: Vector2) -> Array:
	var result: Array = []
	var now: float = float(observation.time)
	var weapons: Dictionary = observation.rules.get("weapons", {})
	var orders: Dictionary = memory.get("orders", {})
	memory.orders = orders
	var enemies: Array = observation.visible_enemies
	var enemy_by_id: Dictionary = {}
	for enemy: Dictionary in enemies: enemy_by_id[int(enemy.id)] = enemy
	for unit: Dictionary in fighters:
		if result.size() >= 70: break
		if float(unit.get("ai_traffic_until", 0.0)) > now: continue
		var current: Array = unit.get("commands", [])
		if str(unit.art) == "scout" and str(memory.get("phase", "")) == "advance":
			var forward: Vector2 = (observation.enemy_start - observation.home).normalized()
			var side: Vector2 = Vector2.DOWN if absf(forward.x) > 0.9 else forward.orthogonal()
			var spot: Vector2 = goal - forward * 10.0 + side * 9.0
			if str(memory.get("phase", "")) != "advance": spot = observation.home + forward * 25.0 + side * 9.0
			var scout_key: String = str(unit.id)
			var old: Dictionary = orders.get(scout_key, {})
			var pursuing: bool = not current.is_empty() and str(current[0].get("kind", "")) == "attack"
			if ((unit.pos as Vector2).distance_to(spot) > 3.5 or pursuing) and now - float(old.get("time", -100.0)) >= 4.0:
				result.append({"action": "issue", "id": int(unit.id), "kind": "move", "pos": spot})
				orders[scout_key] = {"kind": "spot", "time": now}
			continue
		var weapon: Dictionary = weapons.get(str(unit.weapon), {})
		var reach: float = float(weapon.get("range", 5.0))
		var best: Dictionary = {}
		var best_score: float = -INF
		for enemy: Dictionary in enemies:
			if str(enemy.domain) not in weapon.get("targets", []): continue
			if str(enemy.role) in ["rail", "rail_junction", "wall", "barricade"]: continue
			var distance: float = (unit.pos as Vector2).distance_to(enemy.pos)
			if distance > reach + (1.2 if str(unit.art) == "marksman" and str(memory.get("phase", "")) == "advance" else 0.65): continue
			var infantry_target: bool = str(enemy.armor_class) == "infantry"
			var score: float = 20.0 - distance * 0.6
			if not str(enemy.weapon).is_empty(): score += 12.0
			if str(unit.art) in ["gunner", "marksman", "scout", "rifle"]:
				score += 24.0 if infantry_target else -18.0
			else:
				score += 20.0 if not infantry_target else 0.0
			if str(enemy.art) == "marksman": score += 22.0
			elif str(enemy.art) in ["anti", "gunner", "artillery"]: score += 7.0
			score += (1.0 - float(enemy.hp) / maxf(1.0, float(enemy.max_hp))) * 10.0
			if score > best_score:
				best_score = score
				best = enemy
		var key: String = str(unit.id)
		var previous: Dictionary = orders.get(key, {})
		if not best.is_empty():
			if not current.is_empty() and str(current[0].get("kind", "")) == "attack" and int(current[0].get("target", -1)) == int(best.id): continue
			if now - float(previous.get("time", -100.0)) < 2.0: continue
			result.append({"action": "issue", "id": int(unit.id), "kind": "attack", "pos": best.pos, "target": int(best.id)})
			orders[key] = {"kind": "attack", "time": now, "target": int(best.id)}
			continue
		# Avoid pursuing a formerly in-range target away from the combined force.
		var needs_move: bool = current.is_empty()
		if not current.is_empty():
			var kind: String = str(current[0].get("kind", ""))
			if kind == "attack":
				var target: Dictionary = enemy_by_id.get(int(current[0].get("target", -1)), {})
				needs_move = target.is_empty() or (unit.pos as Vector2).distance_to(target.pos) > reach + 1.5
			elif kind in ["move", "attack_move"]:
				needs_move = (current[0].get("pos", goal) as Vector2).distance_to(goal) > 8.0
		if needs_move and (unit.pos as Vector2).distance_to(goal) > 3.0 and now - float(previous.get("time", -100.0)) >= 4.0:
			result.append({"action": "issue", "id": int(unit.id), "kind": "attack_move", "pos": goal})
			orders[key] = {"kind": "attack_move", "time": now, "goal": goal}
	return result

func _miner_circulation(observation: Dictionary, memory: Dictionary) -> Array:
	var now: float = float(observation.time)
	var history: Dictionary = memory.get("miner_positions", {})
	memory.miner_positions = history
	var refineries: Array = []
	var miners: Array = []
	var loads: Dictionary = {}
	for entity: Dictionary in observation.own:
		if str(entity.role) == "refinery" and float(entity.get("construct_remaining", 0.0)) <= 0.0:
			refineries.append(entity)
			loads[int(entity.id)] = 0
		elif str(entity.art) == "harvester": miners.append(entity)
	for miner: Dictionary in miners:
		var job: Dictionary = miner.get("refinery_waiting", {})
		if job.is_empty(): job = miner.get("refinery_docking", {})
		var source: int = int(job.get("source", -1))
		if source >= 0: loads[source] = int(loads.get(source, 0)) + 1
	var result: Array = []
	for miner: Dictionary in miners:
		var key: String = str(miner.id)
		var last: Dictionary = history.get(key, {"pos": miner.pos, "cargo": miner.get("cargo", 0.0), "progress_at": now, "retry_at": 0.0})
		if (miner.pos as Vector2).distance_to(last.pos) > 0.3 or absf(float(miner.get("cargo", 0.0)) - float(last.cargo)) > 1.0:
			last.progress_at = now
			last.pos = miner.pos
			last.cargo = miner.get("cargo", 0.0)
		history[key] = last
		if not result.is_empty() or refineries.size() < 2: continue
		if now - float(last.progress_at) < 10.0 or now < float(last.retry_at): continue
		if float(miner.get("cargo", 0.0)) < 100.0 or float(miner.get("ai_traffic_until", 0.0)) > now: continue
		# Keep normal docking reservations and inside traversal intact. Redirect
		# only an external waiting vehicle to the other paid owned refinery.
		if not miner.get("refinery_docking", {}).is_empty() or bool(miner.get("emerging", false)): continue
		var waiting: Dictionary = miner.get("refinery_waiting", {})
		if waiting.is_empty(): continue
		var source: int = int(waiting.get("source", -1))
		var best: Dictionary = {}
		var score: float = INF
		for refinery: Dictionary in refineries:
			var id: int = int(refinery.id)
			if id == source or int(loads.get(id, 0)) >= int(loads.get(source, 0)): continue
			var candidate: float = (miner.pos as Vector2).distance_to(refinery.pos) + float(loads.get(id, 0)) * 12.0
			if candidate < score:
				score = candidate
				best = refinery
		if best.is_empty(): continue
		result.append({"action": "issue", "id": int(miner.id), "kind": "return_miner", "pos": best.pos, "target": int(best.id)})
		last.retry_at = now + 20.0
		last.progress_at = now
	return result

func _air_support(observation: Dictionary, goal: Vector2) -> Array:
	var result: Array = []
	var weapons: Dictionary = observation.rules.get("weapons", {})
	for unit: Dictionary in observation.own:
		if not _fighter(unit) or str(unit.domain) != "air": continue
		if str(unit.get("flight_state", "")) in ["returning", "rearming", "landing"]: continue
		if float(unit.get("ai_traffic_until", 0.0)) > float(observation.time): continue
		var weapon: Dictionary = weapons.get(str(unit.weapon), {})
		var best: Dictionary = {}
		var score: float = -INF
		for enemy: Dictionary in observation.visible_enemies:
			if str(enemy.domain) not in weapon.get("targets", []): continue
			if str(enemy.role) in ["rail", "rail_junction", "wall", "barricade"]: continue
			var distance: float = (unit.pos as Vector2).distance_to(enemy.pos)
			var candidate: float = 35.0 - distance
			if str(enemy.art) == "marksman": candidate += 20.0
			if not str(enemy.weapon).is_empty(): candidate += 10.0
			if candidate > score:
				score = candidate
				best = enemy
		var current: Array = unit.get("commands", [])
		if not best.is_empty():
			if not current.is_empty() and str(current[0].get("kind", "")) == "attack" and int(current[0].get("target", -1)) == int(best.id): continue
			result.append({"action": "issue", "id": int(unit.id), "kind": "attack", "pos": best.pos, "target": int(best.id)})
		elif current.is_empty() and (unit.pos as Vector2).distance_to(goal) > 5.0:
			result.append({"action": "issue", "id": int(unit.id), "kind": "attack_move", "pos": goal})
	return result

func _economy(observation: Dictionary, memory: Dictionary, army_count: int, infantry_count: int, enemy_armor: int, enemy_air: int) -> Array:
	var commands: Array = []
	var now: float = float(observation.time)
	var units: Dictionary = observation.rules.units
	var buildings: Dictionary = observation.rules.buildings
	var roles: Dictionary = observation.roles
	var counts: Dictionary = observation.counts.duplicate(true)
	var barracks: Array = []
	var factories: Array = []
	var airfields: Array = []
	var liability: float = 0.0
	for entity: Dictionary in observation.own:
		if str(entity.kind) != "building": continue
		if entity.has("construction"):
			liability += maxf(0.0, float(entity.cost) - float(entity.construction.get("spent", 0.0)))
		for queued: Dictionary in entity.get("queue", []):
			counts[str(queued.spec)] = int(counts.get(str(queued.spec), 0)) + 1
		if float(entity.get("construct_remaining", 0.0)) > 0.0 or not entity.get("queue", []).is_empty(): continue
		match str(entity.role):
			"barracks": barracks.append(entity)
			"factory": factories.append(entity)
			"airfield": airfields.append(entity)
	var budget: float = maxf(0.0, float(observation.money) - liability)
	# Pay for essential income before optional towers or another generator.
	# Queued miners count, so this reservation never orders a duplicate worker.
	var priority_miner_target: int = 1 if army_count < 5 else (4 if int(roles.get("refinery", 0)) >= 2 and army_count >= 16 else 2)
	var income_reserve: float = 0.0
	if int(counts.get("kestrel_harvester", 0)) < priority_miner_target and int(roles.get("factory", 0)) > 0 and int(roles.get("refinery", 0)) > 0:
		income_reserve = float(units.kestrel_harvester.cost)
		for factory: Dictionary in factories:
			if budget < income_reserve: break
			commands.append({"action": "produce", "id": int(factory.id), "spec": "kestrel_harvester"})
			budget -= income_reserve
			counts.kestrel_harvester = int(counts.get("kestrel_harvester", 0)) + 1
			memory[str(factory.id) + "_used_at"] = now
			income_reserve = 0.0
			break
	# A dead front-line scout previously removed all view of the enemy's
	# rear marksmen. One ordinary replacement is cheaper than blind volleys.
	var vision_reserve: float = 0.0
	if income_reserve <= 0.0 and int(counts.get("kestrel_scout", 0)) < 1 and army_count >= 6 and int(roles.get("factory", 0)) > 0:
		vision_reserve = float(units.kestrel_scout.cost)
		for factory: Dictionary in factories:
			if now <= float(memory.get(str(factory.id) + "_used_at", -1.0)): continue
			if budget < vision_reserve: break
			commands.append({"action": "produce", "id": int(factory.id), "spec": "kestrel_scout"})
			budget -= vision_reserve
			counts.kestrel_scout = int(counts.get("kestrel_scout", 0)) + 1
			memory[str(factory.id) + "_used_at"] = now
			vision_reserve = 0.0
			break
	var normal: Dictionary = observation.orders.get("normal", {})
	var defense: Dictionary = observation.orders.get("defense", {})
	var power: Vector2 = observation.power
	var goal: String = ""
	var reserve: float = maxf(income_reserve, vision_reserve)
	if normal.is_empty() and income_reserve <= 0.0 and vision_reserve <= 0.0:
		if power.x < power.y + 30.0 or int(roles.get("power", 0)) == 0: goal = "power"
		elif int(roles.get("refinery", 0)) == 0: goal = "refinery"
		elif int(roles.get("barracks", 0)) == 0: goal = "barracks"
		elif int(roles.get("factory", 0)) == 0: goal = "factory"
		elif now >= 140.0 and army_count >= 5 and int(roles.get("power", 0)) < 2: goal = "power"
		elif now >= 180.0 and army_count >= 8 and int(roles.get("refinery", 0)) < 2: goal = "refinery"
		elif int(roles.get("airfield", 0)) >= 1 and power.x < power.y + 120.0: goal = "power"
		elif now >= 360.0 and army_count >= 12 and int(roles.get("barracks", 0)) < 2: goal = "barracks"
		elif now >= 480.0 and army_count >= 16 and int(roles.get("airfield", 0)) < 1: goal = "airfield"
		elif now >= 700.0 and army_count >= 20 and int(roles.get("tech", 0)) < 1 and budget > 2100.0: goal = "tech"
		elif now >= 800.0 and army_count >= 20 and int(roles.get("factory", 0)) < 2 and budget > 1300.0: goal = "factory"
		if not goal.is_empty():
			var spec: String = "kestrel_" + goal
			var cost: float = float(buildings[spec].cost)
			if budget >= cost:
				commands.append({"action": "build", "spec": spec})
				budget -= cost
			elif goal in ["power", "refinery", "factory", "barracks"]:
				reserve = cost
	# An early paid tower protects the screened infantry while it reloads.
	# It no longer depends on the generic factory purchasing first.
	if now >= 220.0 and army_count >= 7 and int(roles.get("tower", 0)) < 1 and defense.is_empty():
		var price: float = float(buildings.kestrel_tower.cost)
		if budget >= price + reserve:
			commands.append({"action": "build", "spec": "kestrel_tower"})
			budget -= price
		elif goal.is_empty(): reserve = maxf(reserve, price)
	# Replacement income has priority, then the second ordinary working miner.
	for factory: Dictionary in factories:
		if now <= float(memory.get(str(factory.id) + "_used_at", -1.0)): continue
		var miners: int = int(counts.get("kestrel_harvester", 0))
		var desired: int = 1 if army_count < 5 else (4 if int(roles.get("refinery", 0)) >= 2 and army_count >= 16 else 2)
		if miners >= desired: continue
		var price: float = float(units.kestrel_harvester.cost)
		if budget >= price + (0.0 if miners == 0 else reserve):
			commands.append({"action": "produce", "id": int(factory.id), "spec": "kestrel_harvester"})
			budget -= price
			counts.kestrel_harvester = miners + 1
			factory = factory.duplicate(true)
			factory.queue = [{"spec": "kestrel_harvester"}]
			memory[str(factory.id) + "_used_at"] = now
	# v5 never replaced its first tank even when it had over 1200 funds.
	# Restore one screen vehicle only when it is already affordable together
	# with the next marksman; do not reserve opening income to wait for it.
	if int(counts.get("kestrel_tank", 0)) < 1 and army_count >= 6 and power.x >= power.y:
		var screen_price: float = float(units.kestrel_tank.cost)
		for factory: Dictionary in factories:
			if now <= float(memory.get(str(factory.id) + "_used_at", -1.0)): continue
			if budget < screen_price + reserve + 240.0: break
			commands.append({"action": "produce", "id": int(factory.id), "spec": "kestrel_tank"})
			budget -= screen_price
			counts.kestrel_tank = 1
			memory[str(factory.id) + "_used_at"] = now
			break
	for producer: Dictionary in barracks:
		if infantry_count >= 32: break
		var marks: int = int(counts.get("kestrel_marksman", 0))
		var anti: int = int(counts.get("kestrel_anti", 0))
		var choice: String = "kestrel_marksman" if marks < 4 or float(marks) < float(anti) * 1.6 + 1.0 else "kestrel_anti"
		if enemy_armor >= 4 and anti < enemy_armor * 2: choice = "kestrel_anti"
		if enemy_air > 0 and int(counts.get("kestrel_aa_infantry", 0)) < mini(4, enemy_air + 1): choice = "kestrel_aa_infantry"
		var price: float = float(units[choice].cost) * int(units[choice].get("squad_size", 1))
		if budget >= price + reserve:
			commands.append({"action": "produce", "id": int(producer.id), "spec": choice})
			budget -= price
			counts[choice] = int(counts.get(choice, 0)) + int(units[choice].get("squad_size", 1))
			infantry_count += int(units[choice].get("squad_size", 1))
	# Extra armor uses only money left after the requested infantry purchase.
	for factory: Dictionary in factories:
		if now <= float(memory.get(str(factory.id) + "_used_at", -1.0)): continue
		if infantry_count < 12: continue
		var choice: String = "kestrel_tank"
		if int(roles.get("tech", 0)) > 0 and int(counts.get("kestrel_artillery", 0)) < 3: choice = "kestrel_artillery"
		if enemy_air > 0 and int(counts.get("kestrel_aa", 0)) < 2: choice = "kestrel_aa"
		var price: float = float(units[choice].cost) * int(units[choice].get("squad_size", 1))
		if budget >= price + reserve + 240.0:
			commands.append({"action": "produce", "id": int(factory.id), "spec": choice})
			budget -= price
			counts[choice] = int(counts.get(choice, 0)) + 1
	for field: Dictionary in airfields:
		if int(counts.get("kestrel_helicopter", 0)) >= 4: break
		var price: float = float(units.kestrel_helicopter.cost)
		if budget >= price + reserve + 240.0:
			commands.append({"action": "produce", "id": int(field.id), "spec": "kestrel_helicopter"})
			budget -= price
			counts.kestrel_helicopter = int(counts.get("kestrel_helicopter", 0)) + 1
	return commands
