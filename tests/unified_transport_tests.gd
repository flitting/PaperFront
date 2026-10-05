extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
const Transport = preload("res://scripts/unit_transport.gd")
const AircraftOperations = preload("res://scripts/aircraft_operations.gd")

class RepairAccountingSim:
	extends "res://tests/rule_test_simulation.gd"
	var paid_restoration: Dictionary = {}

	func _repair_health(e: Dictionary, amount: float) -> void:
		var before_hp: float = float(e.hp)
		super._repair_health(e, amount)
		var id: int = int(e.id)
		paid_restoration[id] = float(paid_restoration.get(id, 0.0)) + float(e.hp) - before_hp

var rules: Dictionary
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	rules = Rules.load_rules("res://data/rules.json", false)
	if rules.is_empty():
		push_error("Transport rules invalid: " + str(Rules.errors))
		quit(1)
		return
	_test_infantry_and_ground_carrier()
	_test_aircraft_field_landing()
	_test_airfield_apron()
	_test_four_aircraft_apron()
	_test_legacy_center_service_save()
	_test_apron_fallback_save()
	print("Unified transport checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _sim(faction: String):
	var sim = RepairAccountingSim.new()
	sim.setup(rules, "dev", 7, faction, false)
	sim.money.assign([100000.0, 100000.0])
	return sim

func _tick(sim, seconds: float) -> void:
	var elapsed: float = 0.0
	while elapsed < seconds - 0.000001:
		var delta: float = minf(1.0 / 30.0, seconds - elapsed)
		sim.step(delta)
		elapsed += delta

func _test_infantry_and_ground_carrier() -> void:
	for faction in ["rivet", "kestrel", "iron", "sky"]:
		_check(int(rules.units[faction + "_scout"].get("transport_capacity", 0)) >= 1, faction + " scout has a passenger seat")
	var sim = _sim("iron")
	var scout: int = sim.debug_spawn(0, "iron_scout", Vector2(22.5, 42.5))
	var engineer: int = sim.debug_spawn(0, "iron_engineer", Vector2(20.5, 42.5))
	_check(Transport.board_error(sim, engineer, scout).is_empty(), "ground engineer is eligible to board an empty scout")
	sim.issue([engineer], "board", sim.entities[scout].pos, scout)
	_tick(sim, 3.0)
	_check(Transport.is_loaded(sim.entities[engineer]), "engineer boards ground transport")
	var destination := Vector2(29.5, 42.5)
	sim.issue([scout], "unload_move", destination)
	_tick(sim, 8.0)
	_check(not Transport.is_loaded(sim.entities[engineer]) and sim.entities[scout].passengers.is_empty(), "ground carrier travels and unloads at selected destination")
	_check((sim.entities[engineer].pos as Vector2).distance_to(destination) < 2.2 and sim._standing(sim.entities[engineer].pos, sim._radius(sim.entities[engineer]), engineer), "ground unload uses nearby legal terrain")

func _test_aircraft_field_landing() -> void:
	var sim = _sim("iron")
	var aircraft: int = sim.debug_spawn(0, "iron_air_transport", Vector2(22.5, 42.5))
	var anti: int = sim.debug_spawn(0, "iron_anti", Vector2(19.5, 42.5))
	_check(aircraft > 0 and anti > 0, "air transport and specialist spawn")
	if aircraft < 0 or anti < 0: return
	_check(Transport.board_error(sim, anti, aircraft).is_empty(), "airborne transport accepts a specialist boarding request near legal ground")
	sim.issue([anti], "board", sim.entities[aircraft].pos, aircraft)
	_tick(sim, 7.0)
	_check(Transport.is_loaded(sim.entities[anti]) and sim.entities[aircraft].flight_state == "landed", "boarding order lands aircraft in the field and embarks specialist")
	_check(not bool(sim.entities[aircraft].airborne) and float(sim.entities[aircraft].flight_height) < 1.0, "landed aircraft has ground height")
	var landed_path: String = "/tmp/paper_front_landed_transport.save"
	_check(sim.save_game(landed_path).is_empty(), "landed transport snapshot writes")
	var landed_restore = Sim.new()
	var load_error: String = landed_restore.load_game(landed_path)
	_check(load_error.is_empty() and landed_restore.entities == sim.entities, "landed transport and passenger survive save/load: " + load_error)
	var destination := Vector2(30.5, 42.5)
	_check(AircraftOperations.land_error(sim, sim.entities[aircraft], destination).is_empty(), "chosen field landing point is legal")
	sim.issue([aircraft], "unload_move", destination)
	_tick(sim, 6.0)
	_check(sim.entities[aircraft].flight_state == "landed" and not Transport.is_loaded(sim.entities[anti]), "aircraft flies to selected ground, lands, and unloads")
	_check((sim.entities[anti].pos as Vector2).distance_to(destination) < 2.1 and sim._standing(sim.entities[anti].pos, sim._radius(sim.entities[anti]), anti), "field disembarkation places passenger on legal nearby land")
	sim.issue([aircraft], "move", Vector2(36.5, 42.5))
	_tick(sim, 0.2)
	_check(sim.entities[aircraft].flight_state == "airborne" and bool(sim.entities[aircraft].airborne), "move order launches a landed aircraft")
	sim.entities[aircraft].ammo = 0
	_tick(sim, 0.1)
	_check(sim.entities[aircraft].flight_state == "stranded", "aircraft without an airport becomes stranded when ammunition is exhausted")
	var emergency_goal := Vector2(37.5, 42.5)
	sim.issue([aircraft], "land", emergency_goal)
	_tick(sim, 2.0)
	_check(sim.entities[aircraft].flight_state == "landed" and (sim.entities[aircraft].pos as Vector2).distance_to(emergency_goal) < 0.2, "stranded aircraft can still land in the field")
	var water: Vector2 = Vector2.INF
	for y in range(sim.map.size):
		for x in range(sim.map.size):
			var point := Vector2(float(x) + 0.5, float(y) + 0.5)
			if not sim._land(point):
				water = point
				break
		if water.is_finite(): break
	if water.is_finite():
		_check(not AircraftOperations.land_error(sim, sim.entities[aircraft], water).is_empty(), "aircraft cannot land on water")

func _test_airfield_apron() -> void:
	var sim = _sim("iron")
	var field: int = sim.debug_spawn(0, "iron_airfield", Vector2(22.5, 30.5))
	var aircraft: int = sim.debug_spawn(0, "iron_air_transport", Vector2(26.5, 35.5))
	_check(field > 0 and aircraft > 0, "airport apron test entities spawn")
	if field < 0 or aircraft < 0: return
	var point: Vector2 = AircraftOperations.service_position(sim, sim.entities[aircraft], sim.entities[field])
	_check(point.is_finite() and AircraftOperations.land_error(sim, sim.entities[aircraft], point).is_empty(), "airport offers a legal service spot")
	var half: float = float(sim.data_for(sim.entities[field].spec).size) * 0.5
	_check(absf(point.x - sim.entities[field].pos.x) > half or absf(point.y - sim.entities[field].pos.y) > half, "service spot sits outside airport roof footprint")
	var full_hp: float = float(sim.data_for(sim.entities[aircraft].spec).hp)
	sim.entities[aircraft].hp = full_hp - 180.0
	var funds_before: float = sim.money[0]
	sim.issue([aircraft], "return", sim.entities[field].pos)
	_tick(sim, 2.0)
	_check(sim.entities[aircraft].flight_state == "rearming" and (sim.entities[aircraft].pos as Vector2).distance_to(point) < 0.2, "returning aircraft services outside airport footprint")
	var path: String = "/tmp/paper_front_unified_transport.save"
	_check(sim.save_game(path).is_empty(), "apron service snapshot writes")
	var restored = Sim.new()
	_check(restored.load_game(path).is_empty() and restored.entities == sim.entities, "apron service snapshot loads with same aircraft state")
	var partial_hp: float = float(sim.entities[aircraft].hp)
	var partial_funds: float = sim.money[0]
	sim.issue([aircraft], "move", Vector2(35.5, 35.5))
	_tick(sim, 0.2)
	_check(sim.entities[aircraft].flight_state == "airborne" and float(sim.entities[aircraft].hp) < full_hp, "explicit move interrupts service and launches with partial health")
	_check(absf(float(sim.entities[aircraft].hp) - partial_hp) < 0.001 and absf(sim.money[0] - partial_funds) < 0.001, "service interruption grants no free healing or extra charge")
	sim.issue([aircraft], "move", Vector2(35.5, 35.5))
	sim.entities[aircraft].ammo = 0
	_tick(sim, 7.0)
	_check(sim.entities[aircraft].flight_state == "rearming" and float(sim.entities[aircraft].hp) < full_hp and not sim.entities[aircraft].commands.is_empty(), "automatic return keeps its prior move queued while repair is incomplete")
	_tick(sim, 7.0)
	_check(float(sim.entities[aircraft].hp) >= full_hp - 0.001 and sim.entities[aircraft].flight_state == "airborne", "automatic return resumes prior move after full repair")
	var repair_spend: float = funds_before - sim.money[0]
	# Iron can regenerate during a long service trip. Only restoration performed
	# by the airport is billable; observe its actual HP gain independently.
	var paid_hp: float = float(sim.paid_restoration.get(aircraft, 0.0))
	_check(paid_hp > 0.0 and absf(repair_spend - paid_hp * float(rules.economy.repair_cost)) < 0.01, "airport spends exactly the HP it restores (spent %.3f for %.3f HP)" % [repair_spend, paid_hp])

func _test_four_aircraft_apron() -> void:
	var sim = _sim("iron")
	var field: int = sim.debug_spawn(0, "iron_airfield", Vector2(22.5, 30.5))
	var planes: Array[int] = []
	for offset in [Vector2(5, 5), Vector2(6, 4), Vector2(7, 5), Vector2(8, 4)]:
		planes.append(sim.debug_spawn(0, "iron_air_transport", sim.entities[field].pos + offset))
	_check(planes.size() == 4 and planes.all(func(id): return id > 0 and int(sim.entities[id].home_airfield) == field), "four aircraft reserve one airport")
	sim.issue(planes, "return", sim.entities[field].pos)
	_tick(sim, 0.1)
	var reserved: Dictionary = {}
	for id in planes: reserved[id] = sim.entities[id].get("service_goal", Vector2.INF)
	_tick(sim, 3.0)
	var all_parked: bool = true
	var stable: bool = true
	var separated: bool = true
	for id in planes:
		var e: Dictionary = sim.entities[id]
		all_parked = all_parked and e.flight_state == "rearming" and not bool(e.airborne) and AircraftOperations.land_error(sim, e, e.pos).is_empty()
		stable = stable and reserved[id].is_finite() and (e.service_goal as Vector2).is_equal_approx(reserved[id]) and (e.pos as Vector2).distance_to(reserved[id]) < 0.2
		for other_id in planes:
			if other_id <= id: continue
			var other: Dictionary = sim.entities[other_id]
			separated = separated and (e.pos as Vector2).distance_to(other.pos) >= 2.25 * 2.0 + 0.18
	_check(all_parked, "four returning aircraft reach legal apron positions outside the airport")
	_check(stable, "all four aircraft retain their initially reserved service goals")
	_check(separated, "four parked aircraft footprints do not overlap")

func _test_legacy_center_service_save() -> void:
	var sim = _sim("iron")
	var field: int = sim.debug_spawn(0, "iron_airfield", Vector2(22.5, 30.5))
	var plane: int = sim.debug_spawn(0, "iron_air_transport", Vector2(27.5, 35.5))
	var e: Dictionary = sim.entities[plane]
	e.pos = sim.entities[field].pos
	e.flight_state = "rearming"
	e.airborne = false
	e.flight_height = 0.35
	e.rearm_remaining = 3.0
	e.erase("service_goal")
	var path: String = "/tmp/paper_front_legacy_center_aircraft.save"
	_check(sim.save_game(path).is_empty(), "legacy center service snapshot writes")
	var restored = Sim.new()
	_check(restored.load_game(path).is_empty() and restored.entities[plane].flight_state == "rearming" and restored.entities[plane].pos == sim.entities[field].pos, "legacy airport-center service snapshot still loads")

func _test_apron_fallback_save() -> void:
	var sim = _sim("iron")
	var field: int = sim.debug_spawn(0, "iron_airfield", Vector2(22.5, 30.5))
	var plane: int = sim.debug_spawn(0, "iron_air_transport", Vector2(27.5, 35.5))
	var center: Vector2 = sim.entities[field].pos
	for offset in [Vector2(5.5, 0), Vector2(-5.5, 0), Vector2(0, 5.5), Vector2(0, -5.5)]:
		sim.debug_spawn(0, "iron_rifle", center + offset)
	var point: Vector2 = AircraftOperations.service_position(sim, sim.entities[plane], sim.entities[field])
	_check(point.is_finite() and point.distance_to(center) > 6.15, "blocked cardinal spots select a legal wider apron fallback")
	if not point.is_finite(): return
	var e: Dictionary = sim.entities[plane]
	e.pos = point
	e.service_goal = point
	e.flight_state = "rearming"
	e.airborne = false
	e.flight_height = 0.35
	e.rearm_remaining = 3.0
	var path: String = "/tmp/paper_front_apron_fallback.save"
	_check(sim.save_game(path).is_empty(), "fallback apron snapshot writes")
	var restored = Sim.new()
	var load_error: String = restored.load_game(path)
	_check(load_error.is_empty(), "fallback apron service snapshot loads: " + load_error)
