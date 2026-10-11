extends SceneTree

const Loader = preload("res://scripts/rules_loader.gd")
const Catalog = preload("res://scripts/wiki_catalog.gd")
const HUD = preload("res://scripts/paper_hud.gd")
const Simulation = preload("res://scripts/simulation.gd")
var checks: int = 0
var failures: Array[String] = []
var rules: Dictionary

func _initialize() -> void:
	rules = Loader.load_rules("res://data/rules.json", false)
	check(not rules.is_empty(), "current rules load before testing optional combat-model fields: " + str(Loader.errors))
	if rules.is_empty(): finish(); return
	test_loader()
	test_snapshot_wording()
	test_veteran_experience_reward()
	finish()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func model_rules(model: Variant) -> Dictionary:
	var result: Dictionary = rules.duplicate(true)
	result.combat_model = model
	return result

func modern_model() -> Dictionary:
	return {"partial_penetration_threshold":0.8,"partial_penetration_damage_multiplier":0.5,"non_penetrating_damage_multiplier":0.25}

func test_loader() -> void:
	var legacy: Dictionary = rules.duplicate(true)
	legacy.erase("combat_model")
	check(Loader.validate(legacy,false).is_empty(), "historical snapshots without combat_model remain valid")
	for model: Dictionary in [{},{"non_penetrating_damage_multiplier":0.25},modern_model(),{"partial_penetration_threshold":1.0,"partial_penetration_damage_multiplier":1.0,"non_penetrating_damage_multiplier":1.0},{"partial_penetration_threshold":0.8,"partial_penetration_damage_multiplier":0.0,"non_penetrating_damage_multiplier":0.0}]:
		check(Loader.validate(model_rules(model),false).is_empty(), "valid optional combat-model ratio boundaries load: " + str(model))
	for invalid: Variant in [null,[],"three bands",0]:
		check(Loader.validate(model_rules(invalid),false).any(func(issue):return issue.contains("$.combat_model: expected an object")), "combat_model must be an object: " + str(invalid))
	for only_field: String in ["partial_penetration_threshold","partial_penetration_damage_multiplier"]:
		var model: Dictionary = modern_model()
		model.erase(only_field)
		check(Loader.validate(model_rules(model),false).any(func(issue):return issue.contains("must be provided together")), "partial penetration fields are required as a pair: " + only_field)
	for field: String in ["partial_penetration_threshold","partial_penetration_damage_multiplier","non_penetrating_damage_multiplier"]:
		for invalid: Variant in [-0.01,1.01,INF,NAN,"0.8",true]:
			var model: Dictionary = modern_model()
			model[field] = invalid
			check(Loader.validate(model_rules(model),false).any(func(issue):return issue.contains("$.combat_model."+field)), "combat ratio rejects an invalid value at its own field: " + field + "=" + str(invalid))
	var zero_threshold: Dictionary = modern_model()
	zero_threshold.partial_penetration_threshold = 0.0
	check(not Loader.validate(model_rules(zero_threshold),false).is_empty(), "partial threshold must be greater than zero")
	for include_explicit_low: bool in [false,true]:
		var reversed: Dictionary = {"partial_penetration_threshold":0.8,"partial_penetration_damage_multiplier":0.2}
		if include_explicit_low: reversed.non_penetrating_damage_multiplier = 0.3
		check(Loader.validate(model_rules(reversed),false).any(func(issue):return issue.contains("must be at least non_penetrating_damage_multiplier")), "partial damage cannot be weaker than the explicit or default non-penetrating band")
	var path: String = "user://penetration_presentation_rules.json"
	var invalid_pair: Dictionary = model_rules({"partial_penetration_threshold":0.8})
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(invalid_pair)); file.close()
	check(Loader.load_rules(path,false).is_empty() and Loader.errors.any(func(issue):return issue.contains("must be provided together")), "file-backed loading rejects an incomplete combat model instead of partially loading it")
	file = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(legacy)); file.close()
	check(not Loader.load_rules(path,false).is_empty(), "file-backed loading still accepts a complete legacy snapshot")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func catalog_rule(snapshot: Dictionary) -> String:
	for section: Dictionary in Catalog.sections(snapshot,"kestrel_tank"):
		for row: Dictionary in section.rows:
			if row.label == "穿甲规则": return str(row.value)
	return ""

func tooltip(snapshot: Dictionary) -> String:
	var simulation = Simulation.new()
	simulation.rules = snapshot
	var hud = HUD.new()
	hud.sim = simulation
	var result: String = hud.spec_tooltip(snapshot.units.kestrel_tank)
	hud.free()
	return result

func test_snapshot_wording() -> void:
	var modern: Dictionary = model_rules(modern_model())
	var before: String = JSON.stringify(modern)
	var detail: String = catalog_rule(modern)
	var card: String = tooltip(modern)
	check(detail.contains("护甲为0时全额伤害") and detail.contains("穿透大于护甲") and detail.contains("达到护甲的80%且不超过护甲时造成50%") and detail.contains("低于护甲的80%时造成25%"), "wiki explains zero armor and the inclusive 80%-to-100% partial band")
	check(card.contains(Catalog.penetration_rule_text(modern,true)) and card.contains("80%至100%：50%") and card.contains("不足80%：25%"), "production/selection tooltip uses the same live three-band snapshot explanation")
	check(not card.contains("穿透≤护甲时伤害为1/4"), "modern tooltip no longer describes equality as quarter damage")
	check(JSON.stringify(modern) == before, "generating penetration explanations leaves the rules snapshot unchanged")
	var historical: Dictionary = model_rules({"non_penetrating_damage_multiplier":0.25})
	for text: String in [catalog_rule(historical),tooltip(historical)]:
		check(text.contains("穿透不超过护甲") and text.contains("25%") and not text.contains("80%") and not text.contains("50%") and not text.contains("护甲为0"), "legacy snapshots retain strict-greater two-band wording, including the zero/zero boundary")
	historical.erase("combat_model")
	check(catalog_rule(historical).contains("25%") and not tooltip(historical).contains("80%"), "snapshots without any combat model show the original quarter-damage rule")
	var customized: Dictionary = model_rules({"partial_penetration_threshold":0.75,"partial_penetration_damage_multiplier":0.6,"non_penetrating_damage_multiplier":0.3})
	for text: String in [catalog_rule(customized),tooltip(customized)]:
		check(text.contains("75%") and text.contains("60%") and text.contains("30%") and not text.contains("80%"), "both interfaces read thresholds and damage ratios from the supplied snapshot rather than current disk rules")

func test_veteran_experience_reward() -> void:
	var field: String = "veteran_kill_experience_multiplier"
	for value: float in [1.0,2.0,2.5]:
		var snapshot: Dictionary = rules.duplicate(true)
		snapshot.experience[field] = value
		var before: String = JSON.stringify(snapshot)
		check(Loader.validate(snapshot,false).is_empty(), "starred-enemy experience multiplier accepts finite values >=1: " + str(value))
		var expected: String = "击杀星级敌军经验×" + Catalog._number(value)
		check(tooltip(snapshot).contains(expected), "unit tooltip shows the supplied snapshot's starred-enemy experience reward")
		var found: bool = false
		for section: Dictionary in Catalog.sections(snapshot,"kestrel_tank"):
			for row: Dictionary in section.rows:
				if row.label == "经验获取" and row.value == expected: found = true
		check(found, "unit encyclopedia shows the same starred-enemy experience reward")
		check(JSON.stringify(snapshot) == before, "experience presentation leaves the active snapshot unchanged")
	for invalid: Variant in [-1.0,0.0,0.99,INF,NAN,"2",true]:
		var snapshot: Dictionary = rules.duplicate(true)
		snapshot.experience[field] = invalid
		check(Loader.validate(snapshot,false).any(func(issue):return issue.contains("$.experience."+field)), "starred-enemy experience multiplier rejects a non-finite, nonnumeric or sub-one value: " + str(invalid))
	var legacy: Dictionary = rules.duplicate(true)
	legacy.experience.erase(field)
	check(Loader.validate(legacy,false).is_empty() and tooltip(legacy).contains("击杀星级敌军经验×1"), "legacy snapshots missing the new experience field keep the original onefold reward")
	legacy.erase("experience")
	check(Loader.validate(legacy,false).is_empty() and Catalog.veteran_kill_experience_text(legacy) == "击杀星级敌军经验×1", "legacy snapshots without an experience section also use onefold reward")
	var path: String = "user://veteran_experience_presentation_rules.json"
	var invalid_file: Dictionary = rules.duplicate(true)
	invalid_file.experience[field] = 0.5
	var file: FileAccess = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(invalid_file)); file.close()
	check(Loader.load_rules(path,false).is_empty() and Loader.errors.any(func(issue):return issue.contains("$.experience."+field)), "file-backed loading rejects an invalid starred-enemy reward")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func finish() -> void:
	print("PENETRATION_PRESENTATION " + JSON.stringify({"checks":checks,"failures":failures}))
	for message: String in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)
