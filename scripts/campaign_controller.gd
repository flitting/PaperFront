extends RefCounted
class_name CampaignController

## Mission logic observes simulation facts. UI actions never complete objectives.
## All event-derived evidence is retained in the save so an early delivery,
## boarding or unloading action remains valid after a restore.
const MAP = preload("res://scripts/campaign_map.gd")
const STAGE_COUNT := 7
const HOLD_SECONDS := 60.0

const OBJECTIVES: Array[Dictionary] = [
	{"title": "点亮后方", "body": "建造一座电站，让基地获得稳定电力。", "hint": "先选中总部，点底部「电站」；完工后再点卡片，在总部附近左键放置。", "marker": Vector2(57, 165)},
	{"title": "第一车辉晶", "body": "建造精炼厂，并让矿车向它交付第一车辉晶。", "hint": "目标指向矿柱。精炼厂建在总部扩建范围内；矿车右键矿柱可持续采矿。", "marker": Vector2(81.5, 142.5)},
	{"title": "组建先遣队", "body": "建造兵营，训练步兵与工程兵，并派步兵侦察无字桥西岸。", "hint": "选中兵营训练；选择步兵后右键桥西岸，确认道路畅通。", "marker": MAP.WEST_BRIDGE},
	{"title": "修复无字桥", "body": "让工程兵修好中央桥梁，恢复补给主路。", "hint": "选中工程兵，右键桥面或桥头；修桥会按进度支付费用。", "marker": Vector2(160, 160)},
	{"title": "建立东岸分基地", "body": "让工程兵在东岸矿场附近建成分基地。", "hint": "选中工程兵，点击右侧「部署分基地」，在目标地点附近左键选址。", "marker": MAP.EXPANSION},
	{"title": "机动运输", "body": "建成战车工厂，用侦察车搭载步兵并在东岸集结区卸载。", "hint": "步兵右键侦察车上车；选车后按 U，左键东岸集结区指定卸载。", "marker": MAP.EAST_ASSEMBLY},
	{"title": "守住补给线 · 反攻", "body": "总部坚守 60 秒，再摧毁重锤军团全部基地兵营。", "hint": "可建防御塔与坦克。稳住西岸工业设施后，沿主桥或南侧道路反攻。", "marker": MAP.ENEMY_START}
]

var stage: int = 0
var finished: bool = false
var flags: Dictionary = {}
var board_ids: Dictionary = {}
var hold_elapsed: float = 0.0
var _last_notice: String = ""

func setup(_sim: WarSimulation) -> void:
	stage = 0
	finished = false
	flags = {"delivery": false, "trained_rifle": false, "trained_engineer": false,
		"bridge_reached": false, "bridge_repaired": false, "outpost": false,
		"transport_unloaded": false, "enemy_hq_destroyed": false}
	board_ids.clear()
	hold_elapsed = 0.0
	_last_notice = ""

func step(sim: WarSimulation, delta: float) -> void:
	if finished or sim == null or sim.map.get("mode", "") != "campaign": return
	_observe_events(sim)
	_observe_entities(sim)
	if stage == 6 and _player_hq_alive(sim): hold_elapsed = minf(HOLD_SECONDS, hold_elapsed + maxf(0.0, delta))
	var guard: int = 0
	while guard < STAGE_COUNT and stage < STAGE_COUNT and _stage_complete(sim, stage):
		guard += 1
		var old: int = stage
		stage += 1
		if stage >= STAGE_COUNT:
			finished = true
			_last_notice = "无字桥补给线完成。重锤基地兵营已全部摧毁，补给线恢复。"
		else:
			_last_notice = "目标完成：%s。下一步：%s。" % [OBJECTIVES[old].title, OBJECTIVES[stage].title]
		sim.notices.append(_last_notice)

func _observe_events(sim: WarSimulation) -> void:
	for event: Dictionary in sim.events:
		var kind: String = str(event.get("kind", ""))
		if kind == "delivery" and int(event.get("team", -1)) == 0 and float(event.get("amount", 0.0)) > 0.0:
			flags.delivery = true
		elif kind == "produce" and int(event.get("team", -1)) == 0:
			var spec: String = str(event.get("spec", ""))
			if spec == "kestrel_rifle": flags.trained_rifle = true
			if spec == "kestrel_engineer": flags.trained_engineer = true
		elif kind == "board" and int(event.get("team", -1)) == 0:
			var carrier_id: int = int(event.get("carrier", -1))
			var passenger_id: int = int(event.get("id", -1))
			if sim.entities.has(carrier_id) and sim.entities.has(passenger_id):
				if str(sim.entities[carrier_id].spec) == "kestrel_scout" and str(sim.entities[passenger_id].spec) == "kestrel_rifle":
					board_ids[passenger_id] = carrier_id
		elif kind == "unload" and int(event.get("team", -1)) == 0:
			var passenger_id: int = int(event.get("id", -1))
			if board_ids.has(passenger_id) and event.get("pos", Vector2.INF) is Vector2:
				if (event.pos as Vector2).distance_to(MAP.EAST_ASSEMBLY) <= 28.0:
					flags.transport_unloaded = true
			board_ids.erase(passenger_id)
		elif kind == "death" and int(event.get("team", -1)) == 1 and str(event.get("spec", "")) == "rivet_hq":
			flags.enemy_hq_destroyed = not _enemy_hq_alive(sim)

func _observe_entities(sim: WarSimulation) -> void:
	var bridge: Dictionary = sim._bridge_by_id(1)
	if not bridge.is_empty() and bool(bridge.alive) and float(bridge.repair_progress) >= 0.999 and _player_engineer_at_bridge(sim, bridge):
		flags.bridge_repaired = true
	for entity: Dictionary in sim.entities.values():
		if int(entity.team) != 0 or float(entity.hp) <= 0.0: continue
		var spec: String = str(entity.spec)
		if spec == "kestrel_rifle" and int(entity.get("transport_id", -1)) < 0:
			if (entity.pos as Vector2).distance_to(MAP.WEST_BRIDGE) <= 17.0:
				flags.bridge_reached = true
		if spec == "kestrel_outpost" and float(entity.get("construct_remaining", 0.0)) <= 0.0:
			if (entity.pos as Vector2).distance_to(MAP.EXPANSION) <= 29.0: flags.outpost = true
	# Result hooks can delete the HQ before mission code inspects the final event.
	if bool(sim.rules.buildings.get("rivet_hq", {}).get("rebuildable", false)):
		flags.enemy_hq_destroyed = not _enemy_hq_alive(sim)
	elif not _enemy_hq_alive(sim):
		flags.enemy_hq_destroyed = true

func _player_engineer_at_bridge(sim: WarSimulation, bridge: Dictionary) -> bool:
	for entity: Dictionary in sim.entities.values():
		if int(entity.team) != 0 or str(entity.spec) != "kestrel_engineer" or float(entity.hp) <= 0.0: continue
		for head: Array in bridge.heads:
			if (entity.pos as Vector2).distance_to(Vector2(float(head[0]), float(head[1]))) <= 4.0: return true
	return false

func _stage_complete(sim: WarSimulation, candidate: int) -> bool:
	match candidate:
		0: return _has_completed_building(sim, "power")
		1: return _has_completed_building(sim, "refinery") and bool(flags.get("delivery", false))
		2: return _has_completed_building(sim, "barracks") and bool(flags.get("trained_rifle", false)) and bool(flags.get("trained_engineer", false)) and bool(flags.get("bridge_reached", false))
		3: return bool(flags.get("bridge_repaired", false))
		4: return bool(flags.get("outpost", false))
		5: return _has_completed_building(sim, "factory") and bool(flags.get("transport_unloaded", false))
		6: return _player_hq_alive(sim) and hold_elapsed >= HOLD_SECONDS and bool(flags.get("enemy_hq_destroyed", false))
	return false

func _has_completed_building(sim: WarSimulation, role: String) -> bool:
	for entity: Dictionary in sim.entities.values():
		if int(entity.team) == 0 and entity.kind == "building" and float(entity.hp) > 0.0 and float(entity.get("construct_remaining", 0.0)) <= 0.0:
			if str(sim.data_for(entity.spec).get("role", "")) == role: return true
	return false

func _player_hq_alive(sim: WarSimulation) -> bool:
	for entity: Dictionary in sim.entities.values():
		if int(entity.team) == 0 and str(entity.spec) == "kestrel_hq" and float(entity.hp) > 0.0: return true
	return false

func _enemy_hq_alive(sim: WarSimulation) -> bool:
	for entity: Dictionary in sim.entities.values():
		if int(entity.team) == 1 and str(entity.spec) == "rivet_hq" and float(entity.hp) > 0.0: return true
	return false

func purchase_error(team: int, spec: String, sim: WarSimulation) -> String:
	if team != 0 or sim == null or sim.map.get("mode", "") != "campaign": return ""
	var threshold: int = _unlock_stage(spec, sim)
	if threshold < 0: return "本关不开放；请完成地面补给线任务"
	if stage >= threshold: return ""
	return "战役第%d阶段开放：%s" % [threshold + 1, OBJECTIVES[threshold].title]

func _unlock_stage(spec: String, sim: WarSimulation) -> int:
	var data: Dictionary = sim.data_for(spec)
	if data.is_empty(): return -1
	if str(data.get("faction", "")) != "kestrel": return -1
	if sim.rules.buildings.has(spec):
		return {"hq": -1, "power": 0, "refinery": 1, "barracks": 2,
			"outpost": 4, "factory": 5, "tower": 6, "wall": 6,
			"barricade": 6, "repair": 6, "tech": 6}.get(str(data.get("role", "")), -1)
	return {"rifle": 2, "engineer": 2, "scout": 5, "harvester": 5,
		"anti": 6, "tank": 6, "aa": 6, "demolition": 6, "artillery": 6}.get(str(data.get("art", "")), -1)

func ai_policy() -> Dictionary:
	return {"army_cap": 4, "wave_cap": 2, "wave_limit": 2, "attack_enabled": stage >= 6,
		"building_caps": {"power": 1, "refinery": 1, "barracks": 1, "factory": 1},
		"allowed_roles": ["hq", "power", "refinery", "barracks", "factory"],
		"hold_position": MAP.ENEMY_START + Vector2(-18, 0),
		"attack_target": MAP.PLAYER_START, "stage": stage}

func view_state() -> Dictionary:
	var objective: Dictionary = OBJECTIVES[mini(stage, STAGE_COUNT - 1)]
	var progress: String = ""
	if stage == 2:
		progress = "步兵 %s · 工程兵 %s · 桥西岸 %s" % ["✓" if flags.get("trained_rifle", false) else "○",
			"✓" if flags.get("trained_engineer", false) else "○", "✓" if flags.get("bridge_reached", false) else "○"]
	elif stage == 5:
		progress = "东岸卸载 %s" % ("✓" if flags.get("transport_unloaded", false) else "○")
	elif stage == 6:
		progress = "总部防守 %d / 60 秒 · 敌方基地兵营 %s" % [ceili(hold_elapsed), "已全部摧毁" if flags.get("enemy_hq_destroyed", false) else "待摧毁"]
	return {"active": true, "title": "无字桥补给线", "stage": stage,
		"total": STAGE_COUNT, "objective": objective.title, "body": objective.body,
		"hint": objective.hint, "marker": objective.marker, "progress": progress,
		"finished": finished, "last_notice": _last_notice}

func to_dict() -> Dictionary:
	return {"version": 1, "stage": stage, "finished": finished,
		"flags": flags.duplicate(true), "board_ids": board_ids.duplicate(true),
		"hold_elapsed": hold_elapsed, "last_notice": _last_notice}

func from_dict(data: Dictionary) -> void:
	stage = clampi(int(data.get("stage", 0)), 0, STAGE_COUNT)
	finished = bool(data.get("finished", false))
	flags = data.get("flags", {}).duplicate(true)
	board_ids = data.get("board_ids", {}).duplicate(true)
	hold_elapsed = clampf(float(data.get("hold_elapsed", 0.0)), 0.0, HOLD_SECONDS)
	_last_notice = str(data.get("last_notice", ""))

static func validate_state(data: Dictionary) -> String:
	if int(data.get("version", -1)) != 1: return "战役存档版本无效"
	if not data.get("stage") is int or int(data.stage) < 0 or int(data.stage) > STAGE_COUNT: return "战役任务阶段无效"
	if not data.get("finished") is bool or not data.get("flags") is Dictionary or not data.get("board_ids") is Dictionary: return "战役任务状态无效"
	if bool(data.finished) != (int(data.stage) == STAGE_COUNT): return "战役任务完成状态无效"
	if not data.get("hold_elapsed") is float and not data.get("hold_elapsed") is int: return "战役防守计时无效"
	if not is_finite(float(data.hold_elapsed)) or float(data.hold_elapsed) < 0.0 or float(data.hold_elapsed) > HOLD_SECONDS: return "战役防守计时越界"
	if not data.get("last_notice", "") is String: return "战役提示无效"
	for key: String in ["delivery", "trained_rifle", "trained_engineer", "bridge_reached", "bridge_repaired", "outpost", "transport_unloaded", "enemy_hq_destroyed"]:
		if not data.flags.get(key) is bool: return "战役任务标记无效"
	for passenger_id: Variant in data.board_ids:
		if not passenger_id is int or int(passenger_id) <= 0 or not data.board_ids[passenger_id] is int or int(data.board_ids[passenger_id]) <= 0:
			return "战役运输记录无效"
	if bool(data.finished) and (not bool(data.flags.enemy_hq_destroyed) or float(data.hold_elapsed) < HOLD_SECONDS): return "战役任务结算无效"
	return ""
