extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
const Validator = preload("res://scripts/sim_save_validator.gd")
const Transport = preload("res://scripts/unit_transport.gd")
var config: Dictionary
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	config = Rules.load_rules("res://data/rules.json", false)
	if config.is_empty():
		push_error("Transport rules invalid: " + str(Rules.errors))
		quit(1)
		return
	_test_board_and_unload()
	_test_capacity_and_eligibility()
	_test_blocked_unload_and_death()
	_test_snapshot_validation()
	print("Scout transport checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
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

func _pair(sim, team: int = 0) -> Vector2i:
	var faction: String = sim.factions[team]
	var carrier: int = sim.debug_spawn(team, faction + "_scout", Vector2(13.5, 39.5))
	var passenger: int = sim.debug_spawn(team, faction + "_rifle", Vector2(11.5, 39.5))
	sim.issue([passenger], "board", sim.entities[carrier].pos, carrier)
	_tick(sim, 2.0)
	return Vector2i(carrier, passenger)

func _test_board_and_unload() -> void:
	var sim = _sim()
	var carrier: int = sim.debug_spawn(0, "rivet_scout", Vector2(22.5, 42.5))
	var passenger: int = sim.debug_spawn(0, "rivet_rifle", Vector2(9.5, 42.5))
	var units_before: int = sim.counts(0).x
	var origin: Vector2 = sim.entities[passenger].pos
	sim.issue([passenger], "board", sim.entities[carrier].pos, carrier)
	_tick(sim, 0.1)
	_check(not Transport.is_loaded(sim.entities[passenger]) and (sim.entities[passenger].pos as Vector2).distance_to(origin) < 1.0, "boarding starts with ordinary movement instead of teleporting infantry")
	_tick(sim, 8.0)
	_check(Transport.is_loaded(sim.entities[passenger]) and sim.entities[carrier].passengers == [passenger], "infantry boards the scout after reaching its side")
	_check(sim.counts(0).x == units_before and sim.entities[passenger].commands.is_empty() and not sim._planning_queue.has(passenger), "embarked infantry retain army count while releasing navigation work")
	var cooldown_before: float = sim.entities[passenger].cooldown
	sim.issue([passenger], "attack_move", Vector2(30.5, 42.5))
	sim.issue([carrier], "move", Vector2(30.5, 42.5))
	_tick(sim, 3.0)
	_check((sim.entities[carrier].pos as Vector2).distance_to(Vector2(30.5, 42.5)) < 0.3 and sim.entities[passenger].pos == sim.entities[carrier].pos, "passenger travels with its moving scout")
	_check(sim.entities[passenger].commands.is_empty() and sim.entities[passenger].cooldown == cooldown_before, "embarked infantry ignore orders and their combat simulation is paused")
	var enemy: int = sim.debug_spawn(1, "kestrel_rifle", Vector2(32.5, 42.5))
	_check(not sim._target_alive(passenger) and not sim._weapon_can_target(sim.entities[enemy], passenger), "embarked infantry cannot be independently targeted")
	var hp_before: float = sim.entities[passenger].hp
	sim._add_damage(passenger, 10.0)
	sim._apply_damage()
	_check(sim.entities[passenger].hp == hp_before, "embarked infantry do not receive independent battlefield damage")
	_check(sim.unload(carrier) == "" and not Transport.is_loaded(sim.entities[passenger]) and sim.entities[carrier].passengers.is_empty(), "unload restores infantry and releases the single seat")
	_check(sim._standing(sim.entities[passenger].pos, sim._radius(sim.entities[passenger]), passenger) and (sim.entities[passenger].pos as Vector2).distance_to(sim.entities[carrier].pos) < 2.1, "unloaded infantry appear on legal nearby terrain without overlapping their scout")
	_check(sim._target_alive(passenger) and sim._weapon_can_target(sim.entities[enemy], passenger), "unloaded infantry return to combat targeting")

func _test_capacity_and_eligibility() -> void:
	for team in range(2):
		var sim = _sim()
		var pair: Vector2i = _pair(sim, team)
		var faction: String = sim.factions[team]
		_check(Transport.is_loaded(sim.entities[pair.y]) and int(config.units[faction + "_scout"].transport_capacity) == 1, "both factions have a scout with exactly one infantry seat")
		var second: int = sim.debug_spawn(team, faction + "_rifle", Vector2(11.5, 42.5))
		var engineer: int = sim.debug_spawn(team, faction + "_engineer", Vector2(13.5, 42.5))
		var rocket: int = sim.debug_spawn(team, faction + "_anti", Vector2(16.5, 42.5))
		_check(not Transport.board_error(sim, second, pair.x).is_empty(), "full scout refuses a second infantry passenger")
		_check(not Transport.board_error(sim, engineer, pair.x).is_empty() and not Transport.board_error(sim, rocket, pair.x).is_empty(), "full scout also refuses engineers and specialist infantry")
		sim.issue([second, engineer, rocket], "board", sim.entities[pair.x].pos, pair.x)
		_check(sim.entities[second].commands.is_empty() and sim.entities[engineer].commands.is_empty() and sim.entities[rocket].commands.is_empty(), "invalid boarding orders leave units available on foot")
		var hostile: int = sim.debug_spawn(1 - team, sim.factions[1 - team] + "_rifle", Vector2(18.5, 42.5))
		_check(not Transport.board_error(sim, hostile, pair.x).is_empty(), "enemy infantry cannot board the scout")
		sim._kill_entity(pair.y, true)
		_check(sim.entities[pair.x].passengers.is_empty() and Transport.board_error(sim, second, pair.x).is_empty(), "removing an embarked passenger cleans the carrier seat")
		_check(Transport.board_error(sim, engineer, pair.x).is_empty() and Transport.board_error(sim, rocket, pair.x).is_empty(), "empty scout accepts engineers and specialist ground infantry")

func _test_blocked_unload_and_death() -> void:
	var sim = _sim()
	var pair: Vector2i = _pair(sim)
	var pos: Vector2 = sim.entities[pair.x].pos
	var saved_terrain: Array = sim.map.terrain.duplicate(true)
	for z in range(floori(pos.y) - 4, floori(pos.y) + 5):
		for x in range(floori(pos.x) - 4, floori(pos.x) + 5): sim.map.terrain[z][x] = 1
	sim.map.terrain[floori(pos.y)][floori(pos.x)] = 0
	sim._prepare_terrain_cache()
	_check(sim.unload(pair.x) != "" and Transport.is_loaded(sim.entities[pair.y]), "blocked unload keeps the passenger aboard instead of dropping into water")
	sim.map.terrain = saved_terrain
	sim._prepare_terrain_cache()
	_check(sim.unload(pair.x) == "", "passenger can unload once local terrain is available")
	sim.issue([pair.y], "board", sim.entities[pair.x].pos, pair.x)
	_tick(sim, 2.0)
	sim._kill_entity(pair.x, true)
	_check(not sim.entities.has(pair.x) and not sim.entities.has(pair.y), "destroying a loaded scout also destroys its passenger")
	_check(not sim._planning_queue.has(pair.x) and not sim._planning_queue.has(pair.y), "transport destruction leaves no pending navigation entities")

func _read_save(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var snapshot: Dictionary = file.get_var(false)
	file.close()
	return snapshot

func _test_snapshot_validation() -> void:
	var sim = _sim()
	var pair: Vector2i = _pair(sim)
	sim.issue([pair.x], "move", Vector2(19.5, 39.5))
	_tick(sim, 0.5)
	var path: String = "/tmp/paper_front_scout_transport.save"
	_check(sim.save_game(path) == "", "loaded scout snapshot writes")
	var restored = Sim.new()
	_check(restored.load_game(path) == "" and restored.entities == sim.entities, "passenger-carrier relation survives save/load")
	_tick(sim, 1.0)
	_tick(restored, 1.0)
	_check(restored.entities == sim.entities, "restored transport movement remains deterministic")
	var snapshot: Dictionary = _read_save(path)
	var invalid: Dictionary = snapshot.duplicate(true)
	invalid.entities[pair.x].passengers = []
	_check(Validator.check(invalid) != "", "validator rejects missing reverse carrier association")
	invalid = snapshot.duplicate(true)
	invalid.entities[pair.y].transport_id = 99999
	_check(Validator.check(invalid) != "", "validator rejects a missing carrier")
	invalid = snapshot.duplicate(true)
	invalid.entities[pair.x].passengers.append(pair.y)
	_check(Validator.check(invalid) != "", "validator rejects duplicate seats and overcapacity")
	invalid = snapshot.duplicate(true)
	invalid.entities[pair.y].pos += Vector2.ONE
	_check(Validator.check(invalid) != "", "validator rejects detached embarked positions")
	invalid = snapshot.duplicate(true)
	invalid.entities[pair.y].commands.append({"kind": "move", "pos": Vector2(15.5, 39.5), "target": -1})
	_check(Validator.check(invalid) != "", "validator rejects active commands on an embarked passenger")
	invalid = snapshot.duplicate(true)
	invalid.entities[pair.y].transport_id = 1.5
	_check(Validator.check(invalid) != "", "validator rejects malformed transport identifiers")
	var bad_rules: Dictionary = config.duplicate(true)
	bad_rules.units.rivet_scout.transport_capacity = 1.5
	_check(not Rules.validate(bad_rules, false).is_empty(), "rules reject fractional transport capacity")
	bad_rules = config.duplicate(true)
	bad_rules.units.rivet_rifle.transport_capacity = 1
	_check(not Rules.validate(bad_rules, false).is_empty(), "rules reject transport seats on ordinary infantry")
	var legacy = _sim()
	legacy.debug_spawn(0, "rivet_scout", Vector2(13.5, 39.5))
	legacy.save_game(path)
	var legacy_snapshot: Dictionary = _read_save(path)
	for e in legacy_snapshot.entities.values():
		e.erase("transport_id")
		e.erase("passengers")
	for info in legacy_snapshot.rules.units.values(): info.erase("transport_capacity")
	_check(Validator.check(legacy_snapshot) == "", "legacy saves without transport fields remain valid")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_var(legacy_snapshot, false)
	file.close()
	_check(restored.load_game(path) == "" and restored.entities.values().all(func(e): return e.kind != "unit" or (e.transport_id == -1 and e.passengers.is_empty())), "legacy loading initializes empty transport state")
	DirAccess.remove_absolute(path)
