extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
var checks: int = 0
var failures: Array[String] = []
var rules: Dictionary

func _initialize() -> void:
	rules = Rules.load_rules()
	for faction: String in ["kestrel","rivet","iron","sky"]:
		_test_priority(faction,false)
		if faction != "rivet":
			_test_priority(faction,true)
			_test_miner_recovery(faction)
	_test_train_and_rail_budget()
	print("AI first tank budget checks: %d passed, %d failed" % [checks-failures.size(),failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func check(ok: bool,message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func fixture(faction: String) -> Dictionary:
	var sim = Sim.new()
	sim.setup_multiteam(rules,"dev",7,[faction,"kestrel" if faction != "kestrel" else "rivet"],false,[Vector2(9,30),Vector2(42,6)])
	for z: int in range(sim.map.size):
		for x: int in range(sim.map.size):
			sim.map.terrain[z][x] = 0
			sim.map.heights[z][x] = 0.0
	sim.mines.clear()
	sim.bridges.clear()
	sim.ruins.clear()
	sim._refresh_mine_spatial()
	sim._refresh_ruin_spatial()
	sim._prepare_terrain_cache()
	sim._spawn(0,faction+"_power",Vector2(6,18),true)
	if rules.buildings.has(faction+"_refinery"):
		var refinery: int = sim._spawn(0,faction+"_refinery",Vector2(32.5,39.5),true)
		sim.entities[refinery].gift_pending = false
	if rules.buildings.has(faction+"_barracks"): sim._spawn(0,faction+"_barracks",Vector2(31,28),true)
	var factory: int = sim._spawn(0,faction+"_factory",Vector2(15,37),true)
	sim._nav_dirty = true
	sim._rebuild_nav()
	return {"sim":sim,"factory":factory}

func plan(sim,faction: String) -> void:
	sim.AIController._produce(sim,0,faction,sim.AIController.SETTINGS.normal)

func _test_priority(faction: String,queued_miner: bool) -> void:
	var ctx: Dictionary = fixture(faction)
	var sim = ctx.sim
	if faction != "rivet":
		if queued_miner:
			sim.money[0] = float(rules.units[faction+"_harvester"].cost)
			check(sim.produce(ctx.factory,faction+"_harvester").is_empty(),faction+" existing queued first miner pays real price")
		else: sim._spawn(0,faction+"_harvester",Vector2(23,43),true)
	var price: float = float(rules.units[faction+"_tank"].cost)
	var funds: float = maxf(price,950.0)
	sim.money[0] = funds
	var rail_before: int = sim._role_count(0,"rail")
	sim.AIController._build(sim,0,faction)
	check(sim.order_for_team(0,"normal").is_empty() and sim.order_for_team(0,"defense").is_empty(),faction+" optional facilities and towers preserve first tank funds")
	check(is_equal_approx(sim.money[0],funds),faction+" deferred construction charges nothing")
	# Exact affordability exposes a guard/engineer buying before the factory.
	sim.money[0] = price
	plan(sim,faction)
	check(sim._unit_spec_count(0,faction+"_tank") == 1,faction+" first tank queues before extra miners or infantry")
	check(is_zero_approx(sim.money[0]),faction+" first tank pays its full normal price once")
	check(sim._role_count(0,"rail") == rail_before,faction+" first tank budget is not spent connecting a second miner")
	if faction != "rivet": check(sim._unit_spec_count(0,faction+"_harvester") == 1,faction+" keeps exactly the existing or queued first miner")
	if not queued_miner:
		for tick: int in range(500):
			sim.step(.05)
			if sim.entities.values().any(func(e):return str(e.spec)==faction+"_tank" and not bool(e.get("emerging",false))): break
		check(sim.entities.values().any(func(e):return str(e.spec)==faction+"_tank" and not bool(e.get("emerging",false))),faction+" paid tank physically completes and exits the actual factory")
		check(is_zero_approx(float(sim.statistics.teams[0].funds_earned)),faction+" test completion uses no income or grants")

func _test_miner_recovery(faction: String) -> void:
	var ctx: Dictionary = fixture(faction)
	var sim = ctx.sim
	var price: float = float(rules.units[faction+"_harvester"].cost)
	sim.money[0] = price
	plan(sim,faction)
	check(sim._unit_spec_count(0,faction+"_harvester") == 1,faction+" losing the last miner prioritizes a real replacement")
	check(sim._unit_spec_count(0,faction+"_tank") == 0,faction+" miner recovery is not replaced with a tank when rail connection waits")
	check(is_zero_approx(sim.money[0]),faction+" replacement miner consumes its exact normal price")
	check(sim.entities[ctx.factory].queue[0].spec == faction+"_harvester",faction+" recovery is a genuine production order")
	for tick: int in range(5): plan(sim,faction)
	check(sim._unit_spec_count(0,faction+"_harvester") == 1 and is_zero_approx(sim.money[0]),faction+" repeated recovery planning adds no free miners or negative balance")

func _test_train_and_rail_budget() -> void:
	var ctx: Dictionary = fixture("iron")
	var sim = ctx.sim
	sim._spawn(0,"iron_harvester",Vector2(23,43),true)
	sim._spawn(0,"iron_tech",Vector2(40.5,19.5),true)
	sim.time = 24.0 # The normal heavy-train cycle must still choose the first tank.
	sim.money[0] = float(rules.units.iron_tank.cost)
	plan(sim,"iron")
	check(sim.entities[ctx.factory].queue[0].spec == "iron_tank", "technology/train cycle cannot replace the first tank")
	check(sim._role_count(0,"rail") == 0 and is_zero_approx(sim.money[0]),"train railway does not consume the first tank budget")
	var recovery: Dictionary = fixture("iron")
	recovery.sim._spawn(0,"iron_tank",Vector2(23,43),true)
	recovery.sim._spawn(0,"iron_tech",Vector2(40.5,19.5),true)
	recovery.sim.time = 24.0
	recovery.sim.money[0] = float(rules.units.iron_harvester.cost)
	plan(recovery.sim,"iron")
	check(not recovery.sim.entities[recovery.factory].queue.is_empty() and recovery.sim.entities[recovery.factory].queue[0].spec == "iron_harvester" and is_zero_approx(recovery.sim.money[0]),"train cycle also preserves paid last-miner recovery after a tank already exists")
	var poor: Dictionary = fixture("iron")
	poor.sim.mines.append({"pos":Vector2(25.5,41.5),"amount":3000.0,"capacity":3000.0,"miner":-1})
	poor.sim._refresh_mine_spatial()
	poor.sim._spawn(0,"iron_rail",Vector2(23.5,41.5),true)
	poor.sim._rail_network.rebuild(poor.sim)
	var old_rails: int = poor.sim._role_count(0,"rail")
	poor.sim.money[0] = float(rules.units.iron_harvester.cost)-1.0
	plan(poor.sim,"iron")
	check(poor.sim.entities[poor.factory].queue.is_empty() and poor.sim._role_count(0,"rail") == old_rails,"unaffordable recovery miner never initiates paid rail construction")
	check(is_equal_approx(poor.sim.money[0],float(rules.units.iron_harvester.cost)-1.0),"unaffordable recovery keeps every remaining credit")
	var before: float = poor.sim.money[0]
	check(poor.sim._rail_network.ai_connect_factory(poor.sim,poor.sim.entities[poor.factory]),"rail budget fixture has a real purchasable factory-to-mine connection")
	var new_rails: int = poor.sim._role_count(0,"rail")-old_rails
	check(new_rails > 0 and is_equal_approx(before-float(poor.sim.money[0]),new_rails*float(rules.buildings.iron_rail.cost)),"fixture railway really charges every new segment at its normal price")
