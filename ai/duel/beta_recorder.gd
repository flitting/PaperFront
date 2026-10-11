extends RefCounted

const VERSION := "beta_recorder_v2_formation_details"

func record(observation: Dictionary, memory: Dictionary) -> Dictionary:
	var now: float = float(observation.get("time", 0.0))
	var home: Vector2 = observation.get("home", Vector2.ZERO)
	var enemy_start: Vector2 = observation.get("enemy_start", home)
	var forward: Vector2 = (enemy_start - home).normalized()
	var elapsed: float = maxf(0.001, now - float(memory.get("time", now - 2.0)))
	var previous: Dictionary = memory.get("units", {})
	var current: Dictionary = {}
	var miners: Array = []
	var producers: Array = []
	var combat_units: Array = []
	var visible_combat: Array = []
	var force: Dictionary = {"count":0,"value":0.0,"hp":0.0,"max_hp":0.0,"front":0.0,"engaged":0,"idle":0,"attacking":0}
	var damaged: Array = []
	var disappeared: Array = []
	var visible: Dictionary = {}
	for enemy: Dictionary in observation.get("visible_enemies", []):
		var spec: String = str(enemy.get("spec", ""))
		visible[spec] = int(visible.get(spec, 0)) + 1
		if str(enemy.get("kind","")) == "unit" and not str(enemy.get("weapon","")).is_empty():
			visible_combat.append({"id":enemy.id,"spec":spec,"pos":enemy.pos,"hp":enemy.hp,"max_hp":enemy.max_hp,"weapon":enemy.weapon,"cost":enemy.cost})
	for unit: Dictionary in observation.get("own", []):
		var id: String = str(unit.id)
		var orders: Array = unit.get("commands", [])
		var position: Vector2 = unit.get("pos", home)
		var old: Dictionary = previous.get(id, {})
		var progress: float = position.distance_to(old.get("pos", position))
		current[id] = {"pos":position,"hp":unit.get("hp",0.0),"spec":unit.get("spec",""),"cargo":unit.get("cargo",0.0)}
		if not old.is_empty() and float(unit.get("hp",0.0)) < float(old.get("hp",0.0)):
			damaged.append({"id":unit.id,"spec":unit.spec,"lost_hp":float(old.hp)-float(unit.hp),"pos":position})
		if str(unit.get("art", "")) == "harvester":
			var stalled: float = float(old.get("stalled",0.0)) + elapsed if progress < 0.2 and float(unit.get("cargo",0.0)) == float(old.get("cargo",-1.0)) else 0.0
			current[id].stalled = stalled
			var miner: Dictionary = {"id":unit.id,"pos":position,"hp":unit.hp,"cargo":unit.get("cargo",0.0),"moved":progress,"stalled_seconds":stalled,"commands":orders.duplicate(true)}
			for key: Variant in unit:
				var label: String = str(key)
				if label.contains("harvest") or label.contains("yield") or label.contains("wait") or label.contains("docking") or label.contains("route") or label.contains("traffic") or label in ["state","path_goal","path_index","last_progress","blocked_time","emerging"]:
					miner[label] = unit[key]
			miners.append(miner)
		if str(unit.get("kind", "")) == "building" and str(unit.get("role", "")) in ["barracks","factory","airfield","refinery"]:
			producers.append({"id":unit.id,"role":unit.get("role",""),"pos":position,"hp":unit.hp,"construct_remaining":unit.get("construct_remaining",0.0),"queue":unit.get("queue",[]).duplicate(true),"idle":unit.get("queue",[]).is_empty()})
		if str(unit.get("kind", "")) == "unit" and not str(unit.get("weapon", "")).is_empty():
			combat_units.append({"id":unit.id,"spec":unit.spec,"pos":position,"hp":unit.hp,"max_hp":unit.get("max_hp",0.0),"weapon":unit.get("weapon",""),"commands":orders.duplicate(true),"last_attack_time":unit.get("last_attack_time",-1.0),"emerging":unit.get("emerging",false),"ai_traffic_until":unit.get("ai_traffic_until",0.0)})
			force.count += 1
			force.value += float(unit.get("cost",0.0))
			force.hp += float(unit.hp)
			force.max_hp += float(unit.get("max_hp",0.0))
			force.front = maxf(float(force.front),(position-home).dot(forward))
			if orders.is_empty(): force.idle += 1
			elif str(orders[0].get("kind","")) == "attack": force.engaged += 1
			if bool(unit.get("ai_attacking",false)): force.attacking += 1
	for id: Variant in previous:
		if not current.has(id): disappeared.append({"id":id,"last":previous[id]})
	var stats: Dictionary = observation.get("statistics", {}).duplicate(true)
	var delta_stats: Dictionary = {}
	var previous_stats: Dictionary = memory.get("statistics", {})
	for key: Variant in stats:
		if (stats[key] is int or stats[key] is float) and previous_stats.has(key): delta_stats[str(key)] = float(stats[key]) - float(previous_stats[key])
	var money: float = float(observation.get("money",0.0))
	var answer: Dictionary = {"version":VERSION,"time":now,"money":money,"money_delta":money-float(memory.get("money",money)),"power":observation.get("power",Vector2.ZERO),"roles":observation.get("roles",{}).duplicate(true),"counts":observation.get("counts",{}).duplicate(true),"statistics":stats,"statistics_delta":delta_stats,"force":force,"miners":miners,"producers":producers,"damaged":damaged,"disappeared":disappeared,"visible_counts":visible,"last_command_results":observation.get("last_commands",[]).duplicate(true)}
	answer.combat_units = combat_units
	answer.visible_combat = visible_combat
	memory.time = now
	memory.money = money
	memory.statistics = stats
	memory.units = current
	return answer
