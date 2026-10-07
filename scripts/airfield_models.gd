extends RefCounted

## Four distinct silhouettes share the same four unobstructed service centres.
## All high structures remain along the outer perimeter of the seven-cell site.
static func make(mesh, faction: String, owner: Color, tier: int) -> Dictionary:
	mesh.detail_tier = tier
	mesh.capture_shell = true
	var paper := Color("e4decb")
	var ink := Color("382a22")
	var brass := Color("b49b71")
	var deck := Color("bcb7a7")
	mesh.slab([Vector2(-3.5,-3.3),Vector2(-3.3,-3.5),Vector2(3.3,-3.5),Vector2(3.5,-3.3),Vector2(3.5,3.3),Vector2(3.3,3.5),Vector2(-3.3,3.5),Vector2(-3.5,3.3)],.18,Vector3(0,.09,0),paper)
	match faction:
		"kestrel":
			# Formal axial runway, two low gatehouses and one slender control tower.
			mesh.box(Vector3(0,.20,0),Vector3(6.65,.08,6.65),deck,false)
			mesh.box(Vector3(0,.255,0),Vector3(1.05,.025,6.40),Color("73776f"),false)
			for side in [-1.0,1.0]:
				mesh.box(Vector3(side*2.55,.62,-3.02),Vector3(1.20,.72,.60),paper)
				mesh.gable(Vector3(side*2.55,1.04,-3.02),1.32,.70,.38,owner)
			mesh.box(Vector3(0,1.07,-3.0),Vector3(.75,1.72,.64),paper)
			mesh.box(Vector3(0,2.08,-3.0),Vector3(1.15,.40,.86),owner)
			mesh.box(Vector3(0,2.1,-2.55),Vector3(.92,.23,.04),Color("759591"),false)
			mesh.gable(Vector3(0,2.33,-3.0),1.25,.97,.29,paper)
			mesh.badge(Vector3(0,1.32,-2.65),faction,owner,Vector3.BACK,.19)
		"rivet":
			# Heavy parallel service lanes and an asymmetric gantry/industrial tower.
			mesh.box(Vector3(0,.22,0),Vector3(6.70,.10,6.70),Color("9f9685"),false)
			for side in [-1.0,1.0]:
				mesh.box(Vector3(side*1.60,.285,0),Vector3(1.85,.025,6.3),deck,false)
				mesh.box(Vector3(side*3.05,.62,2.75),Vector3(.50,.72,.85),owner)
			mesh.box(Vector3(-2.90,1.08,-2.80),Vector3(.72,1.70,1.0),owner)
			mesh.box(Vector3(-2.90,2.03,-2.80),Vector3(.98,.24,1.22),ink)
			mesh.box(Vector3(-2.90,1.51,-2.27),Vector3(.51,.36,.055),Color("759591"),false)
			for x in [-1.9,1.95]: mesh.box(Vector3(x,1.27,-3.10),Vector3(.18,2.12,.22),brass)
			mesh.box(Vector3(0,2.30,-3.10),Vector3(4.18,.29,.44),owner)
			if tier < 2:
				for x in [-1.7,-.8,.1,1.0]: mesh.line(Vector3(x,2.42,-2.86),Vector3(x+.48,2.19,-2.86),.032,ink)
			mesh.badge(Vector3(-2.9,.84,-2.26),faction,owner,Vector3.BACK,.20)
		"iron":
			# Brass circular turntable stands, transverse rail apron and boiler shed.
			mesh.box(Vector3(0,.21,0),Vector3(6.65,.08,6.65),Color("b9ad91"),false)
			for x in [-1.6,1.6]:
				for z in [-1.6,1.6]: mesh.cylinder(Vector3(x,.27,z),1.04,.05,Vector3.UP,deck,16,false)
			for z in [-.18,.18]: mesh.line(Vector3(-3.25,.32,z),Vector3(3.25,.32,z),.038,Color("868783"))
			mesh.box(Vector3(1.0,.81,-3.0),Vector3(3.65,1.2,.62),paper)
			mesh.gable(Vector3(1.0,1.43,-3.0),3.85,.82,.56,owner)
			for x in [-.35,.55,1.45,2.35]:mesh.box(Vector3(x,.93,-2.66),Vector3(.50,.47,.04),ink,false)
			mesh.cylinder(Vector3(-2.85,1.0,-2.85),.43,1.52,Vector3.UP,brass,12)
			mesh.cylinder(Vector3(-2.85,2.05,-2.85),.16,1.05,Vector3.UP,ink,8)
			mesh.cylinder(Vector3(-2.85,2.63,-2.85),.25,.15,Vector3.UP,brass,8)
			mesh.badge(Vector3(1.0,1.55,-2.52),faction,owner,Vector3.BACK,.19)
		"sky":
			# White island decks, open diagonal taxi gaps and a folded wing tower.
			mesh.box(Vector3(0,.20,0),Vector3(6.60,.05,6.60),Color("d4d2c9"),false)
			for x in [-1.6,1.6]:
				for z in [-1.6,1.6]:
					mesh.slab([Vector2(-1.19,-.95),Vector2(-.95,-1.19),Vector2(.95,-1.19),Vector2(1.19,-.95),Vector2(1.19,.95),Vector2(.95,1.19),Vector2(-.95,1.19),Vector2(-1.19,.95)],.08,Vector3(x,.29,z),paper,false)
			mesh.box(Vector3(3.0,1.20,0),Vector3(.57,1.9,1.03),paper)
			mesh.prism([Vector2(-.70,0),Vector2(0,.57),Vector2(.70,0),Vector2(.45,-.09),Vector2(0,.30),Vector2(-.45,-.09)],1.28,Vector3(2.85,2.21,0),owner)
			mesh.box(Vector3(2.68,1.75,0),Vector3(.08,.29,.76),Color("89b8a3"),false)
			for side in [-1.0,1.0]:
				mesh.box(Vector3(side*2.55,.66,-3.05),Vector3(1.30,.73,.52),paper)
				mesh.gable(Vector3(side*2.55,1.04,-3.05),1.42,.67,.48,owner)
			mesh.badge(Vector3(2.65,1.02,0),faction,owner,Vector3.LEFT,.20)
	# Thin painted aprons, rather than a fully saturated slab, identify ownership.
	for x in [-1.6,1.6]:
		for z in [-1.6,1.6]:
			mesh.box(Vector3(x,.345,z+.91),Vector3(1.65,.028,.17),owner,false)
			if tier < 2:
				mesh.box(Vector3(x,.35,z),Vector3(.06,.02,.63),paper,false)
				mesh.box(Vector3(x,.35,z+.31),Vector3(.50,.02,.06),paper,false)
	if tier < 2:
		for z in [-2.4,-1.2,0,1.2,2.4]:mesh.box(Vector3(0,.30,z),Vector3(.07,.02,.39),paper,false)
	return {"body_mesh":mesh.mesh(),"body_border_mesh":mesh.shell_mesh(),"dimensions":Vector3(7,2.85,7),"design":faction+"_distinct_four_stand_airfield","authored_tier":tier,"stand_centers":[Vector2(-1.6,-1.6),Vector2(1.6,-1.6),Vector2(-1.6,1.6),Vector2(1.6,1.6)]}
