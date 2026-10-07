extends SceneTree

const Rules = preload("res://scripts/rules_loader.gd")
const STEP: float = 1.0 / 30.0

class CountingSimulation:
	extends "res://tests/rule_test_simulation.gd"
	var script_entity_ticks: int = 0
	var reference_ground_moves: int = 0

	func _step_entities_script(delta: float, multipliers: Array[float]) -> void:
		script_entity_ticks += 1
		super._step_entities_script(delta, multipliers)

	func _move_ground_reference(e: Dictionary, goal: Vector2, delta: float) -> bool:
		reference_ground_moves += 1
		return super._move_ground_reference(e, goal, delta)

var checks: int = 0
var failures: Array[String] = []
var rules: Dictionary


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)


func _fixture(native_backend: bool):
	var sim = CountingSimulation.new()
	sim.native_kernels_enabled = native_backend
	sim.native_unit_dispatch_enabled = native_backend
	sim.native_geometry_enabled = native_backend
	sim.native_movement_enabled = native_backend
	sim.setup_multiteam(rules.duplicate(true), "dev", 719, ["iron", "iron"], false, [Vector2(6, 43), Vector2(42, 43)])
	for id: int in sim.entities.keys():
		sim._kill_entity(id, false)
	for z: int in range(int(sim.map.size)):
		for x: int in range(int(sim.map.size)):
			sim.map.terrain[z][x] = 0
			sim.map.heights[z][x] = 0.0
	sim.mines.clear()
	sim.bridges.clear()
	sim.ruins.clear()
	sim._refresh_ruin_spatial()
	sim._refresh_mine_spatial()
	sim._spawn(0, "iron_hq", Vector2(6, 43), true)
	sim._spawn(1, "iron_hq", Vector2(42, 43), true)
	sim._prepare_terrain_cache()
	sim._nav_initialized = false
	sim.events.clear()
	return sim


func _track(sim, team: int = 0, y: float = 20.5) -> void:
	for x: int in range(10, 37):
		sim._spawn(team, "iron_rail", Vector2(float(x) + 0.5, y), true)
	sim._rail_network.rebuild(sim)


func _unit(sim, spec: String, pos: Vector2, team: int = 0) -> int:
	var id: int = sim._spawn(team, spec, pos, true)
	sim.entities[id].alpha = 0.0
	sim.entities[id].turret_alpha = 0.0
	# Isolate traffic and crushing from weapon damage without changing rules/HP.
	sim.entities[id].cooldown = 1000.0
	return id


func _prepare(sim) -> void:
	sim._rebuild_nav()
	sim._rebuild_spatial()
	sim.events.clear()
	_check(not sim.ProductionLifecycle.active(sim) and not sim.RefineryDocking.active(sim) and not sim.GarrisonOperations.active(sim) and not sim.Veterancy.active(sim), "rail fixture has no lifecycle fallback")


func _dispatch_checked(sim, native_backend: bool, label: String) -> void:
	_check(sim.script_entity_ticks == 0 if native_backend else sim.script_entity_ticks > 0, label + " uses its requested complete entity-tick backend")
	_check(sim.result.is_empty(), label + " keeps an active match")


func _close(sim) -> void:
	if sim._path_worker != null:
		sim._path_worker.close()


func _test_double_speed(native_backend: bool, spec: String) -> void:
	var sim = _fixture(native_backend)
	_track(sim)
	var origin := Vector2(12.5, 20.5)
	var id: int = _unit(sim, spec, origin)
	_prepare(sim)
	sim.issue([id], "move", Vector2(34.5, 20.5))
	var speed: float = float(sim.data_for(spec).speed)
	var label: String = "%s full tick native=%s" % [spec, native_backend]
	for tick: int in range(6):
		sim.step(STEP)
		var expected: Vector2 = origin + Vector2.RIGHT * speed * 2.0 * STEP * float(tick + 1)
		_check((sim.entities[id].pos as Vector2).distance_to(expected) < 0.0002, label + " starts immediately and preserves exact 2x rail travel tick=" + str(tick))
		_check(not sim._rail_network.at(0, sim.entities[id].pos).is_empty(), label + " remains on owned track")
	_check(sim.entities[id].path.is_empty() and not sim._planning_queue.has(id), label + " does not enter the ordinary AStar queue")
	_dispatch_checked(sim, native_backend, label)
	_close(sim)


func _test_track_loss(native_backend: bool) -> void:
	var sim = _fixture(native_backend)
	_track(sim)
	var id: int = _unit(sim, "iron_train", Vector2(12.5, 20.5))
	_prepare(sim)
	sim.issue([id], "move", Vector2(34.5, 20.5))
	sim.step(STEP)
	var stopped: Vector2 = sim.entities[id].pos
	var cut: Dictionary = sim._rail_network.cells[Vector2i(20, 20)]
	sim._kill_entity(int(cut.id), true)
	for _tick: int in range(9):
		sim.step(STEP)
	_check((sim.entities[id].pos as Vector2).is_equal_approx(stopped) and sim.entities[id].state == "waiting_rail", "broken cached rail route waits without leaving track native=" + str(native_backend))
	_check(not sim.entities[id].commands.is_empty(), "broken track retains the original command native=" + str(native_backend))
	# The authoritative mover must reject a plain-ground command even if a caller
	# bypasses issue()'s destination validation (as restored/queued commands can).
	sim.entities[id].commands = [{"kind": "move", "pos": Vector2(16.5, 24.5), "target": -1}]
	sim.step(STEP)
	_check((sim.entities[id].pos as Vector2).is_equal_approx(stopped), "rail-only mover rejects plain ground after a complete tick native=" + str(native_backend))
	_dispatch_checked(sim, native_backend, "track loss native=" + str(native_backend))
	_close(sim)


func _test_enemy_track(native_backend: bool) -> void:
	var sim = _fixture(native_backend)
	_track(sim, 1)
	var origin := Vector2(12.5, 20.5)
	var id: int = _unit(sim, "iron_rifle", origin)
	_prepare(sim)
	sim.issue([id], "move", Vector2(34.5, 20.5))
	for _tick: int in range(6):
		sim.step(STEP)
	var expected: Vector2 = origin + Vector2.RIGHT * float(sim.data_for("iron_rifle").speed) * STEP * 6.0
	_check((sim.entities[id].pos as Vector2).distance_to(expected) < 0.0002, "enemy-owned track gives ordinary infantry no speed bonus native=" + str(native_backend))
	_check(sim.reference_ground_moves == 0 if native_backend else sim.reference_ground_moves > 0, "enemy track uses the ordinary movement backend native=" + str(native_backend))
	var train: int = _unit(sim, "iron_train", Vector2(16.5, 20.5))
	var stopped: Vector2 = sim.entities[train].pos
	sim.entities[train].commands = [{"kind": "move", "pos": Vector2(34.5, 20.5), "target": -1}]
	sim.step(STEP)
	_check((sim.entities[train].pos as Vector2).is_equal_approx(stopped) and sim.entities[train].state == "waiting_rail", "rail-only train cannot borrow enemy-owned track native=" + str(native_backend))
	_dispatch_checked(sim, native_backend, "enemy track native=" + str(native_backend))
	_close(sim)


func _test_overlap_and_crushing(native_backend: bool) -> void:
	var sim = _fixture(native_backend)
	_track(sim)
	var origin := Vector2(12.5, 20.5)
	var first: int = _unit(sim, "iron_train", origin)
	var second: int = _unit(sim, "iron_train", origin)
	_prepare(sim)
	sim.issue([first, second], "move", Vector2(34.5, 20.5))
	for _tick: int in range(6):
		sim.step(STEP)
	_check((sim.entities[first].pos as Vector2).distance_to(sim.entities[second].pos) < 0.0002 and (sim.entities[first].pos as Vector2).distance_to(origin) > 0.5, "overlapping trains both advance through complete ticks native=" + str(native_backend))
	_dispatch_checked(sim, native_backend, "overlapping trains native=" + str(native_backend))
	_close(sim)

	var crush_sim = _fixture(native_backend)
	_track(crush_sim)
	var tank: int = _unit(crush_sim, "iron_tank", origin)
	var infantry: int = _unit(crush_sim, "iron_rifle", origin + Vector2.RIGHT, 1)
	_prepare(crush_sim)
	_check(crush_sim._can_crush_target(crush_sim.entities[tank], crush_sim.entities[infantry]), "rail crushing control uses a normally crushable enemy native=" + str(native_backend))
	var initial_hp: float = float(crush_sim.entities[infantry].hp)
	crush_sim.issue([tank], "move", Vector2(34.5, 20.5))
	for _tick: int in range(9):
		crush_sim.step(STEP)
	_check((crush_sim.entities[tank].pos as Vector2).distance_to(origin) > 1.0, "tank really traverses enemy infantry's position on rail native=" + str(native_backend))
	_check(crush_sim.entities.has(infantry) and float(crush_sim.entities[infantry].hp) == initial_hp, "rail movement does not crush overlapping enemy infantry native=" + str(native_backend))
	_dispatch_checked(crush_sim, native_backend, "rail crushing native=" + str(native_backend))
	_close(crush_sim)


func _difference(a: Variant, b: Variant, path: String) -> String:
	if a == b:
		return ""
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return path + " dictionary size"
		for key in a:
			if not b.has(key): return path + " missing " + str(key)
			var nested: String = _difference(a[key], b[key], path + "." + str(key))
			if not nested.is_empty(): return nested
	elif a is Array and b is Array:
		if a.size() != b.size(): return path + " array size"
		for index: int in range(a.size()):
			var nested: String = _difference(a[index], b[index], path + "[" + str(index) + "]")
			if not nested.is_empty(): return nested
	return path + ": " + str(a) + " != " + str(b)


func _test_route_cache_safety() -> void:
	var sim = _fixture(false)
	_track(sim)
	var origin := Vector2(12.5, 20.5)
	var goal := Vector2(34.5, 20.5)
	var id: int = _unit(sim, "iron_rifle", origin)
	_prepare(sim)
	var first: Array = sim._rail_network.traversable_path(sim, sim.entities[id], origin, goal)
	_check(not first.is_empty(), "shared rail cache starts with a physically valid route")
	first.clear()
	var second: Array = sim._rail_network.traversable_path(sim, sim.entities[id], origin, goal)
	_check(not second.is_empty() and second.back() == goal, "consuming one returned rail route cannot mutate a shared cached route")
	# The source cell center clears this corner, but another point in the same
	# cell intersects it. Cell-keyed validation must not cover that real connector.
	sim.ruins.append({"id": 0, "kind": "wall", "pos": Vector2(12.0, 20.0), "half": Vector2(.05, .05), "hp": 100.0, "max_hp": 100.0})
	sim._refresh_ruin_spatial()
	sim._mark_nav_region(Rect2(11.95, 19.95, .1, .1))
	_check(not sim._rail_network.traversable_path(sim, sim.entities[id], origin, goal).is_empty(), "center route remains legal beside a small corner obstacle")
	_check(sim._rail_network.traversable_path(sim, sim.entities[id], Vector2(12.1, 20.1), goal).is_empty(), "shared cell route always rechecks its actual subcell start connector")
	sim.ruins.append({"id": 1, "kind": "wall", "pos": Vector2(22.5, 20.5), "half": Vector2(.5, .5), "hp": 100.0, "max_hp": 100.0})
	sim._refresh_ruin_spatial()
	sim._mark_nav_region(Rect2(22, 20, 1, 1))
	_check(sim._rail_network.traversable_path(sim, sim.entities[id], origin, goal).is_empty(), "geometry revision invalidates a previously legal shared rail chain")
	sim.ruins[1].hp = 0.0
	sim._mark_nav_region(Rect2(22, 20, 1, 1))
	_check(not sim._rail_network.traversable_path(sim, sim.entities[id], origin, goal).is_empty(), "clearing geometry invalidates a cached blocked rail chain")
	_close(sim)


func _test_off_rail_equivalence() -> void:
	var fast = _fixture(true)
	var reference = _fixture(false)
	var ids: Array[int] = []
	for sim in [fast, reference]:
		_track(sim, 0, 30.5)
		var id: int = _unit(sim, "iron_tank", Vector2(12.5, 10.5))
		ids.append(id)
		_prepare(sim)
		sim.issue([id], "move", Vector2(34.5, 10.5))
	for tick: int in range(60):
		fast.step(STEP)
		reference.step(STEP)
		for field: String in ["entities", "projectiles", "events", "money", "time", "result"]:
			var mismatch: String = _difference(fast.get(field), reference.get(field), field)
			_check(mismatch.is_empty(), "remote rail complete tick equivalence tick=%d %s" % [tick, mismatch])
		fast.events.clear()
		reference.events.clear()
	_check(fast.reference_ground_moves == 0 and reference.reference_ground_moves > 0, "remote rail leaves ordinary off-rail ground movement on native backend")
	_check((fast.entities[ids[0]].pos as Vector2).x > 17.0, "remote-rail equivalence advances an actual moving ground unit")
	_dispatch_checked(fast, true, "remote rail native")
	_dispatch_checked(reference, false, "remote rail script")
	_close(fast)
	_close(reference)


func _run() -> void:
	rules = Rules.load_rules()
	_check(not rules.is_empty(), "rail regressions load real gameplay rules")
	_check(ClassDB.class_exists("PaperFrontKernels"), "rail regressions require the actual native kernel")
	if not rules.is_empty() and ClassDB.class_exists("PaperFrontKernels"):
		for native_backend: bool in [false, true]:
			for spec: String in ["iron_train", "iron_rifle", "iron_tank"]:
				_test_double_speed(native_backend, spec)
			_test_track_loss(native_backend)
			_test_enemy_track(native_backend)
			_test_overlap_and_crushing(native_backend)
		_test_route_cache_safety()
		_test_off_rail_equivalence()
	print("RESPONSIVE_RAIL_NAVIGATION ", JSON.stringify({"checks": checks, "failures": failures}))
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
