#!/usr/bin/env python3
"""Original functional silhouette cards for the complete first-release catalog."""
import json
from pathlib import Path
from shapely.geometry import Polygon
from shapely.ops import unary_union
import generate_art as art

ROOT = Path(__file__).resolve().parents[1]


def faction_infantry_card(faction, role, state):
    """Two distinct cut-paper armies, with five poses and explicit ownership UVs."""
    heavy = faction == "rivet"
    base = "#bb4034" if heavy else "#2865a5"
    dark = "#633d32" if heavy else "#27445f"
    pale, skin, ink, player = "#e6d5af", "#d9b58a", "#40342b", "#e7ad42"
    p, r, l, c = art.poly, art.rect, art.path, art.circle
    if state == "death":
        silhouette = ([(22,269),(38,234),(93,229),(127,209),(169,220),(206,242),(259,218),(310,230),(348,266),(317,285),(242,291),(198,270),(148,287),(85,280)] if heavy else
                      [(36,264),(58,244),(102,232),(138,224),(189,243),(251,228),(294,239),(316,267),(290,281),(233,282),(194,266),(139,283),(85,275)])
        pieces = [p([(52,249),(129,230),(195,251),(264,237),(300,262),(237,275),(186,259),(120,269),(63,264)],base),
                  p([(247,238),(272,228),(294,241),(302,258),(272,264),(251,252)],skin),
                  p([(255,224),(293,223),(307,241),(304,252),(257,245)],dark),
                  l("M98 249 L147 257 M145 243 L179 263",stroke=pale,width=5)]
        if heavy:pieces += [r(58,231,55,31,dark),r(134,244,52,21,pale),l("M55 247 H110",stroke=base,width=10)]
        else:pieces += [l("M97 242 L177 267",stroke=pale,width=8)]
        pieces += [l("M143 267 H235",stroke=ink,width=8)]
        pieces += ['<g id="player-identification">'+p([(78,239),(98,235),(119,245),(110,257),(85,251)],player,width=3)+'</g>']
        silhouette = list(Polygon(silhouette).buffer(0).exterior.coords)[:-1]
        art.save(f"{faction}_{role}_{state}",silhouette,pieces,robust_outline=True)
        return
    lean = 11 if state == "attack" else -8 if state == "hit" else 5 if state == "move" else 0
    def shift(points, dx=lean, dy=0):return [(x+dx,y+dy) for x,y in points]
    moving = state == "move"
    if heavy:
        head = shift([(143,69),(143,54),(205,54),(216,68),(219,80),(211,86),(209,102),(192,111),(155,100),(146,87)])
        torso = shift([(126,106),(151,111),(188,108),(213,105),(247,125),(252,159),(234,180),(225,207),(137,207),(128,179),(108,165),(107,128)])
        legs = ([(221,202),(220,234),(249,271),(268,278),(267,285),(227,285),(219,279),(194,249),(181,223),(143,253),(126,274),(151,278),(151,285),(108,285),(102,278),(115,256),(140,214),(140,199)] if moving else
                [(224,199),(226,236),(241,273),(252,278),(252,285),(204,285),(199,277),(190,238),(181,220),(170,239),(155,273),(169,278),(169,285),(116,285),(110,278),(130,230),(137,199)])
    else:
        head = shift([(148,73),(154,54),(165,39),(188,43),(209,59),(216,72),(213,83),(208,88),(203,102),(184,111),(163,103),(151,91)])
        torso = shift([(148,110),(170,115),(192,111),(214,123),(222,151),(211,180),(223,210),(145,208),(137,180),(126,157),(129,130)])
        legs = ([(211,202),(218,239),(239,274),(257,278),(257,285),(224,285),(214,273),(188,239),(179,217),(152,258),(129,274),(145,278),(141,285),(105,282),(103,275),(134,231),(148,209),(150,200)] if moving else
                [(213,200),(212,234),(226,274),(242,278),(243,285),(209,285),(202,278),(192,240),(180,218),(166,247),(160,273),(179,279),(179,285),(140,285),(133,278),(139,238),(148,199)])
    if role == "rifle":
        tool = ([(200,137),(220,129),(251,124),(267,129),(321,130),(328,142),(315,155),(269,156),(269,185),(245,185),(240,158),(205,163)] if heavy else
                [(184,143),(214,133),(270,127),(323,116),(335,119),(335,126),(281,145),(247,151),(243,169),(230,173),(225,153),(191,164)])
    elif role == "anti":
        tool = ([(207,128),(220,111),(307,99),(330,111),(342,136),(331,153),(221,177),(209,164)] if heavy else
                [(180,144),(279,104),(328,93),(339,104),(336,125),(290,141),(195,177)])
    elif role == "engineer":
        tool = ([(220,175),(222,112),(245,84),(276,84),(286,104),(282,124),(265,134),(253,132),(251,178)] if heavy else
                [(213,176),(237,103),(250,84),(264,78),(273,90),(268,105),(280,112),(290,93),(300,105),(297,123),(278,134),(236,185)])
    else:
        tool = [(216,169),(233,130),(256,107),(281,107),(298,125),(299,151),(275,174),(244,184)]
    tool = shift(tool, lean + (7 if state == "attack" else 0))
    # Union physical head, coat, legs and equipment, instead of weaving tool
    # vertices into the coat edge. The hit/engineer poses must remain simple
    # triangulatable cuts, including their real paper border.
    neck = shift([(160,96),(202,96),(207,126),(152,126)])
    forearm = shift([(194,149),(236,143),(248,154),(235,169),(194,176)]) if role=="engineer" else shift([(128,148),(143,144),(173,161),(207,145),(217,157),(181,178),(153,179),(130,163)])
    hand = shift([(239,147),(249,150),(252,157),(244,165),(234,161)]) if role=="engineer" else shift([(198,147),(211,140),(224,147),(223,156),(211,164),(199,159)])
    outline = unary_union([Polygon(part).buffer(0).buffer(2.5,join_style=2) for part in [head,neck,torso,legs,tool,forearm,hand]])
    if outline.geom_type != 'Polygon': raise ValueError(f'{faction}/{role}/{state}: detached equipment')
    silhouette = list(outline.exterior.coords)[:-1]
    pieces = [p(legs,"#a89d81" if heavy else pale),p(torso,base),p(head,skin)]
    if heavy:
        pieces += [p(shift([(139,124),(223,124),(223,177),(213,196),(149,196),(137,177)]),dark),
                   p(shift([(151,136),(210,136),(213,166),(203,183),(155,182),(146,164)]),base),
                   p(shift([(112,121),(137,111),(150,131),(145,158),(115,153)]),dark),
                   p(shift([(218,112),(244,127),(245,152),(220,160),(211,136)]),pale),
                   r(130+lean,185,91,20,dark),l(f"M{147+lean} 146 H{211+lean} M{147+lean} 165 H{210+lean}",stroke=pale,width=4),
                   p(shift([(141,73),(141,56),(157,49),(203,49),(219,65),(217,79),(149,83)]),dark),
                   l(f"M{147+lean} 62 H{210+lean}",stroke=base,width=8)]
    else:
        pieces += [p(shift([(143,131),(152,119),(170,143),(171,184),(152,202),(138,176)]),dark),
                   p(shift([(186,116),(197,122),(164,194),(154,191)]),pale),
                   p(shift([(145,187),(212,188),(217,203),(148,204)]),dark),
                   p(shift([(148,73),(158,49),(166,39),(188,42),(209,59),(220,74),(211,82),(152,83)]),dark),
                   l(f"M{157+lean} 65 L{170+lean} 50 L{190+lean} 55 L{204+lean} 71",stroke=pale,width=6)]
    pieces += [p(tool,dark),l(f"M{184+lean} 90 l13 -2 M{193+lean} 100 l8 -2",width=3)]
    if role == "rifle":pieces += [l(f"M{275+lean} 141 H{316+lean}",stroke=pale,width=4),r(247+lean,158,18,18,pale,3)]
    elif role == "anti":pieces += [l(f"M{227+lean} 135 L{313+lean} 110",stroke=pale,width=6),l(f"M{321+lean} 106 l8 26",stroke=ink,width=7)]
    elif role == "engineer":pieces += [l(f"M{238+lean} 157 V121",stroke=pale,width=5),r(142+lean,150,30,32,"#a99068",3)]
    else:pieces += [r(244+lean,126,40,33,"#ad8958",3),l(f"M{251+lean} 131 v22 M{273+lean} 131 v22",stroke=dark,width=3)]
    # Forearms and hands face the functional tool; faction armor remains legible.
    pieces += [p(forearm,base),p(hand,skin,width=3)]
    if heavy:
        identities = [p(shift([(155,56),(197,56),(208,67),(197,73),(156,72)]),player,width=3),
                      p(shift([(116,124),(130,117),(142,133),(138,146),(120,143)]),player,width=3)]
    else:
        identities = [p(shift([(164,49),(177,46),(190,51),(201,63),(193,71),(169,66)]),player,width=3),
                      p(shift([(132,132),(146,122),(156,136),(150,152),(138,149)]),player,width=3)]
    pieces += ['<g id="player-identification">'+''.join(identities)+'</g>']
    if state == "attack" and role in ("rifle","anti"):
        pieces += [p([(330+lean,126),(351+lean,114),(347+lean,128),(370+lean,135),(350+lean,145),(362+lean,163),(332+lean,151)],"#f1ca67",width=3)]
    if state == "hit":pieces += [l(f"M{155+lean} 133 l22 20 -16 20 35 18",stroke=pale,width=5)]
    art.save(f"{faction}_{role}_{state}",silhouette,pieces,robust_outline=True)


def faction_vehicle_card(faction, role, state):
    """New faction silhouettes; do not recolor the retired demo vehicle art."""
    heavy = faction == "rivet"
    base = "#bb4034" if heavy else "#2865a5"
    pale, ink, player = "#e6d5af", "#40342b", "#e7ad42"
    p, r, l, c = art.poly, art.rect, art.path, art.circle
    if role == "harvester":
        silhouette = [(26,270),(26,146),(54,126),(217,126),(230,89),(295,89),(337,128),(354,198),(347,269)]
        pieces = [p([(35,155),(202,155),(216,232),(43,232)],base),r(53,166,130,49,ink),
                  p([(223,109),(286,109),(325,138),(333,232),(210,232)],base),r(229,119,56,38,"#759591"),
                  r(53,142,143,16,pale),r(239,97,50,14,player,3),r(282,188,36,22,player,3)]
        for x in ([62,142,247,321] if heavy else [66,169,292]):pieces += [c(x,247,25,ink),c(x,247,12,pale)]
        for x,y in [(74,164),(109,155),(147,167),(174,160)]:pieces += [p([(x-9,190),(x-13,y),(x+3,y-16),(x+16,y+8),(x+11,191)],"#7499a8",3)]
        if heavy:pieces += [p([(30,212),(212,212),(212,230),(30,230)],pale),r(326,154,13,60,ink),l("M53 164 V202 M181 164 V202",stroke=pale,width=7)]
        else:pieces += [l("M212 225 L228 160 M320 219 L309 163",stroke=pale,width=7),l("M76 213 H176",stroke=pale,width=4)]
    else:
        # Standard Answer has raised trapezoid shoulders and a precise turret.
        # Hammerhead is a low wedge with broad box cheeks and layered glacis.
        silhouette = ([(18,274),(16,211),(48,173),(126,167),(122,136),(143,105),(232,105),(250,137),(323,137),(340,149),(337,175),(269,175),(344,211),(360,247),(342,277)] if heavy else
                      [(25,274),(25,212),(57,179),(99,160),(113,109),(157,83),(218,96),(239,137),(334,141),(348,152),(339,164),(245,166),(280,176),(329,209),(342,249),(320,273)])
        pieces = [p([(32,205),(91,175),(282,175),(336,209),(322,237),(40,237)],base),r(27,235,309,32,ink)]
        for x in ([54,110,166,222,280,326] if heavy else [64,139,215,300]):pieces += [c(x,250,16,pale,3),c(x,250,6,ink,2)]
        if heavy:
            pieces += [p([(28,204),(137,187),(267,185),(330,203),(346,223),(42,223)],base),
                       p([(129,142),(140,115),(229,115),(247,143),(242,173),(127,173)],base),r(147,117,78,13,player,3),
                       r(241,144,78,24,pale),r(307,139,25,35,ink),r(98,182,37,30,pale),r(250,184,39,27,pale),
                       l("M41 205 H121 M254 204 H332 M51 218 H135 M268 217 H338",stroke=pale,width=6)]
            if role == "assault":pieces += [r(133,117,100,48,base),r(229,132,101,29,pale),r(314,126,24,41,ink),l("M63 188 H121",stroke=player,width=7)]
        else:
            pieces += [p([(72,198),(106,154),(120,175),(111,216)],pale),p([(275,178),(311,204),(301,218),(263,193)],pale),
                       p([(118,145),(135,111),(161,96),(210,108),(229,143),(215,174),(129,174)],base),
                       r(146,108,55,17,player,3),r(226,146,103,11,pale),r(325,143,15,17,ink),
                       r(137,177,44,17,player,3),l("M140 136 H206 M87 201 l12 -22 M289 208 l-15 -15",stroke=pale,width=5)]
        pieces += [art.emblem(faction,184,154,13,player)]
    if state == "hit":pieces += [l("M108 153 l29 25 -16 15 41 19",stroke=pale,width=7)]
    if state == "attack" and role != "harvester":pieces += [p([(335,143),(365,128),(358,146),(380,158),(354,163),(367,183),(335,172)],"#f1ca67",width=3)]
    if state == "death":pieces += [l("M194 116 l-30 30 41 19 -19 31 32 36",stroke=ink,width=12)]
    art.save(f"{faction}_{role}_{state}",silhouette,pieces)


def equipment_card(faction, role, state, building=False):
    red = faction == "rivet"
    base = "#bb4034" if red else "#2865a5"
    trim = "#41c7c6" if red else "#e7ad42"
    dark, pale = "#635044", "#e6d5af"
    p, r, l, c = art.poly, art.rect, art.path, art.circle
    pieces = []
    if role in ("fighter", "attacker", "bomber"):
        bomber = role == "bomber"
        silhouette = [(174,26),(197,26),(207,85),(228,112),(334,186),(332,211),(220,190),(207,253),(244,285),(242,298),(189,285),(137,298),(135,285),(172,253),(160,190),(48,211),(46,186),(150,112),(166,85)]
        pieces = [p([(178,36),(193,36),(208,170),(204,252),(185,278),(168,252),(164,170)],base),
                  p([(173,113),(60,189),(58,203),(166,179)],base),p([(203,113),(320,189),(320,203),(206,179)],base),
                  p([(177,70),(191,70),(198,114),(170,114)],"#759591"),r(97,173,43,18,trim,3),r(241,173,43,18,trim,3),
                  l("M185 124 V251 M63 190 L157 169 M219 170 L316 190",stroke=pale,width=4)]
        for x in ([144,222] if bomber else [161,209]): pieces += [r(x,183,18,51,dark,3),l(f"M{x+3} 224 h12",stroke=pale,width=4)]
        if role == "attacker": pieces += [r(118,199,18,39,pale,3),r(240,199,18,39,pale,3)]
        if bomber: pieces += [r(173,152,26,82,dark,4),l("M178 167 h16 M178 183 h16 M178 199 h16",stroke=pale,width=4)]
    elif not building:
        # Hull, independent weapon silhouette and clearly separate role equipment.
        silhouette = [(29,224),(49,180),(94,166),(116,132),(148,111),(211,111),(229,140),(295,147),(337,174),(350,223),(327,276),(57,276)]
        pieces = [p([(51,192),(105,171),(271,174),(328,195),(317,246),(65,246)],base),r(49,237,283,33,dark),
                  r(119,132,112,49,base),r(148,133,55,24,trim,3)]
        if role == "scout":
            pieces += [r(209,146,86,11,dark),r(91,182,58,31,"#759591",3)]
            for x in [80,169,283]: pieces += [c(x,248,24,dark),c(x,248,11,pale,3)]
        elif role == "aa":
            for x in [128,163,198]: pieces += [p([(x,141),(x+30,96),(x+43,106),(x+16,153)],pale),l(f"M{x+5} 137 l25 -33",stroke=base,width=5)]
            pieces += [l("M90 153 V98",width=5),c(90,91,20,base),l("M73 91 H107",stroke=pale,width=4)]
        elif role == "artillery": pieces += [p([(181,149),(296,70),(307,84),(198,170)],pale),l("M204 142 L299 81",stroke=dark,width=11)]
        elif role == "advanced":
            pieces += [r(207,129,139,19,pale),r(207,160,139,19,pale),r(214,148,125,10,dark)]
            for x in [205,228,251,274]: pieces += [c(x,154,20,base,4),l(f"M{x} 137 V173",stroke=pale,width=5)]
    else:
        silhouette = [(24,287),(24,242),(48,226),(48,77),(93,48),(293,48),(334,77),(334,226),(356,242),(356,287)]
        pieces = [r(28,247,324,33,dark),r(46,265,288,12,pale,3)]
        if role in ("hq", "outpost"):
            if red:
                pieces += [r(67,104,47,147,base),r(269,104,47,147,base),r(71,95,244,48,base),r(133,151,120,47,dark),art.emblem(faction,193,175,28,trim)]
            else:
                pieces += [p([(55,247),(83,146),(121,104),(269,104),(308,146),(334,247)],base),p([(102,237),(123,145),(266,145),(287,237)],pale),art.emblem(faction,195,171,28,trim)]
            pieces += [l("M190 104 V59",width=7),p([(198,63),(260,73),(253,99),(198,91)],trim)]
        elif role == "factory":
            if red:
                pieces += [r(53,146,272,80,dark),r(69,149,49,75,base),r(162,129,77,37,base),r(285,130,35,99,base)]
                for x in [133,161,189,217,245]: pieces += [c(x,231,11,pale,3)]
                pieces += [r(170,174,67,32,pale),l("M177 168 V102 H226 V168",stroke=base,width=17)]
            else:
                pieces += [p([(64,246),(64,127),(113,82),(270,82),(320,127),(320,246),(280,246),(280,146),(253,122),(131,122),(104,146),(104,246)],base),r(146,221,99,23,dark)]
            pieces += [r(132,92,116,19,trim,3)]
        elif role == "repair":
            pieces += [r(96,225,200,17,pale),r(124,183,138,38,dark)]
            if red:
                pieces += [l("M68 225 V147 H105 L125 188 M316 225 V147 H279 L261 188",stroke=base,width=25)]
            else:
                pieces += [r(67,99,31,139,base),r(290,99,31,139,base),r(68,97,252,27,base),l("M194 125 V183",stroke=dark,width=9),l("M194 184 q19 22 27 -5",stroke=dark,width=6)]
            pieces += [r(140,102,106,18,trim,3)]
        elif role == "command":
            if red: pieces += [r(171,72,35,174,base),l("M189 82 H268 M189 120 H258",stroke=pale,width=16),r(132,180,115,31,trim)]
            else: pieces += [p([(75,218),(118,176),(269,176),(312,218),(268,245),(119,245)],base),c(194,200,52,pale),l("M76 167 Q192 39 311 166",stroke=base,width=12),r(167,186,54,23,trim)]
        elif role == "airfield":
            pieces += [p([(55,237),(139,112),(228,112),(322,237)],dark),l("M183 135 V154 M184 175 V194 M185 213 V236",stroke=pale,width=9),r(275,107,31,115,base),r(253,93,73,34,pale),r(258,98,62,18,trim,3),l("M289 92 V62",width=5)]
            pieces += [p([(57,208),(87,163),(115,208),(83,195)],base)]
        elif role == "power":
            for x in [86,219]: pieces += [r(x,136,65,105,base),c(x+32,135,33,pale),c(x+32,135,16,base)]
            pieces += [l("M151 214 H219",stroke=dark,width=14),p([(176,137),(152,185),(174,183),(164,215),(204,168),(185,169),(197,137)],trim)]
        elif role == "refinery":
            pieces += [p([(64,93),(143,93),(155,166),(132,212),(82,212),(63,166)],base),r(89,211,44,33,dark),r(186,153,98,74,pale),p([(175,96),(279,96),(263,153),(191,153)],base),r(202,108,54,18,trim,3)]
            for x,y in [(196,111),(225,104),(249,114)]: pieces += [p([(x,y+30),(x-8,y+4),(x+3,y-4),(x+13,y+24)],"#7499a8",3)]
        elif role == "tech":
            pieces += [r(67,226,256,18,pale),r(130,169,117,49,base)]
            if red:
                pieces += [r(81,102,64,109,base),c(113,103,31,pale),l("M248 193 L289 100",stroke=dark,width=14),r(258,209,59,31,base)]
            else:
                for x in [142,168,194,220]: pieces += [c(x,154,27,pale),l(f"M{x} 132 V177",stroke=base,width=6)]
                pieces += [l("M101 219 V105 H139 M278 219 V105 H240",stroke=dark,width=6)]
            pieces += [r(163,180,56,20,trim,3)]
        elif role == "wall": pieces += [r(50,148,280,100,pale),r(51,147,278,19,base),r(162,174,49,25,trim,3),l("M60 211 H318 M117 172 V211 M218 211 V243",stroke=dark,width=5)]
        elif role == "barricade":
            for x in [78,181,282]: pieces += [l(f"M{x-26} 242 l52 -81 M{x-26} 160 l52 82",stroke=dark,width=19),c(x,199,12,base,3)]
            pieces += [r(160,188,42,23,trim,3)]
    if state == "hit": pieces += [l("M127 152 l39 20 -25 21 42 31",stroke="#f5e6c3",width=6)]
    if state == "death": pieces += [l("M171 92 l27 42 -38 47 42 30 -31 52",stroke=dark,width=13)]
    art.save(f"{faction}_{role}_{state}", silhouette, pieces)


def main():
    rules = json.loads((ROOT / "data/rules.json").read_text())
    art.META = json.loads((art.OUT / "contours.json").read_text())
    total = 0
    for category in ("units", "buildings"):
        for spec in rules[category].values():
            role, faction = spec["art"], spec["faction"]
            for state in spec["animations"]:
                if role in ("rifle", "anti", "engineer", "demolition"):
                    faction_infantry_card(faction, role, state)
                elif role in ("tank", "harvester", "assault"):
                    faction_vehicle_card(faction, role, state)
                elif role == "barracks": art.building(faction, role, state)
                else: equipment_card(faction, role, state, category == "buildings")
                total += 1
    (art.OUT / "contours.json").write_text(json.dumps(art.META, separators=(",", ":")))
    print(f"Generated {total} faction cards with fixed faction livery and role silhouettes")


if __name__ == "__main__": main()
