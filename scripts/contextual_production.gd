extends RefCounted

const Tech = preload("res://scripts/tech_availability.gd")
const CATEGORY_BY_ROLE := {"barracks": "infantry", "factory": "vehicle", "airfield": "air", "shipyard": "naval"}

static func building(sim, ids: Array) -> int:
	for id in ids:
		if not sim.entities.has(id): continue
		var e: Dictionary = sim.entities[id]
		if int(e.team) != 0 or e.kind != "building" or float(e.hp) <= 0.0 or float(e.construct_remaining) > 0.0: continue
		var role: String = str(sim.data_for(e.spec).get("role", ""))
		if role in ["hq", "outpost"] or CATEGORY_BY_ROLE.has(role): return int(id)
	return -1

static func categories(sim, ids: Array) -> Array:
	for selected in ids:
		if sim._builder_valid(0, int(selected)) and (sim.rules.factions.get(sim.factions[0], {}).get("building_method", "") == "engineer" or sim.factions[0]=="iron"): return ["build", "defense"]
	var id: int = building(sim, ids)
	if id < 0: return []
	var role: String = str(sim.data_for(sim.entities[id].spec).get("role", ""))
	var info: Dictionary = sim.data_for(sim.entities[id].spec)
	if sim.rules.factions.get(sim.factions[0], {}).get("building_method", "") == "engineer" and role in ["hq", "outpost"]:
		return ["infantry"] if "barracks" in info.get("production_roles", []) else []
	return ["build", "defense"] if role in ["hq", "outpost"] else [CATEGORY_BY_ROLE[role]]

static func deployment_visible(sim, engineer: int) -> bool:
	var spec: String = sim.factions[0] + "_outpost"
	if not sim._builder_valid(0, engineer) or not sim.rules.buildings.has(spec): return false
	if not Tech.missing_requirements(sim, 0, sim.data_for(spec)).is_empty(): return false
	if sim.campaign_controller != null and not sim.campaign_controller.purchase_error(0, spec, sim).is_empty(): return false
	return not sim.entities[engineer].commands.any(func(command): return command.kind in ["deploy_outpost", "resume_outpost"])

## Money and queue occupancy are temporary states. Technology and selected
## production authority decide which cards belong in the contextual catalog.
static func visible_specs(sim, ids: Array, category: String) -> Array[String]:
	var specs: Array[String] = []
	if category not in categories(sim, ids): return specs
	var source: Dictionary = sim.rules.buildings if category in ["build", "defense"] else sim.rules.units
	var current_order: Dictionary = sim.order_for_team(0, "defense" if category == "defense" else "normal") if category in ["build", "defense"] else {}
	for spec: String in source:
		var info: Dictionary = source[spec]
		if str(info.faction) != sim.factions[0] or bool(info.get("internal_only",false)) or bool(info.get("roster_hidden",false)): continue
		if sim._builder_valid(0,int(ids[0])) and sim.factions[0]=="iron" and category in ["build","defense"] and info.get("role","") not in ["rail","rail_junction","outpost"]:continue
		var role: String = str(info.get("role", ""))
		if category in ["build", "defense"]:
			if (role == "hq" and not bool(info.get("rebuildable", false))) or (role == "outpost" and sim.rules.factions.get(sim.factions[0], {}).get("building_method", "") != "engineer"): continue
			var defense: bool = role in ["tower", "wall", "barricade", "rail", "rail_junction"]
			if defense != (category == "defense"): continue
		else:
			if not (str(info.get("producer",""))=="amphibious" and category in ["vehicle","naval"]) and CATEGORY_BY_ROLE.get(str(info.get("producer", "")), "") != category: continue
		var already_ordered: bool = str(current_order.get("spec", "")) == spec
		if not already_ordered and not Tech.missing_requirements(sim, 0, info).is_empty(): continue
		if not already_ordered and sim.campaign_controller != null and not sim.campaign_controller.purchase_error(0, spec, sim).is_empty(): continue
		specs.append(spec)
	return specs
