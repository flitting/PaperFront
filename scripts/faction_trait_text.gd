class_name FactionTraitText
extends RefCounted

## Shared player-facing wording. Both the UI and document generator read the
## templates; all numeric values come from the active rules snapshot.
const TEMPLATES_PATH := "res://scripts/faction_trait_text.json"
const Traits = preload("res://scripts/faction_traits.gd")
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
	return {
		"reduction": number(float(config.get("damage_reduction", 0.0)) * 100.0),
		"delay": number(float(config.get("regen_delay", 0.0))),
		"regen": number(float(config.get("regen_fraction_per_second", 0.0)) * 100.0),
		"radius": number(float(config.get("cohesion_radius", 0.0))),
		"allies": str(int(config.get("cohesion_min_allies", 0))),
		"bonus": number(float(config.get("cohesion_damage_bonus", config.get("breakthrough_damage_bonus", 0.0))) * 100.0),
		"distance": number(float(config.get("breakthrough_distance", 0.0))),
		"window": number(float(config.get("breakthrough_window", 0.0)))
	}

static func _emp_values(weapon: Dictionary) -> Dictionary:
	return {"vehicle": number(float(weapon.get("emp_vehicle_duration", 0.0))), "building": number(float(weapon.get("emp_building_duration", 0.0)))}

static func faction_lines(rules: Dictionary, faction: String) -> PackedStringArray:
	var lines: PackedStringArray = []
	var config: Dictionary = rules.get("factions", {}).get(faction, {}).get("traits", {})
	if not config.is_empty() and faction in ["iron", "kestrel", "rivet"]:
		lines.append(_text(faction, "description", _values(rules, faction)))
	if faction == "sky":
		var emp: Dictionary = rules.get("weapons", {}).get("sky_disruptor", {})
		if emp.has("emp_vehicle_duration"): lines.append(_text("emp", "description", _emp_values(emp)))
	return lines

static func menu_short(rules: Dictionary, faction: String) -> String:
	if not rules.get("factions", {}).get(faction, {}).get("traits", {}).is_empty() and faction in ["iron", "kestrel", "rivet"]:
		return _text(faction, "short", _values(rules, faction))
	if faction == "sky" and rules.get("weapons", {}).get("sky_disruptor", {}).has("emp_vehicle_duration"):
		return _text("emp", "short")
	return {"kestrel":"工程协同 / 精确校正", "rivet":"重装推进 / 范围压制", "iron":"可靠结构 / 维护保障", "sky":"纸模科技 / 蓄能支援"}.get(faction, "")

static func spec_lines(rules: Dictionary, spec: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	var faction: String = str(spec.get("faction", ""))
	var armed: bool = not str(spec.get("weapon", "")).is_empty()
	if spec.has("speed"):
		if faction == "iron" or (faction == "kestrel" and armed) or (faction == "rivet" and armed and spec.get("armor_class", "") == "armored" and spec.get("domain", "ground") in ["ground", "naval"]):
			lines.append_array(faction_lines(rules, faction))
	elif spec.get("role", "") == "hq":
		lines.append_array(faction_lines(rules, faction))
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
	var values: Dictionary = _values(sim.rules, faction)
	if faction == "iron" and config.has("damage_reduction"):
		states.append(_text("iron", "status", values))
		if float(entity.hp) < float(spec.hp):
			var last_combat: float = maxf(float(entity.get("last_damage_time", sim.time)), float(entity.get("last_attack_time", sim.time)))
			var wait: float = maxf(0.0, float(config.get("regen_delay", 0.0)) - (float(sim.time) - last_combat))
			states.append(_text("iron", "healing") if wait <= 0.0 else _text("iron", "waiting", {"remaining": "%.1f" % wait}))
	elif faction == "kestrel" and config.has("cohesion_damage_bonus") and not str(spec.get("weapon", "")).is_empty():
		states.append(_text("kestrel", "active", values) if Traits.cohesion_bonus(sim, entity) > 0.0 else _text("kestrel", "waiting"))
	elif faction == "rivet" and config.has("breakthrough_distance") and spec.get("armor_class", "") == "armored" and spec.get("domain", "ground") in ["ground", "naval"] and not str(spec.get("weapon", "")).is_empty():
		remaining = maxf(0.0, float(entity.get("breakthrough_ready_until", 0.0)) - float(sim.time))
		if remaining > 0.0:
			values.remaining = "%.1f" % remaining
			states.append(_text("rivet", "active", values))
		elif not entity.get("commands", []).is_empty() and entity.commands[0].get("kind", "") == "attack_move":
			values.progress = "%.1f" % float(entity.get("breakthrough_progress", 0.0))
			states.append(_text("rivet", "progress", values))
	return " · ".join(states)
