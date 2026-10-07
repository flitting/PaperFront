extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
const AirNavigation = preload("res://scripts/air_navigation.gd")
const AircraftOperations = preload("res://scripts/aircraft_operations.gd")
var rules: Dictionary
var checks: int = 0
var failures: Array[String] = []
var flight_evidence: Array[Dictionary] = []

func _initialize() -> void:
	rules = Rules.load_rules("res://data/rules.json", false)
	if rules.is_empty():
		push_error("Air navigation rules invalid: " + str(Rules.errors))
		quit(1)
		return
	for native in [false, true]:
		_test_straight_flight(native)
		_test_air_avoidance(native, 0)
		_test_air_avoidance(native, 1)
		_test_crossing_traffic(native, false)
		_test_crossing_traffic(native, true)
		_test_group_destinations(native)
		_test_shared_destinations(native)
		_test_landing_and_takeoff(native)
		_test_grounded_airport_loss(native)
		_test_bounds_and_spawn(native)
	var output: String="res://artifacts/rts_revision_v3_20261007/air_navigation_arrivals.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":flight_evidence},"\t"))
	print("AIR_NAVIGATION checks=%d failures=%s" % [checks, str(failures)])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _sim(native: bool):
	var sim = Sim.new()
	sim.setup(rules, "dev", 7, "rivet", false)
	sim.native_unit_dispatch_enabled = native
	sim.native_geometry_enabled = native
	sim.native_movement_enabled = native
	return sim

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _swept_distance(first_start: Vector2, first_end: Vector2, second_start: Vector2, second_end: Vector2) -> float:
	var offset: Vector2 = first_start - second_start
	var relative_step: Vector2 = (first_end - first_start) - (second_end - second_start)
	var closest: float = 0.0 if relative_step.length_squared() < 0.000001 else clampf(-offset.dot(relative_step) / relative_step.length_squared(), 0.0, 1.0)
	return (offset + relative_step * closest).length()

func _test_straight_flight(native: bool) -> void:
	var sim = _sim(native)
	var start := Vector2(4.25, 27.625)
	var goal := Vector2(40.375, 38.125)
	var plane: int = sim.debug_spawn(0, "sky_recon", start)
	var building: int = sim.debug_spawn(0, "rivet_factory", start.lerp(goal, 0.5))
	var ground: int = sim.debug_spawn(0, "rivet_tank", Vector2(12.5, 30.5))
	var parked: int = sim.debug_spawn(0, "sky_recon", start.lerp(goal, 0.75))
	sim.entities[parked].flight_state = "landed"
	sim._set_airborne(sim.entities[parked], false)
	sim.issue([plane], "move", goal)
	var straight := true
	var maximum_lateral_error:float=0.0
	var arrival: Dictionary={}
	var orbit: Dictionary={"distance":0.0,"max_radius_excess":0.0,"phase_change":0.0}
	for frame in range(150):
		var before: Vector2=sim.entities[plane].pos
		var routing: bool=not sim.entities[plane].commands.is_empty()
		sim.step(1.0 / 30.0)
		if routing:
			var relative: Vector2 = sim.entities[plane].pos - start
			var lateral_error:float=absf(relative.cross(goal-start))/start.distance_to(goal)
			maximum_lateral_error=maxf(maximum_lateral_error,lateral_error)
			straight=straight and lateral_error<.0002
			if sim.entities[plane].commands.is_empty():arrival={"frame":frame,"time":sim.time,"pos":sim.entities[plane].pos,"goal_distance":(sim.entities[plane].pos as Vector2).distance_to(goal)}
		elif not arrival.is_empty():_record_orbit(sim.entities[plane],before,orbit)
	_check(straight, "free-angle route remains straight until command completion native=%s" % native)
	_check(not arrival.is_empty() and sim.entities[plane].commands.is_empty(),"straight flight actually completes its move command native=%s"%native)
	_check(not arrival.is_empty() and float(arrival.goal_distance)<.1,"straight flight reaches exact unsnapped goal at completion native=%s"%native)
	_check(float(orbit.distance)>.5 and float(orbit.phase_change)>.1 and float(orbit.max_radius_excess)<.15,"completed fixed wing flight circles on bounded orbit native=%s"%native)
	orbit.maximum_route_lateral_error=maximum_lateral_error
	_save_flight_evidence("straight",native,sim.entities[plane],goal,arrival,orbit)
	_check(sim.entities[plane].path.is_empty() and not sim._planning_queue.has(plane), "air flight bypasses ground path queues native=%s" % native)
	_check(sim.entities.has(building) and sim.entities.has(ground), "overflight does not crush surface entities native=%s" % native)

func _test_air_avoidance(native: bool, blocker_team: int) -> void:
	var sim = _sim(native)
	var plane: int = sim.debug_spawn(0, "sky_recon", Vector2(8.5, 38.5))
	var blocker_spec:String=str(sim.factions[blocker_team])+"_helicopter"
	var blocker: int = sim.debug_spawn(blocker_team, blocker_spec, Vector2(18.5, 38.5))
	sim.entities[blocker].cooldown=1000.0
	var fixed_blocker:Vector2=sim.entities[blocker].pos
	var blocker_stationary:bool=true
	var maximum_detour:float=0.0
	var goal := Vector2(36.5, 38.5)
	sim.issue([plane], "move", goal)
	var clearance: float = sim._radius(sim.entities[plane]) + sim._radius(sim.entities[blocker])
	var safe: bool=true
	var minimum_sweep:float=INF
	var arrival:Dictionary={}
	var orbit:Dictionary={"distance":0.0,"max_radius_excess":0.0,"phase_change":0.0}
	for frame in range(151):
		var previous:Vector2=sim.entities[plane].pos
		var blocker_previous:Vector2=sim.entities[blocker].pos
		var routing:bool=not sim.entities[plane].commands.is_empty()
		sim.step(1.0 if frame==0 else 1.0/30.0)
		var separation:float=_swept_distance(previous,sim.entities[plane].pos,blocker_previous,sim.entities[blocker].pos)
		minimum_sweep=minf(minimum_sweep,separation)
		safe=safe and separation>=clearance-.0001
		blocker_stationary=blocker_stationary and (sim.entities[blocker].pos as Vector2).distance_to(fixed_blocker)<.0001
		if routing:maximum_detour=maxf(maximum_detour,absf(float(sim.entities[plane].pos.y)-38.5))
		if routing and sim.entities[plane].commands.is_empty():arrival={"frame":frame,"time":sim.time,"pos":sim.entities[plane].pos,"goal_distance":(sim.entities[plane].pos as Vector2).distance_to(goal)}
		elif not routing and not arrival.is_empty():_record_orbit(sim.entities[plane],previous,orbit)
	_check(blocker_stationary,"real faction rotorcraft hovers throughout obstacle test team %d native=%s"%[blocker_team,native])
	_check(maximum_detour>=clearance-.0001,"fixed-wing route genuinely detours around hovering obstacle team %d native=%s"%[blocker_team,native])
	_check(safe, "large-step and whole-flight relative sweeps avoid hovering team %d aircraft native=%s" % [blocker_team, native])
	_check(not arrival.is_empty() and sim.entities[plane].commands.is_empty(),"detouring aircraft actually completes move around team %d native=%s"%[blocker_team,native])
	_check(not arrival.is_empty() and float(arrival.goal_distance)<.1,"detouring aircraft reaches exact goal at completion around team %d native=%s"%[blocker_team,native])
	_check(float(orbit.distance)>.5 and float(orbit.phase_change)>.1 and float(orbit.max_radius_excess)<.15,"detouring aircraft enters bounded idle orbit team %d native=%s"%[blocker_team,native])
	orbit.blocker_spec=blocker_spec
	orbit.blocker_stationary=blocker_stationary
	orbit.maximum_route_detour=maximum_detour
	orbit.minimum_swept_separation=minimum_sweep
	orbit.required_clearance=clearance
	_save_flight_evidence("avoid_team_%d"%blocker_team,native,sim.entities[plane],goal,arrival,orbit)

func _record_orbit(plane:Dictionary,previous:Vector2,orbit:Dictionary)->void:
	orbit.distance=float(orbit.distance)+previous.distance_to(plane.pos)
	if not plane.has("loiter_center"):return
	var radius:float=3.4+float(int(plane.id)%3)*.6
	orbit.max_radius_excess=maxf(float(orbit.max_radius_excess),maxf(0.0,(plane.pos as Vector2).distance_to(plane.loiter_center)-radius))
	var phase:float=float(plane.get("loiter_phase",0.0))
	if orbit.has("last_phase"):orbit.phase_change=float(orbit.phase_change)+absf(phase-float(orbit.last_phase))
	orbit.last_phase=phase

func _save_flight_evidence(label:String,native:bool,plane:Dictionary,goal:Vector2,arrival:Dictionary,orbit:Dictionary)->void:
	flight_evidence.append({"case":label,"native":native,"goal":[goal.x,goal.y],"arrival_frame":arrival.get("frame",-1),"arrival_time":arrival.get("time",-1.0),"arrival_position":str(arrival.get("pos",Vector2.INF)),"arrival_goal_distance":arrival.get("goal_distance",-1.0),"final_position":[plane.pos.x,plane.pos.y],"commands_remaining":plane.commands.size(),"flight_state":plane.get("flight_state",""),"loiter_center":str(plane.get("loiter_center",Vector2.INF)),"loiter_phase":plane.get("loiter_phase",0.0),"orbit":orbit})

func _test_crossing_traffic(native: bool, head_on: bool) -> void:
	var sim = _sim(native)
	var first_start := Vector2(8.5, 12.5)
	var second_start: Vector2 = Vector2(30.5, 12.5) if head_on else Vector2(14.15, 6.85)
	var first_goal := Vector2(40.5, 12.5)
	var second_goal: Vector2 = Vector2(2.5, 12.5) if head_on else Vector2(14.15, 34.5)
	var first: int = sim.debug_spawn(0, "sky_recon", first_start)
	var second: int = sim.debug_spawn(1, "sky_recon", second_start)
	sim.issue([first], "move", first_goal)
	sim.issue([second], "move", second_goal)
	var safe := true
	for frame in range(151):
		first_start = sim.entities[first].pos
		second_start = sim.entities[second].pos
		sim.step(1.0 if frame == 0 else 1.0 / 30.0)
		safe = safe and _swept_distance(first_start, sim.entities[first].pos, second_start, sim.entities[second].pos) >= sim._radius(sim.entities[first]) + sim._radius(sim.entities[second]) - 0.0001
	_check(safe, "simultaneous %s trajectories remain separated throughout each frame native=%s" % ["head-on" if head_on else "crossing", native])
	_check(sim.entities[first].commands.is_empty() and sim.entities[second].commands.is_empty(), "both %s aircraft finish after avoidance native=%s" % ["head-on" if head_on else "crossing", native])

func _test_group_destinations(native: bool) -> void:
	var sim = _sim(native)
	var ids: Array = []
	for offset in range(4): ids.append(sim.debug_spawn(0, "sky_recon", Vector2(6.5 + float(offset) * 2.0, 42.5)))
	sim.issue(ids, "move", Vector2(32.125, 38.875))
	var separated := true
	for first in ids:
		for second in ids:
			if int(second) <= int(first): continue
			separated = separated and (sim.entities[first].commands[0].pos as Vector2).distance_to(sim.entities[second].commands[0].pos) >= sim._radius(sim.entities[first]) + sim._radius(sim.entities[second]) + 0.02
	for _frame in range(300): sim.step(1.0 / 30.0)
	var finished := true
	for id in ids: finished = finished and sim.entities[id].commands.is_empty()
	_check(separated and finished, "group aircraft reserve distinct legal goals and complete movement native=%s" % native)

func _test_shared_destinations(native: bool) -> void:
	var sim = _sim(native)
	var first: int = sim.debug_spawn(0, "sky_recon", Vector2(6.5, 42.5))
	var second: int = sim.debug_spawn(0, "sky_recon", Vector2(8.5, 42.5))
	var goal := Vector2(32.5, 38.5)
	sim.issue([first], "move", goal)
	sim.issue([second], "move", goal)
	_check((sim.entities[first].commands[0].pos as Vector2).distance_to(sim.entities[second].commands[0].pos) >= sim._radius(sim.entities[first]) + sim._radius(sim.entities[second]) + .02, "separate movement orders reserve different shared endpoints native=%s" % native)
	for _frame in range(240): sim.step(1.0 / 30.0)
	_check(sim.entities[first].commands.is_empty() and sim.entities[second].commands.is_empty(), "separately ordered aircraft both complete a shared destination native=%s" % native)
	var late_sim = _sim(native)
	var mover: int = late_sim.debug_spawn(0, "sky_recon", Vector2(6.5, 42.5))
	late_sim.issue([mover], "move", goal)
	var blocker: int = late_sim.debug_spawn(1, "sky_recon", goal)
	for _frame in range(240): late_sim.step(1.0 / 30.0)
	_check(late_sim.entities[mover].commands.is_empty() and (late_sim.entities[mover].pos as Vector2).distance_to(late_sim.entities[blocker].pos) >= late_sim._radius(late_sim.entities[mover]) + late_sim._radius(late_sim.entities[blocker]) + .02, "movement recovers when a new aircraft occupies its assigned goal native=%s" % native)

func _test_landing_and_takeoff(native: bool) -> void:
	var sim = _sim(native)
	var plane: int = sim.debug_spawn(0, "sky_recon", Vector2(20.5, 42.5))
	var point: Vector2 = sim.entities[plane].pos
	_check(AircraftOperations.step_land(sim, sim.entities[plane], {"kind": "land", "pos": point}, 0.1, false), "aircraft lands on available ground native=%s" % native)
	sim.step(1.0 / 30.0)
	sim._in_step = true
	sim._prepare_native_queries()
	_check(not sim._standing(point, 0.35, -1), "landed aircraft joins surface collision occupancy native=%s" % native)
	sim._in_step = false
	var overhead: int = sim.debug_spawn(1, "sky_recon", point)
	_check((sim.entities[overhead].pos as Vector2).is_equal_approx(point), "air and landed layers may share a position native=%s" % native)
	_check(not AircraftOperations.takeoff(sim, sim.entities[plane]) and not bool(sim.entities[plane].airborne), "takeoff waits while overhead aircraft occupies airspace native=%s" % native)
	var second: int = sim.debug_spawn(0, "sky_recon", point + Vector2(4.0, 0.0))
	_check(not AircraftOperations.land_error(sim, sim.entities[second], point + Vector2(.8, 0.0)).is_empty(), "field landing checks exact parked-aircraft footprint native=%s" % native)
	sim._kill_entity(overhead, true)
	_check(AircraftOperations.takeoff(sim, sim.entities[plane]) and bool(sim.entities[plane].airborne), "takeoff resumes when overhead aircraft leaves native=%s" % native)
	sim._in_step = true
	sim._prepare_native_queries()
	_check(sim._standing(point, 0.35, -1), "takeoff releases surface collision occupancy native=%s" % native)
	sim._in_step = false

func _test_grounded_airport_loss(native: bool) -> void:
	var sim = Sim.new()
	sim.setup_multiteam(rules, "dev", 7, ["sky", "sky"], false)
	sim.native_unit_dispatch_enabled = native
	sim.native_geometry_enabled = native
	var field: int = sim.debug_spawn(0, "sky_airfield", Vector2(22.5, 30.5))
	var plane: int = sim.debug_spawn(0, "sky_recon", Vector2(20.5, 42.5))
	var point: Vector2 = sim.entities[plane].pos
	_check(AircraftOperations.step_land(sim, sim.entities[plane], {"kind": "land", "pos": point}, 0.1, false), "airport-loss fixture lands aircraft native=%s" % native)
	sim.entities[plane].ammo = 0
	var overhead: int = sim.debug_spawn(1, "sky_recon", point)
	sim.issue([plane], "return", sim.entities[field].pos)
	_check(not bool(sim.entities[plane].airborne) and sim.entities[plane].flight_state == "landed", "grounded return order waits in a valid landed state native=%s" % native)
	sim._kill_entity(field, true)
	sim.step(1.0 / 30.0)
	_check(not bool(sim.entities[plane].airborne) and sim.entities[plane].flight_state == "landed", "airport destruction preserves blocked takeoff and surface occupancy native=%s" % native)
	var path: String = "/tmp/paper_front_air_navigation_%s.save" % native
	_check(sim.save_game(path).is_empty(), "blocked airport-loss snapshot writes native=%s" % native)
	var restored = Sim.new()
	var error: String = restored.load_game(path)
	_check(error.is_empty() and not bool(restored.entities.get(plane, {}).get("airborne", true)), "blocked airport-loss snapshot validates and restores native=%s: %s" % [native, error])
	if not error.is_empty(): return
	restored.native_unit_dispatch_enabled = native
	restored.native_geometry_enabled = native
	restored._kill_entity(overhead, true)
	restored.step(1.0 / 30.0)
	_check(bool(restored.entities[plane].airborne) and restored.entities[plane].flight_state == "stranded", "restored aircraft takes off safely after overhead obstruction leaves native=%s" % native)

func _test_bounds_and_spawn(native: bool) -> void:
	var sim = _sim(native)
	var point := Vector2(5.5, 40.5)
	var first: int = sim.debug_spawn(0, "sky_recon", point)
	var second: int = sim.debug_spawn(0, "sky_recon", point)
	_check(first > 0 and second > 0 and (sim.entities[first].pos as Vector2).distance_to(sim.entities[second].pos) >= sim._radius(sim.entities[first]) + sim._radius(sim.entities[second]) + 0.02, "aircraft spawning reserves separate airspace native=%s" % native)
	var before: Vector2 = sim.entities[first].pos
	_check(not sim._fly_to(sim.entities[first], Vector2.INF, 1.0) and sim.entities[first].pos == before, "nonfinite air goals preserve aircraft position native=%s" % native)
	sim.issue([first], "move", Vector2(-100.0, -100.0))
	for _frame in range(180): sim.step(1.0 / 30.0)
	_check(sim._in_bounds(sim.entities[first].pos) and sim.entities[first].commands.is_empty(), "air goals clamp to map bounds native=%s" % native)
