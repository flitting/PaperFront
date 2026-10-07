extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
const LegacyRivet = preload("res://tests/legacy_rivet_construction.gd")
const Construction = preload("res://scripts/outpost_construction.gd")
var config: Dictionary
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	config = Rules.load_rules("res://data/rules.json", false)
	if config.is_empty():
		push_error("Outpost rule fixture is invalid: " + str(Rules.errors))
		quit(1)
		return
	# This suite deliberately preserves outpost-era snapshot behavior.
	config = LegacyRivet.adapt(config)
	_test_site_selection_and_travel()
	_test_work_progress_and_cost()
	_test_appended_commands()
	_test_stopped_or_dead_builder()
	_test_takeover_and_dismantling()
	_test_damage_delays_construction()
	_test_insufficient_funds()
	_test_unpaid_final_balance()
	_test_ordinary_repair_and_capture()
	_test_pending_site_snapshots()
	_test_snapshot_determinism()
	print("Outpost construction checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _sim():
	var sim = Sim.new()
	sim.setup(config, "dev", 7, "rivet", false)
	sim.money.assign([100000.0, 100000.0])
	sim.debug_spawn(0, "rivet_power", Vector2(5.5, 40.5))
	return sim


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.001


func _tick(sim, seconds: float) -> void:
	var remaining: float = seconds
	while remaining > 0.000001:
		var delta: float = minf(1.0 / 30.0, remaining)
		sim.step(delta)
		remaining -= delta


func _scaffold(sim, engineer: int) -> int:
	var pos := Vector2(24.5, 43.5)
	_check(sim.build(0, "rivet_outpost", engineer).is_empty() and sim.place_building(0, pos).is_empty(), "fixture places a legal engineer outpost site without preconstruction")
	for tick: int in range(450):
		sim.step(1.0 / 30.0)
		for e: Dictionary in sim.entities.values():
			if e.kind == "building" and e.spec == "rivet_outpost" and (e.pos as Vector2).is_equal_approx(pos):
				return int(e.id)
	_check(false, "fixture engineer reaches the site and creates a real scaffold")
	return -1


func _fixture() -> Dictionary:
	var sim = _sim()
	var engineer: int = sim.debug_spawn(0, "rivet_engineer", Vector2(9.5, 43.5))
	var outpost: int = _scaffold(sim, engineer)
	return {"sim": sim, "engineer": engineer, "outpost": outpost}


func _progress_unchanged(building: Dictionary, before: Dictionary) -> bool:
	return _near(building.construction.progress, before.progress) and _near(building.construction.spent, before.spent)


func _damage(sim, id: int, amount: float) -> void:
	sim._add_damage(id, amount)
	sim._apply_damage()
	sim._damage.clear()


func _test_site_selection_and_travel() -> void:
	var sim = _sim()
	var engineer: int = sim.debug_spawn(0, "rivet_engineer", Vector2(9.5, 43.5))
	sim.money[0] = 0.0
	_check(sim.build(0, "rivet_outpost", engineer).is_empty(), "an engineer may choose an outpost site before receiving any construction funds")
	_check(sim.building_orders[0].ready and _near(sim.money[0], 0.0), "outpost selection is immediately ready and does not pay or start a build timer")
	var entity_count: int = sim.entities.size()
	_check(sim.place_building(0, Vector2(24.5, 43.5)).is_empty(), "free outpost site selection accepts legal remote land")
	_check(sim.entities.size() == entity_count and sim.entities[engineer].commands[0].kind == "deploy_outpost", "outpost placement sends its engineer without remotely creating the scaffold")
	_tick(sim, 1.0)
	_check(sim.entities.size() == entity_count and _near(sim.money[0], 0.0), "engineer travel spends no money and creates no building before arrival")
	var departed = _sim()
	engineer = departed.debug_spawn(0, "rivet_engineer", Vector2(9.5, 43.5))
	var money_before: float = departed.money[0]
	departed.build(0, "rivet_outpost", engineer)
	departed.place_building(0, Vector2(24.5, 43.5))
	departed._kill_entity(engineer, true)
	_tick(departed, 2.0)
	var scaffolds: int = 0
	for e: Dictionary in departed.entities.values():
		if departed.data_for(e.spec).get("role", "") == "outpost":
			scaffolds += 1
	_check(scaffolds == 0 and _near(departed.money[0], money_before), "a builder killed during travel leaves no remotely built or paid outpost")


func _test_work_progress_and_cost() -> void:
	var fixture: Dictionary = _fixture()
	var sim = fixture.sim
	var id: int = fixture.outpost
	if id < 0:
		return
	var e: Dictionary = sim.entities[id]
	var initial_hp: float = minf(50.0, float(config.buildings.rivet_outpost.hp) * 0.03)
	var cost: float = config.buildings.rivet_outpost.cost
	var duration: float = config.buildings.rivet_outpost.build_time
	var money_before: float = sim.money[0]
	_check(e.has("construction") and _near(e.hp, initial_hp) and _near(e.construct_remaining, duration), "arrival starts a low-health scaffold with the full field construction time remaining")
	_check(_near(e.construction.progress, 0.0) and _near(e.construction.spent, 0.0) and sim.entities[fixture.engineer].commands[0].kind == "resume_outpost", "a fresh scaffold has no prepaid work and retains its engineer on the construction order")
	_tick(sim, 1.0)
	_check(_near(e.construction.progress, 1.0 / duration) and _near(money_before - sim.money[0], cost / duration), "one second of real work advances and pays exactly one second of configured construction")
	_check(_near(e.hp, Construction.health_cap(sim, e)) and _near(e.construct_remaining, duration - 1.0), "scaffold health and remaining work follow actual paid construction progress")
	sim._kill_entity(1, true)
	_check(not sim._has_construction_base(0) and not sim.build(0, "rivet_power").is_empty(), "an unfinished scaffold cannot authorize normal construction after headquarters loss")
	_tick(sim, duration + 0.1)
	_check(not e.has("construction") and _near(e.hp, config.buildings.rivet_outpost.hp) and _near(e.construct_remaining, 0.0), "finishing construction restores the complete outpost health and clears scaffold state")
	_check(_near(money_before - sim.money[0], cost) and sim.entities.has(fixture.engineer) and sim.entities[fixture.engineer].commands.is_empty(), "full construction spends exactly the building cost and releases the surviving engineer")
	_tick(sim, 1.0)
	_check(_near(money_before - sim.money[0], cost), "completed outposts stop charging construction funds")


func _test_stopped_or_dead_builder() -> void:
	var fixture: Dictionary = _fixture()
	var sim = fixture.sim
	var id: int = fixture.outpost
	if id < 0:
		return
	_tick(sim, 2.0)
	var e: Dictionary = sim.entities[id]
	var before: Dictionary = e.construction.duplicate(true)
	var hp: float = e.hp
	var remaining: float = e.construct_remaining
	var funds: float = sim.money[0]
	sim.issue([fixture.engineer], "move", Vector2(12.5, 43.5))
	_tick(sim, 5.0)
	_check(_progress_unchanged(e, before) and _near(e.hp, hp) and _near(e.construct_remaining, remaining) and _near(sim.money[0], funds), "commanding the builder away pauses progress, health and spending instead of running an automatic timer")
	_check(e.construction.work_state == "paused" and Construction.status(sim, e).contains("停止"), "the abandoned scaffold exposes its paused work status")
	sim._kill_entity(fixture.engineer, true)
	_tick(sim, 2.0)
	_check(sim.entities.has(id) and _progress_unchanged(e, before) and _near(e.hp, hp) and _near(sim.money[0], funds), "builder death preserves the actual partially built scaffold and all paid progress")
	_check(Construction.status(sim, e).contains("接手"), "a dead builder leaves construction available for another engineer")


func _test_appended_commands() -> void:
	var fixture: Dictionary = _fixture()
	var sim = fixture.sim
	var id: int = fixture.outpost
	if id < 0:
		return
	var goal := Vector2(12.5, 43.5)
	sim.issue([fixture.engineer], "move", goal, -1, true)
	_check(sim.entities[fixture.engineer].commands.size() == 2, "the engineer may queue travel after its ongoing construction work")
	_tick(sim, float(config.buildings.rivet_outpost.build_time) + 0.1)
	var engineer: Dictionary = sim.entities[fixture.engineer]
	_check(not sim.entities[id].has("construction") and not engineer.commands.is_empty() and engineer.commands[0].kind == "move", "finishing field construction preserves and starts the appended movement order")
	_tick(sim, 5.0)
	_check(engineer.commands.is_empty() and (engineer.pos as Vector2).distance_to(goal) < 0.4, "the surviving engineer completes its originally queued movement destination")


func _test_takeover_and_dismantling() -> void:
	var fixture: Dictionary = _fixture()
	var sim = fixture.sim
	var id: int = fixture.outpost
	if id < 0:
		return
	_tick(sim, 2.0)
	var before: Dictionary = sim.entities[id].construction.duplicate(true)
	sim._kill_entity(fixture.engineer, true)
	var builder_before: int = sim.entities[id].construction.builder
	var hostile: int = sim.debug_spawn(1, "kestrel_engineer", Vector2(28.5, 43.5))
	var rifle: int = sim.debug_spawn(0, "rivet_rifle", Vector2(24.5, 46.5))
	_check(not Construction.resume_error(sim, hostile, id).is_empty() and not Construction.resume_error(sim, rifle, id).is_empty(), "only a friendly engineer may take over a scaffold")
	sim.issue([hostile, rifle], "resume_outpost", sim.entities[id].pos, id)
	_check(sim.entities[id].construction.builder == builder_before, "hostile engineers and ordinary infantry cannot claim the builder slot")
	var replacement: int = sim.debug_spawn(0, "rivet_engineer", Vector2(22.4, 43.5))
	sim.issue([replacement], "resume_outpost", sim.entities[id].pos, id)
	_tick(sim, 1.0)
	_check(sim.entities[id].construction.builder == replacement and sim.entities[id].construction.progress > float(before.progress), "a replacement engineer resumes the same already paid field construction")
	var funds: float = sim.money[0]
	var spent: float = sim.entities[id].construction.spent
	_check(spent > 0.0 and sim.dismantle_outpost(id).is_empty(), "a partially funded scaffold can be deliberately dismantled")
	_check(not sim.entities.has(id) and sim.entities.has(replacement) and _near(sim.money[0], funds), "dismantling destroys only the unfinished building and neither refunds spent funds nor collects the unpaid balance")
	_tick(sim, 1.0)
	_check(_near(sim.money[0], funds) and sim.entities[replacement].commands.is_empty(), "dismantling releases its engineer and cancels all future construction charges")
	_check(not sim.dismantle_outpost(1).is_empty(), "field dismantling cannot act as discounted selling for a completed building")


func _test_damage_delays_construction() -> void:
	var fixture: Dictionary = _fixture()
	var sim = fixture.sim
	var id: int = fixture.outpost
	if id < 0:
		return
	_tick(sim, 10.0)
	var e: Dictionary = sim.entities[id]
	var before: Dictionary = e.construction.duplicate(true)
	var cap: float = Construction.health_cap(sim, e)
	var rate: float = config.units.rivet_engineer.repair_rate
	var damage: float = rate * 4.0
	_damage(sim, id, damage)
	var funds: float = sim.money[0]
	_tick(sim, 2.0)
	_check(_progress_unchanged(e, before) and _near(e.hp, cap - damage + rate * 2.0), "a damaged scaffold spends engineer work time on repair before new construction")
	_check(_near(funds - sim.money[0], rate * 2.0 * float(config.economy.repair_cost)) and _near(e.construction.repair_spent, rate * 2.0 * float(config.economy.repair_cost)), "scaffold repair charges the existing per-health repair cost separately from the building budget")
	_tick(sim, 2.0)
	_check(_progress_unchanged(e, before) and _near(e.hp, cap), "the entire damage repair interval delays construction until the paid health limit is restored")
	_tick(sim, 1.0)
	_check(e.construction.progress > float(before.progress) and _near(e.hp, Construction.health_cap(sim, e)), "construction resumes after damage repair and increases health only with newly built progress")
	_tick(sim, float(config.buildings.rivet_outpost.build_time))
	var expected: float = float(config.buildings.rivet_outpost.cost) * (1.0 - float(before.progress)) + damage * float(config.economy.repair_cost)
	_check(not e.has("construction") and _near(funds - sim.money[0], expected), "damage adds only actual repair expense while total construction spending stays at the configured cost")


func _test_insufficient_funds() -> void:
	var fixture: Dictionary = _fixture()
	var sim = fixture.sim
	var id: int = fixture.outpost
	if id < 0:
		return
	var e: Dictionary = sim.entities[id]
	var before: Dictionary = e.construction.duplicate(true)
	sim.money[0] = 0.0
	_tick(sim, 2.0)
	_check(_progress_unchanged(e, before) and _near(e.hp, e.construction.initial_hp) and e.construction.work_state == "paused", "a scaffold with no funds waits without receiving free work or health")
	var cost: float = config.buildings.rivet_outpost.cost
	var duration: float = config.buildings.rivet_outpost.build_time
	sim.money[0] = cost * 0.1
	_tick(sim, duration * 0.2)
	_check(_near(e.construction.progress, 0.1) and _near(e.construction.spent, cost * 0.1) and _near(sim.money[0], 0.0), "partial funds pay only the affordable construction fraction and never create negative money")
	var cap: float = Construction.health_cap(sim, e)
	_damage(sim, id, 8.0)
	before = e.construction.duplicate(true)
	_tick(sim, 1.0)
	_check(_progress_unchanged(e, before) and _near(e.hp, cap - 8.0) and _near(e.construction.repair_spent, 0.0), "damage repair also pauses without funds and cannot bypass unfinished work")
	sim.money[0] = 8.0 * float(config.economy.repair_cost)
	_tick(sim, 1.0)
	_check(_progress_unchanged(e, before) and _near(e.hp, cap) and _near(sim.money[0], 0.0), "repair-only funds restore the existing scaffold health but buy no new construction")
	sim.money[0] = cost * 0.9
	_tick(sim, duration + 0.1)
	_check(not e.has("construction") and _near(sim.money[0], 0.0), "resupplying the exact unpaid construction balance finishes the existing scaffold without an extra charge")


func _test_ordinary_repair_and_capture() -> void:
	var fixture: Dictionary = _fixture()
	var sim = fixture.sim
	var id: int = fixture.outpost
	if id < 0:
		return
	_tick(sim, 3.0)
	_damage(sim, id, 8.0)
	var hp: float = sim.entities[id].hp
	var funds: float = sim.money[0]
	sim.issue([fixture.engineer], "stop", sim.entities[fixture.engineer].pos)
	sim.toggle_repair(id)
	_tick(sim, 1.0)
	_check(_near(sim.entities[id].hp, hp) and _near(sim.money[0], funds), "the ordinary building self-repair toggle cannot repair an unattended scaffold")
	sim.issue([fixture.engineer], "repair", sim.entities[id].pos, id)
	_tick(sim, 0.1)
	_check(sim.entities[id].has("construction") and float(sim.entities[id].hp) < float(config.buildings.rivet_outpost.hp), "the engineer's ordinary instant repair cannot turn a scaffold into a full-health completed outpost")
	var hostile: int = sim.debug_spawn(1, "kestrel_engineer", Vector2(28.5, 43.5))
	_check(not sim.capture_error(hostile, id).is_empty(), "unfinished field construction cannot be captured")
	sim.issue([hostile], "capture", sim.entities[id].pos, id)
	_tick(sim, 0.1)
	_check(sim.entities[id].team == 0 and sim.entities[hostile].commands.is_empty(), "enemy engineer capture cannot take over or resume a friendly scaffold")


func _test_unpaid_final_balance() -> void:
	var fixture: Dictionary = _fixture()
	var sim = fixture.sim
	var id: int = fixture.outpost
	if id < 0:
		return
	var cost: float = config.buildings.rivet_outpost.cost
	var unpaid: float = 0.0001
	sim.money[0] = cost - unpaid
	_tick(sim, float(config.buildings.rivet_outpost.build_time) + 1.0)
	_check(sim.entities[id].has("construction") and _near(sim.money[0], 0.0), "an almost complete scaffold still requires its genuine unpaid final construction balance")
	if not sim.entities[id].has("construction"):
		return
	_check(absf(float(sim.entities[id].construction.spent) - (cost - unpaid)) < 0.00001, "construction ledger does not replace a small real funding deficit with a rounding correction")
	sim.money[0] = unpaid
	_tick(sim, 0.1)
	_check(not sim.entities[id].has("construction") and absf(float(sim.money[0])) < 0.00001, "supplying the exact tiny final balance finishes without a floating-point stall or another charge")


func _test_snapshot_determinism() -> void:
	var path: String = "/tmp/paper_front_outpost_construction.save"
	for state: String in ["working", "repairing", "dead_builder"]:
		var fixture: Dictionary = _fixture()
		var sim = fixture.sim
		var id: int = fixture.outpost
		if id < 0:
			continue
		_tick(sim, 3.0)
		if state == "repairing":
			_damage(sim, id, 16.0)
			_tick(sim, 0.25)
		elif state == "dead_builder":
			sim._kill_entity(fixture.engineer, true)
			_tick(sim, 0.1)
		_check(sim.save_game(path).is_empty(), state + " scaffold snapshot writes")
		var restored = Sim.new()
		var error: String = restored.load_game(path)
		_check(error.is_empty() and restored.entities == sim.entities and restored.money == sim.money, state + " construction progress, expense and engineer state survive save/load: " + error)
		if not error.is_empty():
			continue
		_tick(sim, 4.0)
		_tick(restored, 4.0)
		_check(restored.entities == sim.entities and restored.money == sim.money, state + " scaffold advances identically after restoring its snapshot")
	DirAccess.remove_absolute(path)


func _test_pending_site_snapshots() -> void:
	var path: String = "/tmp/paper_front_outpost_site.save"
	for state: String in ["site_selection", "travelling"]:
		var sim = _sim()
		var engineer: int = sim.debug_spawn(0, "rivet_engineer", Vector2(9.5, 43.5))
		sim.build(0, "rivet_outpost", engineer)
		if state == "travelling":
			sim.place_building(0, Vector2(24.5, 43.5))
			_tick(sim, 0.5)
		_check(sim.save_game(path).is_empty(), state + " free outpost order snapshot writes")
		var restored = Sim.new()
		var error: String = restored.load_game(path)
		_check(error.is_empty() and restored.building_orders == sim.building_orders and restored.entities == sim.entities and restored.money == sim.money, state + " order restores without introducing prepaid construction: " + error)
		if not error.is_empty():
			continue
		_tick(sim, 1.0)
		_tick(restored, 1.0)
		_check(restored.entities == sim.entities and restored.building_orders == sim.building_orders and restored.money == sim.money, state + " order advances identically after restoring the snapshot")
	DirAccess.remove_absolute(path)
