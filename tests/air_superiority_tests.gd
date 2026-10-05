extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const FACTIONS: Array[String] = ["kestrel", "rivet", "iron", "sky"]
var rules: Dictionary
var failures: Array[String] = []
var checks := 0
var most_shots := 0

func _initialize() -> void:
	rules = RulesLoader.load_rules("res://data/rules.json", false)
	if rules.is_empty():
		push_error("Air superiority rules invalid: " + str(RulesLoader.errors))
		quit(1)
		return
	for native_dispatch in [false, true]:
		for attacker in FACTIONS:
			for defender in FACTIONS:
				_duel(attacker, defender, native_dispatch)
		for attacker in FACTIONS:
			_last_shot_after_return(attacker, native_dispatch)
	print("AIR_SUPERIORITY checks=%d max_shots=%d failures=%s" % [checks, most_shots, str(failures)])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _duel(attacker: String, defender: String, native_dispatch: bool) -> void:
	var sim = Sim.new()
	sim.setup_multiteam(rules, "dev", 7, [attacker, defender], false)
	sim.native_unit_dispatch_enabled = native_dispatch
	if not native_dispatch: sim.native_geometry_enabled = false
	var base: Vector2 = Vector2(16.5, 29.5)
	var airfield: int = sim.debug_spawn(0, attacker + "_airfield", base)
	if airfield > 0: sim.entities[airfield].gift_pending = false
	var source: int = sim.debug_spawn(0, attacker + "_fighter", Vector2(20.5, 38.5))
	var victim: int = sim.debug_spawn(1, defender + "_fighter", Vector2(27.5, 38.5))
	var label: String = "%s>%s native=%s" % [attacker, defender, str(native_dispatch)]
	_check(airfield > 0 and source > 0 and victim > 0, label + " spawn")
	if airfield < 0 or source < 0 or victim < 0: return
	# No defensive airport: the target stays airborne without service and moves
	# laterally each tick. The attacker uses its normal attack order and may return
	# before its last in-flight missile lands.
	sim.entities[victim].flight_state = "stranded"
	sim.entities[victim].home_airfield = -1
	sim.issue([source], "attack", sim.entities[victim].pos, victim)
	var shots := 0
	var event_cursor: int = sim.events.size()
	for frame in range(12 * 30):
		if not sim.entities.has(victim): break
		sim.entities[victim].pos = Vector2(27.5 + sin(float(frame) * 0.10) * 0.8, 38.5 + cos(float(frame) * 0.07) * 0.45)
		sim.step(1.0 / 30.0)
		for index in range(event_cursor, sim.events.size()):
			var event: Dictionary = sim.events[index]
			if event.get("kind", "") == "fire" and int(event.get("id", -1)) == source: shots += 1
		event_cursor = sim.events.size()
	_check(not sim.entities.has(victim), label + " moving enemy killed within one sortie")
	_check(shots > 0 and shots <= 8, label + " within eight real launched shots")
	most_shots = maxi(most_shots, shots)

func _last_shot_after_return(attacker: String, native_dispatch: bool) -> void:
	var sim = Sim.new()
	sim.setup_multiteam(rules, "dev", 7, [attacker, "rivet"], false)
	sim.native_unit_dispatch_enabled = native_dispatch
	if not native_dispatch: sim.native_geometry_enabled = false
	var field: int = sim.debug_spawn(0, attacker + "_airfield", Vector2(16.5, 29.5))
	var source: int = sim.debug_spawn(0, attacker + "_fighter", Vector2(20.5, 38.5))
	var victim: int = sim.debug_spawn(1, "rivet_fighter", Vector2(27.5, 38.5))
	var label: String = "%s final missile native=%s" % [attacker, str(native_dispatch)]
	_check(field > 0 and source > 0 and victim > 0, label + " spawn")
	if field < 0 or source < 0 or victim < 0: return
	sim.entities[victim].flight_state = "stranded"
	sim.entities[victim].home_airfield = -1
	sim.entities[victim].hp = float(rules.weapons[attacker + "_fighter"].damage) * 0.5
	sim.entities[source].ammo = 1
	sim.issue([source], "attack", sim.entities[victim].pos, victim)
	var launched := false
	for frame in range(3 * 30):
		sim.step(1.0 / 30.0)
		if int(sim.entities[source].ammo) == 0:
			launched = true
			_check(sim.entities[source].flight_state == "returning" and not sim.projectiles.is_empty(), label + " returns with missile in flight")
			break
	_check(launched, label + " launch")
	for frame in range(30):
		if not sim.entities.has(victim): break
		sim.step(1.0 / 30.0)
	_check(not sim.entities.has(victim), label + " missile settles after return")
