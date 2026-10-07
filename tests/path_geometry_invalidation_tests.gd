extends SceneTree

const Sim = preload("res://scripts/simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
const STEP: float = 1.0 / 30.0
var config: Dictionary
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	config = Rules.load_rules()
	if config.is_empty():
		push_error("Geometry invalidation fixture requires valid gameplay rules")
		quit(1)
		return
	_test_local_building_changes()
	_test_bridge_changes()
	_test_unknown_change()
	print("PATH_GEOMETRY_INVALIDATION ", checks - failures.size(), "/", checks)
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)


func _fixture(with_bridge: bool = false):
	var sim = Sim.new()
	# Use the real asynchronous planner, with script movement to isolate this
	# scheduling contract from independently changing native collision code.
	sim.native_kernels_enabled = false
	sim.native_unit_dispatch_enabled = false
	sim.native_geometry_enabled = false
	sim.native_movement_enabled = false
	sim.setup(config.duplicate(true), "dev", 7, "rivet", false)
	for z: int in range(48):
		for x: int in range(48):
			sim.map.terrain[z][x] = 0
			sim.map.heights[z][x] = 0.0
	sim.mines.clear()
	sim.bridges.clear()
	sim.ruins.clear()
	sim._refresh_ruin_spatial()
	for id: int in sim.entities.keys(): sim._kill_entity(id, false)
	sim.debug_spawn(0, "rivet_hq", Vector2(5, 43))
	sim.debug_spawn(1, "kestrel_hq", Vector2(43, 43))
	if with_bridge:
		for z: int in range(48):
			for x: int in range(22, 26): sim.map.terrain[z][x] = 1
		sim.bridges.append({"id": 0, "bounds": [22, 11, 4, 3], "heads": [[21, 12.5], [26, 12.5]], "alive": true, "hp": float(config.economy.bridge_hp), "repair_progress": 1.0})
	sim._prepare_terrain_cache()
	sim._nav_initialized = false
	sim._rebuild_nav()
	sim._rebuild_spatial()
	_check(not sim.synchronous_path_tests and sim._path_worker != null, "fixture starts the real asynchronous path worker")
	return sim


func _move(sim, start: Vector2, goal: Vector2) -> int:
	var id: int = sim.debug_spawn(0, "rivet_engineer", start)
	if id >= 0:
		sim.entities[id].cooldown = 10000.0
		sim.issue([id], "move", goal)
	return id


func _tick(sim) -> void:
	sim.step(STEP)
	sim.events.clear()
	OS.delay_usec(1000)


func _await_paths(sim, ids: Array) -> bool:
	for tick: int in range(2000):
		_tick(sim)
		if ids.all(func(id): return sim.entities.has(id) and not sim.entities[id].path.is_empty()): return true
	return false


func _damage(sim, id: int) -> void:
	sim._add_damage(id, 1000000.0)
	sim._apply_damage()
	sim._damage.clear()


func _close(sim) -> void:
	if sim._path_worker != null: sim._path_worker.close()


func _test_local_building_changes() -> void:
	var sim = _fixture()
	var mover: int = _move(sim, Vector2(6.5, 12.5), Vector2(30.5, 12.5))
	var ready: bool = mover >= 0 and _await_paths(sim, [mover])
	_check(ready, "worker produces a usable path before local building edits")
	if not ready:
		_close(sim)
		return
	var e: Dictionary = sim.entities[mover]
	var path: Array = e.path.duplicate()
	var goal: Vector2 = e.path_goal
	var commands: Array = e.commands.duplicate(true)
	var submitted: int = int(sim.navigation_stats.submitted)
	var remote: int = sim.debug_spawn(1, "kestrel_power", Vector2(35.5, 35.5))
	_check(remote >= 0 and not sim._path_crosses_changed_region(e), "remote building footprint does not intersect the current path")
	var revision: int = sim._path_revision
	_tick(sim)
	_check(sim._path_revision > revision and e.path == path and e.path_goal == goal and e.commands == commands, "real asynchronous geometry publication preserves the unaffected route and order")
	_check(int(sim.navigation_stats.submitted) == submitted, "remote construction does not submit a replacement route")
	_damage(sim, remote)
	_check(not sim._nav_regions.is_empty() and not sim._path_crosses_changed_region(e), "building destruction publishes its actual remote footprint")
	_tick(sim)
	_check(e.path == path and e.path_goal == goal and int(sim.navigation_stats.submitted) == submitted, "remote building destruction preserves the worker route without replanning")
	var blocking: int = sim.debug_spawn(0, "rivet_power", Vector2(15.5, 12.5))
	_check(blocking >= 0 and sim._path_crosses_changed_region(e), "new building footprint intersects the existing route")
	_tick(sim)
	_check(e.path.is_empty() and e.path_goal == Vector2.INF and e.commands == commands, "intersecting construction invalidates the route while preserving the original order")
	_close(sim)


func _test_bridge_changes() -> void:
	var sim = _fixture(true)
	var crossing: int = _move(sim, Vector2(10.5, 12.5), Vector2(34.5, 12.5))
	var remote: int = _move(sim, Vector2(10.5, 35.5), Vector2(18.5, 35.5))
	var ready: bool = crossing >= 0 and remote >= 0 and _await_paths(sim, [crossing, remote])
	_check(ready, "worker produces both a real bridge crossing and an unrelated shore route")
	if not ready:
		_close(sim)
		return
	var e: Dictionary = sim.entities[crossing]
	var other: Dictionary = sim.entities[remote]
	var commands: Array = e.commands.duplicate(true)
	var remote_path: Array = other.path.duplicate()
	_damage(sim, Sim.BRIDGE_TARGET_BASE)
	_check(not sim.bridges[0].alive and sim._path_crosses_changed_region(e) and not sim._path_crosses_changed_region(other), "bridge destruction marks only the crossing footprint")
	_tick(sim)
	_check(e.path.is_empty() and e.commands == commands, "destroyed bridge invalidates its crossing route and retains the movement command")
	_check(other.path == remote_path, "bridge destruction preserves the unrelated shore route")
	var engineer: int = sim.debug_spawn(0, "rivet_engineer", Vector2(21, 12.5))
	sim.money[0] = 100000.0
	sim.bridges[0].repair_progress = 0.9999
	sim.issue([engineer], "repair_bridge", Vector2(24, 12.5), Sim.BRIDGE_TARGET_BASE)
	_tick(sim)
	_check(sim.bridges[0].alive and sim._nav_regions.has(Rect2(22, 11, 4, 3)), "real bridge repair publishes its exact reopened footprint")
	_tick(sim)
	_check(other.path == remote_path, "bridge repair also preserves the unrelated shore route")
	_close(sim)


func _test_unknown_change() -> void:
	var sim = _fixture()
	var mover: int = _move(sim, Vector2(6.5, 20.5), Vector2(30.5, 20.5))
	var ready: bool = mover >= 0 and _await_paths(sim, [mover])
	_check(ready, "unknown-change fixture receives a real worker route")
	if not ready:
		_close(sim)
		return
	var e: Dictionary = sim.entities[mover]
	var commands: Array = e.commands.duplicate(true)
	sim._nav_regions.clear()
	sim._nav_dirty = true
	_tick(sim)
	_check(e.path.is_empty() and e.path_goal == Vector2.INF and e.commands == commands, "an edit with unknown bounds conservatively invalidates routes while retaining orders")
	_close(sim)
