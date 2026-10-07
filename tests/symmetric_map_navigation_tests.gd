extends SceneTree

const SIM = preload("res://tests/rule_test_simulation.gd")
const RULES = preload("res://scripts/rules_loader.gd")
var checks: int = 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _initialize() -> void:
	var rules: Dictionary = RULES.load_rules()
	var sim = SIM.new()
	sim.setup(rules,"symmetric",73026,"kestrel",false)
	check(sim.map.valid and sim.factions.size() == 2 and sim.counts(0).y == 1 and sim.counts(1).y == 1, "normal game setup deploys both headquarters on the authored starts")
	check(bool(sim.match_options.modern) and sim.vision_enabled, "symmetry map uses current skirmish and scouting rules")
	for radius: float in [.35,1.0,2.2]:
		for route: Array in [[Vector2(40,96),Vector2(152,96)], [Vector2(40,64),Vector2(152,64)], [Vector2(40,128),Vector2(152,128)],
			[Vector2(32,72),Vector2(32,8)], [Vector2(96,72),Vector2(96,8)], [Vector2(160,72),Vector2(160,8)],
			[Vector2(32,120),Vector2(32,184)], [Vector2(96,120),Vector2(96,184)], [Vector2(160,120),Vector2(160,184)]]:
			var path: Array = sim._path_between(route[0],route[1],radius,-1)
			check(not path.is_empty(), "ground route remains legal with scenery and mine collisions at radius %.2f: %s" % [radius,str(route)])
	var save_path: String = "user://symmetric_map_navigation_%d.save" % OS.get_process_id()
	check(sim.save_game(save_path).is_empty(), "symmetry map saves through the normal match format")
	var restored = SIM.new()
	var error: String = restored.load_game(save_path)
	var mines_preserved: bool = restored.mines.size() == sim.mines.size()
	for index: int in mini(restored.mines.size(),sim.mines.size()):
		for key: String in ["pos","capacity","amount"]:
			mines_preserved = mines_preserved and restored.mines[index][key] == sim.mines[index][key]
	check(error.is_empty() and restored.map == sim.map and restored.ruins == sim.ruins and mines_preserved, "symmetry map and neutral/resource geometry round-trip without regeneration: %s" % error)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	print("Symmetric navigation checks: %d passed, %d failed" % [checks-failures.size(),failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
