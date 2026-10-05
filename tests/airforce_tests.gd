extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
const Validator = preload("res://scripts/sim_save_validator.gd")
var config: Dictionary
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	config = Rules.load_rules("res://data/rules.json", false)
	if config.is_empty():
		push_error("Airforce rules invalid: " + str(Rules.errors))
		quit(1)
		return
	_test_domains_and_flight()
	_test_airport_capacity_and_service()
	_test_airport_loss()
	_test_support_and_expansion()
	_test_support_economy()
	_test_damage_multipliers()
	_test_snapshot_and_validation()
	_test_ai_mix()
	_test_late_ai_attack()
	print("Airforce checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _sim():
	var sim = Sim.new()
	sim.setup(config, "dev", 7, "rivet", false)
	sim.money.assign([100000.0, 100000.0])
	return sim

func _tick(sim, seconds: float) -> void:
	var elapsed: float = 0.0
	while elapsed < seconds - 0.000001:
		var dt: float = minf(1.0 / 30.0, seconds - elapsed)
		sim.step(dt)
		elapsed += dt

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.001

func _airport(sim, team: int, pos: Vector2) -> int:
	var faction: String = sim.factions[team]
	sim.debug_spawn(team, faction + "_power", pos + Vector2(-6.0, -2.0))
	sim.debug_spawn(team, faction + "_command", pos + Vector2(5.0, -2.0))
	return sim.debug_spawn(team, faction + "_airfield", pos)

func _test_domains_and_flight() -> void:
	var sim = _sim()
	var tank: int = sim.debug_spawn(0, "rivet_tank", Vector2(9.5, 39.5))
	var fighter: int = sim.debug_spawn(1, "kestrel_fighter", sim.entities[tank].pos)
	_check((sim.entities[fighter].pos as Vector2).is_equal_approx(sim.entities[tank].pos), "aircraft may overlap ground units without displacing them")
	var plane_hp: float = sim.entities[fighter].hp
	sim._fire(sim.entities[tank], fighter)
	sim._apply_damage()
	_check(sim.projectiles.is_empty() and sim.entities[fighter].hp == plane_hp, "ground weapon cannot shoot aircraft")
	var tank_hp: float = sim.entities[tank].hp
	sim._fire(sim.entities[fighter], tank)
	sim._apply_damage()
	_check(sim.projectiles.is_empty() and sim.entities[tank].hp == tank_hp and sim.entities[fighter].ammo == config.units.kestrel_fighter.ammo_capacity, "fighter cannot shoot ground or spend ammunition on it")
	var aa: int = sim.debug_spawn(0, "rivet_aa", Vector2(10.5, 39.5))
	sim.entities[aa].turret_alpha = rad_to_deg((sim.entities[fighter].pos - sim.entities[aa].pos).angle())
	sim._fire(sim.entities[aa], fighter)
	_check(sim.projectiles.size() == 1 and sim.projectiles[0].targets == ["air"], "AA creates an air-only guided shot")
	if not sim.projectiles.is_empty():
		sim.entities[fighter].pos += Vector2(0.0, 0.3)
		sim._step_projectiles(3.0)
		sim._apply_damage()
	_check(sim.entities[fighter].hp < plane_hp and sim.entities[tank].hp == tank_hp, "guided AA hits a moving aircraft without damaging nearby ground unit")
	var flyer: int = sim.debug_spawn(0, "rivet_bomber", Vector2(4.5, 28.5))
	var barrier: int = sim.debug_spawn(0, "rivet_factory", Vector2(15.0, 28.0))
	sim.issue([flyer, tank], "move", Vector2(32.5, 28.5))
	_check(not sim.entities[flyer].commands[0].has("formation") and sim.entities[tank].commands[0].kind=="move", "mixed orders retain separate air and ground movement after group rollback")
	_tick(sim, 7.0)
	_check((sim.entities[flyer].pos as Vector2).distance_to(Vector2(32.5, 28.5)) < 0.2 and sim.entities.has(barrier), "aircraft flies directly across buildings, water and elevation")
	_check(sim.entities[flyer].path.is_empty() and not sim._planning_queue.has(flyer), "air movement does not consume ground path planner slots")
	var bridge_sim = _sim()
	var bridge: Dictionary = bridge_sim.bridges[0]
	var over_bridge: int = bridge_sim.debug_spawn(0, "rivet_fighter", bridge_sim._bridge_center(bridge))
	bridge_sim._add_damage(Sim.BRIDGE_TARGET_BASE - int(bridge.id), 100000.0)
	bridge_sim._apply_damage()
	_check(bridge_sim.entities.has(over_bridge), "bridge collapse does not destroy aircraft overhead")

func _test_airport_capacity_and_service() -> void:
	var sim = _sim()
	var airport: int = _airport(sim, 0, Vector2(12.0, 37.0))
	for index in range(4):
		_check(sim.produce(airport, "rivet_fighter") == "", "airport reserves legal aircraft order %d" % index)
	var money_before: float = sim.money[0]
	_check(sim.produce(airport, "rivet_fighter") != "" and sim.money[0] == money_before, "fifth reservation fails without charging money")
	sim.cancel_production(airport, 3)
	_check(sim.produce(airport, "rivet_fighter") == "", "cancelling queued aircraft releases a reserved slot")
	_tick(sim, float(config.units.rivet_fighter.build_time) + 0.2)
	var aircraft: int = -1
	for e in sim.entities.values():
		if sim._is_air(e) and e.team == 0: aircraft = e.id
	_check(aircraft > 0 and sim.entities[aircraft].home_airfield == airport and sim._airfield_load(airport) == 4, "production assigns home airport while preserving capacity across queue deployment")
	if aircraft < 0: return
	sim.issue([aircraft], "move", Vector2(25.5, 36.5))
	sim.entities[aircraft].ammo = 0
	_tick(sim, 2.0)
	_check(sim.entities[aircraft].flight_state == "rearming" and not sim.entities[aircraft].commands.is_empty() and not sim.entities[aircraft].airborne, "empty aircraft returns and lands while preserving its mission")
	var progress_before: float = sim.entities[aircraft].rearm_remaining
	var power_id: int = -1
	for e in sim.entities.values():
		if e.team == 0 and sim.data_for(e.spec).get("role") == "power": power_id = e.id
	sim._kill_entity(power_id, true)
	sim.step(1.0)
	_check(_near(progress_before - float(sim.entities[aircraft].rearm_remaining), float(config.economy.low_power_multiplier)), "low power slows rearming by configured multiplier")
	_tick(sim, float(config.units.rivet_fighter.rearm_time) * 2.0 + 3.0)
	_check(sim.entities[aircraft].ammo == config.units.rivet_fighter.ammo_capacity and sim.entities[aircraft].flight_state == "airborne" and (sim.entities[aircraft].pos as Vector2).distance_to(Vector2(25.5, 36.5)) < 0.2, "service reloads and resumes the preserved mission")
	var fighter: int = aircraft
	var enemy: int = sim.debug_spawn(1, "kestrel_fighter", sim.entities[fighter].pos + Vector2(2, 0))
	sim.entities[fighter].ammo = 1
	sim.entities[fighter].cooldown = 0.0
	sim.entities[fighter].alpha = 0.0
	sim._fire(sim.entities[fighter], enemy)
	_check(sim.entities[fighter].ammo == 0 and sim.entities[fighter].flight_state == "returning", "last weapon discharge triggers automatic return")
	var returns: int = 0
	for event in sim.events:
		if event.kind == "return" and event.id == fighter: returns += 1
	_check(returns == 2, "automatic return emits exactly one voice event per service trip")

func _test_airport_loss() -> void:
	var sim = _sim()
	var field: int = _airport(sim, 0, Vector2(12.0, 37.0))
	var plane: int = sim.debug_spawn(0, "rivet_fighter", Vector2(19.0, 37.0))
	sim.entities[plane].ammo = 0
	sim._kill_entity(field, true)
	sim.step(0.1)
	_check(sim.entities.has(plane) and sim.entities[plane].flight_state == "stranded" and sim.entities[plane].home_airfield == -1, "airport destruction leaves empty aircraft airborne and awaiting a replacement")
	var replacement: int = _airport(sim, 0, Vector2(25.0, 37.0))
	_tick(sim, 0.1)
	_check(sim.entities[plane].home_airfield == replacement and sim.entities[plane].flight_state == "returning", "stranded aircraft reserves a replacement airport and returns")
	_tick(sim, 12.0)
	_check(sim.entities[plane].ammo == config.units.rivet_fighter.ammo_capacity, "replacement airport restores combat readiness")

func _test_support_and_expansion() -> void:
	var sim = _sim()
	var station: int = sim.debug_spawn(0, "rivet_repair", Vector2(12.5, 37.5))
	sim.debug_spawn(0, "rivet_power", Vector2(6.5, 37.5))
	var tank: int = sim.debug_spawn(0, "rivet_tank", Vector2(16.5, 37.5))
	sim.entities[tank].hp -= 100.0
	var hp: float = sim.entities[tank].hp
	sim.step(1.0)
	_check(_near(sim.entities[tank].hp - hp, config.buildings.rivet_repair.repair_rate), "repair station heals a damaged ground vehicle in its radius")
	var engineer: int = sim.debug_spawn(0, "rivet_engineer", Vector2(20.5, 42.5))
	var rifle: int = sim.debug_spawn(0, "rivet_rifle", Vector2(21.5, 42.5))
	sim.entities[rifle].hp -= 40.0
	hp = sim.entities[rifle].hp
	sim.issue([engineer], "repair", sim.entities[rifle].pos, rifle)
	sim.step(1.0)
	_check(_near(sim.entities[rifle].hp - hp, config.units.rivet_engineer.repair_rate), "engineer repair command restores friendly unit health")
	sim.entities[station].hp -= 60.0
	sim.entities[engineer].pos = Vector2(15.0, 37.5)
	hp = sim.entities[station].hp
	sim.issue([engineer], "repair", sim.entities[station].pos, station)
	sim.step(1.0)
	_check(_near(sim.entities[station].hp, config.buildings.rivet_repair.hp) and _near(sim.entities[station].hp - hp, 60.0), "engineer immediately restores a friendly building from outside its footprint")
	var outpost: int = sim.debug_spawn(0, "rivet_outpost", Vector2(24.5, 37.5))
	sim._kill_entity(1, true)
	sim._check_result()
	_check(sim.result == "" and sim.build(0, "rivet_power") == "", "outpost sustains construction and the match after headquarters loss")
	_tick(sim, float(config.buildings.rivet_power.build_time) + 0.2)
	_check(sim.entities.has(outpost) and sim.building_orders[0].ready, "outpost continues construction progress without headquarters")
	var command: int = sim.debug_spawn(0, "rivet_command", Vector2(28.5, 41.5))
	var base_range: float = sim._acquisition_range(sim.entities[tank], 5.0)
	_check(base_range == 5.0 + float(config.buildings.rivet_command.vision_bonus) and sim.entities.has(command), "powered command centre extends friendly acquisition range")

func _test_support_economy() -> void:
	var sim = _sim()
	var station: int = sim.debug_spawn(0, "rivet_repair", Vector2(12.5, 37.5))
	var tank: int = sim.debug_spawn(0, "rivet_tank", Vector2(16.5, 37.5))
	var infantry: int = sim.debug_spawn(0, "rivet_rifle", Vector2(16.5, 39.5))
	sim.entities[tank].hp -= 100.0
	sim.entities[infantry].hp -= 30.0
	var infantry_hp: float = sim.entities[infantry].hp
	var hp: float = sim.entities[tank].hp
	var money_before: float = sim.money[0]
	sim.step(1.0)
	var rate: float = config.buildings.rivet_repair.repair_rate
	var cost: float = config.economy.repair_cost
	_check(_near(sim.entities[tank].hp - hp, rate) and _near(money_before - sim.money[0], rate * cost), "station charges only for actual vehicle health restored")
	_check(sim.entities[infantry].hp == infantry_hp, "repair station does not heal infantry")
	sim.money[0] = cost * 2.0
	hp = sim.entities[tank].hp
	sim.step(1.0)
	_check(_near(sim.entities[tank].hp - hp, 2.0) and _near(sim.money[0], 0.0), "station heals only what remaining funds can afford")
	hp = sim.entities[tank].hp
	sim.step(1.0)
	_check(sim.entities[tank].hp == hp, "station pauses at zero funds")
	sim.money[0] = 100.0
	sim.debug_spawn(0, "rivet_factory", Vector2(22.0, 37.0))
	sim.debug_spawn(0, "rivet_command", Vector2(28.5, 37.5))
	sim.step(1.0)
	_check(sim._low_power[0] and sim.entities[tank].hp == hp and sim.money[0] == 100.0, "station shuts down without charging when the base lacks power")
	var engineer: int = sim.debug_spawn(0, "rivet_engineer", Vector2(15.5, 37.5))
	sim.entities[station].hp -= 60.0
	hp = sim.entities[station].hp
	money_before = sim.money[0]
	sim.issue([engineer], "repair", sim.entities[station].pos, station)
	sim.step(1.0)
	_check(_near(sim.entities[station].hp - hp, 60.0) and _near(money_before - sim.money[0], 60.0 * cost), "engineer building repair charges once for its entire actual recovery")
	sim.money[0] = cost
	sim.entities[station].hp -= 60.0
	hp = sim.entities[station].hp
	sim.issue([engineer], "repair", sim.entities[station].pos, station)
	sim.step(1.0)
	_check(_near(sim.entities[station].hp, hp) and _near(sim.money[0], cost), "engineer waits without partial building repair when the full repair is unaffordable")

func _test_damage_multipliers() -> void:
	var sim = _sim()
	var target: int = sim.debug_spawn(1, "kestrel_tank", Vector2(17.5, 39.5))
	var infantry: int = sim.debug_spawn(1, "kestrel_rifle", Vector2(18.5, 39.5))
	var building: int = sim.debug_spawn(1, "kestrel_power", Vector2(24.5, 37.5))
	var weapon: Dictionary = config.weapons.rivet_advanced
	_check(_near(sim._scaled_damage(100.0, target, weapon.multipliers), 100.0 * weapon.multipliers.armored), "armor modifier applies to tanks")
	_check(_near(sim._scaled_damage(100.0, infantry, weapon.multipliers), 100.0 * weapon.multipliers.infantry), "infantry modifier applies to infantry")
	_check(_near(sim._scaled_damage(100.0, building, weapon.multipliers), 100.0 * weapon.multipliers.building), "siege modifier applies to buildings")
	var gun: int = sim.debug_spawn(0, "rivet_advanced", Vector2(10.5, 39.5))
	sim.entities[gun].turret_alpha = 0.0
	var hp: float = sim.entities[target].hp
	sim._fire(sim.entities[gun], target)
	sim._step_projectiles(2.0)
	sim._apply_damage()
	_check(_near(hp - float(sim.entities[target].hp), float(weapon.damage) * float(weapon.multipliers.armored)), "actual projectile impact retains configured damage multiplier")

func _read_save(path: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	var snapshot: Dictionary = file.get_var(false)
	file.close()
	return snapshot

func _test_snapshot_and_validation() -> void:
	var sim = _sim()
	var field: int = _airport(sim, 0, Vector2(12.0, 37.0))
	var plane: int = sim.debug_spawn(0, "rivet_fighter", Vector2(15.0, 37.0))
	var enemy: int = sim.debug_spawn(1, "kestrel_fighter", Vector2(18.0, 37.0))
	sim.entities[plane].alpha = 0.0
	sim._fire(sim.entities[plane], enemy)
	sim.issue([plane], "move", Vector2(27.0, 37.0))
	sim.entities[plane].ammo = 0
	_tick(sim, 0.3)
	var path: String = "/tmp/paper_front_airforce.save"
	_check(sim.save_game(path) == "", "air state snapshot writes")
	var restored = Sim.new()
	_check(restored.load_game(path) == "" and restored.entities == sim.entities and restored.projectiles == sim.projectiles, "aircraft state, airport reservations and air projectile survive save/load")
	_tick(sim, 1.0)
	_tick(restored, 1.0)
	_check(restored.entities == sim.entities and restored.projectiles == sim.projectiles, "restored air operations advance deterministically")
	var snapshot: Dictionary = _read_save(path)
	var invalid: Dictionary = snapshot.duplicate(true)
	invalid.entities[plane].ammo = config.units.rivet_fighter.ammo_capacity + 1
	_check(Validator.check(invalid) != "", "validator rejects impossible aircraft ammunition")
	invalid = snapshot.duplicate(true)
	invalid.entities[plane].home_airfield = 2
	_check(Validator.check(invalid) != "", "validator rejects hostile or non-airfield home")
	invalid = snapshot.duplicate(true)
	invalid.entities[field].queue = []
	for index in range(5):
		invalid.entities[field].queue.append({"spec": "rivet_fighter", "remaining": 1.0, "total": 1.0, "cost": 1.0, "ready": false, "started": false, "progress": 0.0})
	_check(Validator.check(invalid) != "", "validator rejects airport overcapacity")
	invalid = snapshot.duplicate(true)
	invalid.projectiles.append({"targets": ["water"]})
	_check(Validator.check(invalid) != "", "validator rejects invalid projectile target domain")
	var bad_rules: Dictionary = config.duplicate(true)
	bad_rules.units.rivet_fighter.ammo_capacity = 1.5
	_check(not Rules.validate(bad_rules, false).is_empty(), "rule validation rejects fractional ammunition capacity")
	bad_rules = config.duplicate(true)
	bad_rules.weapons.rivet_fighter.targets = ["air", "air"]
	_check(not Rules.validate(bad_rules, false).is_empty(), "rule validation rejects duplicated target domains")
	# Ground v1 snapshots do not contain any aircraft fields; they remain valid.
	var legacy = _sim()
	legacy.debug_spawn(0, "rivet_rifle", Vector2(9.5, 39.5))
	legacy.save_game(path)
	var legacy_snapshot: Dictionary = _read_save(path)
	for unit in legacy_snapshot.rules.units.values():
		# Naval definitions were introduced later and require their explicit domain.
		# Keep them intact while exercising omitted legacy ground/air fields.
		if unit.get("domain", "ground") == "naval": continue
		unit.erase("domain")
		if unit.get("producer") == "airfield": unit.domain = "air"
	for weapon in legacy_snapshot.rules.weapons.values(): weapon.erase("targets")
	_check(Validator.check(legacy_snapshot) == "", "old ground snapshots keep default ground domains")
	DirAccess.remove_absolute(path)

func _test_ai_mix() -> void:
	var sim = _sim()
	var field: int = _airport(sim, 1, Vector2(34.0, 35.0))
	sim.debug_spawn(1, "kestrel_refinery", Vector2(40.0, 40.0))
	sim.debug_spawn(1, "kestrel_barracks", Vector2(31.5, 42.5))
	var factory: int = sim.debug_spawn(1, "kestrel_factory", Vector2(31.0, 29.0))
	sim.debug_spawn(1, "kestrel_tech", Vector2(39.5, 29.5))
	sim.debug_spawn(1, "kestrel_tower", Vector2(43.5, 32.5))
	sim.debug_spawn(1, "kestrel_repair", Vector2(43.5, 36.5))
	sim.debug_spawn(1, "kestrel_harvester", Vector2(39.5, 42.5))
	sim.debug_spawn(1, "kestrel_harvester", Vector2(38.5, 43.5))
	sim.time = 6.0
	sim._step_ai()
	_check(not sim.entities[field].queue.is_empty() and config.units[sim.entities[field].queue[0].spec].domain == "air", "AI invests in aircraft production")
	_check(not sim.entities[factory].queue.is_empty() and sim.entities[factory].queue[0].spec == "kestrel_artillery", "AI adds long-range artillery once technology exists")

func _test_late_ai_attack() -> void:
	var sim = _sim()
	var tank: int = sim.debug_spawn(1, "kestrel_tank", Vector2(33.5, 39.5))
	var aa: int = sim.debug_spawn(1, "kestrel_aa", Vector2(31.5, 39.5))
	sim.time = 421.0
	sim._ai_attack_clock = 29.0
	sim._step_ai()
	_check(not sim.entities[tank].commands.is_empty() and sim.entities[tank].commands[0].kind == "attack_move", "late AI sends a small surviving ground force without waiting for five units")
	_check(not sim.entities[aa].commands.is_empty() and sim.entities[aa].commands[0].kind == "attack_move", "AA escorts the late offensive with an air-compatible attack-move order")
	var invulnerable_threat = _sim()
	var attacker: int = invulnerable_threat.debug_spawn(1, "kestrel_tank", Vector2(35.5, 41.5))
	invulnerable_threat.debug_spawn(0, "rivet_fighter", Vector2(37.5, 41.5))
	invulnerable_threat.time = 421.0
	invulnerable_threat._ai_attack_clock = 29.0
	invulnerable_threat._step_ai()
	_check(not invulnerable_threat.entities[attacker].commands.is_empty() and invulnerable_threat.entities[attacker].commands[0].kind == "attack_move", "an untargetable enemy aircraft does not indefinitely cancel a ground offensive")
	var anti_air_only = _sim()
	var plane: int = anti_air_only.debug_spawn(1, "kestrel_fighter", Vector2(33.5, 39.5))
	anti_air_only.time = 421.0
	anti_air_only._ai_attack_clock = 29.0
	anti_air_only._step_ai()
	_check(anti_air_only.entities[plane].commands.is_empty(), "fighter-only AI does not mistake air superiority for a base assault force")
