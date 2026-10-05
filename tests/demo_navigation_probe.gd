extends SceneTree

## Functional reproduction of the historical 96-tank narrow corridor.
## Uses the live asynchronous simulator, with a documented worker yield.
## Run headless; this probe makes no GPU or real-time FPS claim.
const Sim = preload("res://scripts/simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
class YieldTraceSim:
	extends "res://scripts/simulation.gd"
	var yield_metrics: Dictionary={"assigned":0,"reassigned_after_release":0,"arrived":0,"expired":0,"propagation_assigned":0,"same_direction_assigned":0,"opposing_direction_assigned":0,"same_primary_route_assigned":0,"opposing_primary_route_assigned":0,"retreat_projected_primary_m":0.0,"retreat_increasing_command_distance_m":0.0,"retreat_increasing_gate_distance_m":0.0}
	var yield_units: Dictionary={}
	var primary_directions: Dictionary={}
	var yield_tail: Array[Dictionary]=[]
	func unit_metrics(id: int) -> Dictionary:
		if not yield_units.has(id):yield_units[id]={"assigned":0,"arrived":0,"expired":0,"retreat_projected_primary_m":0.0,"retreat_increasing_command_distance_m":0.0,"retreat_increasing_gate_distance_m":0.0}
		return yield_units[id]
	func append_trace(row: Dictionary) -> void:
		if yield_tail.size()>=512:yield_tail.pop_front()
		yield_tail.append(row)
	func _request_movement_yield(e: Dictionary, other: Dictionary, start: Vector2, next: Vector2) -> void:
		var before: Vector2=other.get("yield_goal",Vector2.INF)
		super._request_movement_yield(e,other,start,next)
		var after: Vector2=other.get("yield_goal",Vector2.INF)
		if before==after:return
		var counts: Dictionary=unit_metrics(int(other.id))
		if int(counts.assigned)>0:yield_metrics.reassigned_after_release+=1
		counts.assigned+=1
		yield_metrics.assigned+=1
		var forward: Vector2=(next-start).normalized()
		var primary: Vector2=primary_directions.get(int(other.id),Vector2.ZERO)
		var requester_primary: Vector2=primary_directions.get(int(e.id),Vector2.ZERO)
		var route_alignment: float=requester_primary.dot(primary)
		if route_alignment>.5:yield_metrics.same_primary_route_assigned+=1
		if route_alignment<-.5:yield_metrics.opposing_primary_route_assigned+=1
		var alignment: float=forward.dot(primary)
		if alignment>.5:yield_metrics.same_direction_assigned+=1
		if alignment<-.5:yield_metrics.opposing_direction_assigned+=1
		var propagation: bool=(e.get("yield_goal",Vector2.INF) as Vector2).is_finite()
		if propagation:yield_metrics.propagation_assigned+=1
		append_trace({"event":"assigned","time":time,"requester":e.id,"other":other.id,"requester_pos":str(e.pos),"other_pos":str(other.pos),"goal":str(after),"expires":other.get("yield_until",0.0),"forward":str(forward),"other_primary":str(primary),"alignment":alignment,"requester_primary":str(requester_primary),"route_alignment":route_alignment,"propagation":propagation})
	func step(delta: float) -> void:
		var active: Array[Dictionary]=[]
		for entity in entities.values():
			if entity.kind!="unit":continue
			var before: Vector2=entity.get("yield_goal",Vector2.INF)
			if not before.is_finite() and not entity.path.is_empty():
				primary_directions[int(entity.id)]=(entity.path[0] as Vector2)-entity.pos
				primary_directions[int(entity.id)]=(primary_directions[int(entity.id)] as Vector2).normalized()
			if before.is_finite():active.append({"id":entity.id,"pos":entity.pos,"yield_goal":before,"expires":float(entity.get("yield_until",0.0)),"command_goal":entity.commands[0].get("pos",Vector2.INF) if not entity.commands.is_empty() else Vector2.INF})
		super.step(delta)
		for old in active:
			var entity: Dictionary=entities.get(old.id,{})
			if entity.is_empty():continue
			var counts: Dictionary=unit_metrics(int(old.id))
			var displacement: Vector2=(entity.pos as Vector2)-(old.pos as Vector2)
			var primary: Vector2=primary_directions.get(int(old.id),Vector2.ZERO)
			var retreat: float=maxf(0,-displacement.dot(primary))
			counts.retreat_projected_primary_m+=retreat
			yield_metrics.retreat_projected_primary_m+=retreat
			if (old.command_goal as Vector2).is_finite():
				retreat=maxf(0,(entity.pos as Vector2).distance_to(old.command_goal)-(old.pos as Vector2).distance_to(old.command_goal))
				counts.retreat_increasing_command_distance_m+=retreat
				yield_metrics.retreat_increasing_command_distance_m+=retreat
			if float(old.pos.x)<21:
				retreat=maxf(0,(entity.pos as Vector2).distance_to(Vector2(20,24))-(old.pos as Vector2).distance_to(Vector2(20,24)))
				counts.retreat_increasing_gate_distance_m+=retreat
				yield_metrics.retreat_increasing_gate_distance_m+=retreat
			if not (entity.get("yield_goal",Vector2.INF) as Vector2).is_finite():
				var event: String="expired" if time>=old.expires else "arrived"
				counts[event]+=1
				yield_metrics[event]+=1
				append_trace({"event":event,"time":time,"id":old.id,"pos":str(entity.pos),"goal":str(old.yield_goal),"expires":old.expires})
const STEP := 1.0 / 30.0
const COUNT := 96
const SEED := 7
const COLLISION_SAMPLE_TICKS := 10
var output := "res://artifacts/demo_20261004/navigation/narrow_96_current.json"
var limit_seconds := 600.0
var worker_yield_us := 1000
var unit_count := COUNT
var geometry_only := false
var trace_yields := false
var rows: Array[Dictionary] = []
var failures: Array[String] = []
var cleared: Dictionary = {}
var completed: Dictionary = {}
var waiting_seconds: Dictionary = {}
var still_seconds: Dictionary = {}
var last_positions: Dictionary = {}
var maximum_waiting_seconds := 0.0
var maximum_still_seconds := 0.0
var maximum_planning_wait := 0.0
var maximum_queue := 0
var maximum_in_flight := 0
var overlap_pair_samples := 0
var margin_pair_samples := 0
var static_violation_samples := 0
var collision_sample_count := 0
var maximum_overlap_depth := 0.0
var overlap_pairs: Dictionary = {}
var events: Dictionary = {}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	geometry_only = "--geometry-only" in args
	trace_yields = "--trace-yields" in args
	for index in range(args.size() - 1):
		if args[index] == "--output": output = args[index + 1]
		elif args[index] == "--seconds": limit_seconds = float(args[index + 1])
		elif args[index] == "--yield-us": worker_yield_us = int(args[index + 1])
		elif args[index] == "--count": unit_count = int(args[index + 1])
	if DisplayServer.get_name() != "headless" or limit_seconds <= 0.0 or worker_yield_us < 1 or unit_count < 1 or unit_count > COUNT:
		push_error("Navigation probe requires headless, positive duration and a real worker yield")
		quit(2)
		return
	call_deferred("run")

func run() -> void:
	var rules: Dictionary = Rules.load_rules()
	if rules.is_empty():
		push_error("Navigation fixture rules invalid: " + str(Rules.errors))
		quit(2)
		return
	var setup_start := Time.get_ticks_usec()
	var sim = YieldTraceSim.new() if trace_yields else Sim.new()
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
	for z in range(48):
		if z in [23, 24]: continue
		for x in range(21, 27): sim.map.terrain[z][x] = 4
	sim._prepare_terrain_cache()
	sim._nav_initialized = false
	sim._rebuild_nav()
	var ids: Array[int] = []
	for index in range(unit_count):
		var position := Vector2(4 + (index % 8) * 1.9, 8 + (index / 8) * 1.9)
		var id: int = sim.debug_spawn(0, "rivet_tank", position)
		if id < 0: failures.append("Could not spawn historical tank " + str(index))
		else:
			ids.append(id)
			last_positions[id] = sim.entities[id].pos
	if ids.size() != unit_count: failures.append("Fixture does not contain the requested tanks")
	sim._rebuild_spatial()
	sim.issue(ids, "move", Vector2(38, 24))
	var command_goals: Dictionary = {}
	var actual_starts: Dictionary = {}
	for id in ids:
		actual_starts[str(id)] = point(sim.entities[id].pos)
		if sim.entities[id].commands.is_empty(): failures.append("Tank received no movement command: " + str(id))
		else: command_goals[str(id)] = point(sim.entities[id].commands[0].pos)
	var setup_ms := float(Time.get_ticks_usec() - setup_start) / 1000.0
	var run_start := Time.get_ticks_usec()
	var tick_count := 0
	var unreachable_unit_ticks := 0
	var tick_max_us := 0
	var tick_total_us := 0
	var path_at_start: Dictionary = sim.navigation_stats.duplicate()
	var geometry: Array[Dictionary] = []
	for position in [Vector2(24, 23.5), Vector2(24, 24), Vector2(24, 24.5)]:
		var nearby_nodes: Array[Dictionary] = []
		for z in [23, 24]:
			var node_id: int = int(z) * 48 + 24
			nearby_nodes.append({"id": node_id, "has_node": sim._nav.has_point(node_id),
				"point": point(sim._nav.get_point_position(node_id)) if sim._nav.has_point(node_id) else null,
				"tank_radius_mask_disabled": sim._terrain_masks[snappedf(float(rules.units.rivet_tank.radius), 0.01)].has(node_id)})
		geometry.append({"position": point(position), "static_standing_legal": sim._standing(position, float(rules.units.rivet_tank.radius), -1, false),
			"terrain_clear_legal": sim._terrain_clear(position, float(rules.units.rivet_tank.radius)), "nearby_existing_nodes": nearby_nodes})
	rows.append(snapshot(sim, ids, 0.0))
	print("DEMO_NAV_READY count=", ids.size(), " radius=", rules.units.rivet_tank.radius, " yield_us=", worker_yield_us)
	for tick in range(0 if geometry_only else roundi(limit_seconds * 30.0)):
		var tick_start := Time.get_ticks_usec()
		sim.step(STEP)
		var tick_us := Time.get_ticks_usec() - tick_start
		tick_max_us = maxi(tick_max_us, tick_us)
		tick_total_us += tick_us
		tick_count = tick + 1
		for event in sim.events: events[str(event.kind)] = int(events.get(str(event.kind), 0)) + 1
		sim.events.clear()
		maximum_queue = maxi(maximum_queue, sim._planning_queue.size())
		maximum_in_flight = maxi(maximum_in_flight, sim._path_in_flight)
		maximum_planning_wait = maxf(maximum_planning_wait, float(sim._planning_max_wait))
		for id in ids:
			if not sim.entities.has(id):
				if not failures.has("Tank died unexpectedly: " + str(id)): failures.append("Tank died unexpectedly: " + str(id))
				continue
			var e: Dictionary = sim.entities[id]
			if e.pos.x > 27.95: cleared[id] = true
			if cleared.has(id) and e.commands.is_empty(): completed[id] = true
			if e.state == "unreachable": unreachable_unit_ticks += 1
			var pending: bool = not e.commands.is_empty()
			waiting_seconds[id] = float(waiting_seconds.get(id, 0.0)) + STEP if pending and e.state == "waiting" else 0.0
			still_seconds[id] = float(still_seconds.get(id, 0.0)) + STEP if pending and (e.pos as Vector2).distance_squared_to(last_positions[id]) < 0.00000001 else 0.0
			last_positions[id] = e.pos
			maximum_waiting_seconds = maxf(maximum_waiting_seconds, waiting_seconds[id])
			maximum_still_seconds = maxf(maximum_still_seconds, still_seconds[id])
		if tick % COLLISION_SAMPLE_TICKS == 0: sample_collisions(sim, ids)
		OS.delay_usec(worker_yield_us)
		if tick_count % 300 == 0:
			var row := snapshot(sim, ids, float(Time.get_ticks_usec() - run_start) / 1000000.0)
			rows.append(row)
			print("DEMO_NAV_PROGRESS ", JSON.stringify(row))
		if not sim.result.is_empty():
			failures.append("Fixture ended before its duration: " + sim.result)
			break
		if completed.size() == unit_count: break
	var wall_seconds := float(Time.get_ticks_usec() - run_start) / 1000000.0
	var final_row := snapshot(sim, ids, wall_seconds)
	rows.append(final_row)
	var remaining: Array[Dictionary] = []
	for id in ids:
		if completed.has(id) or not sim.entities.has(id): continue
		var e: Dictionary = sim.entities[id]
		var route: Array = []
		for position in e.path: route.append(point(position))
		remaining.append({"id": id, "pos": point(e.pos), "state": e.state, "commands": clean_commands(e.commands), "path": route,
			"path_wait": e.get("path_wait", 0.0), "planning_wait": e.get("planning_wait", 0.0), "stuck": e.get("stuck", 0.0),
			"alpha":e.alpha,"reversing":e.get("reversing",false),"yield_until":e.get("yield_until",0.0),"yield_goal": point(e.get("yield_goal", Vector2.INF)), "movement_retry_at": e.get("movement_retry_at", 0.0), "cleared": cleared.has(id)})
	var hashes: Dictionary = {}
	for path in ["res://tests/demo_navigation_probe.gd", "res://scripts/simulation.gd", "res://scripts/path_worker.gd", "res://scripts/path_graph.gd", "res://data/rules.json", "res://assets/native/libpaper_front_kernels.so"]:
		if FileAccess.file_exists(path): hashes[path] = FileAccess.get_sha256(path)
	var report := {"schema": 1, "fixture": "historical one-way rivet_tank, 48x48 flat map, 6-cell-long x21..26 barrier with z23..24 opening; default96, small-test prefix permitted",
		"scope": "static geometry diagnosis only" if geometry_only else "functional headless accelerated simulation with real asynchronous worker; no FPS or GPU performance claim", "seed": SEED,
		"corridor_geometry": geometry,
		"unit_count": ids.size(), "radius": rules.units.rivet_tank.radius, "requested_sim_seconds": limit_seconds, "sim_seconds": sim.time,
		"wall_seconds": wall_seconds, "setup_ms": setup_ms, "tick_count": tick_count, "worker_yield_us_per_tick": worker_yield_us,
		"tick_cpu_mean_ms": float(tick_total_us) / maxi(1, tick_count) / 1000.0, "tick_cpu_max_ms": float(tick_max_us) / 1000.0,
		"cleared_count": cleared.size(), "completed_count": completed.size(), "unreachable_unit_ticks": unreachable_unit_ticks,
		"maximum_contiguous_waiting_sim_seconds": maximum_waiting_seconds, "maximum_contiguous_no_translation_pending_sim_seconds": maximum_still_seconds,
		"maximum_planning_wait_sim_seconds": maximum_planning_wait, "maximum_path_queue": maximum_queue, "maximum_path_in_flight": maximum_in_flight,
		"navigation_at_start": path_at_start, "navigation_at_end": sim.navigation_stats.duplicate(), "remaining": remaining, "events": events,
		"collision_sampling_every_sim_ticks": COLLISION_SAMPLE_TICKS, "collision_sample_count": collision_sample_count,
		"geometric_overlap_pair_samples": overlap_pair_samples, "safety_margin_pair_samples": margin_pair_samples,
		"maximum_geometric_overlap_depth_m": maximum_overlap_depth, "overlap_pairs": overlap_pairs.keys(), "static_clearance_violation_unit_samples": static_violation_samples,
		"actual_starts": actual_starts, "command_goals": command_goals, "rows": rows, "failures": failures,
		"native_available": sim._kernels != null, "native_dispatch": sim.native_kernels_enabled and sim.native_unit_dispatch_enabled and sim._kernels != null,
		"yield_trace_enabled":trace_yields,"yield_metrics":sim.yield_metrics if trace_yields else {},"yield_unit_metrics":sim.yield_units if trace_yields else {},"yield_tail":sim.yield_tail if trace_yields else [],
		"synchronous_test_adapter": sim.synchronous_path_tests, "source_hashes": hashes, "godot": Engine.get_version_info().string}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write navigation report: " + output)
		sim = null
		quit(2)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("DEMO_NAV_RESULT cleared=", cleared.size(), "/", unit_count, " completed=", completed.size(), "/", unit_count, " wall_s=", wall_seconds, " sim_s=", sim.time,
		" overlaps=", overlap_pair_samples, " static=", static_violation_samples, " output=", output)
	for failure in failures: push_error(failure)
	# Join the actual worker explicitly before process exit.
	sim = null
	quit(0 if failures.is_empty() and (geometry_only or completed.size() == unit_count) and overlap_pair_samples == 0 and static_violation_samples == 0 else 1)

func point(value: Vector2) -> Variant:
	return [value.x, value.y] if value.is_finite() else null

func clean_commands(commands: Array) -> Array:
	var answer: Array = []
	for command in commands:
		var item: Dictionary = command.duplicate()
		if item.get("pos") is Vector2: item.pos = point(item.pos)
		answer.append(item)
	return answer

func snapshot(sim, ids: Array[int], wall_seconds: float) -> Dictionary:
	var states: Dictionary = {}
	var command_pending := 0
	for id in ids:
		if not sim.entities.has(id): continue
		var e: Dictionary = sim.entities[id]
		states[e.state] = int(states.get(e.state, 0)) + 1
		if not e.commands.is_empty(): command_pending += 1
	return {"sim_seconds": sim.time, "wall_seconds": wall_seconds, "cleared": cleared.size(), "completed": completed.size(),
		"command_pending": command_pending, "states": states, "queue": sim._planning_queue.size(), "in_flight": sim._path_in_flight,
		"path_requests": sim._path_requests.size(), "navigation": sim.navigation_stats.duplicate()}

func sample_collisions(sim, ids: Array[int]) -> void:
	collision_sample_count += 1
	for index in range(ids.size()):
		if not sim.entities.has(ids[index]): continue
		var e: Dictionary = sim.entities[ids[index]]
		if not sim._standing(e.pos, float(e.radius), int(e.id), false): static_violation_samples += 1
		for other_index in range(index + 1, ids.size()):
			if not sim.entities.has(ids[other_index]): continue
			var other: Dictionary = sim.entities[ids[other_index]]
			var separation: float = (e.pos as Vector2).distance_to(other.pos)
			var radius_sum := float(e.radius) + float(other.radius)
			if separation < radius_sum + 0.019: margin_pair_samples += 1
			if separation < radius_sum - 0.001:
				overlap_pair_samples += 1
				maximum_overlap_depth = maxf(maximum_overlap_depth, radius_sum - separation)
				overlap_pairs[str(e.id) + ":" + str(other.id)] = true
