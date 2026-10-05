extends SceneTree

const MAP = preload("res://scripts/campaign_map.gd")
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	var mission: Dictionary = MAP.generate(1)
	check(mission.mode == "campaign" and mission.size == 320 and mission.profile.title == "无字桥补给线", "single authored 320 mission")
	check(mission.valid, "map validates: " + str(mission.get("validation_errors", [])))
	check(mission.bridges.size() == 1 and mission.bridges[0].id == 1, "central repairable bridge")
	check(mission.environment_props.size() >= 20 and mission.civilians.size() >= 3, "city street life")
	check(mission.ruins.any(func(r): return r.get("archetype", "") == "warehouse") and mission.ruins.any(func(r): return r.kind == "tree"), "industrial buildings and forest")
	check(mission.mines.size() >= 8, "mine network")
	for pad: Vector2 in [MAP.PLAYER_START, MAP.ENEMY_START, MAP.WEST_BRIDGE, MAP.EAST_BRIDGE, MAP.EXPANSION, MAP.EAST_ASSEMBLY]:
		check(int(mission.terrain[floori(pad.y)][floori(pad.x)]) != MAP.WATER, "mission pad is dry: " + str(pad))
	var reach: PackedByteArray = MAP._flood(mission, Vector2i(62, 170))
	check(reach[169 * 320 + 262] == 1, "southern detour reaches enemy HQ while bridge is broken")
	check(reach[160 * 320 + 174] == 1, "east bridgehead has land approach")
	var river: int = 0
	for z: int in 270:
		if int(mission.terrain[z][160]) == MAP.WATER: river += 1
	check(river > 200, "river is a substantial world feature")
	print("CAMPAIGN_MAP ", JSON.stringify({"checks": checks, "ruins": mission.ruins.size(), "props": mission.environment_props.size(), "civilians": mission.civilians.size(), "failures": failures}))
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
