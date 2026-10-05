extends SceneTree

const Catalog = preload("res://scripts/wiki_catalog.gd")
const Rules = preload("res://scripts/rules_loader.gd")
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	var rules: Dictionary = Rules.load_rules("res://data/rules.json", false)
	_check(not rules.is_empty(), "The catalog loads the real rule fixture: " + str(Rules.errors))
	if rules.is_empty():
		quit(1)
		return
	var before: String = JSON.stringify(rules)
	_test_roster_and_search(rules)
	_test_complete_numeric_coverage(rules)
	_test_future_fields(rules)
	_test_meaningful_rules(rules)
	_check(JSON.stringify(rules) == before, "Generating and searching catalog tables leaves live rules unchanged")
	var returned: Array[Dictionary] = Catalog.entries(rules)
	returned[0].spec["hp"] = -999
	_check(JSON.stringify(rules) == before, "Returned entry specs do not expose mutable live rule dictionaries")
	print("wiki_catalog_tests: %d checks, %d failures" % [checks, failures.size()])
	for message: String in failures: push_error(message)
	quit(0 if failures.is_empty() else 1)


func _test_roster_and_search(rules: Dictionary) -> void:
	var all: Array[Dictionary] = Catalog.entries(rules)
	_check(all.size() == rules.units.size() + rules.buildings.size(), "Every configured unit and building is browseable")
	var ids: Dictionary = {}
	for entry: Dictionary in all:
		_check(not ids.has(entry.id), "Roster contains no duplicate ID: " + str(entry.id))
		ids[entry.id] = true
		var category: String = "units" if entry.kind == "unit" else "buildings"
		_check(entry.spec == rules[category][entry.id], "Entry preserves its source spec: " + str(entry.id))
		_check(not str(entry.formal_name).is_empty() and not str(entry.description).is_empty(), "Entry includes authored introduction: " + str(entry.id))
	for faction: String in rules.factions:
		for kind: String in ["unit", "building"]:
			var expected: int = 0
			var category: String = "units" if kind == "unit" else "buildings"
			for id: Variant in rules[category]:
				if rules[category][id].faction == faction: expected += 1
			var group: Array[Dictionary] = Catalog.entries(rules, faction, kind)
			_check(group.size() == expected, "Faction and kind filter matches full source group: " + faction + "/" + kind)
	_check(Catalog.entries(rules, "", "", "防御围墙").size() == 2, "Shared-name search reaches both factions")
	_check(Catalog.entries(rules, "", "", "正典军团").size() == Catalog.entries(rules, "kestrel").size(), "Search includes public faction name")
	_check(Catalog.entries(rules, "", "", "再说一遍式重轰炸机").size() == 1, "Search includes formal names")
	_check(Catalog.entries(rules, "", "", "精确支援").size() >= 1, "Search includes authored descriptions")
	_check(Catalog.entries(rules, "", "", "  KESTREL_TANK ").size() == 1, "Search trims whitespace and ignores case")
	_check(Catalog.entries(rules, "rivet", "unit", "kestrel").is_empty(), "Search cannot escape a faction filter")
	_check(Catalog.entries(rules, "", "units").size() == rules.units.size(), "Plural kind alias is supported")
	_check(Catalog.entries(rules, "", "unit", "正典军团 校正炮").size() == 1, "Each search term must match the chosen entry")
	_check(Catalog.entries(rules, "unknown").is_empty() and Catalog.entries(rules, "", "weapon").is_empty(), "Unknown groups are empty")
	_check(Catalog.sections(rules, "missing").is_empty(), "Unknown detail IDs are empty")
	var reordered: Dictionary = rules.duplicate(true)
	for category: String in ["units", "buildings"]:
		var reversed: Dictionary = {}
		var keys: Array = rules[category].keys()
		keys.reverse()
		for id: Variant in keys: reversed[id] = rules[category][id]
		reordered[category] = reversed
	var reordered_entries: Array[Dictionary] = Catalog.entries(reordered)
	for index: int in all.size():
		_check(all[index].id == reordered_entries[index].id, "Catalog order is independent of JSON insertion order")


func _test_complete_numeric_coverage(rules: Dictionary) -> void:
	var used_weapons: Dictionary = {}
	for entry: Dictionary in Catalog.entries(rules):
		var tables: Array[Dictionary] = Catalog.sections(rules, entry.id)
		_check(not tables.is_empty(), "Each browseable entry has detail tables: " + str(entry.id))
		var actual: Dictionary = _source_values(tables)
		var category: String = "units" if entry.kind == "unit" else "buildings"
		var expected: Dictionary = {}
		_numeric_leaves(entry.spec, category + "." + entry.id, expected)
		var weapon_id: String = str(entry.spec.get("weapon", ""))
		if not weapon_id.is_empty():
			used_weapons[weapon_id] = true
			_numeric_leaves(rules.weapons[weapon_id], "weapons." + weapon_id, expected)
		for path: String in expected:
			_check(actual.has(path) and actual[path] == expected[path], "Every numerical / boolean source value is displayed unchanged: " + path)
		for section: Dictionary in tables:
			_check(not str(section.title).is_empty() and not section.rows.is_empty(), "Every table has a useful title and content")
			for row: Dictionary in section.rows:
				_check(not str(row.label).is_empty() and not str(row.value).is_empty(), "Every statistic has a label and display value")
				_check(not str(row.value).contains("res://") and not str(row.value).contains(".svg") and not str(row.value).contains(".png"), "Technical asset paths stay out of product tables")
	_check(used_weapons.size() == rules.weapons.size(), "The catalog exposes every configured weapon through its owning entity")


func _test_future_fields(rules: Dictionary) -> void:
	var future: Dictionary = rules.duplicate(true)
	future.units.kestrel_tank["new_numeric"] = 17.25
	future.units.kestrel_tank["tiny_numeric"] = 0.00000012
	future.units.kestrel_tank["new_behavior"] = true
	future.units.kestrel_tank["new_nested"] = {"bonus": [3.5, false, {"minimum": 0.125}], "resource": "res://hidden.png"}
	future.units.kestrel_tank.animations["asset_metadata"] = {"frames": 99}
	future.weapons.kestrel_tank["future_ballistics"] = {"spread": 0.03, "enabled": false}
	future.weapons.kestrel_tank["multipliers"] = {"new_armor": 1.7}
	future.economy["future_economy"] = {"tax": 0.2, "enabled": true}
	var tables: Array[Dictionary] = Catalog.sections(future, "kestrel_tank")
	var actual: Dictionary = _source_values(tables)
	var expected: Dictionary = {}
	_numeric_leaves(future.units.kestrel_tank, "units.kestrel_tank", expected)
	_numeric_leaves(future.weapons.kestrel_tank, "weapons.kestrel_tank", expected)
	_numeric_leaves(future.economy.future_economy, "economy.future_economy", expected)
	for path: String in expected:
		_check(actual.has(path) and actual[path] == expected[path], "Unknown nested rule values remain discoverable: " + path)
	_check(not actual.has("units.kestrel_tank.animations.asset_metadata.frames"), "Asset internals are excluded even if they contain numbers")
	_check(_all_text(tables).contains("扩展参数") and not _all_text(tables).contains("res://hidden.png"), "Future fields receive a Chinese fallback without exposing resource paths")
	var tiny_display: String = _row_value(tables, "扩展参数（tiny numeric）")
	_check(not tiny_display.is_empty() and tiny_display != "0", "Tiny numerical parameters are not displayed as zero")
	var zero_speed: Dictionary = rules.duplicate(true)
	zero_speed.economy.low_power_multiplier = 0.0
	_check(_all_text(Catalog.sections(zero_speed, "kestrel_fighter")).contains("暂停补给"), "Zero low-power multiplier does not cause division by zero")


func _test_meaningful_rules(rules: Dictionary) -> void:
	var tank: Array[Dictionary] = Catalog.sections(rules, "kestrel_tank")
	_check(_row_value(tank, "生产设施") == "拱架装配厂", "Producer role resolves to the current faction's authored building name")
	_check(_row_value(Catalog.sections(rules, "kestrel_fighter"), "前置设施").contains("战术审定台"), "Prerequisite IDs resolve to Chinese names")
	_check(_row_value(tank, "基础理论每秒伤害") == "35 生命/秒", "Basic DPS is explicitly named as a derived theoretical statistic")
	var scout: Array[Dictionary] = Catalog.sections(rules, "kestrel_scout")
	_check(_source_values(scout).get("weapons.kestrel_scout.multipliers.infantry") == 1.6, "Nested armor multiplier is displayed")
	_check(_row_value(scout, "对步兵理论每秒伤害").begins_with("34.909"), "Per-armor DPS uses actual weapon multipliers")
	_check(_row_value(scout, "步兵运输容量") == "%d 名地面步兵" % int(rules.units.kestrel_scout.transport_capacity) and _row_value(scout, "步兵运输规则").contains("卸载按钮") and _row_value(scout, "步兵运输规则").contains("工程兵、反甲兵"), "Scout transport capacity and the complete ground-infantry unload workflow are documented")
	var workshop: Array[Dictionary] = Catalog.sections(rules, "kestrel_repair")
	_check(_row_value(workshop, "支援维修满速耗费") == "3.6 资金/秒", "Repair station expense is repair_rate times actual per-health cost")
	_check(_row_value(workshop, "建筑自修速度") == "22 生命/秒", "Building self-repair uses maximum health times economy repair ratio")
	_check(_row_value(workshop, "建筑自修满速耗费") == "4.4 资金/秒", "Building self-repair expense uses its actual health-derived rate")
	_check(_row_value(workshop, "出售回收资金") == "350 资金", "Sell recovery is calculated from actual cost and sell ratio")
	_check(_row_value(workshop, "支援维修规则").contains("不叠加"), "Support repair explains non-stacking behavior")
	var fighter: Array[Dictionary] = Catalog.sections(rules, "kestrel_fighter")
	_check(_row_value(fighter, "低电时补给时间") == "12 秒", "Aircraft low-power rearm time uses actual economy multiplier")
	_check(_row_value(fighter, "弹药与返航").contains("每次开火消耗 1 发"), "Aircraft ammunition behavior is explained")
	_check(_row_value(fighter, "可攻击目标") == "空中", "Anti-air restriction is plainly labeled")
	var engineer: Array[Dictionary] = Catalog.sections(rules, "kestrel_engineer")
	_check(_row_value(engineer, "桥梁完整修复费用") == "400 资金", "Engineer describes the actual bridge repair expense")
	_check(_row_value(engineer, "支援维修满速耗费") == "2 资金/秒", "Engineer expense uses fixed repair speed")
	_check(_row_value(engineer, "立即修复建筑").contains("一次恢复全部") and _row_value(engineer, "立即修复建筑").contains("资金不足"), "Engineer describes instant building repair and waiting for its full cost")
	_check(_row_value(engineer, "立即占领建筑").contains("包括防御塔") and _row_value(engineer, "立即占领建筑").contains("不包括围墙、拒马"), "Engineer capture documentation includes towers and excludes walls and barricades")
	_check(_row_value(Catalog.sections(rules, "kestrel_hq"), "总部数量限制").contains("最多拥有一座"), "Headquarters ownership limit is discoverable")
	var outpost_sections:Array[Dictionary]=Catalog.sections(rules,"kestrel_outpost")
	_check(_row_value(outpost_sections,"工程兵施工").contains("立即选址") and _row_value(outpost_sections,"工程兵施工").contains("资金随现场施工进度支付"),"Outposts describe immediate placement and progress payments")
	_check(_row_value(outpost_sections,"受损与接手").contains("右键接手") and _row_value(outpost_sections,"主动拆除").contains("不退款"),"Outposts describe damaged scaffold repairs, replacement engineers and dismantling")
	_check(_row_value(Catalog.sections(rules,"rivet_harvester"),"矿柱规则").contains("储量无限") and _row_value(Catalog.sections(rules,"rivet_harvester"),"矿柱规则").contains("只有一辆矿车"),"Harvesters describe infinite ore and cross-team exclusive mining")
	var refinery: Array[Dictionary] = Catalog.sections(rules, "kestrel_refinery")
	_check(_row_value(refinery, "建成赠送").contains("1 辆"), "Refinery free harvester is documented")
	_check(_row_value(refinery, "满载交付收入").begins_with("500 资金"), "Harvest income follows the actual cargo delivery behavior")
	var voices_found: bool = false
	for section: Dictionary in fighter:
		if section.title == "单位语音": voices_found = section.rows.size() >= 4
	_check(voices_found, "Authored voice lines are offered in a separate section")


func _numeric_leaves(value: Variant, path: String, out: Dictionary) -> void:
	if value is Dictionary:
		for key: Variant in value:
			if str(key) in Catalog.TECHNICAL_FIELDS or key == "voices": continue
			_numeric_leaves(value[key], path + "." + str(key), out)
	elif value is Array:
		for index: int in value.size(): _numeric_leaves(value[index], path + "." + str(index), out)
	elif value is int or value is float or value is bool:
		out[path] = value


func _source_values(tables: Array[Dictionary]) -> Dictionary:
	var values: Dictionary = {}
	for section: Dictionary in tables:
		for row: Dictionary in section.rows:
			if not str(row.get("source_path", "")).is_empty(): values[row.source_path] = row.raw_value
	return values


func _all_text(tables: Array[Dictionary]) -> String:
	var text: String = ""
	for section: Dictionary in tables:
		for row: Dictionary in section.rows: text += str(row.label) + " " + str(row.value) + "\n"
	return text


func _row_value(tables: Array[Dictionary], label: String) -> String:
	for section: Dictionary in tables:
		for row: Dictionary in section.rows:
			if row.label == label: return str(row.value)
	return ""


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
