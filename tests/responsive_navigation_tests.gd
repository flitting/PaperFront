extends SceneTree

# Run only after coordinating with other active test sessions.
# godot --headless --path . --script tests/responsive_navigation_tests.gd
const Sim = preload("res://tests/frozen_path_simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
const STEP: float = 1.0 / 30.0
var config: Dictionary = {}
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
	sim.setup(config.duplicate(true), "dev", 7, "iron", false)
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
	sim._spawn(0, "iron_hq", Vector2(5, 43), true)
	sim._spawn(1, "kestrel_hq", Vector2(43, 43), true)
	sim._prepare_terrain_cache()
	sim._nav_initialized = false
	sim._rebuild_nav()
	sim._rebuild_spatial()
	return sim


func quiet_unit(sim, team: int, spec: String, point: Vector2) -> int:
	var id: int = sim._spawn(team, spec, point, true)
	sim.entities[id].cooldown = 10000.0
	return id


func prepare_geometry(sim) -> void:
	sim._in_step = true
	sim._ground_motion_spatial.clear()
	sim._spec_cache = sim.rules.units.duplicate()
	sim._spec_cache.merge(sim.rules.buildings)
	sim._rebuild_spatial()
	sim._prepare_native_queries()


func close_fixture(sim) -> void:
	sim._in_step = false
	if sim._path_worker != null:
		sim._path_worker.close()


func pending_start(native_backend: bool) -> void:
	var sim = fixture(native_backend)
	var label: String = "native" if native_backend else "script"
	var origin := Vector2(24.17, 24.31)
	var id: int = quiet_unit(sim, 0, "iron_tank", origin)
	var e: Dictionary = sim.entities[id]
	for degrees: float in [17.0, 63.0, 128.0, -29.0, -74.0, -151.0]:
		sim.issue([id], "stop", Vector2.ZERO)
		e.pos = origin
		e.alpha = degrees
		sim._rebuild_spatial()
		var goal: Vector2 = origin + Vector2.from_angle(deg_to_rad(degrees)) * 13.0
		var submitted_before: int = int(sim._path_worker.submitted)
		sim.issue([id], "move", goal)
		sim.step(STEP)
		sim.events.clear()
		check((e.pos as Vector2).distance_to(origin) > .001, label + " starts on the first tick while its aligned arbitrary-angle path is pending: " + str(degrees))
		check(int(sim.navigation_stats.completed) == 0 and int(sim._path_worker.submitted) > submitted_before, label + " first movement happens before any worker route exists")
		var off_line: float = 0.0
		for _tick: int in range(29):
			sim.step(STEP)
			sim.events.clear()
			var point: Vector2 = e.pos
			off_line = maxf(off_line, point.distance_to(Geometry2D.get_closest_point_to_segment(point, origin, goal)))
		check((e.pos as Vector2).distance_to(origin) > 1.2 and off_line < .0005, label + " pending motion remains a straight non-grid line after the old start-drift threshold")
		check(int(sim._path_worker.submitted) - submitted_before == 1, label + " pending movement preserves its original worker request instead of continually replacing it")
		rows.append({"case": "pending_start", "native": native_backend, "angle": degrees, "distance": (e.pos as Vector2).distance_to(origin), "off_line": off_line})
	sim.issue([id], "stop", Vector2.ZERO)
	var stopped: Vector2 = e.pos
	for _tick: int in range(3):
		sim.step(STEP)
	check(e.commands.is_empty() and e.pos == stopped and not sim._path_requests.has(id), label + " stop cancels provisional motion and pending path work")
	close_fixture(sim)


func disabled_control(native_backend: bool) -> void:
	var sim = fixture(native_backend)
	sim.responsive_navigation_enabled = false
	sim.crowd_overlap_enabled = false
	var origin := Vector2(12.17, 20.31)
	var id: int = quiet_unit(sim, 0, "iron_tank", origin)
	sim.entities[id].alpha = 17.0
	sim.issue([id], "move", origin + Vector2.from_angle(deg_to_rad(17.0)) * 12.0)
	for _tick: int in range(3):
		sim.step(STEP)
	check(sim.entities[id].pos == origin and int(sim._path_worker.submitted) == 1, "disabled responsive navigation retains the pending-worker baseline")
	close_fixture(sim)


func static_wall(native_backend: bool) -> void:
	var sim = fixture(native_backend)
	# The wall reaches both map edges, so there is no alternative way through.
	var rectangle := Rect2(Vector2(23.85, 0), Vector2(.3, 48))
	sim.ruins.append({"id": 0, "kind": "wall", "pos": rectangle.get_center(), "half": rectangle.size * .5, "hp": 100000.0, "max_hp": 100000.0, "yaw": 0.0, "variant": 0})
	sim._refresh_ruin_spatial()
	sim._rebuild_nav()
	var origin := Vector2(22, 24)
	var id: int = quiet_unit(sim, 0, "iron_rifle", origin)
	var e: Dictionary = sim.entities[id]
	e.alpha = 0.0
	sim.issue([id], "move", Vector2(30, 24))
	var maximum_x: float = origin.x
	for _tick: int in range(90):
		sim.step(STEP)
		sim.events.clear()
		maximum_x = maxf(maximum_x, (e.pos as Vector2).x)
	# This oracle is independent of the movement query: no segment whose two
	# endpoints remain on this side can cross the full-height vertical wall.
	check(maximum_x <= rectangle.position.x - float(e.radius) - .019, "pending movement retains the entire collision radius outside a static wall")
	check(int(sim.navigation_stats.completed) == 0 and not e.commands.is_empty(), "a permanently pending route cannot declare the far side of the wall reached")
	close_fixture(sim)


func overlap_controls(native_backend: bool) -> void:
	var sim = fixture(native_backend)
	var origin := Vector2(14, 20)
	var id: int = quiet_unit(sim, 0, "iron_rifle", origin)
	var other_id: int = quiet_unit(sim, 0, "iron_rifle", Vector2(14.04, 20.97))
	var e: Dictionary = sim.entities[id]
	var other: Dictionary = sim.entities[other_id]
	e.commands = [{"kind": "move", "pos": Vector2(30, 20), "target": -1}]
	var next := origin + Vector2(.1, 0)
	prepare_geometry(sim)
	check(sim._native_geometry_ready == native_backend, "overlap fixture activates the requested geometry backend")
	check(sim._movement_clear(e, origin, next), "small friendly overlap allows forward movement beside an idle teammate")
	sim.crowd_overlap_enabled = false
	prepare_geometry(sim)
	check(not sim._movement_clear(e, origin, next), "disabling friendly overlap restores the original collision radius")
	sim.crowd_overlap_enabled = true
	other.pos = Vector2(14.04, 20.70)
	prepare_geometry(sim)
	check(not sim._movement_clear(e, origin, next), "friendly overlap remains bounded and cannot pass through a teammate's center")
	other.pos = Vector2(14.04, 20.97)
	other.team = 1
	prepare_geometry(sim)
	check(not sim._movement_clear(e, origin, next), "enemy units retain hard collision despite friendly crowd tolerance")
	other.team = 0
	other.hold_position = true
	prepare_geometry(sim)
	check(not sim._movement_clear(e, origin, next), "held teammates retain hard collision")
	other.hold_position = false
	e.hold_position = true
	prepare_geometry(sim)
	check(not sim._movement_clear(e, origin, next), "held movers do not receive relaxed pair clearance")
	e.hold_position = false
	var tank_id: int = quiet_unit(sim, 0, "iron_tank", Vector2(14.04, 21.47))
	sim._kill_entity(other_id, false)
	prepare_geometry(sim)
	check(sim._movement_clear(e, origin, next), "mixed friendly infantry and vehicles retain only the permitted small overlap")
	var tank: Dictionary = sim.entities[tank_id]
	tank.pos = Vector2(14.04, 21.30)
	prepare_geometry(sim)
	check(not sim._movement_clear(e, origin, next), "mixed-radius pairs cannot use vehicle size to increase infantry overlap allowance")
	sim._kill_entity(tank_id, false)
	quiet_unit(sim, 0, "iron_train", Vector2(14.04, 21.47))
	prepare_geometry(sim)
	check(not sim._movement_clear(e, origin, next), "rail-only units retain hard collision outside the railway overlap rule")
	close_fixture(sim)


func railway_controls(native_backend: bool, enabled: bool) -> void:
	var sim = fixture(native_backend)
	sim.responsive_navigation_enabled = enabled
	sim.crowd_overlap_enabled = enabled
	for x: int in range(14, 36):
		sim._spawn(0, "iron_rail", Vector2(x + .5, 30.5), true)
	sim._rail_network.rebuild(sim)
	var id: int = quiet_unit(sim, 0, "iron_train", Vector2(16.5, 30.5))
	var e: Dictionary = sim.entities[id]
	var origin: Vector2 = e.pos
	var speed: float = float(sim.data_for(e.spec).speed)
	sim._move_to(e, Vector2(33.5, 30.5), .1)
	check(absf((e.pos as Vector2).x - origin.x - speed * .2) < .0001 and absf((e.pos as Vector2).y - origin.y) < .0001, "connected rail-only movement retains exactly double speed with responsive flags=" + str(enabled))
	var before: Vector2 = e.pos
	sim._move_to(e, Vector2(33.5, 34.5), .1)
	check(e.pos == before, "rail-only movement cannot use pending ground motion to leave the track")
	var enemy: int = quiet_unit(sim, 1, "iron_train", Vector2(16.5, 30.5))
	var enemy_origin: Vector2 = sim.entities[enemy].pos
	sim._move_to(sim.entities[enemy], Vector2(33.5, 30.5), .1)
	check(sim.entities[enemy].pos == enemy_origin, "rail-only units cannot borrow the opponent's connected rails")
	var infantry: int = quiet_unit(sim, 0, "iron_rifle", Vector2(28.5, 30.5))
	var soldier: Dictionary = sim.entities[infantry]
	var soldier_origin: Vector2 = soldier.pos
	sim._move_to(soldier, Vector2(34.5, 30.5), .1)
	check(absf((soldier.pos as Vector2).x - soldier_origin.x - float(sim.data_for(soldier.spec).speed) * .2) < .0001, "ordinary infantry retain exactly double speed on connected friendly rails")
	var cut_id: int = int(sim._rail_network.cells[Vector2i(24, 30)].id)
	sim._kill_entity(cut_id, false)
	sim._rail_network.rebuild(sim)
	before = e.pos
	sim._move_to(e, Vector2(33.5, 30.5), .1)
	check(e.pos == before, "a disconnected rail graph cannot be bypassed by responsive ground movement")
	close_fixture(sim)


func synchronous_budget_control(native_backend: bool) -> void:
	var sim = fixture(native_backend)
	sim.synchronous_path_tests = true
	var origin := Vector2(12.17,20.31)
	var id: int = quiet_unit(sim,0,"iron_tank",origin)
	sim.entities[id].alpha = 17.0
	prepare_geometry(sim)
	sim._path_plans_remaining = 0
	sim._move_to(sim.entities[id],origin + Vector2.from_angle(deg_to_rad(17.0))*12.0,STEP)
	check(sim._plan_was_deferred and sim.entities[id].pos == origin,"synchronous rule budget still waits while real asynchronous games can start locally")
	check(not sim.entities[id].has("provisional_goal"),"synchronous rule fixtures never gain asynchronous movement metadata")
	close_fixture(sim)


func run() -> void:
	config = Rules.load_rules()
	check(not config.is_empty(), "responsive navigation uses the real gameplay rules")
	check(ClassDB.class_exists("PaperFrontKernels"), "responsive navigation exercises both script and native movement")
	if not config.is_empty():
		for native_backend: bool in [false, true]:
			if native_backend and not ClassDB.class_exists("PaperFrontKernels"):
				continue
			pending_start(native_backend)
			disabled_control(native_backend)
			synchronous_budget_control(native_backend)
			static_wall(native_backend)
			overlap_controls(native_backend)
			for enabled: bool in [false, true]:
				railway_controls(native_backend, enabled)
	print("RESPONSIVE_NAVIGATION ", JSON.stringify({"checks": checks, "failures": failures, "rows": rows}))
	for message: String in failures:
		push_error(message)
	quit(0 if failures.is_empty() else 1)
