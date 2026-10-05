#!/usr/bin/env python3
"""Original cut-paper artwork. No external assets, fonts, filters, or dependencies."""
from pathlib import Path
import argparse
import json
import math
import random
import xml.etree.ElementTree as ET
ET.register_namespace('', 'http://www.w3.org/2000/svg')

OUT = Path(__file__).resolve().parents[1] / "assets" / "cards"
INK = "#40342b"
PAPER = "#ead6aa"
META = {}


def poly(points, fill, stroke=INK, width=5):
    return f'<polygon points="{" ".join(f"{x},{y}" for x, y in points)}" fill="{fill}" stroke="{stroke}" stroke-width="{width}" stroke-linejoin="round"/>'


def path(d, fill="none", stroke=INK, width=5):
    return f'<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round"/>'


def rect(x, y, w, h, fill, width=5, rx=2):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" stroke="{INK}" stroke-width="{width}"/>'


def circle(x, y, r, fill, width=4):
    return f'<circle cx="{x}" cy="{y}" r="{r}" fill="{fill}" stroke="{INK}" stroke-width="{width}"/>'


def emblem(faction, x, y, size=20, color=None):
    color = color or ("#bb4034" if faction == "rivet" else "#2865a5")
    if faction == "rivet":
        return rect(x-size,y-size,size*2,size*2,color,3) + rect(x-size*.65,y-size*.55,size*1.3,size*.55,PAPER,2) + rect(x-size*.2,y-size*.1,size*.4,size*.85,PAPER,2)
    return poly([(x-size,y-size*.4),(x-size*.2,y-size),(x+size,y-size*.4),(x,y+size),(x-size*.3,y)],color,width=3)


def save(name, silhouette, parts, width=384, height=320, fill=PAPER, robust_outline=False):
    # Mesh silhouette includes the illustrated dark cut edge, but no rectangular paper field.
    cx = sum(p[0] for p in silhouette) / len(silhouette)
    cy = sum(p[1] for p in silhouette) / len(silhouette)
    contour = []
    for x,y in silhouette:
        dx,dy=x-cx,y-cy
        length=max(math.hypot(dx,dy),1)
        contour.append([x+dx/length*5,y+dy/length*5])
    if robust_outline:
        from shapely.geometry import Polygon
        expanded = Polygon(silhouette).buffer(4.5, join_style=2).simplify(.2, preserve_topology=True)
        if expanded.geom_type != 'Polygon' or not expanded.is_valid:
            raise ValueError(f'{name}: the physical paper border must be one valid polygon')
        contour = [[float(x), float(y)] for x,y in list(expanded.exterior.coords)[:-1]]
    outline=poly(silhouette,fill,INK,8)
    rng=random.Random(name)
    flecks=[]
    for _ in range(42):
        x,y=rng.randrange(10,width-10),rng.randrange(10,height-10)
        flecks.append(path(f'M{x},{y} l{rng.randrange(2,8)},-1',stroke="#806c50",width=1))
    contents=''.join(parts) if isinstance(parts,list) else parts
    svg=f'''<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">
<defs><clipPath id="cut"><polygon points="{' '.join(f'{x},{y}' for x,y in silhouette)}"/></clipPath></defs>
{outline}<g clip-path="url(#cut)">{contents}<g opacity=".18">{''.join(flecks)}</g></g>
{path('M'+ ' L'.join(f'{x},{y}' for x,y in silhouette) + ' Z',stroke=INK,width=5)}
</svg>'''
    (OUT/f'{name}.svg').write_text(svg)
    # A separate UV-aligned mask explicitly names the player-owned paint. The
    # game never infers ownership from ordinary faction blue/red or skin color.
    tree = ET.fromstring(svg)
    identity = tree.find(".//{http://www.w3.org/2000/svg}g[@id='player-identification']")
    if identity is not None:
        for element in identity.iter():
            if "fill" in element.attrib: element.set("fill", "#ffffff")
            if "stroke" in element.attrib: element.set("stroke", "#000000")
        identity.set("clip-path", "url(#cut)")
        definitions = tree.find("{http://www.w3.org/2000/svg}defs")
        mask = f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">{ET.tostring(definitions, encoding="unicode")}{ET.tostring(identity, encoding="unicode")}</svg>'
        (OUT/f'{name}_identity.svg').write_text(mask)
    META[name]={"width":width,"height":height,"outline":contour}


def soldier(faction, role, state):
    blue = "#bb4034" if faction == "rivet" else "#2865a5"
    dark = "#734538" if faction == "rivet" else "#375464"
    cloth = "#b5b6a1" if faction == "rivet" else "#c6bc8c"
    skin = "#d9b58a"
    move, fire, hit = state == "move", state == "attack", state == "hit"
    # A smaller helmet, long bent legs, and a forward shoulder give this cut
    # an adult standing weight. Canvas, ground line, and role names stay fixed.
    lean = -10 if hit else 12 if fire else 8 if move else 4
    head_y = -3 if hit else 0
    tool_x = -10 if hit else 6 if fire else 0
    tool_y = 3 if move else -3 if fire else 0

    def shifted(points, dx=0, dy=0):
        return [(x + dx, y + dy) for x, y in points]

    def tool_group(parts):
        return '<g id="role-tool">' + ''.join(parts) + '</g>'

    if state == "death":
        # Keep the existing prone cut and falling-card contract. The coat folds
        # and laid-down equipment now share the standing illustration's ink mass.
        silhouette = [(30,261),(42,240),(85,236),(104,220),(164,225),(190,242),(245,226),(283,234),(305,259),(279,278),(218,282),(189,270),(140,285),(75,275)]
        parts = [poly([(52,254),(105,242),(178,258),(233,244),(271,261),(205,274),(173,264),(107,269)],blue),
                 poly([(90,244),(114,247),(105,261),(79,267),(66,260)],dark,width=3),
                 path("M124 244 L158 263 L143 269 L113 252 Z",cloth,width=3),
                 circle(266,249,17,skin),path("M252 233 Q276 219 287 242 L254 245 Z",dark),
                 path("M76 251 L108 263 M158 247 L187 273",width=4),
                 path("M202 235 l-15 17 17 5 -19 18",stroke=PAPER,width=6)]
        if role == "rifle":
            tool = [poly([(111,253),(124,248),(174,252),(221,249),(230,253),(228,259),(170,263),(143,258),(118,262)],INK,width=3)]
        elif role == "anti":
            tool = [poly([(114,247),(223,247),(234,251),(231,260),(120,263),(110,258)],dark,width=3),path("M210 250 l1 8",stroke=PAPER,width=3)]
        elif role == "engineer":
            tool = [poly([(112,254),(157,250),(168,244),(183,247),(185,254),(172,252),(168,257),(181,262),(173,267),(158,260),(114,262)],"#84918d",width=3)]
        else:
            tool = [poly([(106,245),(132,242),(145,248),(143,265),(118,267),(104,260)],"#b88652",width=4),path("M119 244 l3 20 M134 246 l-2 16",stroke=dark,width=4)]
        parts.append(tool_group(tool))
        parts.append('<g id="player-identification">'+poly([(86,244),(105,242),(127,248),(122,260),(101,261),(85,255)],"#e7ad42",width=3)+'</g>')
        save(f'{faction}_{role}_{state}',silhouette,parts)
        return

    # Per-pose boundaries are complete paths, not positional edits to an idle
    # vertex array. Each boot reaches the same 285px ground line.
    if move:
        legs = [(208,194),(220,223),(239,275),(254,277),(257,285),(229,285),(219,277),(191,240),(179,218),(152,254),(130,274),(142,278),(138,285),(113,282),(110,275),(133,231),(145,196)]
        folds = [([(203,207),(218,230),(239,276),(229,279),(209,246),(188,222)],dark),
                 ([(146,207),(157,216),(140,248),(123,275),(115,276),(130,239)],dark)]
        boots = [[(238,272),(252,276),(257,285),(229,285),(223,278)],[(116,271),(130,272),(142,278),(138,285),(113,282),(110,277)]]
    elif fire:
        legs = [(208,194),(221,224),(239,276),(253,277),(253,285),(223,285),(216,275),(198,243),(186,217),(164,232),(142,269),(156,278),(151,285),(126,280),(124,272),(143,223),(151,193)]
        folds = [([(205,207),(218,230),(239,276),(228,278),(209,247),(188,219)],dark),
                 ([(153,205),(165,215),(150,244),(134,270),(127,271),(141,233)],dark)]
        boots = [[(237,272),(251,276),(253,285),(223,285),(218,279)],[(128,267),(142,269),(156,278),(151,285),(126,280),(124,274)]]
    elif hit:
        legs = [(208,200),(213,230),(223,275),(234,279),(234,285),(208,285),(202,277),(191,243),(179,224),(167,240),(158,273),(172,278),(170,285),(141,285),(135,278),(141,233),(145,201)]
        folds = [([(202,210),(213,232),(222,275),(212,278),(197,247),(181,225)],dark),
                 ([(147,210),(158,218),(152,247),(145,275),(137,277),(141,234)],dark)]
        boots = [[(218,272),(231,277),(234,285),(208,285),(203,279)],[(141,271),(157,273),(172,278),(170,285),(141,285),(135,279)]]
    else:
        legs = [(208,196),(213,232),(229,275),(240,277),(243,285),(214,285),(208,278),(196,240),(181,218),(166,247),(160,276),(174,279),(174,285),(144,285),(138,279),(143,239),(146,198)]
        folds = [([(204,208),(214,238),(227,275),(216,278),(196,240),(185,220)],dark),
                 ([(149,207),(160,216),(155,249),(148,277),(140,277),(144,239)],dark)]
        boots = [[(226,271),(239,276),(243,285),(214,285),(209,279)],[(144,272),(160,275),(174,279),(174,285),(144,285),(138,279)]]

    if faction == "rivet":
        head = [(149,74),(154,59),(165,49),(181,46),(199,50),(211,64),(216,73),(220,78),(214,84),(209,87),(205,101),(191,108),(190,115)]
    else:
        head = [(148,76),(155,57),(167,48),(193,49),(208,62),(212,71),(221,78),(215,86),(208,88),(204,102),(190,109),(190,115)]
    head = shifted(head, lean, head_y)
    right_shoulder = [(212+lean,120),(224+lean,134)]
    # Equipment is part of the actual cut. Rifle bursts and wrench forks have
    # their own complete outlines, including the paper support at their tips.
    if role == "rifle":
        weapon = [(241,128),(298,123),(321,126),(332,136),(323,151),(279,153),(249,155),(240,171),(224,181)]
        if fire:
            weapon = [(241,128),(297,123),(321,124),(341,113),(339,126),(363,136),(344,147),(355,164),(330,157),(315,153),(279,153),(249,155),(240,171),(224,181)]
    elif role == "anti":
        right_shoulder = [(212+lean,120),(215+lean,125)]
        weapon = [(236,122),(310,98),(329,101),(341,114),(340,133),(323,144),(246,169),(224,182)]
        if fire:
            weapon = [(236,122),(310,98),(329,99),(345,91),(341,107),(364,118),(347,130),(355,145),(330,143),(323,149),(246,169),(224,182)]
    elif role == "engineer":
        weapon = [(241,138),(260,138),(265,114),(258,103),(253,88),(263,70),(276,67),(283,84),(290,87),(295,69),(310,79),(313,99),(300,114),(294,120),(289,158),(272,174),(237,182)]
    else:
        weapon = [(241,140),(258,134),(270,110),(273,100),(286,94),(300,104),(301,118),(291,129),(267,173),(235,184)]
        if fire:
            weapon = [(241,137),(263,124),(287,99),(292,85),(307,81),(321,92),(320,108),(307,120),(273,169),(235,181)]
    weapon = shifted(weapon,tool_x,tool_y)
    left_arm = [(133+lean,188),(120+lean,178),(116+lean,151),(127+lean,126),(148+lean,112),(148+lean,102),(143+lean,89)]
    if role in ("engineer","demolition"):
        left_arm = [(133+lean,190),(112+lean,185),(107+lean,152),(118+lean,124),(146+lean,112),(148+lean,102),(143+lean,89)]
    silhouette = head + right_shoulder + weapon + [(213,181)] + legs + left_arm

    # Large sleeve/cloth planes carry the pose at normal game size. The small
    # chest rectangles are replaced by one diagonal strap and two broad folds.
    parts = [poly(legs,cloth)]
    parts += [poly(points,color,stroke="none",width=0) for points,color in folds]
    parts += [poly(boot,INK,width=3) for boot in boots]
    parts += [path(f'M{boots[0][-2][0]} 280 l18 1 M{boots[1][-2][0]} 280 l18 1',stroke=PAPER,width=3),
              poly([(144+lean,119),(176+lean,109),(202+lean,119),(213+lean,146),(207,170),(209,197),(148,202),(134+lean,162),(134+lean,136)],blue),
              poly([(141+lean,135),(155+lean,143),(157,178),(184,193),(151,200),(137+lean,164)],dark,stroke="none",width=0),
              poly([(178+lean,117),(186+lean,120),(163,188),(154,186)],cloth,width=3),
              path("M172 180 L201 171 L206 177 L182 190 Z",dark,width=3),
              poly([(146,190),(207,184),(210,200),(147,205)],dark,width=3),
              rect(169,191,16,10,"#bba279",3)]
    if faction == "kestrel":
        parts += [poly([(139+lean,112),(169+lean,123),(153+lean,144),(129+lean,134)],dark,width=3),
                  path(f'M{142+lean} 117 l15 12 -12 4',stroke=cloth,width=4)]
    else:
        parts += [poly([(125+lean,137),(137+lean,131),(146+lean,147),(141+lean,174),(125+lean,171)],dark,width=4)]

    # A cut profile replaces the old circular cheek, so the nose/neck and tilted
    # helmet stay readable without enlarging the head or changing the palette.
    face = shifted([(151,78),(187,68),(202,76),(207,82),(214,85),(205,90),(202,101),(190,107),(176,108),(157,97),(151,87)],lean,head_y)
    parts += [poly(shifted([(174,99),(191,102),(195,119),(177,119),(172,108)],lean,head_y),skin,width=3),
              poly(face,skin,width=4),
              poly(shifted([(153,82),(164,84),(174,103),(187,107),(171,109),(156,99)],lean,head_y),"#b49166",stroke="none",width=0)]
    if faction == "rivet":
        parts += [path(f'M{149+lean} {75+head_y} Q{152+lean} {49+head_y} {179+lean} {48+head_y} Q{201+lean} {46+head_y} {209+lean} {66+head_y} L{218+lean} {76+head_y} L{211+lean} {81+head_y} L{149+lean} {80+head_y} Z',dark),
                  path(f'M{158+lean} {70+head_y} Q{181+lean} {59+head_y} {203+lean} {71+head_y}',stroke=blue,width=6)]
    else:
        parts += [poly(shifted([(150,75),(159,57),(168,50),(193,52),(207,67),(218,77),(211,82),(150,81)],lean,head_y),dark),
                  path(f'M{158+lean} {63+head_y} L{170+lean} {55+head_y} L{192+lean} {57+head_y} L{207+lean} {74+head_y}',stroke=cloth,width=6)]
    parts += [path(f'M{196+lean} {84+head_y} l8 -1 M{205+lean} {91+head_y} l-7 3 M{190+lean} {100+head_y} l7 -2',width=3)]
    if role == "engineer":
        parts.append(path(f'M{181+lean} {59+head_y} v13 M{175+lean} {65+head_y} h13',stroke=PAPER,width=4))

    near_arm = [(139+lean,129),(151+lean,137),(146+lean,152),(163+lean,157),(182+lean,145),(190+lean,155),(173+lean,173),(152+lean,180),(129+lean,159),(127+lean,142)]
    far_arm = [(203+lean,122),(214+lean,130),(220+lean,155),(232,147),(240,154),(233,169),(215+lean,178),(201+lean,165),(197+lean,144)]
    parts += [poly(far_arm,dark,width=4),poly(near_arm,blue,width=4),
              path(f'M{137+lean} 151 l13 15 18 -1',stroke=dark,width=5)]

    if role == "rifle":
        tool = [poly(shifted([(178,138),(192,133),(219,139),(297,129),(317,132),(324,138),(319,145),(275,148),(243,151),(237,165),(227,166),(225,151),(184,158)],tool_x,tool_y),INK,width=4),
                poly(shifted([(179,139),(189,137),(210,145),(207,153),(184,155)],tool_x,tool_y),"#987b52",width=3),
                path(f'M{263+tool_x} {139+tool_y} L{309+tool_x} {136+tool_y}',stroke=PAPER,width=3),
                poly([(182+lean,149),(193+lean,144),(201+lean,149),(198+lean,157),(189+lean,160),(182+lean,155)],skin,width=3),
                poly(shifted([(230,148),(240,144),(248,149),(244,157),(233,158)],tool_x,tool_y),skin,width=3)]
        if fire:
            tool.append(poly(shifted([(324,130),(340,117),(337,131),(358,136),(340,145),(350,159),(327,151)],tool_x,tool_y),"#f1ca67","#b77c39",3))
    elif role == "anti":
        tool = [poly(shifted([(178,143),(309,104),(327,107),(335,116),(332,130),(319,138),(189,169)],tool_x,tool_y),dark,width=5),
                poly(shifted([(180,144),(308,110),(317,112),(188,153)],tool_x,tool_y),cloth,stroke="none",width=0),
                circle(325+tool_x,119+tool_y,8,"#a68e63",3),
                path(f'M{305+tool_x} {110+tool_y} l5 21',stroke=INK,width=5),
                poly([(181+lean,153),(194+lean,149),(204+lean,157),(201+lean,164),(188+lean,169),(180+lean,164)],skin,width=3)]
        if fire:
            tool.append(poly(shifted([(331,108),(344,95),(341,109),(359,119),(343,129),(351,141),(330,134)],tool_x,tool_y),"#f1ca67","#b77c39",3))
    elif role == "engineer":
        tool = [poly(shifted([(269,151),(281,154),(288,115),(302,99),(302,84),(298,77),(291,94),(278,91),(273,74),(266,75),(258,87),(263,101),(271,112)],tool_x,tool_y),"#84918d",width=5),
                path(f'M{278+tool_x} {117+tool_y} L{274+tool_x} {145+tool_y}',stroke=PAPER,width=4),
                poly(shifted([(258,146),(267,140),(281,145),(283,153),(276,162),(262,164)],tool_x,tool_y),skin,width=3),
                poly([(115+lean,147),(139+lean,146),(141+lean,183),(116+lean,179)],"#ba9459",width=4)]
        parts += [poly([(210+lean,142),(224+lean,144),(239+tool_x,156),(260+tool_x,148),(264+tool_x,158),(240+tool_x,172),(221+lean,167),(207+lean,158)],blue,width=4)]
    else:
        gx, gy = (304+tool_x,101+tool_y) if fire else (284+tool_x,113+tool_y)
        tool = [poly([(113+lean,141),(138+lean,138),(144+lean,181),(116+lean,181),(110+lean,165)],dark,width=4),
                poly([(116+lean,145),(129+lean,144),(133+lean,176),(119+lean,177)],"#b88652",width=3),
                poly([(132+lean,143),(138+lean,145),(141+lean,177),(134+lean,178)],"#b88652",width=3),
                path(f'M{117+lean} 143 Q{114+lean} 130 {126+lean} 135',stroke=INK,width=4),
                path(f'M{223+lean} 157 L{250+tool_x} 151 L{gx-8} {gy+10}',stroke=blue,width=18),
                circle(gx,gy,10,"#b88652",4),path(f'M{gx} {gy-10} l5 -5',width=4),
                circle(gx-8,gy+11,6,skin,3)]
    parts += [tool_group(tool),emblem(faction,193,180,9)]
    if hit:
        # Marks sit on the existing coat. No disconnected star vertices enlarge
        # the physical head contour or splice into the weapon's boundary.
        parts += [path(f'M{146+lean} 130 l-14 -8 M{199+lean} 135 l14 -7',stroke="#bc593f",width=6),
                  path("M171 161 l-10 11 12 8",stroke=PAPER,width=5)]
    # Broad helmet crown and visible shoulder/back panel survive the RTS view.
    # Faction clothing stays fixed; only these explicitly authored regions vary.
    identity = [poly(shifted([(160,58),(175,52),(190,54),(199,64),(190,70),(170,68)],lean,head_y),"#e7ad42",width=3),
                poly([(128+lean,131),(141+lean,126),(152+lean,138),(148+lean,157),(133+lean,153)],"#e7ad42",width=3)]
    parts.append('<g id="player-identification">'+''.join(identity)+'</g>')
    save(f'{faction}_{role}_{state}',silhouette,parts)

def vehicle(faction,role,state):
    accent="#bb4034" if faction=="rivet" else "#2865a5"
    hull="#b4a787" if faction=="rivet" else "#c5bb96"
    dark="#635844"
    y=10 if state=="death" else 0
    recoil=-12 if state=="attack" else 0
    if role=="harvester":
        silhouette=[(30,148),(52,129),(56,87),(85,77),(107,59),(129,78),(152,54),(173,86),(208,93),(251,95),(279,116),(294,148),(335,152),(347,172),(345,225),(328,252),(61,252),(31,229)]
    elif role=="assault":
        silhouette=[(22,176),(39,151),(62,137),(84,137),(91,95),(143,83),(178,70),(244,85),(252,113),(345,108),(362,119),(361,143),(257,151),(285,164),(331,176),(351,193),(347,240),(321,257),(60,259),(24,237)]
    elif faction=="rivet":
        silhouette=[(25,186),(45,165),(63,151),(99,148),(103,106),(156,93),(217,100),(238,120),(339,119),(352,132),(344,149),(236,151),(259,166),(311,176),(336,194),(329,235),(304,255),(65,257),(33,238)]
    else:
        silhouette=[(35,191),(70,162),(109,157),(132,117),(182,105),(222,120),(235,135),(335,122),(350,133),(344,145),(236,158),(254,163),(300,164),(339,198),(326,236),(298,253),(78,255),(42,234)]
    if state=="attack" and role!="harvester":
        # A visible muzzle burst is part of this distinct physical animation cut.
        rightmost=max(range(len(silhouette)),key=lambda i:silhouette[i][0])
        silhouette[rightmost:rightmost+2]=[(351,108),(357,119),(374,130),(357,142),(366,159),(343,150)]
    parts=[poly([(37,187+y),(64,169+y),(302,171+y),(330,197+y),(320,233+y),(299,248+y),(72,248+y),(40,229+y)],dark),path(f'M56 {225+y} L308 {225+y}',stroke="#9f957d",width=9)]
    for x in range(70,311,43 if role!="assault" else 37):
        parts += [circle(x,217+y,17,"#b7a780",4),circle(x,217+y,7,dark,3)]
    parts += [path(f'M53 {242+y} L312 {243+y} M48 {199+y} L313 {194+y}',stroke=PAPER,width=3)]
    if role=="harvester":
        parts += [rect(45,112,165,88,hull,5),path("M54 124 L197 124 M76 132 v54 M103 132 v54 M133 132 v54 M165 132 v54",width=4),poly([(209,119),(256,120),(283,165),(321,166),(327,198),(209,198)],accent),poly([(220,130),(247,132),(265,162),(223,162)],"#768c8c",width=4),rect(283,179,34,13,PAPER,3),circle(260,186,4,PAPER,2)]
        for x,h in [(68,83),(93,71),(116,94),(144,65),(171,87)]:
            parts += [poly([(x-15,111),(x-14,h),(x,h-13),(x+15,h+10),(x+9,116)],"#6c99ae",width=4),path(f'M{x} {h-8} L{x} 110',stroke="#bdd7cf",width=3)]
    else:
        parts += [poly([(58,169+y),(119,143+y),(254,158+y),(304,177+y),(319,195+y),(55,196+y)],hull),path(f'M80 {175+y} L116 {164+y} M253 {178+y} l39 4',stroke=PAPER,width=4),poly([(113+recoil,119+y),(157+recoil,105+y),(217+recoil,112+y),(236+recoil,144+y),(196+recoil,164+y),(109+recoil,149+y)],accent),rect(156+recoil,97+y,31,15,hull,3),poly([(218+recoil,130+y),(339+recoil,125+y),(343+recoil,140+y),(224+recoil,148+y)],dark,width=4),path(f'M{329+recoil} {127+y} l1 13',stroke=PAPER,width=4),emblem(faction,157+recoil,139+y,14)]
        if role=="assault":
            parts += [rect(117,113,73,40,accent,4),circle(233,136,14,INK,4),circle(233,136,6,"#d0bd93",2),path("M83 165 L89 132 L110 127 M104 96 v-22",width=5),rect(298,158,17,30,accent,3)]
        elif faction=="kestrel":
            parts += [poly([(114,145),(135,124),(151,153)],PAPER,width=3),path("M130 177 l25 -6 M169 173 l22 3 M260 164 l-8 18",stroke=accent,width=6)]
        else:
            for x in [84,111,225,250,284]:
                parts += [circle(x,181,3,INK,0)]
    if state=="move":
        parts += [path("M54 221 l17 -11 M95 232 l14 -10 M269 232 l14 -11 M308 219 l13 -11",stroke=PAPER,width=4)]
    if state=="attack":
        parts += [poly([(332,126),(350,113),(346,127),(368,130),(352,141),(360,154),(337,143)],"#f4c760","#af6d31",3)]
    if state=="hit":
        parts += [poly([(63,156),(82,136),(88,155),(107,146),(97,167),(110,181),(88,179),(76,194),(73,175),(54,176)],"#f1b963","#b66c44",3),path("M206 165 l-12 15 16 6 -7 11",stroke=PAPER,width=5)]
    if state=="death":
        parts += [poly([(138,113),(173,127),(157,151),(184,173),(155,195),(189,199),(188,215),(136,206),(145,181),(129,160)],"#e2cea6",width=3),path("M218 145 l-15 15 21 12 -18 17 M88 200 l21 -9",width=6),path("M254 116 l-8 35 18 11",stroke="#2f2922",width=9)]
    save(f'{faction}_{role}_{state}',silhouette,parts)


def building(faction,role,state):
    rivet=faction=="rivet"
    accent="#bb4034" if rivet else "#2865a5"
    pale="#b8b2a0" if rivet else "#c7bd91"
    wall="#cbb793" if rivet else "#ddcba1"
    dark="#655746"
    if role=="tower":
        silhouette=[(129,301),(134,161),(117,157),(112,85),(142,70),(148,20),(158,20),(159,38),(223,41),(224,70),(254,89),(253,157),(238,168),(252,301)]
        if rivet:
            silhouette[10:12]=[(254,89),(253,98),(331,98),(333,128),(253,130),(253,157)]
        else:
            silhouette[10:12]=[(254,67),(270,65),(265,84),(254,91),(253,157)]
        parts=[poly([(138,298),(151,155),(228,156),(245,299)],wall),path("M147 293 L230 159 M237 293 L158 159 M147 224 L237 224",stroke=dark,width=10),rect(121,88,128,72,accent),rect(134,101,105,38,PAPER),emblem(faction,184,120,21),path("M151 75 V25",width=7),poly([(159,30),(211,42),(214,66),(159,55)],accent),emblem(faction,185,47,10),rect(128,285,122,20,pale)]
        if rivet:parts += [rect(231,106,89,17,dark),rect(315,99,14,28,pale,3)]
        else:parts += [path("M208 91 l46 -23 M213 92 l47 -12",stroke=dark,width=9)]
        save(f'{faction}_{role}_{state}',silhouette,parts,width=384,height=320)
        return
    # Rivet has brick buttresses, flat steel roof and rivets. Kestrel has timber
    # cross-braces, a canvas gable and split posts; these are different silhouettes.
    if rivet:
        silhouette=[(26,295),(25,177),(43,155),(48,112),(81,90),(89,90),(89,39),(117,34),(118,90),(162,90),(162,24),(191,22),(196,88),(285,93),(307,123),(337,146),(344,296)]
    else:
        silhouette=[(25,297),(31,158),(53,133),(139,65),(205,78),(219,29),(230,27),(231,75),(288,118),(330,146),(348,166),(342,297)]
    if rivet and role=="barracks":
        silhouette=[(26,295),(25,177),(43,155),(48,112),(119,77),(157,77),(158,34),(168,32),(168,49),(218,54),(213,81),(276,92),(307,123),(337,146),(344,296)]
    elif rivet and role=="factory":
        silhouette=[(26,295),(25,177),(43,155),(45,112),(82,87),(101,112),(142,76),(158,111),(199,74),(216,109),(255,71),(273,111),(305,124),(337,146),(344,296)]
    elif rivet and role=="refinery":
        silhouette=[(26,295),(25,177),(43,155),(47,107),(66,91),(65,51),(94,35),(131,51),(131,96),(180,98),(218,53),(239,53),(275,99),(307,123),(337,146),(344,296)]
    elif rivet and role=="tech":
        silhouette=[(26,295),(25,177),(43,155),(48,113),(108,79),(154,79),(154,54),(174,43),(194,55),(202,79),(285,93),(307,123),(337,146),(344,296)]
    elif not rivet and role=="power":
        silhouette=[(25,297),(31,158),(53,133),(111,89),(137,81),(195,109),(208,63),(232,48),(269,65),(286,108),(314,130),(348,166),(342,297)]
    elif not rivet and role=="barracks":
        silhouette=[(25,297),(31,159),(103,91),(176,145),(205,83),(219,76),(219,31),(230,30),(231,79),(286,120),(330,147),(348,166),(342,297)]
    elif not rivet and role=="refinery":
        silhouette=[(25,297),(31,158),(53,134),(139,67),(204,79),(224,108),(253,107),(253,52),(272,30),(295,45),(295,127),(331,146),(348,166),(342,297)]
    elif not rivet and role=="factory":
        silhouette=[(25,297),(31,158),(61,126),(146,69),(199,82),(282,116),(330,146),(348,166),(342,297)]
    elif not rivet and role=="tech":
        silhouette=[(25,297),(31,158),(53,133),(139,65),(176,72),(178,43),(200,33),(218,48),(220,76),(288,118),(330,146),(348,166),(342,297)]
    parts=[]
    if rivet:
        if role in ("hq","power"):
            parts += [rect(91,38,23,102,dark,4),rect(166,26,26,124,accent,4),path("M94 47 h17 M95 61 h17 M169 36 h17 M170 49 h17",stroke=PAPER,width=4)]
        parts += [poly([(47,121),(90,95),(286,98),(326,151),(299,167),(54,162)],pale),poly([(46,157),(301,157),(336,176),(335,288),(48,288)],wall),poly([(300,159),(335,177),(335,288),(300,276)],"#ad9775",width=4),path("M68 111 L284 113 M64 129 L297 130",stroke=dark,width=3)]
        if role=="factory":parts += [poly([(48,115),(80,94),(100,115),(140,84),(158,115),(198,82),(216,113),(255,79),(274,116),(306,130),(305,143),(49,141)],accent),path("M105 124 v14 M164 123 v14 M224 122 v15",stroke=PAPER,width=5)]
        elif role=="refinery":parts += [poly([(68,101),(70,54),(95,43),(126,55),(127,110)],pale),path("M71 64 h52 M72 76 h51 M95 51 v54",stroke=accent,width=4),poly([(181,101),(223,60),(235,61),(271,105)],accent)]
        elif role=="barracks":parts += [path("M163 95 V38",width=5),poly([(170,43),(210,57),(205,74),(170,63)],accent),emblem(faction,190,60,9)]
        elif role=="tech":parts += [circle(178,66,18,accent),circle(178,66,7,PAPER,3)]
        for y in [177,205,233,263]:
            parts += [path(f'M51 {y} H298',stroke="#a58c68",width=2)]
        for x in range(56,298,27):
            parts += [circle(x,150,3,INK,0)]
        parts += [rect(36,177,19,111,pale),rect(283,173,19,109,pale),rect(23,286,320,16,dark)]
    else:
        parts += [poly([(42,151),(137,76),(205,90),(328,158),(299,172),(145,111),(61,174)],accent),poly([(46,168),(145,112),(304,175),(336,186),(334,289),(48,289)],wall),poly([(305,173),(336,187),(334,289),(305,277)],"#ba9f76"),path("M62 172 L146 125 L289 177",stroke=PAPER,width=4),path("M53 183 V285 M297 188 V282 M56 282 L114 205 M55 205 L114 282",stroke=dark,width=8),path("M164 122 L198 162 M190 134 L223 175 M220 147 L254 184",stroke="#d9bc91",width=3),rect(27,287,316,15,dark)]
        if role in ("hq","barracks"):
            parts += [path("M220 77 V32",width=6),poly([(231,39),(283,49),(271,68),(231,59)],accent),emblem(faction,255,54,9)]
        elif role=="power":parts += [circle(245,93,34,pale),circle(245,93,11,accent),path("M244 65 v16 M259 91 h14 M245 107 v15 M218 91 h15",width=6)]
        elif role=="refinery":parts += [poly([(256,54),(272,38),(291,51),(290,135),(256,132)],pale),path("M261 68 h26 M261 83 h26 M261 99 h26",stroke=accent,width=4)]
        elif role=="tech":parts += [circle(199,57,19,accent),path("M198 45 v14 M194 63 h8",stroke=PAPER,width=5)]
    # Function-specific cut-paper equipment and silhouettes within the façade.
    if role=="hq":
        parts += [rect(146,210,60,84,dark),rect(152,216,48,71,accent,3),path("M176 221 V282",stroke=PAPER,width=3),rect(74,186,47,37,"#839797",4),path("M97 188 V222 M75 205 H117",stroke=PAPER,width=3),rect(225,188,40,36,"#839797",4),emblem(faction,176,172,24),rect(116,263,22,25,pale,3),path("M127 267 v18",width=2)]
    elif role=="power":
        parts += [rect(85,174,59,99,accent),rect(219,173,45,102,pale),path("M96 183 v80 M116 183 v80 M230 184 v78 M249 185 v76",stroke=PAPER,width=5),poly([(175,169),(156,211),(175,211),(164,251),(203,199),(183,199),(195,169)],"#d6a54d",width=4),path("M144 245 H162 M203 245 H219",stroke=dark,width=8),rect(69,270,222,19,dark)]
    elif role=="refinery":
        parts += [rect(65,177,84,95,pale),path("M76 188 h62 M76 201 h62 M76 214 h62",width=3),poly([(156,186),(240,176),(287,212),(265,266),(172,265)],dark),poly([(178,216),(190,180),(205,190),(216,169),(237,199),(253,188),(263,217),(241,239),(186,239)],"#7499a8",width=4),path("M177 265 L277 265 M180 276 L272 276",stroke=PAPER,width=4),rect(101,266,36,28,dark)]
    elif role=="barracks":
        parts += [rect(141,219,77,77,dark),poly([(142,219),(161,219),(165,277),(143,292)],accent),poly([(218,219),(202,219),(195,277),(218,292)],accent),rect(67,186,50,42,pale),path("M76 196 h34 M77 207 h32 M78 217 h30",width=3),rect(239,216,41,66,pale),emblem(faction,178,181,22),path("M246 224 l27 50 M274 224 l-28 50",width=3)]
    elif role=="factory":
        parts += [rect(119,207,149,83,dark),rect(126,211,136,73,pale,4),path("M129 223 H260 M130 237 H260 M130 251 H260 M130 265 H260",width=4),rect(70,191,33,38,accent),circle(190,177,22,accent),circle(190,177,9,PAPER,3),path("M169 177 h-6 M211 177 h6 M190 155 v-7 M190 199 v6",width=6),rect(279,254,32,38,wall,3),path("M281 257 l26 32 M309 257 l-26 31",width=2)]
    else:
        parts += [rect(139,218,89,76,dark),rect(145,224,76,65,pale,4),path("M157 238 l42 38 M204 236 l-47 41",width=6),circle(184,177,27,accent),circle(184,177,13,PAPER,3)]
        if rivet:parts += [rect(64,196,51,62,accent),path("M75 204 V249 M91 204 V249",stroke=PAPER,width=4)]
        else:parts += [poly([(67,222),(89,200),(109,221),(107,259),(66,261)],accent),path("M80 209 l12 41 M95 211 l-9 41",stroke=PAPER,width=4)]
    if state=="death":
        parts += [poly([(155,115),(187,133),(170,161),(200,189),(175,204),(190,234),(159,258),(175,293),(135,295),(143,265),(126,246),(151,226),(133,203),(152,180),(133,155)],"#5a4938",width=3),path("M240 136 l-24 33 30 20 -19 27 M77 242 l38 10 -23 21",stroke="#6d5842",width=8),path("M62 282 L299 282",stroke="#ead7b2",width=3)]
    save(f'{faction}_{role}_{state}',silhouette,parts)


def decor():
    pine=[(183,14),(220,79),(203,80),(252,137),(230,139),(289,202),(260,202),(307,269),(204,276),(205,310),(167,310),(166,275),(70,274),(113,207),(92,207),(140,148),(115,149),(164,83),(146,84)]
    parts=[poly([(183,32),(215,90),(173,93)],"#718168",width=3),poly([(176,90),(231,151),(133,153)],"#65765d",width=3),poly([(176,143),(269,211),(110,213)],"#586c54",width=3),poly([(173,202),(289,263),(87,264)],"#52654e",width=3),path("M184 61 V294",stroke="#69583d",width=8),path("M184 135 L156 121 M184 153 L215 139 M184 205 L145 181 M184 223 L229 194 M185 249 L149 229",stroke="#354938",width=5),rect(170,278,31,28,"#91784f",3),path("M149 152 l22 -25 M119 211 l29 -24 M100 263 l33 -26",stroke="#91a078",width=5)]
    save('decor_pine',pine,parts,fill="#b8b28d")
    birch=[(89,146),(72,101),(91,68),(129,56),(138,24),(186,14),(220,35),(249,39),(271,75),(303,95),(307,130),(287,158),(237,168),(210,191),(203,310),(172,310),(168,194),(139,174),(105,172)]
    parts=[poly([(85,105),(115,75),(160,57),(179,24),(219,53),(256,61),(281,106),(273,146),(225,150),(192,179),(140,152),(110,157)],"#83926f",width=4),path("M187 298 V131 M187 186 L143 142 M189 163 L236 119",stroke=PAPER,width=15),path("M177 281 h15 M182 264 h12 M179 233 h13 M184 206 h10 M180 187 h11",stroke=INK,width=4),path("M118 92 Q146 72 161 80 M232 83 Q258 97 254 117 M104 129 l27 8",stroke="#b8be8c",width=5)]
    save('decor_birch',birch,parts)
    rock=[(34,268),(62,173),(91,166),(115,92),(173,60),(201,72),(224,141),(281,156),(335,253),(311,286),(132,293)]
    parts=[poly([(41,265),(114,100),(174,69),(159,284)],"#a59b80",width=4),poly([(174,69),(202,83),(229,154),(185,210),(158,283)],"#877e69",width=4),poly([(229,153),(278,164),(326,253),(189,276),(185,209)],"#b9ad8c",width=4),path("M82 215 L98 164 M137 120 l-9 62 M215 199 l44 -20 M247 225 l42 13",stroke="#6e654f",width=4)]
    save('decor_rock',rock,parts)
    crystal=[(46,278),(63,219),(92,230),(104,131),(144,89),(162,131),(177,189),(201,64),(234,25),(255,64),(265,199),(287,159),(315,201),(336,274),(295,300),(92,298)]
    parts=[poly([(104,275),(107,136),(144,99),(159,140),(174,282)],"#73a5b8",width=4),poly([(198,279),(205,71),(234,34),(252,74),(264,281)],"#5e8da5",width=4),poly([(277,284),(289,168),(311,207),(328,273)],"#83b7c2",width=4),path("M234 39 V276 M143 102 V279 M289 178 L299 286",stroke="#c2dfd8",width=5),path("M206 72 L233 93 L250 76 M109 139 L140 156 L159 140",stroke="#ceded3",width=3),poly([(53,277),(64,227),(87,240),(97,287)],"#91bfc6",width=3)]
    save('decor_crystal',crystal,parts,fill="#b8d0c9")



def main():
    global OUT, META
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--only', choices=('all', 'infantry'), default='all',
                        help='Regenerate only the chosen original SVG cards')
    parser.add_argument('--output-dir', type=Path, default=OUT,
                        help='Card directory; an existing contours.json is merged')
    args = parser.parse_args()
    OUT = args.output_dir.resolve()
    OUT.mkdir(parents=True, exist_ok=True)
    metadata_path = OUT / 'contours.json'
    if args.only == 'infantry' and not metadata_path.exists():
        parser.error('--only infantry requires an existing contours.json; copy the current card directory first')
    META = json.loads(metadata_path.read_text()) if metadata_path.exists() else {}
    generated = 0
    for faction in ('rivet', 'kestrel'):
        for role in ('rifle', 'anti', 'engineer') + (('demolition',) if faction == 'kestrel' else ()):
            for state in ('idle', 'move', 'attack', 'hit', 'death'):
                soldier(faction, role, state)
                generated += 1
        if args.only == 'all':
            for role in ('tank', 'harvester') + (('assault',) if faction == 'rivet' else ()):
                for state in ('idle', 'move', 'attack', 'hit', 'death'):
                    vehicle(faction, role, state)
                    generated += 1
            for role in ('hq', 'power', 'refinery', 'barracks', 'factory', 'tower', 'tech'):
                for state in ('idle', 'death'):
                    building(faction, role, state)
                    generated += 1
    if args.only == 'all':
        decor()
        generated += 4
    metadata_path.write_text(json.dumps(META, separators=(',', ':')))
    print(f'Generated {generated} original SVG cards; merged {len(META)} matching cut contours in {OUT}')


if __name__ == '__main__':
    main()
