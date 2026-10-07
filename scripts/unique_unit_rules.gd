extends RefCounted

static func occupied(sim, team: int, spec_id: String) -> int:
	var count: int = 0
	for e in sim.entities.values():
		if int(e.get("team", -1)) != team or float(e.get("hp", 0.0)) <= 0.0: continue
		if e.get("kind") == "unit" and str(e.get("spec", "")) == spec_id:
			count += 1
		elif e.get("kind") == "building":
			for order in e.get("queue", []):
				if str(order.get("spec", "")) == spec_id: count += 1
	return count

static func reason(sim, team: int, spec_id: String) -> String:
	var info: Dictionary = sim.rules.get("units", {}).get(spec_id, {})
	if bool(info.get("roster_hidden",false)):return "该单位不在本阵营现行编制中"
	var limit: int = int(info.get("max_active", 0))
	if limit > 0 and occupied(sim, team, spec_id) >= limit:
		return "此英雄单位每名玩家同时最多拥有一只（含生产与待出厂队列）"
	return ""
