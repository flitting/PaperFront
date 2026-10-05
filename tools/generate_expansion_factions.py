#!/usr/bin/env python3
"""Author the independent Iron Nail / Skywing expansion and original paper cuts.

This generator writes only its own faction_expansion.json, faction_expansion_contours.json,
iron_* / sky_* infantry SVGs, and expansion_factions.md. It does not merge or
rewrite the existing rules, contours, models, engine code, or audio assets.
"""
from copy import deepcopy
import json
import random
from pathlib import Path

from shapely.geometry import Polygon
from shapely.ops import unary_union
from faction_balance import apply_balance

ROOT = Path(__file__).resolve().parents[1]
CARDS = ROOT / "assets" / "cards"
STATES = ("idle", "move", "attack", "hit", "death")
PAPER, INK, SKIN, PLAYER = "#eadbc0", "#40382f", "#d4b48b", "#e7ad42"
PALETTES = {
    "iron": {"base": "#bb963e", "dark": "#57564a", "cloth": "#999785", "trim": "#d2b969"},
    "sky": {"base": "#e5dfd0", "dark": "#67578b", "cloth": "#9da2aa", "trim": "#a293bd"},
}


def poly(points, fill, width=4, stroke=INK):
    return '<polygon points="{}" fill="{}" stroke="{}" stroke-width="{}" stroke-linejoin="round"/>'.format(
        " ".join(f"{x:.3f},{y:.3f}" for x, y in points), fill, stroke, width)


def line(d, color=INK, width=4):
    return f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round"/>'


def rect(x, y, w, h, fill, width=4):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="1" fill="{fill}" stroke="{INK}" stroke-width="{width}"/>'


def emblem(faction, x, y, color=PLAYER):
    if faction == "iron":
        return (poly([(x-11,y-10),(x+11,y-10),(x+7,y-4),(x+3,y-4),(x+3,y+12),(x,y+17),(x-3,y+12),(x-3,y-4),(x-7,y-4)], color, 2)
                + line(f"M{x-15} {y+7} Q{x} {y+24} {x+15} {y+7}", PAPER, 3))
    return poly([(x,y-15),(x+3,y-3),(x+20,y-9),(x+13,y+1),(x+3,y+6),(x,y+16),(x-3,y+6),(x-13,y+1),(x-20,y-9),(x-3,y-3)], color, 2)


def shifted(points, dx=0, dy=0):
    return [(x+dx, y+dy) for x, y in points]


def write_card(name, physical_parts, paint, identification, contours):
    # The physical union includes equipment. The stroke and contour use the same
    # cut, and ownership paint is separately authored in UV-aligned coordinates.
    physical = unary_union([Polygon(points).buffer(2.2, join_style=2) for points in physical_parts])
    silhouette = list(physical.exterior.coords)[:-1]
    border = physical.buffer(4.5, join_style=2).simplify(.2, preserve_topology=True)
    contour = [[round(x, 4), round(y, 4)] for x, y in list(border.exterior.coords)[:-1]]
    cut = '<defs><clipPath id="cut">' + poly(silhouette, "#ffffff", 0, "none") + '</clipPath></defs>'
    rng = random.Random(name)
    grain = ''.join(line(f'M{rng.randrange(40,350)} {rng.randrange(35,289)} l{rng.randrange(3,9)} -1', "#806c50", .7) for _ in range(46))
    cut_edge = line('M'+' L'.join(f'{x:.3f} {y:.3f}' for x,y in silhouette)+' Z', INK, 4)
    contents = ''.join(paint) + '<g id="player-identification">' + ''.join(identification) + '</g>'
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="384" height="320" viewBox="0 0 384 320">'
           f'{cut}{poly(silhouette, PAPER, 8)}<g clip-path="url(#cut)">{contents}<g opacity=".16">{grain}</g></g>{cut_edge}</svg>')
    (CARDS / (name + ".svg")).write_text(svg, encoding="utf-8")
    mask_parts = ''.join(identification).replace(PLAYER, "#ffffff").replace(INK, "#000000").replace(PAPER, "#ffffff")
    mask = (f'<svg xmlns="http://www.w3.org/2000/svg" width="384" height="320" viewBox="0 0 384 320">'
            f'{cut}<g clip-path="url(#cut)">{mask_parts}</g></svg>')
    (CARDS / (name + "_identity.svg")).write_text(mask, encoding="utf-8")
    contours[name] = {"width":384, "height":320, "outline":contour}


def infantry(faction, role, state, contours):
    p = PALETTES[faction]
    iron = faction == "iron"
    if state == "death":
        coat = ([(47,246),(85,229),(141,235),(188,255),(246,242),(270,258),(236,280),(175,275),(139,265),(84,276),(48,263)] if iron else
                [(58,250),(112,231),(155,237),(196,259),(246,242),(274,257),(241,277),(192,271),(152,281),(101,271),(64,269)])
        head = [(245,238),(256,227),(279,230),(295,250),(286,265),(260,269),(244,257)]
        helmet = ([(246,238),(250,222),(279,223),(294,240),(291,250),(250,247)] if iron else
                  [(247,238),(260,218),(281,228),(299,247),(290,253),(251,247)])
        tool = ({
            "rifle":[(103,255),(130,250),(182,252),(244,249),(250,255),(242,263),(177,267),(136,260),(112,266)],
            "anti":[(110,249),(135,241),(224,246),(243,253),(239,267),(128,267),(109,260)],
            "engineer":[(112,252),(166,250),(179,239),(196,239),(209,250),(203,261),(189,259),(180,270),(167,263),(112,265)],
        })[role]
        paint = [poly(coat,p["base"]),poly(head,SKIN),poly(helmet,p["dark"]),poly(tool,p["dark"]),
                 line("M89 246 L152 264 M170 249 L195 270",p["cloth"],7),
                 rect(76,239,29,20,p["trim"],3),line("M119 238 l12 18 M208 252 l18 4",PAPER,3)]
        if iron: paint += [line("M72 248 h22 M129 247 h18",p["dark"],3),rect(144,250,25,14,p["cloth"],2)]
        else: paint += [poly([(132,239),(152,238),(178,259),(163,269)],p["dark"],3)]
        identities = [poly([(78,238),(98,235),(119,247),(114,260),(91,257),(78,250)],PLAYER,3)]
        write_card(f"{faction}_{role}_{state}",[coat,head,helmet,tool],paint,identities,contours)
        return

    lean = 10 if state == "attack" else -10 if state == "hit" else 5 if state == "move" else 0
    if state == "move":
        legs = [(143,197),(181,202),(213,198),(221,234),(246,273),(261,279),(259,287),(229,286),(211,268),(182,227),(158,257),(128,279),(144,283),(140,289),(107,285),(106,277),(128,245)]
    elif state == "attack":
        legs = [(143,199),(179,199),(214,200),(229,244),(251,276),(266,280),(263,288),(229,288),(209,265),(185,224),(167,241),(153,270),(164,281),(157,287),(120,280),(118,271),(133,233)]
    elif state == "hit":
        legs = [(140,199),(184,203),(210,200),(214,239),(234,271),(242,281),(238,288),(204,286),(193,254),(178,226),(161,241),(151,274),(164,282),(160,288),(127,283),(121,275),(129,234)]
    else:
        legs = [(139,198),(182,201),(216,197),(218,239),(235,273),(249,279),(247,287),(211,287),(200,275),(186,232),(171,246),(160,273),(172,281),(167,287),(126,285),(120,278),(131,237)]

    if iron:
        torso = {"engineer":[(135,108),(158,107),(196,107),(221,119),(230,156),(215,174),(218,206),(140,211),(127,180),(110,154),(113,128)],
                 "rifle":[(120,106),(151,111),(194,107),(228,106),(243,128),(248,155),(226,183),(222,212),(132,212),(117,180),(104,152),(107,125)],
                 "anti":[(110,105),(149,111),(193,107),(225,103),(253,124),(256,158),(231,185),(228,212),(126,213),(112,184),(94,155),(98,123)]}[role]
        head = {"engineer":[(143,78),(148,58),(162,49),(193,49),(211,63),(214,79),(207,92),(203,105),(181,114),(159,103),(149,90)],
                "rifle":[(143,75),(144,52),(155,44),(199,46),(213,58),(218,76),(227,84),(219,94),(206,96),(202,110),(181,116),(155,104)],
                "anti":[(145,76),(146,54),(158,46),(196,46),(214,62),(217,78),(208,91),(201,107),(183,115),(157,105)]}[role]
        helmet = {"engineer":[(143,78),(146,57),(161,45),(196,45),(214,64),(214,77)],
                  "rifle":[(141,75),(142,52),(151,43),(201,45),(218,60),(218,78),(201,84),(145,82)],
                  "anti":[(143,74),(143,52),(155,42),(202,45),(219,62),(220,81),(147,84)]}[role]
        tool = {"engineer":[(216,187),(226,160),(247,118),(257,97),(248,83),(253,65),(272,56),(278,69),(266,76),(272,90),(287,89),(298,77),(310,89),(307,107),(282,119),(256,169),(239,190)],
                "rifle":[(178,150),(213,136),(241,131),(284,126),(326,128),(338,137),(335,151),(292,156),(263,158),(264,181),(246,185),(240,162),(198,175)],
                "anti":[(166,148),(181,114),(213,112),(218,103),(319,89),(340,100),(349,127),(340,145),(223,170),(179,176)]}[role]
        forearm = [(123,145),(140,140),(172,158),(211,145),(226,154),(221,169),(175,182),(149,177),(123,163)]
        if role == "engineer":forearm=[(195,146),(234,147),(245,157),(239,172),(202,179),(190,163)]
    else:
        torso = {"engineer":[(145,105),(168,111),(190,108),(215,120),(225,147),(208,167),(214,209),(145,210),(135,179),(111,175),(108,126),(129,123)],
                 "rifle":[(133,109),(155,97),(174,112),(195,108),(218,105),(232,132),(226,153),(211,183),(222,211),(143,212),(130,181),(117,154),(119,129)],
                 "anti":[(125,109),(146,103),(169,110),(191,106),(224,96),(240,122),(239,151),(216,178),(220,212),(139,212),(128,183),(115,155),(115,127)]}[role]
        head = {"engineer":[(147,77),(150,57),(164,49),(192,50),(209,61),(214,78),(207,92),(201,106),(179,112),(159,101)],
                "rifle":[(147,78),(149,56),(163,48),(193,48),(209,61),(217,77),(212,91),(204,105),(183,113),(158,102)],
                "anti":[(147,79),(151,58),(165,48),(192,49),(210,61),(218,79),(213,93),(199,107),(181,113),(159,103)]}[role]
        helmet = {"engineer":[(146,76),(149,56),(162,47),(194,47),(212,62),(217,79),(151,83)],
                  "rifle":[(144,78),(148,54),(162,46),(195,46),(214,61),(220,79),(213,85),(149,85)],
                  "anti":[(145,79),(150,55),(163,46),(195,47),(213,61),(219,79),(215,85),(149,86)]}[role]
        tool = {"engineer":[(205,174),(230,158),(230,108),(290,108),(297,179),(238,186),(225,179)],
                "rifle":[(177,151),(210,139),(263,139),(269,142),(300,140),(319,145),(319,153),(269,156),(260,165),(242,164),(241,184),(224,181),(220,162),(186,173)],
                "anti":[(165,150),(179,114),(231,110),(233,88),(268,78),(286,82),(289,111),(327,111),(337,122),(337,145),(230,164),(189,178),(169,172)]}[role]
        forearm = [(125,145),(141,139),(169,157),(200,143),(216,148),(220,161),(178,180),(149,178),(126,161)]
        if role == "engineer":forearm=[(189,143),(222,145),(240,155),(234,171),(199,181),(188,164)]

    torso, head, helmet, forearm = [shifted(points, lean) for points in [torso,head,helmet,forearm]]
    neck = shifted([(160,96),(199,96),(207,125),(151,125)],lean)
    tool = shifted(tool,lean + (6 if state == "attack" else 0), -2 if state == "attack" else 0)
    paint = [poly(legs,p["cloth"]),poly(neck,SKIN),poly(torso,p["base"]),poly(head,SKIN),poly(helmet,p["dark"])]
    if iron:
        paint += [poly(shifted([(134,119),(202,120),(221,143),(210,185),(145,191),(128,166)],lean),p["dark"],3),
                  poly(shifted([(145,130),(190,128),(207,144),(199,176),(151,177)],lean),p["base"],3),
                  rect(144+lean,185,75,19,p["dark"],3),
                  poly(shifted([(112,123),(137,114),(150,135),(141,156),(117,152)],lean),p["cloth"],3),
                  line(f"M{154+lean} 136 l16 -1 M{149+lean} 160 l21 -1 M{170+lean} 188 v11",PAPER,3),
                  line(f"M{160+lean} 56 h31 M{157+lean} 67 h38",p["base"],5)]
        for x,y in [(142,130),(197,131),(144,173),(197,171)]:
            paint += [rect(x+lean,y,6,3,PAPER,1)]
        if role=="engineer":paint += [rect(147+lean,79,49,14,p["dark"],3),rect(151+lean,82,17,8,"#88938a",1),rect(175+lean,82,17,8,"#88938a",1),rect(142+lean,146,25,29,p["trim"],3)]
        if role=="rifle":paint += [poly(shifted([(188,52),(207,58),(210,74),(195,78)],lean),p["trim"],2),line(f"M{199+lean} 60 v12",p["dark"],3)]
        if role=="anti":paint += [rect(102+lean,119,32,42,p["dark"],3),rect(106+lean,125,24,7,p["trim"],2),line(f"M{109+lean} 141 h16 M{116+lean} 119 v41",PAPER,3)]
    else:
        paint += [poly(shifted([(147,114),(164,122),(155,174),(164,199),(146,204),(131,170),(136,129)],lean),p["dark"],3),
                  poly(shifted([(192,113),(205,120),(175,190),(162,196),(156,183)],lean),p["trim"],3),
                  poly(shifted([(147,189),(207,188),(216,205),(146,206)],lean),p["dark"],3),
                  line(f"M{155+lean} 61 h37 M{159+lean} 76 h42",PAPER,3),
                  line(f"M{159+lean} 121 l15 12 M{194+lean} 140 l12 11 M{190+lean} 91 l11 -3",p["dark"],3)]
        if role=="engineer":paint += [rect(110+lean,128,31,43,p["cloth"],3),rect(116+lean,136,18,12,p["dark"],2),line(f"M{111+lean} 159 h28 M{115+lean} 128 v-7 h18 v7",PAPER,3)]
        if role=="rifle":paint += [poly(shifted([(125,115),(151,102),(158,115),(144,141),(121,135)],lean),p["dark"],3),poly(shifted([(215,111),(228,125),(223,145),(205,129)],lean),p["dark"],3)]
        if role=="anti":paint += [rect(130+lean,125,28,28,p["dark"],3),line(f"M{149+lean} 114 l-13 -17",p["dark"],5)]

    paint += [poly(tool,p["dark"]),poly(forearm,p["base"],3),
              poly(shifted([(207,148),(219,147),(228,154),(225,165),(211,170),(203,160)],lean),SKIN,3),
              line("M137 230 l-7 35 M207 235 l18 35",p["dark"],4)]
    if role=="rifle":
        paint += [line(f"M{272+lean} 145 l39 {-11 if iron else 3}",p["trim"],4),rect(246+lean,151,17,17,p["cloth"],3)]
        if not iron: paint += [rect(212+lean,143,43,13,p["cloth"],2),line(f"M{219+lean} 147 h29",PAPER,2)]
    if role=="anti":
        if iron:
            paint += [line(f"M{222+lean} 136 L{320+lean} 112",p["trim"],6),line(f"M{323+lean} 100 l9 16",PAPER,3)]
        else:
            paint += [poly(shifted([(237,93),(267,83),(281,87),(282,111),(238,115)],lean),PAPER,3),
                      line(f"M{253+lean} 90 l1 20 M{241+lean} 101 l33 -5",p["dark"],2),
                      rect(222+lean,121,104,25,p["base"],3),line(f"M{233+lean} 128 h74 M{326+lean} 124 v17",p["trim"],3)]
    if role=="engineer":
        if iron: paint += [line(f"M{234+lean} 160 L{263+lean} 113",p["trim"],4)]
        else:
            paint += [poly(shifted([(236,115),(285,115),(290,175),(242,180)],lean),PAPER,3),
                      line(f"M{244+lean} 122 l2 45 M{245+lean} 137 h34 M{247+lean} 156 h31",p["dark"],2),
                      line(f"M{252+lean} 127 l23 22 -7 20 M{259+lean} 119 v7 M{269+lean} 119 v5 M{280+lean} 119 v7",p["trim"],2)]
    paint += [emblem(faction,180+lean,159,PAPER)]
    identities = [poly(shifted([(155,55),(176,47),(193,54),(201,68),(182,74),(158,68)],lean),PLAYER,3),
                  poly(shifted([(127,131),(139,125),(150,139),(145,153),(131,151)],lean),PLAYER,3)]
    if state=="attack" and role in ("rifle","anti"):
        tip = (346+lean,128) if iron else (343+lean,129 if role=="anti" else 148)
        paint += [poly([(tip[0],tip[1]),(tip[0]+15,tip[1]-11),(tip[0]+12,tip[1]+1),(tip[0]+25,tip[1]+6),(tip[0]+10,tip[1]+12)],"#f1ca67",2)]
    if state=="hit":paint += [line(f"M{153+lean} 131 l24 16 -15 23 28 18",PAPER,4)]
    write_card(f"{faction}_{role}_{state}",[legs,torso,head,helmet,neck,tool,forearm],paint,identities,contours)


def voices(faction, name, role, air=False, armed=False):
    if faction=="iron":
        select = f"{name}检查完毕，等候调度。"
        move = "稳稳前进，连接都已检查。"
        attack = "阵线稳住，准备开火。"
        ready = f"{name}质量验收通过。"
    else:
        select = f"{name}现行版本，等待指令。"
        move = "进入新的工作坐标。"
        attack = "试验条件确认，开始执行。"
        ready = f"{name}获准投入编制。"
    if role=="engineer": attack="现场条件确认，准备施工。"
    if role=="harvester": attack="保持采集，保护货舱。"
    if role in ("repair_vehicle", "rig") and faction=="iron":
        select="这个交给我，保证能修好。"
        attack="修好还要加固，按标准检修。"
    if role=="recycler":
        select="拖救车到位，把战友带回来。"
        attack="保持靠近，先撤到安全位置。"
    if role=="designation":
        select="观测板展开，维持目标跟踪。"
        attack="标定完成，火控条件成立。"
    if role=="inspection": attack="手绘刻度核对，准备现场维修。"
    if role=="attacker" and faction=="sky": ready="现行最终版，准备升空。"
    result={"select":[select],"move":[move],"attack":[attack],"ready":[ready]}
    if air:
        result["return"]=["返回机场，接受维护。" if faction=="iron" and not armed else "返回机场，申请补给。" if faction=="iron" else "进入机场补给航线。"]
    return result


def build_expansion(source):
    data={"factions":{},"buildings":{},"units":{},"weapons":{}}
    data["factions"]={
        "iron":{"name":"铁钉同盟","mark":"nail","color":"bb963e","motto":"放心，不会散架的。","description":"像认真工匠一样可靠的工业军团；厚实结构、标准备件和野战保障支撑稳步推进，装备与战友都值得认真维护。","legacy_id":"iron"},
        "sky":{"name":"天翼教团","mark":"skywing","color":"67578b","motto":"想象即是现实。","description":"掌握先进技术的纸模军团；纸盒、粗纸筒与歪折板构成朴素外壳，通过目标标定、局部蓄能和航空机动取得战斗优势。","legacy_id":"sky"},
    }

    def prefer_own_portrait(entity_id, animations):
        portrait = CARDS / f"{entity_id}_portrait.png"
        if portrait.exists():
            animations["idle"] = f"res://assets/cards/{portrait.name}"
        return animations

    def building(faction, art, name, cost, hp, time, power, size, requires, expands=False, role=None, **extra):
        actual_role=role or art
        # Reserve enough cells for the complete illustrated building shells.
        # Walls remain a single-cell module because construction repeats them.
        footprints = {
            "iron": {"hq":5,"power":5,"refinery":5,"barracks":5,"factory":6,"repair":5,"command":5,"tech":5,"airfield":6,"recycling_yard":5,"outpost":4,"tower":3,"aa_tower":3,"anti_tower":3,"wall":1},
            "sky": {"hq":5,"power":4,"refinery":5,"barracks":4,"factory":6,"repair":4,"command":4,"tech":4,"airfield":6,"accumulator":4,"outpost":4,"tower":3,"aa_tower":3,"anti_tower":3,"wall":1},
        }
        size = footprints[faction][art]
        old_role="repair" if art=="recycling_yard" else "power" if art=="accumulator" else "tower" if art in ("aa_tower","anti_tower") else art
        old_faction="rivet" if faction=="iron" else "kestrel"
        fallback=source["buildings"][f"{old_faction}_{old_role}"]
        spec={"name":name,"formal_name":name,"faction":faction,"art":art,"cost":cost,"hp":hp,"build_time":time,"power":power,"size":size,
              "requires":[f"{faction}_{r}" for r in requires],"role":actual_role,"expands":expands,"weapon":"","animations":prefer_own_portrait(f"{faction}_{art}",deepcopy(fallback["animations"]))}
        spec.update(extra)
        data["buildings"][f"{faction}_{art}"]=spec

    # Shared technologies retain the existing production queues and finite
    # airfield slots. Distinct support / energy branches do not add new resources.
    for faction in ("iron","sky"):
        iron=faction=="iron"
        names=(["总工坊","锅炉发电站","筛选精炼厂","守备兵营","装配工厂","露天检修站","工务指挥台","耐久试验所","野战机场","前线工坊","机枪堡","护场防空台","守门炮座","铆接围墙"] if iron else
               ["展翼总部","励磁发电站","辉晶分离站","勤务兵营","试制工厂","校准维修台","航务指挥台","续稿研究所","展翼机场","前线翼站","哨戒枪座","截空炮台","聚焦炮座","折板围墙"])
        settings=(
            [(2400,3200,60,100,4),(475,1000,16,250,3),(1350,1850,26,-55,4),(425,1400,16,-20,3),(1200,2300,30,-90,4),(650,1250,20,-40,3),(750,1100,22,-35,3),(850,1400,26,-55,3),(1200,1850,32,-85,5),(850,1450,28,-20,3),(500,850,12,-30,2),(650,950,16,-45,2),(750,1100,18,-55,2),(60,800,3,0,1)] if iron else
            [(2550,2500,60,100,4),(575,850,17,300,3),(1550,1350,24,-65,4),(475,1000,14,-20,3),(1350,1850,27,-105,4),(775,950,19,-50,3),(900,900,20,-50,3),(1000,1100,25,-75,3),(1450,1500,28,-110,5),(950,1150,23,-25,3),(575,650,11,-40,2),(750,750,15,-65,2),(900,800,18,-80,2),(65,650,3,0,1)]
        )
        arts=("hq","power","refinery","barracks","factory","repair","command","tech","airfield","outpost","tower","aa_tower","anti_tower","wall")
        reqs=([],["hq"],["power"],["power"],["refinery","barracks"],["factory"],["factory"],["factory"],["factory","command"],["power"],["barracks"],["factory"],["factory","tech"],["hq"])
        descriptions={
            "hq":"调度与建设授权中心；总部和前线分基地共同维持基地存续，低调设备台或手绘星图板标明阵营职能。",
            "power":"供电设备与显露的能源构件；提供基地电力，低电会拖慢生产与航空补给。",
            "refinery":"分离、处理矿车运回的辉晶；建成赠送一辆矿车，并扩展建设范围。",
            "barracks":"训练本阵营基础步兵、反装甲兵和工兵；保留独立步兵生产队列。",
            "factory":"生产地面载具与勤务平台；研究设施解锁后期火炮和试验装备。",
            "repair":"开放检修平台，通电后付费修复范围内己方地面装甲；多个维修来源不叠加。",
            "command":"工务或航务调度设备，通电时扩大友军自动索敌范围，解锁航空；不提高武器射程。",
            "tech":"载荷试验架或纸板试验环组成技术设施；解锁高级平台，投入正常生产时间、资金与电力。",
            "airfield":"飞机生产、接收与补给设施；有限机位包含待造飞机，补给遵循共用机场规则。",
            "outpost":"工兵搭建的前线建设节点，完工后扩展基地授权与建设范围；仍遵守现有现场施工规则。",
            "tower":"通电后自动射击地面目标的近程守备设施；不具备防空能力。",
            "aa_tower":"独立旋转的防空炮座，通电后只攻击空中目标，保护机场与检修区。",
            "anti_tower":"独立旋转的反装甲炮座；擅长对地装甲射击，需要步兵与防空掩护。",
            "wall":"模块围墙与闸门构型，沿用地面阻挡与逐格计费；闸门开闭机制尚未接入。",
        }
        for art,name,numbers,requires in zip(arts,names,settings,reqs):
            kwargs={"description":descriptions[art]}
            if art=="repair":kwargs.update(repair_radius=6,repair_rate=24 if iron else 16)
            if art=="command":kwargs["vision_bonus"]=3 if iron else 4
            if art=="airfield":kwargs.update(aircraft_capacity=4 if iron else 6,aircraft_repair_rate=18 if iron else 12)
            if art in ("tower","aa_tower","anti_tower"):
                kwargs.update(weapon=f"{faction}_{art}",has_turret=True,turret_turn_speed=150 if iron else 210,fire_while_moving=False)
            building(faction,art,name,*numbers,requires,art in ("hq","refinery","barracks","factory","tech","outpost"),"tower" if art in ("aa_tower","anti_tower") else art,**kwargs)
        if iron:
            building("iron","recycling_yard","备件仓",825,1500,24,-35,4,["factory","tech"],role="repair",repair_radius=7,repair_rate=12,
                     description="标准构件架与分类工具仓，供应统一接口备件；通电后付费修复范围内友方地面载具，与其他维修来源取最高效率。")
        else:
            building("sky","accumulator","蓄能站",850,1000,25,350,3,["tech"],role="power",overcharge_radius=8,overcharge_window=5,overcharge_recharge=25,damage_bonus=.2,overcharge_cost=60,overcharge_power=80,
                     description="粗纸筒捆成电容组，下面连接低方盒；为基地供电，有电力余量与资金时自动在交战中开启短时局部增压，随后重新蓄能。")

    def weapon(faction, art, damage, interval, distance, blast=0, speed=0, targets=("ground",), multipliers=None):
        data["weapons"][f"{faction}_{art}"]={"damage":damage,"interval":interval,"range":distance,"kind":"shell" if speed else "instant","blast":blast,"speed":speed,
                                                  "targets":list(targets),"multipliers":multipliers or {}}

    def unit(faction, art, name, formal, cost, hp, speed, time, description, requires=(), armed=False, turret=False, moving=False, air=False, placeholder=None, **extra):
        producer="airfield" if air else "barracks" if art in ("rifle","anti","engineer") else "factory"
        infantry_role=producer=="barracks"
        old_faction="rivet" if faction=="iron" else "kestrel"
        old_art=placeholder or art
        if art in ("rifle","anti","engineer"):
            animations={state:f"res://assets/cards/{faction}_{art}_{state}.svg" for state in STATES}
        else:
            animations=deepcopy(source["units"][old_art if "_" in old_art and old_art.startswith(("kestrel_","rivet_")) else f"{old_faction}_{old_art}"]["animations"])
        animations=prefer_own_portrait(f"{faction}_{art}",animations)
        spec={"name":name,"formal_name":formal,"faction":faction,"art":art,"cost":cost,"hp":hp,"speed":speed,"build_time":time,
              "radius":.35 if infantry_role else .65 if air or art in ("scout","inspection","designation","disruptor") else .85,
              "turn_speed":360 if infantry_role else 180 if air else 100 if faction=="iron" else 140,
              "producer":producer,"requires":[f"{faction}_{r}" for r in requires],"weapon":f"{faction}_{art}" if armed else "",
              "crush":not air and art in ("tank","assault"),"crushable":infantry_role,"domain":"air" if air else "ground",
              "armor_class":"infantry" if infantry_role else "armored","has_turret":turret,"fire_while_moving":moving,
              "animations":animations,"description":description,"voices":voices(faction,name,art,air,armed)}
        if turret:spec["turret_turn_speed"]=145 if faction=="iron" else 200
        if air:spec.update(flight_height=4 if faction=="iron" else 4.5,ammo_capacity=1,rearm_time=7)
        spec.update(extra)
        data["units"][f"{faction}_{art}"]=spec

    unit("iron","engineer","工兵","工务工程勤务兵",165,85,2.3,7,"厚工具包、护目镜和普通工业防护服；负责建筑施工、基础修复与桥梁作业，统一备件便利现场维护。",repair_radius=1.8,repair_rate=12)
    unit("iron","rifle","护甲步兵","结实护甲式战斗步兵",90,110,2.4,5,"宽厚护胸、结实护肩与普通方沿头盔；以短盒体步枪稳定交战，依靠护具与战友配合保持阵线。",armed=True)
    unit("iron","anti","反甲兵","稳托反装甲兵",200,100,2.15,8,"粗短发射器、稳固肩托和大弹箱；从受掩护位置发射穿甲弹，宽肩护具保护普通士兵。",armed=True)
    unit("iron","harvester","矿车","加固军需采集车",625,600,2.6,15,"宽轮距、结实驾驶室与加固货斗；使用统一采矿容量和辉晶交付规则，可靠底盘承担日常矿运。")
    unit("iron","scout","巡检车","工务巡检式装甲车",275,235,4.8,9,"小型轮式底盘、明显防滚架和紧凑机枪座；快速巡检道路、护卫矿运与压制轻步兵。",armed=True,turret=True,moving=True)
    unit("iron","tank","磐石坦克","可靠保证式主战坦克",700,640,2.75,18,"短宽车体、宽履带和牢固炮塔座；结构耐久与维修保障适合稳步推进，主炮可在行进中射击。",armed=True,turret=True,moving=True)
    unit("iron","assault","护路支援车","护路近程支援车",1150,850,2.1,25,"短管支援炮、厚防护盾与低稳履带底盘；以近中程范围炮弹压制步兵，保障主力通行。",requires=("tech",),armed=True,turret=True,moving=True)
    unit("iron","aa","护队防空车","护队机动防空车",550,405,3.15,16,"宽底盘、高仰角炮架与稳固支腿；专用防空火力护卫矿车、维修车辆与推进中的装甲部队。",armed=True,turret=True,moving=True)
    unit("iron","rig","吊装工程车","稳架吊装工程车",575,400,2.4,14,"高位吊臂、加固支柱与履带底座；以短范围低速付费维修辅助吊装检修，需靠近受损友方地面载具。",placeholder="harvester",repair_radius=3,repair_rate=6)
    unit("iron","artillery","稳座榴弹炮","稳座自行榴弹炮",925,400,2.25,23,"大炮架、后部驻锄与厚实承重结构；停稳后提供远程曲射范围支援，需要近身与防空保护。",requires=("tech",),armed=True,turret=True,placeholder="kestrel_artillery")
    unit("iron","repair_vehicle","扳手维修车","保证能修式工程维修车",550,330,3.0,14,"折叠工作台、工具柜与短维修臂；右键受损友方地面载具实施野战维修，按恢复生命消耗现有资金。",placeholder="harvester",repair_radius=4.5,repair_rate=14)
    unit("iron","recycler","拖救车","稳拖战场救援车",625,450,2.5,17,"粗绞盘、拖臂和加固车尾；右键护送低生命友方地面载具，保持近距离时帮助其加速撤离并交给维修。",requires=("tech",),placeholder="harvester",rescue_radius=4,rescue_speed_bonus=.25)
    unit("iron","transport","护送装甲车","护送装甲人员输送车",475,440,3.45,13,"宽载员舱、尾门与朴素装甲；搭载4名普通步兵，以可靠底盘将战友送往前线或接回安全位置。",placeholder="scout",transport_capacity=4)
    unit("iron","fighter","守望战机","守望护航式截击机",1025,340,8.5,23,"厚实机身、坚固翼根与清楚的动力结构；八发对空弹药执行制空护航，耗尽后返回机场补给。",requires=("command",),armed=True,air=True,ammo_capacity=8,rearm_time=7)
    unit("iron","attacker","石隼攻击机","石隼对地攻击机",1100,390,6.8,28,"宽翼、明显挂载与加厚驾驶舱周边；四发范围对地弹支援稳步推进，机场提供弹药和维护。",requires=("command",),armed=True,air=True,placeholder="kestrel_attacker",ammo_capacity=4,rearm_time=9)
    unit("iron","air_transport","稳翼运输机","稳翼勤务运输机",1150,500,6.5,30,"方正货舱、大尾门与结实起落架；在地面停机状态装卸4名普通步兵，有限机场机位约束航空调度。",requires=("command",),air=True,placeholder="rivet_bomber",ammo_capacity=1,rearm_time=8,transport_capacity=4)
    unit("iron","advanced","定心炮","十分稳妥式电磁炮",1750,760,1.9,38,"成熟履带底盘、重型导轨与粗支撑架；停稳后发射后期电磁反重甲火力，长射击间隔要求掩护。",requires=("command","tech"),armed=True,turret=True)

    unit("sky","engineer","工兵","现行版工程勤务兵",175,70,3.0,6,"普通纸片士兵背着方工具盒，携带手绘测量板；负责工程施工、基础修理与桥梁作业。",repair_radius=1.8,repair_rate=9)
    unit("sky","rifle","勤务兵","新版勤务兵",105,80,3.0,5,"简单护甲和普通头盔，短盒体枪械连接清楚的枪管；灵活的基础战斗编制，避免装甲正面对射。",armed=True)
    unit("sky","anti","导引兵","现行导引作业兵",235,75,2.75,8,"肩扛方形发射盒，外接大折板瞄准片；朴素外壳提供先进导引功能，较远距离反甲需要步兵掩护。",armed=True)
    unit("sky","harvester","矿车","辉晶分离勤务采集车",725,440,3.25,14,"普通轮式纸盒卡车，驾驶室与货斗分明；真实轮组承担矿运，使用统一采矿容量和辉晶交付规则。")
    unit("sky","scout","测绘车","新界测绘车",340,170,6.1,9,"小方车竖起展开的纸板观测盘；轻巧轮廓适合高速侦察道路，车载轻机枪提供基础自卫。",armed=True,turret=True,moving=True)
    unit("sky","tank","试验坦克","按理必胜式试验坦克",925,450,3.9,20,"厚纸盒车体、两条履带盒、方炮塔与粗纸筒；少量手画设备线遮着先进电磁系统，可在移动中精确反甲。",armed=True,turret=True,moving=True)
    unit("sky","artillery","修订炮","局部修订式自行炮",1200,315,2.8,25,"履带底盘托住打开的长发射槽，粗折板驻锄承担支撑；停稳后提供远程范围火力。",requires=("tech",),armed=True,turret=True)
    unit("sky","aa","拦空车","现行拦空式防空车",700,290,4.0,17,"顶部打开的发射箱内排列少量粗短纸筒；先进对空导引火力保护机动地面部队。",armed=True,turret=True,moving=True)
    unit("sky","inspection","检验车","现场检验车",550,250,4.4,13,"方工具柜、折条检验臂与手绘刻度板；右键受损友方地面载具开展付费现场维修，需时间与安全位置。",placeholder="scout",repair_radius=4,repair_rate=9)
    unit("sky","designation","标定车","现场标定式勤务车",625,220,4.8,15,"两片大纸板夹成V形观测架，中间固定粗镜筒；在距离与视线内持续跟踪敌方载具，为友军提供目标伤害加成。",requires=("command",),placeholder="scout",designation_radius=12,designation_track_time=1.5,damage_bonus=.15)
    unit("sky","disruptor","断流车","局部断流式试验车",975,285,3.7,23,"短方车身前部的两根粗棒与横向连接板构成脉冲发射器；对地范围能量打击，命中装甲单位或建筑时短暂干扰其行动。",requires=("tech",),armed=True,turret=True,placeholder="scout")
    unit("sky","pulse","脉冲阵列车","暂定永恒脉冲阵列",2100,525,2.3,38,"大纸盒底盘托起厚折板阵列，展开后露出完整发射面；长间隔对地范围打击，蓄能窗口辅助集中火力。",requires=("tech","command"),armed=True,turret=True,placeholder="advanced")
    unit("sky","fighter","越界战机","超出范围式截击机",1125,275,10.7,23,"整张厚板机翼、短盒机身与纸筒发动机；少量手绘检修线之下是真实制空系统，八发对空弹药后返航补给。",requires=("command",),armed=True,air=True,ammo_capacity=8,rearm_time=5.5)
    unit("sky","attacker","终版攻击机","最新最终版攻击机",1450,320,8.4,27,"更宽机翼与粗大的机腹武器盒区别于战机；四发先进对地弹药集中反甲，受防空与出动周期约束。",requires=("command","tech"),armed=True,air=True,ammo_capacity=4,rearm_time=6.5)
    unit("sky","air_transport","翼桥运输机","翼桥勤务运输机",1300,390,8.0,29,"大方货舱、厚直翼与结实尾梁；在地面停机状态装卸4名普通步兵，用朴素纸模执行航空运输。",requires=("command",),air=True,placeholder="attacker",ammo_capacity=1,rearm_time=6,transport_capacity=4)
    unit("sky","recon","巡测机","现行巡测式侦察机",775,205,11.3,18,"小型十字折翼与短观测筒；极简纸模构成无武装高速航空平台，遵守正常机场机位与飞行调度。",requires=("command",),air=True,placeholder="fighter",ammo_capacity=1,rearm_time=5)

    weapon("iron","rifle",10,.8,5.2,multipliers={"infantry":1.15,"armored":.6,"building":.55})
    weapon("iron","anti",90,3.1,8,.3,17,multipliers={"infantry":.55,"armored":1.2,"building":.85})
    weapon("iron","scout",13,.65,6.8,multipliers={"infantry":1.5,"armored":.35,"building":.4})
    weapon("iron","tank",65,2.1,9,.8,18)
    weapon("iron","assault",78,1.7,6.5,2.1,12,multipliers={"infantry":1.5,"armored":.6,"building":.85})
    weapon("iron","aa",65,1.45,12.5,0,30,("air",))
    weapon("iron","artillery",100,3.8,15,1.8,15)
    weapon("iron","fighter",75,.95,10,0,34,("air",))
    weapon("iron","attacker",100,2.0,8,1.1,24,multipliers={"infantry":1.0,"armored":1.15,"building":1.15})
    weapon("iron","advanced",175,4.6,17,1.4,25,multipliers={"infantry":.7,"armored":1.2,"building":1.5})
    weapon("iron","tower",16,.5,11,multipliers={"infantry":1.25,"armored":.65,"building":.65})
    weapon("iron","aa_tower",75,1.5,14,0,32,("air",))
    weapon("iron","anti_tower",95,2.6,12,.45,22,multipliers={"infantry":.45,"armored":1.4,"building":1.0})
    weapon("sky","rifle",10,.65,5.8,multipliers={"infantry":1.1,"armored":.6,"building":.55})
    weapon("sky","anti",95,2.8,9,.25,22,multipliers={"infantry":.5,"armored":1.2,"building":.8})
    weapon("sky","scout",11,.5,7.5,multipliers={"infantry":1.55,"armored":.35,"building":.4})
    weapon("sky","tank",90,2.3,10,.35,30,multipliers={"infantry":.65,"armored":1.2,"building":1.0})
    weapon("sky","artillery",90,3.1,16,1.5,24)
    weapon("sky","aa",64,1.2,13.5,0,38,("air",))
    weapon("sky","disruptor",70,2.4,10,1.7,22,multipliers={"infantry":1.1,"armored":.9,"building":.7})
    weapon("sky","pulse",165,4.2,15,2.0,28,multipliers={"infantry":.8,"armored":1.3,"building":1.2})
    weapon("sky","fighter",80,.8,11,0,42,("air",))
    weapon("sky","attacker",120,1.7,8.8,.55,32,multipliers={"infantry":.6,"armored":1.45,"building":1.05})
    weapon("sky","tower",18,.55,12,multipliers={"infantry":1.2,"armored":.65,"building":.6})
    weapon("sky","aa_tower",65,1.15,15,0,40,("air",))
    weapon("sky","anti_tower",110,2.7,13,.25,34,multipliers={"infantry":.45,"armored":1.5,"building":1.1})
    apply_balance(data)
    return data


def write_document(data):
    lines=["# 铁钉同盟与天翼教团：单位与支援体系修订", "",
           "以本轮‘结实可靠的工业军团’与‘朴素纸模外壳、真正先进功能’的修订说明为设计依据。阵营 ID 保持 `iron`、`sky`，所有既有单位与建筑 ID 兼容；`rivet` 继续表示重锤军团。", "",
           "数据包含 2 个阵营、30 座建筑、33 种单位与 26 种武器。六种纸片步兵分别有 idle / move / attack / hit / death 五状态，配套 30 张 SVG、30 张玩家色遮罩与 30 条轮廓。", "",
           "## 阵营气质与材料", "",
           "**铁钉同盟**：造出来要经得起用，交出去就要负责。赭黄涂装、石墨结构、宽厚纸板、整齐连接片和标准护板表现可靠工艺。士兵采用普通防护服、头盔与护甲；删除强制服役、人体改造、亡者再造等旧意象。单位受到伤害降低 10%，脱战 6 秒后每秒恢复最大生命的 1.2%，以维修支援稳步推进；有效耐久介于正典与重锤之间。", "",
           "**天翼教团**：创造者想象超前，手工制作简单。象牙白底纸、靛紫刷痕和蓝灰部件配合少量大纸盒、粗纸筒、厚折板；粗简外壳下的导引、电磁与航空设备具有真实功能。切边、胶接与不完全整齐的分界可读，关键连接稳固，不使用光滑未来壳体、漂浮尖塔或满面发光纹。", "",
           "固定数据色为 `bb963e` 与 `67578b`；玩家色单独使用头盔和肩部识别片。两个阵营共用现有资金与辉晶经济，不增加备件资源或随机故障。", "",
           "## 纸片步兵", "",
           "铁钉工兵具有护目镜、厚工具包和长扳手；护甲步兵具有宽护胸、结实护肩和短枪；反甲兵具有普通头盔、稳固肩托、粗短发射器与大弹箱。天翼工兵背方工具盒并拿手绘测量板；勤务兵使用普通头盔与短盒体枪械；导引兵肩扛方形发射盒，连接一块明显的大折板瞄准片。每个状态使用对应实际切边，设备和身体保持同一纸片轮廓。", "",
           "## 维修与战场救援", "",
           "- 工兵负责建筑施工与基础修复；露天检修站、校准维修台和备件仓通电后修复范围内地面装甲。多个维修来源取最高速度，按实际恢复生命消耗现有资金，费用沿用 `economy.repair_cost`。",
           "- 扳手维修车的野战维修半径为 4.5、速度为 14 生命/秒；检验车为半径 4、9 生命/秒；吊装工程车为半径 3、6 生命/秒，作为辅助保障。右键受损友方地面载具后靠近开展作业，不代替工兵和机场。",
           "- 拖救车右键护送仍存活的友方地面载具；其生命不高于 60% 且移动时，4 格内提供 25% 撤离速度加成。救援采用近距离护送表现，不回收或复活残骸。",
           "- 野战机场与展翼机场为停机飞机提供付费维护，分别为 18 与 12 生命/秒；弹药补给、有限机位和出动周期继续约束航空。", "",
           "## 标定、蓄能与运输", "",
           "- 标定车在 12 格范围内选择敌方地面载具，保持视线与跟踪 1.5 秒后，使友军对该目标的伤害提高 15%；目标离开范围或视线后需要重新跟踪。",
           "- 蓄能站提供基地电力，并在交战时自动提供局部增压。需要 60 资金和 80 电力余量，8 格内友军获得 5 秒的 20% 伤害加成，随后等待 25 秒重新蓄能。",
           "- 护送装甲车搭载 4 名地面步兵（含工兵和反甲兵）。稳翼运输机与翼桥运输机同样配置 4 人容量，可在任意合法空地降落装卸；机场负责维修与弹药补给，按 B 可返航，后续移动命令起飞。", "",
           "## 文件与接入", "",
           "- `tools/generate_expansion_factions.py` 生成独立数据、纸片与本说明；`tools/merge_expansion_catalog.py` 将 `iron` / `sky` 条目与纸片轮廓合并到现有规则目录。",
           "- `data/faction_expansion.json` 保存四类数据；`data/faction_expansion_contours.json` 保存纸片切边。既有专属肖像在再生成与合并时优先保留。",
           "- `scripts/iron_models.gd` 与 `scripts/sky_models.gd` 保存单位和建筑模型构造；`tools/build_expansion_assets.gd` 生成专属图标与模型清单。游戏的生产、移动、战斗与资料页读取同一规则目录。", "",
           "## 实现边界", "",
           "加固组件与机动组件的可选改装尚未接入。断流车对命中的装甲单位施加 2 秒电磁干扰，对建筑施加 1 秒电磁干扰；步兵不受影响。脉冲阵列车继续使用对地范围打击。巡测机是无武装航空平台，没有独立侦察揭雾光环。围墙使用实体阻挡，闸门形态尚无独立开闭操作。语音为更新后的对白文字，继续沿用现有通用音效。", "",
           "`iron_rig` 保留为吊装工程车，承担低速辅助检修；`iron_recycler` 改为拖救车，`iron_recycling_yard` 改为备件仓。名称变化不改变存档和生产条目的稳定 ID。数值属于当前规则基线与机制初值，后续平衡须结合对战结果。", ""]
    for faction in ("iron","sky"):
        lines += ["## "+data["factions"][faction]["name"], "", "### 建筑（15）", "", "| ID 后缀 | 名称 | role | 造价 | 生命 | 电力 |", "|---|---|---|---:|---:|---:|"]
        for entity_id,spec in data["buildings"].items():
            if spec["faction"]==faction:lines.append(f'| {entity_id.removeprefix(faction+"_")} | {spec["name"]} | {spec["role"]} | {spec["cost"]} | {spec["hp"]} | {spec["power"]} |')
        lines += ["", "### 单位（"+str(sum(spec["faction"]==faction for spec in data["units"].values()))+"）", "", "| ID 后缀 | 名称 | 正式型号 | 生产 | 造价 | 生命 | 速度 |", "|---|---|---|---|---:|---:|---:|"]
        for entity_id,spec in data["units"].items():
            if spec["faction"]==faction:lines.append(f'| {entity_id.removeprefix(faction+"_")} | {spec["name"]} | {spec["formal_name"]} | {spec["producer"]} | {spec["cost"]} | {spec["hp"]} | {spec["speed"]} |')
        lines += [""]
    (ROOT / "docs" / "expansion_factions.md").write_text("\n".join(lines),encoding="utf-8")


def main():
    source=json.loads((ROOT / "data" / "rules.json").read_text(encoding="utf-8"))
    expansion=build_expansion(source)
    contours={}
    for faction in ("iron","sky"):
        for role in ("engineer","rifle","anti"):
            for state in STATES:infantry(faction,role,state,contours)
    (ROOT / "data" / "faction_expansion.json").write_text(json.dumps(expansion,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    (ROOT / "data" / "faction_expansion_contours.json").write_text(json.dumps(contours,separators=(",",":"))+"\n",encoding="utf-8")
    write_document(expansion)
    print("Generated iron/sky expansion: 30 buildings, 33 units, 26 weapons, 30 paper cards, 30 identity masks and 30 contours.")


if __name__=="__main__":
    main()
