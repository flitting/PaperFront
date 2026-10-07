extends RefCounted
## New fleet silhouettes use the same folded paperboard and black ink solids.
const SHIPS=preload("res://scripts/naval_models.gd")
const PAPER=Color("e8e3d9")
const EDGE=Color("4c4741")
const METAL=Color("a5a9a5")
const GLASS=Color("7099a0")
const GOLD=Color("f4b437")

static func make(mesh,art:String,faction:String,team:int,kind:String)->Dictionary:
	if kind!="unit" or art not in ["recon","helicopter","naval_submarine","naval_amphibious","naval_hovercraft","naval_support","naval_carrier","naval_aa"]:return {}
	var owner:Color=load("res://scripts/volume_models.gd").player_color(team)
	var trim:Color=PAPER.lerp(load("res://scripts/volume_models.gd").faction_color(faction),.42)
	mesh.capture_shell=true
	var gun=null
	var pivot:=Vector3.ZERO
	var muzzle:=Vector3.ZERO
	match art:
		"recon":
			# A long straight observation wing, two independent tail booms and an
			# elevated rotating-scan radome distinguish this unarmed survey plane.
			mesh.prism([Vector2(-1.18,.35),Vector2(-.70,.64),Vector2(.77,.63),Vector2(1.63,.39),Vector2(.84,.22),Vector2(-.89,.22)],.60,Vector3.ZERO,PAPER)
			mesh.slab([Vector2(-.39,-2.15),Vector2(.32,-2.15),Vector2(.58,-.34),Vector2(.58,.34),Vector2(.32,2.15),Vector2(-.39,2.15)],.13,Vector3(-.08,.48,0),PAPER)
			for side in [-1.0,1.0]:
				mesh.box(Vector3(-.30,.56,side*1.70),Vector3(.20,.028,.70),owner)
				mesh.prism([Vector2(-1.98,.26),Vector2(-1.75,.43),Vector2(.59,.45),Vector2(.93,.31),Vector2(.47,.19),Vector2(-1.76,.19)],.22,Vector3(0,0,side*.80),trim)
				mesh.cylinder(Vector3(.64,.41,side*.80),.17,.75,Vector3.RIGHT,EDGE,10)
				mesh.cylinder(Vector3(1.05,.41,side*.80),.20,.06,Vector3.RIGHT,METAL,10)
				mesh.box(Vector3(1.09,.41,side*.80),Vector3(.035,.83,.075),EDGE)
				mesh.prism([Vector2(-.35,0),Vector2(-.26,.57),Vector2(.06,.57),Vector2(.24,0)],.10,Vector3(-1.63,.43,side*.80),owner)
				mesh.badge(Vector3(-.04,.56,side*1.34),faction,GOLD,Vector3.UP,.21)
			mesh.box(Vector3(-1.67,.49,0),Vector3(.38,.105,1.95),PAPER)
			mesh.prism([Vector2(-.29,0),Vector2(-.09,.23),Vector2(.36,.16),Vector2(.55,0)],.47,Vector3(.56,.64,0),GLASS)
			mesh.box(Vector3(-.45,.77,0),Vector3(.12,.53,.18),EDGE)
			mesh.box(Vector3(.21,.77,0),Vector3(.12,.53,.18),EDGE)
			mesh.cylinder(Vector3(-.12,1.12,0),.64,.15,Vector3.UP,EDGE,20)
			mesh.cylinder(Vector3(-.12,1.205,0),.62,.065,Vector3.UP,PAPER,20)
			mesh.box(Vector3(-.12,1.247,0),Vector3(.92,.02,.11),owner)
			mesh.cylinder(Vector3(1.19,.23,0),.13,.32,Vector3.DOWN,METAL,10)
			mesh.cylinder(Vector3(1.19,.052,0),.095,.025,Vector3.DOWN,GLASS,10)
		"helicopter":
			mesh.box(Vector3(.1,.55,0),Vector3(1.95,.8,.84),PAPER)
			mesh.box(Vector3(.76,.66,0),Vector3(.66,.52,.87),GLASS)
			mesh.box(Vector3(-.32,1.02,0),Vector3(.83,.18,.65),owner)
			mesh.cylinder(Vector3(-1.23,.62,0),.12,1.4,Vector3.RIGHT,trim,8)
			mesh.box(Vector3(-1.92,.99,0),Vector3(.33,.98,.10),trim)
			mesh.box(Vector3(-1.67,.66,0),Vector3(.30,.10,1.0),PAPER)
			mesh.cylinder(Vector3(-.12,1.22,0),.07,.4,Vector3.UP,EDGE,8)
			mesh.box(Vector3(-.12,1.43,0),Vector3(3.65,.045,.13),EDGE)
			mesh.box(Vector3(-.12,1.44,0),Vector3(.13,.045,3.65),METAL)
			for side in [-1.0,1.0]:
				mesh.box(Vector3(0,.03,side*.59),Vector3(2.12,.08,.08),EDGE)
				mesh.line(Vector3(-.5,.11,side*.59),Vector3(-.5,.43,side*.35),.055,METAL)
				mesh.line(Vector3(.65,.11,side*.59),Vector3(.65,.43,side*.35),.055,METAL)
				mesh.box(Vector3(-.05,.37,side*.65),Vector3(.83,.23,.32),trim)
				mesh.badge(Vector3(.10,.65,side*.43),faction,GOLD,Vector3(0,0,side),.19)
			if faction=="rivet":mesh.box(Vector3(-.45,.80,0),Vector3(.64,.48,1.02),trim)
			elif faction=="iron":
				for x in [-.6,-.2,.2]:mesh.box(Vector3(x,.77,.45),Vector3(.05,.28,.04),METAL)
			elif faction=="sky":mesh.box(Vector3(-.3,.6,0),Vector3(.50,.07,1.6),PAPER)
		"naval_submarine":
			SHIPS._hull(mesh,4.8,1.05,trim,METAL)
			mesh.box(Vector3(-.30,.89,0),Vector3(1.1,.60,.56),PAPER)
			mesh.box(Vector3(-.22,1.24,0),Vector3(.74,.12,.64),owner)
			mesh.cylinder(Vector3(-.20,1.55,0),.055,.65,Vector3.UP,EDGE,8)
			mesh.cylinder(Vector3(-.08,1.85,0),.055,.32,Vector3.RIGHT,METAL,8)
			mesh.box(Vector3(-1.9,.34,0),Vector3(.44,.08,1.6),EDGE)
			for side in [-1.0,1.0]:mesh.cylinder(Vector3(1.75,.43,side*.23),.10,.5,Vector3.RIGHT,EDGE,8)
			mesh.badge(Vector3(-.3,.88,.30),faction,GOLD,Vector3.BACK,.19)
		"naval_amphibious":
			SHIPS._hull(mesh,3.0,1.65,PAPER,trim)
			for side in [-1.0,1.0]:
				mesh.box(Vector3(-.1,.18,side*.77),Vector3(2.6,.53,.30),EDGE)
				for x in [-.95,-.45,.05,.55,1.05]:mesh.cylinder(Vector3(x,.21,side*.95),.20,.06,Vector3.BACK,METAL,8)
			mesh.box(Vector3(-.20,.79,0),Vector3(1.45,.21,1.3),trim)
			mesh.box(Vector3(-.88,1.03,0),Vector3(.40,.30,.70),owner)
			gun=load("res://scripts/volume_models.gd").CraftMesh.new()
			gun.capture_shell=true
			pivot=Vector3(.26,.93,0)
			gun.box(Vector3.ZERO,Vector3(.77,.34,.64),PAPER)
			gun.cylinder(Vector3(.66,.04,0),.075,.96,Vector3.RIGHT,EDGE,8)
			muzzle=Vector3(1.15,.04,0)
			mesh.badge(Vector3(-.20,.62,.84),faction,GOLD,Vector3.BACK,.22)
		"naval_hovercraft":
			mesh.box(Vector3(0,.14,0),Vector3(3.6,.48,1.94),EDGE)
			mesh.box(Vector3(.05,.43,0),Vector3(3.42,.19,1.8),PAPER)
			mesh.box(Vector3(-.15,.69,0),Vector3(2.45,.36,1.40),trim)
			mesh.box(Vector3(-.55,1.09,0),Vector3(1.25,.47,1.16),PAPER)
			mesh.box(Vector3(-.06,1.1,0),Vector3(.12,.29,1.19),GLASS)
			mesh.box(Vector3(1.2,.50,0),Vector3(.82,.13,1.35),owner)
			for side in [-1.0,1.0]:
				mesh.cylinder(Vector3(-1.24,1.1,side*.58),.42,.32,Vector3.RIGHT,EDGE,12)
				mesh.cylinder(Vector3(-1.43,1.1,side*.58),.29,.035,Vector3.RIGHT,METAL,12)
				mesh.badge(Vector3(-.5,1.1,side*.59),faction,GOLD,Vector3(0,0,side),.18)
		"naval_aa":
			SHIPS._hull(mesh,5.1,1.78,PAPER,trim)
			SHIPS._deck(mesh,5.1,1.78,faction,"frigate",PAPER,trim,owner)
			mesh.box(Vector3(-.65,1.70,0),Vector3(.83,.25,.97),owner)
			mesh.line(Vector3(-.70,1.82,0),Vector3(-.70,2.72,0),.055,EDGE)
			mesh.cylinder(Vector3(-.70,2.76,0),.40,.09,Vector3.BACK,METAL,12)
			for station in [-1.65,1.38]:
				mesh.cylinder(Vector3(station,.94,0),.48,.19,Vector3.UP,trim,12)
				mesh.box(Vector3(station,1.19,0),Vector3(.79,.43,.93),owner)
				for side in [-1.0,1.0]:
					mesh.cylinder(Vector3(station+.26,1.63,side*.24),.07,1.27,Vector3(.55,.83,0),EDGE,8)
			mesh.badge(Vector3(-.63,1.48,.58),faction,GOLD,Vector3.BACK,.21)
		"naval_support":
			SHIPS._hull(mesh,6.6,1.9,PAPER,trim)
			SHIPS._deck(mesh,6.6,1.9,faction,"frigate",PAPER,trim,owner)
			for side in [-1.0,1.0]:mesh.box(Vector3(-.6,.53,side*.93),Vector3(2.25,.24,.045),owner,false)
			gun=load("res://scripts/volume_models.gd").CraftMesh.new()
			gun.capture_shell=true
			pivot=Vector3(1.2,.96,0)
			gun.box(Vector3.ZERO,Vector3(1.3,.65,1.1),trim)
			for side in [-1.0,1.0]:gun.cylinder(Vector3(1.3,.17,side*.23),.13,2.4,Vector3.RIGHT,EDGE,10)
			muzzle=Vector3(2.52,.17,0)
			mesh.badge(Vector3(-.65,1.45,1.0),faction,GOLD,Vector3.BACK,.26)
		"naval_carrier":
			SHIPS._hull(mesh,7.1,2.15,PAPER,trim)
			mesh.box(Vector3(0,.87,0),Vector3(6.8,.23,2.60),EDGE)
			mesh.box(Vector3(0,1.0,0),Vector3(6.65,.045,2.45),PAPER)
			for x in [-2.5,-1.5,-.5,.5,1.5,2.5]:mesh.box(Vector3(x,1.03,-.15),Vector3(.6,.018,.08),owner)
			mesh.box(Vector3(-1.1,1.5,.88),Vector3(1.52,1,.5),trim)
			mesh.box(Vector3(-.85,1.91,.88),Vector3(1.1,.27,.60),GLASS)
			mesh.box(Vector3(-1.1,2.18,.88),Vector3(1.5,.16,.72),PAPER)
			mesh.cylinder(Vector3(-1.3,2.53,.88),.06,.55,Vector3.UP,EDGE,8)
			mesh.box(Vector3(-1.3,2.83,.88),Vector3(.60,.10,.26),owner)
			for x in [-2.5,-1.6]:
				mesh.box(Vector3(x,1.17,-.83),Vector3(.78,.17,.18),trim)
				mesh.box(Vector3(x-.10,1.20,-.83),Vector3(.24,.055,.77),METAL)
			mesh.badge(Vector3(-1.10,1.53,1.16),faction,GOLD,Vector3.BACK,.24)
	return SHIPS._finish(mesh,faction,art,kind,gun,pivot,muzzle)
