extends SceneTree

const Sim = preload("res://scripts/simulation.gd")
const SyncSim = preload("res://tests/rule_test_simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
const STEP: float = 1.0 / 30.0
var rules: Dictionary
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	rules = Rules.load_rules()
	_check(not rules.is_empty(), "free navigation uses valid real gameplay rules")
	_check(ClassDB.class_exists("PaperFrontKernels"), "free navigation exercises the native movement backend")
	if rules.is_empty() or not ClassDB.class_exists("PaperFrontKernels"):
		_finish()
		return
	for native_backend: bool in [false, true]:
		for synchronous: bool in [true, false]:
			_test_clear_routes(native_backend, synchronous)
			_test_building_detour(native_backend, synchronous)
			_test_thin_obstacle_between_nodes(native_backend, synchronous)
		_test_swept_units(native_backend)
		_test_same_frame_crossings(native_backend)
		_test_infantry_orders(native_backend)
	_finish()


func _finish() -> void:
	print("FREE_NAVIGATION ", JSON.stringify({"checks": checks, "failures": failures}))
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)


func _label(native_backend: bool, synchronous: bool = true) -> String:
	return ("native" if native_backend else "script") + (" sync: " if synchronous else " worker: ")


func _fixture(native_backend: bool, synchronous: bool = true):
	var sim = SyncSim.new() if synchronous else Sim.new()
	sim.native_kernels_enabled = native_backend
	sim.native_unit_dispatch_enabled = native_backend
	sim.native_geometry_enabled = native_backend
	sim.native_movement_enabled = native_backend
	sim.setup(rules.duplicate(true), "dev", 7, "rivet", false)
	# Retain a valid match with remote HQs, but give the navigation fixtures an
	# obstacle-free flat field and the real configured unit collision sizes.
	for z: int in range(48):
		for x: int in range(48):
			sim.map.terrain[z][x] = 0
			sim.map.heights[z][x] = 0.0
	sim.mines.clear()
	sim.bridges.clear()
	sim.ruins.clear()
	sim._refresh_mine_spatial()
	sim._refresh_ruin_spatial()
	for id: int in sim.entities.keys():
		sim._kill_entity(id, false)
	sim.debug_spawn(0, "rivet_hq", Vector2(4, 44))
	sim.debug_spawn(1, "kestrel_hq", Vector2(44, 44))
	sim._prepare_terrain_cache()
	sim._nav_initialized = false
	sim._rebuild_nav()
	sim._rebuild_spatial()
	return sim


func _quiet_unit(sim, team: int, spec: String, position: Vector2) -> int:
	var id: int = sim.debug_spawn(team, spec, position)
	# Isolate contact damage from weapon fire while still using the actual tick.
	sim.entities[id].cooldown = 10000.0
	return id


func _tick(sim) -> void:
	sim.step(STEP)
	sim.events.clear()
	if not sim.synchronous_path_tests:
		OS.delay_usec(1000)


func _close(sim) -> void:
	if sim._path_worker != null:
		sim._path_worker.close()
	sim._in_step = false


func _prepare_geometry(sim) -> void:
	sim._in_step = true
	sim._spec_cache = sim.rules.units.duplicate()
	sim._spec_cache.merge(sim.rules.buildings)
	sim._rebuild_spatial()
	sim._prepare_native_queries()


func _test_clear_routes(native_backend: bool, synchronous: bool) -> void:
	var sim = _fixture(native_backend, synchronous)
	var prefix: String = _label(native_backend, synchronous)
	var origin := Vector2(24.17, 24.31)
	var tank: int = _quiet_unit(sim, 0, "rivet_tank", origin)
	if not synchronous:
		_check(sim._path_worker != null, prefix + "real background path worker is active")
	for degrees: float in [17.0, 63.0, 128.0, -29.0, -74.0, -151.0]:
		var goal: Vector2 = origin + Vector2.from_angle(deg_to_rad(degrees)) * 13.0
		var e: Dictionary = sim.entities[tank]
		sim.issue([tank], "stop", Vector2.ZERO)
		var previous: Vector2 = e.pos
		e.pos = origin
		sim._spatial_move(e, previous, origin)
		e.alpha = wrapf(degrees + 95.0, -180.0, 180.0)
		e.cooldown = 10000.0
		if synchronous:
			var path: Array = sim._path_between(origin, goal, float(e.radius), tank)
			_check(path.size() == 1 and (path[0] as Vector2).is_equal_approx(goal), prefix + "clear non-grid route has only its actual destination at " + str(degrees) + " degrees")
		sim.issue([tank], "move", goal)
		var off_line: float = 0.0
		var travelled: float = 0.0
		previous = origin
		for tick: int in range(450):
			_tick(sim)
			var point: Vector2 = e.pos
			travelled += previous.distance_to(point)
			off_line = maxf(off_line, point.distance_to(Geometry2D.get_closest_point_to_segment(point, origin, goal)))
			previous = point
			if e.commands.is_empty():
				break
		_check(e.commands.is_empty() and (e.pos as Vector2).distance_to(goal) <= 0.32, prefix + "tank completes clear route at " + str(degrees) + " degrees")
		_check(off_line < 0.0005 and travelled <= origin.distance_to(goal) + 0.001, prefix + "tank follows one straight line after turning at " + str(degrees) + " degrees")
	_close(sim)


func _segment_hits_rectangle(start: Vector2, finish: Vector2, radius: float, rect: Rect2) -> bool:
	# Independent continuous capsule-versus-rectangle oracle. Testing only the
	# waypoints would overlook a diagonal that clips the building between them.
	if start.distance_to(start.clamp(rect.position, rect.end)) < radius or finish.distance_to(finish.clamp(rect.position, rect.end)) < radius:
		return true
	var corners: Array[Vector2] = [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for index: int in range(corners.size()):
		var corner: Vector2 = corners[index]
		if Geometry2D.segment_intersects_segment(start, finish, corner, corners[(index + 1) % corners.size()]) != null:
			return true
		if corner.distance_to(Geometry2D.get_closest_point_to_segment(corner, start, finish)) < radius:
			return true
	return false


func _test_building_detour(native_backend: bool, synchronous: bool) -> void:
	var sim = _fixture(native_backend, synchronous)
	var prefix: String = _label(native_backend, synchronous)
	var building: int = sim.debug_spawn(0, "rivet_factory", Vector2(24, 24))
	sim._rebuild_nav()
	var start := Vector2(13.17, 19.43)
	var goal := Vector2(34.23, 28.13)
	var tank: int = _quiet_unit(sim, 0, "rivet_tank", start)
	var e: Dictionary = sim.entities[tank]
	var half := Vector2.ONE * float(sim.data_for(sim.entities[building].spec).size) * 0.5
	var rectangle := Rect2(sim.entities[building].pos - half, half * 2.0)
	var clearance: float = float(e.radius) + 0.019
	_check(_segment_hits_rectangle(start, goal, clearance, rectangle), prefix + "obstacle fixture actually blocks the direct diagonal")
	if synchronous:
		var path: Array = sim._path_between(start, goal, float(e.radius), tank)
		var legal: bool = not path.is_empty()
		var prior: Vector2 = start
		for point: Vector2 in path:
			legal = legal and not _segment_hits_rectangle(prior, point, clearance, rectangle)
			prior = point
		_check(legal and path.size() > 1 and (path.back() as Vector2).is_equal_approx(goal), prefix + "planned detour preserves exact building clearance and arbitrary endpoint")
	sim.issue([tank], "move", goal)
	var stayed_clear: bool = true
	var detoured: bool = false
	var previous: Vector2 = start
	for tick: int in range(900):
		_tick(sim)
		var point: Vector2 = e.pos
		stayed_clear = stayed_clear and not _segment_hits_rectangle(previous, point, clearance, rectangle)
		detoured = detoured or point.distance_to(Geometry2D.get_closest_point_to_segment(point, start, goal)) > 0.5
		previous = point
		if e.commands.is_empty():
			break
	_check(stayed_clear and detoured, prefix + "all actual movement segments detour outside the complete building footprint")
	_check(e.commands.is_empty() and (e.pos as Vector2).distance_to(goal) <= 0.32, prefix + "building detour reaches its requested destination")
	_close(sim)


func _test_swept_units(native_backend: bool) -> void:
	var prefix: String = _label(native_backend)
	for case: Dictionary in [{"spec": "rivet_rifle", "team": 0, "crush": false}, {"spec": "kestrel_tank", "team": 1, "crush": false}, {"spec": "kestrel_rifle", "team": 1, "crush": true}]:
		var sim = _fixture(native_backend)
		var start := Vector2(10.17, 18.43)
		var finish := Vector2(31.23, 27.13)
		var tank: int = _quiet_unit(sim, 0, "rivet_tank", start)
		var obstacle: int = _quiet_unit(sim, int(case.team), str(case.spec), start.lerp(finish, 0.37))
		var e: Dictionary = sim.entities[tank]
		var other: Dictionary = sim.entities[obstacle]
		e.commands = [{"kind": "force_move", "pos": finish, "target": obstacle}]
		_prepare_geometry(sim)
		_check(sim._native_geometry_ready == native_backend, prefix + "swept fixture activates the requested geometry backend")
		_check(sim._movement_clear(e, start, finish) == bool(case.crush), prefix + "long diagonal sweep observes middle-of-segment " + str(case.spec))
		_check(sim._can_crush_target(e, other) == bool(case.crush), prefix + "crush eligibility respects ownership for selected force_move " + str(case.spec))
		var hp: float = float(other.hp)
		sim._settle_crushing(e, finish)
		_check((float(other.hp) <= 0.0) if bool(case.crush) else is_equal_approx(float(other.hp), hp), prefix + "swept crushing reaches crossed enemy infantry and preserves other units " + str(case.spec))
		_close(sim)
	# A high speed or large delta must not skip contact simply because both
	# tick endpoints lie outside the victim's collision radius.
	var sim = _fixture(native_backend)
	var tank: int = _quiet_unit(sim, 0, "rivet_tank", Vector2(10.17, 18.43))
	var enemy: int = _quiet_unit(sim, 1, "kestrel_rifle", Vector2(18.594, 21.91))
	var goal := Vector2(31.23, 27.13)
	sim.entities[tank].alpha = rad_to_deg((goal - (sim.entities[tank].pos as Vector2)).angle())
	sim.issue([tank], "move", goal)
	sim.entities[tank].path = [goal]
	sim.entities[tank].path_goal = goal
	sim.rules.units.rivet_tank.speed = 100.0
	_prepare_geometry(sim)
	sim._move_to(sim.entities[tank], goal, 1.0)
	_check(float(sim.entities[enemy].hp) <= 0.0 and (sim.entities[tank].pos as Vector2).is_equal_approx(goal), prefix + "an actual high-speed move crushes infantry crossed between tick endpoints")
	_close(sim)


func _test_thin_obstacle_between_nodes(native_backend: bool, synchronous: bool) -> void:
	var sim = _fixture(native_backend, synchronous)
	var prefix: String = _label(native_backend, synchronous)
	# Both adjacent one-meter navigation centers are legal, although the edge
	# between them crosses this small solid object. Node masks alone miss it.
	var center := Vector2(20.0, 20.5)
	var half := Vector2(0.03, 0.03)
	sim.ruins.append({"id": 0, "kind": "tree", "pos": center, "half": half, "hp": 100.0, "max_hp": 100.0, "yaw": 0.0, "variant": 0})
	sim._refresh_ruin_spatial()
	sim._rebuild_nav()
	var start := Vector2(18.5, 20.5)
	var goal := Vector2(22.5, 20.5)
	var unit: int = _quiet_unit(sim, 0, "rivet_engineer", start)
	var e: Dictionary = sim.entities[unit]
	var clearance: float = float(e.radius) + 0.019
	var rectangle := Rect2(center - half, half * 2.0)
	_check(sim._standing(Vector2(19.5, 20.5), float(e.radius), unit, false) and sim._standing(Vector2(20.5, 20.5), float(e.radius), unit, false), prefix + "thin-obstacle neighboring graph nodes are individually safe")
	_check(_segment_hits_rectangle(Vector2(19.5, 20.5), Vector2(20.5, 20.5), clearance, rectangle), prefix + "thin-obstacle edge is continuously blocked between safe graph nodes")
	if synchronous:
		var path: Array = sim._path_between(start, goal, float(e.radius), unit)
		var legal: bool = not path.is_empty()
		var previous: Vector2 = start
		for point: Vector2 in path:
			legal = legal and not _segment_hits_rectangle(previous, point, clearance, rectangle)
			previous = point
		_check(legal, prefix + "synchronous planner finds a route around an obstruction between safe graph nodes")
	sim.issue([unit], "move", goal)
	var stayed_clear: bool = true
	var previous: Vector2 = start
	for tick: int in range(450):
		_tick(sim)
		stayed_clear = stayed_clear and not _segment_hits_rectangle(previous, e.pos, clearance, rectangle)
		previous = e.pos
		if e.commands.is_empty():
			break
	_check(stayed_clear and e.commands.is_empty() and (e.pos as Vector2).distance_to(goal) <= 0.27, prefix + "unit reaches its destination without crossing the thin inter-node obstacle")
	_close(sim)


func _test_infantry_orders(native_backend: bool) -> void:
	var prefix: String = _label(native_backend)
	for friendly: bool in [true, false]:
		for command_kind: String in ["move", "force_move"]:
			var sim = _fixture(native_backend)
			var start := Vector2(12.17, 19.43)
			var goal := Vector2(28.23, 26.13)
			var tank: int = _quiet_unit(sim, 0, "rivet_tank", start)
			var infantry: int = _quiet_unit(sim, 0 if friendly else 1, "rivet_rifle" if friendly else "kestrel_rifle", start.lerp(goal, 0.4))
			var infantry_hp: float = float(sim.entities[infantry].hp)
			sim.issue([infantry], "hold", sim.entities[infantry].pos)
			# For an enemy target, a destination past the infantry keeps the move
			# order active after the crush. Friendly target tracking is itself safe.
			sim.issue([tank], command_kind, goal, infantry if command_kind == "force_move" else -1)
			var stayed_clear: bool = true
			for tick: int in range(600):
				var previous: Vector2 = sim.entities[tank].pos
				_tick(sim)
				if friendly and sim.entities.has(infantry):
					var point: Vector2 = sim.entities[infantry].pos
					var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point, previous, sim.entities[tank].pos)
					stayed_clear = stayed_clear and point.distance_to(closest) >= float(sim.entities[tank].radius) + float(sim.entities[infantry].radius) - 0.001
				if sim.entities[tank].commands.is_empty() or (not friendly and not sim.entities.has(infantry)):
					break
			if friendly:
				_check(sim.entities.has(infantry) and is_equal_approx(float(sim.entities[infantry].hp), infantry_hp) and stayed_clear, prefix + command_kind + " preserves friendly infantry health and swept separation")
				if command_kind == "move":
					_check(sim.entities[tank].commands.is_empty() and (sim.entities[tank].pos as Vector2).distance_to(goal) <= 0.32, prefix + "tank completes its diagonal destination around held friendly infantry")
			else:
				_check(not sim.entities.has(infantry), prefix + command_kind + " retains enemy infantry crushing")
			_close(sim)


func _relative_distance(first_start: Vector2, first_finish: Vector2, second_start: Vector2, second_finish: Vector2) -> float:
	# At normalized frame time t, separation is the linear interpolation of
	# these relative endpoints. Its minimum includes all in-between positions.
	var relative_start: Vector2 = first_start - second_start
	var relative_finish: Vector2 = first_finish - second_finish
	return Geometry2D.get_closest_point_to_segment(Vector2.ZERO, relative_start, relative_finish).length()


func _planned_move(sim, id: int, goal: Vector2, heading: float) -> void:
	sim.issue([id], "move", goal)
	var e: Dictionary = sim.entities[id]
	e.alpha = heading
	e.path = [goal]
	e.path_goal = goal


func _test_same_frame_crossings(native_backend: bool) -> void:
	var prefix: String = _label(native_backend)
	for stride: float in [4.0, 16.0]:
		var sim = _fixture(native_backend)
		var center := Vector2(20.0, 20.0)
		var first_start: Vector2 = center - Vector2.RIGHT * stride * 0.5
		var first_goal: Vector2 = center + Vector2.RIGHT * stride * 0.5
		var second_start: Vector2 = center - Vector2.DOWN * stride * 0.5
		var second_goal: Vector2 = center + Vector2.DOWN * stride * 0.5
		var first: int = _quiet_unit(sim, 0, "rivet_tank", first_start)
		var second: int = _quiet_unit(sim, 0, "rivet_tank", second_start)
		sim.rules.units.rivet_tank.speed = stride
		_planned_move(sim, first, first_goal, 0.0)
		_planned_move(sim, second, second_goal, 90.0)
		var combined: float = float(sim.entities[first].radius) + float(sim.entities[second].radius)
		var static_clear: bool = first_start.distance_to(Geometry2D.get_closest_point_to_segment(first_start, second_start, second_goal)) > combined and first_goal.distance_to(Geometry2D.get_closest_point_to_segment(first_goal, second_start, second_goal)) > combined and second_start.distance_to(Geometry2D.get_closest_point_to_segment(second_start, first_start, first_goal)) > combined and second_goal.distance_to(Geometry2D.get_closest_point_to_segment(second_goal, first_start, first_goal)) > combined
		_check(static_clear and _relative_distance(first_start, first_goal, second_start, second_goal) < 0.001, prefix + "perpendicular tank fixture has safe endpoints and stationary sweeps but collides halfway, stride " + str(stride))
		sim.step(1.0)
		var first_finish: Vector2 = sim.entities[first].pos
		var second_finish: Vector2 = sim.entities[second].pos
		_check(first_finish.distance_to(first_goal) < 0.001, prefix + "earlier tank commits its clear planned crossing, stride " + str(stride))
		_check(_relative_distance(first_start, first_finish, second_start, second_finish) >= combined - 0.001, prefix + "same-frame perpendicular tanks retain continuous relative separation, stride " + str(stride))
		_check(first_finish.distance_to(second_finish) >= combined - 0.001, prefix + "same-frame perpendicular tanks retain endpoint separation, stride " + str(stride))
		_close(sim)

	for stride: float in [4.0, 16.0]:
		var sim = _fixture(native_backend)
		var center := Vector2(20.0, 20.0)
		var infantry_start: Vector2 = center - Vector2.DOWN * stride * 0.5
		var infantry_goal: Vector2 = center + Vector2.DOWN * stride * 0.5
		var tank_start: Vector2 = center - Vector2.RIGHT * stride * 0.5
		var tank_goal: Vector2 = center + Vector2.RIGHT * stride * 0.5
		# The infantry's earlier insertion makes it move first in the actual
		# authoritative tick. Its final point lies outside the tank's sweep.
		var infantry: int = _quiet_unit(sim, 1, "kestrel_rifle", infantry_start)
		var infantry_record: Dictionary = sim.entities[infantry]
		var tank: int = _quiet_unit(sim, 0, "rivet_tank", tank_start)
		sim.rules.units.kestrel_rifle.speed = stride
		sim.rules.units.rivet_tank.speed = stride
		_planned_move(sim, infantry, infantry_goal, 90.0)
		_planned_move(sim, tank, tank_goal, 0.0)
		sim.step(1.0)
		var combined: float = float(sim.entities[tank].radius) + float(infantry_record.radius)
		_check((infantry_record.pos as Vector2).distance_to(infantry_goal) < 0.001 and infantry_goal.distance_to(Geometry2D.get_closest_point_to_segment(infantry_goal, tank_start, tank_goal)) > combined, prefix + "earlier enemy infantry ends outside the tank's stationary sweep, stride " + str(stride))
		_check(_relative_distance(infantry_start, infantry_record.pos, tank_start, sim.entities[tank].pos) < combined and not sim.entities.has(infantry), prefix + "tank crushes enemy infantry crossed by relative motion earlier in the same frame, stride " + str(stride))
		_close(sim)
