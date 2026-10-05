extends SceneTree

## Small functional controls using the real asynchronous worker. No renderer,
## reservations, relaxed radius, or long population/performance benchmark.
## --cases comma,separated,names selects a batch without changing its fixtures.
const Sim = preload("res://scripts/simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
const STEP := 1.0 / 30.0
const SEED := 7
const WORKER_YIELD_US := 1000
const CASES := [
	"tank_opposing_width4", "tank_opposing_width2", "rifle_opposing_width1",
	"tank_fifo8", "tank_fifo8_reversed_ids", "rifle_fifo6_width1",
	"cancel_queued_tank", "death_queued_tank", "hold_gap_permanent",
	"hold_gap_release", "death_gap_release", "queued_moves_survive_yield",
	"opposing_root_cancel", "opposing_root_death", "tank_two_approaches6",
]

class TracedSim:
	extends "res://scripts/simulation.gd"
	var yield_trace: Array[Dictionary] = []
	var yield_assignments := 0
	var yield_edges: Dictionary = {}
	func _request_movement_yield(e: Dictionary, other: Dictionary, start: Vector2, next: Vector2) -> void:
		var before: Vector2 = other.get("yield_goal", Vector2.INF)
		super._request_movement_yield(e, other, start, next)
		var after: Vector2 = other.get("yield_goal", Vector2.INF)
		if before == after: return
		yield_assignments += 1
		var edge := str(e.id) + "→" + str(other.id)
		yield_edges[edge] = int(yield_edges.get(edge, 0)) + 1
		if yield_trace.size() < 1200:
			yield_trace.append({"event": "assigned", "time": time, "requester": e.id, "blocker": other.id,
				"requester_pos": [e.pos.x, e.pos.y], "blocker_pos": [other.pos.x, other.pos.y],
				"forward": [(next-start).normalized().x, (next-start).normalized().y],
				"goal": [after.x, after.y], "expires": other.get("yield_until", 0.0)})
	func step(delta: float) -> void:
		var active: Array[Dictionary] = []
		for entity in entities.values():
			var goal: Vector2 = entity.get("yield_goal", Vector2.INF)
			if goal.is_finite(): active.append({"id": entity.id, "goal": goal, "expires": float(entity.get("yield_until", 0.0))})
		super.step(delta)
		for old in active:
			var entity: Dictionary = entities.get(old.id, {})
			if not entity.is_empty() and not (entity.get("yield_goal", Vector2.INF) as Vector2).is_finite() and yield_trace.size() < 1200:
				yield_trace.append({"event": "expired" if time >= old.expires else "arrived", "time": time, "id": old.id,
					"pos": [entity.pos.x, entity.pos.y], "goal": [old.goal.x, old.goal.y], "expires": old.expires})

var rules: Dictionary
var checks := 0
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var selected: Array[String] = []
var current_case := ""
var output := "res://artifacts/demo_20261004/navigation/control_latest.json"
var source_before: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(current_case + ": " + label)

func source_hashes() -> Dictionary:
	var result: Dictionary = {}
	for path in ["res://tests/demo_navigation_control_tests.gd", "res://scripts/simulation.gd", "res://scripts/path_worker.gd",
		"res://scripts/path_graph.gd", "res://data/rules.json", "res://assets/native/libpaper_front_kernels.so"]:
		if FileAccess.file_exists(path): result[path] = FileAccess.get_sha256(path)
	return result

func run() -> void:
	var args := OS.get_cmdline_user_args()
	for index in range(args.size()-1):
		if args[index] == "--output": output = args[index+1]
		elif args[index] == "--cases":
			for name in args[index+1].split(",", false): selected.append(name)
	if "--list" in args:
		print("DEMO_NAV_CONTROL_CASES ", ",".join(CASES))
		quit(0)
		return
	if DisplayServer.get_name() != "headless":
		push_error("Navigation controls require headless execution")
		quit(2)
		return
	for name in selected:
		if name not in CASES:
			push_error("Unknown control case: " + name)
			quit(2)
			return
	rules = Rules.load_rules()
	if rules.is_empty():
		push_error("Navigation control rules invalid: " + str(Rules.errors))
		quit(2)
		return
	source_before = source_hashes()
	var wall_start := Time.get_ticks_usec()
	for name in CASES:
		if not selected.is_empty() and name not in selected: continue
		current_case = name
		print("DEMO_NAV_CONTROL_BEGIN ", name)
		match name:
			"tank_opposing_width4": opposing(4, "rivet_tank", true)
			"tank_opposing_width2": opposing(2, "rivet_tank", false)
			"rifle_opposing_width1": opposing(1, "rivet_rifle", false)
			"tank_fifo8": fifo(8, "rivet_tank", false)
			"tank_fifo8_reversed_ids": fifo(8, "rivet_tank", true)
			"rifle_fifo6_width1": fifo(6, "rivet_rifle", false)
			"cancel_queued_tank": cancel_or_kill_queued(false)
			"death_queued_tank": cancel_or_kill_queued(true)
			"hold_gap_permanent": held_gap("permanent")
			"hold_gap_release": held_gap("move")
			"death_gap_release": held_gap("death")
			"queued_moves_survive_yield": queued_yield()
			"opposing_root_cancel": opposing_cancel_or_kill(false)
			"opposing_root_death": opposing_cancel_or_kill(true)
			"tank_two_approaches6": two_approaches()
		write_report(false, float(Time.get_ticks_usec()-wall_start)/1000000.0)
	var source_after := source_hashes()
	current_case = "source_snapshot"
	check(source_before == source_after, "source and native binary stayed unchanged throughout this batch")
	write_report(true, float(Time.get_ticks_usec()-wall_start)/1000000.0)
	print("DEMO_NAV_CONTROL ", checks-failures.size(), "/", checks, " cases=", rows.size(), " failures=", JSON.stringify(failures))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func write_report(complete: bool, seconds: float) -> void:
	var report := {"schema": 1, "complete": complete, "checks": checks, "passed": checks-failures.size(),
		"failures": failures, "case_count": rows.size(), "rows": rows, "seed": SEED, "step_seconds": STEP,
		"worker_yield_us_per_tick": WORKER_YIELD_US, "collision_sampling_every_sim_ticks": 1, "wall_seconds": seconds,
		"scope": "small functional headless controls with actual asynchronous worker, unchanged real rules/collision; no GPU/FPS claim",
		"source_before": source_before, "source_after": source_hashes(), "godot": Engine.get_version_info().string}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write navigation control report: " + output)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()

func fixture(width: int, walls: bool, positions: Array[Vector2], spec: String, reverse_ids: bool = false) -> Dictionary:
	var started := Time.get_ticks_usec()
	var checks_before := checks
	var failures_before := failures.size()
	var sim = TracedSim.new()
	sim.setup(rules, "dev", SEED, "rivet", false)
	for z in range(48):
		for x in range(48):
			sim.map.terrain[z][x] = 0
			sim.map.heights[z][x] = 0.0
	sim.mines.clear()
	sim.bridges.clear()
	sim.ruins.clear()
	sim._refresh_ruin_spatial()
	for id in sim.entities.keys(): sim._kill_entity(id, false)
	sim.debug_spawn(0, "rivet_hq", Vector2(4, 44))
	sim.debug_spawn(1, "kestrel_hq", Vector2(44, 44))
	# Both ends stay wide open. A width2/width1 opposing case is physically
	# solvable by retreating out of the six-meter throat into either chamber.
	for z in range(48):
		var open_row: bool = z >= 23 and z < 23+width
		if walls: open_row = z >= 22 and z < 24+width
		if open_row: continue
		for x in range(21, 27): sim.map.terrain[z][x] = 4
	if walls:
		for x in range(21, 27):
			sim.debug_spawn(0, "rivet_wall", Vector2(x+.5, 22.5))
			sim.debug_spawn(0, "rivet_wall", Vector2(x+.5, 23.5+width))
	sim._prepare_terrain_cache()
	sim._nav_initialized = false
	sim._rebuild_nav()
	var ids: Array[int] = []
	ids.resize(positions.size())
	var indices: Array[int] = []
	for index in range(positions.size()): indices.append(index)
	if reverse_ids: indices.reverse()
	for index in indices:
		ids[index] = sim.debug_spawn(0, spec, positions[index])
		check(ids[index] > 0 and (sim.entities[ids[index]].pos as Vector2).distance_to(positions[index]) < .002,
			"unit " + str(index) + " spawned at its exact legal fixture point")
	sim._rebuild_spatial()
	var ctx := {"sim": sim, "ids": ids, "goals": {}, "previous": {}, "still": {}, "maximum_still": 0.0,
		"violations": [], "maximum_overlap": 0.0, "minimum_pair_margin": INF, "maximum_queue": 0,
		"maximum_in_flight": 0, "budget_legal": true, "unexpected_result": "", "snapshots": [],
		"completed_at": {}, "initial": [], "width": width, "walls": walls, "spec": spec, "checks_before": checks_before,
		"failures_before": failures_before, "started_usec": started, "source_hashes": source_hashes()}
	for id in ids:
		ctx.previous[id] = sim.entities[id].pos
		ctx.initial.append(unit_state(sim, id))
	monitor(ctx)
	check(not sim.synchronous_path_tests and sim._path_worker != null, "fixture uses actual background worker")
	return ctx

func point(value: Vector2):
	return [value.x, value.y] if value.is_finite() else null

func unit_state(sim, id: int) -> Dictionary:
	if not sim.entities.has(id): return {"id": id, "dead": true}
	var entity: Dictionary = sim.entities[id]
	var commands: Array[Dictionary] = []
	for command in entity.commands:
		commands.append({"kind": command.kind, "pos": point(command.pos), "target": command.get("target", -1)})
	return {"id": id, "pos": point(entity.pos), "alpha": entity.alpha, "state": entity.state, "commands": commands,
		"yield_goal": point(entity.get("yield_goal", Vector2.INF)), "yield_until": entity.get("yield_until", 0.0),
		"hold": entity.get("hold_position", false), "stuck": entity.stuck, "planning_wait": entity.get("planning_wait", 0.0)}

func move(ctx: Dictionary, id: int, goal: Vector2, append: bool = false) -> void:
	var sim = ctx.sim
	sim.issue([id], "move", goal, -1, append)
	check(not sim.entities[id].commands.is_empty(), "move order accepted for " + str(id))
	if not sim.entities[id].commands.is_empty():
		ctx.goals[id] = sim.entities[id].commands.back().pos
		ctx.completed_at.erase(id)

func completed(ctx: Dictionary, ids: Array[int]) -> bool:
	var sim = ctx.sim
	for id in ids:
		if not sim.entities.has(id) or not sim.entities[id].commands.is_empty(): return false
		# A completed idle unit can legally yield away from its old destination
		# afterwards. Require an observed arrival at its actual final goal, then
		# empty orders, rather than requiring every completed unit to stay parked.
		if ctx.goals.has(id) and not ctx.completed_at.has(id): return false
	return true

func violation(ctx: Dictionary, value: Dictionary) -> void:
	if ctx.violations.size() < 20: ctx.violations.append(value)

func monitor(ctx: Dictionary) -> void:
	var sim = ctx.sim
	var alive: Array[int] = []
	for id in ctx.ids:
		if not sim.entities.has(id): continue
		alive.append(id)
		var entity: Dictionary = sim.entities[id]
		var previous: Vector2 = ctx.previous.get(id, entity.pos)
		var radius: float = float(entity.radius)
		if not sim._standing(entity.pos, radius, id, false):
			violation(ctx, {"kind": "static_position", "time": sim.time, "id": id, "pos": point(entity.pos)})
		if not sim._segment_static(previous, entity.pos, radius, id):
			violation(ctx, {"kind": "static_movement_segment", "time": sim.time, "id": id, "from": point(previous), "to": point(entity.pos)})
		var pending: bool = not entity.commands.is_empty()
		ctx.still[id] = float(ctx.still.get(id, 0.0)) + STEP if pending and (entity.pos as Vector2).distance_squared_to(previous) < .00000001 else 0.0
		ctx.maximum_still = maxf(ctx.maximum_still, ctx.still[id])
		ctx.previous[id] = entity.pos
		if ctx.goals.has(id) and not pending and not ctx.completed_at.has(id) and (entity.pos as Vector2).distance_to(ctx.goals[id]) < .4:
			ctx.completed_at[id] = sim.time
	for index in range(alive.size()):
		for other_index in range(index+1, alive.size()):
			var a: Dictionary = sim.entities[alive[index]]
			var b: Dictionary = sim.entities[alive[other_index]]
			var separation: float = (a.pos as Vector2).distance_to(b.pos)
			var body: float = float(a.radius) + float(b.radius)
			ctx.minimum_pair_margin = minf(ctx.minimum_pair_margin, separation-body)
			ctx.maximum_overlap = maxf(ctx.maximum_overlap, body-separation)
			# Keep the game's .02 margin, allowing only float rounding (.001).
			if separation < body+.019:
				violation(ctx, {"kind": "unit_safety_margin", "time": sim.time, "a": a.id, "b": b.id,
					"a_pos": point(a.pos), "b_pos": point(b.pos), "distance": separation, "required": body+.02})
	ctx.maximum_queue = maxi(ctx.maximum_queue, sim._planning_queue.size())
	ctx.maximum_in_flight = maxi(ctx.maximum_in_flight, sim._path_in_flight)
	ctx.budget_legal = ctx.budget_legal and sim._yield_requests >= 0 and sim._yield_requests <= Sim.YIELD_REQUESTS_PER_TICK and sim._avoidance_probes >= 0 and sim._path_in_flight <= Sim.PATH_IN_FLIGHT
	if not sim.result.is_empty(): ctx.unexpected_result = sim.result

func tick(ctx: Dictionary) -> void:
	var sim = ctx.sim
	sim.step(STEP)
	monitor(ctx)
	sim.events.clear()
	OS.delay_usec(WORKER_YIELD_US)
	if roundi(sim.time*30.0) % 300 == 0:
		var states: Array[Dictionary] = []
		for id in ctx.ids: states.append(unit_state(sim, id))
		ctx.snapshots.append({"time": sim.time, "units": states, "queue": sim._planning_queue.size(), "in_flight": sim._path_in_flight})

func advance(ctx: Dictionary, seconds: float, finish_ids: Array[int] = []) -> void:
	var end: float = ctx.sim.time+seconds
	while ctx.sim.time+STEP*.5 < end:
		tick(ctx)
		if not finish_ids.is_empty() and completed(ctx, finish_ids): break
		if not ctx.unexpected_result.is_empty(): break

func finish(ctx: Dictionary, expected: Array[int], require_completion: bool = true) -> void:
	var sim = ctx.sim
	if require_completion: check(completed(ctx, expected), "all expected surviving units complete their actual final orders")
	check(ctx.violations.is_empty(), "every tick preserves original static footprint and .02 unit margin")
	check(ctx.budget_legal and ctx.maximum_in_flight <= Sim.PATH_IN_FLIGHT, "request/probe/in-flight budgets stay bounded")
	check(ctx.unexpected_result.is_empty(), "no unrelated combat/result interrupts this navigation fixture")
	check(sim.navigation_stats.completed > 0, "actual asynchronous worker completed at least one job")
	var final_units: Array[Dictionary] = []
	for id in ctx.ids: final_units.append(unit_state(sim, id))
	var goal_output: Dictionary = {}
	for id in ctx.goals: goal_output[str(id)] = point(ctx.goals[id])
	var row := {"case": current_case, "unit_count": ctx.ids.size(), "spec": ctx.spec, "radius": rules.units[ctx.spec].radius,
		"expected_outcome": "complete" if require_completion else "legitimate permanent hold blockage", "case_passed": failures.size() == int(ctx.failures_before),
		"gap_width": ctx.width, "real_walls": ctx.walls, "initial": ctx.initial, "actual_final_goals": goal_output,
		"expected_completed_ids": expected, "all_expected_completed": completed(ctx, expected), "completed_at": ctx.completed_at,
		"final": final_units, "sim_seconds": sim.time, "wall_seconds": float(Time.get_ticks_usec()-int(ctx.started_usec))/1000000.0,
		"maximum_contiguous_no_translation_seconds": ctx.maximum_still, "maximum_planning_wait_seconds": sim._planning_max_wait,
		"maximum_queue": ctx.maximum_queue, "maximum_in_flight": ctx.maximum_in_flight, "budget_legal": ctx.budget_legal,
		"minimum_pair_margin": ctx.minimum_pair_margin, "maximum_geometric_overlap": ctx.maximum_overlap,
		"violations": ctx.violations, "navigation": sim.navigation_stats.duplicate(), "yield_assignments": sim.yield_assignments,
		"yield_edges": sim.yield_edges, "yield_trace": sim.yield_trace, "snapshots": ctx.snapshots,
		"native_available": sim._kernels != null, "native_dispatch": sim.native_kernels_enabled and sim.native_unit_dispatch_enabled and sim._kernels != null,
		"native_movement": sim.native_movement_enabled, "source_hashes": ctx.source_hashes,
		"case_failures": failures.slice(int(ctx.failures_before))}
	rows.append(row)
	print("DEMO_NAV_CONTROL_END ", current_case, " completed=", row.all_expected_completed, " sim=", row.sim_seconds,
		" violations=", row.violations.size(), " failures=", JSON.stringify(row.case_failures))
	ctx.sim = null
	sim = null

func opposing(width: int, spec: String, walls: bool) -> void:
	var center: float = 23.0+float(width)*.5
	var positions: Array[Vector2] = [Vector2(18, center), Vector2(15.5, center), Vector2(30, center), Vector2(32.5, center)]
	var ctx := fixture(width, walls, positions, spec)
	for index in range(4): ctx.sim.entities[ctx.ids[index]].alpha = 0.0 if index < 2 else 180.0
	move(ctx, ctx.ids[0], Vector2(35, center))
	move(ctx, ctx.ids[1], Vector2(35, center+3))
	move(ctx, ctx.ids[2], Vector2(12, center))
	move(ctx, ctx.ids[3], Vector2(12, center-3))
	advance(ctx, 120.0, ctx.ids)
	check(ctx.sim._planning_max_wait < 5.0, "opposing teams of allies receive bounded planner service")
	finish(ctx, ctx.ids)

func fifo(count: int, spec: String, reverse_ids: bool) -> void:
	var width := 1 if spec == "rivet_rifle" else 2
	var positions: Array[Vector2] = []
	for index in range(count):
		if spec == "rivet_rifle": positions.append(Vector2(13+index*.9, 23.5))
		else: positions.append(Vector2(16.5+(index%2)*2.5, 20.4+floorf(float(index)/2.0)*2.4))
	var ctx := fixture(width, false, positions, spec, reverse_ids)
	for index in range(count):
		move(ctx, ctx.ids[index], Vector2(34+(index%2)*3, 20.0+floorf(float(index)/2.0)*2.5))
	advance(ctx, 120.0, ctx.ids)
	check(ctx.sim._planning_max_wait < 5.0, "later FIFO callers receive bounded planner service")
	finish(ctx, ctx.ids)

func cancel_or_kill_queued(kill: bool) -> void:
	var positions: Array[Vector2] = []
	for index in range(6): positions.append(Vector2(16.5+(index%2)*2.5, 21.6+floorf(float(index)/2.0)*2.4))
	var ctx := fixture(2, false, positions, "rivet_tank")
	for index in range(6): move(ctx, ctx.ids[index], Vector2(34+(index%2)*3, 20+floorf(float(index)/2.0)*3))
	tick(ctx)
	var removed: int = ctx.ids.back()
	check(ctx.sim._path_requests.has(removed) or ctx.sim._planning_queue.has(removed), "last caller really has pending asynchronous work before cancellation")
	var survivors: Array[int] = ctx.ids.duplicate()
	if kill:
		ctx.sim._kill_entity(removed, false)
		survivors.erase(removed)
		check(not ctx.sim.entities.has(removed), "dead caller is removed from live collision/entities")
	else:
		ctx.sim.issue([removed], "stop", Vector2.ZERO)
		check(ctx.sim.entities[removed].commands.is_empty() and not (ctx.sim.entities[removed].get("yield_goal", Vector2.INF) as Vector2).is_finite(), "stop clears order and active yield immediately")
	check(not ctx.sim._planning_queue.has(removed) and not ctx.sim._path_requests.has(removed), "cancel/death removes stale planner work immediately")
	if not kill: move(ctx, removed, Vector2(13, 18))
	advance(ctx, 119.0, survivors)
	check(ctx.sim._planning_max_wait < 5.0, "remaining callers are served after cancelling/deleting the waiting tail")
	finish(ctx, survivors)

func held_gap(action: String) -> void:
	var positions: Array[Vector2] = [Vector2(18, 24), Vector2(15.5, 24), Vector2(24, 24), Vector2(10, 10)]
	var ctx := fixture(2, true, positions, "rivet_tank")
	var blocker: int = ctx.ids[2]
	var held_position: Vector2 = ctx.sim.entities[blocker].pos
	ctx.sim.issue([blocker], "hold", Vector2.ZERO)
	move(ctx, ctx.ids[0], Vector2(35, 24))
	move(ctx, ctx.ids[1], Vector2(38, 26))
	advance(ctx, 12.0 if action == "permanent" else 4.0)
	check(ctx.sim.entities[blocker].pos == held_position and not (ctx.sim.entities[blocker].get("yield_goal", Vector2.INF) as Vector2).is_finite(), "held vehicle in throat stays exactly still and is never forced to yield")
	check(not ctx.sim.entities[ctx.ids[0]].commands.is_empty() and ctx.sim.entities[ctx.ids[0]].pos.x < 27.0, "permanent held footprint legitimately blocks this single-tank throat")
	var expected: Array[int] = [ctx.ids[0], ctx.ids[1]]
	if action == "permanent":
		finish(ctx, expected, false)
		return
	if action == "death":
		ctx.sim._kill_entity(blocker, false)
		check(not ctx.sim.entities.has(blocker), "destroyed blocking footprint is removed")
	else:
		move(ctx, blocker, Vector2(31, 21))
		expected.append(blocker)
		check(not ctx.sim.entities[blocker].get("hold_position", true), "new move explicitly releases hold")
	advance(ctx, 60.0, expected)
	finish(ctx, expected)

func queued_yield() -> void:
	var positions: Array[Vector2] = [Vector2(18, 24), Vector2(19.52, 24), Vector2(15, 19), Vector2(15, 29)]
	var ctx := fixture(2, false, positions, "rivet_tank")
	var requester: int = ctx.ids[0]
	var blocker: int = ctx.ids[1]
	ctx.sim.entities[requester].alpha = 0.0
	ctx.sim.entities[blocker].alpha = 180.0
	move(ctx, requester, Vector2(35, 24))
	move(ctx, requester, Vector2(35, 31), true)
	move(ctx, blocker, Vector2(35, 27))
	move(ctx, blocker, Vector2(39, 27), true)
	var original: Dictionary = {}
	original[requester] = ctx.sim.entities[requester].commands.duplicate(true)
	original[blocker] = ctx.sim.entities[blocker].commands.duplicate(true)
	var intact := true
	var observed_yield := false
	var end: float = ctx.sim.time+120.0
	while ctx.sim.time+STEP*.5 < end:
		tick(ctx)
		for id in [requester, blocker]:
			var entity: Dictionary = ctx.sim.entities[id]
			if (entity.get("yield_goal", Vector2.INF) as Vector2).is_finite():
				observed_yield = true
			if entity.commands.size() == 2: intact = intact and entity.commands == original[id]
			elif entity.commands.size() == 1: intact = intact and entity.commands[0] == original[id][1]
		if completed(ctx, [requester, blocker]): break
	check(observed_yield, "fixture actually assigns an avoidance yield while queued movement remains")
	check(intact, "temporary yielding preserves original queued order sequence and targets")
	finish(ctx, [requester, blocker])

func opposing_cancel_or_kill(kill: bool) -> void:
	var positions: Array[Vector2] = [Vector2(18, 24), Vector2(15.5, 24), Vector2(30, 24), Vector2(32.5, 24)]
	var ctx := fixture(2, false, positions, "rivet_tank")
	for index in range(4): ctx.sim.entities[ctx.ids[index]].alpha = 0.0 if index < 2 else 180.0
	move(ctx, ctx.ids[0], Vector2(35, 24))
	move(ctx, ctx.ids[1], Vector2(38, 26))
	move(ctx, ctx.ids[2], Vector2(12, 24))
	move(ctx, ctx.ids[3], Vector2(12, 21))
	advance(ctx, 6.0)
	var expected: Array[int] = [ctx.ids[0], ctx.ids[1]]
	for index in [2, 3]:
		var id: int = ctx.ids[index]
		if kill:
			ctx.sim._kill_entity(id, false)
			check(not ctx.sim._path_requests.has(id) and not ctx.sim._planning_queue.has(id), "removed opposing root leaves no stale planner job")
		else:
			ctx.sim.issue([id], "stop", Vector2.ZERO)
			check(ctx.sim.entities[id].commands.is_empty() and not (ctx.sim.entities[id].get("yield_goal", Vector2.INF) as Vector2).is_finite(), "opposing stop clears current movement and yield")
			# Park both in their roomy home chamber after the actual stop command.
			move(ctx, id, Vector2(32+(index-2)*3, 19))
			expected.append(id)
	advance(ctx, 100.0, expected)
	finish(ctx, expected)

func two_approaches() -> void:
	var positions: Array[Vector2] = [Vector2(17, 18), Vector2(19, 20), Vector2(16, 21.5),
		Vector2(17, 30), Vector2(19, 28), Vector2(16, 26.5)]
	var ctx := fixture(2, false, positions, "rivet_tank")
	for index in range(6): move(ctx, ctx.ids[index], Vector2(34+(index%2)*3, 20+floorf(float(index)/2.0)*3))
	advance(ctx, 120.0, ctx.ids)
	check(ctx.sim._planning_max_wait < 5.0, "both merging approaches receive planner service")
	finish(ctx, ctx.ids)
