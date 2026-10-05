extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var rules: Dictionary = Rules.load_rules("res://data/rules.json", false)
	var sim = Sim.new()
	sim.setup_campaign(rules, 77)
	check(sim.map.get("mode", "") == "campaign" and int(sim.map.get("size", 0)) == 320, "campaign map starts")
	check(sim.factions == ["kestrel", "rivet"] and sim.campaign_controller != null, "campaign scenario and controller")
	check(not bool(sim._bridge_by_id(1).alive), "bridge begins destroyed")
	check(sim.availability(0, "kestrel_tank").contains("战役"), "future purchase explains campaign lock")
	var initial_count: int = sim.entities.size()
	sim.step(0.1)
	check(sim.result == "", "campaign victory gate ignores ordinary building count")
	var save_path: String = "user://stage4_campaign_test.pfront"
	check(sim.save_game(save_path).is_empty(), "campaign save")
	var restored = Sim.new()
	check(restored.load_game(save_path).is_empty(), "campaign load")
	check(restored.campaign_controller != null and restored.campaign_controller.stage == sim.campaign_controller.stage, "objective state restores")
	check(restored.entities.size() == initial_count and not bool(restored._bridge_by_id(1).alive), "load does not redeploy and bridge persists")
	restored.step(0.1)
	check(restored.result == "", "restored campaign steps")
	print("Stage4 campaign integration checks: %d failed" % failures.size())
	for failure in failures: push_error(failure)
	quit(1 if not failures.is_empty() else 0)
