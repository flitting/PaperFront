extends "res://tools/profile_navigation_throughput.gd"

# Lightweight correctness controls use the real asynchronous simulation path
# queue. The 448-unit handmade seed-73026 pressure case lives in the parent
# profiler; run both only after coordinating with other active test sessions.
#   godot --headless --path . --script tests/path_throughput_tests.gd -- \
#     --output=/tmp/path-throughput-tests.json --max-wall-seconds=10

var checks: int = 0
var failures: Array[String] = []
var cases: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run_tests")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _flat_fixture(config: Dictionary, options: Dictionary):
	var sim = _new_sim(config,"dev",7,options)
	if sim == null: return null
	for z in range(48):
		for x in range(48):
			sim.map.terrain[z][x] = 0
			sim.map.heights[z][x] = 0.0
	sim.mines.clear()
	sim.bridges.clear()
	sim.ruins.clear()
	sim._refresh_ruin_spatial()
	for id in sim.entities.keys(): sim._kill_entity(id,false)
	sim.debug_spawn(0,"rivet_hq",Vector2(4,44))
	sim.debug_spawn(1,"kestrel_hq",Vector2(44,44))
	sim._prepare_terrain_cache()
	sim._nav_initialized = false
	sim._rebuild_nav()
	sim._rebuild_spatial()
	return sim

func _cliff_batch(config: Dictionary, options: Dictionary) -> void:
	var sim = _flat_fixture(config,options)
	if sim == null: return
	# A raised outcrop has legal flat endpoints on both sides. Its vertical
	# two-metre cliffs force a genuine detour around the plateau.
	for z in range(10,34):
		for x in range(22,29): sim.map.heights[z][x] = 2.0
	sim._prepare_terrain_cache()
	sim._nav_initialized = false
	sim._rebuild_nav()
	var ids: Array = []
	for index in range(48):
		ids.append(sim.debug_spawn(0,"rivet_engineer",Vector2(5.5+(index%8)*1.15,13.5+(index/8)*1.15)))
	var started: int = Time.get_ticks_usec()
	sim.issue(ids,"move",Vector2(37,16))
	var report: Dictionary = _run_case(sim,ids,started,options)
	report.case = "48_unit_same_command_cliff_detour"
	check(int(report.commanded_units)==48,"one selection command orders every one of 48 real units")
	check(int(report.observed_paths)==48,"every unit receives a visible path before the bounded fixture deadline")
	check(int(report.navigation.completed)>=48,"real background worker completes the whole command burst")
	check(int(report.safety.checked)==48 and int(report.safety.unsafe)==0,"all 48 worker routes retain swept footprint and cliff clearance")
	check(int(report.safety.detours)==48,"all 48 paths detour around the raised cliff instead of crossing it")
	check(int(report.max_in_flight)<=int(report.in_flight_limit),"actual asynchronous submissions respect the simulator in-flight bound")
	check(int(report.progress.moved_over_1m)>0,"movement advances while the command batch is being planned")
	cases.append(report)
	sim._path_worker.close()
	sim = null

func _bridge_detour(config: Dictionary, options: Dictionary) -> void:
	var sim = _new_sim(config,"dev",7,options)
	if sim == null: return
	var ids: Array = []
	for index in range(12):
		ids.append(sim.debug_spawn(0,"rivet_engineer",Vector2(15.5+(index%4)*1.2,28.5+(index/4)*1.2)))
	var bridge: Dictionary = sim.bridges[0]
	bridge.alive = false
	bridge.hp = 0.0
	sim._mark_nav_region(Rect2(bridge.bounds[0],bridge.bounds[1],bridge.bounds[2],bridge.bounds[3]))
	sim._rebuild_nav()
	var started: int = Time.get_ticks_usec()
	sim.issue(ids,"move",Vector2(34,30.5))
	var report: Dictionary = _run_case(sim,ids,started,options)
	report.case = "destroyed_bridge_permanent_land_detour"
	check(int(report.observed_paths)==ids.size(),"destroyed-bridge shore units all receive a background detour")
	check(int(report.safety.checked)==ids.size() and int(report.safety.unsafe)==0,"destroyed bridge routes remain clear of water and the disabled deck")
	check(int(report.safety.detours)==ids.size(),"shore routes bend around the river after bridge destruction")
	check(not bool(bridge.alive),"path planning retains the destroyed bridge state")
	check(int(report.progress.moved_over_1m)>0,"shore units make progress along the permanent land route")
	cases.append(report)
	sim._path_worker.close()
	sim = null

func _cancel_in_flight(config: Dictionary, options: Dictionary) -> void:
	var sim = _flat_fixture(config,options)
	if sim == null: return
	var unit: int = sim.debug_spawn(0,"rivet_tank",Vector2(7,17))
	sim.debug_spawn(0,"rivet_power",Vector2(24,17))
	sim._rebuild_nav()
	sim.issue([unit],"move",Vector2(39,17))
	var submission_deadline: int = Time.get_ticks_usec()+int(float(options["max-wall-seconds"])*1000000.0)
	while int(sim.navigation_stats.submitted)==0 and Time.get_ticks_usec()<submission_deadline:
		sim.step(STEP)
		if int(sim.navigation_stats.submitted)==0: OS.delay_usec(int(options["yield-us"]))
	check(int(sim.navigation_stats.submitted)>0,"cancellation control submits a real asynchronous obstacle route")
	sim.issue([unit],"stop",Vector2.ZERO)
	var origin: Vector2 = sim.entities[unit].pos
	var started: int = Time.get_ticks_usec()
	var ticks: int = 0
	while int(sim.navigation_stats.discarded)==0 and Time.get_ticks_usec()-started < int(float(options["max-wall-seconds"])*1000000.0):
		sim.step(STEP)
		sim.events.clear()
		ticks += 1
		OS.delay_usec(int(options["yield-us"]))
	check(int(sim.navigation_stats.discarded)>0,"stop discards the obsolete background token once its real route completes")
	check(sim.entities[unit].commands.is_empty() and sim.entities[unit].path.is_empty() and sim.entities[unit].pos==origin,"a stale result cannot restart a stopped unit")
	cases.append({"case":"cancel_in_flight","ticks":ticks,"navigation":sim.navigation_stats.duplicate()})
	sim._path_worker.close()
	sim = null

func _tank_building_clearance(config: Dictionary, options: Dictionary) -> void:
	var sim = _flat_fixture(config,options)
	if sim == null: return
	sim.debug_spawn(0,"rivet_power",Vector2(24.25,17.25))
	sim._rebuild_nav()
	var ids: Array = []
	for index in range(8):
		ids.append(sim.debug_spawn(0,"rivet_tank",Vector2(14.5-(index%2)*2.0,11.5+(index/2)*3.0)))
	var started: int = Time.get_ticks_usec()
	sim.issue(ids,"move",Vector2(36.25,17.25))
	var report: Dictionary = _run_case(sim,ids,started,options)
	report.case = "tank_offset_building_clearance"
	check(int(report.observed_paths)==ids.size(),"large-radius vehicles all receive routes around a non-grid-aligned building")
	check(int(report.safety.checked)==ids.size() and int(report.safety.unsafe)==0,"vehicle paths retain real radius plus clearance at rounded building corners")
	check(int(report.safety.detours)>0,"the offset-building control exercises an actual obstacle detour")
	cases.append(report)
	sim._path_worker.close()
	sim = null

func run_tests() -> void:
	var options: Dictionary = _options()
	options.ticks = mini(int(options.ticks),240)
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var has_output: bool = false
	var has_deadline: bool = false
	for argument in arguments:
		has_output = has_output or argument.begins_with("--output")
		has_deadline = has_deadline or argument.begins_with("--max-wall-seconds")
	if not has_output:
		options.output = "/tmp/paper_war_path_throughput_tests.json"
	if not has_deadline:
		options["max-wall-seconds"] = 10.0
	var config: Dictionary = Rules.load_rules()
	if config.is_empty():
		push_error("Path throughput test rules invalid: "+str(Rules.errors))
		quit(2)
		return
	_cliff_batch(config,options)
	_bridge_detour(config,options)
	_tank_building_clearance(config,options)
	_cancel_in_flight(config,options)
	for error in errors: failures.append(error)
	check(checks>0,"the asynchronous throughput regression fixtures execute checks")
	var report: Dictionary = {"schema":1,"checks":checks,"passed":checks-failures.size(),"failures":failures,"cases":cases,"options":options}
	var written: bool = _write_report(str(options.output),report)
	print("PATH_THROUGHPUT ",JSON.stringify(report))
	for failure in failures: push_error(failure)
	quit(0 if written and failures.is_empty() else 1)
