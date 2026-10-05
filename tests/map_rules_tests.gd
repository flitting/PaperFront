extends SceneTree

const MapScript = preload("res://scripts/map_data.gd")
const RulesScript = preload("res://scripts/rules_loader.gd")
var checks: int = 0
var failed: Array[String] = []


func _initialize() -> void:
	var rules: Dictionary = RulesScript.load_rules("res://data/rules.json", false)
	_check(not rules.is_empty(), "default rules validate without requiring imported assets: %s" % str(RulesScript.errors))
	if not rules.is_empty():
		_check(rules.factions.size() == 4 and _catalog_complete(rules), "four-faction roster accounts for every configured unit, building and weapon")
		_check(rules.units.rivet_assault.crush and not rules.units.rivet_harvester.crush, "crush permissions differ from generic vehicle status")
		var bad_rules: Dictionary = rules.duplicate(true)
		bad_rules.weapons.rivet_rifle.interval = 0
		_check(not RulesScript.validate(bad_rules, false).is_empty(), "zero weapon interval rejected")
		bad_rules = rules.duplicate(true)
		bad_rules.units.rivet_rifle.weapon = "missing_weapon"
		_check(not RulesScript.validate(bad_rules, false).is_empty(), "unknown weapon reference rejected")
		bad_rules = rules.duplicate(true)
		bad_rules.buildings.rivet_hq.requires = ["rivet_factory"]
		_check(not RulesScript.validate(bad_rules, false).is_empty(), "building prerequisite cycle rejected")
		bad_rules = rules.duplicate(true)
		bad_rules.units.kestrel_tank.animations.erase("attack")
		_check(not RulesScript.validate(bad_rules, false).is_empty(), "missing combat animation rejected")
		_check(not RulesScript._duplicate_keys('{"units":{"rivet_rifle":{},"rivet_rifle":{}}}').is_empty(), "duplicate JSON stable ID detected before parsing")
		_check(RulesScript.validate(rules, true).is_empty(), "all required paper animation assets exist: %s" % str(RulesScript.validate(rules, true)))
	for mode: String in ["dev", "handmade", "random"]:
		var map: Dictionary = MapScript.generate(mode, 20260930)
		_check(map.valid, "%s validates: %s" % [mode, str(map.get("validation_errors", []))])
		_check(map.size == (48 if mode == "dev" else 160), "%s has documented dimensions" % mode)
		var again: Dictionary = MapScript.generate(mode, 20260930)
		_check(JSON.stringify(map) == JSON.stringify(again), "%s generation is seed deterministic" % mode)
		var damaged: Dictionary = map.duplicate(true)
		for z: int in int(damaged.size):
			damaged.terrain[z][int(damaged.size) / 2] = MapScript.WATER
		_check(not MapScript.validate(damaged).is_empty(), "%s broken permanent land route rejected" % mode)
	for seed: int in range(32):
		var random_map: Dictionary = MapScript.generate("random", seed)
		_check(random_map.valid and MapScript.validate(random_map).is_empty(), "random seed %d valid and resources / permanent land / terraces reachable" % seed)
	for seed: int in [-2147483648, -37, -1, 2147483647]:
		for mode: String in ["dev", "handmade", "random"]:
			var seeded_map: Dictionary = MapScript.generate(mode, seed)
			_check(seeded_map.valid and MapScript.validate(seeded_map).is_empty(), "%s accepts signed seed %d" % [mode, seed])
	print("Map / rules checks: %d passed, %d failed" % [checks - failed.size(), failed.size()])
	for problem: String in failed:
		push_error(problem)
	quit(0 if failed.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed.append(message)


func _catalog_complete(rules: Dictionary) -> bool:
	var ids: Dictionary = {}
	var used_weapons: Dictionary = {}
	for category: String in ["units", "buildings"]:
		var accounted: int = 0
		for faction: String in rules.factions:
			var faction_count: int = 0
			for id: String in rules[category]:
				var spec: Dictionary = rules[category][id]
				if spec.faction != faction: continue
				if ids.has(id): return false
				ids[id] = true
				faction_count += 1
				accounted += 1
				var weapon_id: String = str(spec.get("weapon", ""))
				if not weapon_id.is_empty():
					if not rules.weapons.has(weapon_id): return false
					used_weapons[weapon_id] = true
			if faction_count == 0: return false
		if accounted != rules[category].size(): return false
	return used_weapons.size() == rules.weapons.size()
