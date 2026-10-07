extends RefCounted

## Unlocks are based on completed owned facilities, including barracks bases.
static func tier(info: Dictionary) -> int:
	return clampi(int(info.get("tier",0)),0,3)

static func requirement_text(info: Dictionary) -> String:
	return ["T0 · 开局即可建造", "T1 · 完成兵营后解锁", "T2 · 完成战车工厂或飞机场任一后解锁", "T3 · 完成科技中心类建筑后解锁"][tier(info)]

static func current(sim, team: int) -> int:
	if sim._has_role(team,"tech"): return 3
	if sim._has_role(team,"factory") or sim._has_role(team,"airfield"): return 2
	if sim._has_role(team,"barracks"): return 1
	return 0

static func missing(sim, team: int, info: Dictionary) -> Array[String]:
	var result: Array[String] = []
	# Historical rule snapshots without a tier keep their explicit prerequisites.
	if info.has("tier") and current(sim,team)<tier(info): result.append(requirement_text(info))
	return result
