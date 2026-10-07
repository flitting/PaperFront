extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
var failures: Array[String] = []
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _initialize() -> void:
	var rules := RulesLoader.load_rules()
	check(not rules.is_empty(), "Full first-release catalog validates: " + str(RulesLoader.errors))
	if rules.is_empty():
		quit(1)
		return
	check(rules.factions.kestrel.name == "正典军团" and rules.factions.rivet.name == "重锤军团", "Current public faction names")
	check(rules.player_colors == ["e7ad42", "41c7c6"], "Player colors are independent of faction livery")
	var catalog_sim = Sim.new()
	catalog_sim.rules = rules
	catalog_sim.factions.assign(["kestrel", "rivet"])
	for faction in ["kestrel", "rivet"]:
		for art in ["rifle", "anti", "engineer", "harvester", "scout", "tank", "aa", "fighter", "advanced"]:
			check(rules.units.has(faction + "_" + art), "Required unit: " + faction + "_" + art)
		for art in ["hq", "outpost", "power", "refinery", "barracks", "factory", "repair", "command", "tech", "airfield"]:
			if faction == "rivet" and art == "outpost": continue
			var spec_id: String = catalog_sim.building_spec(0 if faction == "kestrel" else 1, art)
			check(not spec_id.is_empty() and rules.buildings.has(spec_id), "Required infrastructure role: " + faction + "/" + art)
	check(catalog_sim.building_spec(1, "hq") == "rivet_hq" and catalog_sim.building_spec(1, "barracks") == "rivet_hq", "Rivet base and infantry production resolve to one blueprint")
	check(not rules.buildings.has("rivet_barracks") and not rules.buildings.has("rivet_outpost") and rules.buildings.rivet_hq.name == "基地兵营", "Rivet catalog contains only its unified base barracks")
	for category in ["units", "buildings"]:
		for id in rules[category]:
			var spec: Dictionary = rules[category][id]
			check(not str(spec.get("formal_name", "")).is_empty() and str(spec.get("description", "")).length() > 15, "Useful Chinese description: " + id)
			var infantry: bool = category=="units" and spec.art in ["rifle","anti","engineer","demolition"]
			check(VolumeModels.supports(spec, "unit" if category == "units" else "building") != infantry, "Requested paper infantry / volume equipment: " + id)
			if infantry:
				for animation in spec.animations.values():
					check(ResourceLoader.exists(str(animation).trim_suffix(".svg")+"_identity.svg"), "Explicit paper player-color mask: " + id)
			for animation in spec.animations.values(): check(ResourceLoader.exists(animation), "Imported role card: " + animation)
			if category == "units":
				for action in ["select", "move", "attack", "ready"]:
					check(spec.get("voices", {}).get(action, []).size() > 0, "Unit-specific voice line: " + id + "/" + action)
	check(rules.units.kestrel_fighter.domain == "air" and rules.units.rivet_bomber.domain == "air", "Both factions field aviation")
	check(rules.weapons.kestrel_aa.targets == ["air"] and rules.weapons.rivet_aa.targets == ["air"], "Both factions have dedicated counters")
	check(rules.weapons.kestrel_attacker.targets == ["ground"] and rules.weapons.rivet_bomber.targets == ["ground"], "Distinct aviation roles")
	print("faction_catalog_tests: %d checks, %d failures" % [checks, failures.size()])
	for message in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)
