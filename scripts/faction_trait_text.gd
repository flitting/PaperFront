class_name FactionTraitText
extends RefCounted

## Shared player-facing wording. Both the UI and document generator read the
## templates; all numeric values come from the active rules snapshot.
const TEMPLATES_PATH := "res://scripts/faction_trait_text.json"
static var _templates: Dictionary = {}
static var _menu_rules: Dictionary = {}

static func menu_rules() -> Dictionary:
	if _menu_rules.is_empty():
		_menu_rules = preload("res://scripts/rules_loader.gd").load_rules("res://data/rules.json", false)
	return _menu_rules

static func _text(group: String, field: String, values: Dictionary = {}) -> String:
	if _templates.is_empty():
		var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEMPLATES_PATH))
		if source is Dictionary: _templates = source
	var result: String = str(_templates.get(group, {}).get(field, ""))
	for key in values: result = result.replace("{" + str(key) + "}", str(values[key]))
	return result

static func number(value: float) -> String:
	return ("%.2f" % value).trim_suffix("00").trim_suffix("0").trim_suffix(".")

static func _values(rules: Dictionary, faction: String) -> Dictionary:
	var config: Dictionary = rules.get("factions", {}).get(faction, {}).get("traits", {})
	var hq: Dictionary = rules.get("buildings", {}).get(faction + "_hq", {})
	var barracks: Dictionary = hq if faction == "rivet" and bool(hq.get("rebuildable", false)) else rules.get("buildings", {}).get(faction + "_barracks", {})
	return {
		"delay": number(float(config.get("regen_delay", 0.0))),
		"regen": number(float(config.get("regen_fraction_per_second", 0.0)) * 100.0),
		"barracks_cost": number(float(barracks.get("cost", 0.0))),
		"barracks_build_time": number(float(barracks.get("build_time", 0.0))),
		"barracks_local_power": number(float(barracks.get("local_power", 0.0))),
		"barracks_local_power_radius": number(float(barracks.get("local_power_radius", 0.0))),
		"barracks_construction_radius": number(float(barracks.get("construction_radius", 0.0))),
		"local_power": number(float(hq.get("local_power", 0.0))),
		"local_power_radius": number(float(hq.get("local_power_radius", 0.0)))
	}

static func _emp_values(weapon: Dictionary) -> Dictionary:
	return {"vehicle": number(float(weapon.get("emp_vehicle_duration", 0.0))), "building": number(float(weapon.get("emp_building_duration", 0.0)))}

static func faction_lines(rules: Dictionary, faction: String) -> PackedStringArray:
	var lines: PackedStringArray = []
	var config: Dictionary = rules.get("factions", {}).get(faction, {}).get("traits", {})
	if faction in ["iron", "kestrel", "rivet", "sky"]:
		var field: String = "standard_description" if faction == "rivet" and rules.get("factions", {}).get(faction, {}).get("building_method", "") != "engineer" else "description"
		if faction == "rivet" and field == "description" and not bool(rules.get("buildings", {}).get("rivet_hq", {}).get("rebuildable", false)):
			field = "legacy_engineer_description"
		lines.append(_text(faction, field, _values(rules, faction)))
	if faction == "iron" and float(config.get("regen_fraction_per_second", 0.0)) > 0.0:
		lines.append(_text("iron", "regeneration", _values(rules, faction)))
	if faction == "sky":
		var emp: Dictionary = rules.get("weapons", {}).get("sky_disruptor", {})
		if emp.has("emp_vehicle_duration"): lines.append(_text("emp", "description", _emp_values(emp)))
	if float(rules.get("buildings", {}).get(faction + "_hq", {}).get("local_power", 0.0)) > 0.0:
		lines.append(_text("hq_power", "base_barracks_description" if faction == "rivet" and bool(rules.get("buildings", {}).get("rivet_hq", {}).get("rebuildable", false)) else "description", _values(rules, faction)))
	return lines

static func menu_short(rules: Dictionary, faction: String) -> String:
	if faction == "rivet" and rules.get("factions", {}).get(faction, {}).get("building_method", "") != "engineer":
		return _text("rivet", "short_standard")
	if faction == "rivet" and not bool(rules.get("buildings", {}).get("rivet_hq", {}).get("rebuildable", false)):
		return _text("rivet", "short_legacy_engineer")
	if faction == "iron" and float(rules.get("factions", {}).get(faction, {}).get("traits", {}).get("regen_fraction_per_second", 0.0)) <= 0.0:
		return _text("iron", "short_without_regeneration")
	return _text(faction, "short")

static func spec_lines(rules: Dictionary, spec: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	var faction: String = str(spec.get("faction", ""))
	if spec.has("speed"):
		if faction == "iron" and spec.get("armor_class", "") == "armored" and float(rules.get("factions", {}).get(faction, {}).get("traits", {}).get("regen_fraction_per_second", 0.0)) > 0.0:
			lines.append(_text("iron", "regeneration", _values(rules, faction)))
	elif spec.get("role", "") == "hq":
		lines.append_array(faction_lines(rules, faction))
	elif float(spec.get("local_power", 0.0)) > 0.0:
		lines.append(_text("local_power", "description", {"capacity": number(float(spec.local_power)), "radius": number(float(spec.get("local_power_radius", 0.0)))}))
	var weapon: Dictionary = rules.get("weapons", {}).get(str(spec.get("weapon", "")), {})
	if weapon.has("emp_vehicle_duration"): lines.append(_text("emp", "description", _emp_values(weapon)))
	return lines

static func state_text(sim, entity: Dictionary) -> String:
	var states: PackedStringArray = []
	var remaining: float = maxf(0.0, float(entity.get("emp_until", 0.0)) - float(sim.time))
	if remaining > 0.0: states.append(_text("emp", "status", {"remaining": "%.1f" % remaining}))
	if entity.get("kind", "") != "unit" or sim.Transport.is_loaded(entity): return " · ".join(states)
	var spec: Dictionary = sim.data_for(str(entity.spec))
	var faction: String = str(sim.factions[int(entity.team)])
	var config: Dictionary = sim.rules.factions.get(faction, {}).get("traits", {})
	if faction == "iron" and spec.get("armor_class", "") == "armored" and float(config.get("regen_fraction_per_second", 0.0)) > 0.0:
		if float(entity.hp) < float(spec.hp):
			var last_combat: float = maxf(float(entity.get("last_damage_time", sim.time)), float(entity.get("last_attack_time", sim.time)))
			var wait: float = maxf(0.0, float(config.get("regen_delay", 0.0)) - (float(sim.time) - last_combat))
			states.append(_text("iron", "healing") if wait <= 0.0 else _text("iron", "waiting", {"remaining": "%.1f" % wait}))
	return " · ".join(states)
