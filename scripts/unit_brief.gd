extends RefCounted

## Short battlefield roles, shared by the selected-unit panel and card hints.
static func role(rules: Dictionary, info: Dictionary) -> String:
	var art: String = str(info.get("art", ""))
	var utility: Dictionary = {
		"engineer":"铁路施工 / 维修 / 占领" if info.get("faction", "") == "iron" else "施工 / 维修 / 占领",
		"harvester":"采矿 / 返厂卸矿", "rig":"部署钻井 / 资源开采",
		"repair_vehicle":"前线维修", "recycler":"拖救 / 撤离护送",
		"inspection":"探测 / 反隐", "designation":"目标标定 / 火力增益",
		"recon":"侦察 / 探测", "air_transport":"空运步兵", "transport":"装甲运兵",
		"naval_transport":"海上运兵", "naval_hovercraft":"登陆运输",
		"naval_carrier":"舰载机 / 远程打击", "naval_submarine":"潜航 / 反舰",
		"naval_support":"远程炮火支援", "naval_signature":"重型海战 / 岸轰",
		"naval_frigate":"基础护航 / 反舰", "naval_aa":"舰队防空 / 空域掩护",
		"creator_hand":"范围毁伤 / 攻坚", "armored_train":"轨道重炮 / 火力支援",
		"zeppelin":"轰炸 / 机枪防空", "disruptor":"EMP / 装甲瘫痪", "pulse":"电流 / 范围压制",
		"rifle":"反步兵", "gunner":"反步兵 / 持续压制", "marksman":"远程反步兵",
		"anti":"反坦克", "aa_infantry":"防空", "storm":"电流 / 反装甲",
		"demolition":"爆破 / 攻坚", "grenadier":"反步兵 / 范围压制", "mortar":"间接炮火支援",
		"scout":"侦察 / 反步兵", "tank":"反坦克 / 正面交战", "heavy_tank":"重装突破 / 反坦克",
		"artillery":"远程炮火支援", "advanced":"重型反装甲 / 攻坚", "assault":"近程攻坚 / 范围压制",
		"aa":"防空", "fighter":"空中拦截", "attacker":"对地 / 反坦克", "bomber":"轰炸 / 范围打击",
		"helicopter":"空中支援 / 对地打击", "naval_amphibious":"两栖突击 / 反装甲"
	}
	if utility.has(art): return str(utility[art])
	var weapon: Dictionary = rules.get("weapons", {}).get(str(info.get("weapon", "")), {})
	if weapon.is_empty(): return "支援"
	var targets: Array = weapon.get("targets", ["ground"])
	if targets == ["air"]: return "防空"
	if float(weapon.get("blast", 0.0)) >= 1.0: return "范围火力支援"
	return "反装甲" if float(weapon.get("penetration", 0.0)) > 50.0 else "反步兵"

static func summary(sim, entity: Dictionary) -> String:
	var info: Dictionary = sim.data_for(entity.spec)
	var weapon: Dictionary = sim.weapon_for(entity)
	var carrier: bool = bool(info.get("carrier", false))
	if carrier:
		var plane: Dictionary = sim.data_for(str(info.faction) + "_carrier_plane")
		weapon = sim.rules.weapons.get(str(plane.get("weapon", "")), {})
	var penetration: String = "—" if weapon.is_empty() else "%.0f" % float(weapon.get("penetration", 0.0))
	if carrier: penetration += "（舰载机）"
	var secondary: Dictionary = sim.weapon_for(entity, str(info.get("secondary_weapon", ""))) if info.has("secondary_weapon") else {}
	if not secondary.is_empty(): penetration += " / %.0f" % float(secondary.get("penetration", 0.0))
	return "定位：%s\n护甲 %.0f · 穿甲 %s" % [role(sim.rules, info), sim.armor_for(entity), penetration]
