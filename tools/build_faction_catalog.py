#!/usr/bin/env python3
"""Build the first-release roster from the v4 setting, preserving save IDs.

Only new entries and editorial fields are generated; established economy and
ground combat values remain intact. New values are an initial playtest baseline.
"""
import json
from pathlib import Path
from faction_balance import apply_balance
from naval_catalog import apply as apply_naval
from creator_hand_catalog import apply as apply_creator_hand

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "data/rules.json"


def animations(faction, art, unit=True):
    states = ["idle", "move", "attack", "hit", "death"] if unit else ["idle", "death"]
    return {s: f"res://assets/cards/{faction}_{art}_{s}.svg" for s in states}


def main():
    rules = json.loads(PATH.read_text())
    rules["version"] = 2
    rules["setting_source"] = "docs/派系设定/paper_front_world_setting_four_factions.md · v4"
    rules["player_colors"] = ["e7ad42", "41c7c6"]
    rules.setdefault("factions", {}).update({
        "kestrel": {"name": "正典军团", "mark": "wing", "color": "2865a5", "motto": "按图建造，按令前进。", "description": "均衡协同、工程保障与机动支援。", "legacy_id": "kestrel"},
        "rivet": {"name": "重锤军团", "mark": "hammer", "color": "bb4034", "motto": "让胜利作证。", "description": "厚重推进、炮火压制与强行突破。", "legacy_id": "rivet"},
    })
    # ID, short name, formal model, role description, select/move/attack/ready.
    texts = [
        ("kestrel_rifle", "步枪兵", "合格步兵", "可靠的基础步兵，支援工程与装甲；适合对付步兵，避开坦克与范围炮火。", "检定合格，等待命令。", "按令前进，保持队形。", "目标已确认，开始处置。", "合格步兵报到。"),
        ("kestrel_anti", "穿甲兵", "穿甲作业组", "远程反装甲步兵；以慢速穿甲弹打击车辆，单独面对大量步兵时脆弱。", "穿甲作业组就位。", "携装转移，保护侧翼。", "装甲参数已核实。", "穿甲作业组通过检验。"),
        ("kestrel_engineer", "工兵", "工程勤务兵", "抵达后立即修满友方建筑、占领敌方建筑（含防御塔，排除围墙和拒马）；可搭建、修建和接手分基地脚手架，并维修桥梁与友方地面单位。", "检验通过，可以承重。", "工程勤务组前往现场。", "请提供作业掩护。", "工具校准完毕。"),
        ("kestrel_harvester", "矿车", "军需采集车", "采集辉晶并送回精炼厂；运输效率较高，必须保护矿运路线。", "军需采集车待命。", "运输路线已经核准。", "请求护送矿运。", "采集车验收完成。"),
        ("kestrel_tank", "答案坦克", "标准答案式主战坦克", "均衡主战装甲，独立炮塔可在移动中射击；通过转场和工程维修对抗重型坦克。", "标准答案已就位，等待提出问题。", "按核准路线转场。", "正在提交标准答案。", "标准答案通过验收。"),
        ("kestrel_demolition", "爆破兵", "定点拆除作业组", "研究所解锁的近程范围步兵，清除密集步兵和障碍；无法攻击空军。", "拆除范围已核定。", "转移爆破器材。", "安全界限已划定。", "拆除作业组报到。"),
        ("kestrel_scout", "巡逻车", "巡察式装甲车", "高速侦察与轻型反步兵支援；装甲薄，避免与主战坦克正面对射；可搭载1名普通步兵。", "巡察路线等待批准。", "巡察车前出。", "发现偏差，立即报告。", "巡察车准备完毕。"),
        ("kestrel_artillery", "校正炮", "稍作更正式自行炮", "远程范围火力，移动时停止射击；适合支援和拆除阵地，近战与空袭是主要威胁。", "已收到坐标。开始修正。", "校正炮转移阵位。", "准许修正目标。", "校正炮校准完成。"),
        ("kestrel_aa", "护空车", "护空式防空车", "机动防空导弹平台，只能攻击空中目标；随队掩护，不能代替地面坦克。", "获准天空由我们维护。", "护空车跟随主队。", "空中目标偏离许可。", "护空系统上线。"),
        ("kestrel_fighter", "航向战机", "正确航向式截击机", "高速制空截击机，只攻击空军；八发弹药耗尽后自动返航，机场补给受电力影响。", "正确航向，等待许可。", "航向已核准。", "截击许可已确认。", "航向战机准备升空。"),
        ("kestrel_attacker", "批准攻击机", "正式批准式对地攻击机", "对地精确支援，擅长打击装甲；四次出击弹药，无法还击截击机，需要护航。", "正式批准，支援待命。", "进入获准航线。", "处置权限已经确认。", "攻击机通过适航检定。"),
        ("kestrel_advanced", "校对炮", "最终校对电磁炮", "指挥中心与研究所解锁的重型电磁平台；长射程穿甲，无对空能力，造价高且移动缓慢。", "最终校对，等待原稿。", "校对平台转移。", "执行最终校对。", "电磁导轨校准完成。"),
        ("rivet_rifle", "突击兵", "不容置疑式突击兵", "耐用基础步兵，伴随重装推进并保护侧翼；不适合单独迎击装甲。", "突击兵听候号令。", "推进命令有效。", "压制抵抗目标。", "突击编制完成。"),
        ("rivet_anti", "破甲兵", "破甲作业组", "低成本反装甲步兵，保护重坦免遭侧袭；装填慢，需突击兵掩护。", "破甲作业组待命。", "跟随装甲前进。", "击穿目标防护。", "破甲器材验收完成。"),
        ("rivet_engineer", "工兵", "军工勤务兵", "抵达后立即修满友方建筑、占领敌方建筑（含防御塔，排除围墙和拒马）；可搭建、修建和接手分基地脚手架，并维修桥梁与友方地面单位。", "军工勤务，检查完毕。", "作业命令有效。", "申请装甲掩护。", "军工勤务兵报到。"),
        ("rivet_harvester", "矿车", "重载采集车", "厚重矿运车，按统一规则采集辉晶；耐久较高，但转场较慢。", "信仰坚定。货舱已备。", "重载运输开始。", "矿运请求掩护。", "重载采集车交付。"),
        ("rivet_tank", "锤头坦克", "无可辩驳式重型坦克", "高耐久主力突破载具，独立炮塔可移动开火；成本和转场速度限制持续推进。", "重型装甲等待号令。", "推进命令有效。", "以火力确认结果。", "锤头坦克验收完毕。"),
        ("rivet_assault", "理由炮", "充分理由式攻城炮", "厚装甲范围火力，针对建筑与密集阵地；需要防空保护，转场缓慢。", "理由已备齐，等待提交。", "理由炮进入阵位。", "向目标提交充分理由。", "攻城理由准备完成。"),
        ("rivet_scout", "侦察车", "前导侦察车", "为装甲集团探路的轻型支援车辆；擅长侦察和反步兵，无法承受主战火力；可搭载1名普通步兵。", "前导侦察等待号令。", "前导车确认道路。", "目标位置已经呈报。", "前导侦察车出厂。"),
        ("rivet_aa", "拒飞车", "拒绝通行式防空车", "厚重防空导弹平台，只攻击空军；覆盖推进集团，面对地面兵力需队友保护。", "本空域拒绝通行。", "拒飞车随队推进。", "撤销目标通行资格。", "拒飞平台准备完成。"),
        ("rivet_fighter", "拦截战机", "终止通行式截击机", "耐久制空战机，只攻击空军；八发弹药后自动返航，机场被毁需转降其他机场。", "终止通行，等待命令。", "拦截航线确认。", "目标通行到此结束。", "拦截战机交付。"),
        ("rivet_bomber", "重申轰炸机", "再说一遍式重轰炸机", "慢速对地范围轰炸机，擅长攻坚与集群打击；两轮投弹后返航，怕截击与防空。", "目标尚未理解。申请再次说明。", "重申航线已确认。", "向目标再次说明。", "重轰炸机准备升空。"),
        ("rivet_advanced", "终审炮", "到此为止式重型助推炮", "指挥中心与研究所解锁的顶级攻城平台；射程长、建筑伤害高，成本高且需侧翼保护。", "终审材料已经备齐。", "终审平台进入阵位。", "争议到此为止。", "重型助推炮验收完成。"),
    ]
    def add_unit(faction, art, cost, hp, speed, duration, producer="factory", requires=None, turret=False, air=False, ammo=0, rearm=0):
        uid = f"{faction}_{art}"
        spec = dict(name=art, faction=faction, cost=cost, hp=hp, speed=speed, build_time=duration,
                    radius=.65 if air or art == "scout" else .85, turn_speed=180 if air else 110,
                    producer=producer, requires=requires or [], weapon=uid, crush=False,
                    crushable=False, art=art, domain="air" if air else "ground", armor_class="armored",
                    animations=animations(faction, art), has_turret=turret, fire_while_moving=turret)
        if turret: spec["turret_turn_speed"] = 180
        if air: spec.update(flight_height=5 if art == "bomber" else 4, ammo_capacity=ammo, rearm_time=rearm)
        rules["units"].setdefault(uid, spec)

    def weapon(uid, damage, interval, reach, blast=0, speed=24, targets=None, multipliers=None):
        rules["weapons"].setdefault(uid, dict(damage=damage, interval=interval, range=reach,
            kind="shell" if speed else "instant", blast=blast, speed=speed,
            targets=targets or ["ground"], multipliers=multipliers or {}))

    for faction in ["kestrel", "rivet"]:
        heavy = faction == "rivet"
        add_unit(faction, "scout", 360 if heavy else 300, 240 if heavy else 180, 4.6 if heavy else 5.6, 9, turret=True)
        weapon(f"{faction}_scout", 15 if heavy else 12, .55, 7, speed=0, multipliers={"infantry": 1.6, "armored": .35, "building": .4})
        add_unit(faction, "aa", 720 if heavy else 600, 420 if heavy else 320, 2.8 if heavy else 3.6, 15, turret=True)
        weapon(f"{faction}_aa", 72 if heavy else 58, 1.5 if heavy else 1.2, 13, speed=32, targets=["air"])
        air_req = [f"{faction}_command"]
        add_unit(faction, "fighter", 1100 if heavy else 950, 400 if heavy else 300, 8 if heavy else 9.5, 22,
                 "airfield", air_req, air=True, ammo=8, rearm=6)
        weapon(f"{faction}_fighter", 85 if heavy else 75, .9 if heavy else .8, 10, speed=38, targets=["air"])
        add_unit(faction, "advanced", 2300 if heavy else 2000, 950 if heavy else 620, 1.6 if heavy else 2.1, 36,
                 requires=[f"{faction}_tech", f"{faction}_command"], turret=True)
        # Heavy guns must deploy before firing; tanks retain firing on the move.
        rules["units"][f"{faction}_advanced"]["fire_while_moving"] = False
        weapon(f"{faction}_advanced", 210 if heavy else 180, 4.8 if heavy else 4.2, 18 if heavy else 16,
               1.5 if heavy else .4, 30, multipliers={"building": 1.7 if heavy else 1.2, "armored": 1.15 if heavy else 1.5, "infantry": .65})
    add_unit("kestrel", "artillery", 1050, 360, 2.6, 22, requires=["kestrel_tech"], turret=True)
    rules["units"]["kestrel_artillery"]["fire_while_moving"] = False
    weapon("kestrel_artillery", 95, 3.4, 15, 1.7, 16)
    add_unit("kestrel", "attacker", 1250, 340, 7.5, 26, "airfield", ["kestrel_command"], air=True, ammo=4, rearm=8)
    weapon("kestrel_attacker", 110, 1.8, 8, .6, 26, multipliers={"armored": 1.4, "infantry": .65})
    add_unit("rivet", "bomber", 1700, 560, 5.8, 32, "airfield", ["rivet_command", "rivet_tech"], air=True, ammo=2, rearm=10)
    weapon("rivet_bomber", 160, 3, 7, 2.2, 14, multipliers={"building": 1.4, "armored": .85})
    for uid, name, formal, description, select, move, attack, ready in texts:
        spec = rules["units"][uid]
        spec.update(name=name, formal_name=formal, description=description,
                    domain=spec.get("domain", "ground"), armor_class="infantry" if spec["crushable"] else "armored",
                    voices={"select": [select], "move": [move], "attack": [attack], "ready": [ready]})
        if spec["domain"] == "air":
            spec["voices"]["return"] = ["弹药耗尽，申请返回补给。" if spec["faction"] == "kestrel" else "返回机场，准备再次出动。"]
        if spec["art"] == "scout": spec["transport_capacity"] = 1
        if spec["art"] == "engineer": spec.update(repair_rate=10 if spec["faction"] == "kestrel" else 8, repair_radius=1.8)
        if spec["art"] == "harvester": spec["description"] = "从无限水晶柱采矿并向精炼厂交付；每柱同一时刻只有一辆矿车开采，敌我双方共用采矿位。"
    for spec in rules["weapons"].values(): spec.setdefault("targets", ["ground"])
    building_text = {
        "hq": ("原图总部", "压印总部", "每个势力一场游戏最多拥有一个总部，不能建造额外总部；总部和前线分基地共同维持基地存续。"),
        "power": ("标准发电站", "重型发电站", "供应电力；低电会拖慢建造、生产与航空补给，停用防御设施。"),
        "refinery": ("辉晶精炼厂", "辉晶压炼厂", "处理矿车运来的辉晶；建成附带一辆矿车，并扩展基地建设范围。"),
        "barracks": ("正典兵营", "重锤兵营", "训练基础步兵、反装甲兵与工兵；使用独立生产队列。"),
        "factory": ("拱架装配厂", "横向冲压厂", "统一生产普通与重型载具；研究所解锁高级火炮。"),
        "tower": ("连射守备塔", "炮击守备塔", "通电后自动攻击地面目标；不能替代防空单位。"),
        "tech": ("开放校准所", "压力试验所", "解锁阵营火炮与试验装备；与指挥中心共同解锁顶级火炮。"),
        "wall": ("防御围墙", "防御围墙", "每格独立计费，阻挡所有地面单位；飞机可越过。"),
        "barricade": ("反坦克拒马", "反坦克拒马", "阻挡车辆，步兵缓慢穿越；飞机不受影响。"),
        "outpost": ("前线图台", "前线压梁台", "工程兵选址并抵达后搭建低生命脚手架；现场施工逐步付款，受伤先维修、工兵阵亡后可接手或拆除，完工后授权前线建设。"),
        "repair": ("工程维修站", "夹臂检修站", "通电后付费修复范围内受损地面载具；露天检修平台，需前线保护。"),
        "command": ("战术审定台", "号令广播塔", "扩大友军自动索敌范围，解锁航空与顶级试验装备；不提供任意神力。"),
        "airfield": ("航向航空站", "重载航空站", "生产、接收与补给最多四架所属飞机；失去机场后飞机寻找备用机场。"),
    }
    for faction in ["kestrel", "rivet"]:
        heavy = faction == "rivet"
        for art, cost, hp, duration, power, size, requires, expands in [
            ("outpost", 1100 if heavy else 900, 1700 if heavy else 1350, 60, -20, 3, [f"{faction}_power"], True),
            ("repair", 850 if heavy else 700, 1400 if heavy else 1100, 20, -45, 3, [f"{faction}_factory"], False),
            ("command", 950 if heavy else 800, 1200 if heavy else 950, 22, -40, 3, [f"{faction}_factory"], False),
            ("airfield", 1500 if heavy else 1300, 2000 if heavy else 1650, 30, -90, 5, [f"{faction}_factory", f"{faction}_command"], False),
        ]:
            bid = f"{faction}_{art}"
            rules["buildings"].setdefault(bid, dict(name=art, faction=faction, cost=cost, hp=hp, build_time=duration,
                power=power, size=size, requires=requires, role=art, expands=expands, weapon="", art=art,
                animations=animations(faction, art, False)))
        rules["buildings"][f"{faction}_repair"].update(repair_radius=6, repair_rate=14 if heavy else 18)
        rules["buildings"][f"{faction}_command"]["vision_bonus"] = 3
        rules["buildings"][f"{faction}_airfield"]["aircraft_capacity"] = 4
    for bid, spec in rules["buildings"].items():
        if spec["faction"] not in ("kestrel", "rivet"):
            continue
        if spec["art"] not in building_text:
            continue  # Additional catalogs own their building names and text.
        canonical, hammer, description = building_text[spec["art"]]
        spec.update(name=hammer if spec["faction"] == "rivet" else canonical, formal_name=hammer if spec["faction"] == "rivet" else canonical, description=description)
    apply_balance(rules)
    apply_naval(rules)
    apply_creator_hand(rules)
    PATH.write_text(json.dumps(rules, ensure_ascii=False, indent=2) + "\n")
    print(f"Catalog: {len(rules['units'])} units, {len(rules['buildings'])} buildings, {len(rules['weapons'])} weapons")


if __name__ == "__main__":
    main()
