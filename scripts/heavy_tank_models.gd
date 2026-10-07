extends RefCounted

# Heavy chassis are authored independently of each faction's ordinary tank.
# +X is forward; the turret and its muzzle remain independently articulated.
const INK := Color("382a22")
const STEEL := Color("a9aea4")
const KRAFT := Color("c9ad7f")
const RUBBER := Color("625849")

static func make(body, faction: String, owner: Color, tier: int = 0) -> Dictionary:
	body.detail_tier=tier
	var volume=load("res://scripts/volume_models.gd")
	var turret=volume.CraftMesh.new()
	turret.detail_tier=tier
	var paint: Color = {"kestrel":Color("2865a5"),"rivet":Color("bb4034"),"iron":Color("bb963e"),"sky":Color("74569d")}.get(faction,owner)
	var base_paint: Color = Color("e9e5dc") if faction == "sky" else paint
	var sections: int = 12 if tier==0 else 8 if tier==1 else 6
	var wheels: int = 7 if tier==0 else 5 if tier==1 else 3
	# Two broad continuous track boxes and their full-length armored skirts.
	for side in [-1.0,1.0]:
		body.prism([Vector2(-1.36,.08),Vector2(1.28,.08),Vector2(1.49,.30),Vector2(1.31,.70),Vector2(-1.27,.70),Vector2(-1.49,.39)],.52,Vector3(0,0,side*1.03),RUBBER,tier==0)
		for i in range(wheels):
			var x: float=lerpf(-1.17,1.16,float(i)/float(wheels-1))
			body.cylinder(Vector3(x,.36,side*1.30),.23,.065,Vector3(0,0,side),STEEL,sections,false)
			if tier==0: body.cylinder(Vector3(x,.36,side*1.35),.075,.05,Vector3(0,0,side),INK,6,false)
		body.prism([Vector2(-1.35,.59),Vector2(1.29,.59),Vector2(1.50,.82),Vector2(1.13,1.02),Vector2(-1.35,.91)],.16,Vector3(0,0,side*1.32),paint)
		if tier<2:
			for x in [-.95,-.33,.29,.91]:
				body.box(Vector3(x,.80,side*1.43),Vector3(.48,.30,.10),KRAFT,tier==0)
		if tier==0:
			for x in [-1.16,-.77,-.38,.01,.40,.79,1.18]:
				body.box(Vector3(x,.10,side*1.05),Vector3(.095,.10,.60),STEEL,false)
	body.prism([Vector2(-1.37,.53),Vector2(1.41,.53),Vector2(1.57,.80),Vector2(.89,1.08),Vector2(-1.27,1.03)],1.92,Vector3.ZERO,base_paint)
	# A real protruding ram and a double glacis distinguish crushing armor.
	body.prism([Vector2(1.26,.28),Vector2(1.62,.35),Vector2(1.60,.56),Vector2(1.38,.75)],2.34,Vector3.ZERO,STEEL)
	body.fixed_box(Vector3(-1.09,1.07,0),Vector3(.54,.17,1.56),volume.faction_color(faction))
	for side in [-1.0,1.0]:
		body.box(Vector3(-1.20,1.17,side*.70),Vector3(.38,.22,.36),STEEL)
		body.badge(Vector3(.14,.83,side*1.51),faction,owner,Vector3(0,0,side),.19)
	if tier==0:
		for z in [-.48,-.24,0,.24,.48]:body.box(Vector3(-1.12,1.17,z),Vector3(.33,.03,.055),INK,false)
	var pivot:=Vector3(-.08,1.13,0)
	var muzzle:=Vector3(1.90,.29,0)
	match faction:
		"kestrel":
			# Broad angular command turret, paired frontal cheeks and long bore.
			turret.prism([Vector2(-.83,0),Vector2(.72,0),Vector2(.83,.27),Vector2(.34,.68),Vector2(-.71,.63)],1.62,Vector3.ZERO,paint)
			for side in [-1.0,1.0]:turret.box(Vector3(.50,.27,side*.64),Vector3(.64,.42,.32),KRAFT)
			turret.cylinder(Vector3(1.22,.30,0),.15,1.28,Vector3.RIGHT,STEEL,sections)
			turret.box(Vector3(1.83,.30,0),Vector3(.24,.29,.36),paint)
			turret.box(Vector3(-.22,.72,0),Vector3(.72,.12,.72),paint)
			muzzle=Vector3(1.96,.30,0)
		"rivet":
			# Tall stepped siege turret with a massive armored short cannon.
			turret.box(Vector3(-.12,.33,0),Vector3(1.72,.64,1.65),paint)
			turret.box(Vector3(-.22,.73,0),Vector3(1.38,.20,1.35),KRAFT)
			turret.box(Vector3(.69,.36,0),Vector3(.39,.62,1.04),STEEL)
			turret.cylinder(Vector3(1.28,.36,0),.25,1.20,Vector3.RIGHT,paint,sections)
			turret.cylinder(Vector3(1.92,.36,0),.29,.17,Vector3.RIGHT,STEEL,sections)
			for side in [-1.0,1.0]:turret.box(Vector3(-.14,.40,side*.89),Vector3(1.13,.40,.17),KRAFT)
			muzzle=Vector3(2.02,.36,0)
		"iron":
			# Low circular bolted cupola and two reinforced parallel cannon tubes.
			turret.cylinder(Vector3(-.19,.25,0),.91,.50,Vector3.UP,paint,sections)
			turret.cylinder(Vector3(-.22,.54,0),.69,.11,Vector3.UP,Color("39847b"),sections)
			turret.box(Vector3(.51,.27,0),Vector3(.54,.45,1.08),STEEL)
			for side in [-1.0,1.0]:
				turret.cylinder(Vector3(1.21,.29,side*.27),.135,1.29,Vector3.RIGHT,paint,sections)
				turret.cylinder(Vector3(1.88,.29,side*.27),.17,.15,Vector3.RIGHT,STEEL,sections)
				if tier==0:
					for x in [-.60,-.10,.40]:turret.cylinder(Vector3(x,.26,side*.88),.045,.05,Vector3(0,0,side),STEEL,6,false)
			muzzle=Vector3(1.97,.29,0)
		"sky":
			# Nested rectangular capacitor turret, shield cheeks and coil barrel.
			turret.box(Vector3(-.12,.30,0),Vector3(1.53,.57,1.60),Color("e9e5dc"))
			turret.box(Vector3(-.21,.66,0),Vector3(1.22,.15,1.27),Color("e9e5dc"))
			for side in [-1.0,1.0]:
				turret.box(Vector3(.31,.36,side*.86),Vector3(1.07,.56,.17),KRAFT)
				body.box(Vector3(.07,1.10,side*.88),Vector3(.82,.20,.18),paint)
			turret.cylinder(Vector3(1.10,.30,0),.16,1.45,Vector3.RIGHT,STEEL,sections)
			var coils: int=4 if tier<2 else 2
			for i in range(coils):turret.cylinder(Vector3(.68+float(i)*.82/float(coils-1),.30,0),.25,.13,Vector3.RIGHT,paint,sections)
			turret.box(Vector3(1.80,.30,0),Vector3(.19,.39,.39),KRAFT)
			muzzle=Vector3(1.90,.30,0)
	# Identification survives the far LOD; fine armor fittings may disappear.
	turret.badge(Vector3(-.27,.86 if faction=="rivet" else .61 if faction=="iron" else .77,0),faction,owner,Vector3.UP,.25)
	for side in [-1.0,1.0]:turret.badge(Vector3(-.16,.33,side*.96),faction,owner,Vector3(0,0,side),.16)
	if tier==0:
		body.line(Vector3(-1.05,1.17,-.67),Vector3(-1.05,1.93,-.67),.025,STEEL)
		turret.box(Vector3(-.52,.82,-.30),Vector3(.27,.17,.27),KRAFT)
	return {"body_mesh":body.mesh(),"turret_mesh":turret.mesh(),"turret_pos":pivot,"muzzle_pos":muzzle,"dimensions":Vector3(4.2,2.1,3.05),"recoil_distance":.12,"design":"heavy_"+faction+"_tier_"+str(tier),"heavy_chassis":true}
