#!/usr/bin/env python3
"""Authored 22-role human paper silhouettes, shared by battlefield and portraits.

Only silhouette art, cut geometry and portrait masks are generated. Logical
sizes, motion, facing and the renderer's existing 0.6 scale remain untouched.
"""
from pathlib import Path
import argparse
import json
import subprocess
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'assets/cards/paper_infantry_revision'
INK='#302d28'; PAPER='#e6ddc8'; LIGHT='#f1ebdb'; DARK='#5d584f'; STEEL='#929991'; SKIN='#d7af8b'; OWNER='#bd53be'; SEAL='#e7ad42'
ROSTER={
 'rivet': [('rifle','assault','flat',106,'plate'),('anti','double_tube','visor',100,'rockets'),('engineer','wrench','hardhat',100,'tools'),('gunner','rotary','bucket',126,'ammo'),('grenadier','lobber','round',82,'canisters')],
 'kestrel': [('rifle','carbine','combat',80,'roll'),('anti','rocket','combat_high',86,'rocket_pair'),('engineer','scanner','cap',74,'radio'),('demolition','detonator','eod',112,'bombs'),('gunner','machinegun','visor',92,'ammo_box'),('marksman','sniper','beret',72,'cloak'),('aa_infantry','missile','sensor',84,'missile_pack')],
 'iron': [('rifle','nailer','stovepipe',85,'boiler'),('anti','harpoon','widebrim',98,'shells'),('engineer','pickaxe','railcap',83,'rails'),('marksman','longrifle','highhat',70,'longcoat'),('mortar','mortar','roundbrim',103,'mortar_plate')],
 'sky': [('rifle','foldgun','hood',70,'cape'),('anti','foldlauncher','crest',82,'fold_shield'),('engineer','foldtools','openhood',72,'fold_tools'),('storm','pulse','crown',85,'coil'),('aa_infantry','winglauncher','winghood',76,'fold_wings')],
}
STATES=('idle','move','combat','hit','death')

class Drawing:
 def __init__(self,lod): self.parts=[];self.lod=lod;self.sw=(2.8,3.0,3.5)[lod]
 def path(self,d,fill=PAPER,stroke=INK,sw=None):self.parts.append(f'<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{self.sw if sw is None else sw}" stroke-linecap="round" stroke-linejoin="round"/>')
 def poly(self,pts,fill=PAPER,stroke=INK):self.path('M'+' L'.join(f'{x},{y}' for x,y in pts)+' Z',fill,stroke)
 def rect(self,x,y,w,h,fill=PAPER,rx=0):self.parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}" stroke="{INK}" stroke-width="{self.sw}"/>')
 def ellipse(self,x,y,rx,ry,fill=PAPER):self.parts.append(f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="{fill}" stroke="{INK}" stroke-width="{self.sw}"/>')
 def line(self,x,y,x2,y2,fill=INK,sw=None):self.path(f'M{x} {y} L{x2} {y2}','none',fill,sw)
 def begin(self,transform):self.parts.append(f'<g transform="{transform}">')
 def end(self):self.parts.append('</g>')


def backgear(d,faction,gear,width,combat):
 # Every role's largest recognition cue remains in all three detail levels.
 if gear in ('cloak','longcoat','cape'):
  end=(252 if combat else 283) if gear in ('cloak','longcoat') else 242
  d.poly([(75,105),(105,125),(90,205),(74,end),(34,end-7),(52,195),(40,143)],DARK if gear=='cloak' else PAPER)
  d.poly([(56,150),(68,117),(66,217),(43,end-9)],OWNER if gear=='cape' else '#a49b84')
 elif gear=='plate':
  d.rect(35,119,38,66,STEEL,7);d.rect(39,139,28,25,OWNER,3)
 elif gear=='rockets':
  for x,y in [(27,89),(43,81)]:d.poly([(x,y+70),(x,y+12),(x+7,y),(x+14,y+12),(x+14,y+70)],DARK)
 elif gear=='tools':
  d.rect(27,117,43,80,'#a28b69',5);d.line(38,143,23,72,DARK,8);d.rect(11,66,38,15,STEEL)
 elif gear=='ammo':
  d.rect(19,108,49,91,DARK,5);d.rect(25,116,35,20,OWNER);d.path('M48 153 Q27 202 77 205','none','#b39863',12)
 elif gear=='canisters':
  for x in [23,43]:d.rect(x,95,19,105,STEEL,9);d.rect(x+3,85,13,16,DARK,2)
 elif gear=='roll':d.rect(50,112,22,48,DARK,5);d.rect(41,104,33,14,'#b5ad95',6)
 elif gear=='rocket_pair':
  for x,y in [(39,86),(52,96)]:d.poly([(x,y+84),(x,y+17),(x+7,y),(x+14,y+17),(x+14,y+84)],'#999d8c')
 elif gear=='radio':
  d.rect(30,123,40,62,DARK,4);d.line(39,121,35,47,INK,4);d.line(57,122,58,84,INK,4);d.rect(35,133,25,14,STEEL)
 elif gear=='bombs':
  d.rect(23,120,45,85,DARK,9)
  for x in [30,44]:d.rect(x,128,11,63,'#b8a37f',5)
 elif gear=='ammo_box':d.rect(29,98,41,99,DARK,1);d.rect(33,106,31,23,OWNER);d.path('M41 175 Q61 210 100 173','none','#b39863',10)
 elif gear=='missile_pack':
  for x,y in [(19,99),(36,88),(53,102)]:d.rect(x,y,15,108,DARK,3);d.poly([(x,y),(x+7,y-16),(x+15,y)],STEEL)
 elif gear=='boiler':
  d.rect(28,98,36,99,'#a9936c',16);d.rect(38,65,15,38,DARK);d.ellipse(43,136,12,13,PAPER);d.line(43,137,50,130,INK,2.3)
 elif gear=='shells':
  d.rect(28,131,39,71,DARK,4)
  for x,y in [(28,78),(46,93)]:d.poly([(x,y+72),(x,y+20),(x+9,y),(x+18,y+20),(x+18,y+72)],'#baa577')
 elif gear=='rails':
  for x in [22,47]:d.rect(x,53,8,165,STEEL)
  for y in [69,100,131,162,195]:d.rect(18,y,43,7,'#a08b6c')
 elif gear=='mortar_plate':
  d.poly([(19,105),(55,91),(76,152),(48,202),(18,177)],DARK);d.line(23,126,65,101,STEEL,15);d.rect(18,189,49,16,STEEL)
 elif gear=='fold_shield':
  d.poly([(39,89),(79,112),(67,211),(18,187),(27,151)],LIGHT);d.poly([(39,89),(48,168),(18,187),(27,151)],OWNER)
 elif gear=='fold_tools':
  d.poly([(23,76),(60,100),(65,178),(47,161)],LIGHT);d.poly([(20,128),(59,114),(72,160),(24,175)],STEEL);d.line(37,98,54,138,OWNER,7)
 elif gear=='coil':
  d.poly([(25,117),(47,79),(75,114),(60,191),(32,184)],DARK);d.ellipse(45,137,20,30,STEEL);d.ellipse(45,137,10,18,OWNER)
 elif gear=='fold_wings':
  d.poly([(15,53),(54,86),(83,150),(53,158),(31,113)],LIGHT);d.poly([(31,94),(60,118),(53,158),(22,175)],OWNER);d.poly([(60,72),(80,90),(76,136),(64,117)],LIGHT)


def helmet(d,faction,hat):
 # Open facial profiles stay human; differences are headgear, not skin color.
 if hat in ('flat','hardhat','round','bucket','visor') and faction=='rivet':
  if hat=='bucket':d.path('M71 39 Q102 17 130 40 L139 84 L115 90 L79 76 Z',STEEL);d.rect(112,56,24,12,DARK);return
  if hat=='hardhat':d.path('M66 58 Q63 19 104 24 Q136 27 137 56 Z',PAPER);d.rect(59,53,84,12,OWNER);d.rect(91,22,14,29,STEEL)
  elif hat=='round':d.path('M64 59 Q59 17 99 19 Q140 22 141 65 L127 59 L75 65 Z',PAPER);d.ellipse(80,64,11,13,DARK)
  elif hat=='visor':d.path('M64 55 Q68 20 111 24 L139 47 L139 66 L116 57 L65 69 Z',STEEL);d.rect(74,45,64,13,OWNER)
  else:d.path('M66 49 Q75 21 105 29 L133 47 L138 55 L63 61 Z',STEEL);d.poly([(56,55),(144,47),(149,59),(58,68)],PAPER)
 elif faction=='kestrel':
  if hat=='beret':d.path('M66 47 Q56 24 91 21 L124 31 L139 45 L111 49 L seventy 49'.replace('seventy','70'),DARK);d.rect(71,44,53,10,OWNER)
  elif hat=='cap':d.path('M66 50 L73 26 L110 26 L124 49 Z',PAPER);d.poly([(67,48),(151,48),(158,55),(68,60)],DARK)
  elif hat=='eod':d.path('M59 58 Q52 13 99 14 Q149 13 147 69 L134 91 L75 88 Z',STEEL);d.rect(80,43,61,22,SKIN,6);d.line(117,54,129,54,INK,3);d.path('M71 76 L133 82 L146 114 L68 115 Z',PAPER)
  else:
   d.path('M64 51 L69 29 L96 22 L124 31 L138 52 L128 61 L66 65 Z',PAPER)
   d.path('M69 41 L77 54 L70 75 L58 72 L58 51 Z',DARK)
   d.rect(81,30,37,8,OWNER)
   if hat=='combat_high':d.poly([(79,27),(86,12),(106,14),(114,29)],STEEL)
   if hat=='visor':d.poly([(116,51),(146,53),(145,65),(123,64)],DARK)
   if hat=='sensor':d.rect(78,9,26,18,STEEL,3);d.line(91,27,91,36,INK,4)
 elif faction=='iron':
  if hat=='stovepipe':d.poly([(68,44),(73,13),(104,10),(119,41)],DARK)
  elif hat=='highhat':d.poly([(69,43),(72,6),(98,5),(109,44)],DARK);d.line(75,19,100,18,OWNER,8)
  elif hat=='railcap':d.poly([(63,46),(61,28),(107,26),(128,48)],PAPER);d.rect(65,40,57,13,OWNER)
  elif hat=='widebrim':d.path('M68 43 L77 24 L111 25 L123 46 Z',DARK)
  else:d.path('M61 51 Q57 21 98 24 Q126 29 133 50 Z',STEEL)
  d.poly([(46 if hat=='widebrim' else 53,48),(135,42),(145 if hat=='widebrim' else 137,53),(51,62)],'#b6a27e')
  if hat!='highhat':d.ellipse(94,44,10,7,STEEL);d.ellipse(115,43,8,7,STEEL)
 else:
  top=(92,9) if hat in ('hood','openhood') else (103,4)
  if hat=='crown':
   d.poly([(62,49),(64,8),(80,26),(95,6),(107,27),(128,8),(130,54),(114,43),(92,31)],LIGHT)
  elif hat=='winghood':
   d.poly([(54,49),(49,7),(89,24),(108,9),(144,42),(128,61),(114,37),(94,30),(74,52)],LIGHT)
  elif hat=='crest':d.poly([(58,52),(65,19),(103,4),(145,48),(124,67),(115,37),(90,29),(72,50),(78,86),(56,89)],LIGHT)
  elif hat=='openhood':d.poly([(55,41),(79,16),(115,19),(136,44),(127,55),(114,32),(78,36),(65,58),(67,87),(49,77)],LIGHT)
  else:d.poly([(57,45),top,(128,39),(134,63),(118,65),(110,34),(88,29),(69,49),(72,82),(54,89)],LIGHT)
  d.line(60,52,69,72,OWNER,6)


def weapon(d,style,gy,combat,lod):
 # All coordinates are local to the hands; equipment has a dedicated silhouette.
 d.begin(f'translate(121 {gy})')
 if style in ('carbine','assault','foldgun'):
  if style=='assault':d.poly([(0,0),(63,-6),(73,4),(53,15),(21,17),(10,30),(1,24)],DARK);d.ellipse(35,22,13,12,STEEL)
  elif style=='foldgun':d.poly([(0,1),(43,-13),(76,-5),(59,8),(36,10),(22,25),(15,14)],LIGHT);d.poly([(40,-12),(59,-8),(47,5),(30,7)],OWNER)
  else:d.poly([(0,2),(21,-6),(59,-6),(62,3),(84,3),(84,10),(43,12),(35,28),(24,25),(26,12),(0,16)],DARK)
  d.line(65 if style=='assault' else 75,4,105,4,INK,5)
 elif style=='double_tube':
  d.rect(-31,-8,134,19,DARK,7);d.rect(-21,15,124,17,STEEL,6);d.rect(78,-13,25,28,PAPER,2);d.line(18,12,20,28,INK,8)
 elif style=='rocket':
  d.rect(-40,-8,127,22,STEEL,8);d.poly([(84,-11),(115,3),(84,18)],DARK);d.rect(-20,-11,14,28,OWNER);d.rect(5,10,14,19,DARK)
 elif style=='wrench':
  d.rect(2,24,49,39,'#aa9270',4);d.path('M11 24 L17 15 L37 15 L42 24','none',INK,4)
  d.line(43,15,64,-67,STEEL,10);d.poly([(54,-66),(53,-83),(65,-99),(76,-92),(66,-77),(78,-72),(89,-87),(96,-79),(86,-60),(71,-55)],STEEL)
  d.rect(55,25,39,11,DARK);d.rect(64,36,10,16,DARK)
 elif style=='rotary':
  d.ellipse(29,18,25,29,DARK);d.ellipse(30,17,13,18,OWNER);d.rect(27,-8,86,28,STEEL,5)
  for dy in [-3,8,17]:d.line(54,dy,119,dy,INK,4)
  d.rect(90,-11,13,35,DARK);d.line(13,-3,13,-17,INK,7)
 elif style=='lobber':
  d.ellipse(37,19,23,22,DARK);d.rect(28,-8,64,19,STEEL,4);d.ellipse(96,2,11,14,DARK);d.line(7,12,5,34,INK,8)
 elif style=='machinegun':
  d.rect(0,-3,67,19,DARK,3);d.line(52,5,116,5,INK,5);d.rect(32,17,29,26,STEEL,2);d.line(89,9,80,35,DARK,4);d.line(89,9,105,35,DARK,4)
 elif style in ('sniper','longrifle'):
  d.poly([(-20,12),(15,-2),(64,-2),(72,6),(41,13),(29,32),(17,27),(20,13),(-17,24)],'#ad9471')
  d.line(55,4,126,1,INK,5 if style=='longrifle' else 4)
  d.rect(32,-18,44,9,DARK,4);d.line(43,-7,43,-15,INK,4)
  if style=='longrifle':d.ellipse(30,6,14,11,STEEL);d.line(97,4,93,29,DARK,3)
 elif style in ('missile','winglauncher'):
  d.begin('rotate(-28 30 4)' if combat else 'rotate(-43 30 4)')
  if style=='missile':d.rect(-35,-10,143,28,DARK,7);d.poly([(107,-13),(124,3),(107,21)],STEEL);d.rect(16,-22,25,12,STEEL,2)
  else:d.poly([(-31,-11),(11,-24),(111,-12),(122,5),(96,20),(15,23),(-26,15)],LIGHT);d.poly([(26,-25),(48,-12),(22,15),(5,23),(11,-24)],OWNER);d.line(58,-5,113,1,DARK,4)
  d.end()
 elif style=='scanner':
  d.rect(-1,4,56,39,STEEL,4);d.rect(6,10,36,24,DARK,2);d.line(12,25,34,17,OWNER,5);d.line(36,37,51,62,DARK,8);d.line(28,3,15,-25,DARK,5)
 elif style=='detonator':
  d.rect(-1,2,32,25,DARK,3);d.line(15,3,15,-12,INK,4);d.line(8,-12,23,-12,INK,5)
  d.rect(52,13,46,39,'#ac9674',3)
  for x in [60,72,84]:d.rect(x,18,8,26,DARK,2)
  d.path('M29 8 Q45 -9 63 16','none',INK,3)
 elif style=='nailer':
  d.rect(0,-5,61,26,STEEL,5);d.ellipse(26,25,20,18,DARK);d.line(56,5,101,5,INK,7);d.rect(61,-20,28,12,'#b69e78')
  for x in [66,74,82]:d.line(x,-26,x,-8,STEEL,3)
  d.path('M0 12 Q-28 36 -40 11','none','#a88d60',6)
 elif style=='harpoon':
  d.rect(-24,-9,105,21,DARK,5);d.line(69,1,109,1,STEEL,8);d.poly([(107,-13),(126,1),(106,15),(111,1)],'#b5b4a6');d.ellipse(19,18,17,15,'#ae966b')
 elif style=='pickaxe':
  d.line(29,49,54,-90,'#a98c62',10);d.path('M10 -70 Q42 -107 95 -88 L107 -70 Q66 -91 17 -57 Z',STEEL)
  d.rect(57,29,48,34,'#a68e68',3);d.line(64,25,93,25,DARK,5);d.line(43,13,65,29,DARK,4)
 elif style=='mortar':
  d.begin('rotate(-26)');d.rect(-2,-66,31,109,STEEL,5);d.ellipse(13,-65,18,11,DARK);d.rect(0,-19,32,10,OWNER);d.line(9,43,-15,66,DARK,7);d.line(16,43,48,64,DARK,7);d.end()
  d.rect(-9,56,71,12,DARK,2)
 elif style=='foldlauncher':
  d.poly([(-23,-10),(53,-21),(111,-12),(119,17),(62,29),(-24,20)],LIGHT);d.poly([(48,-19),(67,-22),(77,26),(61,29)],OWNER);d.poly([(106,-11),(119,17),(103,21),(95,-8)],DARK);d.line(1,24,5,43,DARK,7)
 elif style=='foldtools':
  d.poly([(-5,-6),(24,-28),(70,-10),(86,17),(34,32),(-5,15)],STEEL);d.poly([(24,-28),(40,-1),(34,32),(-5,15),(-5,-6)],LIGHT);d.line(41,9,81,-37,DARK,7);d.poly([(72,-45),(91,-50),(97,-25),(83,-29)],LIGHT)
 elif style=='pulse':
  d.line(29,55,56,-86,DARK,9);d.path('M51 -84 L30 -102 L19 -80 L24 -56 L47 -49 L61 -62 L76 -89 L66 -105 L60 -82 Z',LIGHT);d.ellipse(46,-75,13,18,OWNER);d.poly([(25,45),(48,35),(52,52),(22,64)],STEEL)
 if lod<2:
  d.line(12,9,24,8,LIGHT,1.5)
 d.end()


def draw(faction,profile,state,lod):
 art,style,hat,width,gear=profile
 d=Drawing(lod);combat=state=='combat';move=state=='move'
 # Individual body proportions remain recognisable with all colour removed.
 left=105-width*.5;right=105+width*.5
 crouch=24 if art in ('grenadier','mortar','demolition') else 18 if art=='marksman' else 0
 d.begin(f'translate(0 {crouch})');backgear(d,faction,gear,width,combat or crouch>0);d.end()
 # Legs have faction/role-specific boots, stride and kneeling arrangements.
 kneel=combat and art in ('marksman','mortar','demolition')
 if crouch and not move:
  d.poly([(80,218),(108,221),(102,248),(60,273),(87,286),(83,302),(49,297),(37,279),(64,237)],PAPER)
  d.poly([(111,218),(137,220),(161,247),(149,273),(175,286),(171,300),(134,300),(124,277),(132,249)],PAPER)
 elif art=='gunner' and not move:
  d.poly([(79,202),(104,205),(96,242),(73,277),(96,288),(90,302),(47,299),(47,278),(67,237)],PAPER)
  d.poly([(111,203),(134,203),(148,241),(153,276),(181,285),(178,301),(135,299),(127,279),(120,246)],PAPER)
 elif art=='engineer' and not move:
  d.poly([(84,203),(106,205),(98,246),(101,280),(119,289),(113,301),(80,297),(77,278),(80,243)],PAPER)
  d.poly([(113,203),(133,203),(129,245),(125,280),(148,291),(143,302),(115,297),(110,280),(108,244)],PAPER)
 elif art in ('anti','aa_infantry') and not move:
  d.poly([(79,202),(105,205),(95,241),(71,280),(94,290),(89,302),(51,295),(47,278),(70,236)],PAPER)
  d.poly([(111,202),(133,203),(141,245),(133,279),(165,286),(161,301),(126,299),(117,280),(118,245)],PAPER)
 elif kneel:
  d.poly([(84,201),(108,205),(102,239),(68,272),(91,287),(85,299),(50,294),(42,276),(75,235)],PAPER)
  d.poly([(111,202),(134,205),(139,240),(155,277),(181,285),(180,297),(144,298),(126,278),(114,244)],PAPER)
 elif move:
  d.poly([(83,204),(107,206),(94,251),(70,280),(91,291),(86,302),(47,290),(43,276),(73,241)],PAPER)
  d.poly([(110,203),(132,205),(143,238),(143,270),(164,286),(158,301),(130,285),(122,271),(120,242)],PAPER)
 else:
  d.poly([(79,202),(105,204),(101,247),(91,278),(111,288),(107,301),(70,300),(65,281),(74,242)],PAPER)
  d.poly([(111,203),(135,203),(139,245),(138,278),(165,286),(162,300),(128,300),(119,281),(119,246)],PAPER)
 d.begin(f'translate(0 {crouch})')
 if faction=='rivet':
  d.rect(69 if not move else 59,246,28,36,STEEL,3);d.rect(118,247,28,35,STEEL,3)
 elif faction=='kestrel':
  d.line(77,208,72 if not move else 58,271,DARK,7);d.line(135,210,138,273,DARK,7)
  d.ellipse(76,236,8,8,STEEL);d.ellipse(133,238,8,8,STEEL)
 elif faction=='iron':
  d.poly([(left+5,162),(right-3,162),(right+8,242),(116,261),(103,233),(85,267),(left-7,248)],'#b6a58a')
  d.poly([(left+8,172),(80,186),(83,246),(left-7,248)],OWNER)
 else:
  d.poly([(left+8,171),(right-5,171),(right+7,228),(109,264),(92,240),(63,251)],LIGHT)
  d.poly([(79,197),(105,217),(92,240),(63,251)],OWNER)
 # Torso, harness and shoulders set faction-level contour language.
 if faction=='rivet':
  d.poly([(left,113),(77,99),(128,100),(right,120),(right-6,209),(left+7,211),(left-8,156)],PAPER)
  d.poly([(left-18,114),(left+8,99),(left+23,123),(left+9,151),(left-20,144)],STEEL)
  d.poly([(right-15,106),(right+13,110),(right+25,143),(right+4,153),(right-8,133)],STEEL)
  d.rect(left+12,144,width-26,49,'#b7ac95',5)
  d.rect(left+15,154,18,33,OWNER,2)
 elif faction=='kestrel':
  d.poly([(left,116),(77,101),(126,101),(right,115),(right-2,205),(left+4,205),(left-7,153)],PAPER)
  d.poly([(left-10,111),(left+15,105),(left+18,124),(left-6,135)],DARK)
  d.poly([(right-18,104),(right+11,112),(right+14,137),(right-5,132)],STEEL)
  d.rect(left+12,142,width-23,42,STEEL,3);d.rect(left+17,145,17,36,OWNER)
  d.line(left+3,132,left+3,203,DARK,6);d.line(right-4,132,right-4,203,DARK,6)
 elif faction=='iron':
  d.poly([(left,113),(77,98),(126,100),(right,119),(right-4,205),(left+3,211),(left-7,155)],PAPER)
  d.poly([(71,99),(100,122),(85,148),(61,119)],'#b6a58a');d.poly([(125,100),(137,128),(108,145),(99,122)],'#b6a58a')
  d.rect(left+15,150,width-22,48,'#9c886c',3);d.rect(left+17,153,17,40,OWNER)
 else:
  d.poly([(left,116),(80,94),(128,105),(right+8,143),(right-6,203),(102,226),(left+1,204)],LIGHT)
  d.poly([(left-18,128),(left-3,86),(left+20,117),(left+10,152)],PAPER)
  d.poly([(right-15,101),(right+29,125),(right+10,157),(right-8,127)],LIGHT)
  d.poly([(80,118),(99,138),(92,192),(71,201)],OWNER)
 # Human neck and exposed face; ink expression survives the far card.
 d.rect(89,84,23,24,SKIN,3)
 d.path('M72 46 Q80 28 105 34 L126 43 L130 57 L143 65 L130 71 L125 87 L107 96 L84 88 L71 72 Z',SKIN)
 d.ellipse(77,66,6,8,SKIN)
 d.line(119,58,129,57,INK,2.2 if lod<2 else 3)
 if lod<2:d.line(119,78,128,77,INK,1.5);d.line(100,88,118,86,INK,1.2)
 helmet(d,faction,hat)
 # Orange seal is fixed; faction/player pigment never encodes specialist role.
 seal=(100,119)
 d.ellipse(*seal,7,7,SEAL)
 if lod==0:d.line(96,119,103,116,DARK,1.2);d.line(101,116,103,122,DARK,1.2)
 # Role-specific front wear remains large enough at far detail.
 if art=='grenadier':
  for x,y in [(80,138),(96,153),(111,168),(126,183)]:d.rect(x,y,11,18,'#b29a73',5)
 if art=='demolition':d.rect(70,181,35,37,'#ae9873',4);d.rect(112,181,34,37,'#ae9873',4)
 if art=='engineer':d.path('M77 141 L126 141 L133 225 L73 225 Z','#b29b78')
 # Weapon heights differ by role, not only by a small painted detail.
 high=style in ('double_tube','rocket','missile','winglauncher','harpoon')
 gy=(130 if high else 168) if state=='idle' else (124 if high else 151) if move else (116 if high else 130) if combat else (147 if high else 178)
 if style in ('pickaxe','pulse','wrench'):gy=175 if not combat else 158
 if style=='mortar':gy=171 if not combat else 190
 d.path(f'M{left+7} 131 L{left+18} 153 L126 {gy+14} L143 {gy+7} L136 {gy-3} L{left+32} 139 L{left+18} 121 Z',PAPER)
 d.path(f'M{right-6} 132 L{right+8} {gy-5} L173 {gy+5} L165 {gy+18} L{right-4} {gy+10} L{right-18} 149 Z',PAPER)
 weapon(d,style,gy,combat,lod)
 d.ellipse(129,gy+11,8,6,SKIN);d.ellipse(165,gy+10,7,6,SKIN)
 if lod<2:
  # Sparse handmade seams; no fine feature is required for role recognition.
  d.line(left+9,185,left+12,204,DARK,1.3)
  for x,y in [(left+2,120),(right+7,122)]:d.ellipse(x,y,2,2,LIGHT)
 if lod==0:
  for x,y in [(left+9,175),(right-9,184),(77,259)]:d.line(x,y,x+4,y-5,'#a99c83',1.2)
 d.end()
 drawing=''.join(d.parts)
 transform=''
 if state=='hit':transform='translate(6 -1) rotate(-5 104 210)'
 if state=='death':transform='translate(122 279) rotate(-87) scale(.67) translate(-106 -187)'
 if transform:drawing=f'<g transform="{transform}">{drawing}</g>'
 svg=f'<svg xmlns="http://www.w3.org/2000/svg" width="256" height="320" viewBox="0 0 256 320"><!-- distinct-role:{faction}_{art}; silhouette:{style}/{hat}/{gear}; lod:{lod} -->{drawing}</svg>'
 mask=f'<svg xmlns="http://www.w3.org/2000/svg" width="256" height="320" viewBox="0 0 256 320"><g'+(f' transform="{transform}"' if transform else '')+f'><ellipse cx="{seal[0]}" cy="{seal[1]+crouch}" rx="6" ry="6" fill="white"/></g></svg>'
 ET.fromstring(svg)
 return svg,mask


def atomic_write(path, text):
 temporary=path.with_name(path.name+".tmp")
 temporary.write_text(text)
 temporary.replace(path)

def generate():
 rules=json.loads((ROOT/'data/rules.json').read_text())
 written=[]
 for faction,profiles in ROSTER.items():
  for profile in profiles:
   key=faction+'_'+profile[0]
   info=rules['units'][key]
   for state in STATES:
    for lod in range(3):
     svg,mask=draw(faction,profile,state,lod)
     destination=OUT/f'{key}_{state}_{lod}.svg'
     atomic_write(destination,svg);atomic_write(destination.with_name(destination.stem+'_identity.svg'),mask);written.append(str(destination.relative_to(ROOT)))
     if lod==0:
      action='attack' if state=='combat' else state
      legacy=ROOT/info['animations'][action].removeprefix('res://')
      atomic_write(legacy,svg);atomic_write(legacy.with_name(legacy.stem+'_identity.svg'),mask)
      if state=='idle':
       portrait=ROOT/info['portrait'].removeprefix('res://')
       atomic_write(portrait,svg);atomic_write(portrait.with_name(portrait.stem+'_identity.svg'),mask)
   
 print(f'Generated {len(written)} role/action/LOD cards, 22 production portraits and live animation aliases')
 atomic_write(OUT/'distinct_roles_manifest.json',json.dumps({'roles':{f:[{'id':f+'_'+p[0],'weapon':p[1],'headgear':p[2],'width':p[3],'backgear':p[4]} for p in ps] for f,ps in ROSTER.items()}},indent=2)+'\n')

if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--contours',action='store_true');args=parser.parse_args()
 generate()
 if args.contours:subprocess.run(['godot','--headless','--path',str(ROOT),'--script','res://tools/register_expanded_infantry_contours.gd'],check=True)
