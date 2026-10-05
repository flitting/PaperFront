extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
var config: Dictionary
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	config = Rules.load_rules("res://data/rules.json", false)
	if config.is_empty():
		push_error("Engineer rule fixture is invalid: " + str(Rules.errors))
		quit(1)
		return
	_test_headquarters_limit()
	_test_capture_and_exclusions()
	_test_capture_production_refunds()
	_test_capture_airfield()
	_test_instant_building_repair()
	_test_outpost_deployment()
	_test_outpost_without_headquarters()
	_test_builder_loss_selection()
	_test_command_snapshots()
	print("Engineer rule checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _sim(faction: String = "rivet"):
	var sim = Sim.new()
	sim.setup(config, "dev", 7, faction, false)
	sim.money.assign([100000.0, 100000.0])
	return sim


func _tick(sim, seconds: float) -> void:
	var remaining: float = seconds
	while remaining > 0.000001:
		var delta: float = minf(1.0 / 30.0, remaining)
		sim.step(delta)
		remaining -= delta


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.001


func _outpost_at(sim, pos: Vector2) -> int:
	for e: Dictionary in sim.entities.values():
		if e.team == 0 and e.kind == "building" and sim.data_for(e.spec).get("role", "") == "outpost" and (e.pos as Vector2).is_equal_approx(pos):
			return int(e.id)
	return -1


func _wait_for_outpost(sim, pos: Vector2, seconds: float = 15.0) -> int:
	for tick: int in range(ceili(seconds * 30.0)):
		sim.step(1.0 / 30.0)
		var id: int = _outpost_at(sim, pos)
		if id >= 0:
			return id
	return -1


func _test_headquarters_limit() -> void:
	for faction: String in ["rivet", "kestrel"]:
		var sim = _sim(faction)
		var money_before: float = sim.money[0]
		_check(not sim.build(0, faction + "_hq").is_empty() and sim.money[0] == money_before and sim.building_orders[0].is_empty(), faction + " cannot order another headquarters")
		var engineer: int = sim.debug_spawn(0, faction + "_engineer", sim.entities[2].pos + Vector2(-3.0, 0.0))
		_check(sim._engineering_distance(sim.entities[engineer], sim.entities[2]) <= float(config.units[faction + "_engineer"].repair_radius), "headquarters capture fixture starts within engineering reach of the snapped building edge")
		_check(not sim.capture_error(engineer, 2).is_empty(), faction + " cannot capture a second headquarters while its own survives")
		sim.issue([engineer], "capture", sim.entities[2].pos, 2)
		_check(sim.entities[engineer].commands.is_empty() and sim.entities[2].team == 1, "rejected headquarters capture does not enter the command queue")
		sim.debug_spawn(0, faction + "_power", Vector2(5.5, 43.5))
		sim._kill_entity(1, true)
		_check(not sim.build(0, faction + "_hq").is_empty() and sim.money[0] == money_before, "headquarters cannot be rebuilt after losing the original")
		_check(sim.capture_error(engineer, 2).is_empty(), "losing the original headquarters frees the single headquarters ownership slot")
		sim.issue([engineer], "capture", sim.entities[2].pos, 2)
		_tick(sim, 0.1)
		_check(sim.entities[2].team == 0 and sim.entities.has(engineer), "an engineer immediately captures an eligible headquarters from its edge and survives")


func _test_capture_and_exclusions() -> void:
	var sim = _sim()
	var target: int = sim.debug_spawn(1, "kestrel_power", Vector2(20.5, 43.5))
	var engineer: int = sim.debug_spawn(0, "rivet_engineer", Vector2(10.5, 43.5))
	var money_before: Array = sim.money.duplicate()
	var target_hp: float = sim.entities[target].hp - 47.0
	sim.entities[target].hp = target_hp
	_check(sim.capture_error(engineer, target).is_empty(), "ordinary enemy buildings are eligible for engineer capture")
	sim.issue([engineer], "capture", sim.entities[target].pos, target)
	sim.step(1.0 / 30.0)
	_check(sim.entities[target].team == 1 and not sim.entities[engineer].commands.is_empty() and sim.entities[engineer].commands[0].kind == "capture", "a distant capture order walks to the building before changing its owner")
	_tick(sim, 6.0)
	_check(sim.entities[target].team == 0 and sim.entities[target].spec == "kestrel_power" and _near(sim.entities[target].hp, target_hp), "capture transfers ownership without replacing the building model or repairing it")
	_check(sim.entities.has(engineer) and sim.money == money_before, "capture neither consumes the engineer nor charges either team")
	sim = _sim()
	var tower: int = sim.debug_spawn(1, "kestrel_tower", Vector2(20.0, 43.0))
	engineer = sim.debug_spawn(0, "rivet_engineer", Vector2(18.0, 43.0))
	_check(sim.capture_error(engineer, tower).is_empty(), "defense towers are eligible for capture")
	sim.issue([engineer], "capture", sim.entities[tower].pos, tower)
	sim.step(1.0 / 30.0)
	_check(sim.entities[tower].team == 0 and sim.entities.has(engineer), "an adjacent engineer takes a defense tower immediately")
	for role: String in ["wall", "barricade"]:
		sim = _sim()
		target = sim.debug_spawn(1, "kestrel_" + role, Vector2(20.5, 43.5))
		engineer = sim.debug_spawn(0, "rivet_engineer", Vector2(18.5, 43.5))
		_check(not sim.capture_error(engineer, target).is_empty(), "engineers cannot capture " + role)
		sim.issue([engineer], "capture", sim.entities[target].pos, target)
		_tick(sim, 0.1)
		_check(sim.entities[target].team == 1 and sim.entities[engineer].commands.is_empty(), "excluded " + role + " remains hostile without a queued capture")
	sim = _sim()
	target = sim.debug_spawn(1, "kestrel_power", Vector2(20.5, 43.5))
	var rifle: int = sim.debug_spawn(0, "rivet_rifle", Vector2(17.5, 43.5))
	engineer = sim.debug_spawn(0, "rivet_engineer", Vector2(16.5, 43.5))
	_check(not sim.capture_error(rifle, target).is_empty() and not sim.capture_error(engineer, 1).is_empty() and not sim.capture_error(engineer, rifle).is_empty(), "capture excludes non-engineers, friendly buildings and units")
	sim.issue([rifle], "capture", sim.entities[target].pos, target)
	_check(sim.entities[rifle].commands.is_empty(), "ordinary infantry cannot acquire engineer capture commands")


func _test_capture_production_refunds() -> void:
	var sim = _sim()
	sim.debug_spawn(1, "kestrel_power", Vector2(35.5, 40.5))
	var barracks: int = sim.debug_spawn(1, "kestrel_barracks", Vector2(20.5, 43.5))
	_check(sim.produce(barracks, "kestrel_rifle").is_empty() and sim.produce(barracks, "kestrel_rifle").is_empty(), "capture refund fixture starts active and waiting enemy production")
	_tick(sim, 1.0)
	var expected_refund: float = 0.0
	for order: Dictionary in sim.entities[barracks].queue:
		expected_refund += float(order.cost) * float(order.remaining) / float(order.total)
	var money_before: Array = sim.money.duplicate()
	var engineer: int = sim.debug_spawn(0, "rivet_engineer", Vector2(17.5, 43.5))
	sim.issue([engineer], "capture", sim.entities[barracks].pos, barracks)
	sim.step(1.0 / 30.0)
	_check(sim.entities[barracks].team == 0 and sim.entities[barracks].queue.is_empty(), "captured production building cancels the old owner's entire queue")
	# Production advances before the engineer acts during the capture tick.
	var tick_refund: float = expected_refund - float(config.units.kestrel_rifle.cost) / float(config.units.kestrel_rifle.build_time) / 30.0
	_check(_near(sim.money[1] - float(money_before[1]), tick_refund) and _near(sim.money[0], float(money_before[0])), "cancelled capture queues refund their remaining value only to the previous owner")
	_check(sim.produce(barracks, "rivet_rifle").is_empty(), "captured barracks uses its producer role to train the new owner's infantry")


func _test_capture_airfield() -> void:
	var sim = _sim()
	sim.debug_spawn(1, "kestrel_power", Vector2(35.5, 40.5))
	sim.debug_spawn(1, "kestrel_command", Vector2(30.5, 43.5))
	var field: int = sim.debug_spawn(1, "kestrel_airfield", Vector2(20.5, 43.5))
	var plane: int = sim.debug_spawn(1, "kestrel_fighter", Vector2(25.5, 43.5))
	_check(sim.entities[plane].home_airfield == field, "capture airfield fixture assigns a real home airport")
	sim.entities[plane].ammo = 0
	var engineer: int = sim.debug_spawn(0, "rivet_engineer", Vector2(16.5, 43.5))
	sim.issue([engineer], "capture", sim.entities[field].pos, field)
	_tick(sim, 0.1)
	_check(sim.entities[field].team == 0 and sim.entities[plane].team == 1 and sim.entities[plane].home_airfield == -1, "capturing an airport removes it as a home for the old owner's aircraft")
	_check(sim.entities[plane].flight_state == "stranded" and sim.entities[plane].airborne and _near(sim.entities[plane].rearm_remaining, 0.0), "an empty aircraft cannot land or rearm at the captured enemy airport")


func _test_instant_building_repair() -> void:
	var sim = _sim()
	var target: int = sim.debug_spawn(0, "rivet_power", Vector2(20.5, 43.5))
	var engineer: int = sim.debug_spawn(0, "rivet_engineer", Vector2(17.5, 43.5))
	var second: int = sim.debug_spawn(0, "rivet_engineer", Vector2(20.5, 40.5))
	var maximum: float = config.buildings.rivet_power.hp
	var missing: float = 137.0
	var cost: float = missing * float(config.economy.repair_cost)
	sim.entities[target].hp = maximum - missing
	var money_before: float = sim.money[0]
	sim.issue([engineer, second], "repair", sim.entities[target].pos, target)
	sim.step(1.0 / 30.0)
	_check(_near(sim.entities[target].hp, maximum) and _near(money_before - sim.money[0], cost), "engineers restore all missing building health in one tick and charge its exact cost once")
	_check(sim.entities.has(engineer) and sim.entities.has(second), "instant building repair preserves both engineers")
	_tick(sim, 0.1)
	_check(_near(money_before - sim.money[0], cost), "a completed building repair cannot charge again")
	sim.entities[target].hp = maximum - missing
	sim.money[0] = cost - 1.0
	sim.issue([engineer], "repair", sim.entities[target].pos, target)
	_tick(sim, 1.0)
	_check(_near(sim.entities[target].hp, maximum - missing) and _near(sim.money[0], cost - 1.0) and not sim.entities[engineer].commands.is_empty(), "insufficient funds preserve the whole repair order without partial health or spending")
	sim.money[0] = cost
	sim.step(1.0 / 30.0)
	_check(_near(sim.entities[target].hp, maximum) and _near(sim.money[0], 0.0), "a waiting engineer completes the full repair as soon as the exact funds arrive")


func _test_outpost_deployment() -> void:
	var sim = _sim()
	sim.debug_spawn(0, "rivet_power", Vector2(5.5, 40.5))
	var engineer: int = sim.debug_spawn(0, "rivet_engineer", Vector2(9.5, 43.5))
	var rifle: int = sim.debug_spawn(0, "rivet_rifle", Vector2(9.5, 45.5))
	var hostile: int = sim.debug_spawn(1, "kestrel_engineer", Vector2(35.5, 43.5))
	var money_before: float = sim.money[0]
	_check(not sim.build(0, "rivet_outpost").is_empty() and not sim.build(0, "rivet_outpost", rifle).is_empty() and not sim.build(0, "rivet_outpost", hostile).is_empty(), "outposts require a live friendly engineer as their builder")
	_check(sim.money[0] == money_before and sim.building_orders[0].is_empty(), "invalid outpost builders do not charge money or create orders")
	_check(sim.build(0, "rivet_outpost", engineer).is_empty(), "a friendly engineer can prepare an outpost order")
	_check(sim.money[0] == money_before and sim.building_orders[0].ready, "selecting an engineer outpost starts free, immediately ready site selection")
	var order: Dictionary = sim.building_orders[0].duplicate(true)
	var count_before: int = sim.entities.size()
	var pos := Vector2(24.5, 43.5)
	_check(not sim.placement_error(0, Vector2(-2.5, 43.5)).is_empty() and not sim.placement_error(0, sim.entities[1].pos).is_empty() and not sim.placement_error(0, Vector2(23.5, 35.5)).is_empty(), "outpost placement still rejects map boundaries, occupied buildings and water")
	_check(sim.building_orders[0] == order and sim.entities.size() == count_before, "invalid outpost placement leaves the prepared order intact")
	_check((sim.entities[1].pos as Vector2).distance_to(pos) > float(config.economy.build_radius) and sim.placement_error(0, pos).is_empty(), "engineer outposts may be placed beyond existing base expansion coverage")
	_check(sim.place_building(0, pos).is_empty() and sim.entities.size() == count_before and not sim.entities[engineer].commands.is_empty() and sim.entities[engineer].commands[0].kind == "deploy_outpost", "placing an outpost assigns travel to its engineer without remotely spawning a building")
	var outpost: int = _wait_for_outpost(sim, pos)
	_check(outpost >= 0, "the assigned engineer reaches the remote site and deploys its outpost")
	if outpost < 0:
		return
	_check(_near(sim.entities[outpost].construct_remaining, float(config.buildings.rivet_outpost.build_time)) and sim.entities[outpost].has("construction") and sim.entities.has(engineer), "on-site deployment starts the full engineer construction period and preserves the engineer")
	_tick(sim, float(config.buildings.rivet_outpost.build_time) + 0.1)
	_check(_near(sim.entities[outpost].construct_remaining, 0.0) and not sim.entities[outpost].has("construction") and sim.entities[engineer].commands.is_empty(), "the engineer finishes the outpost through on-site work and becomes available again")
	_check(_near(money_before - sim.money[0], float(config.buildings.rivet_outpost.cost)), "complete field construction spends exactly the configured outpost cost")


func _test_outpost_without_headquarters() -> void:
	var sim = _sim()
	sim.debug_spawn(0, "rivet_power", Vector2(5.5, 40.5))
	var engineer: int = sim.debug_spawn(0, "rivet_engineer", Vector2(9.5, 43.5))
	sim._kill_entity(1, true)
	sim._check_result()
	_check(sim.result.is_empty() and not sim.build(0, "rivet_power").is_empty(), "a surviving power station keeps the match active but cannot authorize normal construction")
	_check(sim.build(0, "rivet_outpost", engineer).is_empty(), "a friendly engineer can prepare a new outpost after headquarters loss")
	var pos := Vector2(24.5, 43.5)
	_check(sim.place_building(0, pos).is_empty(), "engineer outpost placement works without a headquarters or an existing outpost")
	var outpost: int = _wait_for_outpost(sim, pos)
	if outpost >= 0:
		_tick(sim, float(config.buildings.rivet_outpost.build_time) + 0.1)
	_check(outpost >= 0 and sim.build(0, "rivet_power").is_empty(), "a completed engineer outpost restores normal building authorization")


func _test_builder_loss_selection() -> void:
	var sim = _sim()
	sim.debug_spawn(0, "rivet_power", Vector2(5.5, 40.5))
	var engineer: int = sim.debug_spawn(0, "rivet_engineer", Vector2(9.5, 43.5))
	var money_before: float = sim.money[0]
	_check(sim.build(0, "rivet_outpost", engineer).is_empty(), "builder-loss fixture starts free outpost site selection")
	sim._kill_entity(engineer, true)
	sim.step(1.0 / 30.0)
	_check(sim.building_orders[0].is_empty() and _near(sim.money[0], money_before), "losing an engineer before placement cancels free site selection without charging or refunding money")


func _test_command_snapshots() -> void:
	var path: String = "/tmp/paper_front_engineer_rules.save"
	for command: String in ["capture", "repair", "deploy_outpost"]:
		var sim = _sim()
		var engineer: int = sim.debug_spawn(0, "rivet_engineer", Vector2(9.5, 43.5))
		if command == "deploy_outpost":
			sim.debug_spawn(0, "rivet_power", Vector2(5.5, 40.5))
			_check(sim.build(0, "rivet_outpost", engineer).is_empty(), "snapshot deployment fixture starts a legal order")
			_check(sim.place_building(0, Vector2(24.5, 43.5)).is_empty(), "snapshot deployment fixture assigns its remote site")
		else:
			var team: int = 1 if command == "capture" else 0
			var target: int = sim.debug_spawn(team, ("kestrel" if team == 1 else "rivet") + "_power", Vector2(20.5, 43.5))
			if command == "repair":
				sim.entities[target].hp -= 120.0
			sim.issue([engineer], command, sim.entities[target].pos, target)
		_check(sim.save_game(path).is_empty(), command + " command snapshot writes")
		var restored = Sim.new()
		var error: String = restored.load_game(path)
		_check(error.is_empty() and restored.entities == sim.entities and restored.building_orders == sim.building_orders, command + " command and its engineering state survive save/load: " + error)
		if not error.is_empty():
			continue
		_tick(sim, 12.0)
		_tick(restored, 12.0)
		_check(restored.entities == sim.entities and restored.money == sim.money and restored.building_orders == sim.building_orders, command + " advances identically after restoring the snapshot")
	DirAccess.remove_absolute(path)
