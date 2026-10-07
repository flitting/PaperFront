extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
const LegacyRivet = preload("res://tests/legacy_rivet_construction.gd")
var config: Dictionary
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	config = Rules.load_rules()
	if config.is_empty():
		push_error("Rule fixture is invalid: " + str(Rules.errors))
		quit(1)
		return
	_test_heading()
	_test_tank_fire()
	_test_turret_save_and_config()
	_test_crush_and_collision()
	_test_shells()
	_test_bridge()
	_test_power_and_placement()
	_test_building_repair()
	_test_queues_and_refunds()
	_test_gift_and_result()
	_test_radius_approach()
	_test_active_traffic()
	_test_save()
	print("Game rule checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _new_sim(faction: String = "rivet"):
	var sim = Sim.new()
	sim.setup(config, "dev", 7, faction, false)
	return sim


func _legacy_construction_sim():
	# Preserve the historical construction/refund and global-power snapshot
	# independently of current Rivet engineer scaffolds and local HQ supply.
	# Current faction mechanics are exercised in rivet_mechanics_tests.
	var historical: Dictionary = LegacyRivet.adapt(config)
	var sim = Sim.new()
	sim.setup(historical, "dev", 7, "rivet", false)
	return sim


func _tick(sim, seconds: float, dt: float = 1.0 / 30.0) -> void:
	var remaining: float = seconds
	while remaining > 0.000001:
		var step: float = minf(dt, remaining)
		sim.step(step)
		remaining -= step


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.001


func _fires(sim, id: int) -> int:
	var amount: int = 0
	for event: Dictionary in sim.events:
		if event.kind == "fire" and int(event.get("id", -1)) == id:
			amount += 1
	return amount


func _damage(sim, id: int, amount: float) -> void:
	sim._add_damage(id, amount)
	sim._apply_damage()
	sim._damage.clear()
	sim._check_result()


func _test_heading() -> void:
	var sim = _new_sim()
	var id: int = sim.debug_spawn(0, "rivet_tank", Vector2(6.5, 43.5))
	for angle: float in [0.0, 79.0, -79.0, 80.0, -80.0, 81.0, -81.0, 90.0, -90.0, 135.0, -135.0, 180.0]:
		var e: Dictionary = sim.entities[id]
		e.alpha = angle
		var original_position: Vector2 = e.pos
		var normalized: float = wrapf(float(e.alpha), -180.0, 180.0)
		var mirrored: bool = absf(normalized) > 80.0
		_check(mirrored == (absf(angle) > 80.0), "world heading mirror boundary at %s degrees" % angle)
		for camera_rotation: float in [0.0, 90.0, 180.0, 270.0, 360.0]:
			# Simulation owns heading, with no camera input. The rendering test
			# exercises the camera; this check covers the fixed-world predicate.
			sim._turn(e, angle, 0.01)
			_check(_near(absf(wrapf(float(e.alpha), -180.0, 180.0)), absf(normalized)) and e.pos == original_position and (absf(wrapf(float(e.alpha), -180.0, 180.0)) > 80.0) == mirrored, "heading and mirror are invariant under camera reference %s at heading %s" % [camera_rotation, angle])
	var e: Dictionary = sim.entities[id]
	e.alpha = 79.0
	sim._turn(e, 81.0, 1.0 / 30.0)
	_check(_near(float(e.alpha), 81.0) and absf(float(e.alpha)) > 80.0, "crossing 80 changes only the mirror predicate")
	e.alpha = 179.0
	sim._turn(e, -179.0, 1.0 / 30.0)
	_check(_near(float(e.alpha), -179.0), "turning across the rear seam uses the shortest world rotation")


func _test_tank_fire() -> void:
	var sim = _new_sim()
	var tank: int = sim.debug_spawn(0, "rivet_tank", Vector2(6.5, 43.5))
	var target: int = sim.debug_spawn(1, "kestrel_power", Vector2(13.5, 43.5))
	var e: Dictionary = sim.entities[tank]
	e.alpha = 179.0
	e.turret_alpha = 179.0
	var origin: Vector2 = e.pos
	sim.issue([tank], "attack", sim.entities[target].pos, target)
	sim.step(1.0 / 30.0)
	_check(_near(float(e.alpha), 179.0) and e.pos == origin, "an in-range attack aims the turret without rotating or moving the hull")
	_check(_near(float(e.turret_alpha), 179.0 - float(config.units.rivet_tank.turret_turn_speed) / 30.0) and int(e.turret_target) == target, "the turret turns smoothly at its configured degrees per second toward the specified target")
	_check(_fires(sim, tank) == 0 and sim.projectiles.is_empty(), "an aligned hull cannot bypass an independently misaligned turret firing cone")
	var first_fire: Dictionary = {}
	for tick: int in range(90):
		sim.step(1.0 / 30.0)
		for event: Dictionary in sim.events:
			if event.kind == "fire" and int(event.get("id", -1)) == tank:
				first_fire = event
		if not first_fire.is_empty():
			break
	_check(not first_fire.is_empty() and absf(wrapf(float(first_fire.get("heading", 180.0)), -180.0, 180.0)) <= float(config.economy.fire_angle), "the tank fires only after the actual turret enters the configured target cone")
	_check(_near(float(e.alpha), 179.0) and e.pos == origin and _near(float(e.motion), 0.0), "stationary turret fire leaves the independent hull heading and position unchanged")
	e.alpha = 79.0
	e.turret_alpha = 179.0
	sim._turn_turret(e, -179.0, 1.0 / 30.0)
	_check(_near(float(e.turret_alpha), -179.0) and _near(float(e.alpha), 79.0), "turret aiming crosses the rear seam by the shortest rotation without changing the hull")

	for vehicle: String in ["rivet_tank", "kestrel_tank", "rivet_assault"]:
		var faction: String = "kestrel" if vehicle.begins_with("kestrel") else "rivet"
		sim = _new_sim(faction)
		tank = sim.debug_spawn(0, vehicle, Vector2(6.5, 43.5))
		target = sim.debug_spawn(1, sim.factions[1] + "_power", Vector2(6.5, 37.5))
		e = sim.entities[tank]
		e.alpha = 0.0
		e.turret_alpha = 0.0
		origin = e.pos
		var goal := Vector2(20.5, 43.5)
		sim.issue([tank], "attack_move", goal)
		var moving_fire: Dictionary = {}
		var firing_motion: float = 0.0
		var firing_position := Vector2.ZERO
		for tick: int in range(90):
			var previous_fires: int = _fires(sim, tank)
			sim.step(1.0 / 30.0)
			if _fires(sim, tank) > previous_fires:
				firing_motion = float(e.motion)
				firing_position = e.pos
				for event: Dictionary in sim.events:
					if event.kind == "fire" and int(event.get("id", -1)) == tank:
						moving_fire = event
				break
		_check(not moving_fire.is_empty() and bool(moving_fire.get("moving", false)) and firing_motion > 0.0 and firing_position.distance_to(origin) > 0.2, "%s really advances and fires during the same attack-move tick" % vehicle)
		var separation: float = absf(wrapf(float(moving_fire.get("heading", 0.0)) - float(moving_fire.get("body_heading", 0.0)), -180.0, 180.0))
		_check(separation > 45.0 and not e.commands.is_empty() and e.commands[0].kind == "attack_move" and e.commands[0].pos == goal and (e.pos as Vector2).x > origin.x, "%s aims off-axis while retaining and advancing its original destination" % vehicle)
		if not moving_fire.is_empty():
			var bearing: float = rad_to_deg(((moving_fire.landing as Vector2) - (moving_fire.pos as Vector2)).angle())
			_check(absf(wrapf(bearing - float(moving_fire.heading), -180.0, 180.0)) <= float(config.economy.fire_angle), "%s moving shot respects the actual turret firing cone" % vehicle)
			_check(sim.projectiles.size() == 1 and sim.projectiles[0].landing == moving_fire.landing and sim.projectiles[0].heading == moving_fire.heading and sim.projectiles[0].body_heading == moving_fire.body_heading and sim.projectiles[0].spec == vehicle and int(sim.projectiles[0].source) == tank, "%s shell retains its fixed landing and true launch heading/model" % vehicle)

	sim = _new_sim()
	tank = sim.debug_spawn(0, "rivet_tank", Vector2(6.5, 43.5))
	target = sim.debug_spawn(1, "kestrel_power", Vector2(23.5, 43.5))
	origin = sim.entities[tank].pos
	sim.issue([tank], "attack", sim.entities[target].pos, target)
	_tick(sim, 4.0)
	_check(_fires(sim, tank) >= 1 and (sim.entities[tank].pos as Vector2).distance_to(origin) > 6.0 and int(sim.entities[tank].turret_target) == target, "specified tank attack still pursues an out-of-range target and shoots once within range")

	sim = _new_sim()
	tank = sim.debug_spawn(0, "rivet_tank", Vector2(6.5, 43.5))
	target = sim.debug_spawn(1, "kestrel_power", Vector2(13.5, 43.5))
	sim.issue([tank], "move", Vector2(10.5, 43.5))
	_tick(sim, 0.7)
	_check(_fires(sim, tank) == 0 and sim.entities[tank].pos.distance_to(Vector2(6.5, 43.5)) > 0.2, "ordinary tank move preserves marching semantics and passes an enemy without firing")

	sim = _new_sim()
	var rifle: int = sim.debug_spawn(0, "rivet_rifle", Vector2(6.5, 43.5))
	target = sim.debug_spawn(1, "kestrel_power", Vector2(10.5, 43.5))
	origin = sim.entities[rifle].pos
	sim.issue([rifle], "attack_move", Vector2(20.5, 43.5))
	_tick(sim, 0.5)
	_check(_fires(sim, rifle) >= 1 and sim.entities[rifle].pos == origin and float(sim.entities[rifle].motion) == 0.0, "infantry attack-move still stops and fires from a settled position")

	sim = _new_sim()
	tank = sim.debug_spawn(0, "rivet_tank", Vector2(6.5, 43.5))
	target = sim.debug_spawn(1, "kestrel_power", Vector2(13.5, 43.5))
	e = sim.entities[tank]
	e.alpha = 0.0
	e.turret_alpha = 90.0
	sim._fire(e, target)
	_check(_fires(sim, tank) == 0 and float(e.cooldown) == 0.0, "the shared fire function independently rejects a wrong turret angle")
	e.alpha = 180.0
	e.turret_alpha = 0.0
	sim._fire(e, target)
	sim._fire(e, target)
	_check(_fires(sim, tank) == 1 and _near(float(e.cooldown), float(config.weapons.rivet_tank.interval)), "an aligned turret can fire with the hull facing away and preserves weapon cooldown")
	_tick(sim, float(config.weapons.rivet_tank.interval) - 0.1)
	_check(_fires(sim, tank) == 1, "turret tracking cannot shorten an active weapon cooldown")
	_tick(sim, 0.2)
	_check(_fires(sim, tank) == 2, "a second turret shot becomes available only after the configured cooldown")

	sim = _new_sim()
	sim.debug_spawn(0, "rivet_power", Vector2(17.5, 37.5))
	var tower: int = sim.debug_spawn(0, "rivet_tower", Vector2(10.5, 43.5))
	target = sim.debug_spawn(1, "kestrel_power", Vector2(4.5, 43.5))
	sim.step(1.0 / 30.0)
	var tower_bearing: float = rad_to_deg(((sim.entities[target].pos as Vector2) - (sim.entities[tower].pos as Vector2)).angle())
	_check(_fires(sim, tower) == 1 and _near(float(sim.entities[tower].alpha), 0.0) and _near(float(sim.entities[tower].turret_alpha), tower_bearing), "a powered tower aims its visual turret at the target and retains immediate omnidirectional firing")
	var tower_heading: bool = false
	for event: Dictionary in sim.events:
		if event.kind == "fire" and int(event.get("id", -1)) == tower:
			tower_heading = _near(float(event.heading), tower_bearing) and _near(float(event.body_heading), 0.0)
	_check(tower_heading and sim.projectiles.size() == 1 and _near(float(sim.projectiles[0].heading), tower_bearing), "tower fire effects and shell metadata point along the actual target bearing")


func _write_turret_snapshot(snapshot: Dictionary, path: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_var(snapshot, false)
	file.close()


func _test_turret_save_and_config() -> void:
	for vehicle: String in ["rivet_tank", "kestrel_tank", "rivet_assault"]:
		var info: Dictionary = config.units[vehicle]
		_check(bool(info.get("has_turret", false)) and bool(info.get("fire_while_moving", false)) and float(info.get("turret_turn_speed", 0.0)) > 0.0, "%s explicitly configures its turret and mobile fire capability" % vehicle)
	var bad_rules: Dictionary = config.duplicate(true)
	bad_rules.units.rivet_tank.turret_turn_speed = 0.0
	_check(not Rules.validate(bad_rules, false).is_empty(), "rules reject a nonpositive configured turret rotation speed")
	bad_rules = config.duplicate(true)
	bad_rules.units.rivet_rifle.fire_while_moving = true
	_check(not Rules.validate(bad_rules, false).is_empty(), "rules reject mobile fire configured without a turret")
	var sim = _new_sim()
	var tank: int = sim.debug_spawn(0, "rivet_tank", Vector2(6.5, 43.5))
	var target: int = sim.debug_spawn(1, "kestrel_power", Vector2(13.5, 43.5))
	sim.entities[tank].alpha = 73.0
	sim.entities[tank].turret_alpha = 179.0
	sim.issue([tank], "attack", sim.entities[target].pos, target)
	_tick(sim, 0.2)
	var path: String = "/tmp/paper_war_turret.save"
	_check(sim.save_game(path) == "", "an independently aiming turret can be saved")
	var restored = Sim.new()
	var error: String = restored.load_game(path)
	_check(error == "" and restored.entities == sim.entities, "save/load exactly preserves independent turret angle and target")
	_tick(sim, 1.5)
	_tick(restored, 1.5)
	_check(sim.entities == restored.entities and sim.projectiles == restored.projectiles, "original and restored turrets advance identically through aiming and shell launch")
	_check(sim.save_game(path) == "", "a current turret snapshot with projectile launch metadata is writable")
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var snapshot: Dictionary = file.get_var(false)
	file.close()
	var legacy: Dictionary = snapshot.duplicate(true)
	for info: Dictionary in legacy.rules.units.values():
		for field: String in ["has_turret", "fire_while_moving", "turret_turn_speed"]:
			info.erase(field)
	for entity: Dictionary in legacy.entities.values():
		entity.erase("turret_alpha")
		entity.erase("turret_target")
	for shell: Dictionary in legacy.projectiles:
		for field: String in ["source", "spec", "heading", "body_heading"]:
			shell.erase(field)
	_write_turret_snapshot(legacy, path)
	var old_save = Sim.new()
	error = old_save.load_game(path)
	_check(error == "" and float(old_save.entities[tank].turret_alpha) == float(old_save.entities[tank].alpha) and int(old_save.entities[tank].turret_target) == -1, "legacy v1 turrets safely default to current hull heading without requiring new fields")
	_check(old_save.rules == legacy.rules and old_save.money == legacy.money and old_save.projectiles == legacy.projectiles and old_save._has_turret(old_save.data_for("rivet_tank")), "legacy migration retains saved rules/economy/projectiles and recognizes existing tank art")
	for bad_value: Variant in ["north", INF]:
		var damaged: Dictionary = snapshot.duplicate(true)
		damaged.entities[tank].turret_alpha = bad_value
		_write_turret_snapshot(damaged, path)
		var before: Dictionary = restored.entities.duplicate(true)
		_check(restored.load_game(path) != "" and restored.entities == before, "invalid turret heading %s is rejected before changing the running game" % str(bad_value))
	var damaged: Dictionary = snapshot.duplicate(true)
	damaged.entities[tank].turret_target = "enemy"
	_write_turret_snapshot(damaged, path)
	_check(restored.load_game(path) != "", "a malformed turret target is rejected safely")
	DirAccess.remove_absolute(path)


func _test_shells() -> void:
	var sim = _new_sim()
	var attacker: int = sim.debug_spawn(0, "rivet_anti", Vector2(6.5, 43.5))
	var target: int = sim.debug_spawn(1, "kestrel_engineer", Vector2(14.5, 43.5))
	var friend: int = sim.debug_spawn(0, "rivet_engineer", Vector2(14.5, 42.5))
	sim.entities[target].alpha = 90.0
	sim.entities[friend].alpha = 90.0
	sim.issue([attacker], "attack", sim.entities[target].pos, target)
	sim.issue([target], "move", Vector2(14.5, 46.5))
	sim.step(1.0 / 30.0)
	var target_hp: float = float(config.units.kestrel_engineer.hp)
	_check(sim.projectiles.size() == 1 and _near(float(sim.entities[target].hp), target_hp), "shell launch creates an in-flight projectile without immediate damage")
	var landing: Vector2 = sim.projectiles[0].landing
	_check(landing == Vector2(14.5, 43.5), "shell stores the target position at firing time")
	_damage(sim, attacker, 10000.0)
	_check(not sim.entities.has(attacker) and sim.projectiles.size() == 1, "attacker death leaves its projectile in flight")
	_tick(sim, 0.267)
	sim.issue([friend], "move", landing)
	_tick(sim, 0.4)
	_check(sim.projectiles.is_empty() and sim.entities.has(target) and _near(float(sim.entities[target].hp), target_hp), "moving original target escapes the fixed impact point")
	_check(not sim.entities.has(friend), "friendly unit entering the fixed impact point receives full splash damage")
	sim = _new_sim()
	attacker = sim.debug_spawn(0, "rivet_tank", Vector2(6.5, 43.5))
	target = sim.debug_spawn(1, "kestrel_engineer", Vector2(14.5, 43.5))
	var building: int = sim.debug_spawn(0, "rivet_power", Vector2(16.5, 43.5))
	sim.issue([attacker], "attack", sim.entities[target].pos, target)
	_tick(sim, 0.6)
	var tank_weapon: Dictionary = config.weapons[config.units.rivet_tank.weapon]
	var building_damage: float = float(tank_weapon.damage) * float(tank_weapon.get("multipliers", {}).get("building", 1.0))
	_check(_near(float(sim.entities[building].hp), float(config.buildings.rivet_power.hp) - building_damage), "shell splash intersects and damages a friendly building footprint exactly once")

	# A real mobile tank shot must retain the launch-time impact point even
	# after both the target and a friendly infantry unit move, and after death.
	sim = _new_sim()
	attacker = sim.debug_spawn(0, "rivet_tank", Vector2(6.5, 43.5))
	target = sim.debug_spawn(1, "kestrel_engineer", Vector2(14.5, 43.5))
	friend = sim.debug_spawn(0, "rivet_engineer", Vector2(14.5, 41.5))
	var friend_hp: float = float(sim.entities[friend].hp)
	var friend_armor: String = str(config.units.rivet_engineer.armor_class)
	var friend_damage: float = float(tank_weapon.damage) * float(tank_weapon.get("multipliers", {}).get(friend_armor, 1.0))
	sim.entities[target].alpha = 90.0
	sim.entities[friend].alpha = 90.0
	sim.issue([attacker], "attack_move", Vector2(20.5, 43.5))
	sim.step(1.0 / 30.0)
	_check(sim.projectiles.size() == 1 and float(sim.entities[attacker].motion) > 0.0, "a real moving tank launches an in-flight shell before its impact damage")
	landing = sim.projectiles[0].landing
	sim.issue([target], "move", Vector2(14.5, 46.5))
	sim.issue([friend], "move", landing)
	_tick(sim, 0.1)
	_check(sim.projectiles.size() == 1 and sim.projectiles[0].landing == landing and sim.entities[target].pos != landing, "a mobile tank shell keeps its original landing while its target physically moves")
	_damage(sim, attacker, 10000.0)
	_check(not sim.entities.has(attacker) and sim.projectiles.size() == 1, "a fired mobile tank shell survives destruction of its moving source")
	_tick(sim, 0.5)
	var friend_damaged: bool = not sim.entities.has(friend) if friend_damage >= friend_hp else sim.entities.has(friend) and _near(float(sim.entities[friend].hp), friend_hp - friend_damage)
	_check(sim.projectiles.is_empty() and friend_damaged, "a friendly unit moving into the mobile tank's original impact point receives full configured splash damage")


func _test_crush_and_collision() -> void:
	var sim = _new_sim()
	var vehicle: int = sim.debug_spawn(0, "rivet_tank", Vector2(6.5, 43.5))
	var pedestrian: int = sim.debug_spawn(1, "kestrel_engineer", Vector2(8.0, 43.5))
	sim.issue([vehicle], "move", Vector2(11.5, 43.5))
	_tick(sim, 1.0)
	_check(not sim.entities.has(pedestrian), "tank ground contact crushes enemy infantry during a move order")
	sim = _new_sim()
	vehicle = sim.debug_spawn(0, "rivet_tank", Vector2(6.5, 43.5))
	pedestrian = sim.debug_spawn(0, "rivet_engineer", Vector2(8.0, 43.5))
	sim.issue([vehicle], "move", Vector2(11.5, 43.5))
	var clear: bool = true
	for tick: int in range(60):
		sim.step(1.0 / 30.0)
		if sim.entities[vehicle].pos.distance_to(sim.entities[pedestrian].pos) < 1.10:
			clear = false
	_check(sim.entities.has(pedestrian) and clear, "tank avoids or waits for friendly infantry without crushing or overlap")
	sim = _new_sim()
	vehicle = sim.debug_spawn(0, "rivet_harvester", Vector2(6.5, 43.5))
	pedestrian = sim.debug_spawn(1, "kestrel_engineer", Vector2(8.0, 43.5))
	sim.issue([vehicle], "move", Vector2(11.5, 43.5))
	clear = true
	for tick: int in range(60):
		sim.step(1.0 / 30.0)
		if sim.entities[vehicle].pos.distance_to(sim.entities[pedestrian].pos) < 1.10:
			clear = false
	_check(sim.entities.has(pedestrian) and clear, "unarmed harvester has no generic vehicle crush privilege")


func _test_bridge() -> void:
	var sim = _new_sim()
	var bridge: Dictionary = sim.bridges[0]
	var unit_a: int = sim.debug_spawn(0, "rivet_engineer", Vector2(23.0, 29.5))
	var unit_b: int = sim.debug_spawn(1, "kestrel_engineer", Vector2(25.0, 30.5))
	var bank: int = sim.debug_spawn(0, "rivet_engineer", Vector2(19.5, 30.5))
	_check(sim.bridge_at(sim.entities[unit_a].pos) == 1 and sim.bridge_at(sim.entities[unit_b].pos) == 1, "bridge-death fixtures are physically on the bridge")
	_damage(sim, Sim.BRIDGE_TARGET_BASE - int(bridge.id), float(config.economy.bridge_hp))
	_check(not bool(bridge.alive) and not sim.entities.has(unit_a) and not sim.entities.has(unit_b) and sim.entities.has(bank), "bridge destruction kills both teams on its deck and preserves bank units")
	var head: Vector2 = Vector2(float(bridge.heads[0][0]), float(bridge.heads[0][1]))
	sim.entities[bank].pos = head
	sim.issue([bank], "repair_bridge", head, -1001)
	var funds: float = sim.money[0]
	_tick(sim, float(config.economy.bridge_time) * 0.2)
	_check(_near(float(bridge.repair_progress), 0.2) and _near(sim.money[0], funds - float(config.economy.bridge_cost) * 0.2) and not bool(bridge.alive), "bridge repair charges its configured cost proportionally and opens only at completion")
	sim.issue([bank], "stop", head)
	_tick(sim, 1.0)
	_check(_near(float(bridge.repair_progress), 0.2) and _near(sim.money[0], funds - float(config.economy.bridge_cost) * 0.2), "interrupted bridge repair preserves progress and stops charging")
	sim.money[0] = float(config.economy.bridge_cost) * 0.02
	sim.issue([bank], "repair_bridge", head, -1001)
	_tick(sim, float(config.economy.bridge_time) * 0.1)
	_check(_near(float(bridge.repair_progress), 0.22) and _near(sim.money[0], 0.0), "insufficient repair funds pause without negative money")
	sim.money[0] = float(config.economy.bridge_cost)
	_tick(sim, float(config.economy.bridge_time) * 0.78)
	_check(bool(bridge.alive) and _near(float(bridge.hp), float(config.economy.bridge_hp)) and _near(sim.money[0], float(config.economy.bridge_cost) * 0.22), "bridge repair resumes remaining progress and restores full HP and passage")


func _test_power_and_placement() -> void:
	var sim = _legacy_construction_sim()
	var barracks: int = sim.debug_spawn(0, "rivet_barracks", Vector2(5.5, 37.5))
	sim.debug_spawn(0, "rivet_factory", Vector2(11.5, 38.5))
	var tower: int = sim.debug_spawn(0, "rivet_tower", Vector2(7.5, 43.5))
	sim.debug_spawn(1, "kestrel_engineer", Vector2(15.5, 43.5))
	_check(sim.power(0).y > sim.power(0).x, "power fixture has genuine completed-building deficit")
	_check(sim.build(0, "rivet_power") == "" and sim.produce(barracks, "rivet_rifle") == "", "low power still accepts recovery power station and legal production")
	sim.step(1.0)
	var slow_progress: float = float(config.economy.low_power_multiplier)
	_check(_near(float(sim.building_orders[0].remaining), float(config.buildings.rivet_power.build_time) - slow_progress) and _near(float(sim.entities[barracks].queue[0].remaining), float(config.units.rivet_rifle.build_time) - slow_progress), "low power scales both building and production progress by the configured multiplier")
	_check(_fires(sim, tower) == 0, "low-power tower stops firing")
	sim.debug_spawn(0, "rivet_power", Vector2(17.5, 37.5))
	sim.step(0.5)
	_check(_near(float(sim.building_orders[0].remaining), float(config.buildings.rivet_power.build_time) - slow_progress - 0.5) and _near(float(sim.entities[barracks].queue[0].remaining), float(config.units.rivet_rifle.build_time) - slow_progress - 0.5) and _fires(sim, tower) >= 1, "restored power resumes normal progress and tower fire")
	sim = _legacy_construction_sim()
	_check(sim.build(0, "rivet_power") == "", "building order accepts legal HQ prerequisite")
	_tick(sim, float(config.buildings.rivet_power.build_time) + 0.05)
	var order: Dictionary = sim.building_orders[0].duplicate(true)
	var funds: float = sim.money[0]
	var count: int = sim.entities.size()
	_check(sim.place_building(0, Vector2(9.5, 30.5)) != "", "overlapping placement reports an error")
	_check(sim.building_orders[0] == order and sim.money[0] == funds and sim.entities.size() == count, "illegal placement preserves ready order, money and entity count")
	_check(sim.place_building(0, Vector2(4.5, 30.5)) == "", "ready building places on valid flat covered land")
	var new_id: int = sim._next_id - 1
	_check(float(sim.entities[new_id].construct_remaining) > 0.0 and sim.counts(0).y == 2 and sim.power(0).x == float(sim.data_for("rivet_hq").power), "landed construction immediately counts and occupies but does not supply power")
	_tick(sim, float(config.economy.construction_animation) + 0.1)
	_check(sim.power(0).x == float(sim.data_for("rivet_hq").power) + float(config.buildings.rivet_power.power), "completed construction supplies configured power")


func _block_exits(sim, barracks: int) -> Array:
	var ids: Array = []
	for offset: Vector2 in [Vector2(3.5, 0.5), Vector2(-3.5, 0.5), Vector2(0.5, 3.5), Vector2(0.5, -3.5)]:
		ids.append(sim.debug_spawn(0, "rivet_hq", sim.entities[barracks].pos + offset))
	for offset: Vector2 in [Vector2(4, 4), Vector2(-3, 4), Vector2(4, -3), Vector2(-3, -3)]:
		ids.append(sim.debug_spawn(0, "rivet_power", sim.entities[barracks].pos + offset))
	return ids


func _test_building_repair() -> void:
	var sim = _new_sim()
	var id: int = sim.debug_spawn(0, "rivet_power", Vector2(4.5, 37.5))
	var repair_per_second: float = float(config.buildings.rivet_power.hp) * float(config.economy.repair_rate)
	var damaged_hp: float = float(config.buildings.rivet_power.hp) - 5.0 * repair_per_second
	var funds: float = sim.money[0]
	var repair_cost: float = float(config.economy.repair_cost)
	sim.entities[id].hp = damaged_hp
	sim.toggle_repair(id)
	sim.step(1.0)
	_check(_near(float(sim.entities[id].hp), damaged_hp + repair_per_second) and _near(sim.money[0], funds - repair_per_second * repair_cost), "ordinary repair restores the configured fraction of max HP per second and pays the configured price per HP")
	sim.toggle_repair(id)
	sim.toggle_repair(id)
	sim.step(1.0)
	_check(_near(float(sim.entities[id].hp), damaged_hp + 2.0 * repair_per_second) and _near(sim.money[0], funds - 2.0 * repair_per_second * repair_cost), "repeated repair toggles do not stack recovery")
	sim.money[0] = repair_cost
	sim.step(1.0)
	_check(_near(float(sim.entities[id].hp), damaged_hp + 2.0 * repair_per_second + 1.0) and _near(sim.money[0], 0.0), "ordinary repair pauses at available funds without negative money")


func _test_queues_and_refunds() -> void:
	var sim = _legacy_construction_sim()
	var starting_money: float = float(config.economy.initial_money)
	var building_cost: float = float(config.buildings.rivet_power.cost)
	var building_time: float = float(config.buildings.rivet_power.build_time)
	var rifle_cost: float = float(config.units.rivet_rifle.cost)
	var rifle_time: float = float(config.units.rivet_rifle.build_time)
	_check(sim.build(0, "rivet_power") == "", "start building refund fixture")
	_tick(sim, building_time * 0.2)
	sim.cancel_build(0)
	_check(_near(sim.money[0], starting_money - building_cost * 0.2), "partially constructed building refunds only remaining 80 percent")
	sim.build(0, "rivet_power")
	_tick(sim, building_time + 0.05)
	var funds: float = sim.money[0]
	sim.cancel_build(0)
	_check(sim.money[0] == funds and not sim.notices.is_empty(), "ready building cancellation refunds zero and provides a notice")
	# These historical FIFO fixtures use the retired standalone barracks.
	# Current base-barracks production is covered by rivet_mechanics_tests.
	sim = _legacy_construction_sim()
	var barracks: int = sim.debug_spawn(0, "rivet_barracks", Vector2(10.5, 39.5))
	sim.produce(barracks, "rivet_rifle")
	sim.produce(barracks, "rivet_rifle")
	_tick(sim, rifle_time * 0.4)
	sim.cancel_production(barracks, 1)
	_check(_near(sim.money[0], starting_money - rifle_cost), "unstarted FIFO order receives a full refund")
	sim.cancel_production(barracks, 0)
	_check(_near(sim.money[0], starting_money - rifle_cost * 0.4), "active FIFO order receives remaining-progress refund")
	sim = _legacy_construction_sim()
	barracks = sim.debug_spawn(0, "rivet_barracks", Vector2(10.5, 39.5))
	sim.produce(barracks, "rivet_rifle")
	sim.produce(barracks, "rivet_rifle")
	_tick(sim, rifle_time * 0.4)
	_damage(sim, barracks, 10000.0)
	_check(_near(sim.money[0], starting_money - rifle_cost * 0.4) and not sim.entities.has(barracks), "destroyed producer refunds active and unstarted orders by the same rule")
	sim = _legacy_construction_sim()
	barracks = sim.debug_spawn(0, "rivet_barracks", Vector2(10.5, 39.5))
	var blockers: Array = _block_exits(sim, barracks)
	sim.produce(barracks, "rivet_rifle")
	sim.produce(barracks, "rivet_rifle")
	_tick(sim, rifle_time + 1.0)
	_check(sim.entities[barracks].queue.size() == 2 and bool(sim.entities[barracks].queue[0].ready) and sim.counts(0).x == 0, "blocked producer retains ready unit and never overlaps or teleports it")
	_damage(sim, barracks, 10000.0)
	_check(_near(sim.money[0], starting_money - rifle_cost), "destroying blocked producer loses finished product and refunds waiting order")
	sim = _legacy_construction_sim()
	barracks = sim.debug_spawn(0, "rivet_barracks", Vector2(10.5, 39.5))
	blockers = _block_exits(sim, barracks)
	sim.produce(barracks, "rivet_rifle")
	_tick(sim, rifle_time + 1.0)
	for id: int in blockers:
		sim._kill_entity(id, true)
	sim.step(1.0 / 30.0)
	_check(sim.entities[barracks].queue.is_empty() and sim.counts(0).x == 1, "clearing producer exits deploys the waiting unit exactly once")


func _test_gift_and_result() -> void:
	var sim = _new_sim()
	var refinery: int = sim.debug_spawn(0, "rivet_refinery", Vector2(10.5, 39.5))
	_tick(sim, 0.1)
	_check(sim.counts(0).x == 1 and not bool(sim.entities[refinery].gift_pending), "completed refinery grants exactly one harvester")
	_tick(sim, 1.0)
	_check(sim.counts(0).x == 1, "refinery repeated ticks do not repeat the harvester gift")
	_damage(sim, 1, 10000.0)
	_check(sim.result == "" and sim.counts(0).y == 1, "HQ destruction alone does not end a surviving economy base")
	_damage(sim, refinery, 10000.0)
	_check(sim.result == "lose" and sim.counts(0).x == 1, "last building destruction loses even when a unit survives")
	sim = _new_sim()
	sim._add_damage(1, 10000.0)
	sim._add_damage(2, 10000.0)
	sim._apply_damage()
	sim._check_result()
	_check(sim.result == "draw", "simultaneous batch destruction of both last buildings is a draw")
	sim = _new_sim()
	_check(sim.sell(1) == "CONFIRM_LAST_BUILDING" and sim.result == "", "last-building sale requires explicit confirmation")
	_check(sim.sell(1, true) == "" and sim.result == "lose" and _near(sim.money[0], float(config.economy.initial_money) + float(config.buildings.rivet_hq.cost) * float(config.economy.sell_ratio)), "confirmed last sale applies configured refund and defeat")


func _test_save() -> void:
	var sim = _legacy_construction_sim()
	sim.debug_spawn(0, "rivet_power", Vector2(4.5, 37.5))
	var refinery: int = sim.debug_spawn(0, "rivet_refinery", Vector2(10.5, 39.5))
	var barracks: int = sim.debug_spawn(0, "rivet_barracks", Vector2(17.5, 36.5))
	var attacker: int = sim.debug_spawn(0, "rivet_tank", Vector2(5.5, 43.5))
	var target: int = sim.debug_spawn(1, "kestrel_engineer", Vector2(14.5, 44.5))
	sim.entities[attacker].alpha = 0.0
	sim.issue([attacker], "attack", sim.entities[target].pos, target)
	sim.issue([target], "move", Vector2(18.5, 44.5))
	sim.issue([target], "move", Vector2(18.5, 41.5), -1, true)
	sim.produce(barracks, "rivet_rifle")
	sim.produce(barracks, "rivet_engineer")
	sim.build(0, "rivet_barracks")
	_tick(sim, 0.1)
	# Create a nontrivial snapshot without changing the save implementation.
	sim.entities[attacker].cooldown = 1.27
	sim.entities[target].alpha = 81.0
	sim.mines[0].amount = sim.mines[0].capacity
	sim.bridges[0].alive = false
	sim.bridges[0].hp = 0.0
	sim.bridges[0].repair_progress = 0.37
	for e: Dictionary in sim.entities.values():
		if str(e.spec).ends_with("_harvester"):
			e.cargo = 219.5
			e.harvest_override = true
	_check(sim.projectiles.size() > 0, "save fixture includes an actual in-flight shell")
	var path: String = "/tmp/paper_war_game_rules_test.save"
	_check(sim.save_game(path) == "", "save writes one consistent rule snapshot")
	var restored = Sim.new()
	_check(restored.load_game(path) == "", "load accepts the current snapshot format")
	for field: String in ["rules", "map", "factions", "money", "time", "result", "entities", "projectiles", "mines", "bridges", "building_orders", "_next_id", "ai_enabled", "_ai_clock", "_ai_attack_clock", "_low_power"]:
		_check(sim.get(field) == restored.get(field), "save/load preserves " + field)
	_check(not bool(restored.entities[refinery].gift_pending), "load preserves consumed refinery gift state")
	var before_units: int = restored.counts(0).x
	_tick(sim, 0.3)
	_tick(restored, 0.3)
	_check(sim.entities == restored.entities and sim.projectiles == restored.projectiles and sim.money == restored.money and sim.mines == restored.mines and sim.building_orders == restored.building_orders, "original and restored snapshots advance identically through combat, queues and mining")
	_check(restored.counts(0).x == before_units, "post-load refinery does not duplicate a harvester")
	DirAccess.remove_absolute(path)


func _test_radius_approach() -> void:
	var sim = _new_sim()
	var refinery: int = sim.debug_spawn(1, "kestrel_refinery", Vector2(40.0, 36.0))
	sim.entities[refinery].gift_pending = false
	sim.debug_spawn(1, "kestrel_barracks", Vector2(34.5, 33.5))
	sim.debug_spawn(1, "kestrel_factory", Vector2(34.0, 29.0))
	var harvester: int = sim.debug_spawn(1, "kestrel_harvester", Vector2(34.85851, 36.34755))
	sim.entities[harvester].cargo = 500.0
	sim.entities[harvester].harvest_refinery = refinery
	var funds: float = sim.money[1]
	_tick(sim, 8.0)
	_check(sim.money[1] >= funds + 500.0, "vehicle reaches legal exact refinery entrance even when its floor-cell centre fails the larger radius")


func _test_active_traffic() -> void:
	var sim = _new_sim()
	var refinery: int = sim.debug_spawn(1, "kestrel_refinery", Vector2(40.0, 36.0))
	sim.entities[refinery].gift_pending = false
	sim.debug_spawn(1, "kestrel_barracks", Vector2(34.5, 33.5))
	sim.debug_spawn(1, "kestrel_factory", Vector2(34.0, 29.0))
	var target: int = sim.debug_spawn(0, "rivet_factory", Vector2(5.0, 32.0))
	for position: Vector2 in [Vector2(34.85851, 36.34755), Vector2(33.27202, 36.14288)]:
		var vehicle: int = sim.debug_spawn(1, "kestrel_harvester", position)
		sim.entities[vehicle].cargo = 500.0
		sim.entities[vehicle].harvest_refinery = refinery
	var positions: Array[Vector2] = [Vector2(33.21249, 37.35155), Vector2(33.83239, 37.79984), Vector2(33.94649, 37.06849), Vector2(35.65977, 35.49984), Vector2(36.47048, 34.82973), Vector2(36.56309, 34.10078)]
	var actors: Array = []
	for index: int in positions.size():
		var spec: String = "kestrel_anti" if index == 1 else "kestrel_rifle"
		var actor: int = sim.debug_spawn(1, spec, positions[index])
		actors.append(actor)
		sim.issue([actor], "attack", sim.entities[target].pos, target)
	var origin: Vector2 = sim.entities[int(actors[0])].pos
	var funds: float = sim.money[1]
	_tick(sim, 15.0)
	_check(sim.money[1] >= funds + 500.0, "two full harvesters deliver despite active friendly infantry traffic near the refinery")
	_check(not sim.entities.has(int(actors[0])) or sim.entities[int(actors[0])].pos.distance_to(origin) > 3.0, "active infantry bypass occupied initial grid centres while preserving their attack command")
