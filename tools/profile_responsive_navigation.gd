extends SceneTree

# Short headless diagnostic; coordinate the test window with other sessions.
# godot --headless --path . --script tools/profile_responsive_navigation.gd -- \
#   --units=256 --ticks=30 --case=all --output=/tmp/responsive-current.json
# Repeat with --baseline for a SAME-REVISION control disabling only responsive
# startup and friendly overlap. Wide-terrain and rail optimizations remain on.
# --script selects the GDScript backend. No render timing is included.
const Sim = preload("res://scripts/simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
const STEP: float = 1.0 / 30.0
var errors: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func options() -> Dictionary:
	var result: Dictionary = {"units": 96, "ticks": 30, "case": "all", "baseline": false, "script": false, "yield-us": 0, "max-wall-seconds": 20.0, "output": "/tmp/paper_war_responsive_navigation.json"}
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var index: int = 0
	while index < args.size():
		var argument: String = args[index]
		if argument.begins_with("--"):
			var parts: PackedStringArray = argument.substr(2).split("=", true, 1)
			var key: String = parts[0]
			if key in ["baseline", "script"]:
				result[key] = true
			elif result.has(key):
				if parts.size() > 1:
					result[key] = parts[1]
				elif index + 1 < args.size():
					index += 1
					result[key] = args[index]
			else:
				errors.append("Unknown option: " + key)
		index += 1
	result.units = int(result.units)
	result.ticks = clampi(int(result.ticks), 20, 40)
	result["yield-us"] = maxi(0, int(result["yield-us"]))
	result["max-wall-seconds"] = maxf(.1, float(result["max-wall-seconds"]))
	if int(result.units) not in [96, 256, 512]:
		errors.append("--units must be 96, 256, or 512")
	if str(result.case) not in ["all", "open", "gate", "rail"]:
		errors.append("--case must be all, open, gate, or rail")
	return result


func fixture(config: Dictionary, opts: Dictionary):
	var sim = Sim.new()
	var native_backend: bool = not bool(opts.script)
	sim.native_kernels_enabled = native_backend
	sim.native_unit_dispatch_enabled = native_backend
	sim.native_geometry_enabled = native_backend
	sim.native_movement_enabled = native_backend
	sim.responsive_navigation_enabled = not bool(opts.baseline)
	sim.crowd_overlap_enabled = not bool(opts.baseline)
	sim.setup(config.duplicate(true), "dev", 7, "iron", false)
	if sim._path_worker != null:
		sim._path_worker.close()
	for id: int in sim.entities.keys():
		sim._kill_entity(id, false)
	for z: int in range(int(sim.map.size)):
		for x: int in range(int(sim.map.size)):
			sim.map.terrain[z][x] = 0
			sim.map.heights[z][x] = 0.0
	sim.mines.clear()
	sim.bridges.clear()
	sim.ruins.clear()
	sim._refresh_mine_spatial()
	sim._refresh_ruin_spatial()
	var size: float = float(sim.map.size)
	sim._spawn(0, "iron_hq", Vector2(6, size - 6), true)
	sim._spawn(1, "kestrel_hq", Vector2(size - 6, size - 6), true)
	return sim


func finish_geometry(sim) -> void:
	sim._prepare_terrain_cache()
	sim._nav_initialized = false
	sim._rebuild_nav()
	sim._rebuild_spatial()


func quiet_unit(sim, spec: String, point: Vector2) -> int:
	# Direct spawn preserves the deliberately dense rail distribution instead
	# of relocating bodies through debug_spawn's ordinary standing search.
	var id: int = sim._spawn(0, spec, point, true)
	sim.entities[id].cooldown = 10000.0
	sim.entities[id].alpha = 145.0
	return id


func percentiles(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {"mean": 0.0, "p50": 0.0, "p95": 0.0, "max": 0.0}
	var ordered: Array[float] = values.duplicate()
	ordered.sort()
	var total: float = 0.0
	for value: float in values:
		total += value
	return {"mean": total / values.size(), "p50": ordered[mini(ordered.size() - 1, ceili(ordered.size() * .5) - 1)], "p95": ordered[mini(ordered.size() - 1, ceili(ordered.size() * .95) - 1)], "max": ordered.back()}


func latency_summary(observed: Dictionary, total: int) -> Dictionary:
	var first: Dictionary = {}
	var latest: Dictionary = {}
	for id in observed:
		var item: Dictionary = observed[id]
		if first.is_empty() or float(item.wall_ms) < float(first.wall_ms):
			first = item.duplicate()
			first.id = int(id)
		if latest.is_empty() or float(item.wall_ms) >= float(latest.wall_ms):
			latest = item.duplicate()
			latest.id = int(id)
	return {"observed_units": observed.size(), "total_units": total, "first": first if not first.is_empty() else null, "latest_observed": latest if not latest.is_empty() else null, "last_when_all_responded": latest if observed.size() == total and total > 0 else null}


func measure(sim, ids: Array[int], goal: Vector2, name: String, opts: Dictionary) -> Dictionary:
	var starts: Dictionary = {}
	for id: int in ids:
		starts[id] = {"pos": sim.entities[id].pos, "alpha": sim.entities[id].alpha}
	var command_sim_time: float = sim.time
	var command_started: int = Time.get_ticks_usec()
	sim.issue(ids, "move", goal)
	var command_finished: int = Time.get_ticks_usec()
	var responses: Dictionary = {}
	var movements: Dictionary = {}
	var tick_us: Array[float] = []
	var tick_rows: Array[Dictionary] = []
	var admin_us: int = 0
	var timed_out: bool = false
	for tick: int in range(int(opts.ticks)):
		if Time.get_ticks_usec() - command_started >= int(float(opts["max-wall-seconds"]) * 1000000.0):
			timed_out = true
			break
		var started: int = Time.get_ticks_usec()
		sim.step(STEP)
		var finished: int = Time.get_ticks_usec()
		tick_us.append(float(finished - started))
		admin_us += int(sim.navigation_stats.main_us)
		var moved: int = 0
		var turned: int = 0
		var waiting: int = 0
		for id: int in ids:
			var e: Dictionary = sim.entities[id]
			var displacement: float = (e.pos as Vector2).distance_to(starts[id].pos)
			var angle: float = absf(wrapf(float(e.alpha) - float(starts[id].alpha), -180.0, 180.0))
			var has_moved: bool = displacement > .0001
			var has_turned: bool = angle > .0001
			moved += 1 if has_moved else 0
			turned += 1 if has_turned else 0
			waiting += 1 if str(e.state) in ["waiting", "waiting_rail"] else 0
			var observation: Dictionary = {"tick": tick + 1, "simulation_ms": (sim.time - command_sim_time) * 1000.0, "wall_ms": float(finished - command_started) / 1000.0, "moved": has_moved, "turned": has_turned}
			if has_moved and not movements.has(id):
				movements[id] = observation
			if (has_moved or has_turned) and not responses.has(id):
				responses[id] = observation
		tick_rows.append({"tick": tick + 1, "tick_us": finished - started, "moved_units": moved, "turned_units": turned, "waiting_units": waiting, "submitted": int(sim.navigation_stats.submitted), "completed": int(sim.navigation_stats.completed), "queued": sim._planning_queue.size(), "in_flight": sim._path_in_flight})
		sim.events.clear()
		if int(opts["yield-us"]) > 0:
			OS.delay_usec(int(opts["yield-us"]))
	var report: Dictionary = {"case": name, "units": ids.size(), "map_size": int(sim.map.size), "command_us": command_finished - command_started, "ticks_observed": tick_rows.size(), "timed_out": timed_out, "simulation_tick_us": percentiles(tick_us), "path_admin_us_total": admin_us, "response_latency": latency_summary(responses, ids.size()), "movement_latency": latency_summary(movements, ids.size()), "navigation": sim.navigation_stats.duplicate(), "ticks": tick_rows}
	if timed_out:
		errors.append(name + " exceeded its wall-clock deadline")
	if sim._path_worker != null:
		sim._path_worker.close()
	return report


func ground_case(config: Dictionary, opts: Dictionary, gate: bool) -> Dictionary:
	var sim = fixture(config, opts)
	var size: int = int(sim.map.size)
	if gate:
		# A six-metre opening is legal for the real infantry radius. Starting
		# units occupy both sides of its approach, so some require worker detours.
		for z: int in range(size):
			if z >= size / 2 - 3 and z < size / 2 + 3:
				continue
			for x: int in [size / 2 - 1, size / 2]:
				sim.map.terrain[z][x] = 4
	finish_geometry(sim)
	var ids: Array[int] = []
	var columns: int = 16
	var count_rows: int = ceili(float(opts.units) / columns)
	var first_x: float = float(size) * .5 - 1.6 - float(columns - 1) * 1.12
	var first_z: float = float(size) * .5 - float(count_rows - 1) * 1.12 * .5
	for index: int in range(int(opts.units)):
		ids.append(quiet_unit(sim, "iron_rifle", Vector2(first_x + float(index % columns) * 1.12, first_z + float(index / columns) * 1.12)))
	sim._rebuild_spatial()
	return measure(sim, ids, Vector2(float(size) * .75, float(size) * .5), "gate" if gate else "open", opts)


func rail_case(config: Dictionary, opts: Dictionary) -> Dictionary:
	var sim = fixture(config, opts)
	var size: int = int(sim.map.size)
	var track_z: float = floorf(float(size) * .5) + .5
	for x: int in range(12, size - 12):
		sim._spawn(0, "iron_rail", Vector2(x + .5, track_z), true)
	sim._rail_network.rebuild(sim)
	finish_geometry(sim)
	var ids: Array[int] = []
	for index: int in range(int(opts.units)):
		ids.append(quiet_unit(sim, "iron_train", Vector2(14.5 + float(index % 24), track_z)))
	sim._rebuild_spatial()
	return measure(sim, ids, Vector2(float(size - 15) + .5, track_z), "rail", opts)


func run() -> void:
	var opts: Dictionary = options()
	var config: Dictionary = Rules.load_rules()
	if config.is_empty():
		errors.append("Gameplay rules are unavailable: " + str(Rules.errors))
	if not bool(opts.script) and not ClassDB.class_exists("PaperFrontKernels"):
		errors.append("Native backend unavailable; use --script explicitly for the script control")
	var cases: Array[Dictionary] = []
	if errors.is_empty():
		if str(opts.case) in ["all", "open"]:
			cases.append(ground_case(config, opts, false))
		if str(opts.case) in ["all", "gate"]:
			cases.append(ground_case(config, opts, true))
		if str(opts.case) in ["all", "rail"]:
			cases.append(rail_case(config, opts))
	var report: Dictionary = {"schema": 1, "comparison": "same_revision_responsive_and_overlap_flags_disabled" if bool(opts.baseline) else "current_responsive_and_overlap_enabled", "baseline_scope": "Only responsive_navigation_enabled and crowd_overlap_enabled are disabled; current terrain, worker, native and rail changes are retained.", "backend": "script" if bool(opts.script) else "native", "render_timing_included": false, "latency_clock": "Wall latency starts before issue(); simulation latency starts at the current simulation time. Turn or displacement counts as a response; displacement is also reported separately. A missing all-units last response is null, not zero.", "timing_scope": "Tick duration measures sim.step() only. Fixture setup, per-unit observation, optional yielding, JSON output, and worker shutdown are outside tick samples.", "options": opts, "errors": errors, "cases": cases}
	var destination: String = str(opts.output)
	var file = FileAccess.open(destination, FileAccess.WRITE)
	if file == null:
		errors.append("Cannot write output: " + destination)
	else:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	print("RESPONSIVE_NAVIGATION_PROFILE ", JSON.stringify(report))
	for message: String in errors:
		push_error(message)
	quit(0 if errors.is_empty() else 1)
