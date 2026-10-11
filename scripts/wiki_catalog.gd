class_name WikiCatalog
extends RefCounted

const Squads = preload("res://scripts/infantry_squads.gd")
const Localization = preload("res://scripts/localization.gd")
const TraitText = preload("res://scripts/faction_trait_text.gd")
const Construction = preload("res://scripts/building_construction.gd")
const TierAvailability = preload("res://scripts/tier_availability.gd")

## Read-only presentation of the live rules. Every numeric / boolean leaf is
## retained, including future nested fields; asset paths never enter the tables.
const TECHNICAL_FIELDS: Array[String] = ["id", "art", "animations", "legacy_id", "portrait", "model", "model_path", "icon", "icon_path", "roster_hidden", "naval_role"]
const BASE_FIELDS: Array[String] = ["tier", "cost", "hp", "armor", "build_time"]
const UNIT_FIELDS: Array[String] = ["speed", "radius", "turn_speed", "has_turret", "turret_turn_speed", "fire_while_moving", "crush", "crushable", "crush_strength", "crush_resistance", "flight_height", "ammo_capacity", "rearm_time", "repair_radius", "repair_rate", "transport_capacity", "logical_size", "rail_only", "self_heal_rate", "self_heal_delay", "vision_radius"]
const BUILDING_FIELDS: Array[String] = ["power", "local_power", "local_power_radius", "construction_radius", "size", "expands", "aircraft_capacity", "repair_radius", "repair_rate", "service_rate", "unlocks_tier", "vision_radius", "vision_bonus"]
const WEAPON_FIELDS: Array[String] = ["damage", "penetration", "interval", "range", "kind", "blast", "speed", "targets", "multipliers", "trajectory", "gravity", "inherited_velocity", "beam_duration", "emp_vehicle_duration", "emp_building_duration", "emp_air_duration"]
const LABELS: Dictionary = {
	"tier": "科技等级", "cost": "造价", "hp": "最大生命", "build_time": "生产时间", "speed": "移动速度",
	"radius": "碰撞半径", "turn_speed": "车体 / 身体转向速度", "has_turret": "独立炮塔",
	"turret_turn_speed": "炮塔转向速度", "fire_while_moving": "行进中射击", "crush": "可执行地面碾压", "crush_strength": "碾压等级", "crush_resistance": "抗碾压等级",
	"crushable": "可被载具碾压", "flight_height": "巡航高度", "ammo_capacity": "弹药容量",
	"rearm_time": "机场补给时间", "repair_radius": "维修范围", "repair_rate": "维修速度",
	"service_rate": "车间维修速度", "unlocks_tier": "完工解锁科技",
	"transport_capacity": "步兵运输容量",
	"rescue_radius": "拖救协助范围", "rescue_speed_bonus": "受损友军撤离速度增量",
	"designation_radius": "目标标定范围", "designation_track_time": "持续追踪时间", "damage_bonus": "伤害增量",
	"aircraft_repair_rate": "停机飞机维修速度",
	"power": "电力收支", "size": "占地尺寸", "expands": "扩展建设范围",
	"aircraft_capacity": "机场机位", "vision_radius": "视野半径", "vision_bonus": "友军自动索敌范围增量",
	"damage": "单次基础伤害", "interval": "攻击间隔", "range": "射程", "kind": "弹种",
	"permanent_air":"永久留空", "rotorcraft":"旋翼机", "amphibious":"两栖通行", "submarine":"潜航", "sonar_range":"声呐范围", "anti_submarine":"反潜武器", "carrier":"航空母舰", "internal_only":"舰载自动单位", "armor": "护甲数值", "penetration": "武器穿透", "friendly_fire": "伤及友军",
	"trajectory": "弹道", "gravity": "重力加速度", "inherited_velocity": "继承载具速度比例",
	"blast": "爆炸半径", "targets": "可攻击目标", "multipliers": "护甲伤害倍率",
	"infantry": "步兵", "armored": "装甲", "building": "建筑", "ground": "地面", "air": "空中", "naval": "海上",
	"draft": "吃水", "air_draft": "水面以上净空", "waterline": "模型水线", "coast_split": "岸水占地比例", "harbor_depth": "港湾水深要求",
	"initial_money": "开局资金", "ore_capacity": "旧矿量参数（新矿柱无限）", "ore_regen": "旧矿点再生参数（新矿柱不耗尽）",
	"harvester_capacity": "矿车载货上限", "harvest_rate": "矿车采集速度", "ore_value": "矿石价值参数",
	"low_power_multiplier": "低电工作速度倍率", "construction_animation": "落地施工时间",
	"sell_ratio": "建筑出售回收比例", "repair_cost": "每回复 1 生命的维修费用",
	"bridge_hp": "桥梁最大生命", "bridge_cost": "桥梁完整修复费用", "bridge_time": "桥梁完整修复时间",
	"build_radius": "扩建半径", "construction_radii": "完工设施建设半径", "fire_angle": "开火允许偏角", "cell_size": "格子尺寸参数",
	"minimum_shell_time": "炮弹最短飞行时间参数",
	"select": "选中", "move": "移动", "attack": "攻击", "ready": "生产完成", "return": "返航",
	"local_power": "基地局部供电容量", "local_power_radius": "基地局部供电半径", "construction_radius": "基地建设半径",
	"production_roles": "生产职能", "prerequisite_roles": "科技前置职能", "building_method": "建设方式",
	"rebuildable": "允许重复建造",
	"regen_delay": "自动恢复等待", "regen_fraction_per_second": "自动恢复最大生命比例 / 秒",
	"emp_vehicle_duration": "装甲单位失控时间", "emp_building_duration": "建筑失控时间", "emp_air_duration": "空军失控时间",
	"beam_duration": "持续束流时长", "logical_size": "逻辑占地边长", "rail_only": "仅沿己方铁路通行",
	"self_heal_rate": "自身恢复生命 / 秒", "self_heal_delay": "自身恢复脱战等待", "drill_income_rate": "钻机资金收入 / 秒",
	"harvester_unload_time": "矿车卸矿时间", "air_idle_return_delay": "空闲返航等待", "rail_transition_cost": "铁路上下轨选路惩罚"
}
const ROLE_NAMES: Dictionary = {
	"hq": "总部", "power": "发电站", "refinery": "精炼厂", "barracks": "兵营", "factory": "载具工厂",
	"tower": "防御塔", "tech": "研究所", "wall": "围墙", "barricade": "拒马", "outpost": "分基地",
	"repair": "修理厂", "advanced_power": "高级发电站", "airfield": "机场", "shipyard": "船坞", "drill": "采矿钻机", "rail": "铁路", "rail_junction": "三向铁路岔道"
}

static func tier_label(spec: Dictionary) -> String:
	return "T%d" % TierAvailability.tier(spec)


static func tier_description(spec: Dictionary) -> String:
	return TierAvailability.requirement_text(spec).get_slice(" · ", 1)


static func penetration_rule_text(rules: Dictionary, compact: bool = false) -> String:
	var configured: Variant = rules.get("combat_model", {})
	var model: Dictionary = configured if configured is Dictionary else {}
	var low: String = _number(float(model.get("non_penetrating_damage_multiplier", 0.25)) * 100.0) + "%"
	# The partial pair also opts the snapshot into unarmored full damage.
	# Older snapshots retain the original strict-greater two-band behavior.
	if model.has("partial_penetration_threshold") and model.has("partial_penetration_damage_multiplier"):
		var threshold: String = _number(float(model.partial_penetration_threshold) * 100.0) + "%"
		var partial: String = _number(float(model.partial_penetration_damage_multiplier) * 100.0) + "%"
		if compact: return "护甲为0或穿透大于护甲：全额；穿透达护甲的%s至100%%：%s伤害；不足%s：%s伤害" % [threshold, partial, threshold, low]
		return "护甲为0时全额伤害；穿透大于护甲时造成全额伤害；穿透达到护甲的%s且不超过护甲时造成%s伤害；低于护甲的%s时造成%s伤害。" % [threshold, partial, threshold, low]
	if compact: return "穿透大于护甲：全额；穿透不超过护甲：%s伤害" % low
	return "穿透大于护甲时造成全额伤害；穿透不超过护甲时造成%s伤害。" % low


static func veteran_kill_experience_text(rules: Dictionary) -> String:
	var configured: Variant = rules.get("experience", {})
	var experience: Dictionary = configured if configured is Dictionary else {}
	return "击杀星级敌军经验×" + _number(float(experience.get("veteran_kill_experience_multiplier", 1.0)))


static func entries(rules: Dictionary, faction: String = "", kind: String = "", query: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var search: String = query.strip_edges().to_lower()
	var chosen_kind: String = kind.trim_suffix("s")
	for category: String in ["units", "buildings"]:
		var entry_kind: String = "unit" if category == "units" else "building"
		if not chosen_kind.is_empty() and chosen_kind != entry_kind:
			continue
		var specs: Dictionary = rules.get(category, {})
		for raw_id: Variant in specs:
			if not specs[raw_id] is Dictionary:
				continue
			var id: String = str(raw_id)
			var spec: Dictionary = specs[raw_id]
			if bool(spec.get("roster_hidden",false)):continue
			var spec_faction: String = str(spec.get("faction", ""))
			if not faction.is_empty() and faction != spec_faction:
				continue
			var faction_name: String = str(rules.get("factions", {}).get(spec_faction, {}).get("name", spec_faction))
			var entry: Dictionary = {
				"id": id, "kind": entry_kind, "spec": spec.duplicate(true), "faction": spec_faction,
				"faction_name": faction_name, "name": str(spec.get("name", id)),
				"formal_name": str(spec.get("formal_name", spec.get("name", id))),
				"description": str(spec.get("description", ""))
			}
			var search_text: String = " ".join([id, entry.name, entry.formal_name, entry.description, faction_name,
				ROLE_NAMES.get(str(spec.get("role", spec.get("producer", ""))), ""),
				"单位" if entry_kind == "unit" else "建筑", tier_label(spec), tier_description(spec), _names(rules, spec.get("requires", [])),
				" ".join(TraitText.spec_lines(rules, spec))]).to_lower()
			# Search both source and displayed text, so English names and roles work
			# without changing the authoritative rules or save format.
			search_text += " " + Localization.text(search_text).to_lower()
			var matches: bool = true
			for term: String in search.split(" ", false):
				if not search_text.contains(term):
					matches = false
					break
			if matches:
				result.append(entry)
	# Keep a stable order independent of JSON dictionary insertion order.
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_key: String = str(a.faction) + ("0" if a.kind == "unit" else "1") + str(a.id)
		var b_key: String = str(b.faction) + ("0" if b.kind == "unit" else "1") + str(b.id)
		return a_key < b_key)
	return result


static func sections(rules: Dictionary, id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var category: String = "units" if rules.get("units", {}).has(id) else "buildings"
	if not rules.get(category, {}).get(id) is Dictionary:
		return result
	var spec: Dictionary = rules[category][id]
	var prefix: String = category + "." + id
	var unit: bool = category == "units"
	var faction: String = str(spec.get("faction", ""))
	var base: Array[Dictionary] = []
	base.append(_row("所属阵营", str(rules.get("factions", {}).get(faction, {}).get("name", faction))))
	base.append(_row("科技解锁", tier_label(spec) + " · " + tier_description(spec)))
	base.append(_row("前置设施", _names(rules, spec.get("requires", []))))
	if unit:
		var producer: String = _producer(rules, spec)
		base.append(_row("生产设施", producer))
	else:
		base.append(_row("设施用途", "基地兵营" if _is_base_barracks(spec) else str(ROLE_NAMES.get(str(spec.get("role", "")), "其他设施"))))
	var infantry: bool = unit and spec.get("armor_class", "") == "infantry" and spec.get("domain", "ground") == "ground"
	if infantry:
		base.append(_row("编制人数", "%d 人" % Squads.size(spec), prefix + ".squad_size" if spec.has("squad_size") else "", spec.get("squad_size")))
		var squad_roles: Dictionary = {"engineer":"单人工程兵", "line":"常规步兵小队", "specialist":"精锐步兵小队", "sniper":"狙击小队"}
		base.append(_row("操控类型", str(squad_roles.get(str(spec.get("squad_role", "engineer" if spec.get("art", "") == "engineer" else "line")), "步兵小队"))))
		base.append(_row("整组招募费用", _number(Squads.cost(spec)) + " 资金"))
		base.append(_row("整组训练时间", _number(Squads.training_time(spec)) + " 秒", prefix + ".squad_build_time" if spec.has("squad_build_time") else "", spec.get("squad_build_time")))
		base.append(_row("成员伤害结算", "整队生产与指挥；每名成员独立承受伤害。" if Squads.size(spec) > 1 else "工程兵单独生产与指挥。"))
	for key: String in BASE_FIELDS:
		_append_field(base, spec, key, prefix, "entity")
		if infantry and key in ["cost", "hp", "build_time"]:
			base.back().label = {"cost":"每名成员造价", "hp":"每名成员最大生命", "build_time":"每名成员训练时间"}[key]
		if key == "build_time" and not unit and _field_building(rules, spec): base.back().label = "现场施工时间"
	_add_section(result, "生产与基础", base)
	var trait_rows: Array[Dictionary] = []
	for line: String in TraitText.spec_lines(rules, spec): trait_rows.append(_row("作战特性", line))
	if unit or spec.get("role", "") == "hq":
		var traits: Dictionary = {}
		if faction == "iron" and (not unit or spec.get("armor_class", "") == "armored"):
			for key in ["regen_delay", "regen_fraction_per_second"]:
				var configured: Dictionary = rules.get("factions", {}).get(faction, {}).get("traits", {})
				if configured.has(key): traits[key] = configured[key]
		_flatten_numeric(traits, "factions." + faction + ".traits", "阵营特性", trait_rows, "trait")
	_add_section(result, "阵营与作战特性", trait_rows)
	var capabilities: Array[Dictionary] = []
	if bool(spec.get("permanent_air",false)):capabilities.append(_row("飞行与补给","永久留空，不消耗弹药，不需要机场停靠。"))
	if bool(spec.get("amphibious",false)):capabilities.append(_row("生产与通行","战车工厂和船坞均可生产；可跨越可通行海岸。"))
	if bool(spec.get("internal_only",false)):capabilities.append(_row("生产方式","由航母自动调度，不可单独购买。"))
	if unit:
		capabilities.append(_row("行动领域", _domain(str(spec.get("domain", "ground")))))
		capabilities.append(_row("护甲类别", str(LABELS.get(str(spec.get("armor_class", "infantry" if spec.get("crushable", false) else "armored")), "其他护甲"))))
		capabilities.append(_row("经验获取", veteran_kill_experience_text(rules)))
		for key: String in UNIT_FIELDS:
			_append_field(capabilities, spec, key, prefix, "entity")
		# These missing flags have an actual default in Simulation, so readers also
		# learn why paper infantry cannot fire while moving or rotate a turret.
		if not spec.has("has_turret"):
			capabilities.append(_row("独立炮塔", "否"))
		if not spec.has("fire_while_moving"):
			capabilities.append(_row("行进中射击", "否"))
	else:
		capabilities.append(_row("护甲类别", "建筑"))
		for key: String in BUILDING_FIELDS:
			_append_field(capabilities, spec, key, prefix, "entity")
			if key == "expands" and rules.get("economy", {}).has("construction_radii"):
				capabilities.back().label = "旧存档扩建标记"
	_add_section(result, "机动与能力" if unit else "建筑能力", capabilities)
	var weapon_id: String = str(spec.get("weapon", ""))
	var weapon: Dictionary = rules.get("weapons", {}).get(weapon_id, {})
	var weapon_rows: Array[Dictionary] = []
	if weapon.is_empty():
		weapon_rows.append(_row("武装", "无"))
	else:
		if weapon.get("trajectory", "") == "gravity_bomb":
			weapon_rows.append(_row("主武器", "短程自由落体炸弹"))
			weapon_rows.append(_row("投弹方式", "飞临目标附近，从吊舱向下投放；炸弹受重力下落，短程投弹只攻击地面与海上目标。背部机枪独立瞄准与开火。"))
		for key: String in WEAPON_FIELDS:
			_append_field(weapon_rows, weapon, key, "weapons." + weapon_id, "weapon")
		if not weapon.has("targets"):
			weapon_rows.append(_row("可攻击目标（默认）", "地面"))
		# An omitted armor multiplier is exactly 1 in the damage implementation.
		for armor: String in ["infantry", "armored", "building"]:
			var multiplier: float = float(weapon.get("multipliers", {}).get(armor, 1.0))
			if not weapon.get("multipliers", {}).has(armor):
				weapon_rows.append(_row("对" + str(LABELS[armor]) + "伤害倍率（默认）", _number(multiplier) + " 倍"))
			if float(weapon.get("interval", 0.0)) > 0.0:
				weapon_rows.append(_row("对" + str(LABELS[armor]) + "理论每秒伤害", _number(float(weapon.get("damage", 0.0)) * multiplier / float(weapon.interval)) + " 生命/秒"))
		if float(weapon.get("interval", 0.0)) > 0.0:
			weapon_rows.append(_row("射速", _number(1.0 / float(weapon.interval)) + " 发/秒"))
			weapon_rows.append(_row("基础理论每秒伤害", _number(float(weapon.get("damage", 0.0)) / float(weapon.interval)) + " 生命/秒"))
		weapon_rows.append(_row("理论伤害说明", "只对可攻击目标生效，假设连续命中单个目标；不计转向、移动、飞行与返航补给，范围伤害不重复计入。"))
		if weapon.has("penetration"):
			weapon_rows.append(_row("穿甲规则", penetration_rule_text(rules) + "表中理论值按全额穿甲伤害计算，并保留兵种伤害倍率。"))
			if weapon.get("aoe_falloff","")=="linear": weapon_rows.append(_row("范围衰减", "从爆心至受击表面，伤害与穿透同时线性递减；边缘降至零。"))
		var additional_weapon: Array[Dictionary] = []
		_extra_numeric(weapon, WEAPON_FIELDS, "weapons." + weapon_id, additional_weapon, "weapon")
		weapon_rows.append_array(additional_weapon)
	_add_section(result, "武器与伤害", weapon_rows)
	var secondary_id: String = str(spec.get("secondary_weapon", ""))
	var secondary: Dictionary = rules.get("weapons", {}).get(secondary_id, {})
	if not secondary.is_empty():
		var secondary_rows: Array[Dictionary] = [_row("副武器", "独立背部机枪")]
		for key: String in WEAPON_FIELDS:
			_append_field(secondary_rows, secondary, key, "weapons." + secondary_id, "weapon")
		if float(secondary.get("interval", 0.0)) > 0.0:
			secondary_rows.append(_row("射速", _number(1.0 / float(secondary.interval)) + " 发/秒"))
			secondary_rows.append(_row("基础理论每秒伤害", _number(float(secondary.get("damage", 0.0)) / float(secondary.interval)) + " 生命/秒"))
		secondary_rows.append(_row("独立开火", "机枪独立转向、瞄准与射击，可攻击空中、地面与海上目标；可在主武器投弹时同时防御，不消耗炸弹弹药。"))
		_extra_numeric(secondary, WEAPON_FIELDS, "weapons." + secondary_id, secondary_rows, "weapon")
		_add_section(result, "独立副武器 · 背部机枪", secondary_rows)
	_add_section(result, "经济与支援", _economy_rows(rules, spec, unit))
	var extras: Array[Dictionary] = []
	var known: Array[String] = BASE_FIELDS.duplicate()
	known.append_array(UNIT_FIELDS if unit else BUILDING_FIELDS)
	if infantry: known.append_array(["squad_size", "squad_build_time"])
	_extra_numeric(spec, known, prefix, extras, "entity")
	_add_section(result, "其他规则数值", extras)
	var voices: Array[Dictionary] = []
	var voice_spec: Dictionary = spec.get("voices", {})
	for action: Variant in voice_spec:
		var lines: Variant = voice_spec[action]
		if lines is Array:
			for index: int in lines.size():
				voices.append(_row(str(LABELS.get(str(action), "其他语音")) + " · " + str(index + 1), str(lines[index])))
	_add_section(result, "单位语音", voices)
	return result


static func _is_base_barracks(spec: Dictionary) -> bool:
	return spec.get("faction", "") == "rivet" and spec.get("role", "") == "hq" and bool(spec.get("rebuildable", false))


static func _unified_rivet_base(rules: Dictionary) -> bool:
	return _is_base_barracks(rules.get("buildings", {}).get("rivet_hq", {}))


static func _field_building(rules: Dictionary, spec: Dictionary) -> bool:
	return spec.get("role", "") == "outpost" or (rules.factions.get(spec.get("faction", ""), {}).get("building_method", "") == "engineer" and (spec.get("role", "") != "hq" or bool(spec.get("rebuildable", false))))


static func _economy_rows(rules: Dictionary, spec: Dictionary, unit: bool) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var eco: Dictionary = rules.get("economy", {})
	var low: float = float(eco.get("low_power_multiplier", 0.5))
	_append_field(rows, eco, "low_power_multiplier", "economy", "economy")
	var field_building: bool = not unit and _field_building(rules, spec)
	var engineer_faction: bool = rules.factions.get(spec.get("faction", ""), {}).get("building_method", "") == "engineer"
	var unified_base: bool = engineer_faction and _unified_rivet_base(rules)
	if field_building:
		rows.append(_row("现场施工速度", "按建筑设定的施工时间推进，不受全域缺电影响；资金不足或工程兵离开时暂停。"))
	elif spec.has("build_time"):
		var grouped: bool = unit and Squads.size(spec) > 1
		var duration: float = Squads.training_time(spec) if grouped else float(spec.build_time)
		rows.append(_row("低电时整队训练时间" if grouped else "低电时生产时间", _number(duration / low) + " 秒" if low > 0.0 else "暂停生产"))
	_append_field(rows, eco, "repair_cost", "economy", "economy")
	if not unit:
		_append_field(rows, eco, "construction_animation", "economy", "economy")
		_append_field(rows, eco, "sell_ratio", "economy", "economy")
		rows.append(_row("出售回收资金", _number(float(spec.get("cost", 0.0)) * float(eco.get("sell_ratio", 0.5))) + " 资金"))
		if eco.has("construction_radii"):
			rows.append(_row("扩建半径", _number(Construction.radius_in_rules(rules, spec)) + " 格"))
			var coverage: String = "重锤只有基地兵营提供基地建设范围；开局与工兵新建的是同一种建筑，新建基地兵营可以在已有范围外扩张。" if unified_base else "重锤只有主基地和大兵营提供基地建设范围；须由工程兵在范围内施工，新的大兵营可以远程扩张。" if engineer_faction else "每座己方建筑完成后都提供周围建设范围，围墙和拒马也提供小范围；同方设施的范围连成建设区，放置仍需满足前置、地形和占地要求。"
			rows.append(_row("完工建设范围", coverage if Construction.radius_in_rules(rules, spec) > 0.0 else "本对局规则未给该类设施配置建设范围。"))
		elif bool(spec.get("expands", false)):
			_append_field(rows, eco, "build_radius", "economy", "economy")
		_append_field(rows, eco, "repair_rate", "economy", "economy")
		var self_rate: float = float(spec.get("hp", 0.0)) * float(eco.get("repair_rate", 0.02))
		rows.append(_row("建筑自修速度", _number(self_rate) + " 生命/秒"))
		rows.append(_row("建筑自修满速耗费", _number(self_rate * float(eco.get("repair_cost", 0.2))) + " 资金/秒"))
		rows.append(_row("从零生命修至满血的理论费用", _number(float(spec.get("hp", 0.0)) * float(eco.get("repair_cost", 0.2))) + " 资金"))
		if spec.get("role", "") == "refinery":
			rows.append(_row("建成赠送", "1 辆" + _name(rules, str(spec.get("faction", "")) + "_harvester")))
		if spec.get("role", "") in ["barracks", "factory", "airfield", "shipyard"] or not spec.get("production_roles", []).is_empty():
			var produced: Array[String] = []
			for id: Variant in rules.get("units", {}):
				var candidate: Dictionary = rules.units[id]
				if candidate.get("faction", "") == spec.get("faction", "") and (candidate.get("producer", "") == spec.get("role", "") or candidate.get("producer", "") in spec.get("production_roles", [])):
					produced.append(_name(rules, str(id)))
			rows.append(_row("可生产单位", "、".join(produced)))
		if spec.get("role", "") in ["hq", "outpost"]:
			rows.append(_row("基地存续与授权", "每座基地兵营只训练步兵，不建造建筑；工程兵可继续现场建造基地兵营与其他建筑，每座完工基地兵营均满足基地和兵营前置。" if unified_base else "重锤建筑由工程兵现场施工；主基地只训练步兵，分基地也不提供远程建筑生产。" if engineer_faction else "任意一座己方总部或分基地存活，即可维持基地存续与建筑生产；分基地可代替总部前置。"))
		if float(spec.get("local_power", 0.0)) > 0.0:
			rows.append(_row("局部供电规则", "只供应半径内的己方已完成建筑，按距离分配并受总容量限制；不向远处建筑供电。供电建筑被EMP压制或摧毁后停止供电。"))
		if spec.get("role", "") == "hq":
			rows.append(_row("基地兵营数量" if _is_base_barracks(spec) else "总部数量限制", "可建造多座；开局与工程兵新建的基地兵营共用同一建筑类型和全部数值，失守后可重新建造。" if _is_base_barracks(spec) else "每方同时最多拥有一座总部；总部不能建造其他总部，失守后也不能重新建造。"))
		if field_building:
			rows.append(_row("工程兵施工", "选中己方工程兵点击建筑卡立即选址，无需预付款或等订单；工程兵抵达后搭起脚手架，资金随现场施工进度支付，不消耗工程兵。"))
			rows.append(_row("前线建设范围", "钻机可以在已有建设范围之外的合法矿脉上施工。" if spec.get("role", "") == "drill" else "基地兵营可以在已有建设范围外选址扩张；其他重锤建筑须在已完成基地兵营的建设范围内施工。" if unified_base else "额外大兵营可以远程选址扩张；其他重锤建筑须在已完成主基地或大兵营的建设范围内施工。" if engineer_faction else "无需己方总部或已有扩建覆盖；仍遵守前置、地形及占地规则，资金不足时保留进度并暂停。"))
			rows.append(_row("受损与接手", "脚手架受伤后工程兵先维修再继续建造，额外维修费会拖慢施工；工程兵阵亡或离开则暂停，其他工程兵可右键接手。"))
			rows.append(_row("主动拆除", "选中未完工建筑点击拆除脚手架；释放占地，已花施工及维修资金不退款。"))
		if spec.get("role", "") in ["tower", "repair"]:
			rows.append(_row("电力要求", "低电时停止自动攻击或维修。"))
		if spec.has("service_rate"):
			rows.append(_row("入厂维修", "选中受损己方地面装甲载具，右键修理厂；载具自行寻路进入车间，再按实际恢复生命付费。离开车间、资金不足或停电时停止维修。"))
			rows.append(_row("维修对象", "地面装甲载具；飞机由机场检修，舰船使用海上维修。"))
			rows.append(_row("车间满速耗费", _number(float(spec.service_rate) * float(eco.get("repair_cost", 0.2))) + " 资金/秒"))
		if spec.get("role", "") == "airfield":
			rows.append(_row("机位规则", "已造飞机与生产队列共同占用机位；飞机补给不花资金，低电时补给减速。"))
		if spec.get("role", "") == "shipyard": rows.append(_row("港湾建设", shipyard_instructions()))
		if spec.get("role", "") == "wall":
			rows.append(_row("通行规则", "阻挡所有地面单位；飞机可越过。延伸线上的每格独立计费。"))
		if spec.get("role", "") == "barricade":
			rows.append(_row("通行规则", "阻挡车辆；步兵穿越速度为正常的 35%；飞机可越过。"))
	if spec.get("role", "") == "drill":
		rows.append(_row("钻机收入", _number(float(eco.get("drill_income_rate",16)))+" 资金/秒（正常供电、已完工）"))
		rows.append(_row("矿点占用", "钻机与矿脉是独立对象，脚手架开工即独占该矿脉；摧毁后释放原矿脉，不重置储量或复制矿物。"))
	if bool(spec.get("rail_only",false)):
		rows.append(_row("铁路专用通行", "只能沿所属玩家的合法铁路运行，速度为地面基准两倍；断轨立即更新路径，工厂无轨则等待连接。"))
	if str(spec.get("art", "")) == "harvester" or (not unit and spec.get("role", "") == "refinery"):
		for key: String in ["harvester_capacity", "harvest_rate", "ore_capacity", "ore_regen"]:
			_append_field(rows, eco, key, "economy", "economy")
		var rate: float = float(eco.get("harvest_rate", 25.0))
		if rate > 0.0:
			rows.append(_row("理论装满时间", _number(float(eco.get("harvester_capacity", 500.0)) / rate) + " 秒（不含往返）"))
		rows.append(_row("满载交付收入", _number(float(eco.get("harvester_capacity", 500.0))) + " 资金（1 单位辉晶直接兑换 1 资金）"))
		rows.append(_row("矿柱规则", "辉晶矿柱储量无限，不会耗尽或被摧毁，地面单位不可穿过；双方合计每根同时只有一辆矿车开采，其余矿车等待或转场。"))
	if spec.has("repair_rate"):
		rows.append(_row("支援维修满速耗费", _number(float(spec.repair_rate) * float(eco.get("repair_cost", 0.2))) + " 资金/秒"))
		rows.append(_row("支援维修规则", "持续修复己方受损地面单位；多个维修来源取最高速度，不叠加，资金不足时按剩余资金修复。" if unit else "修复己方受损目标；多个维修来源取最高速度，不叠加，资金不足时按剩余资金修复。"))
		rows.append(_row("支援维修目标", "己方地面单位（不含飞机）；建筑使用立即修复规则。" if unit and spec.get("art", "") == "engineer" else "己方地面装甲载具；维修车不能修步兵、建筑或飞机。" if unit else "地面装甲载具"))
	if str(spec.get("art", "")) == "engineer":
		rows.append(_row("立即修复建筑", "右键己方受损建筑；到达建筑边缘后一次恢复全部缺失生命，按实际恢复生命收费，资金不足时等待整次修复，不消耗工程兵。"))
		rows.append(_row("现场建设" if engineer_faction else "修建分基地", ("可搭建全部建筑；基地兵营可在已有建设范围外选址扩张，开局与新建的是同一种建筑。" if unified_base else "可搭建所有非总部建筑；须先建大兵营拓展基地建设范围。" if engineer_faction else "可搭建分基地。") + "点击建造卡立即选址；工程兵抵达后搭建脚手架，随施工进度扣款。受损先修复，工兵阵亡或离开则暂停，其他工兵右键接手，也可主动拆除。"))
		rows.append(_row("立即占领建筑", "右键敌方建筑，到达边缘后立即转为己方，不消耗工程兵。包括防御塔；不包括围墙、拒马、铁路和岔道口。基地兵营可占领多座；其他总部已有一座时不能再占领另一座。" if _unified_rivet_base(rules) else "右键敌方建筑，到达边缘后立即转为己方，不消耗工程兵。包括防御塔；不包括围墙、拒马、铁路和岔道口。已有总部时不能占领另一座总部。"))
		rows.append(_row("占领生产设施", "原生产队列清空，按未完成比例退款给原主人；原主人飞机失去被占领机场的保障。"))
		for key: String in ["bridge_hp", "bridge_cost", "bridge_time"]:
			_append_field(rows, eco, key, "economy", "economy")
		rows.append(_row("修桥规则", "按修复进度支付资金；桥梁已有生命时按缺损比例计算费用与时间；多个工兵不加速同一座桥。"))
	if int(spec.get("transport_capacity", 0)) > 0:
		rows.append(_row("步兵运输规则", transport_instructions(spec)))
		rows.append(_row("地点卸载", "L 选择卸载地点；载具抵达后卸下步兵，空地不足时等待。U 在当前位置卸载。"))
		if spec.get("domain", "ground") == "air": rows.append(_row("航空装卸", "B 返航补给后停机；步兵到机场边缘登机。也可点击降落选择合法空地，或用 L 选择地点降落并卸载；下达移动命令重新起飞。"))
		if spec.get("domain", "ground") == "naval": rows.append(_row("海岸装卸", "运输船停靠陆岸；步兵从岸边登船。L 选择登陆海岸，船只抵达邻接海域后卸下步兵；U 在当前海岸卸载，空地不足时等待。"))
	if spec.get("domain", "ground") == "naval": rows.append(_row("航行规则", "沿连通水域航行；陆地及低净空桥梁阻挡舰艇。指定海上集结点；登陆由运输船将地面步兵送到可通行海岸。"))
	if spec.has("rescue_radius"): rows.append(_row("拖救规则", "拖救车右键仍存活的友方受损载具，持续护送；目标生命≤60%并执行撤离移动时获得速度增量。需距离与可通行连接，多车不叠加，不回收残骸。"))
	if spec.has("designation_radius"): rows.append(_row("标定规则", "自动持续追踪范围内最近敌方地面载具，满足距离与视线后提高友方射击伤害；追踪中断即失效，多标定车不叠加。"))
	if spec.has("aircraft_repair_rate"): rows.append(_row("航空维护", "飞机返航停机时按实际恢复生命消耗资金；电力不足停止维修。"))
	if spec.get("domain", "ground") == "air":
		rows.append(_row("低电时补给时间", _number(float(spec.get("rearm_time", 0.0)) / low) + " 秒" if low > 0.0 else "暂停补给"))
		rows.append(_row("弹药与返航", "主武器每次投弹消耗 1 发；独立机枪不消耗炸弹弹药。炸弹耗尽后自动返航补满；机场失去后寻找有空机位的己方机场。" if not str(spec.get("secondary_weapon", "")).is_empty() else "每次开火消耗 1 发；耗尽后自动返航补满。机场失去后寻找有空机位的己方机场。" if not str(spec.get("weapon", "")).is_empty() else "无武装，不消耗射击弹药；可主动返航接受机场检修。机场失去后寻找有空机位的己方机场。"))
	if not str(spec.get("weapon", "")).is_empty():
		_append_field(rows, eco, "fire_angle", "economy", "economy")
		rows.append(_row("强制命令", "H 后左键目标或地面强制攻击，可攻击友方、树木、房屋和中立石墙；普通右键及攻击移动不会主动破坏这些中立障碍。F 后左键强制移动：普通坦克可碾压敌方步兵；重型坦克及重装高级单位还可碾压敌方普通坦克。友军、同等级重装、舰船、飞机和轨道专用车辆不参与地面碾压。"))
	# New economy numbers cannot silently disappear when the rule schema grows.
	var known_eco: Array[String] = []
	for raw_key: Variant in LABELS:
		known_eco.append(str(raw_key))
	_extra_numeric(eco, known_eco, "economy", rows, "economy")
	return rows


static func _append_field(rows: Array[Dictionary], spec: Dictionary, key: String, prefix: String, context: String) -> void:
	if not spec.has(key):
		return
	var value: Variant = spec[key]
	if value is Dictionary:
		_flatten_numeric(value, prefix + "." + key, _label(key), rows, context)
	elif value is Array:
		if key == "targets":
			var domains: Array[String] = []
			for domain: Variant in value: domains.append(_domain(str(domain)))
			rows.append(_row(_label(key), "、".join(domains), prefix + "." + key, value))
		else:
			_flatten_numeric(value, prefix + "." + key, _label(key), rows, context)
	else:
		var label: String = _label(key)
		if key == "speed" and context == "weapon": label = "弹丸飞行速度"
		if key == "repair_rate" and context == "economy": label = "建筑自修生命比例 / 秒"
		rows.append(_row(label, _value(key, value, context), prefix + "." + key, value))


static func _extra_numeric(spec: Dictionary, known: Array[String], prefix: String, rows: Array[Dictionary], context: String) -> void:
	for raw_key: Variant in spec:
		var key: String = str(raw_key)
		if key in known or key in TECHNICAL_FIELDS or key == "voices":
			continue
		_flatten_numeric(spec[raw_key], prefix + "." + key, _label(key), rows, context)


static func _flatten_numeric(value: Variant, path: String, label: String, rows: Array[Dictionary], context: String) -> void:
	if value is Dictionary:
		for key: Variant in value:
			_flatten_numeric(value[key], path + "." + str(key), label + " · " + _label(str(key)), rows, context)
	elif value is Array:
		for index: int in value.size():
			_flatten_numeric(value[index], path + "." + str(index), label + " · " + str(index + 1), rows, context)
	elif value is int or value is float or value is bool:
		var key: String = path.get_slice(".", path.get_slice_count(".") - 1)
		var display: String = "是" if value is bool and value else "否" if value is bool else _value(key, value, context)
		if path.contains(".multipliers."):
			display += " 倍"
		rows.append(_row(label, display, path, value))


static func _value(key: String, value: Variant, context: String) -> String:
	if value is bool:
		return "是" if value else "否"
	if key == "kind":
		return {"instant":"即时命中", "shell":"飞行弹丸", "laser":"定点激光射线", "beam":"持续束流"}.get(str(value),str(value))
	if key == "trajectory": return {"gravity_bomb":"自由落体投弹"}.get(str(value), str(value))
	if not (value is int or value is float):
		return str(value)
	var number: String = _number(float(value))
	if key in ["tier", "unlocks_tier"]: return "T" + number
	if key == "local_power": return number + " 电力（仅供附近建筑）"
	if key == "power":
		return ("供应 +" + number if float(value) > 0.0 else "消耗 " + _number(absf(float(value))) if float(value) < 0.0 else "0") + " 电力"
	if key == "size":
		return number + " × " + number + " 格（" + _number(float(value) * float(value)) + " 格²）"
	if key in ["cost", "initial_money", "bridge_cost"]:
		return number + " 资金"
	if key == "repair_cost":
		return number + " 资金/生命"
	if key in ["hp", "damage", "bridge_hp"]:
		return number + " 生命"
	if key in ["build_time", "rearm_time", "interval", "construction_animation", "bridge_time", "minimum_shell_time", "regen_delay", "emp_vehicle_duration", "emp_building_duration", "emp_air_duration", "beam_duration", "self_heal_delay", "harvester_unload_time", "air_idle_return_delay"]:
		return number + " 秒"
	if key == "service_rate": return number + " 生命/秒"
	if key == "repair_rate":
		return number + "（" + _number(float(value) * 100.0) + "% 最大生命/秒）" if context == "economy" else number + " 生命/秒"
	if key in ["low_power_multiplier", "sell_ratio", "regen_fraction_per_second"]:
		return number + "（" + _number(float(value) * 100.0) + "%）"
	if key in ["turn_speed", "turret_turn_speed"]:
		return number + " °/秒"
	if key == "fire_angle":
		return "±" + number + " °"
	if key == "speed":
		return number + " 格/秒" + ("（即时命中，无飞行时间）" if context == "weapon" and float(value) == 0.0 else "")
	if key in ["radius", "flight_height", "repair_radius", "vision_bonus", "range", "blast", "build_radius", "construction_radius", "cell_size", "local_power_radius"]:
		return number + " 格"
	if key in ["harvest_rate", "ore_regen"]:
		return number + " 辉晶/秒"
	if key in ["harvester_capacity", "ore_capacity"]:
		return number + " 辉晶"
	if key == "ammo_capacity":
		return number + " 发"
	if key == "aircraft_capacity":
		return number + " 架（含生产队列）"
	if key == "transport_capacity":
		return number + " 名地面步兵"
	return number


static func _names(rules: Dictionary, ids: Array) -> String:
	var names: Array[String] = []
	for id: Variant in ids:
		names.append(_name(rules, str(id)))
	return "无" if names.is_empty() else "、".join(names)


static func _name(rules: Dictionary, id: String) -> String:
	for category: String in ["units", "buildings"]:
		if rules.get(category, {}).get(id) is Dictionary:
			var spec: Dictionary = rules[category][id]
			return str(spec.get("name", spec.get("formal_name", "未命名条目")))
	return "未收录设施"


static func _producer(rules: Dictionary, spec: Dictionary) -> String:
	var faction: String = str(spec.get("faction", ""))
	var role: String = str(spec.get("producer", ""))
	if role == "carrier": return "航母飞行甲板"
	var producer_roles: Array = ["factory", "shipyard"] if role == "amphibious" else [role]
	var names: PackedStringArray = []
	for id: Variant in rules.get("buildings", {}):
		var candidate: Dictionary = rules.buildings[id]
		if candidate.get("faction", "") == faction and producer_roles.any(func(required): return candidate.get("role", "") == required or required in candidate.get("production_roles", [])):
			names.append(_name(rules, str(id)))
	return "、".join(names) if not names.is_empty() else str(ROLE_NAMES.get(role, "未收录设施"))


static func _domain(domain: String) -> String:
	return domain_name(domain)


static func domain_name(domain: String) -> String:
	return str(LABELS.get(domain, "其他领域"))


static func target_names(domains: Array) -> String:
	var names: PackedStringArray = []
	for domain: Variant in domains: names.append(domain_name(str(domain)))
	return " / ".join(names)


static func transport_instructions(spec: Dictionary) -> String:
	var capacity: int = int(spec.get("transport_capacity", 0))
	if capacity <= 0: return ""
	var text: String = "搭载 %d 名地面步兵（含工程兵、反甲兵）；步兵右键己方运输载具登载，选中载具点击卸载按钮下车。搭载中无法独立行动或攻击。" % capacity
	if spec.get("domain", "ground") == "naval": text += "\n运输船须停靠陆岸装卸；U 当前岸边卸载，L 指定登陆海岸。"
	elif spec.get("domain", "ground") == "air": text += "\n运输机先降落装卸；B 返航停机，U 当前卸载，L 指定地点降落卸载。"
	else: text += "\nU 当前卸载，L 指定地点抵达卸载。"
	return text


static func shipyard_instructions() -> String:
	return "船厂必须横跨相邻陆岸与连通水面，舰艇由水侧出口出航。己方保护港湾可由已完成总部或分基地授权建设；扩张港湾须取得己方扩建范围，工兵可建立海岸分基地。"


static func _label(key: String) -> String:
	return str(LABELS.get(key, "扩展参数（" + key.replace("_", " ") + "）"))


static func _number(value: float) -> String:
	# Tiny new rule values must not be rounded to an apparent zero.
	if value != 0.0 and absf(value) < 0.000001:
		return String.num_scientific(value)
	var formatted: String = "%.6f" % value
	while formatted.ends_with("0"):
		formatted = formatted.trim_suffix("0")
	return formatted.trim_suffix(".")


static func _row(label: String, value: String, source_path: String = "", raw_value: Variant = null) -> Dictionary:
	var original: Variant = raw_value.duplicate(true) if raw_value is Dictionary or raw_value is Array else raw_value
	return {"label": label, "value": value, "source_path": source_path, "raw_value": original}


static func _add_section(result: Array[Dictionary], title: String, rows: Array[Dictionary]) -> void:
	if not rows.is_empty():
		result.append({"title": title, "rows": rows})
