extends SceneTree

const Sim = preload("res://scripts/simulation.gd")
const Loader = preload("res://scripts/rules_loader.gd")
const Adapter = preload("res://scripts/ai_faction_adapter.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func fixture(factions: Array[String]):
	var sim = Sim.new()
	sim.synchronous_path_tests = true
	sim.setup_multiteam(Loader.load_rules("res://data/rules.json", false), "symmetric", 733, factions, false)
	return sim

func test_paid_pressure_defense(faction: String) -> void:
	var enemy_faction: String = "iron" if faction == "kestrel" else "kestrel"
	var sim = fixture([faction,enemy_faction])
	sim._spawn(0,faction + "_power",Vector2(16,80),true)
	if faction == "rivet":
		sim._spawn(0,"rivet_drill",Vector2(44,84),true)
	else:
		var refinery: int = sim._spawn(0,faction + "_refinery",Vector2(44,80),true)
		sim.entities[refinery].gift_pending = false
		sim._spawn(0,faction + "_harvester",Vector2(45,88),true)
		sim._spawn(0,faction + "_barracks",Vector2(20,112),true)
	var factory: int = sim._spawn(0,faction + "_factory",Vector2(32,120),true)
	sim._spawn(0,faction + "_engineer",Vector2(20,96),true)
	var price: float = sim.production_cost(faction + "_rifle")
	sim.money[0] = price
	sim.AIController._produce_land(sim,0,faction)
	check(sim._unit_spec_count(0,faction + "_rifle") == 0 and is_equal_approx(sim.money[0],price), faction + " peaceful first-tank saving retains its real budget")
	var threat: int = sim._spawn(1,enemy_faction + "_rifle",Vector2(60,96),true)
	sim.TeamVision.refresh(sim,true)
	check(sim.AIController._home_under_pressure(sim,0), faction + " discovers a close armed raid through ordinary sight")
	sim.AIController._produce_land(sim,0,faction)
	check(sim._unit_spec_count(0,faction + "_rifle") == 1 and is_zero_approx(sim.money[0]), faction + " pays the exact infantry price during a raid instead of saving indefinitely for its first tank")
	check(sim.entities[factory].queue.is_empty() and int(sim.ai_state[0].get("emergency_defenders",0)) == 1, faction + " urgency creates a genuine barracks order without a free vehicle")
	var defender_orders: Array = []
	for producer: Dictionary in sim.entities.values():
		if int(producer.team) == 0:
			for order: Dictionary in producer.queue:
				if order.spec == faction + "_rifle": defender_orders.append(order)
	check(defender_orders.size() == 1 and int(defender_orders[0].squad_size) == sim.squad_size(faction + "_rifle") and is_equal_approx(float(defender_orders[0].total),sim.production_time(faction + "_rifle")), faction + " emergency order buys and trains the full current squad")
	sim._spawn(0,faction + "_tank",Vector2(35,110),true)
	sim._spawn(0,faction + "_rifle",Vector2(26,112),true)
	sim._spawn(0,faction + "_rifle",Vector2(28,112),true)
	sim.time = 180.0
	check(sim.AIController._land_goal(sim,0,sim.AIController._profile(sim,0)).is_empty(), faction + " suspends optional economy and technology while the small army faces a visible raid")
	sim.entities[threat].pos = Vector2(160,80)
	sim.TeamVision.refresh(sim,true)
	check(not sim.AIController._home_under_pressure(sim,0) and sim.AIController._land_goal(sim,0,sim.AIController._profile(sim,0)) == ("drill" if faction == "rivet" else "refinery"), faction + " resumes normal expansion once the nearby visible threat leaves")
	sim = null

func test_emergency_fallback() -> void:
	var sim = fixture(["sky","kestrel"])
	var barracks: int = sim._spawn(0,"sky_barracks",Vector2(20,112),true)
	sim._spawn(0,"sky_rifle",Vector2(24,110),true)
	sim._spawn(0,"sky_rifle",Vector2(26,110),true)
	sim._spawn(1,"kestrel_rifle",Vector2(60,96),true)
	sim.TeamVision.refresh(sim,true)
	sim.ai_state[0].production_counts = {"barracks":1}
	var money: float = sim.production_cost("sky_storm")-5.0
	sim.money[0] = money
	sim.AIController._produce_land(sim,0,"sky")
	check(sim.entities[barracks].queue.size() == 1 and sim.entities[barracks].queue[0].spec == "sky_rifle", "urgent defense falls back from an unaffordable storm trooper to a real rifle purchase even when the engineer was lost")
	check(is_equal_approx(sim.money[0],money-sim.production_cost("sky_rifle")), "emergency fallback pays exactly the current whole rifle squad price")
	sim = null

func test_miner_recovery_commands() -> void:
	var sim = fixture(["kestrel","sky"])
	var refinery: int = sim._spawn(0,"kestrel_refinery",Vector2(20,80),true)
	sim.entities[refinery].gift_pending = false
	var miner: int = sim._spawn(0,"kestrel_harvester",Vector2(25,88),true)
	sim.entities[miner].cargo = 250.0
	sim._rebuild_spatial()
	var state: Dictionary = sim.ai_state[0]
	sim.AIController._manage_miners(sim,0,state)
	sim.time = 14.0
	var funds: float = sim.money[0]
	sim.AIController._manage_miners(sim,0,state)
	check(sim.entities[miner].commands.size() == 1 and sim.entities[miner].commands[0].kind == "return_miner", "a stalled loaded miner receives an ordinary refinery return command")
	check(is_equal_approx(float(sim.entities[miner].cargo),250.0) and is_equal_approx(sim.money[0],funds), "recovery issues orders without creating income or moving cargo")
	var recoveries: int = int(state.get("miner_recovery_orders",0))
	sim.AIController._manage_miners(sim,0,state)
	check(int(state.get("miner_recovery_orders",0)) == recoveries, "miner retry cooldown prevents repeated command resets in the same game time")
	var save_path: String = "user://ai_miner_watch_test.pfront"
	check(sim.save_game(save_path).is_empty(), "miner progress watches save with ordinary game state")
	var loaded = Sim.new()
	loaded.synchronous_path_tests = true
	check(loaded.load_game(save_path).is_empty(), "miner progress watches restore with ordinary game state")
	loaded.AIController._manage_miners(loaded,0,loaded.ai_state[0])
	check(int(loaded.ai_state[0].get("miner_recovery_orders",0)) == recoveries, "restoring a watch preserves retry cooldown and does not duplicate recovery")
	for tick: int in 800:
		loaded.step(.05)
		if float(loaded.statistics.teams[0].funds_earned) >= 250.0: break
	check(float(loaded.statistics.teams[0].funds_earned) >= 250.0 and float(loaded.entities[miner].cargo) < 250.0, "the return command physically docks and credits the existing cargo through normal simulation")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	sim = null; loaded = null
	var pinned = fixture(["kestrel","sky"])
	var empty: int = pinned._spawn(0,"kestrel_harvester",Vector2(40,90),true)
	pinned.entities[empty].harvest_mine = 0
	pinned.AIController._manage_miners(pinned,0,pinned.ai_state[0])
	pinned.time = 14.0
	pinned.AIController._manage_miners(pinned,0,pinned.ai_state[0])
	check(not pinned.entities[empty].commands.is_empty() and pinned.entities[empty].commands[0].kind == "harvest" and int(pinned.entities[empty].commands[0].target) != 0, "an empty stalled miner can select another public safe ore patch using normal harvest orders")
	pinned = null

func test_paid_broken_rail_repair() -> void:
	var sim = fixture(["iron","kestrel"])
	sim._spawn(0,"iron_rail",Vector2(40.5,90.5),true)
	sim._spawn(0,"iron_rail",Vector2(42.5,90.5),true)
	sim._rail_network.rebuild(sim)
	var miner: int = sim._spawn(0,"iron_harvester",Vector2(40.5,90.5),true)
	sim.money[0] = float(sim.data_for("iron_rail").cost)
	var state: Dictionary = sim.ai_state[0]
	check(sim.AIController._try_rail_repair(sim,sim.entities[miner],state), "a local broken rail can be repaired before an unaffordable first tank")
	check(is_zero_approx(sim.money[0]) and sim.order_for_team(0,"defense").spec == "iron_rail", "rail repair uses the ordinary paid rail building queue")
	for tick: int in 12: sim.step(.05)
	sim.AIController._place_land(sim,0,"defense")
	for tick: int in 80: sim.step(.05)
	check(not sim._rail_network.at(0,Vector2(41.5,90.5)).is_empty(), "the paid repair physically restores the missing track cell")
	check(not sim._rail_network.traversable_path(sim,sim.entities[miner],Vector2(40.5,90.5),Vector2(42.5,90.5)).is_empty(), "the repaired track restores the real rail-only miner route")
	sim = null

func test_refinery_rail_branch_recovery() -> void:
	for disconnected_branch: bool in [false,true]:
		var sim = fixture(["iron","kestrel"])
		var refinery: int = sim._spawn(0,"iron_refinery",Vector2(36.5,103.5) if disconnected_branch else Vector2(39.5,100.5),true)
		sim.entities[refinery].gift_pending = false
		var source: Array[Vector2] = [Vector2(40.5,104.5),Vector2(41.5,104.5),Vector2(42.5,104.5),Vector2(42.5,105.5),Vector2(42.5,106.5)]
		if disconnected_branch:
			source.append(Vector2(39.5,104.5))
			for point: Vector2 in [Vector2(36.5,107.5),Vector2(37.5,107.5),Vector2(38.5,107.5),Vector2(39.5,107.5),Vector2(40.5,107.5),Vector2(41.5,107.5),Vector2(41.5,108.5),Vector2(41.5,109.5),Vector2(42.5,109.5)]: source.append(point)
		for point: Vector2 in source: sim._spawn(0,"iron_rail",point,true)
		sim._rail_network.rebuild(sim)
		var miner: int = sim._spawn(0,"iron_harvester",Vector2(42.5,106.3),true)
		sim.entities[miner].cargo = 500.0
		var rail_cost: float = float(sim.data_for("iron_rail").cost)
		var refund: float = rail_cost * float(sim._eco("sell_ratio",.5))
		var budget: float = float(sim.data_for("iron_rail_junction").cost) + rail_cost - refund if disconnected_branch else rail_cost
		sim.money[0] = budget
		var state: Dictionary = sim.ai_state[0]
		check(sim.AIController._try_rail_repair(sim,sim.entities[miner],state), "disconnected old refinery branch schedules a paid junction upgrade" if disconnected_branch else "a missing refinery exit with only one neighboring rail schedules normal repair")
		if disconnected_branch:
			check(sim.order_for_team(0,"defense").spec == "iron_rail_junction" and is_equal_approx(sim.money[0],rail_cost), "junction upgrade receives only the normal rail sale refund and reserves the connector cost")
			check(is_equal_approx(float(sim.statistics.teams[0].sales_income),refund), "the old track sale records its real refund in economic telemetry")
		for tick: int in 12: sim.step(.05)
		sim.AIController._place_land(sim,0,"defense")
		for tick: int in 40: sim.step(.05)
		if disconnected_branch:
			state.miner_watch = {miner:{"pos":sim.entities[miner].pos,"cargo":float(sim.entities[miner].cargo),"phase":"","last_progress":float(sim.time),"last_seen":float(sim.time),"retry_at":float(sim.time)+120.0,"attempts":0}}
			sim.AIController._manage_miners(sim,0,state)
			check(not sim.order_for_team(0,"defense").is_empty() and sim.order_for_team(0,"defense").spec == "iron_rail" and is_zero_approx(sim.money[0]), "the branch connector consumes its full normal track price after the junction completes")
			check(sim.time < 12.0 and sim.time < float(state.miner_watch[miner].retry_at), "a validated paid branch phase advances immediately while the originating miner's fault-scan retry is still throttled")
			check(int(state.get("rail_phase_advances",0)) == 1 and int(state.miner_watch[miner].attempts) == 0, "phase progression remains separate from repeated new-fault scans")
			for tick: int in 12: sim.step(.05)
			sim.AIController._place_land(sim,0,"defense")
			for tick: int in 40: sim.step(.05)
		check(not sim._rail_network.traversable_path(sim,sim.entities[miner],sim.entities[miner].pos,sim._rail_network.exit_cell(sim,sim.entities[refinery])).is_empty() or not sim.entities[miner].get("refinery_docking",{}).is_empty(), "paid repair restores a physically traversable route to the surviving refinery")
		for tick: int in 800:
			sim.step(.05)
			if float(sim.statistics.teams[0].funds_earned) >= 500.0: break
		check(float(sim.statistics.teams[0].funds_earned) >= 500.0 and float(sim.entities[miner].cargo) < 500.0, "the isolated miner physically returns and credits its original cargo through normal docking")
		sim = null

func test_paid_armed_miner_retreat(faction: String) -> void:
	var sim = fixture([faction,"kestrel"])
	sim._spawn(0,faction+"_power",Vector2(20,80),true)
	sim._spawn(0,faction+"_barracks",Vector2(20,110),true)
	var refinery: int = sim._spawn(0,faction+"_refinery",Vector2(30.5,110.5),true)
	sim.entities[refinery].gift_pending = false
	var factory: int = sim._spawn(0,faction+"_factory",Vector2(39.5,100.5),true)
	var enemy_barracks: int = sim._spawn(1,"kestrel_barracks",Vector2(56,110),true)
	if faction == "iron":
		var route: Array[Vector2] = [Vector2(42.5,106.5),Vector2(42.5,105.5),Vector2(41.5,105.5),Vector2(40.5,105.5),Vector2(39.5,105.5),Vector2(38.5,105.5),Vector2(37.5,105.5),Vector2(36.5,105.5),Vector2(35.5,105.5)]
		for y: int in range(106,115): route.append(Vector2(35.5,float(y)+.5))
		for x: int in range(30,35): route.append(Vector2(float(x)+.5,114.5))
		for point: Vector2 in route: sim._spawn(0,"iron_rail",point,true)
		sim._rail_network.rebuild(sim)
	var own_start: float = sim.money[0]
	var enemy_start: float = sim.money[1]
	check(sim.produce(factory,faction+"_harvester").is_empty() and sim.produce(enemy_barracks,"kestrel_anti").is_empty(), faction+" armed raid fixture buys its normal miner and normal anti-armor infantry")
	check(is_equal_approx(sim.money[0],own_start-sim.production_cost(faction+"_harvester")) and is_equal_approx(sim.money[1],enemy_start-sim.production_cost("kestrel_anti")), faction+" raid actors pay their actual rules prices, including the complete anti-armor squad")
	var miner: int = -1
	var enemy: int = -1
	var raiders: Array[int] = []
	for tick: int in 1800:
		sim.step(.05)
		raiders.clear()
		for unit: Dictionary in sim.entities.values():
			if unit.kind != "unit": continue
			if unit.spec == faction+"_harvester" and int(unit.team) == 0: miner = int(unit.id)
			elif unit.spec == "kestrel_anti" and int(unit.team) == 1:
				enemy = int(unit.id)
				raiders.append(enemy)
		if miner >= 0 and raiders.size() == sim.squad_size("kestrel_anti") and not bool(sim.entities[miner].get("emerging",false)) and raiders.all(func(id): return not bool(sim.entities[id].get("emerging",false))) and float(sim.entities[miner].cargo) >= 25.0: break
	if miner < 0 or enemy < 0: check(false,faction+" raid actors physically complete production"); return
	check(raiders.size() == sim.squad_size("kestrel_anti") and raiders.all(func(id): return not bool(sim.entities[id].get("emerging",false))) and sim.entities[enemy_barracks].queue.is_empty(), faction+" raid purchases and physically deploys every member before issuing its squad move")
	# The old single-soldier fixture put an entire new squad inside range at
	# once. Approach the range edge so this remains a first-hit withdrawal
	# test rather than requiring a normal miner to survive four anti-tank hits.
	var raid_range: float = float(sim.rules.weapons.kestrel_anti.range)
	sim.issue([enemy],"move",sim.entities[miner].pos + Vector2(raid_range + .5,0))
	for tick: int in 400:
		sim.step(.05)
		if not sim.entities.has(miner) or float(sim.entities[miner].hp) < sim.max_hp(sim.entities[miner]): break
	if not sim.entities.has(miner): check(false,faction+" ordinary miner survives the first real weapon hit"); return
	check(float(sim.entities[miner].hp) < sim.max_hp(sim.entities[miner]), faction+" safety test receives a real armed hit with ordinary miner health")
	var before: Vector2 = sim.entities[miner].pos
	var cargo: float = float(sim.entities[miner].cargo)
	var funds: float = sim.money[0]
	sim.AIController._manage_miners(sim,0,sim.ai_state[0])
	check(int(sim.ai_state[0].get("miner_safety_retreats",0)) > 0 and not sim.entities[miner].commands.is_empty(), faction+" visible armed pressure triggers an immediate ordinary retreat")
	check(is_equal_approx(float(sim.entities[miner].cargo),cargo) and is_equal_approx(sim.money[0],funds), faction+" retreat creates no cargo, cash or economic subsidy")
	if faction == "iron":
		var order: Dictionary = sim.entities[miner].commands[0]
		var destination: Vector2 = sim._rail_network.exit_cell(sim,sim.entities[int(order.target)]) if order.kind == "return_miner" else order.pos
		check(not sim._rail_network.traversable_path(sim,sim.entities[miner],before,destination).is_empty(), "rail-only miner retreat uses a real connected owned railway route")
	var orders: int = int(sim.ai_state[0].miner_safety_retreats)
	sim.AIController._manage_miners(sim,0,sim.ai_state[0])
	check(int(sim.ai_state[0].miner_safety_retreats) == orders, faction+" repeated danger checks preserve the retreat command during its cooldown")
	for tick: int in 120:
		sim.step(.05)
		if not sim.entities.has(miner): break
		if tick % 40 == 0: sim.AIController._manage_miners(sim,0,sim.ai_state[0])
	check(sim.entities.has(miner) and (sim.entities[miner].pos as Vector2).distance_to(before) > 3.0, faction+" normally vulnerable miner physically escapes the attacked ore")
	if not sim.entities.has(miner): return
	sim.issue([enemy],"move",Vector2(90,110))
	for tick: int in 2000:
		sim.step(.05)
		if tick % 40 == 0: sim.AIController._manage_miners(sim,0,sim.ai_state[0])
		if float(sim.statistics.teams[0].funds_earned) > 0.0 and int(sim.ai_state[0].get("miner_safety_resumes",0)) + int(sim.ai_state[0].get("miner_safety_switches",0)) > 0: break
	check(float(sim.statistics.teams[0].funds_earned) > 0.0 and int(sim.ai_state[0].get("miner_safety_resumes",0)) + int(sim.ai_state[0].get("miner_safety_switches",0)) > 0, faction+" danger withdrawal is followed by real mining/return income after the raid leaves")
	sim = null

func test_hidden_threat_and_traffic_lease() -> void:
	var sim = fixture(["kestrel","iron"])
	var miner: int = sim._spawn(0,"kestrel_harvester",Vector2(55,110),true)
	sim._spawn(1,"iron_anti",Vector2(155,170),true)
	sim.TeamVision.refresh(sim,true)
	check(not sim.AIController._manage_miner_safety(sim,sim.entities[miner],sim.ai_state[0]) and sim.entities[miner].commands.is_empty(), "a hidden armed enemy cannot trigger a healthy miner retreat")
	sim.entities[miner].path_goal = Vector2(55,115)
	var tank: int = sim._spawn(0,"kestrel_tank",Vector2(56,112),true)
	sim.entities[tank].ai_attacking = true
	sim._rebuild_spatial()
	check(sim.AIController._unblock_unit(sim,sim.entities[miner],sim.ai_state[0]) > 0, "a blocked miner gives a nearby friendly combat vehicle an ordinary clearance move")
	var order: String = JSON.stringify(sim.entities[tank].commands)
	sim.ai_state[0].attack_clock = 100.0
	sim.AIController._skirmish_attack(sim,0,sim.AIController.SETTINGS.normal,sim.ai_state[0])
	check(sim.time < float(sim.entities[tank].get("ai_traffic_until",0.0)) and JSON.stringify(sim.entities[tank].commands) == order, "the attack planner preserves the traffic clearance lease instead of overwriting the move in the same reaction")
	sim = null

func run() -> void:
	test_paid_armed_miner_retreat("kestrel")
	test_paid_armed_miner_retreat("iron")
	test_hidden_threat_and_traffic_lease()
	test_emergency_fallback()
	test_miner_recovery_commands()
	test_paid_broken_rail_repair()
	test_refinery_rail_branch_recovery()
	for faction: String in ["kestrel","rivet","iron","sky"]:
		var balanced: Dictionary = Adapter.profile(faction, "balanced")
		var pressure: Dictionary = Adapter.profile(faction, "pressure")
		var armor: Dictionary = Adapter.profile(faction, "armor")
		check(int(pressure.infantry_limit) > int(balanced.infantry_limit) and int(armor.infantry_limit) < int(balanced.infantry_limit), faction + " styles change actual army preferences")
		check(float(pressure.attack_scale) < float(balanced.attack_scale) and float(armor.factory_share) > float(balanced.factory_share), faction + " styles change timing and purchase priorities")
		check(Adapter.vehicle(faction, armor, 0, {}) == faction + "_tank", faction + " armor profile begins with its own available tank")
		test_paid_pressure_defense(faction)
	var sim = fixture(["kestrel","sky"])
	var enemy_air: int = sim._spawn(1,"sky_fighter",Vector2(158,92),true)
	var fighter: int = sim._spawn(0,"kestrel_fighter",Vector2(48,92),true)
	sim.TeamVision.refresh(sim,true)
	check(int(sim.AIController._observed_enemies(sim,0).air) == 0, "hidden aircraft cannot affect the production observation")
	sim.AIController._land_air_and_support(sim,0)
	check(sim.entities[fighter].commands.is_empty(), "fighter receives no attack against an unseen aircraft")
	sim._spawn(0,"kestrel_scout",Vector2(147,91),true)
	sim.TeamVision.refresh(sim,true)
	check(int(sim.AIController._observed_enemies(sim,0).air) == 1, "scouting supplies ordinary visible air intelligence")
	sim.AIController._land_air_and_support(sim,0)
	check(not sim.entities[fighter].commands.is_empty() and int(sim.entities[fighter].commands[0].target) == enemy_air, "fighter can respond to the aircraft after normal sight discovers it")
	var troops: Array[int] = []
	for n: int in 7: troops.append(sim._spawn(0,"kestrel_rifle",Vector2(55 + n,100),true))
	var tank: int = sim._spawn(0,"kestrel_tank",Vector2(58,106),true)
	var engineer: int = sim._spawn(0,"kestrel_engineer",Vector2(55,110),true)
	var state: Dictionary = sim.ai_state[0]
	state.attack_clock = 100.0
	sim.AIController._skirmish_attack(sim,0,sim.AIController.SETTINGS.normal,state)
	check(not sim.entities[tank].commands.is_empty() and sim.entities[tank].commands[0].kind == "attack_move", "a combined wave includes the tank created after the first six infantry")
	check(sim.entities[engineer].commands.is_empty(), "construction engineers remain available for normal construction")
	check(int(state.attack_waves) == 1, "a real combined force increments the wave counter")
	sim.entities[tank].commands.clear()
	state.attack_clock = 0.0
	sim.AIController._skirmish_attack(sim,0,sim.AIController.SETTINGS.normal,state)
	check(not sim.entities[tank].commands.is_empty() and (sim.entities[tank].commands[0].pos as Vector2).distance_to(Vector2(160,96)) < 25.0, "an idle surviving assault tank continues clearing the enemy base")
	check(not sim.AIController._land_apron_clear(sim,0,"kestrel_power",Vector2(40.5,96.5)), "planner rejects the compact power site that trapped the first refinery miner")
	check(sim.AIController._land_apron_clear(sim,0,"kestrel_power",Vector2(32,80)), "planner accepts a normal site with real traffic clearance")
	sim = null
	var rivet = fixture(["rivet","kestrel"])
	var builder: int = rivet._spawn(0,"rivet_engineer",Vector2(32,86),true)
	var scaffold: int = rivet._spawn(0,"rivet_power",Vector2(32,80),true)
	rivet.Construction.initialize(rivet,rivet.entities[scaffold],builder)
	check(is_equal_approx(rivet.AIController._construction_liability(rivet,0),600.0), "unpaid field construction retains its full actual rules liability")
	rivet.money[0] = 600.0
	rivet.AIController._produce_land(rivet,0,"rivet")
	check(is_equal_approx(rivet.money[0],600.0) and rivet.entities[1].queue.is_empty(), "routine infantry cannot spend the power scaffold budget")
	rivet.AIController._resume_construction(rivet,0)
	check(not rivet.entities[builder].commands.is_empty() and rivet.entities[builder].commands[0].kind == "resume_outpost", "an available engineer resumes the ordinary paused scaffold command")
	rivet._spawn(1,"kestrel_rifle",Vector2(33,84),true)
	rivet.TeamVision.refresh(rivet,true)
	rivet.AIController._defend(rivet,0)
	check(rivet.entities[builder].commands[0].kind == "resume_outpost", "land defense preserves the armed engineer's paid construction order")
	rivet.money[0] = 600.0
	rivet.AIController._produce_land(rivet,0,"rivet")
	check(is_equal_approx(rivet.money[0],600.0) and rivet._unit_spec_count(0,"rivet_rifle") == 0, "emergency defenders still preserve the actual unpaid scaffold liability")
	rivet.money[0] = 600.0 + rivet.production_cost("rivet_rifle")
	rivet.AIController._produce_land(rivet,0,"rivet")
	check(is_equal_approx(rivet.money[0],600.0) and rivet._unit_spec_count(0,"rivet_rifle") == 1, "an urgent defender buys only with credits above the remaining scaffold liability")
	rivet = null
	var objectives = fixture(["kestrel","iron"])
	var rail: int = objectives._spawn(1,"iron_rail",Vector2(80.5,96.5),true)
	var junction: int = objectives._spawn(1,"iron_rail_junction",Vector2(82.5,96.5),true)
	var wall: int = objectives._spawn(1,"iron_wall",Vector2(85,96),true)
	var power: int = objectives._spawn(1,"iron_power",Vector2(145,96),true)
	objectives.vision_enabled = false
	objectives.TeamVision.refresh(objectives,true)
	check(objectives.AIController._objective(objectives,0) == objectives.entities[power].pos, "visible nearby rails and passive walls cannot replace a remaining victory building objective")
	objectives.vision_enabled = true
	objectives.TeamVision.refresh(objectives,true)
	objectives.team_vision.last_known[0] = {}
	for id: int in [rail,junction,wall,power]:
		var entity: Dictionary = objectives.entities[id]
		objectives.team_vision.last_known[0][id] = {"kind":"building","spec":entity.spec,"pos":entity.pos,"seen_at":0.0}
	check(objectives.AIController._objective(objectives,0) == objectives.entities[power].pos, "remembered rails and walls cannot replace the last observed remaining economic building")
	objectives.team_vision.last_known[0].erase(power)
	check(objectives.AIController._objective(objectives,0) == Vector2(160,96), "memory containing only passive infrastructure falls back to public enemy geography")
	objectives = null
	print("AI_LAND_PLANNER " + JSON.stringify({"checks":checks,"failures":failures}))
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
