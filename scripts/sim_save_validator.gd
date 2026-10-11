extends RefCounted

const AUTHORED_RUIN_HALF_LIMITS:Dictionary={
	"stone_fort":10.5,"sawmill":6.5,"bell_tower":7.3,"mesa_gate":6.8,"oasis_village":5.5,
}
const AUTHORED_RUIN_MODES:Dictionary={
	"stone_fort":["random_city","islands"],"sawmill":["forest"],"bell_tower":["snow"],
	"mesa_gate":["desert"],"oasis_village":["desert"],
}

# Validate the entire snapshot before changing the running match.
static func check(snapshot: Dictionary) -> String:
	for field in ["rules", "map", "entities"]:
		if not snapshot.get(field) is Dictionary:
			return "存档字段类型错误：" + field
	for field in ["factions", "money", "projectiles", "mines", "bridges", "building_orders", "low_power"]:
		if not snapshot.get(field) is Array:
			return "存档字段类型错误：" + field
	var team_count: int = snapshot.factions.size()
	if team_count < 2 or team_count > 8 or snapshot.money.size() != team_count or snapshot.building_orders.size() != team_count or snapshot.low_power.size() != team_count:
		return "存档阵营状态长度无效"
	if snapshot.has("match_options"):
		if not snapshot.match_options is Dictionary or int(snapshot.match_options.get("players", -1)) != team_count or not snapshot.match_options.get("vision_enabled") is bool: return "存档对局配置无效"
		if snapshot.match_options.has("modern") and not snapshot.match_options.modern is bool: return "存档对局配置无效"
		if snapshot.match_options.has("slots"):
			if not snapshot.match_options.slots is Array or snapshot.match_options.slots.size() != team_count: return "存档玩家槽位无效"
			for team in range(team_count):
				var slot: Variant = snapshot.match_options.slots[team]
				if not slot is Dictionary or slot.get("faction") != snapshot.factions[team] or slot.get("control") not in ["human", "ai"] or slot.get("difficulty") not in ["easy", "normal", "hard"]: return "存档玩家槽位无效"
	if snapshot.has("team_vision"):
		if not snapshot.team_vision is Dictionary or not snapshot.team_vision.get("last_known") is Array or snapshot.team_vision.last_known.size() != team_count: return "存档视野状态无效"
		for team in range(team_count):
			var memory: Variant = snapshot.team_vision.last_known[team]
			if not memory is Dictionary: return "存档视野记忆无效"
			for id in memory:
				var record: Variant = memory[id]
				if not id is int or int(id) < 1 or not record is Dictionary or not record.get("pos") is Vector2 or not (record.pos as Vector2).is_finite() or not _number(record.get("seen_at")) or float(record.seen_at) < 0.0 or float(record.seen_at) > float(snapshot.time): return "存档视野记忆无效"
	if snapshot.has("ai_state"):
		if not snapshot.ai_state is Array or snapshot.ai_state.size() != team_count: return "存档AI状态无效"
		for state in snapshot.ai_state:
			if not state is Dictionary: return "存档AI状态无效"
			for field in ["reaction_clock", "attack_clock", "scout_clock", "naval_clock"]:
				if not _number(state.get(field)) or float(state[field]) < 0.0: return "存档AI状态无效"
	for flag in snapshot.low_power:
		if not flag is bool:
			return "存档电力标记无效"
	if snapshot.has("defense_orders"):
		if not snapshot.defense_orders is Array or snapshot.defense_orders.size() != team_count: return "存档防御订单长度无效"
	if not snapshot.get("ai_enabled") is bool or not _number(snapshot.get("ai_clock")) or not _number(snapshot.get("ai_attack_clock")):
		return "存档电脑状态无效"
	if snapshot.has("nav_dirty") and not snapshot.nav_dirty is bool:
		return "存档导航失效标记无效"
	if snapshot.has("nav_regions"):
		if not snapshot.nav_regions is Array:
			return "存档导航失效区域无效"
		for region in snapshot.nav_regions:
			if not region is Rect2 or not region.position.is_finite() or not region.size.is_finite() or region.size.x < 0.0 or region.size.y < 0.0:
				return "存档导航区域坐标无效"
	if snapshot.has("planning_max_wait") and (not _number(snapshot.planning_max_wait) or float(snapshot.planning_max_wait) < 0.0):
		return "存档寻路等待统计无效"
	if snapshot.has("planning_queue"):
		if not snapshot.planning_queue is Array:
			return "存档寻路等待队列无效"
		var queued: Dictionary = {}
		for id in snapshot.planning_queue:
			if not id is int or queued.has(id) or not snapshot.entities.has(id) or not snapshot.entities[id] is Dictionary or snapshot.entities[id].get("kind") != "unit":
				return "存档寻路等待实体无效"
			queued[id] = true
	for amount in snapshot.money:
		if not _number(amount) or float(amount) < 0.0:
			return "存档资金无效"
	if not _number(snapshot.get("time")) or float(snapshot.time) < 0.0 or not _number(snapshot.get("next_id")) or int(snapshot.next_id) < 1:
		return "存档时间或实体编号无效"
	if snapshot.has("match_statistics"):
		var ledger: Variant=snapshot.match_statistics
		if not ledger is Dictionary or not ledger.get("teams") is Array or not ledger.get("initial_money") is Array or ledger.teams.size()!=team_count or ledger.initial_money.size()!=team_count:
			return "存档战局统计长度无效"
		if not _number(ledger.get("since_time")) or float(ledger.since_time)<0.0 or float(ledger.since_time)>float(snapshot.time):return "存档战局统计时间无效"
		for team: int in team_count:
			var row: Variant=ledger.teams[team]
			if not row is Dictionary or row.get("faction")!=snapshot.factions[team] or not _number(ledger.initial_money[team]) or float(ledger.initial_money[team])<0.0:return "存档战局统计阵营无效"
			for field: String in ["funds_earned","sales_income","units_produced","buildings_built","units_killed","units_lost","buildings_destroyed","buildings_lost","damage_dealt"]:
				if not _number(row.get(field)) or float(row[field])<0.0:return "存档战局统计数值无效"
	if snapshot.get("result", "") not in ["", "win", "lose", "draw"]:
		return "存档胜负状态无效"
	for category in ["economy", "factions", "units", "buildings", "weapons"]:
		if not snapshot.rules.get(category) is Dictionary:
			return "存档规则分类无效：" + category
	var rule_errors: Array[String] = RulesLoader.validate(snapshot.rules, false)
	if not rule_errors.is_empty():
		return "存档规则无效：" + rule_errors[0]
	for faction in snapshot.factions:
		if not faction is String or not snapshot.rules.factions.has(faction):
			return "存档阵营引用无效"
	var terrain: Dictionary = snapshot.map
	if not _number(terrain.get("size")) or int(terrain.size) < 8 or int(terrain.size) > 1024:
		return "存档地图尺寸无效"
	var size: int = int(terrain.size)
	for field in ["heights", "terrain"]:
		if not terrain.get(field) is Array or terrain[field].size() != size:
			return "存档地图网格无效：" + field
		for row in terrain[field]:
			if not row is Array or row.size() != size:
				return "存档地图行长度无效：" + field
			for value in row:
				if not _number(value):
					return "存档地图包含非数值地格"
				if field == "terrain" and int(value) not in [0, 1, 2, 3, 4]:
					return "存档地形类型无效"
	for field in ["starts", "mines", "bridges", "decorations"]:
		if not terrain.get(field) is Array:
			return "存档地图元数据无效：" + field
	var expected_starts: int = int(terrain.get("profile", {}).get("players", 2))
	if terrain.starts.size() != expected_starts:
		return "存档出生点无效"
	for start in terrain.starts:
		if not _pair(start):
			return "存档出生点坐标无效"
	for bridge in terrain.bridges:
		if not _bridge_shape(bridge):
			return "存档桥梁布局无效"
	for mine in terrain.mines:
		if not mine is Dictionary or not _pair(mine.get("pos")) or not _number(mine.get("capacity")):
			return "存档矿区布局无效"
	for decoration in terrain.decorations:
		if not decoration is Dictionary or not _pair(decoration.get("pos")) or not decoration.get("kind") is String:
			return "存档装饰布局无效"
	var map_errors: Array[String] = MapData.validate(terrain)
	if not map_errors.is_empty():
		return "存档地图无效：" + map_errors[0]
	if str(terrain.get("mode", "")) == "campaign":
		if not snapshot.get("campaign") is Dictionary: return "战役任务状态缺失"
		var campaign_error: String = preload("res://scripts/campaign_controller.gd").validate_state(snapshot.campaign)
		if not campaign_error.is_empty(): return campaign_error
	elif snapshot.has("campaign"):
		return "非战役存档包含战役任务状态"
	var ruins: Variant=snapshot.get("ruins",terrain.get("ruins",[]))
	if not ruins is Array:return "存档废墟列表无效"
	for i in range(ruins.size()):
		var ruin: Variant=ruins[i]
		if not ruin is Dictionary or ruin.get("id")!=i or ruin.get("kind") not in ["wall","house","tree"] or not _position(ruin.get("pos"),size):return "存档废墟身份无效"
		if not _ruin_footprint(ruin,terrain,size):return "存档废墟占地无效"
		if not _number(ruin.get("hp")) or not _number(ruin.get("max_hp")) or ruin.hp<0 or ruin.max_hp<=0 or ruin.hp>ruin.max_hp:return "存档废墟生命值无效"
		if ruin.has("yaw") and not _number(ruin.yaw):return "存档废墟朝向无效"
		if not _number(ruin.get("variant")) or int(ruin.variant)<0 or int(ruin.variant)>2:return "存档废墟模型无效"
	if snapshot.has("group_navigation") and not preload("res://scripts/group_navigation.gd").valid_state(snapshot.group_navigation):return "存档群体通行队列无效"
	if snapshot.has("next_formation") and (not snapshot.next_formation is int or snapshot.next_formation<1):return "存档编队编号无效"
	var aircraft_counts: Dictionary = {}
	var unique_counts: Dictionary = {}
	var headquarters_counts: Array[int] = []
	headquarters_counts.resize(team_count)
	headquarters_counts.fill(0)
	var max_id: int = 0
	for id in snapshot.entities:
		if not id is int or int(id) < 1:
			return "存档实体编号类型无效"
		var e: Variant = snapshot.entities[id]
		if not e is Dictionary or e.get("id", -1) != id or e.get("kind", "") not in ["unit", "building"] or not e.get("spec") is String:
			return "存档实体身份无效"
		var group: Dictionary = snapshot.rules.units if e.kind == "unit" else snapshot.rules.buildings
		if not group.has(e.spec) or not _number(e.get("team")) or int(e.team) < 0 or int(e.team) >= team_count:
			return "存档实体规则引用无效"
		var info: Dictionary = group[e.spec]
		if e.kind == "unit" and int(info.get("max_active", 0)) > 0:
			var unique_key: String = "%d:%s" % [int(e.team), str(e.spec)]
			unique_counts[unique_key] = int(unique_counts.get(unique_key, 0)) + 1
		if e.has("captured") and (not e.captured is bool or (e.captured and e.kind != "building")):
			return "存档建筑占领标记无效"
		if e.kind == "building" and info.get("role") == "hq" and not bool(info.get("rebuildable", false)):
			headquarters_counts[int(e.team)] += 1
			if headquarters_counts[int(e.team)] > 1: return "存档每个势力只能拥有一个总部"
		if e.has("veteran") and not e.veteran is bool:return "存档星级标记无效"
		if e.has("experience_value") and (not _number(e.experience_value) or float(e.experience_value)<0):return "存档经验价值无效"
		if bool(e.get("veteran",false)) and (e.kind!="unit" or float(e.get("experience_value",0))<=float(info.get("experience_cost",info.cost))*float(snapshot.rules.get("experience",{}).get("threshold_cost_multiplier",3))):return "存档星级经验不足"
		for carrier_field:String in ["carrier_ready","carrier_pending_count"]:
			if e.has(carrier_field) and (not bool(info.get("carrier",false)) or not e[carrier_field] is int or int(e[carrier_field])<0 or int(e[carrier_field])>2):return "存档航母机组计数无效"
		if e.has("carrier_next_launch") and (not bool(info.get("carrier",false)) or not _number(e.carrier_next_launch) or float(e.carrier_next_launch)<0):return "存档航母起飞时钟无效"
		if e.has("carrier_pending_target") and (not bool(info.get("carrier",false)) or not e.carrier_pending_target is int or int(e.carrier_pending_target)==0):return "存档航母起飞目标无效"
		if e.has("carrier_rebuild") and (not bool(info.get("carrier",false)) or not _number(e.carrier_rebuild) or float(e.carrier_rebuild)<0 or float(e.carrier_rebuild)>20.0):return "存档航母飞机补充状态无效"
		var aircraft: bool = e.kind == "unit" and info.get("domain", "ground") == "air"
		if aircraft:
			if not e.get("ammo") is int or int(e.ammo) < 0 or int(e.ammo) > int(info.ammo_capacity):
				return "存档飞机弹药无效"
			if not e.get("home_airfield") is int or (int(e.home_airfield) != -1 and int(e.home_airfield) < 1):
				return "存档飞机归属机场无效"
			if e.get("flight_state") not in ["airborne", "returning", "rearming", "stranded", "landed"] or not e.get("airborne") is bool:
				return "存档飞机状态无效"
			if not _number(e.get("rearm_remaining")) or float(e.rearm_remaining) < 0.0 or float(e.rearm_remaining) > float(info.rearm_time) or not _number(e.get("flight_height")):
				return "存档飞机补给或高度无效"
			var launch:Variant=e.get("carrier_launch",null)
			var launching:bool=launch!=null
			if launching:
				if not launch is Dictionary or not bool(info.get("carrier_plane",false)) or not _number(launch.get("elapsed")) or float(launch.elapsed)<0 or float(launch.elapsed)>2.5 or not e.get("carrier_id") is int or int(e.carrier_id)<1 or int(e.home_airfield)!=-1 or not bool(e.airborne) or e.flight_state!="airborne":return "存档舰载机起飞状态无效"
				var carrier:Variant=snapshot.entities.get(int(e.carrier_id),{})
				if not carrier is Dictionary:return "存档舰载机起飞母舰无效"
				if not carrier.is_empty() and (carrier.get("team")!=e.team or not bool(snapshot.rules.units.get(str(carrier.get("spec","")),{}).get("carrier",false))):return "存档舰载机起飞母舰无效"
				if float(e.flight_height)<-64.0 or float(e.flight_height)>float(info.flight_height)+.001:return "存档舰载机起飞高度无效"
			var servicing: bool = e.flight_state == "rearming"
			var grounded: bool = servicing or e.flight_state == "landed"
			if e.airborne == grounded or (not launching and absf(float(e.flight_height) - (0.35 if grounded else float(info.flight_height))) > 0.001) or (not servicing and float(e.rearm_remaining) != 0.0):
				return "存档飞机飞行与补给状态不匹配"
			if servicing and int(e.home_airfield)<1 and not bool(info.get("carrier_plane",false)):
				return "存档补给飞机缺少机场"
			if int(e.home_airfield) > 0:
				var field: Variant = snapshot.entities.get(int(e.home_airfield))
				if not field is Dictionary or field.get("kind") != "building" or field.get("team") != e.team or not snapshot.rules.buildings.has(str(field.get("spec", ""))) or snapshot.rules.buildings[field.spec].get("role") != "airfield" or not _number(field.get("construct_remaining")) or float(field.construct_remaining) > 0.0:
					return "存档飞机机场引用无效"
				var apron_limit: float = float(snapshot.rules.buildings[field.spec].get("size", 1)) * 0.5 + maxf(float(info.get("radius", 0.35)), 2.25) + 3.8
				if servicing and (not field.get("pos") is Vector2 or (e.pos as Vector2).distance_to(field.pos) > apron_limit):
					return "存档补给飞机不在机场"
				aircraft_counts[int(e.home_airfield)] = int(aircraft_counts.get(int(e.home_airfield), 0)) + 1
		if not _position(e.get("pos"), size) or not e.get("rally") is Vector2 or not e.rally.is_finite():
			return "存档实体位置无效"
		if group[e.spec].faction != snapshot.factions[int(e.team)] and not (e.kind == "building" and e.get("captured", false)):
			return "存档实体阵营不匹配"
		if e.has("turret_alpha") and not _number(e.turret_alpha):
			return "存档炮塔朝向无效"
		if e.has("rotation_quarters") and (e.kind!="building" or not _quarter_turn(e.rotation_quarters)):return "存档建筑朝向必须为四个直角方向"
		if e.has("rail_rotation") and not _quarter_turn(e.rail_rotation):return "存档铁路朝向必须为四个直角方向"
		for field in ["hand_contact_height","hand_ground_height"]:
			if e.has(field) and (e.kind != "unit" or not bool(info.get("hero",false)) or not _number(e[field])):
				return "存档手掌接触高度无效："+field
			if e.has(field) and absf(float(e[field]))>128.0: return "存档手掌高度超出范围："+field
		if e.has("turret_target") and (not e.turret_target is int or int(e.turret_target) == 0 or (int(e.turret_target) < -1 and int(e.turret_target) > -1001)):
			return "存档炮塔目标无效"
		if e.has("planning_wait") and (not _number(e.planning_wait) or float(e.planning_wait) < 0.0):
			return "存档单位寻路等待无效"
		if e.has("visible_to") and (not e.visible_to is int or int(e.visible_to) < 0 or int(e.visible_to) >= 1 << team_count): return "存档单位视野掩码无效"
		if e.has("last_damage_time") and (e.kind != "unit" or not _number(e.last_damage_time) or float(e.last_damage_time) < 0.0 or float(e.last_damage_time) > float(snapshot.time)):
			return "存档脱战时间无效"
		if e.has("last_attack_time") and (e.kind != "unit" or not _number(e.last_attack_time) or float(e.last_attack_time) < 0.0 or float(e.last_attack_time) > float(snapshot.time)):
			return "存档攻击时间无效"
		if e.has("breakthrough_last_pos") and (e.kind != "unit" or not _position(e.breakthrough_last_pos, size)):
			return "存档突破位置无效"
		if e.has("hand_strike") or e.has("hand_recover") or e.has("hand_target") or e.has("hand_landing") or e.has("hand_force") or e.has("hand_resolving"):
			if e.kind != "unit" or not bool(info.get("hero", false)): return "存档英雄状态附着于普通单位"
			for timer in ["hand_strike", "hand_recover"]:
				if not _number(e.get(timer)) or float(e[timer]) < 0.0 or float(e[timer]) > float(info.get("attack_windup", 0.5)) + float(info.get("attack_recovery", 0.35)): return "存档英雄攻击计时无效"
			if not e.get("hand_target") is int or int(e.hand_target) == 0 or not _position(e.get("hand_landing"), size) or not e.get("hand_force") is bool or not e.get("hand_resolving") is bool: return "存档英雄目标状态无效"
			if bool(e.hand_resolving): return "存档英雄结算状态无效"
		for field in ["breakthrough_progress", "breakthrough_ready_until", "emp_until"]:
			if e.has(field) and (not _number(e[field]) or float(e[field]) < 0.0): return "存档阵营状态无效：" + field
		for field in ["overcharge_remaining", "overcharge_cooldown", "designation_progress"]:
			if e.has(field) and (not _number(e[field]) or float(e[field]) < 0.0): return "存档支援状态无效：" + field
		for field in ["park_after_service", "service_interrupt"]:
			if e.has(field) and not e[field] is bool: return "存档飞机服务标记无效：" + field
		if e.has("service_goal") and (not e.service_goal is Vector2 or (not e.service_goal.is_finite() and e.service_goal != Vector2.INF)): return "存档飞机服务目标无效"
		if e.has("designation_target") and (not e.designation_target is int or (int(e.designation_target) != -1 and int(e.designation_target) < 1)): return "存档标定目标无效"
		for field in ["mine_search", "refinery_search"]:
			if e.has(field) and not _resource_search(e[field], snapshot.mines.size() if field == "mine_search" else -1):
				return "存档采矿目标搜索无效：" + field
		for field in ["zeppelin_mg_cooldown","zeppelin_mg_flash","zeppelin_bomb_flash","zeppelin_mg_alpha","zeppelin_mg_pitch"]:
			if e.has(field) and (not _number(e[field]) or (field.ends_with("cooldown") and float(e[field])<0)): return "存档飞艇独立武器数值无效"
		for field in ["hp", "alpha", "cooldown", "construct_remaining", "cargo", "hit_flash", "path_wait", "stuck", "motion", "attack_flash"]:
			if not _number(e.get(field)):
				return "存档实体数值无效：" + field
		if e.kind=="unit" and float(e.hp)>float(info.hp)*(float(snapshot.rules.get("experience",{}).get("max_hp_multiplier",1.15)) if bool(e.get("veteran",false)) else 1.0)+.01:return "存档单位生命超过星级上限"
		if float(e.hp) <= 0.0 or float(e.cooldown) < 0.0 or float(e.cargo) < 0.0 or float(e.construct_remaining) < 0.0:
			return "存档实体数值范围无效"
		if e.has("construction"):
			var construction_error: String = _construction(snapshot, e, info)
			if not construction_error.is_empty(): return construction_error
		for field in ["commands", "queue", "path"]:
			if not e.get(field) is Array:
				return "存档实体队列无效：" + field
		if not e.get("path_goal") is Vector2 or not e.get("state") is String:
			return "存档导航状态无效"
		if not e.path_goal.is_finite() and e.path_goal != Vector2.INF:
			return "存档导航目标无效"
		if e.has("yield_goal") and (not e.yield_goal is Vector2 or (not e.yield_goal.is_finite() and e.yield_goal != Vector2.INF)):
			return "存档让路状态无效"
		for field in ["harvest_override", "repairing", "gift_pending", "blocked_notice"]:
			if not e.get(field) is bool:
				return "存档实体标记无效：" + field
		for field in ["harvest_mine", "harvest_refinery", "auto_target"]:
			if not _number(e.get(field)):
				return "存档实体目标无效：" + field
		for point in e.path:
			if not _position(point, size):
				return "存档路径包含无效位置"
		for command in e.commands:
			if command is Dictionary and command.has("rotation_quarters") and not _quarter_turn(command.rotation_quarters):return "存档施工命令朝向无效"
			if not command is Dictionary or command.get("kind", "") not in ["move", "force_move", "attack_move", "patrol", "attack", "force_attack", "repair_bridge", "repair_unit", "repair_building", "capture", "deploy_outpost", "resume_outpost", "board", "return", "harvest", "rescue", "land", "unload_move", "service", "garrison", "return_miner"] or not _position(command.get("pos"), size) or not _number(command.get("target")):
				return "存档单位命令无效"
			if e.kind != "unit": return "存档建筑不可持有单位命令"
			if aircraft and command.has("formation"): return "存档飞机不可加入地面编队"
			if command.kind == "return" and not aircraft: return "存档地面单位不可返航"
			if command.kind == "land" and not aircraft: return "存档地面单位不可降落"
			if command.kind == "unload_move" and (int(info.get("transport_capacity", 0)) <= 0 or e.get("passengers", []).is_empty()): return "存档卸载命令运输单位无效"
			if command.kind in ["repair_building", "repair_bridge", "capture", "deploy_outpost", "resume_outpost"] and info.get("art") != "engineer": return "存档工程命令单位无效"
			if command.kind == "repair_unit" and info.get("art") != "engineer" and (float(info.get("repair_rate", 0.0)) <= 0.0 or aircraft): return "存档维修单位无效"
			if command.kind == "rescue" and (float(info.get("rescue_speed_bonus", 0.0)) <= 0.0 or not command.target is int or int(command.target) < 1): return "存档拖救命令无效"
			if command.kind == "resume_outpost":
				if not command.target is int or int(command.target) < 1: return "存档接手施工目标无效"
				if snapshot.entities.has(int(command.target)):
					var site: Variant = snapshot.entities[int(command.target)]
					if not site is Dictionary or site.get("kind") != "building" or site.get("team") != e.team or not snapshot.rules.buildings.has(str(site.get("spec", ""))) or not _engineer_building(snapshot, int(e.team), snapshot.rules.buildings[site.spec]): return "存档接手施工建筑无效"
			if command.kind == "capture":
				if not command.target is int or int(command.target) < 1: return "存档占领目标无效"
				if snapshot.entities.has(int(command.target)):
					var capture_target: Variant = snapshot.entities[int(command.target)]
					if not capture_target is Dictionary or capture_target.get("kind") != "building" or not snapshot.rules.buildings.has(str(capture_target.get("spec", ""))) or snapshot.rules.buildings[capture_target.spec].get("role") in ["wall", "barricade", "rail", "rail_junction"]:
						return "存档占领建筑类型无效"
			if command.kind == "deploy_outpost":
				if command.target != -1 or not command.get("spec") is String or not snapshot.rules.buildings.has(command.spec): return "存档现场施工规则无效"
				var field_building: Dictionary = snapshot.rules.buildings[command.spec]
				if not _engineer_building(snapshot, int(e.team), field_building) or not _number(command.get("cost")) or float(command.cost) not in [0.0, float(field_building.cost)]: return "存档现场施工费用无效"
			if command.kind == "board":
				if info.get("armor_class") != "infantry" or aircraft or not command.target is int or int(command.target) < 1: return "存档上车命令单位无效"
				if snapshot.entities.has(int(command.target)):
					var carrier: Variant = snapshot.entities[int(command.target)]
					if not carrier is Dictionary or carrier.get("kind") != "unit" or carrier.get("team") != e.team or not snapshot.rules.units.has(str(carrier.get("spec", ""))) or int(snapshot.rules.units[carrier.spec].get("transport_capacity", 0)) <= 0:
						return "存档上车车辆无效"
			if command.has("formation") and (not command.formation is int or command.formation<1 or not command.get("formation_goal") is Vector2 or not command.formation_goal.is_finite()):return "存档编队命令无效"
		for order in e.queue:
			if not _order(order, snapshot.rules.units, false):
				return "存档单位生产订单无效"
			if e.kind != "building" or snapshot.rules.units[order.spec].faction != snapshot.factions[int(e.team)] or not _producer_matches(info, str(snapshot.rules.units[order.spec].producer)):
				return "存档生产设施与订单不匹配"
			if int(snapshot.rules.units[order.spec].get("max_active", 0)) > 0:
				var unique_key: String = "%d:%s" % [int(e.team), str(order.spec)]
				unique_counts[unique_key] = int(unique_counts.get(unique_key, 0)) + 1
		max_id = maxi(max_id, int(id))
	for unique_key in unique_counts:
		var unique_spec: String = str(unique_key).split(":", false, 1)[1]
		if int(unique_counts[unique_key]) > int(snapshot.rules.units[unique_spec].max_active): return "存档英雄数量超过上限"
	var garrison_error:String=preload("res://scripts/garrison_operations.gd").validate_snapshot(snapshot)
	if not garrison_error.is_empty():return garrison_error
	var squad_error: String = preload("res://scripts/infantry_squads.gd").validate_snapshot(snapshot)
	if not squad_error.is_empty(): return squad_error
	var emergence_error: String = preload("res://scripts/production_lifecycle.gd").validate_snapshot(snapshot)
	if not emergence_error.is_empty(): return emergence_error
	var transport_error: String = _transports(snapshot)
	if not transport_error.is_empty(): return transport_error
	for id in snapshot.entities:
		var e: Dictionary = snapshot.entities[id]
		if e.kind == "building" and snapshot.rules.buildings[e.spec].get("role") == "airfield":
			if int(aircraft_counts.get(id, 0)) + e.queue.size() > int(snapshot.rules.buildings[e.spec].aircraft_capacity):
				return "存档机场机位超过容量"
	if int(snapshot.next_id) <= max_id:
		return "存档实体编号重复风险"
	for team in range(team_count):
		for channel in ["normal", "defense"]:
			var order: Variant = snapshot.building_orders[team] if channel == "normal" else (snapshot.defense_orders[team] if snapshot.has("defense_orders") else {})
			if not order is Dictionary or (not order.is_empty() and not _order(order, snapshot.rules.buildings, true)):
				return "存档建筑订单无效"
			if not order.is_empty() and snapshot.rules.buildings[order.spec].faction != snapshot.factions[team]:
				return "存档建筑订单阵营无效"
			if not order.is_empty():
				var building_info: Dictionary = snapshot.rules.buildings[order.spec]
				var role: String = str(building_info.role)
				if role == "hq" and not bool(building_info.get("rebuildable", false)): return "存档总部不可建造"
				if (role in ["tower", "wall", "barricade", "rail", "rail_junction"]) != (channel == "defense"): return "存档建筑订单通道无效"
				if _engineer_building(snapshot, team, building_info) and building_info.get("role","") not in ["rail","rail_junction"] and not order.has("builder"): return "存档现场施工缺少工兵"
				if order.has("builder"):
					if not _engineer_building(snapshot, team, building_info) or not order.builder is int or not snapshot.entities.has(order.builder): return "存档现场施工建造者无效"
					var builder: Dictionary = snapshot.entities[order.builder]
					if builder.kind != "unit" or builder.team != team or snapshot.rules.units[builder.spec].get("art") != "engineer" or int(builder.get("transport_id", -1)) > 0: return "存档现场施工建造者无效"
	for shell in snapshot.projectiles:
		if not shell is Dictionary:
			return "存档炮弹类型无效"
		if shell.has("trajectory"):
			if str(shell.trajectory)!="gravity_bomb": return "存档自由落体弹道无效"
			for field in ["gravity_origin_y","gravity_y","gravity_velocity","gravity"]:
				if not _number(shell.get(field)): return "存档自由落体数值无效"
			if float(shell.gravity)<=0 or not shell.get("horizontal_velocity") is Vector2 or not (shell.horizontal_velocity as Vector2).is_finite(): return "存档炸弹速度无效"
		if shell.has("force") and not shell.force is bool: return "存档强制攻击标记无效"
		if (shell.has("heading") and not _number(shell.heading)) or (shell.has("body_heading") and not _number(shell.body_heading)):
			return "存档炮弹发射朝向无效"
		if shell.has("source") and (not shell.source is int or int(shell.source) < 1):
			return "存档炮弹发射实体无效"
		if shell.has("spec") and (not shell.spec is String or (not snapshot.rules.units.has(shell.spec) and not snapshot.rules.buildings.has(shell.spec))):
			return "存档炮弹发射模型无效"
		if shell.has("weapon") and (not shell.weapon is String or not snapshot.rules.weapons.has(shell.weapon)):
			return "存档炮弹武器无效"
		for field in ["emp_vehicle_duration", "emp_building_duration"]:
			if shell.has(field) and (not _number(shell[field]) or float(shell[field]) < 0.0): return "存档炮弹断流时长无效"
		if shell.has("targets"):
			if not shell.targets is Array or shell.targets.is_empty(): return "存档弹道目标域无效"
			var target_domains: Dictionary = {}
			for domain in shell.targets:
				if domain not in ["ground", "air", "naval"] or target_domains.has(str(domain)): return "存档弹道目标域无效"
				target_domains[str(domain)] = true
		if shell.has("multipliers"):
			if not shell.multipliers is Dictionary: return "存档弹道伤害倍率无效"
			for armor in shell.multipliers:
				if armor not in ["building", "armored", "infantry"] or not _number(shell.multipliers[armor]) or float(shell.multipliers[armor]) < 0.0: return "存档弹道伤害倍率无效"
		if shell.has("target") and (not shell.target is int or int(shell.target) == 0): return "存档弹道目标无效"
		for height in ["source_height", "target_height"]:
			if shell.has(height) and not _number(shell[height]): return "存档弹道高度无效"
		for field in ["pos", "start", "landing"]:
			if not _position(shell.get(field), size):
				return "存档炮弹坐标无效"
		for field in ["elapsed", "duration", "damage", "blast", "team"]:
			if not _number(shell.get(field)):
				return "存档炮弹数值无效"
		if float(shell.duration) <= 0.0 or float(shell.elapsed) < 0.0 or float(shell.damage) < 0.0 or float(shell.blast) < 0.0 or int(shell.team) < 0 or int(shell.team) >= team_count:
			return "存档炮弹数值范围无效"
	var miners: Dictionary = {}
	for index in range(snapshot.mines.size()):
		var mine: Variant = snapshot.mines[index]
		if not mine is Dictionary or not _position(mine.get("pos"), size) or not _number(mine.get("amount")) or not _number(mine.get("capacity")) or float(mine.amount) < 0.0 or float(mine.capacity) <= 0.0 or float(mine.amount) > float(mine.capacity):
			return "存档矿点状态无效"
		if mine.has("drill") and int(mine.drill) > 0:
			var drill_id: int = int(mine.drill)
			if not snapshot.entities.has(drill_id): return "存档矿点钻机占用失效"
			var drill: Dictionary = snapshot.entities[drill_id]
			if drill.kind != "building" or snapshot.rules.buildings.get(drill.spec, {}).get("role", "") != "drill" or int(drill.get("drill_mine", -1)) != index: return "存档矿点与钻机关系无效"
		if mine.has("miner"):
			var miner: Variant = mine.miner
			if not miner is int or (miner != -1 and miner < 1): return "存档矿柱占用者无效"
			if miner > 0:
				if miners.has(miner) or not snapshot.entities.has(miner): return "存档矿柱占用重复或失效"
				var unit: Dictionary = snapshot.entities[miner]
				if unit.kind != "unit" or not str(unit.spec).ends_with("_harvester") or int(unit.harvest_mine) != index or (unit.pos as Vector2).distance_to(mine.pos) > float(snapshot.rules.units[unit.spec].radius) + float(snapshot.rules.economy.get("harvester_mining_margin", 1.4)): return "存档矿柱采矿关系无效"
				miners[miner] = true
	for bridge in snapshot.bridges:
		if not _bridge_shape(bridge) or not bridge.get("alive") is bool or not _number(bridge.get("hp")) or not _number(bridge.get("repair_progress")) or float(bridge.repair_progress) < 0.0 or float(bridge.repair_progress) > 1.0:
			return "存档桥梁状态无效"
	return ""

static func _engineer_building(snapshot: Dictionary, team: int, info: Dictionary) -> bool:
	if str(info.get("faction", "")) != snapshot.factions[team] or (str(info.get("role", "")) == "hq" and not bool(info.get("rebuildable", false))): return false
	return (snapshot.factions[team]=="iron" and info.get("role","") in ["rail","rail_junction"]) or str(info.get("role", "")) == "outpost" or snapshot.rules.factions[snapshot.factions[team]].get("building_method", "") == "engineer"

static func _producer_matches(info: Dictionary, role: String) -> bool:
	return (role=="amphibious" and info.get("role","") in ["factory","shipyard"]) or str(info.get("role", "")) == role or role in info.get("production_roles", [])

static func _construction(snapshot: Dictionary, e: Dictionary, info: Dictionary) -> String:
	if e.kind != "building" or not _engineer_building(snapshot, int(e.team), info) or not e.construction is Dictionary: return "存档脚手架类型无效"
	var c: Dictionary = e.construction
	if not c.get("builder") is int or (c.builder != -1 and c.builder < 1): return "存档施工工程兵编号无效"
	for field in ["progress", "spent", "initial_hp", "repair_spent"]:
		if not _number(c.get(field)): return "存档施工数值无效"
	if c.progress < 0.0 or c.progress >= 1.0 or c.spent < 0.0 or c.spent > float(info.cost) or c.initial_hp <= 0.0 or c.initial_hp > float(info.hp) or c.repair_spent < 0.0: return "存档施工数值范围无效"
	if absf(float(c.spent) - float(c.progress) * float(info.cost)) > 0.01 or absf(float(e.construct_remaining) - (1.0 - float(c.progress)) * float(info.build_time)) > 0.01: return "存档施工进度和付款不一致"
	if float(e.hp) > float(c.initial_hp) + (float(info.hp) - float(c.initial_hp)) * float(c.progress) + 0.01: return "存档脚手架生命超过当前施工进度"
	if c.get("work_state") not in ["paused", "working", "repairing"] or not c.get("pause_reason") is String: return "存档施工状态无效"
	if c.builder > 0:
		var builder: Variant = snapshot.entities.get(c.builder)
		if not builder is Dictionary or builder.get("kind") != "unit" or builder.get("team") != e.team or not snapshot.rules.units.has(str(builder.get("spec", ""))) or snapshot.rules.units[builder.spec].get("art") != "engineer": return "存档施工工程兵引用无效"
	return ""

static func _transports(snapshot: Dictionary) -> String:
	var entities: Dictionary = snapshot.entities
	for e in entities.values():
		var transport_id: Variant = e.get("transport_id", -1)
		var passengers: Variant = e.get("passengers", [])
		if not transport_id is int or (transport_id != -1 and transport_id < 1): return "存档步兵运输车辆编号无效"
		if not passengers is Array: return "存档运输乘员列表无效"
		var info: Dictionary = snapshot.rules.units[e.spec] if e.kind == "unit" else snapshot.rules.buildings[e.spec]
		var capacity: int = int(info.get("transport_capacity", 0)) if e.kind == "unit" else 0
		if passengers.size() > capacity: return "存档侦察车搭载人数超过容量"
		var seen: Dictionary = {}
		for id in passengers:
			if not id is int or seen.has(id) or not entities.has(id): return "存档运输乘员引用无效"
			seen[id] = true
			var passenger: Dictionary = entities[id]
			if passenger.kind != "unit" or passenger.team != e.team or passenger.get("transport_id", -1) != e.id or snapshot.rules.units[passenger.spec].get("armor_class") != "infantry" or snapshot.rules.units[passenger.spec].get("domain", "ground") != "ground": return "存档运输乘员关联无效"
		if transport_id > 0:
			if e.kind != "unit" or info.get("armor_class") != "infantry" or info.get("domain", "ground") != "ground" or not entities.has(transport_id): return "存档搭载步兵类型无效"
			var carrier: Dictionary = entities[transport_id]
			if carrier.kind != "unit" or carrier.team != e.team or not carrier.get("passengers", []).has(e.id) or int(snapshot.rules.units[carrier.spec].get("transport_capacity", 0)) < 1: return "存档步兵与侦察车关联无效"
			if not (e.pos as Vector2).is_equal_approx(carrier.pos): return "存档搭载步兵位置无效"
			if not e.commands.is_empty() or not e.path.is_empty() or e.state != "transported" or snapshot.get("planning_queue", []).has(e.id): return "存档搭载步兵导航状态无效"
	return ""

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

static func _pair(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1])

static func _position(value: Variant, size: int) -> bool:
	return value is Vector2 and value.is_finite() and value.x >= 0.0 and value.y >= 0.0 and value.x < size and value.y < size

static func _ruin_footprint(ruin:Dictionary,terrain:Dictionary,size:int)->bool:
	var half:Variant=ruin.get("half")
	if not half is Vector2 or not half.is_finite() or half.x<=0.0 or half.y<=0.0:return false
	# Historical ordinary scenery keeps the original six-metre radius bound.
	if half.length()<=6.0:return true
	var archetype:Variant=ruin.get("archetype")
	var profile:Variant=terrain.get("profile",{})
	if ruin.get("kind")!="house" or not archetype is String or not AUTHORED_RUIN_HALF_LIMITS.has(archetype):return false
	if not profile is Dictionary or not profile.get("design_version") is int or profile.design_version!=6 or terrain.get("mode") not in AUTHORED_RUIN_MODES[archetype]:return false
	var limit:float=float(AUTHORED_RUIN_HALF_LIMITS[archetype])
	if half.x>limit+.0001 or half.y>limit+.0001 or not _position(ruin.get("pos"),size):return false
	var yaw:Variant=ruin.get("yaw",0.0)
	if not _number(yaw):return false
	# These are real broad landmark colliders, never artificially reduced to
	# satisfy a serialization limit. Their full rotated footprint must fit.
	var cosine:float=absf(cos(float(yaw)))
	var sine:float=absf(sin(float(yaw)))
	var extent:=Vector2(cosine*half.x+sine*half.y,sine*half.x+cosine*half.y)
	var position:Vector2=ruin.pos
	return position.x-extent.x>=0.0 and position.y-extent.y>=0.0 and position.x+extent.x<=float(size) and position.y+extent.y<=float(size)

static func _bridge_shape(value: Variant) -> bool:
	if not value is Dictionary or not _number(value.get("id")) or int(value.id) < 1 or not value.get("bounds") is Array or value.bounds.size() != 4 or not value.get("heads") is Array or value.heads.size() != 2:
		return false
	if value.has("naval_clearance") and (not _number(value.naval_clearance) or float(value.naval_clearance)<0.0): return false
	for number in value.bounds:
		if not _number(number):
			return false
	return _pair(value.heads[0]) and _pair(value.heads[1])

static func _order(value: Variant, group: Dictionary, building: bool) -> bool:
	if not value is Dictionary or not value.get("spec") is String or not group.has(value.spec) or not value.get("ready") is bool:
		return false
	for field in ["remaining", "total", "cost", "progress"]:
		if not _number(value.get(field)):
			return false
	if not building and not value.get("started") is bool:
		return false
	for field in ["rotation_quarters","rail_rotation"]:
		if value.has(field) and not _quarter_turn(value[field]):return false
	return float(value.total) > 0.0 and float(value.remaining) >= 0.0 and float(value.remaining) <= float(value.total) and float(value.cost) >= 0.0 and float(value.progress) >= 0.0 and float(value.progress) <= 1.0

static func _quarter_turn(value: Variant) -> bool:
	return value is int and value>=0 and value<4

static func _resource_search(value: Variant, mine_count: int) -> bool:
	if not value is Dictionary:
		return false
	if value.is_empty():
		return true
	if not value.get("candidates") is Array or not value.get("next") is int or value.next < 0 or value.next > value.candidates.size() or not _number(value.get("retry_at")) or float(value.retry_at) < 0.0:
		return false
	for id in value.candidates:
		if not id is int or int(id) < (0 if mine_count >= 0 else 1) or (mine_count >= 0 and int(id) >= mine_count):
			return false
	return true
