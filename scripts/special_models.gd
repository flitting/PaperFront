extends RefCounted

## Three independent recipes for the new drill, heavy dirigible, locomotive and
## rail shapes. A tier omits small assembly details and changes section counts.
const INK := Color("35312b")
const PAPER := Color("dbd1b7")
const KRAFT := Color("b5966d")
const ARMOR := Color("63584b")
const BRASS := Color("b49b71")
const RAIL := Color("868783")

static func make(mesh, spec: Dictionary, owner: Color, tier: int = 0) -> Dictionary:
	mesh.detail_tier = tier
	match str(spec.art):
		"rail", "rail_junction": return _rail(mesh,spec,owner,tier)
		"drill": return _drill(mesh,owner,tier)
		"zeppelin": return _zeppelin(mesh,owner,tier)
		"armored_train": return _train(mesh,owner,tier)
	return {}

static func _rail(mesh, spec: Dictionary, owner: Color, tier: int) -> Dictionary:
	var mask: int = int(spec.get("rail_mask",5))
	if str(spec.art) == "rail_junction": mask = int(spec.get("rail_ports",mask))
	if mask == 0: mask = 5
	var ports: Array[Vector3] = []
	for entry in [[1,Vector3.RIGHT],[2,Vector3.BACK],[4,Vector3.LEFT],[8,Vector3.FORWARD]]:
		if mask & int(entry[0]): ports.append(entry[1])
	var lines: Array = []
	if ports.size() == 2 and absf(ports[0].dot(ports[1])) < .1:
		# Real quarter-circle rails join perpendicular endpoints continuously.
		var corner: Vector3 = (ports[0]+ports[1])*.5
		var a: Vector3 = ports[0]*.5-corner
		var b: Vector3 = ports[1]*.5-corner
		var count: int = 10 if tier == 0 else 5 if tier == 1 else 3
		var points: Array[Vector3] = []
		for i in range(count+1):
			var angle: float = float(i)/count*PI*.5
			points.append(corner+a*cos(angle)+b*sin(angle))
		for i in range(count): lines.append([points[i],points[i+1]])
	else:
		for port in ports: lines.append([Vector3.ZERO,port*.5])
	var tie_count: int = 6 if tier == 0 else 4 if tier == 1 else 2
	for segment in lines:
		var a: Vector3 = segment[0]
		var b: Vector3 = segment[1]
		var tangent: Vector3 = (b-a).normalized()
		var side: Vector3 = tangent.cross(Vector3.UP)
		for offset in [-.145,.145]: mesh.line(a+side*offset+Vector3(0,.075,0),b+side*offset+Vector3(0,.075,0),.026 if tier == 2 else .023,RAIL)
		if ports.size() == 2 and absf(ports[0].dot(ports[1])) < .1:
			mesh.line(a+Vector3(0,.035,0)-side*.22,a+Vector3(0,.035,0)+side*.22,.036,KRAFT)
		else:
			for i in range(tie_count):
				var p: Vector3 = a.lerp(b,(i+.5)/tie_count)+Vector3(0,.028,0)
				mesh.line(p-side*.22,p+side*.22,.035,KRAFT)
	if str(spec.art) == "rail_junction":
		mesh.box(Vector3(.23,.10,.24),Vector3(.12,.12,.12),owner,false)
		if tier < 2: mesh.line(Vector3(.23,.15,.24),Vector3(.23,.32,.24),.022,ARMOR)
	return {"body_mesh":mesh.mesh(),"dimensions":Vector3(1,.35,1),"design":"rail_%d_tier_%d" % [mask,tier],"rail_mask":mask,"authored_tier":tier}

static func _drill(mesh, owner: Color, tier: int) -> Dictionary:
	# A heavy auger rig: open front, low ore collar, tall tapered derrick and
	# an oversized motor. Original map crystals remain independent underneath.
	var sections: int = 12 if tier == 0 else 8 if tier == 1 else 6
	for x in [-.82,.82]:
		for z in [-.73,.73]:
			mesh.box(Vector3(x,.14,z),Vector3(.36,.22,.40),ARMOR,false)
			mesh.line(Vector3(x,.25,z),Vector3(x*.67,3.53,z*.75),.085,KRAFT)
			mesh.box(Vector3(x,.36,z),Vector3(.24,.17,.27),KRAFT,false)
	# Side shields hug the crystal, with a continuous .45-high root opening.
	for side in [-1.0,1.0]:
		mesh.prism([Vector2(-.54,.50),Vector2(-.67,1.25),Vector2(-.48,1.65),Vector2(.48,1.65),Vector2(.66,1.25),Vector2(.54,.50)],.10,Vector3(0,0,side*.70),owner,false)
		mesh.box(Vector3(side*.78,1.04,0),Vector3(.13,.88,1.35),KRAFT,false)
		# Big hydraulic cylinders are readable even at the coarsest tier.
		mesh.cylinder(Vector3(side*.65,1.85,.57),.12,1.04,Vector3.UP,ARMOR,sections,false)
		mesh.cylinder(Vector3(side*.65,2.52,.57),.065,.52,Vector3.UP,PAPER,sections,false)
		mesh.cylinder(Vector3(side*.65,2.34,.57),.145,.12,Vector3.UP,KRAFT,sections,false)
		mesh.box(Vector3(side*.65,2.83,.51),Vector3(.25,.18,.28),ARMOR,false)
		# Exposed diagonal gussets form a derrick, rather than four shed walls.
		mesh.line(Vector3(side*.80,.63,-.73),Vector3(side*.61,2.15,.54),.055,ARMOR)
		mesh.line(Vector3(side*.76,1.50,.68),Vector3(side*.57,3.36,-.51),.055,KRAFT)
		mesh.line(Vector3(side*.71,2.30,-.62),Vector3(side*.57,3.36,.51),.045,ARMOR)
		mesh.box(Vector3(side*.86,1.13,.21),Vector3(.035,.25,.54),owner,false)
	mesh.badge(Vector3(0,3.14,.66),"rivet",owner,Vector3.BACK,.16)
	# Broad octagonal gearbox with layered corrugated-paper motor casing.
	mesh.box(Vector3(0,3.04,.06),Vector3(1.34,.48,1.12),owner,tier == 0)
	mesh.cylinder(Vector3(0,3.42,.06),.49,.46,Vector3.UP,KRAFT,sections,false)
	mesh.cylinder(Vector3(0,3.69,.06),.57,.13,Vector3.UP,ARMOR,sections,false)
	mesh.cylinder(Vector3(0,3.80,.06),.28,.10,Vector3.UP,KRAFT,sections,false)
	mesh.cylinder(Vector3(0,2.79,.22),.30,.22,Vector3.UP,KRAFT,sections,false)
	mesh.box(Vector3(0,3.12,.637),Vector3(.68,.14,.024),owner,false)
	mesh.line(Vector3(-.59,3.40,-.54),Vector3(.59,3.40,-.54),.072,ARMOR)
	# Twin rolled-paper return pipes; wide bends remain visible at medium LOD.
	for side in [-1.0,1.0]:
		mesh.line(Vector3(side*.46,3.15,-.42),Vector3(side*.79,2.84,-.54),.065,ARMOR)
		mesh.line(Vector3(side*.79,2.84,-.54),Vector3(side*.86,1.45,-.49),.065,ARMOR)
		mesh.line(Vector3(side*.86,1.45,-.49),Vector3(side*.59,1.10,-.42),.065,ARMOR)
	if tier < 2:
		for x in [-.43,-.21,0,.21,.43]:
			mesh.box(Vector3(x,3.42,.505),Vector3(.075,.31,.095),ARMOR,false)
		for y in [.64,.86,1.08,1.30]:
			mesh.line(Vector3(-.80,y,-.75),Vector3(-.40,y,-.75),.025,PAPER)
		for side in [-1.0,1.0]:
			for y in [1.44,2.24]:mesh.cylinder(Vector3(side*.65,y,.57),.135,.10,Vector3.UP,KRAFT,8,false)
	if tier == 0:
		# Thick cut edges and rivet heads sell the assembled cardboard material.
		for x in [-.54,.54]:
			for y in [2.90,3.18]:mesh.cylinder(Vector3(x,y,.628),.044,.035,Vector3.BACK,PAPER,6,false)
		for side in [-1.0,1.0]:
			for z in [-.43,0,.43]:mesh.line(Vector3(side*.852,.61,z),Vector3(side*.852,1.43,z),.012,ARMOR)
	# A continuous helical cutting flight, NOT a stack of disconnected rings.
	var spindle = load("res://scripts/volume_models.gd").CraftMesh.new()
	spindle.detail_tier = tier
	spindle.cylinder(Vector3(0,-.88,0),.135,1.88,Vector3.UP,ARMOR,sections,false)
	_drill_flight(spindle,tier)
	# Tapered chisel crown extends below the flight into the actual crystal.
	for i in range(sections):
		var a: float = float(i)/sections*TAU
		var b: float = float(i+1)/sections*TAU
		var p0 := Vector3(cos(a)*.34,-1.65,sin(a)*.34)
		var p1 := Vector3(cos(b)*.34,-1.65,sin(b)*.34)
		var tip := Vector3(0,-2.09,0)
		spindle.triangle(p0,p1,tip,KRAFT if i%2 else ARMOR,(p1-p0).cross(tip-p0).normalized())
		if i%2 == 0:spindle.line(p0,p0.lerp(tip,.73),.043,PAPER)
	var wheel = load("res://scripts/volume_models.gd").CraftMesh.new()
	wheel.detail_tier = tier
	_drill_flywheel(wheel,tier)
	var damage = load("res://scripts/volume_models.gd").CraftMesh.new()
	damage.detail_tier = tier
	damage.prism([Vector2(-.38,.14),Vector2(-.19,-.16),Vector2(-.10,.02),Vector2(.03,-.23),Vector2(.22,.08),Vector2(.37,-.03),Vector2(.29,.21)],.035,Vector3(0,0,.025),INK,false)
	if tier < 2:
		damage.line(Vector3(-.30,-.20,.04),Vector3(-.06,-.37,.04),.028,INK)
		damage.line(Vector3(-.06,-.37,.04),Vector3(.21,-.30,.04),.028,INK)
	return {"body_mesh":mesh.mesh(),"parts":[
		{"name":"MineSpindle","mesh":spindle.mesh(),"pivot":Vector3(0,2.79,.22),"role":"mine_spindle"},
		{"name":"DrillDamage","mesh":damage.mesh(),"pivot":Vector3(0,3.03,.647),"role":"drill_damage"},
		{"name":"DrillFlywheel","mesh":wheel.mesh(),"pivot":Vector3(.74,2.70,.02),"role":"mine_flywheel"}
	],"dimensions":Vector3(2.0,3.89,1.90),"design":"hammer_heavy_helical_auger_derrick","authored_tier":tier}

static func _drill_flight(mesh, tier: int) -> void:
	var segments: int = 66 if tier == 0 else 36 if tier == 1 else 21
	var turns: float = 3.0
	for i in range(segments):
		var t0: float = float(i)/segments
		var t1: float = float(i+1)/segments
		var a: float = t0*TAU*turns
		var b: float = t1*TAU*turns
		var y0: float = -.13-t0*1.52
		var y1: float = -.13-t1*1.52
		var p0 := Vector3(cos(a)*.135,y0,sin(a)*.135)
		var p1 := Vector3(cos(a)*.40,y0,sin(a)*.40)
		var p2 := Vector3(cos(b)*.40,y1,sin(b)*.40)
		var p3 := Vector3(cos(b)*.135,y1,sin(b)*.135)
		var normal: Vector3 = (p1-p0).cross(p3-p0).normalized()
		if normal.y < 0: normal = -normal
		mesh.face([p0,p1,p2,p3],PAPER,normal)
		var thickness := Vector3(0,-.068,0)
		mesh.face([p3+thickness,p2+thickness,p1+thickness,p0+thickness],ARMOR,-normal)
		mesh.face([p1,p1+thickness,p2+thickness,p2],KRAFT,Vector3(cos((a+b)*.5),0,sin((a+b)*.5)))

static func _drill_flywheel(mesh, tier: int) -> void:
	var sections: int = 16 if tier == 0 else 10 if tier == 1 else 6
	mesh.cylinder(Vector3.ZERO,.12,.31,Vector3.RIGHT,KRAFT,sections,false)
	for i in range(sections):
		var a: float = float(i)/sections*TAU
		var b: float = float(i+1)/sections*TAU
		mesh.line(Vector3(0,cos(a)*.36,sin(a)*.36),Vector3(0,cos(b)*.36,sin(b)*.36),.078,ARMOR)
		if i%2 == 0:
			mesh.line(Vector3.ZERO,Vector3(0,cos(a)*.33,sin(a)*.33),.042,KRAFT)
			mesh.box(Vector3(0,cos(a)*.425,sin(a)*.425),Vector3(.17,.12,.12),KRAFT,false)

static func _zeppelin(mesh, owner: Color, tier: int) -> Dictionary:
	# Faceted kraft envelope, broad fins and a suspended armored bomb cradle.
	var sections: int = 12 if tier == 0 else 8 if tier == 1 else 6
	var rings: Array = [[-.49,.07],[-.36,.22],[-.12,.27],[.20,.25],[.40,.16],[.51,.025]] if tier == 0 else [[-.49,.07],[-.29,.245],[.18,.26],[.49,.04]]
	for ring in range(rings.size()-1):
		for j in range(sections):
			var aa: float = float(j)/sections*TAU
			var ab: float = float(j+1)/sections*TAU
			var x0: float = rings[ring][0]
			var x1: float = rings[ring+1][0]
			var r0: float = rings[ring][1]
			var r1: float = rings[ring+1][1]
			var p0:=Vector3(x0,.44+cos(aa)*r0,sin(aa)*r0)
			var p1:=Vector3(x1,.44+cos(aa)*r1,sin(aa)*r1)
			var p2:=Vector3(x1,.44+cos(ab)*r1,sin(ab)*r1)
			var p3:=Vector3(x0,.44+cos(ab)*r0,sin(ab)*r0)
			mesh.face([p0,p1,p2,p3],owner if j in [2,3,8,9] else PAPER if j%3 else KRAFT,Vector3(0,cos((aa+ab)*.5),sin((aa+ab)*.5)))
			if tier == 0 and j%3 == 0: mesh.line(p0,p1,.005,ARMOR)
	for side in [-1.0,1.0]:
		mesh.slab([Vector2(-.46,side*.04),Vector2(-.25,side*.10),Vector2(-.49,side*.38),Vector2(-.54,side*.29)],.025,Vector3(0,.43,0),owner,false)
		mesh.line(Vector3(-.17,.26,side*.13),Vector3(-.09,.12,side*.09),.013,ARMOR)
		mesh.cylinder(Vector3(.07,.25,side*.27),.065,.19,Vector3.RIGHT,ARMOR,8,false)
		if tier < 2: mesh.line(Vector3(.18,.25,side*.27-.10),Vector3(.18,.25,side*.27+.10),.013,KRAFT)
	mesh.prism([Vector2(-.30,0),Vector2(-.30,.13),Vector2(.26,.13),Vector2(.32,.05),Vector2(.22,0)],.20,Vector3(0,.045,0),ARMOR,false)
	mesh.badge(Vector3(.01,.15,.115),"rivet",owner,Vector3.BACK,.035)
	if tier < 2:
		for x in [-.20,-.06,.09]: mesh.cylinder(Vector3(x,.02,0),.032,.16,Vector3.BACK,KRAFT,6,false)
	# Dorsal machine gun is a separately aimed part, above the envelope.
	var mg = load("res://scripts/volume_models.gd").CraftMesh.new()
	mg.detail_tier = tier
	mesh.cylinder(Vector3(.08,.74,0),.065,.07,Vector3.UP,ARMOR,8,false)
	mg.box(Vector3.ZERO,Vector3(.14,.10,.16),ARMOR,false)
	mg.cylinder(Vector3(.15,.025,0),.020,.25,Vector3.RIGHT,BRASS,8,false)
	if tier < 2:
		mg.box(Vector3(-.03,.075,0),Vector3(.12,.075,.10),KRAFT,false)
		mg.cylinder(Vector3(.275,.025,0),.026,.045,Vector3.RIGHT,INK,6,false)
	return {"body_mesh":mesh.mesh(),"muzzle_pos":Vector3(0,.025,0),"dimensions":Vector3(1.1,.88,.81),"design":"hammer_fortress_dirigible","authored_tier":tier,"parts":[{"name":"DorsalMachineGun","role":"zeppelin_mg","mesh":mg.mesh(),"pivot":Vector3(.08,.78,0)}]}


static func _train(mesh, owner: Color, tier: int) -> Dictionary:
	# One long steam locomotive: driving wheels, boiler bands, brass pipework,
	# folded-paper cab and a traversing artillery cradle share Iron's materials.
	mesh.capture_shell = true
	mesh.box(Vector3(0,.48,0),Vector3(6.65,.28,1.65),ARMOR)
	mesh.box(Vector3(0,.70,0),Vector3(6.35,.13,1.88),PAPER)
	for side in [-1.0,1.0]:
		for x in [-2.46,-1.38,-.30,.78,1.86]:
			mesh.cylinder(Vector3(x,.40,side*.82),.38,.16,Vector3.BACK,INK,12)
			mesh.cylinder(Vector3(x,.40,side*.92),.28,.045,Vector3.BACK,BRASS,10,false)
			mesh.cylinder(Vector3(x,.40,side*.955),.10,.065,Vector3.BACK,ARMOR,8,false)
			if tier == 0:
				for spoke in range(6):
					var a: float = spoke*TAU/6.0
					mesh.line(Vector3(x,.40,side*.975),Vector3(x+cos(a)*.25,.40+sin(a)*.25,side*.975),.025,PAPER)
		mesh.line(Vector3(-2.46,.43,side*1.01),Vector3(1.86,.43,side*1.01),.048,BRASS)
		mesh.box(Vector3(-.20,.82,side*.86),Vector3(5.8,.17,.19),owner)
	# Boiler has a heavy front smoke box, cream paper casing and separate hoops.
	mesh.cylinder(Vector3(.30,1.29,0),.58,3.95,Vector3.RIGHT,PAPER,16)
	mesh.cylinder(Vector3(2.22,1.29,0),.61,.62,Vector3.RIGHT,ARMOR,16)
	mesh.cylinder(Vector3(2.56,1.29,0),.47,.09,Vector3.RIGHT,BRASS,14)
	mesh.cylinder(Vector3(2.62,1.29,0),.35,.06,Vector3.RIGHT,INK,12)
	for x in [-1.42,-.60,.25,1.08,1.72]:mesh.cylinder(Vector3(x,1.29,0),.60,.085,Vector3.RIGHT,BRASS,16,false)
	mesh.box(Vector3(-2.33,1.43,0),Vector3(1.45,1.41,1.68),owner)
	mesh.gable(Vector3(-2.33,2.17,0),1.74,1.86,.20,Color("39847b"))
	for side in [-1.0,1.0]:
		mesh.box(Vector3(-2.27,1.77,side*.86),Vector3(.82,.47,.05),INK,false)
		mesh.box(Vector3(-2.27,1.79,side*.893),Vector3(.66,.34,.02),Color("718881"),false)
		mesh.line(Vector3(-2.27,1.59,side*.91),Vector3(-2.27,1.98,side*.91),.026,BRASS)
		mesh.badge(Vector3(-2.35,1.17,side*.885),"iron",owner,Vector3(0,0,side),.22)
		mesh.line(Vector3(-1.42,1.61,side*.49),Vector3(1.83,1.61,side*.49),.045,BRASS)
		mesh.line(Vector3(1.83,1.61,side*.49),Vector3(2.12,.91,side*.49),.045,BRASS)
		mesh.box(Vector3(-2.66,.64,side*1.02),Vector3(.63,.12,.36),BRASS)
	# Flared chimney and dome silhouette remain readable at every detail tier.
	mesh.cylinder(Vector3(1.80,2.03,0),.16,.81,Vector3.UP,ARMOR,10)
	mesh.cylinder(Vector3(1.80,2.45,0),.27,.14,Vector3.UP,BRASS,12)
	mesh.cylinder(Vector3(-1.01,1.96,0),.23,.27,Vector3.UP,BRASS,12)
	mesh.prism([Vector2(-.16,0),Vector2(.52,.04),Vector2(.23,.47),Vector2(-.16,.47)],1.95,Vector3(2.91,.30,0),ARMOR)
	if tier < 2:
		for z in [-.76,-.38,0,.38,.76]:mesh.line(Vector3(3.39,.36,z),Vector3(3.12,.72,z),.027,BRASS)
		for x in [-2.89,2.86]:
			mesh.cylinder(Vector3(x,.72,0),.105,.22,Vector3.RIGHT,BRASS,8)
		mesh.cylinder(Vector3(2.69,1.60,0),.14,.10,Vector3.RIGHT,PAPER,10)
	# Two full armoured combat coaches follow the locomotive on real bogies.
	for car_index in range(2):
		var x: float = -5.65-car_index*4.15
		mesh.box(Vector3(x,.55,0),Vector3(3.83,.29,1.83),ARMOR)
		mesh.box(Vector3(x,.78,0),Vector3(3.65,.14,2.03),BRASS)
		mesh.prism([Vector2(-1.70,.72),Vector2(-1.56,1.42),Vector2(1.35,1.42),Vector2(1.70,.94),Vector2(1.70,.72)],1.71,Vector3(x,0,0),Color("39847b"))
		for side in [-1.0,1.0]:
			for wheel_x in [-1.31,-.88,.88,1.31]:
				mesh.cylinder(Vector3(x+wheel_x,.40,side*.93),.34,.16,Vector3.BACK,INK,10)
				mesh.cylinder(Vector3(x+wheel_x,.40,side*1.025),.23,.05,Vector3.BACK,BRASS,8,false)
			mesh.box(Vector3(x,1.04,side*.90),Vector3(2.75,.24,.065),owner,false)
			for panel in [-1.18,-.40,.40,1.18]:
				mesh.box(Vector3(x+panel,1.25,side*.91),Vector3(.34,.13,.08),INK,false)
				if tier < 2:mesh.line(Vector3(x+panel-.18,.80,side*.95),Vector3(x+panel-.18,1.37,side*.95),.018,BRASS)
			mesh.badge(Vector3(x,1.08,side*.97),"iron",owner,Vector3(0,0,side),.19)
		mesh.box(Vector3(x+2.01,.50,0),Vector3(.52,.16,.27),BRASS)
		mesh.cylinder(Vector3(x-.15,1.51,0),.65,.18,Vector3.UP,BRASS,12)
		if car_index == 0:
			mesh.prism([Vector2(-.79,0),Vector2(-.61,.65),Vector2(.37,.72),Vector2(.69,.36),Vector2(.70,0)],1.27,Vector3(x-.15,1.60,0),owner)
			mesh.cylinder(Vector3(x+1.05,2.04,0),.16,2.06,Vector3.RIGHT,ARMOR,12)
			mesh.cylinder(Vector3(x+2.12,2.04,0),.22,.19,Vector3.RIGHT,BRASS,10)
			mesh.cylinder(Vector3(x+2.225,2.04,0),.12,.025,Vector3.RIGHT,INK,8,false)
			mesh.fixed_box(Vector3(x-.25,2.27,0),Vector3(.72,.12,.84),Color("39847b"))
		else:
			mesh.box(Vector3(x-.13,1.86,0),Vector3(1.02,.62,1.24),owner)
			for side in [-1.0,1.0]:
				mesh.cylinder(Vector3(x+.56,2.25,side*.27),.09,1.35,Vector3(.88,.48,0),ARMOR,10)
			mesh.box(Vector3(x-.37,2.23,0),Vector3(.62,.10,.79),PAPER)
			mesh.line(Vector3(x-1.23,1.41,0),Vector3(x-1.23,2.68,0),.045,BRASS)
			mesh.box(Vector3(x-1.23,2.69,0),Vector3(.13,.28,.68),Color("39847b"))
	# A single long main cannon in a faceted open cradle, not a box of tubes.
	var gun = load("res://scripts/volume_models.gd").CraftMesh.new()
	gun.detail_tier = tier
	gun.capture_shell = true
	gun.cylinder(Vector3.ZERO,.46,.15,Vector3.UP,BRASS,12)
	for side in [-1.0,1.0]:
		gun.prism([Vector2(-.46,0),Vector2(-.37,.42),Vector2(.30,.42),Vector2(.44,0)],.16,Vector3(0,.06,side*.34),owner)
	gun.cylinder(Vector3(.70,.36,0),.125,2.09,Vector3.RIGHT,ARMOR,12)
	gun.cylinder(Vector3(-.20,.36,0),.22,.49,Vector3.RIGHT,BRASS,12)
	gun.cylinder(Vector3(1.76,.36,0),.18,.19,Vector3.RIGHT,BRASS,10)
	gun.cylinder(Vector3(1.87,.36,0),.115,.025,Vector3.RIGHT,INK,10,false)
	gun.badge(Vector3(-.08,.34,.435),"iron",owner,Vector3.BACK,.13)
	# Centre the complete consist over its unchanged logical two-cell anchor.
	var center_offset := Vector3(4.22,0,0)
	for index in range(mesh.vertices.size()):mesh.vertices[index] += center_offset
	for index in range(mesh.shell_vertices.size()):mesh.shell_vertices[index] += center_offset
	return {"body_mesh":mesh.mesh(),"body_border_mesh":mesh.shell_mesh(),"turret_mesh":gun.mesh(),"turret_border_mesh":gun.shell_mesh(),"turret_pos":Vector3(-.08,1.91,0)+center_offset,"muzzle_pos":Vector3(1.91,.36,0),"dimensions":Vector3(15.8,2.75,2.2),"design":"iron_three_section_armoured_battle_train","authored_tier":tier,"carriage_count":3}
