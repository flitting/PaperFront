extends SceneTree

const Sim = preload("res://scripts/simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
const Operations = preload("res://scripts/naval_operations.gd")
var failures: Array[String] = []
var checks: int = 0

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _tick(sim, seconds: float) -> void:
	for step in range(ceili(seconds * 20.0)):
		sim.step(0.05)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	OS.set_environment("PAPER_FRONT_DISABLE_NATIVE", "1")
	var rules: Dictionary = Rules.load_rules("res://data/rules.json", false)
	_check(not rules.is_empty(), "naval rules pass schema validator: " + str(Rules.errors))
	if rules.is_empty():
		_report()
		return
	var sim = Sim.new()
	sim.setup_multiteam(rules, "islands", 31, ["rivet", "kestrel"], false)
	_check(sim.map.get("valid", false), "islands map is valid")
	var harbors: Array = sim.map.get("harbors", [])
	_check(harbors.size() >= 2, "two physical harbors exist")
	if harbors.size() < 2:
		_report()
		return
	var origin: Dictionary = {}
	var destination: Dictionary = {}
	for harbor:Dictionary in harbors:
		if harbor.get("role")!="home":continue
		if int(harbor.get("team",-1))==0:origin=harbor
		if int(harbor.get("team",-1))==1:destination=harbor
	var yard_pos: Vector2 = Vector2.INF
	for z in range(int(origin.land_pos.y) - 8, int(origin.land_pos.y) + 9):
		if yard_pos.is_finite(): break
		for x in range(int(origin.land_pos.x) - 12, int(origin.land_pos.x) + 13):
			var candidate := Vector2(x, z)
			if Operations.shipyard_site_error(sim, 0, rules.buildings.rivet_shipyard, candidate).is_empty():
				yard_pos = candidate
				break
	_check(yard_pos.is_finite(), "shipyard has a legal full-water footprint in the owned harbor")
	if yard_pos.is_finite():
		var yard: Dictionary = {"spec": "rivet_shipyard", "pos": yard_pos}
		_check(Operations.spawn_point(sim, yard, "rivet_ship_transport").is_finite(), "shipyard has a physical water-side production exit")
	var ship: int = sim.debug_spawn(0, "rivet_ship_transport", origin.water_pos)
	var soldier: int = sim.debug_spawn(0, "rivet_rifle", origin.land_pos)
	_check(ship > 0 and soldier > 0, "ship and infantry spawn in their domains")
	if ship < 0 or soldier < 0:
		_report()
		return
	_check(sim._terrain(sim.entities[ship].pos) == 1 and sim._terrain(sim.entities[soldier].pos) != 1, "initial domain terrain is correct")
	var initial: Vector2 = sim.entities[soldier].pos
	sim.issue([soldier], "board", sim.entities[ship].pos, ship)
	for i in range(500):
		sim.step(0.05)
		# Keep the production path worker. A tight headless loop can consume
		# its entire simulated deadline before the worker gets CPU time.
		OS.delay_msec(1)
		await process_frame
		if int(sim.entities[soldier].get("transport_id", -1)) == ship: break
	print("Naval integration real worker: %d submitted, %d completed; boarding after %.2f simulation seconds" % [int(sim.navigation_stats.submitted), int(sim.navigation_stats.completed), sim.time])
	_check(int(sim.entities[soldier].get("transport_id", -1)) == ship, "infantry boards at a reachable coast")
	_check(sim.entities[soldier].pos.distance_to(initial) > 0.5, "boarding involves physical movement")
	if int(sim.entities[soldier].get("transport_id", -1)) == ship:
		sim.issue([ship], "unload_move", destination.land_pos)
		for i in range(2200):
			sim.step(0.1)
			if i % 200 == 0:
				var e: Dictionary = sim.entities[ship]
				print("SHIP_DIAGNOSTIC ",JSON.stringify({"time":sim.time,"pos":e.pos,"state":e.state,"naval_path":e.get("naval_path",[]),"goal":e.get("naval_path_goal",Vector2.INF),"commands":e.commands,"notices":sim.notices}))
			OS.delay_msec(1)
			await process_frame
			if int(sim.entities[soldier].get("transport_id", -1)) < 0: break
		_check(int(sim.entities[soldier].get("transport_id", -1)) < 0, "ship crosses water and unloads on far island")
		if int(sim.entities[soldier].get("transport_id", -1)) < 0:
			_check(sim._terrain(sim.entities[soldier].pos) != 1, "unloaded infantry stands on land")
			_check(sim.entities[soldier].pos.distance_to(destination.land_pos) < 20.0, "unload uses destination shore")
	_report()

func _report() -> void:
	print("Naval integration checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	for item: String in failures: push_error(item)
	quit(0 if failures.is_empty() else 1)
