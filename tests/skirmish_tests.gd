extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
var failures: Array[String] = []
var match_count: int = 0
var match_results: Array[Dictionary] = []


func _initialize() -> void:
	var config: Dictionary = Rules.load_rules()
	if config.is_empty():
		push_error(str(Rules.errors))
		quit(1)
		return
	var modes: Array[String] = ["dev", "handmade"]
	var factions: Array[String] = ["rivet", "kestrel"]
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--mode="):
			modes.assign([argument.trim_prefix("--mode=")])
		elif argument.begins_with("--faction="):
			factions.assign([argument.trim_prefix("--faction=")])
	for mode: String in modes:
		for faction: String in factions:
			match_count += 1
			_run_match(config, faction, mode)
	for message: String in failures:
		push_error(message)
	var report: FileAccess = FileAccess.open("res://artifacts/skirmish_results.json", FileAccess.WRITE)
	if report != null:
		report.store_string(JSON.stringify({"engine": Engine.get_version_info().string, "platform": OS.get_name(), "seed": 24, "physics_delta": 0.1, "initial_money_per_team": 4000, "initial_entities": "one completed HQ per team", "free_spawns_or_money": false, "matches": match_results, "failures": failures}, "\t"))
		report.close()
	print("Paid skirmish tests: %d passed, %d failed" % [match_count - failures.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)


func _run_match(config: Dictionary, faction: String, mode: String) -> void:
	var sim = Sim.new()
	sim.setup(config, mode, 24, faction, true)
	# These matches have precisely the shipping HQ + 4000 start. The controller
	# below only spends through build/produce/place and gives ordinary commands.
	if sim.entities.size() != 2 or sim.money != [4000.0, 4000.0]:
		failures.append(faction + "/" + mode + ": incorrect unassisted skirmish opening")
		return
	var metrics: Dictionary = {"delivery": [0, 0], "produce": [0, 0], "fire": [0, 0], "build": [0, 0]}
	var control_clock: float = 0.0
	var attack_clock: float = 0.0
	var report_clock: float = 0.0
	while sim.result == "" and sim.time < 1800.0:
		if control_clock <= 0.0:
			_controller(sim)
			control_clock = 2.0
		if attack_clock <= 0.0:
			_attack(sim)
			attack_clock = 6.0
		sim.step(0.1)
		control_clock -= 0.1
		attack_clock -= 0.1
		report_clock -= 0.1
		for event: Dictionary in sim.events:
			var kind: String = str(event.kind)
			if not metrics.has(kind):
				continue
			var team: int = int(event.get("team", -1))
			if team < 0 and sim.entities.has(int(event.get("id", -1))):
				team = int(sim.entities[int(event.id)].team)
			if team >= 0 and team <= 1:
				metrics[kind][team] += 1
		sim.events.clear()
		if report_clock <= 0.0:
			report_clock = 300.0
			print("Skirmish ", faction, "/", mode, " t=", roundi(sim.time), " funds=", sim.money, " counts=", [sim.counts(0), sim.counts(1)], " deliveries=", metrics.delivery)
	print("Skirmish final ", faction, "/", mode, " result=", sim.result, " t=", roundi(sim.time), " metrics=", metrics, " counts=", [sim.counts(0), sim.counts(1)])
	var error: String = ""
	if metrics.delivery[0] == 0 or metrics.delivery[1] == 0:
		error += "no complete mining delivery loop; "
	if metrics.produce[0] < 3 or metrics.produce[1] < 3:
		error += "insufficient paid production; "
	if metrics.fire[0] == 0 or metrics.fire[1] == 0:
		error += "no actual combat for both players; "
	if sim.result == "" or (sim.counts(0).y != 0 and sim.counts(1).y != 0):
		error += "no building-elimination conclusion within 30 simulated minutes; "
	match_results.append({"player_faction": faction, "map_mode": mode, "map_size": int(sim.map.size), "result": sim.result, "simulated_seconds": sim.time, "money": sim.money.duplicate(), "final_counts": [[sim.counts(0).x, sim.counts(0).y], [sim.counts(1).x, sim.counts(1).y]], "events": metrics.duplicate(true), "error": error})
	if error != "":
		var diagnostic_path: String = "/tmp/paper_war_stalled_" + faction + "_" + mode + ".save"
		sim.save_game(diagnostic_path)
		print("Stalled snapshot saved: ", diagnostic_path)
		for entity: Dictionary in sim.entities.values():
			print("Stalled entity ", entity.id, " ", entity.spec, " team=", entity.team, " pos=", entity.pos, " state=", entity.state, " commands=", entity.commands, " path_count=", entity.path.size(), " goal=", entity.path_goal, " cargo=", entity.cargo)
		failures.append(faction + "/" + mode + ": " + error)


func _count_role(sim, role: String) -> int:
	var count: int = 0
	for entity: Dictionary in sim.entities.values():
		if int(entity.team) == 0 and entity.kind == "building" and str(sim.data_for(entity.spec).get("role", "")) == role:
			count += 1
	return count


func _controller(sim) -> void:
	var faction: String = sim.factions[0]
	if not sim.building_orders[0].is_empty():
		if bool(sim.building_orders[0].ready):
			_place_ready(sim)
	else:
		var next: String = ""
		var energy: Vector2 = sim.power(0)
		if _count_role(sim, "power") == 0 or energy.y > energy.x:
			next = "power"
		elif _count_role(sim, "refinery") == 0:
			next = "refinery"
		elif _count_role(sim, "barracks") == 0:
			next = "barracks"
		elif _count_role(sim, "factory") == 0:
			next = "factory"
		elif _count_role(sim, "tech") == 0:
			next = "tech"
		elif _count_role(sim, "command") == 0:
			next = "command"
		elif _count_role(sim, "airfield") == 0:
			next = "airfield"
		elif _count_role(sim, "refinery") < 2 and sim.money[0] > 2000.0:
			next = "refinery"
		elif _count_role(sim, "tower") == 0 and sim.money[0] > 1100.0:
			next = "tower"
		if next != "":
			sim.build(0, faction + "_" + next)
	# This paid controller now develops the first-release technology tree.
	# Preserve resources for infrastructure and an aircraft before buying rifles.
	var reserve: float = 0.0
	if sim.building_orders[0].is_empty():
		for role in ["power", "refinery", "barracks", "factory", "tech", "command", "airfield"]:
			if _count_role(sim, role) == 0:
				reserve = float(sim.data_for(faction + "_" + role).cost)
				break
	var air_reserve: float = 0.0
	for entity in sim.entities.values():
		if entity.team == 0 and sim.data_for(entity.spec).get("role") == "airfield" and sim._airfield_load(entity.id) < 2:
			air_reserve = float(sim.data_for(faction + ("_bomber" if faction == "rivet" else "_attacker")).cost)
	var ground_reserve: float = maxf(reserve, air_reserve)
	var harvesters: int = 0
	var combat_count: int = 0
	for entity: Dictionary in sim.entities.values():
		if int(entity.team) == 0 and entity.kind == "unit":
			if str(entity.spec).ends_with("_harvester"):
				harvesters += 1
			elif str(sim.data_for(entity.spec).get("weapon", "")) != "":
				combat_count += 1
	for entity: Dictionary in sim.entities.values():
		if int(entity.team) != 0 or entity.kind != "building" or float(entity.construct_remaining) > 0.0 or not entity.queue.is_empty():
			continue
		var role: String = str(sim.data_for(entity.spec).get("role", ""))
		if role == "factory":
			if harvesters < 2:
				sim.produce(int(entity.id), faction + "_harvester")
			else:
				var choice: String = faction + "_tank"
				if sim._enemy_air_count(0)>0 and combat_count%3==0: choice=faction+"_aa"
				elif _count_role(sim,"tech")>0: choice=faction+("_assault" if faction=="rivet" else "_artillery")
				if sim.money[0]>=ground_reserve+float(sim.data_for(choice).cost):sim.produce(int(entity.id),choice)
		elif role == "airfield":
			var plane: String = faction + ("_bomber" if faction=="rivet" else "_attacker")
			if sim._enemy_air_count(0)>0 and sim._airfield_load(entity.id)%2==1:plane=faction+"_fighter"
			if sim.money[0]>=reserve+float(sim.data_for(plane).cost):sim.produce(entity.id,plane)
		elif role == "barracks":
			if sim.money[0] > ground_reserve+220.0:
				var unit: String = "anti" if combat_count % 4 == 3 else "rifle"
				sim.produce(int(entity.id), faction + "_" + unit)


func _place_ready(sim) -> void:
	for entity: Dictionary in sim.entities.values():
		if int(entity.team) != 0 or entity.kind != "building" or float(entity.construct_remaining) > 0.0 or not bool(sim.data_for(entity.spec).get("expands", false)):
			continue
		for radius: int in range(5, 13):
			for direction: int in range(24):
				var pos: Vector2 = entity.pos + Vector2.from_angle(TAU * float(direction) / 24.0 + 0.31) * radius
				if sim.placement_error(0, pos) == "":
					sim.place_building(0, pos)
					return


func _attack(sim) -> void:
	var fighters: Array = []
	for entity: Dictionary in sim.entities.values():
		if int(entity.team) == 0 and entity.kind == "unit" and str(sim.data_for(entity.spec).get("weapon", "")) != "":
			fighters.append(int(entity.id))
	if fighters.is_empty():
		return
	var base: Vector2 = Vector2(float(sim.map.starts[0][0]), float(sim.map.starts[0][1]))
	var threat: int = -1
	var distance: float = 23.0
	for entity: Dictionary in sim.entities.values():
		if int(entity.team) != 0 and entity.kind == "unit":
			var separation: float = base.distance_to(entity.pos)
			if separation < distance:
				distance = separation
				threat = int(entity.id)
	if threat >= 0:
		for id: int in fighters:
			if not sim._weapon_can_target(sim.entities[id],threat): continue
			if sim.entities[id].commands.is_empty() or int(sim.entities[id].commands[0].get("target", -1)) != threat:
				sim.issue([id], "attack", sim.entities[threat].pos, threat)
		return
	if fighters.size() < 5 and sim.time < 420.0:
		return
	var target: int = -1
	distance = INF
	for entity: Dictionary in sim.entities.values():
		if int(entity.team) != 0 and entity.kind == "building":
			var separation: float = base.distance_to(entity.pos)
			if separation < distance:
				distance = separation
				target = int(entity.id)
	if target >= 0:
		for id: int in fighters:
			if not sim._weapon_can_target(sim.entities[id],target):
				sim.issue([id],"attack_move",sim.entities[target].pos)
				continue
			if sim.entities[id].commands.is_empty() or int(sim.entities[id].commands[0].get("target", -1)) != target:
				sim.issue([id], "attack", sim.entities[target].pos, target)
