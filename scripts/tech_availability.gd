extends RefCounted

const TierAvailability=preload("res://scripts/tier_availability.gd")

# One source of truth for purchase checks and contextual catalog prerequisites.
static func engineer_building(sim, team: int, info: Dictionary) -> bool:
	return (sim.factions[team] == "iron" and str(info.get("role", "")) in ["rail", "rail_junction"]) or str(info.get("role", "")) == "outpost" or (sim.rules.factions.get(sim.factions[team], {}).get("building_method", "") == "engineer" and (str(info.get("role", "")) != "hq" or bool(info.get("rebuildable", false))))

static func building_id(sim, team: int, role: String) -> String:
	var conventional: String = sim.factions[team] + "_" + role
	if sim.rules.buildings.has(conventional): return conventional
	for spec_id in sim.rules.buildings:
		var info: Dictionary = sim.rules.buildings[spec_id]
		if info.get("faction", "") == sim.factions[team] and (info.get("role", "") == role or role in info.get("production_roles", [])): return str(spec_id)
	return ""

static func producer_matches(sim, facility: Dictionary, role: String) -> bool:
	var info: Dictionary = sim.data_for(str(facility.get("spec", "")))
	return (role=="amphibious" and info.get("role","") in ["factory","shipyard"]) or str(info.get("role", "")) == role or role in info.get("production_roles", [])
static func missing_requirements(sim: RefCounted, team: int, info: Dictionary) -> Array[String]:
	var names: Array[String] = TierAvailability.missing(sim,team,info)
	for required in info.get("requires", []):
		var spec: Dictionary = sim.data_for(str(required))
		var role: String = str(spec.get("role", required))
		if not sim._has_role(team, str(required)) and not sim._has_role(team, role) and not (role == "hq" and sim._has_role(team, "outpost")):
			names.append(str(spec.get("name", required)))
	return names

static func producer_name(sim: RefCounted, team: int, role: String) -> String:
	if role=="amphibious":return "战车工厂或船坞"
	if role=="carrier":return "航母飞行甲板"
	var spec_id: String = building_id(sim, team, role)
	return str(sim.data_for(spec_id).get("name", role)) if not spec_id.is_empty() else role

static func reason(sim: RefCounted, team: int, spec_id: String, builder: int = -1, producer: int = -1) -> String:
	if sim.result != "": return "对局已经结束"
	if team < 0 or team >= sim.factions.size(): return "无效阵营"
	var building: bool = sim.rules.get("buildings", {}).has(spec_id)
	var unit: bool = sim.rules.get("units", {}).has(spec_id)
	if not building and not unit: return "无效项目"
	var info: Dictionary = sim.data_for(spec_id)
	if bool(info.get("roster_hidden",false)):return "该单位不在本阵营现行编制中"
	if bool(info.get("internal_only",false)):return "该单位由载舰调度，无法单独购买"
	if str(info.get("faction", "")) != sim.factions[team]: return "不能使用其他阵营的项目"
	if sim.campaign_controller != null:
		var campaign_error: String = sim.campaign_controller.purchase_error(team, spec_id, sim)
		if not campaign_error.is_empty(): return campaign_error
	if building:
		var role: String = str(info.get("role", ""))
		if role == "hq" and not bool(info.get("rebuildable", false)): return "总部在开局部署，不可重造"
		if engineer_building(sim, team, info) and (builder>=0 or not (sim.factions[team]=="iron" and role in ["rail","rail_junction"])):
			if not sim._builder_valid(team, builder): return "缺少己方工程兵：建筑需要现场施工"
			for pending in [sim.order_for_team(team, "normal"), sim.order_for_team(team, "defense")]:
				if int(pending.get("builder", -1)) == builder: return "该工程兵已有待选址建筑"
			for command in sim.entities[builder].commands:
				if command.kind in ["deploy_outpost", "resume_outpost"]: return "该工程兵正在现场施工"
		elif builder >= 0: return "工程兵只能部署分基地"
		var channel: String = preload("res://scripts/building_construction.gd").channel_for(info)
		if not sim.order_for_team(team, channel).is_empty(): return "建筑队列已有订单；就绪建筑须先放置或取消"
		if builder < 0 and not sim._has_construction_base(team): return "缺少已完成的总部或前哨基地"
	else:
		var role_name: String = str(info.get("producer", ""))
		var facility: Dictionary = sim.entities.get(producer, {})
		if facility.is_empty() or facility.get("kind", "") != "building" or int(facility.get("team", -1)) != team or float(facility.get("hp", 0.0)) <= 0.0 or float(facility.get("construct_remaining", 1.0)) > 0.0 or not producer_matches(sim, facility, role_name):
			var unmet: Array[String] = missing_requirements(sim, team, info)
			return "缺少生产设施：" + producer_name(sim, team, role_name) + ("；缺少前置设施与科技：" + "、".join(unmet) if not unmet.is_empty() else "")
	var missing: Array[String] = missing_requirements(sim, team, info)
	if not missing.is_empty(): return "缺少前置设施与科技：" + "、".join(missing)
	if unit:
		var limit_error: String = preload("res://scripts/unique_unit_rules.gd").reason(sim, team, spec_id)
		if not limit_error.is_empty(): return limit_error
	if unit and info.get("domain", "ground") == "air" and not bool(info.get("permanent_air",false)) and sim._airfield_load(producer) >= int(sim.data_for(sim.entities[producer].spec).get("aircraft_capacity", 4)):
		return "机场机位已满（含生产队列）；请取消订单或增建机场"
	if not (building and engineer_building(sim, team, info)) and sim.money[team] < float(info.get("cost", 0.0)): return "资金不足"
	return ""
