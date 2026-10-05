extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const FACTIONS: Array[String] = ["kestrel", "rivet", "iron", "sky"]
var rules: Dictionary
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	rules = RulesLoader.load_rules("res://data/rules.json", false)
	if rules.is_empty():
		push_error("Economy rules invalid: " + str(RulesLoader.errors))
		quit(1)
		return
	var incomes: Array[float] = []
	for faction in FACTIONS:
		var spec: Dictionary = rules.units[faction + "_harvester"]
		_check(is_equal_approx(float(spec.speed), 3.0) and is_equal_approx(float(spec.turn_speed), 120.0) and is_equal_approx(float(spec.radius), 0.75), faction + " harvester movement parity")
		incomes.append(_income(faction))
	for index in range(1, incomes.size()):
		_check(absf(incomes[index] - incomes[0]) <= 1.0, "%s equal 75s actual delivery income: %s" % [FACTIONS[index], str(incomes)])
	print("ECONOMY_PARITY incomes=%s checks=%d failures=%s" % [str(incomes), checks, str(failures)])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _income(faction: String) -> float:
	var sim = Sim.new()
	sim.setup_multiteam(rules, "dev", 7, [faction, "rivet"], false)
	sim.money.assign([10000.0, 10000.0])
	var mine: Vector2 = sim.mines[1].pos
	var refinery: int = sim.debug_spawn(0, faction + "_refinery", mine + Vector2(-7.0, 0.0))
	_check(refinery > 0, faction + " refinery spawn")
	if refinery < 0: return -1.0
	sim.entities[refinery].gift_pending = false
	var miner: int = sim.debug_spawn(0, faction + "_harvester", mine + Vector2(-1.55, 0.0))
	_check(miner > 0, faction + " harvester spawn")
	if miner < 0: return -1.0
	sim.issue([miner], "harvest", mine, 1)
	var initial: float = sim.money[0]
	for frame in range(75 * 30): sim.step(1.0 / 30.0)
	_check(float(sim.entities[miner].cargo) >= 0.0, faction + " miner survives")
	return float(sim.money[0]) - initial
