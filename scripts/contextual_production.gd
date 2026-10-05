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
	var id: int = building(sim, ids)
	if id < 0: return []
	var role: String = str(sim.data_for(sim.entities[id].spec).get("role", ""))
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
		if str(info.faction) != sim.factions[0]: continue
		var role: String = str(info.get("role", ""))
		if category in ["build", "defense"]:
			if role == "hq" or role == "outpost": continue
			var defense: bool = role in ["tower", "wall", "barricade"]
			if defense != (category == "defense"): continue
		else:
			if CATEGORY_BY_ROLE.get(str(info.get("producer", "")), "") != category: continue
		var already_ordered: bool = str(current_order.get("spec", "")) == spec
		if not already_ordered and not Tech.missing_requirements(sim, 0, info).is_empty(): continue
		if not already_ordered and sim.campaign_controller != null and not sim.campaign_controller.purchase_error(0, spec, sim).is_empty(): continue
		specs.append(spec)
	return specs
