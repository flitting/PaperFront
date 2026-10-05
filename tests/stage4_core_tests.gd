extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
const Hero = preload("res://scripts/hero_rules.gd")
const Saves = preload("res://scripts/sim_save_validator.gd")
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var rules: Dictionary = Rules.load_rules("res://data/rules.json", false)
	check(not rules.is_empty(), "creator hand rules validate without assets")
	var sim = Sim.new()
	sim.native_kernels_enabled = false
	sim.setup(rules, "dev", 19, "sky", false)
	var factory: int = sim.debug_spawn(0, "sky_factory", Vector2(12.5, 42.5))
	var second_factory: int = sim.debug_spawn(0, "sky_factory", Vector2(20.5, 42.5))
	sim.debug_spawn(0, "sky_tech", Vector2(27.5, 42.5))
	sim.debug_spawn(0, "sky_command", Vector2(33.5, 42.5))
	sim.money[0] = 40000.0
	check(factory > 0 and second_factory > 0 and sim.availability(0, "sky_creator_hand", -1, factory).is_empty(), "tech and command unlock hero")
	check(sim.produce(factory, "sky_creator_hand").is_empty(), "first factory reserves hero")
	check(sim.produce(second_factory, "sky_creator_hand").contains("最多拥有一只"), "second factory cannot queue same hero")
	check(sim.cancel_production(factory, 0).is_empty(), "cancel reservation")
	check(sim.availability(0, "sky_creator_hand", -1, second_factory).is_empty(), "cancel releases reservation")
	var hand: int = sim.debug_spawn(0, "sky_creator_hand", Vector2(33.0, 35.0))
	check(hand > 0, "spawn hand")
	check(sim.produce(factory, "sky_creator_hand").contains("最多拥有一只"), "living hand occupies slot")
	check(sim.debug_spawn(0, "sky_creator_hand", Vector2(28, 35)) == -1, "debug spawn respects slot")
	var forced: int = sim.debug_spawn(0, "sky_creator_hand", Vector2(28, 35), true)
	check(forced > 0, "explicit fixture can force spawn")
	sim._kill_entity(forced, true)
	var target: int = sim.debug_spawn(1, "rivet_power", Vector2(38.5, 35.5))
	check(target > 0, "attack fixture")
	var hand_entity: Dictionary = sim.entities[hand]
	sim._fire(hand_entity, target)
	check(float(hand_entity.hand_strike) > 0.0 and sim.entities.has(target), "windup starts before impact")
	Hero.step(sim, 0.25)
	check(sim.entities.has(target), "no damage during windup")
	Hero.step(sim, 0.25)
	sim._apply_damage()
	check(not sim.entities.has(target), "one strike executes building")
	var second_target: int = sim.debug_spawn(1, "rivet_power", Vector2(38.5, 35.5))
	hand_entity.cooldown = 0.0
	sim._fire(hand_entity, second_target)
	sim.issue([hand], "stop", hand_entity.pos)
	Hero.step(sim, 0.6)
	check(sim.entities.has(second_target), "stop cancels windup")
	hand_entity.cooldown = 0.0
	sim._fire(hand_entity, second_target)
	hand_entity.emp_until = sim.time + 1.0
	Hero.step(sim, 0.6)
	sim._apply_damage()
	check(sim.entities.has(second_target), "EMP cancels pending impact")
	hand_entity.emp_until = 0.0
	hand_entity.cooldown = 0.0
	sim._fire(hand_entity, second_target)
	sim.entities[second_target].pos = Vector2(44.0, 35.5)
	Hero.step(sim, 0.6)
	sim._apply_damage()
	check(sim.entities.has(second_target), "target moving out of range cancels impact")
	sim.entities[second_target].pos = Vector2(38.5, 35.5)
	sim.vision_enabled = true
	sim.entities[second_target].visible_to = 3
	hand_entity.cooldown = 0.0
	sim._fire(hand_entity, second_target)
	sim.entities[second_target].visible_to = 2
	Hero.step(sim, 0.6)
	sim._apply_damage()
	check(sim.entities.has(second_target), "lost vision cancels impact without tracking hidden position")
	sim.vision_enabled = false
	var scaffold: int = sim._spawn(1, "rivet_power", Vector2(37.5, 35.5), false)
	check(scaffold > 0 and float(sim.entities[scaffold].construct_remaining) > 0.0, "unfinished building fixture")
	hand_entity.cooldown = 0.0
	sim._fire(hand_entity, scaffold)
	Hero.step(sim, 0.5)
	sim._apply_damage()
	check(not sim.entities.has(scaffold), "one strike executes unfinished building")
	sim._kill_entity(hand, true)
	check(sim.availability(0, "sky_creator_hand", -1, factory).is_empty(), "hero can be rebuilt after death")
	var duplicate: int = sim.debug_spawn(0, "sky_creator_hand", Vector2(31, 35))
	var duplicate2: int = sim.debug_spawn(0, "sky_creator_hand", Vector2(27, 35), true)
	var snapshot: Dictionary = _snapshot(sim)
	check(duplicate > 0 and duplicate2 > 0 and Saves.check(snapshot).contains("超过上限"), "malicious duplicate save rejected")
	_native_and_save_check(rules)
	_issued_approach_check(rules, false)
	_issued_approach_check(rules, true)
	_naval_approach_check(rules)
	print("Stage4 core checks: %d failed" % failures.size())
	for failure in failures: push_error(failure)
	quit(1 if not failures.is_empty() else 0)

func _native_and_save_check(rules: Dictionary) -> void:
	var native = Sim.new()
	native.setup(rules, "dev", 29, "sky", false)
	var enemy_hq: int = -1
	for e in native.entities.values():
		if int(e.team) == 1 and e.spec == "rivet_hq": enemy_hq = int(e.id)
	check(enemy_hq > 0, "native fixture enemy HQ")
	if enemy_hq < 0: return
	var hq_pos: Vector2 = native.entities[enemy_hq].pos
	var hand: int = native.debug_spawn(0, "sky_creator_hand", hq_pos + Vector2(-5.5, 0))
	check(hand > 0, "native fixture hero")
	if hand < 0: return
	native._fire(native.entities[hand], enemy_hq)
	check(float(native.entities[hand].hand_strike) > 0.0, "native path initiates windup")
	var save_path: String = "user://stage4_hero_windup_test.pfront"
	check(native.save_game(save_path).is_empty(), "windup save")
	var restored = Sim.new()
	check(restored.load_game(save_path).is_empty(), "windup restore")
	if restored.entities.has(hand) and restored.entities.has(enemy_hq):
		check(float(restored.entities[hand].hand_strike) > 0.0, "windup persists")
		restored.step(0.2)
		check(restored.entities.has(enemy_hq), "native windup defers HQ damage")
		restored.step(0.35)
		check(not restored.entities.has(enemy_hq), "native resumed strike executes HQ")

func _issued_approach_check(rules: Dictionary, use_native: bool) -> void:
	var sim = Sim.new()
	sim.native_unit_dispatch_enabled = use_native
	sim.setup(rules, "dev", 19, "sky", false)
	var hand: int = sim.debug_spawn(0, "sky_creator_hand", Vector2(12.5, 40.5))
	var power: int = sim.debug_spawn(1, "rivet_power", Vector2(26.5, 40.5))
	var path_name: String = "native" if use_native else "script"
	check(hand > 0 and power > 0, path_name + " attack approach fixture")
	if hand < 0 or power < 0: return
	sim.issue([hand], "attack", sim.entities[power].pos, power)
	var struck: bool = false
	for tick in range(540):
		sim.step(1.0 / 30.0)
		if sim.entities.has(hand) and float(sim.entities[hand].get("hand_strike", 0.0)) > 0.0: struck = true
		if not sim.entities.has(power): break
	check(struck and not sim.entities.has(power), path_name + " issued attack crosses approach and executes building")

func _naval_approach_check(rules: Dictionary) -> void:
	var sim = Sim.new()
	sim.setup_multiteam(rules, "islands", 7, ["sky", "rivet"], false)
	sim.vision_enabled = false
	var nav = sim._naval_navigation
	var source: Vector2 = Vector2.INF
	var target: Vector2 = Vector2.INF
	for z in range(15, int(sim.map.size) - 15, 3):
		if source.is_finite(): break
		for x in range(15, int(sim.map.size) - 38, 3):
			var first: Vector2 = Vector2(x + 0.5, z + 0.5)
			var last: Vector2 = first + Vector2(22, 0)
			if not nav.static_clear(first, 3.25, 1.8) or not nav.static_clear(last, 2.65, 1.8): continue
			if nav.segment_clear(sim, first, last, 3.25, 1.8, -1, false):
				source = first
				target = last
				break
	check(source.is_finite(), "open water approach fixture")
	if not source.is_finite(): return
	var ship: int = sim.debug_spawn(0, "sky_ship_signature", source)
	var enemy: int = sim.debug_spawn(1, "rivet_ship_frigate", target)
	check(ship > 0 and enemy > 0, "large ship pursuit fixture")
	if ship < 0 or enemy < 0: return
	var reach: float = float(sim.rules.weapons.sky_ship_signature.range)
	var goal: Vector2 = sim._combat_approach(sim.entities[ship], sim.entities[enemy].pos, reach)
	check(goal.is_finite() and nav.water_clear(sim, goal, 3.25, 1.8, ship, false) and goal.distance_to(target) + 3.25 * 0.35 < reach, "large ship approach is safe and within firing margin")
	var enemy_hp: float = float(sim.entities[enemy].hp)
	sim.issue([ship], "attack", sim.entities[enemy].pos, enemy)
	for tick in range(600):
		sim.step(0.05)
		if not sim.entities.has(enemy) or float(sim.entities[enemy].hp) < enemy_hp: break
	check(not sim.entities.has(enemy) or float(sim.entities[enemy].hp) < enemy_hp, "native large ship attacks after approaching from beyond range")

func _snapshot(sim) -> Dictionary:
	var path: String = "user://stage4_core_test.pfront"
	check(sim.save_game(path).is_empty(), "save fixture")
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_var(false)
