extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
const STEP: float = 1.0 / 30.0
var config: Dictionary
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	config = Rules.load_rules()
	if config.is_empty():
		push_error("Navigation fixture rules are invalid: " + str(Rules.errors))
		quit(1)
		return
	_test_warm_masks_and_local_changes()
	_test_flat_segment_equivalence()
	_test_dynamic_tree_corners()
	_test_expired_detour_at_water_bank()
	_test_neighbor_cache_mutations()
	_test_bridge_batching_and_live_systems()
	_test_pending_navigation_save()
	_test_queue_cleanup()
	_test_candidate_search_progress()
	_test_planner_fairness()
	print("Navigation checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _new_sim():
	var sim = Sim.new()
	sim.setup(config, "dev", 7, "rivet", false)
	return sim


func _all_masks_warm(sim) -> bool:
	for info: Dictionary in config.units.values():
		if str(info.get("domain", "ground")) != "ground":
			continue
		if not sim._terrain_masks.has(snappedf(float(info.radius), 0.01)):
			return false
	return true


func _damage(sim, target: int, amount: float) -> void:
	sim._add_damage(target, amount)
	sim._apply_damage()
	sim._damage.clear()
	sim._check_result()


func _prepare_command_paths(sim, ids: Array) -> bool:
	var ready: bool = true
	for id: int in ids:
		var e: Dictionary = sim.entities[id]
		if e.commands.is_empty():
			ready = false
			continue
		var goal: Vector2 = e.commands[0].pos
		e.path = sim._path_between(e.pos, goal, float(e.radius), id)
		e.path_goal = goal
		ready = ready and not e.path.is_empty()
	return ready


func _test_warm_masks_and_local_changes() -> void:
	var sim = _new_sim()
	_check(_all_masks_warm(sim), "setup warms terrain masks for every configured ground unit radius")
	var mover: int = sim.debug_spawn(0, "rivet_engineer", Vector2(6.5, 43.5))
	sim.issue([mover], "move", Vector2(18.5, 43.5))
	_check(_prepare_command_paths(sim, [mover]), "local-change fixture has a real path before changing buildings")
	var original_path: Array = sim.entities[mover].path.duplicate()
	var original_command: Array = sim.entities[mover].commands.duplicate(true)
	var remote_building: int = sim.debug_spawn(1, "kestrel_power", Vector2(36.5, 41.5))
	sim._rebuild_nav()
	_check(sim.entities[mover].path == original_path and sim.entities[mover].commands == original_command, "an unrelated new building preserves the existing path and command")
	_damage(sim, remote_building, 100000.0)
	sim._rebuild_nav()
	_check(sim.entities[mover].path == original_path, "removing an unrelated building also preserves the existing path")
	var blocking_building: int = sim.debug_spawn(0, "rivet_power", Vector2(12.5, 43.5))
	sim._rebuild_nav()
	_check(sim.entities[mover].path.is_empty() and sim.entities[mover].commands == original_command, "a building intersecting the path invalidates that path without dropping its command")
	_damage(sim, blocking_building, 100000.0)


func _bridge_fixture(live_systems: bool = false, army_spec: String = "rivet_engineer", command_kind: String = "move") -> Dictionary:
	var sim = _new_sim()
	var army: Array[int] = []
	for z: float in [28.5, 30.0, 31.5]:
		for x: float in [16.5, 18.0, 19.5]:
			army.append(sim.debug_spawn(0, army_spec, Vector2(x, z)))
	sim.issue(army, command_kind, Vector2(33.0, 30.5))
	var paths_ready: bool = _prepare_command_paths(sim, army)
	var deck: Array[int] = [sim.debug_spawn(0, "rivet_engineer", Vector2(23.0, 29.5)), sim.debug_spawn(1, "kestrel_engineer", Vector2(25.0, 30.5))]
	var fixture: Dictionary = {"sim": sim, "army": army, "deck": deck, "paths_ready": paths_ready}
	if live_systems:
		var harvester: int = sim.debug_spawn(0, "rivet_harvester", sim.mines[0].pos)
		sim.entities[harvester].harvest_mine = 0
		sim.mines[0].amount = 123.0
		var attacker: int = sim.debug_spawn(0, "rivet_rifle", Vector2(6.5, 43.5))
		var target: int = sim.debug_spawn(1, "kestrel_engineer", Vector2(10.5, 43.5))
		sim.entities[attacker].alpha = 0.0
		sim.issue([attacker], "attack", sim.entities[target].pos, target)
		fixture.harvester = harvester
		fixture.attacker = attacker
		fixture.target = target
		fixture.build_error = sim.build(0, "rivet_power")
	var bridge: Dictionary = sim.bridges[0]
	_damage(sim, Sim.BRIDGE_TARGET_BASE - int(bridge.id), float(config.economy.bridge_hp))
	return fixture


func _army_on_land(sim, ids: Array) -> bool:
	for id: int in ids:
		if not sim.entities.has(id) or MapData.terrain_at(sim.map, sim.entities[id].pos) == MapData.WATER:
			return false
	return true


func _record_arrivals(sim, ids: Array, goals: Dictionary, arrived: Dictionary) -> void:
	for id: int in ids:
		if sim.entities.has(id) and (sim.entities[id].pos as Vector2).distance_to(goals[id]) <= 0.4 and sim.entities[id].commands.is_empty():
			arrived[id] = true


func _goals(sim, ids: Array) -> Dictionary:
	var answer: Dictionary = {}
	for id: int in ids:
		answer[id] = sim.entities[id].commands[0].pos
	return answer


func _route_until_arrival(sim, ids: Array, goals: Dictionary, limit: float = 120.0) -> Dictionary:
	var stayed_dry: bool = _army_on_land(sim, ids)
	var budget_bounded: bool = true
	var route_planned: Dictionary = {}
	var arrived: Dictionary = {}
	_record_arrivals(sim, ids, goals, arrived)
	var elapsed: float = 0.0
	while elapsed < limit and arrived.size() < ids.size():
		sim.step(STEP)
		elapsed += STEP
		stayed_dry = stayed_dry and _army_on_land(sim, ids)
		budget_bounded = budget_bounded and sim._path_plans_remaining >= 0 and sim._path_plans_remaining <= Sim.PATH_PLANS_PER_TICK
		# Completed units can subsequently yield to allies still arriving. Record
		# each actual completion when it happens rather than requiring all nine
		# units to remain on their original formation spots simultaneously.
		_record_arrivals(sim, ids, goals, arrived)
		for id: int in ids:
			if sim.entities.has(id) and not sim.entities[id].path.is_empty():
				route_planned[id] = true
	return {"dry": stayed_dry, "bounded": budget_bounded, "planned": route_planned.size(), "arrived": arrived.size() == ids.size(), "elapsed": elapsed}


func _test_bridge_batching_and_live_systems() -> void:
	var fixture: Dictionary = _bridge_fixture(true)
	var sim = fixture.sim
	var army: Array = fixture.army
	var goals: Dictionary = _goals(sim, army)
	_check(bool(fixture.paths_ready) and army.size() > Sim.PATH_PLANS_PER_TICK, "bridge fixture has more real crossing paths than one tick can replan")
	var deck_removed: bool = true
	for id: int in fixture.deck:
		deck_removed = deck_removed and not sim.entities.has(id)
	_check(deck_removed and not bool(sim.bridges[0].alive), "bridge damage immediately kills both teams on the deck")
	_check(_army_on_land(sim, army) and sim._nav_dirty and not sim._nav_regions.is_empty(), "shore units survive with the destroyed bridge region pending refresh")
	var all_affected: bool = true
	for id: int in army:
		all_affected = all_affected and sim._path_crosses_changed_region(sim.entities[id])
	_check(all_affected, "every pre-destruction route actually crosses the changed bridge region")
	_check(str(fixture.build_error) == "", "a real paid building order is active while navigation is queued")
	var remaining: float = sim.building_orders[0].remaining
	var hp: float = sim.entities[fixture.target].hp
	sim.step(STEP)
	_check(sim._path_plans_remaining == 0 and not sim._planning_deferred_ids.is_empty(), "the first refresh tick bounds planning work and defers excess units")
	var commands_preserved: bool = true
	for id: int in army:
		commands_preserved = commands_preserved and not sim.entities[id].commands.is_empty() and sim.entities[id].commands[0].pos == goals[id]
	_check(commands_preserved and _army_on_land(sim, army), "deferred shore units keep their move goals and do not enter water")
	_check(is_equal_approx(float(sim.time), STEP), "simulation time advances while units await navigation")
	_check(is_equal_approx(float(sim.building_orders[0].remaining), remaining - STEP), "paid construction advances during deferred planning")
	_check(float(sim.entities[fixture.harvester].cargo) > 0.0, "real ore harvesting continues during deferred planning")
	_check(float(sim.entities[fixture.target].hp) < hp, "real weapon fire and damage continue during deferred planning")
	var route: Dictionary = _route_until_arrival(sim, army, goals)
	_check(bool(route.bounded), "all subsequent ticks preserve the configured planning budget")
	_check(bool(route.dry), "every shore unit stays off water throughout the reroute")
	_check(int(route.planned) == army.size(), "all deferred units eventually receive a usable route")
	_check(bool(route.arrived), "all units complete their original goals via permanent land with the bridge still destroyed")
	_check(not bool(sim.bridges[0].alive), "the route completes without silently restoring the destroyed bridge")
	if not bool(route.arrived):
		print("Navigation stalled army: ", _unit_diagnostics(sim, army))


func _snapshot(sim) -> Dictionary:
	var path: String = "/tmp/paper_war_navigation_snapshot.save"
	if sim.save_game(path) != "":
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	var snapshot: Dictionary = file.get_var(false)
	file.close()
	DirAccess.remove_absolute(path)
	return snapshot


func _write_snapshot(snapshot: Dictionary, path: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_var(snapshot, false)
	file.close()


func _test_pending_navigation_save() -> void:
	var fixture: Dictionary = _bridge_fixture()
	var sim = fixture.sim
	var goals: Dictionary = _goals(sim, fixture.army)
	var path: String = "/tmp/paper_war_navigation_pending.save"
	_check(sim._nav_dirty and not sim.entities[fixture.army[0]].path.is_empty(), "pending-save fixture has unprocessed old paths after actual bridge destruction")
	_check(sim.save_game(path) == "", "saving immediately after bridge destruction succeeds")
	var restored = Sim.new()
	var error: String = restored.load_game(path)
	_check(error == "", "loading a pending-navigation snapshot succeeds: " + error)
	if error != "":
		DirAccess.remove_absolute(path)
		return
	_check(restored._nav_dirty == sim._nav_dirty and restored._nav_regions == sim._nav_regions, "loading preserves pending invalidation regions instead of losing the refresh")
	_check(restored.bridges == sim.bridges and restored.entities == sim.entities, "loading preserves destroyed bridge state, crossing paths and unit commands exactly")
	_check(_all_masks_warm(restored), "load warms every configured ground radius before resuming the simulation")
	var identical: bool = true
	for tick: int in range(30):
		sim.step(STEP)
		restored.step(STEP)
		identical = identical and _snapshot(sim) == _snapshot(restored)
	_check(identical, "original and restored pending snapshots advance identically through batched planning")
	# Capture the real queue on the first refresh tick in a separate fixture.
	var queued: Dictionary = _bridge_fixture()
	queued.sim.step(STEP)
	_check(not queued.sim._planning_queue.is_empty(), "queue-save fixture has actual deferred navigation requests")
	_write_snapshot(_snapshot(queued.sim), path)
	var queued_load = Sim.new()
	error = queued_load.load_game(path)
	_check(error == "" and queued_load._planning_queue == queued.sim._planning_queue and queued_load.entities == queued.sim.entities, "save/load preserves FIFO order and per-unit wait state")
	if error == "":
		identical = true
		for tick: int in range(12):
			queued.sim.step(STEP)
			queued_load.step(STEP)
			identical = identical and _snapshot(queued.sim) == _snapshot(queued_load)
		_check(identical, "a restored live planning queue produces the same subsequent simulation state")
	var route: Dictionary = _route_until_arrival(restored, fixture.army, goals)
	_check(bool(route.dry) and bool(route.arrived) and not bool(restored.bridges[0].alive), "restored commands finish by dry permanent land and retain destroyed bridge state")
	# Older v1 snapshots predate these optional derived-navigation fields.
	# Use a fully refreshed snapshot, as the older simulator cleared obsolete
	# crossing paths immediately when the bridge was destroyed.
	var legacy: Dictionary = _snapshot(sim)
	for field: String in ["nav_dirty", "nav_regions", "planning_max_wait", "planning_queue"]:
		legacy.erase(field)
	for e: Dictionary in legacy.entities.values():
		e.erase("planning_wait")
		e.erase("mine_search")
		e.erase("refinery_search")
	_write_snapshot(legacy, path)
	var old_save = Sim.new()
	error = old_save.load_game(path)
	_check(error == "", "legacy v1 snapshots without optional navigation fields remain loadable: " + error)
	if error == "":
		_check(not old_save._nav_dirty and old_save._nav_regions.is_empty() and old_save._planning_queue.is_empty() and is_zero_approx(old_save._planning_max_wait) and _all_masks_warm(old_save), "legacy snapshots use safe defaults and warm derived navigation masks")
		route = _route_until_arrival(old_save, fixture.army, goals)
		_check(bool(route.dry) and bool(route.arrived) and not bool(old_save.bridges[0].alive), "legacy loaded commands resume safely around the destroyed bridge")
	DirAccess.remove_absolute(path)


func _test_queue_cleanup() -> void:
	var fixture: Dictionary = _bridge_fixture()
	var sim = fixture.sim
	sim.step(STEP)
	_check(sim._planning_queue.size() >= 3, "queue cleanup starts with at least three genuinely deferred units")
	if sim._planning_queue.size() < 3:
		return
	var stopped: int = sim._planning_queue[0]
	sim.issue([stopped], "stop", sim.entities[stopped].pos)
	_check(not sim._planning_queue.has(stopped), "S removes a queued head immediately without waiting for another tick")
	var killed: int = sim._planning_queue[0]
	_damage(sim, killed, 100000.0)
	_check(not sim.entities.has(killed) and not sim._planning_queue.has(killed), "death removes a queued head immediately")
	var arrived: int = sim._planning_queue[0]
	# This fixture represents a queued unit already within its arrival radius;
	# step must finish its real command and release its planner queue position.
	sim.entities[arrived].pos = sim.entities[arrived].commands[0].pos
	sim.step(STEP)
	_check(sim.entities[arrived].commands.is_empty() and not sim._planning_queue.has(arrived), "an already-arrived queue head releases its slot at the end of the tick")
	fixture = _bridge_fixture(false, "rivet_rifle", "attack_move")
	sim = fixture.sim
	sim.step(STEP)
	_check(not sim._planning_queue.is_empty(), "combat cleanup starts from a real queued attack-move unit")
	if sim._planning_queue.is_empty():
		return
	var engaged: int = sim._planning_queue[0]
	var enemy: int = sim.debug_spawn(1, "kestrel_engineer", sim.entities[engaged].pos + Vector2(-2.0, 0.0))
	sim.step(STEP)
	_check(int(sim.entities[engaged].auto_target) == enemy and not sim._planning_queue.has(engaged), "acquiring an in-range enemy releases a queued planning slot while combat proceeds")


func _search_fixture(include_reachable: bool) -> Dictionary:
	var sim = _new_sim()
	# Four land islands have legal standable mine goals but no path out of
	# their obstacle rings. The fifth mine is on connected land. This exposes
	# the budget edge using real terrain/AStar and real harvester behavior.
	var inaccessible: Array[Vector2] = [Vector2(8.5, 21.5), Vector2(15.5, 21.5), Vector2(8.5, 40.5), Vector2(15.5, 40.5)]
	sim.mines.clear()
	for pos: Vector2 in inaccessible:
		var center := Vector2i(floori(pos.x), floori(pos.y))
		for dz: int in range(-3, 4):
			for dx: int in range(-3, 4):
				var x: int = center.x + dx
				var z: int = center.y + dz
				sim.map.terrain[z][x] = MapData.BLOCKED if abs(dx) == 3 or abs(dz) == 3 else MapData.LAND
				sim.map.heights[z][x] = 0.0
		sim.mines.append({"pos": pos, "amount": 1000.0, "capacity": 1000.0})
	if include_reachable:
		sim.mines.append({"pos": Vector2(19.5, 46.5), "amount": 1000.0, "capacity": 1000.0})
	# Keep valid, equal starting-resource metadata for save validation. The
	# runtime candidate list above deliberately includes currently isolated ore.
	sim.map.mines = []
	for pos: Vector2 in [Vector2(4.5, 25.5), Vector2(14.5, 34.5), Vector2(43.5, 25.5), Vector2(33.5, 34.5)]:
		sim.map.mines.append({"pos": [pos.x, pos.y], "capacity": 3000.0})
	sim._prepare_terrain_cache()
	sim._nav_initialized = false
	sim._nav_dirty = true
	sim._rebuild_nav()
	var harvester: int = sim.debug_spawn(0, "rivet_harvester", Vector2(5.5, 29.5))
	return {"sim": sim, "harvester": harvester}


func _test_candidate_search_progress() -> void:
	var fixture: Dictionary = _search_fixture(true)
	var sim = fixture.sim
	var id: int = fixture.harvester
	var e: Dictionary = sim.entities[id]
	var first_four_inaccessible: bool = true
	for index: int in range(4):
		var goal: Vector2 = sim._near_stand(sim.mines[index].pos, float(e.radius), id, 2.0, false)
		first_four_inaccessible = first_four_inaccessible and goal.is_finite() and sim._path_between(e.pos, goal, float(e.radius), id).is_empty()
	_check(first_four_inaccessible, "the first four mine candidates are standable but genuinely unreachable")
	var final_goal: Vector2 = sim._near_stand(sim.mines[4].pos, float(e.radius), id, 2.0, false)
	_check(not sim._path_between(e.pos, final_goal, float(e.radius), id).is_empty(), "the fifth mine candidate has a real reachable path")
	_check(sim._resource_candidates(e, false).back() == 4, "the reachable mine ranks after all four inaccessible candidates")
	sim.step(STEP)
	var search: Dictionary = e.get("mine_search", {})
	_check(not search.is_empty() and int(search.next) == Sim.PATH_PLANS_PER_TICK and sim._planning_queue.has(id), "candidate search retains its cursor and queue position after exhausting the first tick budget")
	var path: String = "/tmp/paper_war_navigation_search.save"
	_check(sim.save_game(path) == "", "a resource search interrupted by the planning budget can be saved")
	var restored = Sim.new()
	var error: String = restored.load_game(path)
	_check(error == "", "a saved candidate-search cursor loads successfully: " + error)
	if error == "":
		_check(restored.entities[id].get("mine_search", {}) == search and restored._planning_queue == sim._planning_queue, "loading preserves the candidate-search breakpoint and FIFO position")
	var elapsed: float = 0.0
	var identical: bool = true
	while elapsed < 40.0 and float(e.cargo) <= 0.0:
		sim.step(STEP)
		if error == "":
			restored.step(STEP)
			identical = identical and sim.entities == restored.entities and sim.mines == restored.mines and sim._planning_queue == restored._planning_queue
		elapsed += STEP
	_check(int(e.harvest_mine) == 4 and float(e.cargo) > 0.0, "a harvester searches beyond four failed candidates and actually harvests the reachable fifth mine")
	if error == "":
		_check(identical and float(restored.entities[id].cargo) > 0.0, "original and restored candidate searches finish identically with useful harvested ore")
	DirAccess.remove_absolute(path)
	if float(e.cargo) <= 0.0:
		print("Mine search stalled: ", _unit_diagnostics(sim, [id]))


func _test_planner_fairness() -> void:
	var fixture: Dictionary = _search_fixture(false)
	var sim = fixture.sim
	var harvester: int = fixture.harvester
	var mover: int = sim.debug_spawn(0, "rivet_engineer", Vector2(19.5, 29.5))
	var destination := Vector2(19.5, 34.5)
	sim.issue([mover], "move", destination)
	var elapsed: float = 0.0
	var got_path: bool = false
	while elapsed < 15.0 and not sim.entities[mover].commands.is_empty():
		sim.step(STEP)
		elapsed += STEP
		got_path = got_path or not sim.entities[mover].path.is_empty()
	_check(harvester < mover and int(sim.entities[harvester].harvest_mine) == -1, "a lower-ID harvester keeps encountering only unreachable candidates")
	_check(got_path and sim.entities[mover].commands.is_empty() and (sim.entities[mover].pos as Vector2).distance_to(destination) < 0.4, "the higher-ID mover still receives planning work and completes its command")
	if not sim.entities[mover].commands.is_empty():
		print("Planner fairness stalled: ", _unit_diagnostics(sim, [harvester, mover]))


func _unit_diagnostics(sim, ids: Array) -> Array:
	var answer: Array = []
	for id: int in ids:
		if not sim.entities.has(id):
			answer.append({"id": id, "missing": true})
			continue
		var e: Dictionary = sim.entities[id]
		answer.append({"id": id, "pos": e.pos, "state": e.state, "path": e.path, "commands": e.commands, "path_wait": e.path_wait, "planning_wait": e.get("planning_wait", 0.0), "harvest_mine": e.harvest_mine, "cargo": e.cargo})
	return answer


func _reference_segment_static(sim, start: Vector2, end: Vector2, radius: float, ignore: int) -> bool:
	# Literal pre-optimization rule: every 0.25 terrain sample, then every 0.4
	# footprint/building sample. This comparison must include mixed terrain.
	if not sim._segment_terrain(start, end):
		return false
	var count: int = maxi(1, ceili(start.distance_to(end) / 0.4))
	for n: int in range(1, count + 1):
		if not sim._standing(start.lerp(end, float(n) / float(count)), radius, ignore, false):
			return false
	return true


func _test_flat_segment_equivalence() -> void:
	var sim = _new_sim()
	sim.debug_spawn(0, "rivet_power", Vector2(12.5, 43.5))
	sim.bridges[0].alive = false
	sim.bridges[0].hp = 0.0
	var probes: Array[Vector2] = []
	for z: int in range(0, int(sim.map.size), 3):
		for x: int in range(0, int(sim.map.size), 3):
			probes.append(Vector2(x + 0.97, z + 0.03))
	# Static blockers, ramps and broken-bridge shoreline retain terrain probes.
	var special: Dictionary = {MapData.BLOCKED: 0, MapData.RAMP: 0, MapData.WATER: 0}
	for z: int in range(int(sim.map.size)):
		for x: int in range(int(sim.map.size)):
			var terrain: int = int(sim.map.terrain[z][x])
			if special.has(terrain) and int(special[terrain]) < 12:
				probes.append(Vector2(x + 0.99, z + 0.99))
				special[terrain] = int(special[terrain]) + 1
	# Trees now block through removable neutral footprints over LAND cells.
	# Sample actual footprint corners rather than requiring old BLOCKED terrain.
	var forest_corners: int = 0
	for ruin in sim.ruins:
		if ruin.kind != "tree" or float(ruin.hp) <= 0.0: continue
		probes.append(ruin.pos + ruin.half - Vector2.ONE * .01)
		forest_corners += 1
		if forest_corners == 12: break
	probes.append_array([Vector2(10.6, 41.6), Vector2(21.99, 30.0), Vector2(26.01, 30.0)])
	var offsets: Array[Vector2] = [Vector2(0.1, 0.1), Vector2(-0.35, 0.15), Vector2(0.4, 0.0), Vector2(0.29, 0.29), Vector2(1.7, 1.1), Vector2(3.2, -0.8)]
	var identical: bool = true
	var exact_never_relaxes: bool = true
	var exact_rejections: int = 0
	var comparisons: int = 0
	var flat_cases: int = 0
	var discrepancies: Array = []
	for start: Vector2 in probes:
		for offset: Vector2 in offsets:
			var end: Vector2 = start + offset
			for radius: float in [0.35, 0.75, 0.95, 0.99, 1.01]:
				var original: bool = _reference_segment_static(sim, start, end, radius, -1)
				# Keep the original sampler equivalence contract. The shared exact
				# sweep deliberately rejects contacts that the old sampler missed.
				var optimized: bool = sim._segment_static_sampled(start, end, radius, -1)
				var exact: bool = sim._segment_static(start, end, radius, -1)
				exact_never_relaxes = exact_never_relaxes and (original or not exact)
				if original and not exact: exact_rejections += 1
				comparisons += 1
				if sim._fast_flat(start, radius) and sim._fast_flat(end, radius): flat_cases += 1
				if original != optimized:
					identical = false
					if discrepancies.size() < 10: discrepancies.append({"start": start, "end": end, "radius": radius, "original": original, "optimized": optimized})
	_check(comparisons > 8000 and flat_cases > 0, "segment equivalence fixture exercises both the flat fast path and thousands of radius/corner/border cases")
	_check(forest_corners > 0 and int(special[MapData.RAMP]) > 0 and int(special[MapData.WATER]) > 0, "segment equivalence explicitly covers live forest footprint corners, ramps and broken-bridge water")
	_check(identical, "optimized sampler exactly matches the original sampled terrain/footprint rule across %d probes" % comparisons)
	_check(exact_never_relaxes, "continuous static collision never admits a segment rejected by the original sampled rule")
	_check(exact_rejections > 0, "continuous static collision catches real contacts missed between the original footprint samples")
	print("Segment sampler comparisons: ", comparisons, "; continuous rejections of sampled-clear contacts: ", exact_rejections)
	if not identical: print("Segment discrepancies: ", discrepancies)


func _test_dynamic_tree_corners() -> void:
	var sim = _new_sim()
	var start := Vector2(14.5, 40.5)
	var goal := Vector2(15.5, 39.5)
	var tree: Dictionary = {"id": sim.ruins.size(), "kind": "tree", "pos": Vector2(15.5, 40.5), "half": Vector2(.48, .48), "hp": 180.0, "max_hp": 180.0, "yaw": 0.0, "variant": 0}
	sim.ruins.append(tree)
	sim._refresh_ruin_spatial()
	sim._mark_nav_region(Rect2(tree.pos - tree.half, tree.half * 2.0))
	sim._rebuild_nav()
	var mover: int = sim.debug_spawn(0, "rivet_engineer", start)
	_check(sim.entities[mover].pos == start and sim._standing(goal, .35, mover, false) and not sim._segment_static(start, goal, .35, mover), "two legal neighbors across a live tree corner have an illegal direct diagonal")
	var path: Array = sim._path_between(start, goal, .35, mover)
	var legal: bool = not path.is_empty()
	var previous: Vector2 = start
	for point: Vector2 in path:
		legal = legal and sim._segment_static(previous, point, .35, mover)
		previous = point
	_check(legal, "a dynamic tree corner route contains only traversable segments")
	sim.issue([mover], "move", goal)
	for i in range(120): sim.step(STEP)
	_check(sim.entities[mover].commands.is_empty() and (sim.entities[mover].pos as Vector2).distance_to(goal) < .4, "infantry completes the short route around the live tree corner")
	sim._add_damage(Sim.RUIN_TARGET_BASE - int(tree.id), 180.0, true)
	sim._apply_damage()
	sim._rebuild_nav()
	_check(float(tree.hp) == 0.0 and sim._segment_static(start, goal, .35, mover), "destroying the tree immediately permits its former corner diagonal")


func _test_expired_detour_at_water_bank() -> void:
	var sim = _new_sim()
	var start := Vector2(21.56444, 26.34252)
	var goal := Vector2(20.5, 25.5)
	var mover: int = sim.debug_spawn(0, "rivet_engineer", start)
	sim.issue([mover], "move", goal)
	var e: Dictionary = sim.entities[mover]
	_check(e.pos == start and _prepare_command_paths(sim, [mover]) and sim._segment_static(start, goal, .35, mover), "water-bank recovery starts with an unobstructed goal and valid path")
	# A real earlier collision may leave a right-hand detour pointing into the
	# river after the next waypoint becomes clear. That detour must stop owning
	# movement instead of extending itself during every subsequent turn.
	e.alpha = 78.96
	e.avoid_dir = Vector2(.857484, .51451)
	e.avoid_until = sim.time + .55
	for i in range(120): sim.step(STEP)
	_check(e.commands.is_empty() and (e.pos as Vector2).distance_to(goal) < .4 and MapData.terrain_at(sim.map, e.pos) != MapData.WATER, "a cleared waypoint overrides stale side-stepping and completes safely beside water")


func _reference_neighbors(sim, pos: Vector2) -> Array:
	var answer: Array = []
	var cell: Vector2i = sim._bucket(pos)
	for z: int in range(-1, 2):
		for x: int in range(-1, 2):
			answer.append_array(sim._spatial.get(cell + Vector2i(x, z), []))
	return answer


func _test_neighbor_cache_mutations() -> void:
	var sim = _new_sim()
	var mover: int = sim.debug_spawn(0, "rivet_engineer", Vector2(6.5, 43.5))
	var other: int = sim.debug_spawn(0, "rivet_engineer", Vector2(8.5, 43.5))
	sim._rebuild_spatial()
	var position: Vector2 = sim.entities[mover].pos
	var first: Array = sim._neighbors(position)
	_check(first == _reference_neighbors(sim, position) and sim._neighbor_cache.has(sim._bucket(position)), "neighbor cache preserves the original bucket and entity order")
	var added: int = sim.debug_spawn(0, "rivet_engineer", Vector2(7.5, 45.5))
	_check(sim._neighbor_cache.is_empty() and added > 0, "adding a real unit invalidates neighbor arrays immediately within the same tick")
	_check(sim._neighbors(position) == _reference_neighbors(sim, position), "the next query includes the newly spawned unit in original bucket order")
	sim.entities[mover].alpha = -90.0
	sim._move_to(sim.entities[mover], Vector2(6.5, 39.5), STEP)
	_check(float(sim.entities[mover].motion) > 0.0 and not sim._standing(sim.entities[mover].pos, .35, other), "actual movement updates live cached coordinates before later units test collision in the same tick")
	position = sim.entities[mover].pos
	_check(sim._neighbors(position) == _reference_neighbors(sim, position), "post-movement neighbor order and membership match fresh original queries")
	_damage(sim, other, 10000.0)
	_check(not sim.entities.has(other) and sim._neighbor_cache.is_empty(), "same-tick unit death immediately invalidates the neighbor cache")
	_check(sim._neighbors(position) == _reference_neighbors(sim, position), "the rebuilt cache excludes dead units without reordering surviving neighbors")
