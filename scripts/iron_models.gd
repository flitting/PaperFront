extends RefCounted

## Iron Alliance: dependable industrial craft, standardized joints and honest service gear.
## Geometry is authored at game size. +X is forward and every gun's bore.
## CraftMesh is passed in; runtime loading only creates independent gun meshes.
const INK := Color("382a22")
const ARMOR := Color("51463a")
const OLD_PAINT := Color("39847b")
const YELLOW := Color("bb963e")
const PATCH := Color("d2ad54")
const PAPER := Color("e6d5af")
const EDGE := Color("ba9c68")
const STEEL := Color("99978b")
const RUBBER := Color("39372f")
const GLASS := Color("718881")
const BUILDING_ARTS := ["hq","power","refinery","barracks","factory","repair","command","tech","airfield","recycling_yard","outpost","tower","aa_tower","anti_tower","wall"]
const UNIT_ARTS := ["harvester","scout","tank","assault","aa","rig","artillery","repair_vehicle","recycler","transport","fighter","attacker","air_transport","advanced"]


static func make(mesh, art: String, team: int, kind: String) -> Dictionary:
	var owner: Color=_owner(team)
	mesh.capture_shell=true
	if kind=="building":
		match art:
			"hq":_hq(mesh,owner)
			"power":_power(mesh,owner)
			"refinery":_refinery(mesh,owner)
			"barracks":_barracks(mesh,owner)
			"factory":_factory(mesh,owner)
			"repair":_repair(mesh,owner)
			"command":_command(mesh,owner)
			"tech":_tech(mesh,owner)
			"airfield":_airfield(mesh,owner)
			"recycling_yard":_recycling_yard(mesh,owner)
			"outpost":_outpost(mesh,owner)
			"wall":_wall(mesh,owner)
			"tower","aa_tower","anti_tower":return _defense(mesh,art,owner)
			_:return {}
		var recipe: Dictionary=_finish(mesh,art,kind)
		if art=="power":recipe.smoke_ports=[Vector3(-1.23,2.96,-.77)]
		return recipe
	if kind!="unit":return {}
	match art:
		"harvester":return _harvester(mesh,owner)
		"scout":return _scout(mesh,owner)
		"tank":return _tank(mesh,owner)
		"assault":return _assault(mesh,owner)
		"aa":return _aa(mesh,owner)
		"rig":return _rig(mesh,owner)
		"artillery":return _artillery(mesh,owner)
		"repair_vehicle":return _repair_vehicle(mesh,owner)
		"recycler":return _recycler(mesh,owner)
		"transport":return _transport(mesh,owner)
		"fighter":return _fighter(mesh,owner)
		"attacker":return _attacker(mesh,owner)
		"air_transport":return _air_transport(mesh,owner)
		"advanced":return _advanced(mesh,owner)
	return {}


static func _owner(team: int) -> Color:
	var volume=load("res://scripts/volume_models.gd")
	return volume.player_color(team)


static func _part():
	var volume=load("res://scripts/volume_models.gd")
	var part=volume.CraftMesh.new()
	part.capture_shell=true
	return part


static func _finish(mesh, art: String, kind: String, gun=null, pivot: Vector3=Vector3.ZERO, muzzle: Vector3=Vector3.ZERO, extras: Dictionary={}) -> Dictionary:
	if kind == "unit" and art not in ["fighter","attacker","air_transport"]:
		# Small kraft boiler stack and bent steam feed identify the long-nail army
		# even when every player uses identical paint. No glossy metal material.
		mesh.cylinder(Vector3(-.67,1.08,-.29),.095,.49,Vector3.UP,ARMOR,8,false)
		mesh.cylinder(Vector3(-.67,1.34,-.29),.14,.09,Vector3.UP,OLD_PAINT,8,false)
		mesh.line(Vector3(-.64,.94,-.32),Vector3(-.24,.94,-.32),.045,EDGE)
	var low:=Vector3(INF,INF,INF)
	var high:=Vector3(-INF,-INF,-INF)
	for p: Vector3 in mesh.vertices:
		low=low.min(p)
		high=high.max(p)
	var result: Dictionary={"body_mesh":mesh.mesh(),"body_border_mesh":mesh.shell_mesh(),"design_signature":"iron_"+kind+"_"+art,"faction_geometry":true,"faction_color":YELLOW,"emblem":"repair_triangle"}
	if gun!=null:
		for p: Vector3 in gun.vertices:
			low=low.min(p+pivot)
			high=high.max(p+pivot)
		result.turret_mesh=gun.mesh()
		result.turret_border_mesh=gun.shell_mesh()
		result.turret_pos=pivot
		result.muzzle_pos=muzzle
	result.dimensions=high-low
	result.visual_bounds=AABB(low,high-low)
	result.merge(extras,true)
	return result


static func _basis(normal: Vector3) -> Basis:
	var n: Vector3=normal.normalized()
	var right: Vector3=Vector3.RIGHT if absf(n.y)>.9 else Vector3.UP.cross(n).normalized()
	return Basis(right,n.cross(right).normalized(),n)


static func _oriented_box(mesh, center: Vector3, size: Vector3, normal: Vector3, color: Color) -> void:
	var basis: Basis=_basis(normal)
	var h: Vector3=size*.5
	var p: Array[Vector3]=[]
	for q: Vector3 in [Vector3(-1,-1,-1),Vector3(1,-1,-1),Vector3(1,1,-1),Vector3(-1,1,-1),Vector3(-1,-1,1),Vector3(1,-1,1),Vector3(1,1,1),Vector3(-1,1,1)]:p.append(center+basis*(q*h))
	mesh.face([p[0],p[3],p[2],p[1]],color,-basis.z)
	mesh.face([p[4],p[5],p[6],p[7]],color,basis.z)
	mesh.face([p[0],p[4],p[7],p[3]],color,-basis.x)
	mesh.face([p[1],p[2],p[6],p[5]],color,basis.x)
	mesh.face([p[3],p[7],p[6],p[2]],color,basis.y)
	mesh.face([p[0],p[1],p[5],p[4]],color,-basis.y)


static func _mark(mesh, center: Vector3, normal: Vector3, owner: Color, size: float=.25) -> void:
	owner = Color("efb537")
	# A nail in an eight-tooth workshop seal. Owner paint occupies the same small
	# orange plate; the broad panel pigments follow the player palette.
	var previous: bool=mesh.capture_shell
	mesh.capture_shell=false
	var b: Basis=_basis(normal)
	_oriented_box(mesh,center,Vector3(size*2.15,size*1.95,.055),normal,INK)
	_oriented_box(mesh,center+b.z*.04,Vector3(size*1.94,size*1.75,.035),normal,owner)
	for i in range(8):
		var a: float=float(i)*TAU/8.0
		var v: Vector3=b*Vector3(cos(a),sin(a),0)
		var across: Vector3=b*Vector3(-sin(a),cos(a),0)*size*.13
		var inner: Vector3=center+v*size*.48+b.z*.081
		var outer: Vector3=center+v*size*.73+b.z*.081
		mesh.face([inner-across,outer-across,outer+across,inner+across],INK,b.z)
		var next: float=a+TAU/8.0
		mesh.line(center+b*Vector3(cos(a)*size*.49,sin(a)*size*.49,.082),center+b*Vector3(cos(next)*size*.49,sin(next)*size*.49,.082),maxf(.010,size*.10),INK)
	_oriented_box(mesh,center+b*Vector3(0,.29*size,.102),Vector3(size*.70,size*.22,.016),normal,PAPER)
	_oriented_box(mesh,center+b*Vector3(0,-.06*size,.102),Vector3(size*.24,size*.64,.016),normal,PAPER)
	mesh.capture_shell=previous

static func _patch(mesh, center: Vector3, size: Vector3, normal: Vector3=Vector3.BACK, color: Color=PATCH) -> void:
	var previous: bool=mesh.capture_shell
	mesh.capture_shell=false
	var basis: Basis=_basis(normal)
	_oriented_box(mesh,center,size,normal,INK)
	_oriented_box(mesh,center+basis.z*.021,Vector3(size.x*.89,size.y*.86,maxf(.015,size.z*.64)),normal,color)
	for side in [-1.0,1.0]:
		for row in [-1.0,1.0]:mesh.cylinder(center+basis*Vector3(side*size.x*.36,row*size.y*.32,size.z*.5+.027),.023,.020,normal,STEEL,6,false)
	mesh.capture_shell=previous


static func _tool_cabinet(mesh, center: Vector3, width: float=.68, height: float=.57, depth: float=.39) -> void:
	mesh.box(center,Vector3(width,height,depth),YELLOW)
	mesh.box(center+Vector3(0,height*.5+.045,0),Vector3(width+.08,.09,depth+.07),ARMOR)
	for row in range(3):
		var y: float=center.y+height*(.31-float(row)*.31)
		mesh.box(Vector3(center.x,y,center.z+depth*.5+.018),Vector3(width*.84,height*.24,.025),OLD_PAINT,false)
		mesh.line(Vector3(center.x-width*.19,y,center.z+depth*.5+.045),Vector3(center.x+width*.19,y,center.z+depth*.5+.045),.018,STEEL)


static func _joint(mesh, center: Vector3, width: float, height: float, normal: Vector3=Vector3.BACK) -> void:
	# Uniform rectangular joining plates replace improvised-looking scraps.
	_patch(mesh,center,Vector3(width,height,.060),normal,YELLOW)
	var b: Basis=_basis(normal)
	for side in [-1.0,1.0]:
		mesh.line(center+b*Vector3(-width*.40,side*height*.40,.048),center+b*Vector3(width*.40,side*height*.40,.048),.010,EDGE)


static func _outrigger(mesh, x: float, z: float, width: float=.58) -> void:
	mesh.box(Vector3(x,.44,z),Vector3(.30,.26,width),ARMOR)
	mesh.box(Vector3(x,.19,z),Vector3(.42,.20,width+.13),YELLOW)
	mesh.box(Vector3(x,.075,z),Vector3(.48,.09,width+.19),EDGE)


static func _foot(mesh, width: float, depth: float) -> void:
	mesh.box(Vector3(0,.13,0),Vector3(width,.25,depth),EDGE)
	for z in [-depth*.37,depth*.37]:mesh.box(Vector3(0,.30,z),Vector3(width*.91,.13,.20),ARMOR)


static func _room(mesh, center: Vector3, size: Vector3, yellow: bool=false) -> void:
	mesh.box(center,size,YELLOW if yellow else OLD_PAINT)
	var top: float=center.y+size.y*.5
	mesh.box(Vector3(center.x,top+.085,center.z),Vector3(size.x+.16,.17,size.z+.16),ARMOR)
	for side in [-1.0,1.0]:
		mesh.box(Vector3(center.x+side*(size.x*.5-.075),center.y,center.z+size.z*.5+.037),Vector3(.15,size.y*.97,.10),EDGE)
	_patch(mesh,Vector3(center.x+size.x*.20,center.y,center.z+size.z*.5+.085),Vector3(size.x*.27,size.y*.40,.045))


static func _door(mesh, center: Vector3, width: float, height: float) -> void:
	mesh.box(center,Vector3(width+.17,height+.14,.075),INK,false)
	mesh.box(center+Vector3(0,0,.046),Vector3(width,height,.026),ARMOR,false)
	for i in range(4):mesh.line(center+Vector3(-width*.44,-height*.35+i*height*.23,.069),center+Vector3(width*.44,-height*.35+i*height*.23,.069),.017,EDGE)
	mesh.line(center+Vector3(-width*.40,-height*.42,.081),center+Vector3(width*.40,height*.42,.081),.027,YELLOW)


static func _window(mesh, center: Vector3, width: float, height: float) -> void:
	mesh.box(center,Vector3(width+.09,height+.09,.075),INK,false)
	mesh.box(center+Vector3(0,0,.042),Vector3(width,height,.020),GLASS,false)
	mesh.line(center+Vector3(-width*.44,height*.43,.058),center+Vector3(width*.44,height*.43,.058),.019,EDGE)


static func _brace(mesh, a: Vector3, b: Vector3, radius: float=.065) -> void:
	mesh.line(a,b,radius,ARMOR)
	mesh.cylinder(a,.085,.11,Vector3.BACK,STEEL,6,false)
	mesh.cylinder(b,.085,.11,Vector3.BACK,STEEL,6,false)


static func _flag(mesh, position: Vector3, owner: Color, height: float=.85) -> void:
	mesh.cylinder(position+Vector3(0,height*.5,0),.035,height,Vector3.UP,INK,6,false)
	mesh.box(position+Vector3(.30,height-.19,0),Vector3(.58,.37,.06),YELLOW)
	_mark(mesh,position+Vector3(.30,height-.19,.050),Vector3.BACK,owner,.15)


static func _stack(mesh, position: Vector3, height: float, radius: float) -> void:
	mesh.cylinder(position+Vector3.UP*height*.5,radius,height,Vector3.UP,ARMOR,8)
	for y in [.17,height*.43,height*.76,height]:mesh.cylinder(position+Vector3.UP*y,radius*1.14,.12,Vector3.UP,YELLOW,8)
	_patch(mesh,position+Vector3(0,height*.48,radius+.025),Vector3(radius*1.13,height*.21,.04))


static func _hq(mesh, owner: Color) -> void:
	_foot(mesh,4.70,4.02)
	# A low industrial dispatch core: four strong corner columns, continuous
	# workrooms and a broad central table, with no scavenged lookout tower.
	mesh.slab([Vector2(-2.13,-1.29),Vector2(-1.59,-1.79),Vector2(1.59,-1.79),Vector2(2.13,-1.29),Vector2(2.13,1.29),Vector2(1.59,1.79),Vector2(-1.59,1.79),Vector2(-2.13,1.29)],1.41,Vector3(0,1.00,0),OLD_PAINT)
	mesh.box(Vector3(0,1.81,0),Vector3(4.28,.22,3.51),ARMOR)
	for x in [-1.85,1.85]:
		for z in [-1.44,1.44]:
			mesh.box(Vector3(x,1.04,z),Vector3(.34,1.55,.40),YELLOW)
			mesh.box(Vector3(x,.49,z),Vector3(.57,.30,.63),ARMOR)
		_room(mesh,Vector3(x*.84,.71,1.43),Vector3(.84,.86,.56),true)
	_room(mesh,Vector3(0,2.26,-.31),Vector3(1.96,.70,1.53),true)
	mesh.box(Vector3(0,2.72,-.31),Vector3(2.19,.18,1.75),OLD_PAINT)
	for x in [-.66,0,.66]:_window(mesh,Vector3(x,2.29,.50),.43,.28)
	for x in [-1.30,1.30]:_joint(mesh,Vector3(x,1.01,1.85),.54,.45)
	_door(mesh,Vector3(0,.99,1.835),1.06,1.16)
	for x in [-.90,.90]:mesh.box(Vector3(x,1.99,.99),Vector3(.78,.13,.52),YELLOW)
	_mark(mesh,Vector3(0,2.28,.56),Vector3.BACK,owner,.34)
	_mark(mesh,Vector3(0,2.86,-.31),Vector3.UP,owner,.33)
	_flag(mesh,Vector3(-1.65,1.95,-1.37),owner,.93)

static func _power(mesh, owner: Color) -> void:
	_foot(mesh,4.02,3.61)
	# One horizontal boiler on cradles with an exposed flywheel and short stack.
	_room(mesh,Vector3(-1.23,.93,-.23),Vector3(.83,1.22,2.67),true)
	for x in [-.61,.86]:
		mesh.prism([Vector2(-.35,0),Vector2(-.25,.66),Vector2(.25,.66),Vector2(.35,0)],1.30,Vector3(x,.30,.10),ARMOR)
	mesh.cylinder(Vector3(.26,1.30,.10),.68,2.37,Vector3.RIGHT,OLD_PAINT,12)
	for x in [-.84,-.29,.37,1.36]:mesh.cylinder(Vector3(x,1.30,.10),.72,.105,Vector3.RIGHT,YELLOW,12)
	mesh.cylinder(Vector3(1.48,1.30,.10),.52,.14,Vector3.RIGHT,ARMOR,12)
	mesh.cylinder(Vector3(1.56,1.30,.10),.19,.065,Vector3.RIGHT,STEEL,10)
	_stack(mesh,Vector3(-1.23,1.51,-.77),1.45,.26)
	mesh.line(Vector3(-1.23,1.75,.18),Vector3(-.73,1.75,.18),.14,STEEL)
	mesh.line(Vector3(-.73,1.75,.18),Vector3(-.73,1.30,.18),.14,STEEL)
	mesh.line(Vector3(.74,.85,.60),Vector3(.74,.85,1.14),.11,STEEL)
	mesh.cylinder(Vector3(.74,.85,1.27),.45,.19,Vector3.BACK,ARMOR,12)
	mesh.cylinder(Vector3(.74,.85,1.385),.35,.035,Vector3.BACK,YELLOW,12,false)
	for i in range(4):
		var a: float=float(i)*TAU/4.0
		mesh.line(Vector3(.74,.85,1.416),Vector3(.74+cos(a)*.34,.85+sin(a)*.34,1.416),.038,STEEL)
	_door(mesh,Vector3(-1.23,.91,1.15),.55,.83)
	_joint(mesh,Vector3(.28,1.33,.81),.69,.38)
	_mark(mesh,Vector3(-1.23,1.41,1.19),Vector3.BACK,owner,.23)
	_mark(mesh,Vector3(-1.23,1.64,-.11),Vector3.UP,owner,.25)

static func _refinery(mesh, owner: Color) -> void:
	_foot(mesh,4.77,4.03)
	_room(mesh,Vector3(.34,1.03,-.06),Vector3(3.69,1.42,2.93),true)
	_room(mesh,Vector3(-1.68,1.49,-.64),Vector3(.74,2.36,1.39))
	# Closed tapered sorting hopper and a real inclined conveyor feed separate
	# the tall screening side from the low loading hall.
	mesh.prism([Vector2(-.65,0),Vector2(-.98,.54),Vector2(-.98,1.04),Vector2(.98,1.04),Vector2(.98,.54),Vector2(.65,0)],1.63,Vector3(.38,1.95,-.36),OLD_PAINT)
	mesh.box(Vector3(.38,3.08,-.36),Vector3(2.06,.17,1.76),YELLOW)
	mesh.prism([Vector2(-1.89,.09),Vector2(-1.90,.36),Vector2(.06,1.54),Vector2(.22,1.33)],.69,Vector3(-.10,.35,1.16),ARMOR)
	for x in [-1.60,-1.10,-.60,-.10]:mesh.cylinder(Vector3(x,.88+(x+1.60)*.55,1.17),.12,.77,Vector3.BACK,STEEL,8)
	mesh.box(Vector3(1.39,.48,1.60),Vector3(1.19,.51,.72),ARMOR)
	mesh.cylinder(Vector3(1.19,1.75,.71),.37,1.04,Vector3.RIGHT,ARMOR,12)
	for x in [.72,1.18,1.66]:mesh.cylinder(Vector3(x,1.75,.71),.40,.075,Vector3.RIGHT,YELLOW,12)
	for x in [.76,1.62]:mesh.box(Vector3(x,1.34,.71),Vector3(.18,.50,.59),STEEL)
	for z in [-1.19,.26]:_brace(mesh,Vector3(-2.09,.36,z),Vector3(-1.81,2.48,z),.07)
	_door(mesh,Vector3(.89,.91,1.46),1.06,1.02)
	_mark(mesh,Vector3(.38,2.62,.52),Vector3.BACK,owner,.34)
	_mark(mesh,Vector3(.38,3.20,-.36),Vector3.UP,owner,.30)


static func _barracks(mesh, owner: Color) -> void:
	_foot(mesh,4.28,3.08)
	_room(mesh,Vector3(0,1.03,-.08),Vector3(3.85,1.47,2.37))
	mesh.prism([Vector2(-2.05,-.07),Vector2(-1.58,.31),Vector2(.60,.31),Vector2(2.05,.03),Vector2(2.05,-.07)],2.58,Vector3(0,1.93,-.08),YELLOW)
	_room(mesh,Vector3(-1.76,.70,1.09),Vector3(.51,.79,.65),true)
	_room(mesh,Vector3(1.59,.70,1.10),Vector3(.83,.81,.61))
	_door(mesh,Vector3(-.73,.94,1.155),.88,1.18)
	_door(mesh,Vector3(.49,.94,1.155),.85,1.18)
	for x in [-1.35,-.36,.54,1.40]:_joint(mesh,Vector3(x,2.34,-.12),.48,.53,Vector3.UP)
	for x in [1.11,1.46,1.81]:
		mesh.box(Vector3(x,.69,1.30),Vector3(.17,.48,.18),ARMOR)
		mesh.box(Vector3(x,.96,1.30),Vector3(.22,.13,.22),YELLOW)
	for x in [-1.67,1.59]:_window(mesh,Vector3(x,1.26,1.17),.39,.36)
	_mark(mesh,Vector3(-.18,1.62,1.23),Vector3.BACK,owner,.27)
	_mark(mesh,Vector3(-.08,2.36,.21),Vector3.UP,owner,.28)
	_flag(mesh,Vector3(.96,2.29,-.67),owner,.80)


static func _factory(mesh, owner: Color) -> void:
	_foot(mesh,5.03,4.16)
	# An actual through assembly line. Thick side walls, three transverse roof
	# beams and two partial roof strips enclose a broad open work corridor.
	for side in [-1.0,1.0]:
		mesh.box(Vector3(side*1.94,1.02,-.08),Vector3(.52,1.43,3.63),OLD_PAINT)
		for z in [-1.61,0,1.52]:
			mesh.box(Vector3(side*1.99,1.58,z),Vector3(.30,2.58,.35),YELLOW)
			_joint(mesh,Vector3(side*1.99,1.41,z+.20),.31,.43)
		mesh.box(Vector3(side*1.51,2.91,-.08),Vector3(1.06,.17,3.77),OLD_PAINT)
		mesh.box(Vector3(side*1.80,.63,1.78),Vector3(.43,.43,.46),ARMOR)
	for z in [-1.64,0,1.56]:mesh.box(Vector3(0,2.71,z),Vector3(4.38,.26,.36),ARMOR)
	mesh.box(Vector3(0,.55,-.05),Vector3(2.80,.43,3.72),ARMOR)
	for x in [-1.04,1.04]:mesh.box(Vector3(x,.83,-.04),Vector3(.17,.14,3.95),STEEL)
	for z in [-1.53,-1.03,-.53,-.03,.47,.97,1.47]:mesh.cylinder(Vector3(0,.80,z),.10,1.94,Vector3.RIGHT,EDGE,8,false)
	mesh.prism([Vector2(-.78,0),Vector2(-.66,.40),Vector2(.54,.40),Vector2(.78,.15),Vector2(.78,0)],1.35,Vector3(0,.91,-.37),YELLOW)
	mesh.box(Vector3(-1.52,1.10,1.36),Vector3(.55,.74,.48),YELLOW)
	_tool_cabinet(mesh,Vector3(1.58,1.15,.73),.65,.83,.40)
	mesh.box(Vector3(-1.78,2.18,1.79),Vector3(.77,.15,.16),EDGE)
	_mark(mesh,Vector3(.19,2.72,1.78),Vector3.BACK,owner,.35)
	_mark(mesh,Vector3(-1.51,3.045,.38),Vector3.UP,owner,.31)
	_flag(mesh,Vector3(-1.96,2.99,-1.39),owner,.63)

static func _repair(mesh, owner: Color) -> void:
	_foot(mesh,4.64,3.91)
	_room(mesh,Vector3(-1.50,1.04,-.13),Vector3(1.14,1.53,3.34),true)
	_room(mesh,Vector3(1.63,.75,-1.11),Vector3(.87,.96,1.39))
	mesh.box(Vector3(.37,.45,.20),Vector3(2.30,.33,2.86),ARMOR)
	for x in [-.35,1.08]:mesh.box(Vector3(x,.70,.20),Vector3(.30,.16,2.60),STEEL)
	for x in [-.77,1.69]:
		mesh.box(Vector3(x,1.70,-.77),Vector3(.24,2.83,.35),OLD_PAINT)
		_brace(mesh,Vector3(x,.38,-1.05),Vector3(x*.52,2.93,-1.05),.075)
	mesh.box(Vector3(.45,3.14,-.77),Vector3(2.80,.30,.43),YELLOW)
	mesh.box(Vector3(.62,2.93,-.77),Vector3(.48,.29,.49),ARMOR)
	mesh.line(Vector3(.62,2.75,-.77),Vector3(.62,1.53,-.77),.045,STEEL)
	mesh.line(Vector3(.62,1.53,-.77),Vector3(.83,1.63,-.77),.057,INK)
	_tool_cabinet(mesh,Vector3(1.63,1.03,.43),.64,.70,.52)
	mesh.box(Vector3(1.63,.70,1.17),Vector3(.76,.13,.83),YELLOW)
	for x in [1.35,1.91]:mesh.box(Vector3(x,.52,1.17),Vector3(.13,.43,.54),ARMOR)
	_door(mesh,Vector3(-1.5,1.02,1.60),.69,1.14)
	_mark(mesh,Vector3(-1.50,1.48,1.63),Vector3.BACK,owner,.24)
	_mark(mesh,Vector3(.34,3.335,-.77),Vector3.UP,owner,.30)


static func _command(mesh, owner: Color) -> void:
	_foot(mesh,4.03,3.61)
	mesh.box(Vector3(0,.81,.03),Vector3(3.42,1.00,2.73),OLD_PAINT)
	mesh.box(Vector3(0,1.42,.03),Vector3(3.64,.20,2.94),ARMOR)
	# Wide dispatch board on two legs, never an improvised antenna crane.
	for x in [-1.20,1.20]:mesh.box(Vector3(x,1.99,-.54),Vector3(.16,1.05,.20),YELLOW)
	mesh.box(Vector3(0,2.29,-.54),Vector3(2.73,.94,.15),ARMOR)
	mesh.box(Vector3(0,2.29,-.443),Vector3(2.44,.72,.035),PAPER,false)
	for x in [-.62,0,.62]:mesh.box(Vector3(x,2.26,-.410),Vector3(.045,.59,.015),EDGE,false)
	for y in [2.06,2.29,2.52]:mesh.box(Vector3(0,y,-.408),Vector3(2.20,.033,.015),OLD_PAINT,false)
	mesh.box(Vector3(0,1.66,.76),Vector3(1.93,.23,.74),YELLOW)
	for x in [-.65,0,.65]:mesh.box(Vector3(x,1.805,.77),Vector3(.43,.035,.43),GLASS,false)
	mesh.cylinder(Vector3(1.48,2.38,-1.03),.030,2.00,Vector3.UP,STEEL,6,false)
	mesh.line(Vector3(1.16,3.36,-1.03),Vector3(1.79,3.36,-1.03),.027,ARMOR)
	_door(mesh,Vector3(-.84,.82,1.43),.67,.80)
	_window(mesh,Vector3(.83,.99,1.43),.82,.34)
	_mark(mesh,Vector3(.03,1.09,1.46),Vector3.BACK,owner,.25)
	_mark(mesh,Vector3(-1.19,1.55,.08),Vector3.UP,owner,.25)

static func _tech(mesh, owner: Color) -> void:
	_foot(mesh,4.20,3.72)
	_room(mesh,Vector3(0,.90,-.68),Vector3(3.65,1.14,1.80),true)
	# Horizontal durability test frame around a loaded beam, with two anchored
	# uprights and a readable low instrument cabinet.
	mesh.box(Vector3(-.13,.56,.63),Vector3(3.62,.43,1.30),ARMOR)
	for x in [-1.49,1.26]:
		mesh.box(Vector3(x,1.49,.53),Vector3(.35,2.15,.57),OLD_PAINT)
		mesh.box(Vector3(x,.49,.53),Vector3(.70,.31,.88),YELLOW)
		_joint(mesh,Vector3(x,1.20,.85),.34,.48)
	mesh.box(Vector3(-.13,2.63,.53),Vector3(3.42,.28,.65),YELLOW)
	mesh.cylinder(Vector3(-.12,2.17,.53),.17,.65,Vector3.UP,STEEL,10)
	mesh.box(Vector3(-.12,1.83,.53),Vector3(.75,.17,.91),ARMOR)
	mesh.box(Vector3(-.13,1.48,.53),Vector3(1.81,.50,.73),OLD_PAINT)
	mesh.box(Vector3(-.13,1.12,.53),Vector3(2.54,.21,1.01),YELLOW)
	_tool_cabinet(mesh,Vector3(1.54,.91,1.24),.66,.58,.45)
	mesh.box(Vector3(1.54,1.35,1.26),Vector3(.53,.22,.08),PAPER,false)
	for x in [1.36,1.45,1.54,1.63,1.72]:mesh.box(Vector3(x,1.36,1.31),Vector3(.016,.11,.012),INK,false)
	_door(mesh,Vector3(-1.22,.91,.25),.58,.84)
	_mark(mesh,Vector3(-.13,2.63,.89),Vector3.BACK,owner,.27)
	_mark(mesh,Vector3(.60,1.58,-.72),Vector3.UP,owner,.29)

static func _airfield(mesh, owner: Color) -> void:
	_foot(mesh,5.13,4.20)
	_room(mesh,Vector3(-.07,1.12,-.88),Vector3(4.53,1.67,1.94))
	mesh.prism([Vector2(-2.36,-.04),Vector2(-2.17,.48),Vector2(1.20,.48),Vector2(2.36,.17),Vector2(2.36,-.04)],2.14,Vector3(0,2.09,-.88),YELLOW)
	_door(mesh,Vector3(-.27,1.21,.115),2.23,1.41)
	_room(mesh,Vector3(1.88,1.22,.52),Vector3(.88,1.86,.84),true)
	mesh.box(Vector3(1.88,2.31,.52),Vector3(1.04,.31,1.00),ARMOR)
	_window(mesh,Vector3(1.88,2.31,1.055),.76,.21)
	mesh.box(Vector3(-.62,.295,1.22),Vector3(3.70,.040,1.48),ARMOR,false)
	for x in [-2.07,-1.43,-.79,-.15,.49]:mesh.box(Vector3(x,.327,1.22),Vector3(.32,.022,.12),PAPER,false)
	for z in [.62,1.82]:mesh.box(Vector3(-.72,.325,z),Vector3(3.58,.020,.10),YELLOW,false)
	_mark(mesh,Vector3(-.29,1.84,.17),Vector3.BACK,owner,.34)
	_mark(mesh,Vector3(.14,2.71,-.65),Vector3.UP,owner,.34)
	_tool_cabinet(mesh,Vector3(-1.74,.67,1.34),.66,.51,.51)
	mesh.box(Vector3(.65,.47,1.50),Vector3(.49,.32,.37),YELLOW)
	for side in [-1.0,1.0]:mesh.cylinder(Vector3(.65,.38,1.50+side*.24),.14,.08,Vector3.BACK,RUBBER,8)
	_flag(mesh,Vector3(-1.79,2.58,-1.23),owner,.64)


static func _recycling_yard(mesh, owner: Color) -> void:
	_foot(mesh,4.73,4.10)
	# Classified stock: two matching racks and a small enclosed parts store.
	# Every component sits in a shelf; there is no scrap heap or grab crane.
	_room(mesh,Vector3(1.50,1.11,-.25),Vector3(1.22,1.65,3.22),true)
	for z in [-1.18,.78]:
		for x in [-1.91,.49]:mesh.box(Vector3(x,1.27,z),Vector3(.18,1.94,.24),ARMOR)
		for y in [.52,1.18,1.87]:mesh.box(Vector3(-.70,y,z),Vector3(2.75,.17,.89),OLD_PAINT)
		for x in [-1.65,-.84,-.02]:
			mesh.box(Vector3(x,.85,z),Vector3(.60,.47,.62),YELLOW)
			_joint(mesh,Vector3(x,.86,z+.35),.35,.23)
			mesh.cylinder(Vector3(x,1.48,z),.21,.67,Vector3.BACK,STEEL,8)
		for x in [-1.61,-.84,-.06]:mesh.box(Vector3(x,2.03,z),Vector3(.63,.21,.59),EDGE)
		mesh.box(Vector3(-.71,2.18,z),Vector3(2.78,.14,1.01),YELLOW)
	_door(mesh,Vector3(1.50,1.04,1.42),.76,1.21)
	_mark(mesh,Vector3(1.50,1.71,1.46),Vector3.BACK,owner,.26)
	_mark(mesh,Vector3(1.50,2.105,-.25),Vector3.UP,owner,.28)

static func _outpost(mesh, owner: Color) -> void:
	_foot(mesh,3.88,3.47)
	mesh.slab([Vector2(-1.66,-1.09),Vector2(-1.06,-1.47),Vector2(1.11,-1.47),Vector2(1.69,-.99),Vector2(1.69,1.03),Vector2(1.07,1.45),Vector2(-1.09,1.45),Vector2(-1.66,1.04)],1.18,Vector3(0,.92,0),OLD_PAINT)
	mesh.box(Vector3(0,1.60,0),Vector3(3.14,.20,2.40),YELLOW)
	_room(mesh,Vector3(-.94,1.97,-.63),Vector3(.74,.67,.71))
	_room(mesh,Vector3(1.34,.63,.94),Vector3(.58,.69,.62),true)
	_door(mesh,Vector3(-.01,.91,1.51),.95,1.01)
	for x in [-1.13,.72]:_patch(mesh,Vector3(x,1.73,.65),Vector3(.67,.43,.045),Vector3.UP)
	_mark(mesh,Vector3(.31,1.28,1.53),Vector3.BACK,owner,.26)
	_mark(mesh,Vector3(.16,1.745,-.38),Vector3.UP,owner,.30)
	_flag(mesh,Vector3(-.98,2.39,-.63),owner,.72)


static func _wall(mesh, owner: Color) -> void:
	# One grid-cell closed gate/wall segment. Narrow end posts meet neighbouring
	# segments, while the reinforced leaves retain the sheet's bolted X-bracing.
	# Ink edges and the forward identity plate stay inside a roughly 1 x .5 pad.
	_foot(mesh,.94,.40)
	for side in [-1.0,1.0]:
		mesh.box(Vector3(side*.40,.86,0),Vector3(.12,1.27,.25),OLD_PAINT)
		mesh.box(Vector3(side*.40,1.575,0),Vector3(.15,.12,.29),YELLOW)
		mesh.box(Vector3(side*.20,.91,0),Vector3(.35,1.20,.12),ARMOR)
		_patch(mesh,Vector3(side*.20,.93,.085),Vector3(.31,1.05,.04))
		mesh.line(Vector3(side*.04,.43,.12),Vector3(side*.35,1.42,.12),.032,ARMOR)
		mesh.line(Vector3(side*.35,.43,.12),Vector3(side*.04,1.42,.12),.032,EDGE)
	mesh.box(Vector3(0,1.60,0),Vector3(.92,.12,.17),ARMOR)
	_mark(mesh,Vector3(0,1.01,.16),Vector3.BACK,owner,.135)
	_mark(mesh,Vector3(0,1.695,0),Vector3.UP,owner,.13)


static func _defense(mesh, art: String, owner: Color) -> Dictionary:
	var gun=_part()
	var pivot:=Vector3(0,1.08,0)
	var muzzle:=Vector3(1.05,.22,0)
	_foot(mesh,2.61,2.30)
	if art=="tower":
		mesh.cylinder(Vector3(0,.75,0),1.07,.87,Vector3.UP,OLD_PAINT,8)
		mesh.cylinder(Vector3(0,1.25,0),1.14,.16,Vector3.UP,YELLOW,8)
		pivot.y=1.33
		gun.box(Vector3(-.14,.16,0),Vector3(.65,.32,.59),ARMOR)
		gun.cylinder(Vector3(.40,.20,0),.060,.84,Vector3.RIGHT,STEEL,8)
		gun.box(Vector3(-.31,.12,.42),Vector3(.40,.32,.29),YELLOW)
		muzzle=Vector3(.84,.20,0)
	elif art=="aa_tower":
		mesh.box(Vector3(0,.69,0),Vector3(1.34,.71,1.23),OLD_PAINT)
		mesh.box(Vector3(0,.56,0),Vector3(2.24,.35,.55),ARMOR)
		mesh.box(Vector3(0,.56,0),Vector3(.55,.35,1.98),ARMOR)
		for side in [-1.0,1.0]:
			_outrigger(mesh,side*.92,0,.57)
			_outrigger(mesh,0,side*.78,.43)
		mesh.cylinder(Vector3(0,1.19,0),.72,.25,Vector3.UP,YELLOW,10)
		pivot.y=1.36
		gun.box(Vector3(0,.26,0),Vector3(.81,.52,1.03),ARMOR)
		for side in [-1.0,1.0]:
			gun.prism([Vector2(-.58,0),Vector2(-.58,.40),Vector2(.26,.72),Vector2(.53,.34),Vector2(.53,0)],.42,Vector3(0,.31,side*.49),YELLOW)
			for offset in [-.08,.11]:gun.cylinder(Vector3(.58,.87,side*.49+offset),.078,.73,Vector3(1,.37,0),STEEL,8)
		muzzle=Vector3(.99,1.02,0)
	else:
		mesh.prism([Vector2(-1.09,.30),Vector2(-1.01,1.05),Vector2(.62,1.05),Vector2(1.09,.56),Vector2(1.09,.30)],1.70,Vector3.ZERO,OLD_PAINT)
		mesh.box(Vector3(.84,.66,0),Vector3(.32,.53,2.13),YELLOW)
		pivot.y=1.18
		gun.prism([Vector2(-.53,0),Vector2(-.46,.54),Vector2(.37,.54),Vector2(.60,.24),Vector2(.60,0)],.83,Vector3.ZERO,ARMOR)
		gun.prism([Vector2(.35,-.03),Vector2(.37,.65),Vector2(.59,.71),Vector2(.73,.58),Vector2(.73,-.03)],1.26,Vector3.ZERO,YELLOW)
		gun.cylinder(Vector3(1.00,.30,0),.11,1.43,Vector3.RIGHT,STEEL,10)
		gun.cylinder(Vector3(1.72,.30,0),.16,.15,Vector3.RIGHT,ARMOR,8)
		muzzle=Vector3(1.81,.30,0)
	if art=="tower":
		mesh.box(Vector3(0,.85,.995),Vector3(1.85,.56,.22),OLD_PAINT)
		_joint(mesh,Vector3(-.65,.85,1.135),.38,.34)
		_mark(mesh,Vector3(.18,.89,1.135),Vector3.BACK,owner,.24)
		_mark(gun,Vector3(-.16,.345,0),Vector3.UP,owner,.18)
		_mark(gun,Vector3(-.15,.16,.325),Vector3.BACK,owner,.14)
	elif art=="aa_tower":
		_joint(mesh,Vector3(-.44,.79,.645),.34,.31)
		_mark(mesh,Vector3(.18,.80,.645),Vector3.BACK,owner,.22)
		_mark(gun,Vector3(-.12,.555,0),Vector3.UP,owner,.20)
		_mark(gun,Vector3(-.15,.25,.545),Vector3.BACK,owner,.17)
	else:
		_joint(mesh,Vector3(-.64,.79,.88),.44,.37)
		_mark(mesh,Vector3(.03,.87,.88),Vector3.BACK,owner,.25)
		_mark(gun,Vector3(-.12,.575,0),Vector3.UP,owner,.20)
		_mark(gun,Vector3(-.15,.25,.445),Vector3.BACK,owner,.17)
	return _finish(mesh,art,"building",gun,pivot,muzzle)


static func _wheels(mesh, xs: Array, z: float, radius: float=.31) -> void:
	for side in [-1.0,1.0]:
		for x in xs:
			mesh.cylinder(Vector3(x,radius+.015,side*z),radius,.21,Vector3.BACK,RUBBER,8)
			mesh.cylinder(Vector3(x,radius+.015,side*(z+.13)),radius*.55,.04,Vector3.BACK,EDGE,8,false)
			mesh.cylinder(Vector3(x,radius+.015,side*(z+.158)),radius*.18,.022,Vector3.BACK,INK,6,false)


static func _tracks(mesh, length: float, width: float, wheels: int=5) -> void:
	var half: float=length*.5
	for side in [-1.0,1.0]:
		var z: float=side*(width*.5-.17)
		mesh.prism([Vector2(-half+.20,.04),Vector2(half-.17,.04),Vector2(half,.19),Vector2(half,.45),Vector2(half-.18,.62),Vector2(-half+.20,.62),Vector2(-half,.43),Vector2(-half,.19)],.38,Vector3(0,0,z),RUBBER)
		for i in range(wheels):
			var x: float=lerpf(-half+.26,half-.26,float(i)/float(wheels-1))
			mesh.cylinder(Vector3(x,.32,z+side*.18),.205,.045,Vector3.BACK,EDGE,8,false)
			mesh.cylinder(Vector3(x,.32,z+side*.207),.075,.020,Vector3.BACK,INK,6,false)
		mesh.box(Vector3(-.04,.65,z),Vector3(length*.86,.11,.43),OLD_PAINT)


static func _harvester(mesh, owner: Color) -> Dictionary:
	_wheels(mesh,[-.84,-.15,.79],.64,.28)
	mesh.box(Vector3(-.03,.45,0),Vector3(2.17,.20,1.15),ARMOR)
	mesh.prism([Vector2(.36,.49),Vector2(.38,1.12),Vector2(.82,1.18),Vector2(1.13,.86),Vector2(1.13,.49)],1.09,Vector3.ZERO,YELLOW)
	mesh.box(Vector3(-.46,.65,0),Vector3(1.34,.16,1.15),EDGE)
	for side in [-1.0,1.0]:
		mesh.box(Vector3(-.46,.87,side*.51),Vector3(1.43,.43,.105),OLD_PAINT)
		mesh.box(Vector3(-.46,1.135,side*.56),Vector3(1.48,.095,.17),YELLOW)
		_patch(mesh,Vector3(-.52,.88,side*.59),Vector3(.43,.25,.045),Vector3(0,0,side))
	for x in [-1.16,.20]:mesh.box(Vector3(x,.86,0),Vector3(.105,.40,1.17),ARMOR)
	for x in [-.98,-.50,-.02]:
		for side in [-1.0,1.0]:_joint(mesh,Vector3(x,.87,side*.606),.30,.29,Vector3(0,0,side))
	mesh.box(Vector3(.64,1.225,0),Vector3(.92,.10,1.20),ARMOR)
	_window(mesh,Vector3(.68,.98,.586),.35,.22)
	mesh.box(Vector3(1.10,.56,0),Vector3(.17,.17,1.20),ARMOR)
	_mark(mesh,Vector3(-.49,.89,.68),Vector3.BACK,owner,.18)
	_mark(mesh,Vector3(.68,1.255,0),Vector3.UP,owner,.20)
	return _finish(mesh,"harvester","unit",null,Vector3.ZERO,Vector3.ZERO,{"cargo_origin":Vector3(-.97,.76,-.30),"cargo_step":Vector3(.26,.10,.30),"drill_pos":Vector3(1.13,.41,0),"cargo_capacity_visual":12})


static func _scout(mesh, owner: Color) -> Dictionary:
	_wheels(mesh,[-.64,.65],.58,.27)
	mesh.prism([Vector2(-.94,.39),Vector2(-.87,.80),Vector2(.24,.80),Vector2(.95,.58),Vector2(.95,.39)],.98,Vector3.ZERO,OLD_PAINT)
	mesh.box(Vector3(.54,.78,0),Vector3(.55,.21,1.03),YELLOW)
	mesh.box(Vector3(-.19,.95,0),Vector3(.63,.23,.74),ARMOR)
	# A continuous four-post roll cage frames the patrol cab.
	for side in [-1.0,1.0]:
		for x in [-.60,.22]:mesh.box(Vector3(x,1.15,side*.43),Vector3(.09,.81,.10),ARMOR)
		mesh.box(Vector3(-.19,1.57,side*.43),Vector3(.93,.10,.12),YELLOW)
		_joint(mesh,Vector3(-.53,.70,side*.57),.43,.25,Vector3(0,0,side))
	for x in [-.60,.22]:mesh.box(Vector3(x,1.57,0),Vector3(.10,.10,.93),ARMOR)
	_window(mesh,Vector3(-.12,1.09,.461),.42,.19)
	mesh.box(Vector3(-.78,.94,-.31),Vector3(.21,.22,.32),YELLOW)
	mesh.line(Vector3(-.78,1.05,-.31),Vector3(-.78,1.78,-.31),.020,INK)
	_mark(mesh,Vector3(.55,.935,0),Vector3.UP,owner,.17)
	_mark(mesh,Vector3(.42,.62,.55),Vector3.BACK,owner,.17)
	var gun=_part()
	gun.box(Vector3(-.02,.06,0),Vector3(.34,.18,.29),YELLOW)
	gun.cylinder(Vector3(.37,.10,0),.044,.55,Vector3.RIGHT,STEEL,6)
	return _finish(mesh,"scout","unit",gun,Vector3(-.10,1.66,0),Vector3(.68,.10,0))

static func _tank(mesh, owner: Color) -> Dictionary:
	_tracks(mesh,2.38,1.76,5)
	mesh.prism([Vector2(-1.05,.42),Vector2(-.98,.92),Vector2(.58,.98),Vector2(1.11,.68),Vector2(1.11,.42)],1.39,Vector3.ZERO,ARMOR)
	mesh.box(Vector3(-.42,.98,0),Vector3(.92,.15,1.29),OLD_PAINT)
	for side in [-1.0,1.0]:
		_joint(mesh,Vector3(.12,.77,side*.75),.82,.37,Vector3(0,0,side))
		mesh.box(Vector3(.93,.57,side*.52),Vector3(.18,.17,.25),EDGE)
		mesh.box(Vector3(-.82,.78,side*.55),Vector3(.26,.29,.27),YELLOW)
	# Broad bolted turret bearing is visible around the short, solid turret.
	mesh.cylinder(Vector3(-.08,.99,0),.65,.16,Vector3.UP,STEEL,12)
	mesh.cylinder(Vector3(-.08,1.065,0),.58,.095,Vector3.UP,YELLOW,12)
	_mark(mesh,Vector3(.74,1.045,0),Vector3.UP,owner,.18)
	var gun=_part()
	gun.prism([Vector2(-.62,0),Vector2(-.60,.37),Vector2(-.28,.48),Vector2(.42,.46),Vector2(.65,.22),Vector2(.65,0)],1.15,Vector3.ZERO,OLD_PAINT)
	gun.box(Vector3(.58,.25,0),Vector3(.29,.36,.56),YELLOW)
	gun.cylinder(Vector3(1.07,.28,0),.096,1.04,Vector3.RIGHT,STEEL,8)
	gun.cylinder(Vector3(1.59,.28,0),.14,.13,Vector3.RIGHT,ARMOR,8)
	_joint(gun,Vector3(-.18,.23,.62),.53,.27)
	gun.box(Vector3(-.22,.525,0),Vector3(.51,.09,.49),ARMOR)
	_mark(gun,Vector3(-.18,.59,0),Vector3.UP,owner,.22)
	_mark(gun,Vector3(.17,.24,-.635),Vector3.FORWARD,owner,.16)
	return _finish(mesh,"tank","unit",gun,Vector3(-.08,1.09,0),Vector3(1.675,.28,0))

static func _assault(mesh, owner: Color) -> Dictionary:
	_tracks(mesh,2.55,1.79,5)
	mesh.prism([Vector2(-1.17,.44),Vector2(-1.08,1.06),Vector2(.12,1.12),Vector2(1.18,.73),Vector2(1.18,.44)],1.44,Vector3.ZERO,OLD_PAINT)
	mesh.box(Vector3(.96,.59,0),Vector3(.37,.31,1.65),ARMOR)
	for side in [-1.0,1.0]:
		_joint(mesh,Vector3(-.28,.86,side*.783),.78,.40,Vector3(0,0,side))
		mesh.box(Vector3(-.79,1.10,side*.57),Vector3(.45,.24,.26),YELLOW)
	mesh.cylinder(Vector3(.10,1.09,0),.57,.16,Vector3.UP,STEEL,10)
	_mark(mesh,Vector3(-.72,1.285,0),Vector3.UP,owner,.20)
	var gun=_part()
	# A short support gun behind a broad shield; no burner tanks or furnace.
	gun.box(Vector3(-.16,.19,0),Vector3(.62,.42,.77),ARMOR)
	gun.prism([Vector2(.08,-.12),Vector2(.12,.64),Vector2(.30,.72),Vector2(.44,.62),Vector2(.44,-.12)],1.16,Vector3.ZERO,YELLOW)
	gun.cylinder(Vector3(.64,.28,0),.15,.82,Vector3.RIGHT,STEEL,10)
	gun.cylinder(Vector3(1.075,.28,0),.20,.12,Vector3.RIGHT,ARMOR,10)
	gun.cylinder(Vector3(1.142,.28,0),.12,.015,Vector3.RIGHT,INK,10,false)
	for side in [-1.0,1.0]:_joint(gun,Vector3(.27,.31,side*.618),.26,.33,Vector3(0,0,side))
	_mark(gun,Vector3(-.18,.46,0),Vector3.UP,owner,.19)
	return _finish(mesh,"assault","unit",gun,Vector3(.10,1.17,0),Vector3(1.15,.28,0))

static func _aa(mesh, owner: Color) -> Dictionary:
	_tracks(mesh,2.30,1.65,4)
	mesh.box(Vector3(-.06,.71,0),Vector3(1.97,.39,1.34),OLD_PAINT)
	mesh.prism([Vector2(.35,.66),Vector2(.35,1.01),Vector2(.98,.84),Vector2(1.12,.66)],1.10,Vector3.ZERO,YELLOW)
	mesh.cylinder(Vector3(-.13,.90,0),.56,.18,Vector3.UP,STEEL,10)
	for side in [-1.0,1.0]:
		for x in [-.79,.75]:_outrigger(mesh,x,side*.77,.26)
	_mark(mesh,Vector3(.70,1.03,0),Vector3.UP,owner,.18)
	_mark(mesh,Vector3(-.30,.73,.728),Vector3.BACK,owner,.18)
	var gun=_part()
	gun.box(Vector3(-.16,.18,0),Vector3(.64,.38,.82),ARMOR)
	for side in [-1.0,1.0]:
		gun.box(Vector3(.04,.49,side*.38),Vector3(.70,.45,.27),YELLOW)
		for z_offset in [-.09,.09]:gun.cylinder(Vector3(.54,.64,side*.38+z_offset),.058,.99,Vector3(1,.16,0),STEEL,8)
	gun.line(Vector3(-.39,.27,-.24),Vector3(-.39,.94,-.24),.035,ARMOR)
	gun.box(Vector3(-.39,1.03,-.24),Vector3(.31,.20,.07),EDGE)
	_mark(gun,Vector3(-.14,.445,0),Vector3.UP,owner,.18)
	return _finish(mesh,"aa","unit",gun,Vector3(-.13,.87,0),Vector3(1.07,.72,0))


static func _rig(mesh, owner: Color) -> Dictionary:
	_tracks(mesh,2.67,1.80,6)
	mesh.box(Vector3(-.07,.74,0),Vector3(2.20,.40,1.47),ARMOR)
	_room(mesh,Vector3(-.77,1.14,-.24),Vector3(.80,.58,1.02),true)
	mesh.box(Vector3(.43,1.79,-.24),Vector3(.29,2.07,.34),ARMOR)
	for side in [-1.0,1.0]:_outrigger(mesh,.43,side*.77,.32)
	for y in [1.08,1.67,2.27]:mesh.box(Vector3(.43,y,-.24),Vector3(.52,.13,.46),YELLOW)
	_brace(mesh,Vector3(.18,1.03,-.25),Vector3(.58,2.63,-.25),.047)
	mesh.line(Vector3(.44,2.79,-.24),Vector3(1.35,1.92,-.24),.11,YELLOW)
	mesh.line(Vector3(1.35,1.92,-.24),Vector3(1.35,1.25,-.24),.034,STEEL)
	mesh.line(Vector3(1.35,1.25,-.24),Vector3(1.53,1.36,-.24),.05,INK)
	_window(mesh,Vector3(-.76,1.15,.305),.40,.25)
	_mark(mesh,Vector3(-.76,1.51,-.24),Vector3.UP,owner,.20)
	_mark(mesh,Vector3(-.03,.79,.81),Vector3.BACK,owner,.20)
	return _finish(mesh,"rig","unit")


static func _artillery(mesh, owner: Color) -> Dictionary:
	_wheels(mesh,[-1.05,-.50,.68],.66,.28)
	mesh.box(Vector3(-.12,.53,0),Vector3(2.48,.21,1.11),ARMOR)
	mesh.prism([Vector2(.24,.56),Vector2(.34,1.16),Vector2(.86,1.21),Vector2(1.13,.90),Vector2(1.13,.56)],1.05,Vector3.ZERO,YELLOW)
	mesh.box(Vector3(-.65,.80,0),Vector3(1.16,.34,1.12),OLD_PAINT)
	for side in [-1.0,1.0]:
		mesh.box(Vector3(-.63,.99,side*.59),Vector3(1.42,.13,.15),EDGE)
		mesh.line(Vector3(-.83,.71,side*.41),Vector3(-1.27,.31,side*.58),.10,ARMOR)
		mesh.box(Vector3(-1.27,.22,side*.58),Vector3(.30,.28,.34),YELLOW)
		mesh.box(Vector3(-1.28,.065,side*.58),Vector3(.43,.085,.46),EDGE)
	_mark(mesh,Vector3(.62,1.275,0),Vector3.UP,owner,.18)
	_mark(mesh,Vector3(-.59,.83,.667),Vector3.BACK,owner,.20)
	var gun=_part()
	gun.box(Vector3(-.13,.19,0),Vector3(.81,.40,.90),ARMOR)
	for side in [-1.0,1.0]:
		gun.prism([Vector2(-.46,-.01),Vector2(-.46,.66),Vector2(-.02,.74),Vector2(.24,.31),Vector2(.24,-.01)],.16,Vector3(0,0,side*.42),YELLOW)
		gun.cylinder(Vector3(.51,.16,side*.31),.066,1.06,Vector3.RIGHT,STEEL,8,false)
	gun.cylinder(Vector3(.94,.40,0),.12,1.78,Vector3.RIGHT,EDGE,10)
	gun.cylinder(Vector3(1.86,.40,0),.18,.19,Vector3.RIGHT,ARMOR,8)
	_mark(gun,Vector3(-.22,.78,0),Vector3.UP,owner,.20)
	return _finish(mesh,"artillery","unit",gun,Vector3(-.63,1.0,0),Vector3(1.97,.40,0))

static func _repair_vehicle(mesh, owner: Color) -> Dictionary:
	_wheels(mesh,[-.80,.78],.66,.31)
	mesh.box(Vector3(-.02,.53,0),Vector3(2.15,.26,1.22),ARMOR)
	_room(mesh,Vector3(.61,1.02,0),Vector3(.87,.72,1.20),true)
	mesh.box(Vector3(-.64,.80,0),Vector3(1.08,.31,1.10),OLD_PAINT)
	_tool_cabinet(mesh,Vector3(-.70,1.19,-.28),.76,.58,.45)
	# Folded worktable hangs on a straight hinge with two short folded legs.
	mesh.box(Vector3(-.67,.87,.64),Vector3(.87,.42,.08),YELLOW)
	mesh.cylinder(Vector3(-.67,1.10,.67),.043,.91,Vector3.RIGHT,STEEL,8,false)
	for x in [-.99,-.34]:mesh.box(Vector3(x,.83,.703),Vector3(.06,.30,.038),ARMOR,false)
	# Compact elbow arm reaches the work area, without a tall recovery mast.
	mesh.box(Vector3(-1.06,1.03,.30),Vector3(.19,.28,.24),ARMOR)
	mesh.line(Vector3(-1.06,1.13,.30),Vector3(-.96,1.76,.30),.070,YELLOW)
	mesh.line(Vector3(-.96,1.76,.30),Vector3(-.46,1.45,.30),.065,ARMOR)
	for point in [Vector3(-1.06,1.13,.30),Vector3(-.96,1.76,.30),Vector3(-.46,1.45,.30)]:mesh.cylinder(point,.11,.13,Vector3.BACK,STEEL,8,false)
	mesh.box(Vector3(-.46,1.37,.30),Vector3(.19,.22,.22),YELLOW)
	_window(mesh,Vector3(.61,1.09,.652),.55,.29)
	_mark(mesh,Vector3(.61,1.52,0),Vector3.UP,owner,.23)
	_mark(mesh,Vector3(-.66,.86,.75),Vector3.BACK,owner,.18)
	return _finish(mesh,"repair_vehicle","unit")

static func _recycler(mesh, owner: Color) -> Dictionary:
	_wheels(mesh,[-.97,-.37,.51],.67,.28)
	mesh.box(Vector3(-.12,.49,0),Vector3(2.30,.24,1.18),ARMOR)
	_room(mesh,Vector3(.59,.99,0),Vector3(.86,.79,1.11),true)
	mesh.box(Vector3(-.69,.76,0),Vector3(.93,.36,1.21),OLD_PAINT)
	# Reinforced rear, crosswise winch and a low towing arm rescue live vehicles.
	mesh.box(Vector3(-1.16,.54,0),Vector3(.21,.39,1.49),YELLOW)
	mesh.cylinder(Vector3(-.65,1.03,0),.23,.88,Vector3.BACK,STEEL,10)
	for side in [-1.0,1.0]:
		mesh.cylinder(Vector3(-.65,1.03,side*.47),.29,.12,Vector3.BACK,ARMOR,10)
		mesh.box(Vector3(-.65,.80,side*.46),Vector3(.37,.33,.17),YELLOW)
		_joint(mesh,Vector3(-1.13,.66,side*.78),.21,.34,Vector3(0,0,side))
	for z in [-.22,-.11,0,.11,.22]:mesh.cylinder(Vector3(-.65,1.03,z),.238,.027,Vector3.BACK,RUBBER,10,false)
	mesh.prism([Vector2(-1.55,.31),Vector2(-1.42,.62),Vector2(-.77,.96),Vector2(-.51,.82),Vector2(-1.19,.48),Vector2(-1.29,.31)],.23,Vector3.ZERO,ARMOR)
	mesh.box(Vector3(-1.43,.29,0),Vector3(.19,.17,.64),STEEL)
	for side in [-1.0,1.0]:mesh.box(Vector3(-1.48,.34,side*.25),Vector3(.24,.24,.16),YELLOW)
	mesh.line(Vector3(-.86,1.10,0),Vector3(-1.39,.58,0),.042,RUBBER)
	_window(mesh,Vector3(.59,1.05,.595),.48,.26)
	_mark(mesh,Vector3(.59,1.51,0),Vector3.UP,owner,.22)
	_mark(mesh,Vector3(-.36,.77,.666),Vector3.BACK,owner,.18)
	return _finish(mesh,"recycler","unit")

static func _transport(mesh, owner: Color) -> Dictionary:
	_wheels(mesh,[-1.0,-.16,.94],.67,.29)
	mesh.prism([Vector2(-1.27,.48),Vector2(-1.19,1.40),Vector2(.52,1.40),Vector2(1.30,1.09),Vector2(1.30,.48)],1.27,Vector3.ZERO,OLD_PAINT)
	mesh.box(Vector3(-.27,1.47,0),Vector3(1.81,.13,1.38),YELLOW)
	for x in [-.94,-.35,.24]:
		_window(mesh,Vector3(x,1.19,.675),.31,.16)
		_patch(mesh,Vector3(x,.78,-.69),Vector3(.49,.47,.05),Vector3.FORWARD)
	_door(mesh,Vector3(-1.14,.89,.697),.40,.66)
	_oriented_box(mesh,Vector3(-1.288,.92,0),Vector3(.93,.67,.055),Vector3.LEFT,ARMOR)
	for z in [-.30,.30]:mesh.box(Vector3(-1.331,.92,z),Vector3(.035,.68,.063),STEEL,false)
	mesh.box(Vector3(-1.37,.57,0),Vector3(.18,.16,1.15),EDGE)
	mesh.box(Vector3(1.28,.61,0),Vector3(.22,.21,1.35),ARMOR)
	_mark(mesh,Vector3(-.20,1.59,0),Vector3.UP,owner,.25)
	_mark(mesh,Vector3(.62,.81,.722),Vector3.BACK,owner,.22)
	return _finish(mesh,"transport","unit")


static func _advanced(mesh, owner: Color) -> Dictionary:
	_tracks(mesh,2.53,1.85,5)
	mesh.prism([Vector2(-1.16,.43),Vector2(-1.07,.92),Vector2(.62,.96),Vector2(1.17,.67),Vector2(1.17,.43)],1.47,Vector3.ZERO,ARMOR)
	for side in [-1.0,1.0]:
		mesh.box(Vector3(-.78,1.11,side*.44),Vector3(.56,.37,.34),YELLOW)
		_joint(mesh,Vector3(.06,.77,side*.792),.70,.37,Vector3(0,0,side))
	mesh.cylinder(Vector3(-.08,1.00,0),.68,.20,Vector3.UP,STEEL,12)
	_mark(mesh,Vector3(-.75,1.35,0),Vector3.UP,owner,.20)
	var gun=_part()
	gun.box(Vector3(-.20,.25,0),Vector3(.97,.49,1.00),OLD_PAINT)
	# Parallel load-bearing electromagnetic rails on a solid cradle, neither
	# luminous coils nor an unsupported thin tube.
	gun.box(Vector3(.73,.05,0),Vector3(1.86,.22,.78),ARMOR)
	for side in [-1.0,1.0]:
		gun.box(Vector3(.94,.36,side*.22),Vector3(1.91,.24,.21),STEEL)
		gun.box(Vector3(.84,.57,side*.23),Vector3(1.59,.11,.25),YELLOW)
		gun.line(Vector3(-.20,.16,side*.42),Vector3(.82,.23,side*.42),.10,ARMOR)
		gun.box(Vector3(.15,.28,side*.40),Vector3(.25,.54,.19),YELLOW)
		gun.box(Vector3(1.11,.28,side*.40),Vector3(.25,.54,.19),YELLOW)
	gun.box(Vector3(1.94,.36,0),Vector3(.15,.41,.74),ARMOR)
	gun.box(Vector3(2.023,.36,0),Vector3(.017,.14,.22),INK,false)
	_joint(gun,Vector3(-.20,.27,.55),.54,.32)
	_mark(gun,Vector3(-.20,.565,0),Vector3.UP,owner,.22)
	return _finish(mesh,"advanced","unit",gun,Vector3(-.08,1.11,0),Vector3(2.04,.36,0))

static func _propeller(mesh, center: Vector3, radius: float) -> void:
	# This is the static modelling pose. Animation can later rotate the propeller
	# independently; aircraft hull geometry stays cached and solid.
	mesh.cylinder(center,.085,.11,Vector3.RIGHT,ARMOR,8,false)
	for i in range(3):
		var angle: float=float(i)*TAU/3.0+.27
		mesh.line(center+Vector3(0,cos(angle)*.08,sin(angle)*.08),center+Vector3(0,cos(angle)*radius,sin(angle)*radius),.053,EDGE)


static func _fighter(mesh, owner: Color) -> Dictionary:
	# Maintained propeller escort: solid fuselage, thick wing roots and regular
	# fasteners. Workshop reliability comes from joints, not mismatched salvage.
	mesh.prism([Vector2(-1.46,.23),Vector2(-1.27,.55),Vector2(.71,.63),Vector2(1.42,.43),Vector2(1.50,.26),Vector2(-1.30,.12)],.52,Vector3.ZERO,OLD_PAINT)
	mesh.slab([Vector2(-.46,-1.85),Vector2(.32,-1.77),Vector2(.59,-.22),Vector2(.59,.22),Vector2(.32,1.77),Vector2(-.46,1.85),Vector2(-.70,.24),Vector2(-.70,-.24)],.14,Vector3(0,.32,0),YELLOW)
	mesh.slab([Vector2(-.35,-.82),Vector2(.07,-.76),Vector2(.30,-.14),Vector2(.30,.14),Vector2(.07,.76),Vector2(-.35,.82)],.10,Vector3(-1.18,.48,0),OLD_PAINT)
	mesh.prism([Vector2(-.36,0),Vector2(-.28,.60),Vector2(.04,.55),Vector2(.26,0)],.11,Vector3(-1.16,.47,0),YELLOW)
	mesh.cylinder(Vector3(1.40,.35,0),.27,.35,Vector3.RIGHT,ARMOR,10)
	_propeller(mesh,Vector3(1.615,.35,0),.60)
	mesh.prism([Vector2(-.21,0),Vector2(-.06,.22),Vector2(.25,.16),Vector2(.34,0)],.35,Vector3(.32,.64,0),GLASS)
	for side in [-1.0,1.0]:
		_joint(mesh,Vector3(-.01,.44,side*1.37),.52,.50,Vector3.UP)
		mesh.box(Vector3(-.03,.48,side*.40),Vector3(.76,.13,.30),ARMOR)
		mesh.line(Vector3(-.39,.55,side*.28),Vector3(-.28,.40,side*.89),.05,STEEL)
		_mark(mesh,Vector3(.04,.475,side*.86),Vector3.UP,owner,.22)
	_mark(mesh,Vector3(-1.19,.82,.090),Vector3.BACK,owner,.15)
	return _finish(mesh,"fighter","unit",null,Vector3.ZERO,Vector3.ZERO,{"muzzle_pos":Vector3(1.64,.35,0)})


static func _attacker(mesh, owner: Color) -> Dictionary:
	# Broad wing attack plane with regular stores, thick cockpit protection and
	# short twin engines secured by full-width mounting plates.
	mesh.prism([Vector2(-1.37,.25),Vector2(-1.20,.64),Vector2(.61,.74),Vector2(1.42,.44),Vector2(1.51,.23),Vector2(-1.22,.12)],.62,Vector3.ZERO,ARMOR)
	mesh.slab([Vector2(-.59,-1.79),Vector2(.61,-1.79),Vector2(.66,-.24),Vector2(.66,.24),Vector2(.61,1.79),Vector2(-.59,1.79)],.20,Vector3(0,.36,0),OLD_PAINT)
	for side in [-1.0,1.0]:
		mesh.cylinder(Vector3(.20,.36,side*.76),.25,1.37,Vector3.RIGHT,YELLOW,10)
		_propeller(mesh,Vector3(.93,.36,side*.76),.42)
		mesh.cylinder(Vector3(.11,.13,side*1.30),.09,.70,Vector3.RIGHT,STEEL,8)
		_joint(mesh,Vector3(-.11,.50,side*1.41),.65,.51,Vector3.UP)
		mesh.box(Vector3(.15,.59,side*.39),Vector3(.92,.15,.30),YELLOW)
		mesh.box(Vector3(.08,.18,side*1.30),Vector3(.61,.08,.25),ARMOR)
	mesh.slab([Vector2(-.32,-.87),Vector2(.19,-.83),Vector2(.25,.83),Vector2(-.32,.87)],.12,Vector3(-1.22,.54,0),YELLOW)
	for side in [-1.0,1.0]:mesh.prism([Vector2(-.31,0),Vector2(-.27,.49),Vector2(.05,.49),Vector2(.24,0)],.10,Vector3(-1.18,.54,side*.67),OLD_PAINT)
	mesh.box(Vector3(.52,.77,0),Vector3(.72,.15,.60),YELLOW)
	mesh.box(Vector3(.52,.86,0),Vector3(.55,.15,.43),GLASS)
	_mark(mesh,Vector3(.05,.585,1.11),Vector3.UP,owner,.24)
	_mark(mesh,Vector3(.05,.585,-1.11),Vector3.UP,owner,.24)
	_mark(mesh,Vector3(-1.16,.80,.754),Vector3.BACK,owner,.15)
	return _finish(mesh,"attacker","unit",null,Vector3.ZERO,Vector3.ZERO,{"muzzle_pos":Vector3(1.54,.32,0)})


static func _air_transport(mesh, owner: Color) -> Dictionary:
	# Square cargo fuselage and reinforced high wing, stout landing gear and a
	# broad rear door distinguish a dependable transport from combat aircraft.
	mesh.prism([Vector2(-1.71,.22),Vector2(-1.42,.68),Vector2(-.72,1.00),Vector2(.71,1.00),Vector2(1.68,.67),Vector2(1.85,.38),Vector2(1.70,.16),Vector2(-1.49,.12)],.92,Vector3.ZERO,OLD_PAINT)
	mesh.slab([Vector2(-.48,-2.05),Vector2(.64,-2.02),Vector2(.77,-.35),Vector2(.77,.35),Vector2(.64,2.02),Vector2(-.48,2.05)],.22,Vector3(0,.86,0),YELLOW)
	for side in [-1.0,1.0]:
		mesh.cylinder(Vector3(.49,.72,side*.98),.30,1.28,Vector3.RIGHT,ARMOR,10)
		_propeller(mesh,Vector3(1.19,.72,side*.98),.50)
		_joint(mesh,Vector3(.02,1.035,side*1.60),.74,.61,Vector3.UP)
		mesh.box(Vector3(.18,1.07,side*.47),Vector3(1.01,.13,.37),ARMOR)
		mesh.line(Vector3(-.07,.47,side*.37),Vector3(.12,.05,side*.73),.075,STEEL)
		mesh.cylinder(Vector3(.12,-.01,side*.76),.18,.16,Vector3.BACK,RUBBER,8)
	mesh.slab([Vector2(-.36,-1.07),Vector2(.18,-1.00),Vector2(.29,.98),Vector2(-.36,1.07)],.14,Vector3(-1.41,.65,0),OLD_PAINT)
	mesh.prism([Vector2(-.36,0),Vector2(-.31,.82),Vector2(.08,.80),Vector2(.30,0)],.13,Vector3(-1.35,.65,0),YELLOW)
	for x in [-.98,-.57,-.14,.29,.70]:_window(mesh,Vector3(x,.69,.498),.23,.16)
	_door(mesh,Vector3(-.49,.48,.52),.62,.62)
	_oriented_box(mesh,Vector3(-1.51,.47,0),Vector3(.67,.45,.055),Vector3.LEFT,ARMOR)
	mesh.box(Vector3(-1.56,.24,0),Vector3(.12,.13,.73),YELLOW)
	mesh.box(Vector3(1.34,.81,0),Vector3(.45,.24,.63),GLASS)
	_mark(mesh,Vector3(.07,1.065,-1.23),Vector3.UP,owner,.26)
	_mark(mesh,Vector3(.07,1.065,1.23),Vector3.UP,owner,.26)
	_mark(mesh,Vector3(-1.38,1.19,.109),Vector3.BACK,owner,.19)
	return _finish(mesh,"air_transport","unit")
