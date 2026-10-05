extends RefCounted

# One source of truth for purchase checks and contextual catalog prerequisites.
static func missing_requirements(sim: RefCounted, team: int, info: Dictionary) -> Array[String]:
	var names: Array[String] = []
	for required in info.get("requires", []):
		var spec: Dictionary = sim.data_for(str(required))
		var role: String = str(spec.get("role", required))
		if not sim._has_role(team, str(required)) and not sim._has_role(team, role) and not (role == "hq" and sim._has_role(team, "outpost")):
			names.append(str(spec.get("name", required)))
	return names

static func producer_name(sim: RefCounted, team: int, role: String) -> String:
	for building in sim.rules.get("buildings", {}).values():
		if building.get("faction", "") == sim.factions[team] and str(building.get("role", "")) == role:
			return str(building.get("name", role))
	return role

static func reason(sim: RefCounted, team: int, spec_id: String, builder: int = -1, producer: int = -1) -> String:
	if sim.result != "": return "对局已经结束"
	if team < 0 or team >= sim.factions.size(): return "无效阵营"
	var building: bool = sim.rules.get("buildings", {}).has(spec_id)
	var unit: bool = sim.rules.get("units", {}).has(spec_id)
	if not building and not unit: return "无效项目"
	var info: Dictionary = sim.data_for(spec_id)
	if str(info.get("faction", "")) != sim.factions[team]: return "不能使用其他阵营的项目"
	if sim.campaign_controller != null:
		var campaign_error: String = sim.campaign_controller.purchase_error(team, spec_id, sim)
		if not campaign_error.is_empty(): return campaign_error
	if building:
		var role: String = str(info.get("role", ""))
		if role == "hq": return "总部在开局部署，不可重造"
		if role == "outpost":
			if not sim._builder_valid(team, builder): return "缺少己方工程兵：分基地需要现场部署"
			for command in sim.entities[builder].commands:
				if command.kind in ["deploy_outpost", "resume_outpost"]: return "该工程兵正在部署或修建分基地"
		elif builder >= 0: return "工程兵只能部署分基地"
		var channel: String = preload("res://scripts/building_construction.gd").channel_for(info)
		if not sim.order_for_team(team, channel).is_empty(): return "建筑队列已有订单；就绪建筑须先放置或取消"
		if builder < 0 and not sim._has_construction_base(team): return "缺少已完成的总部或前哨基地"
	else:
		var role_name: String = str(info.get("producer", ""))
		var facility: Dictionary = sim.entities.get(producer, {})
		if facility.is_empty() or facility.get("kind", "") != "building" or int(facility.get("team", -1)) != team or float(facility.get("hp", 0.0)) <= 0.0 or float(facility.get("construct_remaining", 1.0)) > 0.0 or str(sim.data_for(str(facility.get("spec", ""))).get("role", "")) != role_name:
			var unmet: Array[String] = missing_requirements(sim, team, info)
			return "缺少生产设施：" + producer_name(sim, team, role_name) + ("；缺少前置设施与科技：" + "、".join(unmet) if not unmet.is_empty() else "")
	var missing: Array[String] = missing_requirements(sim, team, info)
	if not missing.is_empty(): return "缺少前置设施与科技：" + "、".join(missing)
	if unit:
		var limit_error: String = preload("res://scripts/unique_unit_rules.gd").reason(sim, team, spec_id)
		if not limit_error.is_empty(): return limit_error
	if unit and info.get("domain", "ground") == "air" and sim._airfield_load(producer) >= int(sim.data_for(sim.entities[producer].spec).get("aircraft_capacity", 4)):
		return "机场机位已满（含生产队列）；请取消订单或增建机场"
	if not (building and info.get("role", "") == "outpost") and sim.money[team] < float(info.get("cost", 0.0)): return "资金不足"
	return ""
