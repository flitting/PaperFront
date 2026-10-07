extends SceneTree

# Coordinate all Godot runs with other sessions. Run this once against the
# unchanged idle controller, then after the phase fix for a controlled repro.
const Sim = preload("res://tests/rule_test_simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
const AirNavigation = preload("res://scripts/air_navigation.gd")
const STEP: float = 1.0 / 30.0
var rules: Dictionary = {}
var checks: int = 0
var failures: Array[String] = []
var rows: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func fixture(native_backend: bool):
	var sim = Sim.new()
	sim.native_kernels_enabled = native_backend
	sim.native_unit_dispatch_enabled = native_backend
	sim.native_geometry_enabled = native_backend
	sim.native_movement_enabled = native_backend
	sim.setup(rules.duplicate(true), "dev", 7, "rivet", false)
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
	sim._spawn(0, "rivet_hq", Vector2(5, 43), true)
	sim._spawn(1, "kestrel_hq", Vector2(43, 43), true)
	sim._prepare_terrain_cache()
	sim._nav_initialized = false
	sim._rebuild_nav()
	sim._rebuild_spatial()
	return sim


func aircraft(sim, spec: String, point: Vector2) -> int:
	var id: int = sim._spawn(0, spec, point, true)
	sim.entities[id].cooldown = 100000.0
	return id


func loiterer(sim, center: Vector2, phase: float) -> int:
	var id: int = int(sim._next_id)
	var radius: float = 3.4 + float(id % 3) * .6
	id = aircraft(sim, "sky_recon", center + Vector2.from_angle(phase) * radius)
	var e: Dictionary = sim.entities[id]
	e.loiter_center = center
	e.loiter_phase = phase
	e.alpha = rad_to_deg(phase + PI * .5)
	return id


func swept_distance(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	# Independent closest approach of two linearly moving circles, including
	# contacts between clear frame endpoints.
	var relative: Vector2 = a - c
	var movement: Vector2 = (b - a) - (d - c)
	var fraction: float = 0.0 if movement.length_squared() < .000001 else clampf(-relative.dot(movement) / movement.length_squared(), 0.0, 1.0)
	return (relative + movement * fraction).length()


func observe_loiter(sim, movers: Array[int], all_air: Array[int], frames: int) -> Dictionary:
	var angles: Dictionary = {}
	var phases: Dictionary = {}
	var windows: Dictionary = {}
	var window_start: Dictionary = {}
	var opposite: Dictionary = {}
	var safe: bool = true
	var minimum_clearance: float = INF
	for id: int in movers:
		angles[id] = 0.0
		phases[id] = float(sim.entities[id].loiter_phase)
		windows[id] = []
		window_start[id] = 0.0
		opposite[id] = false
	for frame: int in range(frames):
		var before: Dictionary = {}
		for id: int in all_air:
			before[id] = sim.entities[id].pos
		sim.step(STEP)
		sim.events.clear()
		for first: int in all_air:
			for second: int in all_air:
				if second <= first:
					continue
				var required: float = sim._radius(sim.entities[first]) + sim._radius(sim.entities[second]) + AirNavigation.CLEARANCE
				var clearance: float = swept_distance(before[first], sim.entities[first].pos, before[second], sim.entities[second].pos) - required
				minimum_clearance = minf(minimum_clearance, clearance)
				safe = safe and clearance >= -.0002
		for id: int in movers:
			var e: Dictionary = sim.entities[id]
			var center: Vector2 = e.loiter_center
			var old_angle: float = ((before[id] as Vector2) - center).angle()
			var new_angle: float = ((e.pos as Vector2) - center).angle()
			angles[id] = float(angles[id]) + wrapf(new_angle - old_angle, -PI, PI)
			opposite[id] = bool(opposite[id]) or (e.pos as Vector2).x < center.x - 1.0
			if (frame + 1) % 60 == 0:
				windows[id].append(float(angles[id]) - float(window_start[id]))
				window_start[id] = angles[id]
	var records: Array[Dictionary] = []
	for id: int in movers:
		var e: Dictionary = sim.entities[id]
		records.append({"id": id, "actual_angle_progress": angles[id], "phase_change": float(e.loiter_phase) - float(phases[id]), "window_angle_progress": windows[id], "visited_opposite_side": opposite[id], "position": str(e.pos)})
	return {"safe": safe, "minimum_clearance_margin": minimum_clearance, "aircraft": records}


func blocked_loiter(native_backend: bool) -> void:
	var sim = fixture(native_backend)
	var center := Vector2(24, 24)
	var id: int = loiterer(sim, center, 0.0)
	var radius: float = 3.4 + float(id % 3) * .6
	# Even the smallest real orbit has >2.02m initial separation at .75rad.
	var blocker: int = aircraft(sim, "rivet_helicopter", center + Vector2.from_angle(.75) * radius)
	var blocker_origin: Vector2 = sim.entities[blocker].pos
	check((sim.entities[id].pos as Vector2).distance_to(blocker_origin) > sim._radius(sim.entities[id]) + sim._radius(sim.entities[blocker]) + AirNavigation.CLEARANCE, "blocked orbit starts with legal separate airspace")
	var result: Dictionary = observe_loiter(sim, [id], [id, blocker], 240)
	var record: Dictionary = result.aircraft[0]
	check(bool(result.safe), "idle orbit retains full continuous swept separation around a hovering blocker native=" + str(native_backend))
	check(float(record.actual_angle_progress) > PI and bool(record.visited_opposite_side), "idle aircraft actually passes the blocked orbit sector and reaches the far side native=" + str(native_backend))
	var windows: Array = record.window_angle_progress
	check(float(windows[2]) > .2 and float(windows[3]) > .2, "later two-second windows retain actual angular progress instead of local trembling native=" + str(native_backend))
	check(sim.entities[blocker].pos == blocker_origin and sim.entities[id].commands.is_empty(), "hovering traffic stays stationary while idle flight retains control")
	result.case = "hover_blocked_idle_orbit"
	result.native = native_backend
	rows.append(result)


func shared_loiter(native_backend: bool) -> void:
	var sim = fixture(native_backend)
	var ids: Array[int] = []
	for index: int in range(4):
		ids.append(loiterer(sim, Vector2(24, 24), float(index) * PI * .5))
	var initial_clear: bool = true
	for first: int in ids:
		for second: int in ids:
			if second > first:
				initial_clear = initial_clear and (sim.entities[first].pos as Vector2).distance_to(sim.entities[second].pos) > sim._radius(sim.entities[first]) + sim._radius(sim.entities[second]) + AirNavigation.CLEARANCE
	check(initial_clear, "shared-center orbit fixture starts without overlapping aircraft")
	var result: Dictionary = observe_loiter(sim, ids, ids, 240)
	check(bool(result.safe), "shared-center idle traffic retains continuous moving-pair separation native=" + str(native_backend))
	var progressed: bool = true
	for record: Dictionary in result.aircraft:
		progressed = progressed and float(record.actual_angle_progress) > PI
	check(progressed, "every shared-center aircraft makes at least half a real orbit instead of starving native=" + str(native_backend))
	result.case = "four_shared_center_idle_orbits"
	result.native = native_backend
	rows.append(result)


func active_flight_controls(native_backend: bool) -> void:
	var sim = fixture(native_backend)
	var origin := Vector2(8.17, 18.31)
	var goal := Vector2(38.43, 27.19)
	var id: int = aircraft(sim, "sky_recon", origin)
	var e: Dictionary = sim.entities[id]
	e.loiter_center = Vector2(24, 24)
	e.loiter_phase = .4
	sim.issue([id], "move", goal)
	var maximum_lateral: float = 0.0
	for _frame: int in range(30):
		sim.step(STEP)
		maximum_lateral = maxf(maximum_lateral, (e.pos as Vector2).distance_to(Geometry2D.get_closest_point_to_segment(e.pos, origin, goal)))
	check(not e.commands.is_empty() and not e.has("loiter_center") and maximum_lateral < .0003 and (e.pos as Vector2).distance_to(origin) > 5.0, "an active arbitrary-angle move retains its straight route instead of being taken over by idle orbit native=" + str(native_backend))
	var returning = fixture(native_backend)
	var field: int = returning._spawn(0, "sky_airfield", Vector2(35, 34), true)
	var plane: int = aircraft(returning, "sky_recon", Vector2(8, 8))
	var carrier: Dictionary = returning.entities[plane]
	returning._set_home_airfield(carrier, field)
	carrier.ammo = 0
	carrier.flight_state = "returning"
	carrier.loiter_center = Vector2(24, 24)
	carrier.loiter_phase = .4
	var before: Vector2 = carrier.pos
	for _frame: int in range(10):
		returning.step(STEP)
	check(carrier.flight_state == "returning" and is_equal_approx(float(carrier.loiter_phase), .4) and (carrier.pos as Vector2).distance_to(before) > 1.0, "returning flight continues toward service without advancing or following an idle orbit native=" + str(native_backend))


func run() -> void:
	rules = Rules.load_rules("res://data/rules.json", false)
	check(not rules.is_empty(), "idle air traffic regression uses valid gameplay rules")
	check(ClassDB.class_exists("PaperFrontKernels"), "idle air traffic regression covers both native and script dispatch")
	if not rules.is_empty():
		for native_backend: bool in [false, true]:
			if native_backend and not ClassDB.class_exists("PaperFrontKernels"):
				continue
			blocked_loiter(native_backend)
			shared_loiter(native_backend)
			active_flight_controls(native_backend)
	print("AIR_NAVIGATION_STALL ", JSON.stringify({"checks": checks, "failures": failures, "cases": rows}))
	for message: String in failures:
		push_error(message)
	quit(0 if failures.is_empty() else 1)
