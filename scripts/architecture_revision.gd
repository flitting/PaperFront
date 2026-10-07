extends RefCounted

## Buildings share construction techniques, never a pasted-on entrance.
## All public entrances face +Z; vessel slipways intentionally face +X.
## Geometry is authored in final world metres. Moving parts are small equipment.
const PAPER = Color("e6d5af")
const KRAFT = Color("c9ad7f")
const INK = Color("382a22")
const STEEL = Color("a9aea4")
const GLASS = Color("759591")
const PAINT = {"kestrel":Color("2865a5"),"rivet":Color("bb4034"),"iron":Color("bb963e"),"sky":Color("e9e5dc")}
const ARTS = ["hq","outpost","power","factory","refinery","barracks","repair","tech","advanced_power","advanced_tower","aa_tower","shipyard"]

static func handles(art: String) -> bool:
	return art in ARTS

static func _mesh(tier: int):
	var result = load("res://scripts/volume_models.gd").CraftMesh.new()
	result.detail_tier = tier
	result.capture_shell = true
	return result

static func make(spec: Dictionary, faction: String, owner: Color, tier: int) -> Dictionary:
	var art: String = str(spec.art)
	var size: float = float(spec.get("size",3))*.96
	var m = _mesh(tier)
	var parts: Array = []
	var meta: Dictionary = {}
	var paint: Color = PAINT[faction]
	if art == "refinery" and faction in ["iron","sky"]:
		meta = _refinery_complex(m,parts,faction,owner,size,tier)
	elif art == "shipyard":
		_shipyard(m,parts,faction,owner,size,tier)
	elif art == "repair" and faction != "sky":
		_service_yard(m,parts,faction,owner,size,tier)
		meta.integrated_gate = true
	elif faction == "sky" and art in ["barracks","factory","repair"]:
		meta = _sky_specialized(m,parts,owner,size,tier,art)
	elif faction == "sky" and art in ["hq","outpost"]:
		meta = _sky_command(m,parts,owner,size,tier,art == "hq")
	elif art in ["advanced_tower","aa_tower"]:
		meta = _tower(m,parts,faction,owner,size,tier,art == "aa_tower")
	elif art == "tech":
		_tech(m,parts,faction,owner,size,tier)
	elif art in ["power","advanced_power"]:
		_power(m,parts,faction,owner,size,tier,art == "advanced_power")
	else:
		var personnel: bool = art in ["hq","outpost","barracks"]
		var gate_width: float = 1.48 if personnel else 2.56
		var gate_height: float = 1.78 if personnel else 2.52
		# Service bays admit the same vehicles as factories, even in compact yards.
		if art == "repair": gate_width = minf(size*.67,2.56)
		var height: float = gate_height + (.52 if faction == "sky" else .42)
		var front: float = size*.34
		var width: float = size*.90
		var depth: float = size*.77
		if art == "hq":
			height = 2.82 if faction == "rivet" else 2.60
			width = size*.90
			depth = size*.70
			front = size*.31
		if art == "outpost": height = 2.15; gate_height = 1.65
		_plinth(m,size,size)
		_hall(m,faction,owner,width,depth,height,front,gate_width,gate_height,tier)
		m.badge(Vector3(0,gate_height+.26,front+.22),faction,owner,Vector3.BACK,.17)
		meta.entrance = {"width":gate_width,"height":gate_height,"front":front,"bottom":.13,"mode":faction}
		match art:
			"hq", "outpost": _headquarters(m,parts,faction,owner,size,height,art == "hq",tier)
			"factory": _factory_equipment(m,parts,faction,size,height,tier)
			"refinery": _refinery_equipment(m,parts,faction,size,height,tier)
			"barracks": _barracks_equipment(m,parts,faction,owner,size,height,tier)
			"repair": _repair_equipment(m,parts,faction,size,height,tier)
		_add_gates(parts,meta.entrance,faction,owner,tier)
		meta.integrated_gate = true
	var high := Vector3.ZERO
	for v: Vector3 in m.vertices: high = high.max(Vector3(absf(v.x),v.y,absf(v.z)))
	if meta.has("turret_mesh"):
		for surface in range(meta.turret_mesh.get_surface_count()):
			for v: Vector3 in meta.turret_mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var world: Vector3 = v+(meta.turret_pos as Vector3)
				high = high.max(Vector3(absf(world.x),world.y,absf(world.z)))
	for p: Dictionary in parts:
		for v: Vector3 in p.get("extent_vertices",[]):
			var world: Vector3 = v + (p.pivot as Vector3)
			high = high.max(Vector3(absf(world.x),world.y,absf(world.z)))
		p.erase("extent_vertices")
	meta.body_mesh = m.mesh()
	meta.body_border_mesh = m.shell_mesh()
	meta.parts = parts
	meta.dimensions = Vector3(maxf(size,high.x*2),high.y,maxf(size,high.z*2))
	meta.design_signature = faction+"_"+art+"_integrated_20261007"
	meta.faction_geometry = true
	meta.art = art
	return meta

static func _part(parts: Array, mesh, name: String, pivot: Vector3, role: String, extra: Dictionary = {}) -> void:
	var part: Dictionary = {"name":name,"mesh":mesh.mesh(),"border_mesh":mesh.shell_mesh(),"pivot":pivot,"role":role,"extent_vertices":mesh.vertices.duplicate()}
	part.merge(extra,true)
	parts.append(part)

static func _plinth(m, width: float, depth: float) -> void:
	m.slab([Vector2(-width*.5+.12,-depth*.5),Vector2(width*.5-.12,-depth*.5),Vector2(width*.5,-depth*.5+.12),Vector2(width*.5,depth*.5-.12),Vector2(width*.5-.12,depth*.5),Vector2(-width*.5+.12,depth*.5),Vector2(-width*.5,depth*.5-.12),Vector2(-width*.5,-depth*.5+.12)],.12,Vector3(0,.06,0),KRAFT)

static func _hall(m, faction: String, owner: Color, width: float, depth: float, height: float, front: float, opening: float, gate_height: float, tier: int) -> void:
	var paint: Color = PAINT[faction]
	var wing: float = (width-opening)*.5
	var rear: float = front-depth
	# Solid walls enclose a genuine empty aisle. The door sits recessed into it.
	for side in [-1.0,1.0]:
		m.box(Vector3(side*(opening+wing)*.5,height*.5+.12,(front+rear)*.5),Vector3(wing,height,depth),paint)
		m.box(Vector3(side*(opening*.5+.09),gate_height*.5+.13,front+.08),Vector3(.18,gate_height+.08,.32),KRAFT)
		m.box(Vector3(side*(opening+wing)*.5,height*.56,front+.055),Vector3(wing*.60,.32,.075),owner)
		if tier < 2:
			for i in range(3 if tier == 0 else 1):
				m.box(Vector3(side*(width*.5+.015),height*.48,rear+depth*(.24+float(i)*.25)),Vector3(.035,height*.46,.13),KRAFT)
	m.box(Vector3(0,height*.5+.12,rear+.10),Vector3(opening,height,.20),paint)
	m.box(Vector3(0,gate_height+(height-gate_height)*.5+.13,front-.03),Vector3(opening,height-gate_height,.34),paint)
	m.box(Vector3(0,height+.15,(front+rear)*.5),Vector3(width+.10,.20,depth+.12),KRAFT)
	m.box(Vector3(0,.14,(front+rear)*.5),Vector3(opening,.035,depth),INK,false)
	match faction:
		"kestrel":
			m.gable(Vector3(0,height+.25,(front+rear)*.5),width+.20,depth+.20,.46,paint)
			# Broad folded roof/side pockets make the paired sliding portals natural.
			m.box(Vector3(0,gate_height+.27,front+.08),Vector3(width,.16,.37),paint)
			for side in [-1.0,1.0]: m.box(Vector3(side*(width*.5-.10),height*.5,front+.12),Vector3(.18,height,.30),PAPER)
		"rivet":
			m.prism([Vector2(-width*.5,0),Vector2(-width*.40,.40),Vector2(width*.40,.40),Vector2(width*.5,0)],depth+.16,Vector3(0,height+.22,(front+rear)*.5),paint)
			for side in [-1.0,1.0]:
				m.prism([Vector2(-.22,0),Vector2(-.12,height*.78),Vector2(.13,height),Vector2(.25,0)],.48,Vector3(side*(width*.5-.14),.14,front-.25),KRAFT)
				m.cylinder(Vector3(side*(opening*.5+.09),gate_height*.5+.14,front+.27),.09,gate_height,Vector3.UP,STEEL,8)
		"iron":
			m.prism([Vector2(-width*.5,0),Vector2(-width*.40,.34),Vector2(-width*.22,.60),Vector2(width*.22,.60),Vector2(width*.40,.34),Vector2(width*.5,0)],depth+.14,Vector3(0,height+.18,(front+rear)*.5),paint)
			m.cylinder(Vector3(0,gate_height+.36,front+.06),.21,opening+.48,Vector3.RIGHT,STEEL,12)
			if tier < 2:
				for z in [rear+.2,(rear+front)*.5,front-.2]:
					m.line(Vector3(-width*.43,height+.46,z),Vector3(-width*.23,height+.79,z),.045,KRAFT)
					m.line(Vector3(-width*.23,height+.79,z),Vector3(width*.23,height+.79,z),.045,KRAFT)
					m.line(Vector3(width*.23,height+.79,z),Vector3(width*.43,height+.46,z),.045,KRAFT)
		"sky":
			# Two triangular folded shells, light well, flush energy gate emitters.
			for side in [-1.0,1.0]:
				m.prism([Vector2(-wing*.5,0),Vector2(0,.46),Vector2(wing*.5,.16),Vector2(wing*.5,0)],depth+.25,Vector3(side*(opening+wing)*.5,height+.25,(front+rear)*.5),paint)
				m.box(Vector3(side*(opening*.5+.06),gate_height*.5+.13,front+.22),Vector3(.07,gate_height,.065),GLASS,false)
			m.box(Vector3(0,height+.29,(front+rear)*.5),Vector3(opening*.60,.08,depth*.72),GLASS,false)
	if tier == 0:
		# Score lines and folded paper edge tabs live on the shell, not the gate.
		for x in [-width*.33,width*.33]:
			m.line(Vector3(x,height+.27,rear+.06),Vector3(x,height+.27,front-.08),.012,INK)

static func _add_gates(parts: Array, portal: Dictionary, faction: String, owner: Color, tier: int) -> void:
	var width: float = portal.width
	var height: float = portal.height
	var front: float = portal.front
	var bottom: float = portal.bottom
	var paint: Color = PAINT[faction]
	if faction in ["kestrel","rivet"]:
		for side in [-1.0,1.0]:
			var leaf = _mesh(tier)
			var center: float = -side*width*.25 if faction == "rivet" else 0.0
			leaf.box(Vector3(center,0,0),Vector3(width*.495,height,.13),paint)
			leaf.box(Vector3(center,height*.11,.075),Vector3(width*.38,height*.34,.035),owner,false)
			if tier < 2:
				leaf.box(Vector3(center,-height*.31,.08),Vector3(width*.39,.12,.05),KRAFT)
				leaf.line(Vector3(center-width*.19,-height*.40,.09),Vector3(center+width*.19,-height*.40,.09),.018,INK)
			var pivot: Vector3 = Vector3(side*width*(.5 if faction == "rivet" else .25),height*.5+bottom,front-.10)
			_part(parts,leaf,"GateLeft" if side < 0 else "GateRight",pivot,"production_door",{"gate_mode":"hinge" if faction == "rivet" else "slide","side":side,"travel":width*.5})
	elif faction == "iron":
		var shutter = _mesh(tier)
		shutter.box(Vector3.ZERO,Vector3(width,height,.12),paint)
		shutter.box(Vector3(0,height*.10,.08),Vector3(width*.76,height*.31,.03),owner,false)
		if tier < 2:
			for i in range(9 if tier == 0 else 5):
				shutter.box(Vector3(0,-height*.44+float(i)*height/(10 if tier == 0 else 5),.075),Vector3(width,.045,.04),STEEL,false)
		_part(parts,shutter,"RollingShutter",Vector3(0,height*.5+bottom,front-.09),"production_door",{"gate_mode":"roll","travel":height*.5})
	else:
		# Each half originates at the centre seam and retracts OUT toward its
		# own emitter. Keeping separate leaves makes the opening unambiguous.
		for side in [-1.0,1.0]:
			for index in range(7):
				var field = _mesh(tier)
				var beam_height: float = height/7.0*.83
				field.box(Vector3.ZERO,Vector3(width*.495,beam_height,.035),GLASS,false)
				field.box(Vector3(0,beam_height*.36,.026),Vector3(width*.495,.018,.016),PAPER,false)
				_part(parts,field,"PhaseBand_%s_%s" % [side,index],Vector3(side*width*.25,bottom+(float(index)+.5)*height/7.0,front-.09),"production_door",{"gate_mode":"phase","side":side,"phase":float(index)/7.0,"travel":width*.50})

static func _sky_command(m,parts: Array,owner: Color,size: float,tier: int,major: bool) -> Dictionary:
	var paint: Color = PAINT.sky
	var gate_width: float = 1.48
	var gate_height: float = 1.78 if major else 1.65
	var front: float = size*.34
	var wing_width: float = (size*.90-gate_width-.24)*.5
	var wing_center: float = gate_width*.5+.12+wing_width*.5
	var wing_height: float = 2.25 if major else 1.66
	var core_height: float = 3.65 if major else 2.72
	# The HQ is a low spread of two folded wedge wings, an empty portal throat,
	# and a tall aft command leaf. No generic warehouse room or gabled roof.
	m.slab([Vector2(-size*.29,-size*.46),Vector2(size*.29,-size*.46),Vector2(size*.48,-size*.15),Vector2(size*.42,size*.36),Vector2(size*.20,size*.46),Vector2(-size*.20,size*.46),Vector2(-size*.42,size*.36),Vector2(-size*.48,-size*.15)],.14,Vector3(0,.07,0),KRAFT)
	for side in [-1.0,1.0]:
		# Mirror the complete folded solid, including winding, via explicit x
		# coordinates of the cross section rather than a negative node scale.
		var shape: Array = [Vector2(side*-wing_width*.5,0),Vector2(side*-wing_width*.5,wing_height*.88),Vector2(side*-wing_width*.27,wing_height),Vector2(side*wing_width*.38,wing_height*.35),Vector2(side*wing_width*.50,.16),Vector2(side*wing_width*.50,0)]
		m.prism(shape,size*.53,Vector3(side*wing_center,.17,-size*.045),paint)
		# Deep paper cut face at each wing's front explains the folded section.
		m.line(Vector3(side*(wing_center-wing_width*.27),wing_height+.18,size*.222),Vector3(side*(wing_center+wing_width*.40),wing_height*.34+.18,size*.222),.037,KRAFT)
		m.line(Vector3(side*(wing_center-wing_width*.27),wing_height+.18,-size*.29),Vector3(side*(wing_center+wing_width*.40),wing_height*.34+.18,-size*.29),.037,KRAFT)
		m.box(Vector3(side*(gate_width*.5+.13),gate_height*.5+.16,front-.10),Vector3(.20,gate_height+.20,.26),paint)
		m.box(Vector3(side*(gate_width*.5+.025),gate_height*.5+.16,front+.05),Vector3(.045,gate_height,.075),GLASS,false)
		# Sloping cheek ribs physically join the doorway to the wing volume.
		m.line(Vector3(side*(gate_width*.5+.16),gate_height+.26,front-.1),Vector3(side*(wing_center-wing_width*.20),wing_height*.88,-size*.035),.14,paint)
		var fin_count: int = 3 if major else 2
		for i in range(fin_count):
			var x: float = side*(wing_center-wing_width*.14+float(i)*wing_width*.23)
			var base_y: float = wing_height*(.82-float(i)*.15)+.16
			var fin_height: float = (1.17 if major else .76)*(1.0-float(i)*.16)
			m.prism([Vector2(-.065,0),Vector2(-.065,fin_height),Vector2(.015,fin_height+.20),Vector2(.095,fin_height*.56),Vector2(.095,0)],size*.20,Vector3(x,base_y,-size*.12),owner)
			if tier < 2: m.box(Vector3(x,base_y+fin_height*.52,-size*.018),Vector3(.046,fin_height*.67,.045),GLASS,false)
		if tier == 0:
			for z in [-size*.23,0.0,size*.18]:
				m.line(Vector3(side*(wing_center-wing_width*.33),wing_height*.94+.19,z),Vector3(side*(wing_center+wing_width*.18),wing_height*.52+.20,z),.012,INK)
	# A faceted rear spire folds forward over the throat, leaving the ground
	# aisle entirely empty. The slit skylight is part of its closed shell.
	m.prism([Vector2(-size*.14,0),Vector2(-size*.15,core_height*.61),Vector2(-size*.06,core_height),Vector2(size*.11,core_height*.84),Vector2(size*.15,core_height*.14),Vector2(size*.14,0)],size*.23,Vector3(0,.17,-size*.285),paint)
	m.prism([Vector2(-size*.07,0),Vector2(-size*.04,.43),Vector2(size*.07,.25),Vector2(size*.08,0)],size*.29,Vector3(0,maxf(core_height*.57,gate_height+.38),-size*.11),PAPER)
	m.box(Vector3(0,core_height*.60,-size*.161),Vector3(size*.095,core_height*.37,.045),GLASS,false)
	# Thin origami lintel, backed by two roof ribs; neither is a pasted door.
	m.prism([Vector2(-gate_width*.63,0),Vector2(-gate_width*.48,.28),Vector2(0,.46),Vector2(gate_width*.48,.28),Vector2(gate_width*.63,0),Vector2(0,.12)],.30,Vector3(0,gate_height+.18,front-.12),paint)
	m.box(Vector3(0,.155,front*.43),Vector3(gate_width,.035,front*1.20),INK,false)
	m.badge(Vector3(0,gate_height+.50,front+.07),"sky",owner,Vector3.BACK,.16 if major else .13)
	_scanner(m,parts,"sky",Vector3(-size*.035,core_height+.33,-size*.285),tier)
	var entrance: Dictionary = {"width":gate_width,"height":gate_height,"front":front,"bottom":.16,"mode":"sky"}
	_add_gates(parts,entrance,"sky",owner,tier)
	return {"entrance":entrance,"integrated_gate":true,"architecture_form":"folded_command_wings" if major else "folded_field_node"}

static func _headquarters(m,parts: Array,faction: String,owner: Color,size: float,height: float,major: bool,tier: int) -> void:
	var paint: Color = PAINT[faction]
	var width: float = size*(.42 if major else .44)
	var back: float = -size*.13
	match faction:
		"sky":
			# Faceted command prism rests on a thin origami bridge, with no giant box.
			m.prism([Vector2(-width*.5,0),Vector2(-width*.38,1.12),Vector2(width*.17,1.42),Vector2(width*.50,.40)],size*.23,Vector3(0,height+.31,back),paint)
			m.box(Vector3(width*.05,height+.96,back+size*.12),Vector3(width*.64,.24,.045),GLASS,false)
			for side in [-1.0,1.0]:
				m.prism([Vector2(-width*.27,0),Vector2(-width*.04,.74),Vector2(width*.27,.09)],.10,Vector3(side*width*.75,height+.38,back),PAPER)
				m.line(Vector3(side*width*.25,height+.52,back+size*.13),Vector3(side*width*.42,height+1.06,back+size*.13),.028,KRAFT)
			m.badge(Vector3(0,height+1.39,back+.07),faction,owner,Vector3.UP,.25 if major else .16)
			_scanner(m,parts,faction,Vector3(width*.29,height+1.80,back-.12),tier)
		"rivet":
			m.box(Vector3(0,height+.76,back),Vector3(width,1.02,size*.24),paint)
			m.box(Vector3(0,height+1.32,back),Vector3(width+.22,.16,size*.28),KRAFT)
			for side in [-1.0,1.0]:
				m.box(Vector3(side*width*.38,height+.81,back+size*.125),Vector3(width*.21,.25,.06),GLASS)
				m.cylinder(Vector3(side*width*.57,height+.90,back),.12,1.1,Vector3.UP,STEEL,8)
			m.badge(Vector3(0,height+.92,back+size*.14),faction,owner,Vector3.BACK,.28)
			_scanner(m,parts,faction,Vector3(-width*.27,height+1.75,back),tier)
		"iron":
			m.box(Vector3(-width*.20,height+.77,back),Vector3(width*.77,1.05,size*.24),paint)
			m.gable(Vector3(-width*.20,height+1.32,back),width*.86,size*.27,.43,KRAFT)
			m.cylinder(Vector3(width*.40,height+1.25,back),width*.22,1.4,Vector3.UP,paint,12)
			m.cylinder(Vector3(width*.40,height+2.00,back),width*.25,.15,Vector3.UP,KRAFT,12)
			_gear(m,parts,Vector3(width*.40,height+1.23,back+width*.23),.35,tier)
			m.badge(Vector3(-width*.20,height+.83,back+size*.13),faction,owner,Vector3.BACK,.23)
		"kestrel":
			m.box(Vector3(0,height+.92,back),Vector3(width*.62,1.28,size*.24),paint)
			m.gable(Vector3(0,height+1.58,back),width*.76,size*.28,.45,paint)
			for side in [-1.0,1.0]: m.box(Vector3(side*width*.26,height+1.06,back+size*.13),Vector3(.12,1.06,.12),PAPER)
			m.box(Vector3(0,height+.96,back+size*.13),Vector3(width*.37,.31,.07),GLASS)
			m.badge(Vector3(0,height+1.45,back+size*.15),faction,owner,Vector3.BACK,.21)
			_scanner(m,parts,faction,Vector3(0,height+2.18,back),tier)

static func _factory_equipment(m,parts: Array,faction: String,size: float,height: float,tier: int) -> void:
	var paint: Color = PAINT[faction]
	# Three roof exhausts and an inspection walk distinguish assembly from ore.
	for side in [-1.0,1.0]:
		m.box(Vector3(side*size*.30,height+.54,-size*.09),Vector3(size*.18,.42,size*.42),paint)
		if tier < 2:
			for z in [-.7,-.3,.1,.5]: m.box(Vector3(side*size*.30,height+.79,z),Vector3(size*.14,.05,.12),STEEL,false)
	_fan(m,parts,Vector3(size*.29,height+.85,-size*.18),.39,tier)
	if faction == "iron": _gear(m,parts,Vector3(-size*.29,height+.82,size*.14),.42,tier)
	elif faction == "sky": _scanner(m,parts,faction,Vector3(-size*.30,height+1.1,-size*.15),tier)
	else: m.cylinder(Vector3(-size*.31,height+.97,-size*.21),.17,.80,Vector3.UP,paint,10)

static func _refinery_equipment(m,parts: Array,faction: String,size: float,height: float,tier: int) -> void:
	var paint: Color = PAINT[faction]
	for side in [-1.0,1.0]:
		var p := Vector3(side*size*.29,height+.63,-size*.15)
		m.cylinder(p,size*.13,1.14,Vector3.UP,paint,12)
		m.cylinder(p+Vector3(0,.62,0),size*.145,.15,Vector3.UP,KRAFT,12)
		m.line(p+Vector3(0,.6,0),Vector3(side*size*.28,height+.7,size*.24),.10,STEEL)
		if tier < 2:
			for y in [-.36,.08,.46]: m.cylinder(p+Vector3(0,y,0),size*.134,.07,Vector3.UP,STEEL,12,false)
	_fan(m,parts,Vector3(size*.29,height+1.38,-size*.15),size*.105,tier)
	if faction == "iron": _gear(m,parts,Vector3(-size*.29,height+.66,size*.11),.35,tier)

static func _barracks_equipment(m,parts: Array,faction: String,owner: Color,size: float,height: float,tier: int) -> void:
	var paint: Color = PAINT[faction]
	m.box(Vector3(0,height+.79,-size*.13),Vector3(size*.27,.56,size*.27),paint)
	m.badge(Vector3(0,height+.80,size*.015),faction,owner,Vector3.BACK,.23)
	_scanner(m,parts,faction,Vector3(0,height+1.24,-size*.13),tier)

static func _repair_equipment(m,parts: Array,faction: String,size: float,height: float,tier: int) -> void:
	var paint: Color = PAINT[faction]
	for side in [-1.0,1.0]:
		m.box(Vector3(side*size*.23,.24,.06),Vector3(.19,.18,size*.64),STEEL)
		m.box(Vector3(side*size*.33,height+.51,0),Vector3(.18,.54,size*.74),paint)
	m.box(Vector3(0,height+.81,-.10),Vector3(size*.73,.22,.35),paint)
	var arm = _mesh(tier)
	arm.box(Vector3.ZERO,Vector3(.43,.32,.39),KRAFT)
	arm.line(Vector3(0,-.10,0),Vector3(0,-.76,0),.037,STEEL)
	arm.line(Vector3(0,-.76,0),Vector3(.17,-.88,0),.07,STEEL)
	_part(parts,arm,"ServiceHoist",Vector3(0,height+.55,-.10),"building_hoist",{"travel":size*.13})

static func _tech(m,parts: Array,faction: String,owner: Color,size: float,tier: int) -> void:
	var paint: Color = PAINT[faction]
	_plinth(m,size,size)
	match faction:
		"sky":
			# Wide across the facade, very thin in depth: a standing folded research leaf.
			m.box(Vector3(0,.37,0),Vector3(size*.86,.56,size*.60),KRAFT)
			for side in [-1.0,1.0]:
				m.prism([Vector2(-size*.21,0),Vector2(-size*.15,4.10),Vector2(size*.11,4.36),Vector2(size*.21,3.88),Vector2(size*.21,0)],size*.22,Vector3(side*size*.23,.62,0),paint)
				m.box(Vector3(side*size*.23,2.65,size*.12),Vector3(size*.20,3.13,.035),PAPER,false)
				m.box(Vector3(side*size*.23,2.65,size*.129),Vector3(size*.095,2.86,.038),owner,false)
				m.line(Vector3(side*size*.28,.8,size*.13),Vector3(side*size*.28,4.59,size*.13),.027,KRAFT)
			m.box(Vector3(0,2.94,0),Vector3(size*.14,3.73,size*.14),GLASS,false)
			m.box(Vector3(0,1.22,size*.315),Vector3(size*.58,.72,.075),paint)
			m.badge(Vector3(0,1.31,size*.37),faction,owner,Vector3.BACK,.27)
			_scanner(m,parts,faction,Vector3(0,4.81,0),tier)
		"iron":
			m.box(Vector3(0,.73,0),Vector3(size*.85,1.25,size*.78),paint)
			m.gable(Vector3(0,1.42,0),size*.89,size*.82,.51,paint)
			m.cylinder(Vector3(-size*.21,2.27,-.18),size*.18,2.25,Vector3.UP,paint,14)
			for y in [1.33,1.83,2.35,2.89,3.39]: m.cylinder(Vector3(-size*.21,y,-.18),size*.195,.12,Vector3.UP,KRAFT,14)
			m.cylinder(Vector3(size*.27,2.30,-size*.22),.18,2.31,Vector3.UP,INK,10)
			m.cylinder(Vector3(size*.27,3.48,-size*.22),.29,.18,Vector3.UP,STEEL,10)
			m.line(Vector3(-size*.20,2.9,-.1),Vector3(size*.26,2.9,-.1),.13,STEEL)
			_gear(m,parts,Vector3(-size*.21,2.36,size*.19),size*.22,tier)
			_gear(m,parts,Vector3(size*.21,1.96,size*.30),size*.13,tier)
			m.badge(Vector3(size*.21,1.0,size*.40),faction,owner,Vector3.BACK,.25)
		"rivet":
			# Stepped monumental institute: a slim central research tower and low wings.
			for side in [-1.0,1.0]:
				m.box(Vector3(side*size*.31,1.08,0),Vector3(size*.29,1.92,size*.72),paint)
				m.box(Vector3(side*size*.31,2.09,0),Vector3(size*.32,.17,size*.76),KRAFT)
				if tier < 2:
					for i in range(3): m.box(Vector3(side*size*.31,.7+float(i)*.44,size*.37),Vector3(size*.18,.20,.05),GLASS)
			m.box(Vector3(0,1.92,-.12),Vector3(size*.35,3.55,size*.56),paint)
			m.box(Vector3(0,3.81,-.12),Vector3(size*.43,.24,size*.64),KRAFT)
			m.box(Vector3(0,4.18,-.12),Vector3(size*.24,.56,size*.40),paint)
			m.prism([Vector2(-size*.12,0),Vector2(0,1.0),Vector2(size*.12,0)],size*.25,Vector3(0,4.45,-.12),paint)
			for side in [-1.0,1.0]: m.box(Vector3(side*size*.10,2.12,size*.18),Vector3(.12,2.78,.14),PAPER)
			m.badge(Vector3(0,3.86,size*.22),faction,owner,Vector3.BACK,.23)
			_scanner(m,parts,faction,Vector3(size*.30,2.43,0),tier)
		"kestrel":
			m.box(Vector3(0,.94,0),Vector3(size*.83,1.62,size*.75),paint)
			m.cylinder(Vector3(0,1.92,-.09),size*.32,.26,Vector3.UP,KRAFT,16)
			m.prism([Vector2(-size*.30,0),Vector2(-size*.22,.64),Vector2(0,.94),Vector2(size*.22,.64),Vector2(size*.30,0)],size*.52,Vector3(0,2.05,-.09),paint)
			for side in [-1.0,1.0]: m.box(Vector3(side*size*.31,.96,size*.40),Vector3(.15,1.66,.13),PAPER)
			m.badge(Vector3(0,1.45,size*.40),faction,owner,Vector3.BACK,.24)
			_scanner(m,parts,faction,Vector3(0,3.22,-.09),tier)

static func _power(m,parts: Array,faction: String,owner: Color,size: float,tier: int,advanced: bool) -> void:
	var paint: Color = PAINT[faction]
	_plinth(m,size,size)
	var count: int = 3 if advanced else 2
	m.box(Vector3(0,.46,0),Vector3(size*.84,.68,size*.80),paint)
	for i in range(count):
		var x: float = (float(i)-float(count-1)*.5)*size*.26
		if faction == "sky":
			m.prism([Vector2(-size*.11,0),Vector2(-size*.065,2.05),Vector2(size*.04,2.31),Vector2(size*.11,1.73),Vector2(size*.11,0)],size*.35,Vector3(x,.80,-size*.13),paint)
			m.box(Vector3(x,1.72,size*.06),Vector3(size*.11,1.20,.038),GLASS,false)
		else:
			m.cylinder(Vector3(x,1.73,-size*.13),size*.13,1.90,Vector3.UP,paint,12)
			for y in [1.0,1.72,2.48]: m.cylinder(Vector3(x,y,-size*.13),size*.15,.12,Vector3.UP,KRAFT,12)
	m.box(Vector3(0,.97,size*.29),Vector3(size*.56,.40,size*.18),owner if faction == "sky" else paint)
	m.badge(Vector3(0,1.0,size*.39),faction,owner,Vector3.BACK,.21)
	if advanced:
		for side in [-1.0,1.0]:
			m.line(Vector3(side*size*.38,1.20,-size*.25),Vector3(side*size*.35,2.95,-size*.25),.085,STEEL)
		m.line(Vector3(-size*.35,2.95,-size*.25),Vector3(size*.35,2.95,-size*.25),.075,STEEL)
		_scanner(m,parts,faction,Vector3(0,3.31,-size*.13),tier)
	else: _fan(m,parts,Vector3(0,1.15,size*.26),size*.17,tier)

static func _tower(m,parts: Array,faction: String,owner: Color,size: float,tier: int,aa: bool) -> Dictionary:
	var paint: Color = PAINT[faction]
	_plinth(m,size,size)
	var height: float = 1.95 if aa else 2.25
	match faction:
		"kestrel":
			m.prism([Vector2(-size*.37,0),Vector2(-size*.26,height),Vector2(size*.26,height),Vector2(size*.37,0)],size*.69,Vector3(0,.12,0),paint)
			for side in [-1.0,1.0]: m.box(Vector3(side*size*.28,height*.51,size*.35),Vector3(.15,height,.17),PAPER)
		"rivet":
			m.box(Vector3(0,height*.43,0),Vector3(size*.78,height*.78,size*.76),paint)
			m.box(Vector3(0,height*.84,0),Vector3(size*.60,height*.37,size*.59),KRAFT)
			for side in [-1.0,1.0]: m.prism([Vector2(-.15,0),Vector2(0,height*.95),Vector2(.22,0)],size*.60,Vector3(side*size*.38,.12,0),paint)
		"iron":
			m.cylinder(Vector3(0,height*.45,0),size*.35,height*.85,Vector3.UP,paint,10)
			for y in [.45,1.05,1.70]: m.cylinder(Vector3(0,y,0),size*.38,.14,Vector3.UP,STEEL,10)
			_gear(m,parts,Vector3(0,1.07,size*.36),.39,tier)
		"sky":
			for side in [-1.0,1.0]: m.prism([Vector2(-.27,0),Vector2(-.17,height),Vector2(.15,height),Vector2(.30,0)],size*.50,Vector3(side*size*.22,.12,0),paint)
			m.box(Vector3(0,height*.59,0),Vector3(size*.17,height*.83,size*.30),GLASS)
	m.cylinder(Vector3(0,height+.15,0),size*.32,.22,Vector3.UP,KRAFT,12)
	m.badge(Vector3(0,.67,size*.41),faction,owner,Vector3.BACK,.23)
	_fan(m,parts,Vector3(0,height+.30,size*.27),.17,tier)
	var gun = _mesh(tier)
	gun.box(Vector3(-.20,.23,0),Vector3(.76,.49,.85),paint)
	var barrels: int = 4 if aa else 2 if faction in ["rivet","iron"] else 1
	for i in range(barrels):
		var z: float = (float(i)-float(barrels-1)*.5)*.22
		var bore: float = .07 if aa else .12 if faction != "sky" else .15
		gun.cylinder(Vector3(.67,.26,z),bore,1.35 if aa else 1.65,Vector3.RIGHT,STEEL,10)
		gun.cylinder(Vector3(1.40 if aa else 1.54,.26,z),bore*1.28,.18,Vector3.RIGHT,INK,8)
		if faction == "sky":
			for x in [.35,.67,1.02]: gun.box(Vector3(x,.26,z),Vector3(.13,.47,.39),paint)
	gun.box(Vector3(-.20,.51,0),Vector3(.57,.08,.65),owner)
	if aa:
		gun.line(Vector3(-.44,.53,0),Vector3(-.44,.99,0),.05,STEEL)
		gun.box(Vector3(-.44,1.02,0),Vector3(.12,.27,.65),paint)
	return {"turret_mesh":gun.mesh(),"turret_border_mesh":gun.shell_mesh(),"turret_pos":Vector3(0,height+.31,0),"muzzle_pos":Vector3(1.66,.26,0),"recoil_distance":.055}

static func _shipyard(m,parts: Array,faction: String,owner: Color,size: float,tier: int) -> void:
	var paint: Color = PAINT[faction]
	# +X remains open water in all four designs. Different major load-bearing
	# structures, not roof swaps on a shared room, establish faction identity.
	match faction:
		"kestrel":
			# Neat cream masonry shore hall and paired light slipway cranes.
			m.box(Vector3(-size*.32,.17,0),Vector3(size*.34,.34,size*.93),KRAFT)
			for side in [-1.0,1.0]: m.box(Vector3(size*.14,.14,side*size*.43),Vector3(size*.70,.22,size*.10),KRAFT)
			m.box(Vector3(-size*.32,1.0,0),Vector3(size*.29,1.44,size*.74),paint)
			m.gable(Vector3(-size*.32,1.77,0),size*.34,size*.79,.39,paint)
			for side in [-1.0,1.0]:
				m.box(Vector3(size*.07,1.21,side*size*.42),Vector3(.17,2.18,.20),PAPER)
				m.line(Vector3(-size*.15,2.28,side*size*.42),Vector3(size*.28,2.28,side*size*.42),.10,paint)
			m.box(Vector3(size*.07,2.31,0),Vector3(.29,.20,size*.87),paint)
			_scanner(m,parts,faction,Vector3(-size*.32,2.43,0),tier)
		"rivet":
			# Monumental twin dock towers support an armored transverse lift
			# bridge. The slip is sheltered beneath deep inclined side girders.
			m.box(Vector3(-size*.40,.20,0),Vector3(size*.18,.38,size*.96),KRAFT)
			for side in [-1.0,1.0]:
				m.box(Vector3(size*.07,.22,side*size*.43),Vector3(size*.83,.34,size*.13),paint)
				m.box(Vector3(-size*.235,1.92,side*size*.355),Vector3(size*.28,3.40,size*.19),paint)
				m.box(Vector3(-size*.235,3.74,side*size*.355),Vector3(size*.33,.25,size*.24),KRAFT)
				m.prism([Vector2(-.28,0),Vector2(-.14,2.70),Vector2(.10,2.42),Vector2(.33,0)],.30,Vector3(size*.28,.35,side*size*.415),paint)
				m.line(Vector3(-size*.235,3.35,side*size*.36),Vector3(size*.34,2.76,side*size*.415),.19,paint)
				if tier < 2:
					for y in [.9,1.65,2.40]: m.box(Vector3(-size*.07,y,side*size*.355),Vector3(.045,.35,size*.11),INK,false)
					m.line(Vector3(-size*.36,.57,side*size*.43),Vector3(-size*.36,3.44,side*size*.43),.06,STEEL)
			m.box(Vector3(-size*.235,3.44,0),Vector3(size*.34,.51,size*.82),paint)
			m.box(Vector3(-size*.235,3.78,0),Vector3(size*.25,.20,size*.78),KRAFT)
			m.box(Vector3(-size*.40,1.03,0),Vector3(size*.17,1.62,size*.40),paint)
			m.badge(Vector3(-size*.049,3.49,0),faction,owner,Vector3.RIGHT,.30)
			var hoist = _mesh(tier)
			hoist.box(Vector3.ZERO,Vector3(.45,.24,.50),STEEL)
			hoist.line(Vector3(0,-.1,0),Vector3(0,-.49,0),.045,STEEL)
			hoist.box(Vector3(0,-.52,0),Vector3(.37,.12,.37),KRAFT)
			_part(parts,hoist,"DockHeavyHoist",Vector3(-size*.10,3.07,0),"building_hoist",{"travel":.35})
			_fan(m,parts,Vector3(-size*.235,3.92,-size*.355),.28,tier)
		"iron":
			# An asymmetric long boiler quay with a large exposed drive wheel.
			# There is no opposing room or paired gantry: the sea face stays open.
			m.box(Vector3(0,.16,-size*.385),Vector3(size*.96,.30,size*.22),KRAFT)
			m.box(Vector3(-size*.415,.15,size*.13),Vector3(size*.13,.27,size*.64),KRAFT)
			m.cylinder(Vector3(-size*.02,1.03,-size*.38),.34,size*.79,Vector3.RIGHT,paint,14)
			for x in [-size*.31,0.0,size*.29]: m.cylinder(Vector3(x,1.03,-size*.38),.385,.13,Vector3.RIGHT,KRAFT,14)
			for x in [-size*.32,-size*.13]:
				var height: float = 3.05 if x < -size*.2 else 2.55
				m.cylinder(Vector3(x,(1.31+height)*.5,-size*.345),.12,height-1.31,Vector3.UP,STEEL,10)
				m.cylinder(Vector3(x,height,-size*.345),.22,.16,Vector3.UP,paint,10)
			m.line(Vector3(-size*.35,1.72,-size*.30),Vector3(size*.36,1.72,-size*.30),.085,STEEL)
			m.line(Vector3(size*.36,1.72,-size*.30),Vector3(size*.36,.73,-size*.30),.085,STEEL)
			m.line(Vector3(-size*.13,1.34,-size*.34),Vector3(-size*.13,2.18,-size*.34),.14,STEEL)
			_gear(m,parts,Vector3(-size*.13,2.18,-size*.39),.87,tier)
			m.box(Vector3(-size*.395,.88,size*.255),Vector3(size*.17,1.34,size*.34),paint)
			m.gable(Vector3(-size*.395,1.60,size*.255),size*.20,size*.38,.29,paint)
			# One swiveling jib is braced into the boiler quay, not duplicated.
			m.box(Vector3(size*.15,1.30,-size*.38),Vector3(.21,2.24,.22),STEEL)
			m.line(Vector3(size*.15,2.48,-size*.38),Vector3(size*.15,2.40,size*.15),.105,KRAFT)
			m.line(Vector3(size*.15,1.70,-size*.38),Vector3(size*.15,2.40,size*.15),.055,STEEL)
			m.badge(Vector3(size*.41,1.03,-size*.38),faction,owner,Vector3.RIGHT,.21)
			if tier == 0:
				for x in [-size*.3,-size*.1,size*.1,size*.3]: m.box(Vector3(x,.43,-size*.38),Vector3(.055,.035,size*.17),INK,false)
		"sky":
			# Two continuous folded cantilever arms rise from swept sponsons.
			# Their thin cross bridge is visibly attached at both ends; rear
			# capacitor leaves replace the conventional shore warehouse.
			m.box(Vector3(-size*.405,.15,0),Vector3(size*.12,.26,size*.87),KRAFT)
			for side in [-1.0,1.0]:
				var z: float=side*size*.402
				m.slab([Vector2(-size*.46,z-side*.15),Vector2(size*.34,z-side*.10),Vector2(size*.47,z+side*.025),Vector2(size*.21,z+side*.18),Vector2(-size*.44,z+side*.17)],.16,Vector3(0,.25,0),PAPER)
				m.prism([Vector2(-size*.42,0),Vector2(-size*.42,.43),Vector2(-size*.24,2.09),Vector2(size*.025,2.95),Vector2(size*.41,2.44),Vector2(size*.35,2.20),Vector2(size*.035,2.54),Vector2(-size*.18,1.80),Vector2(-size*.25,.36),Vector2(-size*.23,0)],.24,Vector3(0,.33,z),paint)
				m.line(Vector3(-size*.25,1.70,z-side*.135),Vector3(size*.025,2.97,z-side*.135),.035,GLASS)
				m.line(Vector3(size*.025,2.97,z-side*.135),Vector3(size*.35,2.48,z-side*.135),.035,GLASS)
			m.slab([Vector2(-size*.06,-size*.41),Vector2(size*.09,-size*.41),Vector2(size*.18,0),Vector2(size*.09,size*.41),Vector2(-size*.06,size*.41),Vector2(-size*.15,0)],.16,Vector3(0,3.04,0),owner)
			for i in range(4):
				var z: float=(float(i)-1.5)*size*.22
				var height: float=1.77 if i in [1,2] else 1.26
				m.prism([Vector2(-.12,0),Vector2(-.10,height),Vector2(.14,height+.25),Vector2(.25,height*.25),Vector2(.15,0)],size*.13,Vector3(-size*.355,.31,z),paint)
				if tier < 2: m.box(Vector3(-size*.287,height*.57+.31,z),Vector3(.035,height*.59,size*.072),GLASS,false)
			m.fixed_box(Vector3(-size*.03,3.14,0),Vector3(size*.08,.045,size*.60),Color("67578b"),false)
			m.badge(Vector3(size*.15,3.14,0),faction,owner,Vector3.UP,.24)
			_scanner(m,parts,faction,Vector3(size*.005,3.34,0),tier)
	if tier < 2 and faction == "kestrel":
		for side in [-1.0,1.0]:
			for i in range(4): m.box(Vector3(-size*.1+float(i)*size*.16,.30,side*size*.43),Vector3(.08,.09,.16),STEEL,false)

static func _fan(m,parts: Array,pos: Vector3,radius: float,tier: int) -> void:
	m.cylinder(pos,radius*1.16,.13,Vector3.UP,INK,12)
	var rotor = _mesh(tier)
	rotor.cylinder(Vector3.ZERO,radius*.20,.16,Vector3.UP,STEEL,8)
	for i in range(4 if tier < 2 else 3):
		var angle: float = float(i)*TAU/float(4 if tier < 2 else 3)
		rotor.line(Vector3(cos(angle),0,sin(angle))*radius*.18,Vector3(cos(angle),0,sin(angle))*radius*.88,radius*.12,KRAFT)
	_part(parts,rotor,"RoofFan"+str(parts.size()),pos+Vector3(0,.09,0),"building_fan")

static func _gear(m,parts: Array,pos: Vector3,radius: float,tier: int) -> void:
	m.cylinder(pos,radius*.22,.23,Vector3.BACK,STEEL,8)
	var wheel = _mesh(tier)
	wheel.cylinder(Vector3.ZERO,radius,.12,Vector3.BACK,KRAFT,14)
	wheel.cylinder(Vector3(0,0,.075),radius*.65,.03,Vector3.BACK,INK,12,false)
	for i in range(8 if tier == 0 else 4):
		var angle: float = float(i)*TAU/float(8 if tier == 0 else 4)
		wheel.line(Vector3(0,0,.105),Vector3(cos(angle)*radius*.9,sin(angle)*radius*.9,.105),.041,STEEL)
		wheel.box(Vector3(cos(angle),sin(angle),0)*radius,Vector3(.13,.13,.16),KRAFT,false)
	_part(parts,wheel,"Flywheel"+str(parts.size()),pos+Vector3(0,0,.14),"building_gear")

static func _scanner(m,parts: Array,faction: String,pos: Vector3,tier: int) -> void:
	m.cylinder(pos-Vector3(0,.15,0),.055,.30,Vector3.UP,STEEL,8)
	var rotor = _mesh(tier)
	if faction == "sky":
		rotor.prism([Vector2(-.37,0),Vector2(0,.25),Vector2(.37,0),Vector2(0,-.08)],.08,Vector3.ZERO,PAINT[faction])
		rotor.box(Vector3(0,.07,.05),Vector3(.49,.055,.024),GLASS,false)
	elif faction == "rivet":
		rotor.box(Vector3.ZERO,Vector3(.61,.19,.22),PAINT[faction])
		rotor.box(Vector3(0,0,.13),Vector3(.46,.10,.04),GLASS,false)
	else:
		rotor.box(Vector3.ZERO,Vector3(.66,.30,.10),PAINT[faction])
		if tier < 2:
			for x in [-.23,0.0,.23]: rotor.box(Vector3(x,0,.065),Vector3(.038,.24,.028),KRAFT,false)
	_part(parts,rotor,"Scanner"+str(parts.size()),pos,"building_scanner")

static func add_idle_equipment(recipe: Dictionary,faction: String,tier: int,art: String = "") -> void:
	if recipe.get("parts",[]).any(func(p): return str(p.role).begins_with("building_")): return
	var dim: Vector3 = recipe.dimensions
	var base = _mesh(tier)
	var parts: Array = recipe.get("parts",[])
	var mount := Vector3(0,dim.y+.12,-dim.z*.39)
	if art == "airfield": mount = Vector3(0,{"kestrel":2.50,"rivet":2.32,"iron":1.93,"sky":2.42}[faction],-2.75)
	_scanner(base,parts,faction,mount,tier)
	_part(parts,base,"ScannerMount",Vector3.ZERO,"architecture")
	for p: Dictionary in parts: p.erase("extent_vertices")
	recipe.parts = parts
	recipe.dimensions.y = maxf(dim.y,mount.y+.28)

static func _sky_specialized(m, parts: Array, owner: Color, size: float, tier: int, art: String) -> Dictionary:
	var white := Color("e9e5dc")
	var purple := Color("74569d")
	var dark := Color("4b376e")
	var front: float = size*.36
	var width: float = 1.48 if art == "barracks" else minf(2.56,size*.66)
	var height: float = 1.78 if art == "barracks" else 2.52
	var portal: Dictionary = {"width":width,"height":height,"front":front,"bottom":.15,"mode":"sky"}
	if art == "barracks":
		# Radial folded sleeping pods surround a hollow personnel portal.
		m.slab([Vector2(-size*.46,-size*.18),Vector2(-size*.23,-size*.46),Vector2(size*.23,-size*.46),Vector2(size*.46,-size*.18),Vector2(size*.39,size*.40),Vector2(-size*.39,size*.40)],.13,Vector3(0,.07,0),KRAFT)
		for side in [-1.0,1.0]:
			var x: float = side*(width*.5+.36)
			m.prism([Vector2(-.42,0),Vector2(-.35,1.50),Vector2(0,2.46),Vector2(.35,1.50),Vector2(.42,0)],size*.54,Vector3(x,.15,-size*.03),white)
			m.prism([Vector2(-.28,0),Vector2(0,.55),Vector2(.28,0)],.045,Vector3(x,1.53,front+.03),purple)
			m.box(Vector3(x,1.24,front+.05),Vector3(.27,.36,.055),GLASS,false)
			m.badge(Vector3(x,.72,front+.08),"sky",owner,Vector3.BACK,.14)
		# A tall single folded sail marks the barracks at every LOD.
		m.prism([Vector2(-.54,0),Vector2(-.43,2.75),Vector2(.13,3.25),Vector2(.53,.30)],.65,Vector3(0,.15,-size*.29),purple)
		m.prism([Vector2(-width*.57,0),Vector2(0,.50),Vector2(width*.57,0)],.32,Vector3(0,height+.16,front),white)
	elif art == "factory":
		# An open skeletal assembly vault: five hexagonal ribs and a suspended
		# assembly spine, with daylight through both sides instead of a box hall.
		m.slab([Vector2(-size*.48,-size*.44),Vector2(size*.48,-size*.44),Vector2(size*.45,size*.45),Vector2(-size*.45,size*.45)],.15,Vector3(0,.075,0),KRAFT)
		for side in [-1.0,1.0]:
			m.prism([Vector2(-.40,0),Vector2(-.36,.78),Vector2(.26,1.12),Vector2(.48,0)],size*.86,Vector3(side*size*.36,.16,0),purple)
			for z in [-size*.34,-size*.17,0.0,size*.17,size*.34]:
				var foot := Vector3(side*size*.42,.24,z)
				var shoulder := Vector3(side*size*.32,2.77,z)
				var crown := Vector3(side*.44,3.52,z)
				m.line(foot,shoulder,.24,white)
				m.line(shoulder,crown,.24,white)
				m.line(crown,Vector3(0,3.58,z),.24,white)
			m.box(Vector3(side*size*.33,1.02,front+.11),Vector3(.60,.24,.08),owner)
			m.box(Vector3(side*(width*.5+.12),height*.5+.15,front),Vector3(.23,height,.27),purple)
		# Rear enclosure and perforated side screens close the assembly room.
		# Open hexagonal windows still reveal the printer without opening the rear.
		m.box(Vector3(0,.62,-size*.39),Vector3(size*.82,.94,.16),white)
		m.box(Vector3(0,2.83,-size*.36),Vector3(size*.64,.40,.16),white)
		for x in [-.30,-.15,0,.15,.30]:
			m.box(Vector3(x*size,1.76,-size*.385),Vector3(.13,1.45,.18),purple)
		m.box(Vector3(0,1.83,-size*.40),Vector3(size*.75,.12,.20),white)
		for side in [-1.0,1.0]:
			for z in [-size*.255,-size*.085,size*.085]:
				m.box(Vector3(side*size*.38,1.48,z),Vector3(.12,.15,size*.13),white)
				m.line(Vector3(side*size*.39,.94,z-size*.06),Vector3(side*size*.35,2.25,z+size*.06),.045,purple)
		m.box(Vector3(0,3.58,0),Vector3(.42,.22,size*.84),dark)
		m.line(Vector3(0,3.42,-size*.18),Vector3(.58,2.85,-size*.18),.17,STEEL)
		m.line(Vector3(.58,2.85,-size*.18),Vector3(.20,2.22,-size*.18),.14,purple)
		m.badge(Vector3(0,3.65,front+.08),"sky",owner,Vector3.BACK,.21)
	else:
		# Open hexagonal service cradle; low circular turntable and two swept
		# repair booms give a third, entirely different silhouette.
		var ring: Array = []
		for index in range(8):
			var angle: float = TAU*float(index)/8.0
			ring.append(Vector2(cos(angle),sin(angle))*size*.49)
		m.slab(ring,.18,Vector3(0,.09,0),white)
		m.cylinder(Vector3(0,.24,0),size*.32,.20,Vector3.UP,dark,12)
		m.cylinder(Vector3(0,.35,0),size*.26,.035,Vector3.UP,STEEL,12)
		for side in [-1.0,1.0]:
			var base := Vector3(side*size*.39,.22,-size*.12)
			m.prism([Vector2(-.24,0),Vector2(-.17,1.80),Vector2(.16,2.40),Vector2(.30,.15)],.56,base,purple)
			m.line(base+Vector3(0,2.17,0),Vector3(side*.42,2.72,-size*.03),.22,white)
			m.line(Vector3(side*.42,2.72,-size*.03),Vector3(side*.20,1.90,size*.08),.12,STEEL)
			m.box(Vector3(side*.20,1.82,size*.08),Vector3(.24,.22,.26),GLASS)
			m.badge(base+Vector3(0,.82,.31),"sky",owner,Vector3.BACK,.15)
		m.prism([Vector2(-.40,0),Vector2(0,.46),Vector2(.40,0)],.24,Vector3(0,.22,-size*.42),white)
		_scanner(m,parts,"sky",Vector3(-size*.39,2.70,-size*.12),tier)
		return {"architecture_form":"open_octagonal_repair_cradle","integrated_gate":true}
	_scanner(m,parts,"sky",Vector3(.13,3.48,-size*.29) if art == "barracks" else Vector3(0,3.81,-size*.34),tier)
	m.box(Vector3(0,.16,front*.42),Vector3(width,.035,front*1.3),INK,false)
	_add_gates(parts,portal,"sky",owner,tier)
	return {"entrance":portal,"integrated_gate":true,"architecture_form":"radial_barracks_sails" if art == "barracks" else "open_assembly_rib_vault"}

static func _service_yard(m,parts: Array,faction: String,owner: Color,size: float,tier: int) -> void:
	# An open repair gantry has no warehouse silhouette or enclosed roof.
	var paint: Color = PAINT[faction]
	_plinth(m,size,size)
	for side in [-1.0,1.0]:
		m.box(Vector3(side*size*.23,.23,0),Vector3(.22,.22,size*.75),STEEL)
		m.box(Vector3(side*size*.40,.47,-size*.13),Vector3(.50,.72,size*.52),paint)
		for z in [-size*.32,size*.29]:
			m.line(Vector3(side*size*.39,.14,z),Vector3(side*size*.31,2.45,z),.19,paint)
		m.box(Vector3(side*size*.31,2.52,-.06),Vector3(.25,.25,size*.78),paint)
		m.badge(Vector3(side*size*.40,.55,size*.15),faction,owner,Vector3.BACK,.15)
		if faction == "rivet":
			m.line(Vector3(side*size*.39,.18,-size*.33),Vector3(side*size*.31,2.36,size*.27),.09,KRAFT)
	m.box(Vector3(0,2.55,0),Vector3(size*.72,.29,.36),paint)
	if faction == "iron":
		m.cylinder(Vector3(size*.36,2.55,0),.30,.15,Vector3.RIGHT,STEEL,10)
	var hoist = _mesh(tier)
	hoist.box(Vector3.ZERO,Vector3(.42,.32,.46),KRAFT)
	hoist.line(Vector3(0,-.10,0),Vector3(0,-.95,0),.035,STEEL)
	hoist.line(Vector3(0,-.95,0),Vector3(.18,-1.05,0),.07,STEEL)
	_part(parts,hoist,"ServiceHoist",Vector3(0,2.33,0),"building_hoist",{"travel":size*.22})

static func _refinery_complex(m, parts: Array, faction: String, owner: Color, size: float, tier: int) -> Dictionary:
	# A real unloading aisle between separate process machines, not a warehouse.
	var front: float = size*.37
	var portal: Dictionary = {"width":2.56,"height":2.52,"front":front,"bottom":.15,"mode":faction}
	_plinth(m,size,size)
	m.box(Vector3(0,.15,.30),Vector3(2.62,.035,size*.68),INK,false)
	for side in [-1.0,1.0]:
		m.box(Vector3(side*1.40,1.42,front),Vector3(.20,2.54,.34),PAPER)
		m.box(Vector3(side*1.40,1.64,front+.19),Vector3(.13,.65,.04),owner,false)
	m.box(Vector3(0,2.78,front),Vector3(3.18,.22,.47),owner)
	m.badge(Vector3(0,2.81,front+.26),faction,owner,Vector3.BACK,.18)
	if faction == "iron":
		# A riveted distillation tower, steam condenser and exposed gear drive.
		var left := Vector3(-size*.34,0,-size*.14)
		m.cylinder(left+Vector3(0,1.72,0),size*.135,2.98,Vector3.UP,Color("39847b"),16)
		for y in [.38,1.0,1.67,2.35,3.11]:m.cylinder(left+Vector3(0,y,0),size*.148,.13,Vector3.UP,KRAFT,16)
		m.cylinder(left+Vector3(0,3.29,0),size*.12,.24,Vector3.UP,PAPER,12)
		m.cylinder(left+Vector3(0,3.83,0),.16,.94,Vector3.UP,INK,10)
		m.cylinder(left+Vector3(0,4.34,0),.24,.13,Vector3.UP,KRAFT,10)
		m.cylinder(Vector3(size*.38,1.02,-size*.12),.43,size*.57,Vector3.BACK,PAPER,14)
		for z in [-size*.35,-size*.12,size*.12]:m.cylinder(Vector3(size*.38,1.02,z),.48,.11,Vector3.BACK,owner,14)
		for side in [-1.0,1.0]:m.box(Vector3(size*.38,.42,-size*.12+side*size*.23),Vector3(.83,.54,.24),KRAFT)
		m.line(left+Vector3(.1,2.59,-.28),Vector3(size*.30,2.59,-size*.27),.12,KRAFT)
		m.line(Vector3(size*.30,2.59,-size*.27),Vector3(size*.30,1.32,-size*.27),.12,KRAFT)
		m.box(Vector3(0,.54,-size*.38),Vector3(size*.42,.87,.66),Color("39847b"))
		m.gable(Vector3(0,1.01,-size*.38),size*.48,.75,.28,PAPER)
		_gear(m,parts,Vector3(size*.39,1.11,size*.18),.35,tier)
		_gear(m,parts,Vector3(size*.32,.78,size*.20),.20,tier)
		for z in [-.7,-.35,0,.35]:m.box(Vector3(-size*.34,.33,z),Vector3(.80,.06,.11),STEEL,false)
		if tier < 2:
			for y in [.6,1.0,1.4,1.8,2.2,2.6,3.0]:m.line(left+Vector3(-.19,y,.66),left+Vector3(.19,y,.66),.025,KRAFT)
	else:
		# Thin origami separator sails frame a luminous mineral processing core.
		for side in [-1.0,1.0]:
			var x: float = side*size*.34
			m.prism([Vector2(-.32,0),Vector2(-.28,2.91),Vector2(.03,3.45),Vector2(.27,2.55),Vector2(.32,0)],size*.57,Vector3(x,.17,-size*.12),Color("e9e5dc"))
			m.box(Vector3(x,1.89,size*.175),Vector3(.22,1.78,.055),owner,false)
			m.fixed_box(Vector3(x,1.92,size*.188),Vector3(.055,1.20,.064),Color("67578b"),false)
			m.line(Vector3(x,.38,-size*.34),Vector3(side*.37,2.92,-size*.32),.14,Color("e9e5dc"))
		m.cylinder(Vector3(0,1.04,-size*.30),.51,1.53,Vector3.UP,GLASS,8)
		for y in [.35,.98,1.78]:m.cylinder(Vector3(0,y,-size*.30),.63,.12,Vector3.UP,PAPER,12)
		m.cylinder(Vector3(0,2.1,-size*.30),.46,.10,Vector3.UP,owner,8)
		m.prism([Vector2(-.28,0),Vector2(-.17,.55),Vector2(.11,.96),Vector2(.30,.37),Vector2(.16,0)],.42,Vector3(0,2.19,-size*.30),GLASS)
		_scanner(m,parts,"sky",Vector3(0,3.42,-size*.29),tier)
	# The folded front canopy shades the unloading slot while leaving headroom.
	m.gable(Vector3(0,2.91,front-.04),3.34,.82,.23,PAPER)
	_add_gates(parts,portal,faction,owner,tier)
	return {"entrance":portal,"integrated_gate":true,"architecture_form":faction+"_open_process_refinery"}
