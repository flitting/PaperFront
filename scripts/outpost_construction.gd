class_name OutpostConstruction
extends RefCounted

## Field construction is paid as the engineer works. A damaged scaffold must
## first be repaired up to the health justified by its existing progress.
const INITIAL_HEALTH_RATIO: float = 0.03
const INITIAL_HEALTH_LIMIT: float = 50.0
const EPSILON: float = 0.000001


static func initialize(sim, building: Dictionary, builder: int) -> void:
	var info: Dictionary = sim.data_for(building.spec)
	var initial_hp: float = minf(INITIAL_HEALTH_LIMIT, float(info.hp) * INITIAL_HEALTH_RATIO)
	building.hp = initial_hp
	building.construct_remaining = float(info.build_time)
	building.construction = {
		"builder": builder, "progress": 0.0, "spent": 0.0,
		"initial_hp": initial_hp, "repair_spent": 0.0,
		"work_state": "paused", "pause_reason": "等待工程兵施工"
	}
	building.state = "construct"
	building.repairing = false


static func health_cap(sim, building: Dictionary) -> float:
	var maximum: float = float(sim.data_for(building.spec).hp)
	var construction: Dictionary = building.get("construction", {})
	if construction.is_empty():
		return maximum
	var initial: float = float(construction.initial_hp)
	return initial + (maximum - initial) * float(construction.progress)


static func resume_error(sim, engineer_id: int, target_id: int) -> String:
	if not str(sim.result).is_empty():
		return "对局已经结束"
	if not sim.entities.has(engineer_id):
		return "继续施工需要工程兵"
	var engineer: Dictionary = sim.entities[engineer_id]
	if not sim._builder_valid(int(engineer.team), engineer_id):
		return "继续施工需要工程兵"
	if not sim.entities.has(target_id):
		return "施工分基地已不存在"
	var building: Dictionary = sim.entities[target_id]
	if building.kind != "building" or sim.data_for(building.spec).get("role", "") != "outpost" or building.get("construction", {}).is_empty() or float(building.hp) <= 0.0:
		return "只能继续未完工分基地的施工"
	if int(building.team) != int(engineer.team):
		return "只能接手己方分基地施工"
	return ""


static func assign_builder(sim, engineer_id: int, target_id: int) -> String:
	var error: String = resume_error(sim, engineer_id, target_id)
	if not error.is_empty():
		return error
	var construction: Dictionary = sim.entities[target_id].construction
	var previous: int = int(construction.builder)
	if previous != engineer_id and sim.entities.has(previous):
		var old_builder: Dictionary = sim.entities[previous]
		if _has_work_order(old_builder, target_id):
			sim._finish_command(old_builder)
	construction.builder = engineer_id
	construction.work_state = "paused"
	construction.pause_reason = "等待工程兵到达"
	return ""


static func _has_work_order(engineer: Dictionary, target_id: int) -> bool:
	return not engineer.commands.is_empty() and str(engineer.commands[0].kind) == "resume_outpost" and int(engineer.commands[0].target) == target_id


static func _pause_reason(sim, building: Dictionary) -> String:
	var builder: int = int(building.construction.builder)
	if not sim._builder_valid(int(building.team), builder):
		return "等待工程兵接手"
	var engineer: Dictionary = sim.entities[builder]
	if not _has_work_order(engineer, int(building.id)):
		return "工程兵已停止施工"
	if sim._engineering_distance(engineer, building) > sim._radius(engineer) + 0.5:
		return "等待工程兵到达"
	return ""


static func _pause(construction: Dictionary, reason: String) -> void:
	construction.work_state = "paused"
	construction.pause_reason = reason


static func step(sim, building: Dictionary, delta: float) -> void:
	var construction: Dictionary = building.get("construction", {})
	if construction.is_empty() or delta <= 0.0:
		return
	var reason: String = _pause_reason(sim, building)
	if not reason.is_empty():
		_pause(construction, reason)
		return
	var builder: Dictionary = sim.entities[int(construction.builder)]
	var info: Dictionary = sim.data_for(building.spec)
	var maximum: float = float(info.hp)
	var total: float = maxf(float(info.build_time), EPSILON)
	var team: int = int(building.team)
	var remaining_time: float = delta
	var cap: float = health_cap(sim, building)
	var missing: float = maxf(0.0, cap - float(building.hp))
	if missing > EPSILON:
		var repair_rate: float = maxf(float(sim.data_for(builder.spec).get("repair_rate", 8.0)), EPSILON)
		var repair_cost: float = maxf(float(sim._eco("repair_cost", 0.2)), 0.0)
		var restored: float = minf(missing, repair_rate * remaining_time)
		if repair_cost > 0.0:
			restored = minf(restored, float(sim.money[team]) / repair_cost)
		if restored <= 0.0:
			_pause(construction, "维修资金不足")
			return
		var paid: float = restored * repair_cost
		building.hp = minf(cap, float(building.hp) + restored)
		sim.money[team] = maxf(0.0, float(sim.money[team]) - paid)
		construction.repair_spent = float(construction.repair_spent) + paid
		remaining_time = maxf(0.0, remaining_time - restored / repair_rate)
		construction.work_state = "repairing"
		construction.pause_reason = ""
		builder.state = "repair"
		if cap - float(building.hp) > EPSILON or remaining_time <= EPSILON:
			return
	var cost: float = maxf(float(info.cost), 0.0)
	var progress: float = float(construction.progress)
	# Money and progress accumulate through separate floating-point sums. Settle
	# only an affordable final rounding remainder; a real unpaid balance waits.
	var unpaid: float = maxf(0.0, cost - float(construction.spent))
	if 1.0 - progress <= EPSILON and unpaid <= float(sim.money[team]) + EPSILON and remaining_time + EPSILON >= total * (1.0 - progress):
		sim.money[team] = maxf(0.0, float(sim.money[team]) - unpaid)
		construction.spent = cost
		construction.progress = 1.0
		_complete(sim, building)
		return
	var increase: float = minf(remaining_time / total, 1.0 - progress)
	if cost > 0.0:
		increase = minf(increase, float(sim.money[team]) / cost)
	if increase <= 0.0:
		_pause(construction, "施工资金不足")
		return
	var next_progress: float = minf(1.0, progress + increase)
	var paid: float = minf(cost * (next_progress - progress), maxf(0.0, cost - float(construction.spent)))
	sim.money[team] = maxf(0.0, float(sim.money[team]) - paid)
	construction.spent = minf(cost, float(construction.spent) + paid)
	construction.progress = next_progress
	construction.work_state = "working"
	construction.pause_reason = ""
	building.construct_remaining = maxf(0.0, total * (1.0 - next_progress))
	building.hp = minf(maximum, float(building.hp) + (maximum - float(construction.initial_hp)) * (next_progress - progress))
	building.state = "construct"
	builder.state = "construct"
	if next_progress >= 1.0:
		_complete(sim, building)


static func _complete(sim, building: Dictionary) -> void:
	var builder_id: int = int(building.construction.builder)
	building.construct_remaining = 0.0
	building.hp = float(sim.data_for(building.spec).hp)
	building.state = "idle"
	building.erase("construction")
	sim._invalidate_base_cache()
	if sim.entities.has(builder_id):
		var builder: Dictionary = sim.entities[builder_id]
		if _has_work_order(builder, int(building.id)):
			sim._finish_command(builder)
	sim.events.append({"kind": "ready", "pos": building.pos, "id": building.id})


static func status(sim, building: Dictionary) -> String:
	var construction: Dictionary = building.get("construction", {})
	if construction.is_empty():
		return "已完工"
	var reason: String = _pause_reason(sim, building)
	if not reason.is_empty():
		return reason
	if str(construction.work_state) == "repairing":
		return "修复脚手架"
	if str(construction.work_state) == "paused":
		return str(construction.pause_reason)
	return "现场施工中"


static func dismantle(sim, target_id: int) -> String:
	if not str(sim.result).is_empty():
		return "对局已经结束"
	if not sim.entities.has(target_id):
		return "施工分基地已不存在"
	var building: Dictionary = sim.entities[target_id]
	if building.kind != "building" or sim.data_for(building.spec).get("role", "") != "outpost" or building.get("construction", {}).is_empty():
		return "只能拆除未完工分基地"
	var builder_id: int = int(building.construction.builder)
	if sim.entities.has(builder_id) and _has_work_order(sim.entities[builder_id], target_id):
		sim._finish_command(sim.entities[builder_id])
	sim._kill_entity(target_id, false)
	sim._check_result()
	return ""
