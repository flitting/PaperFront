extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const FACTIONS: Array[String] = ["kestrel", "rivet", "iron", "sky"]
var rules: Dictionary
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	rules = RulesLoader.load_rules("res://data/rules.json", false)
	if rules.is_empty():
		push_error("Balance rules invalid: " + str(RulesLoader.errors))
		quit(1)
		return
	_check_stats()
	_check_tank_vs_machine_gun()
	_equal_budget_skirmish()
	print("BALANCE checks=%d failures=%s" % [checks, str(failures)])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _check_stats() -> void:
	_check(not rules.factions.iron.traits.has("damage_reduction"), "Iron has no faction-wide damage reduction")
	for faction in FACTIONS:
		var traits: Dictionary = rules.factions[faction].get("traits", {})
		_check(not traits.has("cohesion_damage_bonus") and not traits.has("breakthrough_damage_bonus"), faction + " has no faction-wide offensive bonus")
	_check(is_equal_approx(float(rules.factions.iron.traits.regen_delay), 6.0) and is_equal_approx(float(rules.factions.iron.traits.regen_fraction_per_second), 0.012), "iron regeneration cadence")
	for role in ["rifle", "anti", "engineer", "harvester", "scout", "tank", "aa", "fighter", "advanced"]:
		var canonical: Dictionary = rules.units["kestrel_" + role]
		var hammer: Dictionary = rules.units["rivet_" + role]
		var iron: Dictionary = rules.units["iron_" + role]
		_check(float(canonical.hp) <= float(iron.hp) and float(iron.hp) < float(hammer.hp), "%s Iron roster HP between canonical and hammer" % role)
		_check(float(canonical.cost) <= float(iron.cost) and float(iron.cost) <= float(hammer.cost), "%s iron cost between canonical and hammer" % role)
	for role in ["rifle", "anti", "engineer", "harvester", "scout", "tank", "aa", "fighter"]:
		_check(float(rules.units["sky_" + role].hp) < float(rules.units["kestrel_" + role].hp), "%s sky has low HP" % role)
	for faction in FACTIONS:
		_check(int(rules.buildings[faction + "_refinery"].hp) == 1600, faction + " refinery HP")
		_check(int(rules.units[faction + "_fighter"].ammo_capacity) == 8, faction + " fighter ammo")
		_check(is_equal_approx(float(rules.weapons[faction + "_tank"].multipliers.infantry), 0.30), faction + " tank infantry multiplier")
	_check(is_equal_approx(float(rules.weapons.iron_assault.multipliers.infantry), 1.5), "dedicated anti infantry cannon retained")
	_check(is_equal_approx(float(rules.weapons.sky_disruptor.emp_vehicle_duration), 2.0) and is_equal_approx(float(rules.weapons.sky_disruptor.emp_building_duration), 1.0), "sky EMP data contract")

func _check_tank_vs_machine_gun() -> void:
	for faction in FACTIONS:
		var tank_weapon: Dictionary = rules.weapons[faction + "_tank"]
		var scout_weapon: Dictionary = rules.weapons[faction + "_scout"]
		var tank_dps: float = float(tank_weapon.damage) * float(tank_weapon.multipliers.infantry) / float(tank_weapon.interval)
		var gun_dps: float = float(scout_weapon.damage) * float(scout_weapon.multipliers.infantry) / float(scout_weapon.interval)
		_check(tank_dps < gun_dps * 0.5, "%s cannon infantry DPS below half machine gun DPS" % faction)
		var sim = Sim.new()
		sim.setup_multiteam(rules, "dev", 7, [faction, "kestrel"], false)
		var tank: int = sim.debug_spawn(0, faction + "_tank", Vector2(14.5, 38.5))
		var infantry: int = sim.debug_spawn(1, "kestrel_rifle", Vector2(18.5, 38.5))
		var initial: float = float(sim.entities[infantry].hp)
		sim.entities[tank].turret_alpha = 0.0
		sim._fire(sim.entities[tank], infantry)
		sim._step_projectiles(1.0)
		sim._apply_damage()
		_check(sim.entities.has(infantry) and is_equal_approx(initial - float(sim.entities[infantry].hp), float(tank_weapon.damage) * 0.30), "%s actual cannon infantry hit" % faction)

func _equal_budget_skirmish() -> void:
	# A reproducible sample, not an assertion that one roster always wins.
	# Three standard tanks cost 2280; two heavy tanks cost 2200.
	var sim = Sim.new()
	sim.setup_multiteam(rules, "dev", 7, ["kestrel", "rivet"], false)
	var standard: Array[int] = []
	var heavy: Array[int] = []
	for y in [35.5, 38.5, 41.5]: standard.append(sim.debug_spawn(0, "kestrel_tank", Vector2(14.5, y)))
	for y in [37.0, 40.0]: heavy.append(sim.debug_spawn(1, "rivet_tank", Vector2(32.5, y)))
	_check(3 * int(rules.units.kestrel_tank.cost) <= 2300 and 2 * int(rules.units.rivet_tank.cost) <= 2300, "equal budget 2300 tank rosters")
	for id in standard: sim.issue([id], "attack_move", Vector2(32.5, 38.5))
	for id in heavy: sim.issue([id], "attack_move", Vector2(14.5, 38.5))
	for frame in range(40 * 30): sim.step(1.0 / 30.0)
	var standard_hp := 0.0
	var heavy_hp := 0.0
	for id in standard:
		if sim.entities.has(id): standard_hp += float(sim.entities[id].hp)
	for id in heavy:
		if sim.entities.has(id): heavy_hp += float(sim.entities[id].hp)
	print("EQUAL_BUDGET_TANK_SAMPLE standard=3/2280 remaining_hp=%.1f heavy=2/2200 remaining_hp=%.1f" % [standard_hp, heavy_hp])
	_check(standard_hp < 3.0 * float(rules.units.kestrel_tank.hp) and heavy_hp < 2.0 * float(rules.units.rivet_tank.hp), "equal budget skirmish engaged both sides")
