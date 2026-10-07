extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const MAP = preload("res://scripts/campaign_map.gd")
const Mission = preload("res://scripts/campaign_controller.gd")
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/rules.json"))
	var sim = Sim.new()
	sim.setup(config, "campaign", 1, "kestrel", true)
	check(sim.campaign_controller != null and sim.factions == ["kestrel", "rivet"], "canonical sides and controller")
	check(sim.map.valid and sim.map.size == 320, "dedicated mission map")
	check(not bool(sim.bridges[0].alive), "bridge begins broken")
	check(sim.availability(0, "kestrel_power").is_empty(), "first phase power is available")
	check(sim.availability(0, "kestrel_refinery").contains("战役第2阶段"), "future technology has stage explanation")
	check(sim.availability(0, "kestrel_shipyard").contains("本关不开放"), "high technology remains visible and restricted")
	check(sim.availability(1, "rivet_power").is_empty() or not sim.availability(1, "rivet_power").contains("战役"), "enemy economy is not campaign gated")
	check(sim.entities.values().any(func(e): return e.spec == "kestrel_harvester"), "one-time starting harvester")
	check(sim.build(0, "kestrel_power").is_empty(), "player can buy first mission building")
	sim.building_orders[0].ready = true
	var power_site: Vector2 = Vector2.INF
	for radius: int in range(5, 24):
		if power_site.is_finite(): break
		for z: int in range(170 - radius, 171 + radius):
			for x: int in range(62 - radius, 63 + radius):
				if sim.placement_error(0, Vector2(x, z)).is_empty(): power_site = Vector2(x, z); break
			if power_site.is_finite(): break
	check(power_site.is_finite(), "power site is playable beside HQ")
	print("CAMPAIGN_POWER_SITE ", power_site)
	sim.building_orders[0] = {}
	var controller = sim.campaign_controller
	# Fixture buildings are real completed simulation entities. The controller
	# still requires delivery/production/boarding events and map positions.
	sim._spawn(0, "kestrel_power", Vector2(90, 171), true)
	controller.step(sim, 0.1)
	check(controller.stage == 1, "completed power advances mission")
	sim._spawn(0, "kestrel_refinery", Vector2(97, 158), true)
	check(sim.build(0, "kestrel_refinery").is_empty(), "refinery unlocks after power")
	sim.building_orders[0].ready = true
	check(sim.placement_error(0, Vector2(102, 157)).is_empty(), "refinery has a clear working pad within completed building coverage")
	sim.building_orders[0] = {}
	controller.step(sim, 0.1)
	check(controller.stage == 1, "refinery alone does not fake a delivery")
	sim.events.append({"kind":"delivery", "team":0, "amount":300.0, "pos":Vector2(97,158)})
	controller.step(sim, 0.1)
	check(controller.stage == 2, "real delivery event advances economy phase")
	sim.events.clear()
	sim._spawn(0, "kestrel_barracks", Vector2(98, 175), true)
	var rifle: int = sim._spawn(0, "kestrel_rifle", MAP.WEST_BRIDGE + Vector2(-2, 0), true)
	sim.events.append({"kind":"produce", "team":0, "spec":"kestrel_rifle", "id":rifle})
	controller.step(sim, 0.1)
	check(controller.stage == 2, "predeployed engineer does not satisfy trained engineer")
	var engineer: int = sim._spawn(0, "kestrel_engineer", Vector2(146, 159), true)
	sim.events.append({"kind":"produce", "team":0, "spec":"kestrel_engineer", "id":engineer})
	controller.step(sim, 0.1)
	check(controller.stage == 3, "trained infantry/engineer and actual recon position advance")
	sim.events.clear()
	sim.bridges[0].alive = true
	sim.bridges[0].hp = float(config.economy.bridge_hp)
	sim.bridges[0].repair_progress = 1.0
	controller.step(sim, 0.1)
	check(controller.stage == 4, "repaired bridge state advances")
	check(sim.build(0, "kestrel_outpost", engineer).is_empty(), "engineer can order eastward outpost")
	check(sim.placement_error(0, Vector2(207, 119)).is_empty(), "eastern expansion pad is buildable")
	sim.building_orders[0] = {}
	sim._spawn(0, "kestrel_outpost", MAP.EXPANSION + Vector2(3, 3), true)
	controller.step(sim, 0.1)
	check(controller.stage == 5, "completed eastern outpost advances")
	sim._spawn(0, "kestrel_factory", Vector2(105, 186), true)
	var scout: int = sim._spawn(0, "kestrel_scout", MAP.EAST_ASSEMBLY + Vector2(0, 3), true)
	sim.events.append({"kind":"board", "team":0, "id":rifle, "carrier":scout, "pos":MAP.EAST_ASSEMBLY})
	controller.step(sim, 0.1)
	check(controller.stage == 5, "boarding alone does not satisfy eastern unload")
	sim.events.clear()
	sim.events.append({"kind":"unload", "team":0, "id":rifle, "carrier":scout, "pos":MAP.EAST_ASSEMBLY})
	controller.step(sim, 0.1)
	check(controller.stage == 6, "boarding followed by designated unload advances")
	controller.step(sim, 32.0)
	check(not controller.finished and controller.hold_elapsed < 60.0, "defense timer cannot be skipped")
	var invalid_timer: Dictionary = controller.to_dict()
	invalid_timer.hold_elapsed = NAN
	check(not Mission.validate_state(invalid_timer).is_empty(), "save validator rejects nonfinite hold timer")
	var invalid_stage: Dictionary = controller.to_dict()
	invalid_stage.stage = 7
	check(not Mission.validate_state(invalid_stage).is_empty(), "save validator rejects finished/stage mismatch")
	var invalid_board: Dictionary = controller.to_dict()
	invalid_board.board_ids = {"bad":3}
	check(not Mission.validate_state(invalid_board).is_empty(), "save validator rejects malformed transport evidence")
	var save_path: String = "user://campaign_flow_tests.pfront"
	sim.ai_state[1].campaign_waves = 1
	check(sim.save_game(save_path).is_empty(), "mid-mission save")
	var restored = Sim.new()
	var load_error: String = restored.load_game(save_path)
	check(load_error.is_empty(), "mid-mission load: " + load_error)
	if load_error.is_empty():
		check(restored.campaign_controller.stage == 6 and is_equal_approx(restored.campaign_controller.hold_elapsed, controller.hold_elapsed), "stage and timer restore")
		check(int(restored.ai_state[1].get("campaign_waves", -1)) == 1, "bounded enemy wave count restores")
		var enemy_hq: int = -1
		for e: Dictionary in restored.entities.values():
			if e.spec == "rivet_hq": enemy_hq = int(e.id)
		check(enemy_hq > 0, "enemy command facility still exists")
		if enemy_hq > 0:
			var extra_base: int = restored._spawn(1, "rivet_hq", MAP.ENEMY_START + Vector2(-8, 0), true)
			restored.entities.erase(enemy_hq)
			restored.events.append({"kind":"death", "team":1, "spec":"rivet_hq", "id":enemy_hq})
			restored.campaign_controller.step(restored, 28.0)
			check(not restored.campaign_controller.finished and not restored.campaign_controller.flags.enemy_hq_destroyed, "destroying the starting base does not complete the mission while another base barracks survives")
			restored.entities.erase(extra_base)
			restored.events.clear()
			restored.campaign_controller.step(restored, 0.0)
			check(restored.campaign_controller.finished, "defend then destroy all enemy base barracks completes mission even without the final death event")
	var rebuilt_enemy = Sim.new()
	rebuilt_enemy.setup(config, "campaign", 1, "kestrel", true)
	var rebuilt_controller = rebuilt_enemy.campaign_controller
	rebuilt_controller.stage = 6
	for e: Dictionary in rebuilt_enemy.entities.values():
		if e.spec == "rivet_hq": rebuilt_enemy.entities.erase(e.id)
	rebuilt_controller.step(rebuilt_enemy, 1.0)
	check(rebuilt_controller.flags.enemy_hq_destroyed and not rebuilt_controller.finished, "all bases can be destroyed before the defense timer finishes")
	rebuilt_enemy._spawn(1, "rivet_hq", MAP.ENEMY_START, true)
	rebuilt_controller.step(rebuilt_enemy, 60.0)
	check(not rebuilt_controller.flags.enemy_hq_destroyed and not rebuilt_controller.finished, "a rebuilt enemy base barracks restores the live mission objective")
	var ordinary = Sim.new()
	ordinary.setup(config, "dev", 1, "kestrel", false)
	check(ordinary.campaign_controller == null and not ordinary.availability(0, "kestrel_shipyard").contains("本关不开放"), "skirmish is free of mission gates")
	print("CAMPAIGN_FLOW ", JSON.stringify({"checks":checks,"failures":failures}))
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
