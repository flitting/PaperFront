extends RefCounted
class_name BattlefieldRuins
const VOLUME = preload("res://scripts/volume_models.gd")
static var cache: Dictionary = {}

static func apply_layout(map: Dictionary) -> void:
	# Retire solitary boulder/pillar cells; trees and timber fences stay put.
	for field in ["decorations","foreground_grove","north_context"]:
		var kept: Array = []
		for item in map.get(field,[]):
			if str(item.kind) in ["rock","ruin"]:
				var p:=Vector2(item.pos[0],item.pos[1])
				if int(map.terrain[int(p.y)][int(p.x)])==4:map.terrain[int(p.y)][int(p.x)]=0
			else:kept.append(item)
		if map.has(field):map[field]=kept
	map.ruins=[]
	var centers: Array[Vector2]=[]
	var rng:=RandomNumberGenerator.new()
	rng.seed=int(map.seed)+731915
	# Seeded random, separated same-kind clusters. Mirrored locations retain
	# equal terrain for the two starting sides; no wall/house compound pairing.
	for attempt in range(9600 if int(map.size) >= 640 else 2400):
		var center:=Vector2(rng.randi_range(5,int(map.size)/2-5)+.5,rng.randi_range(5,int(map.size)-6)+.5)
		var mirror:=Vector2(float(map.size)-center.x,center.y)
		var close: bool=false
		for old in centers:
			if old.distance_to(center)<15:close=true;break
		if close or not _safe_compound(map,center) or not _safe_compound(map,mirror):continue
		var kind: String="wall" if rng.randf()<.55 else "house"
		if centers.size()==2:kind="house" if map.ruins[0].kind=="wall" else "wall"
		var turn: int=rng.randi_range(0,3)
		var variant: int=rng.randi_range(0,2)
		var parts: Array=[]
		if kind=="wall":
			parts=[[Vector2(-1.5,-.3),0.0],[Vector2(1.5,-.3),0.0]]
			if variant==1:parts.append([Vector2(1.5,1.55),PI*.5])
		else:
			parts=[[Vector2(-1.65,-1.45),0.0],[Vector2(1.65,1.45),PI]]
		for c in [center,mirror]:
			var group: int=centers.size()
			centers.append(c)
			var yaw: float=turn*PI*.5
			for part in parts:
				var rotation: float=yaw+float(part[1])
				var half:=Vector2(1.5,1.35) if kind=="house" else Vector2(1.5,.34)
				if posmod(roundi(rotation/(PI*.5)),2)==1:half=Vector2(half.y,half.x)
				map.ruins.append({"id":map.ruins.size(),"group":group,"kind":kind,"pos":c+(part[0] as Vector2).rotated(-yaw),"half":half,"yaw":rotation,"hp":900.0 if kind=="house" else 360.0,"max_hp":900.0 if kind=="house" else 360.0,"variant":variant})
		if centers.size()>=(4 if int(map.size)==48 else 240 if int(map.size)>=640 else 60 if int(map.size)>=320 else 20):break
	register_trees(map)

## Keep tree art in its original prop lists, while neutral footprints own its
## collision and health. The static grid has a node under every removable tree.
static func register_trees(map: Dictionary) -> void:
	if not map.has("ruins"): map.ruins = []
	var occupied: Dictionary = {}
	for ruin in map.ruins:
		if ruin.kind == "tree": occupied[Vector2i(floori(ruin.pos.x), floori(ruin.pos.y))] = int(ruin.id)
	for field in ["decorations", "foreground_grove", "north_context"]:
		for item in map.get(field, []):
			if item.get("kind") != "tree": continue
			var pos := Vector2(float(item.pos[0]), float(item.pos[1]))
			var cell := Vector2i(floori(pos.x), floori(pos.y))
			if int(map.terrain[cell.y][cell.x]) == 4: map.terrain[cell.y][cell.x] = 0
			if occupied.has(cell):
				item.ruin_id = occupied[cell]
				continue
			var id: int = map.ruins.size()
			item.ruin_id = id
			occupied[cell] = id
			map.ruins.append({"id": id, "kind": "tree", "pos": pos, "half": Vector2(.48, .48), "cell": cell, "yaw": float(item.get("yaw", 0.0)), "hp": 180.0, "max_hp": 180.0, "variant": int(item.get("variant", posmod(cell.x * 7 + cell.y * 11, 3)))})

static func _safe_compound(map: Dictionary, p: Vector2) -> bool:
	for start in map.starts:
		if p.distance_to(Vector2(start[0],start[1]))<15:return false
	for mine in map.mines:
		if p.distance_to(Vector2(mine.pos[0],mine.pos[1]))<7:return false
	var level: float=float(map.heights[int(p.y)][int(p.x)])
	for z in range(floori(p.y-4),ceili(p.y+4)):
		for x in range(floori(p.x-4),ceili(p.x+4)):
			if x<2 or z<2 or x>=int(map.size)-2 or z>=int(map.size)-2:return false
			if int(map.terrain[z][x])!=0 or absf(float(map.heights[z][x])-level)>.01:return false
	return true

static func meshes(kind: String, variant: int) -> Dictionary:
	var key:=kind+str(variant)
	if cache.has(key):return cache[key]
	var intact:=VOLUME.CraftMesh.new()
	var rubble:=VOLUME.CraftMesh.new()
	if kind=="wall":
		for row in range(3):
			for column in range(7):
				var left: float=-1.35+column*.46-(.23 if row%2 else 0)
				var low: float=maxf(-1.35,left)
				var high: float=minf(1.35,left+.44)
				if high-low<.05:continue
				_stone(intact,Vector3((low+high)*.5,.16+row*.245,0),Vector3(high-low,.225,.49),row*9+column+variant)
		for x in [-1.42,1.42]:
			intact.box(Vector3(x,.43,0),Vector3(.14,.86,.57),Color("756044"),false)
			intact.line(Vector3(x-.04,.1,-.29),Vector3(x-.02,.8,-.29),.009,Color("3c3228"))
		_scatter(intact,Vector2(1.4,.31),variant,9,.12)
		_scatter(rubble,Vector2(1.4,.31),variant,16,.2)
	else:
		intact.box(Vector3(0,.015,0),Vector3(2.75,.03,2.4),Color("b39463"),false)
		rubble.box(Vector3(0,.015,0),Vector3(2.75,.03,2.4),Color("b39463"),false)
		# Broken thick walls, real empty window apertures and stepped roof line.
		for row in range(7):
			for column in range(6):
				var height_limit: int=[4,6,7,5,7,6][column]
				if row>=height_limit or (column in [2,3] and row in [2,3]):continue
				_stone(intact,Vector3(-1.2+column*.47+(row%2)*.09,.21+row*.34,-1.06),Vector3(.448,.32,.38),row*7+column+variant)
		for row in range(6):
			for column in range(5):
				if row>=[6,5,3,2,1][column] or (column==1 and row in [2,3]):continue
				_stone(intact,Vector3(1.22,.21+row*.34,-.65+column*.43),Vector3(.38,.32,.41),row*5+column+13+variant)
		for column in range(5):
			for row in range([2,1,0,1,3][column]):
				_stone(intact,Vector3(-1.13+column*.49,.21+row*.34,1.08),Vector3(.46,.32,.36),column*3+row+variant)
		intact.box(Vector3(1.4,.73,-.22),Vector3(.07,1.46,.08),Color("987044"),false)
		intact.line(Vector3(-.85,.12,.65),Vector3(.4,.40,-.7),.07,Color("6d5138"))
		intact.line(Vector3(.78,.1,.72),Vector3(1.07,1.1,-.15),.065,Color("816348"))
		_scatter(intact,Vector2(1.4,1.23),variant,24,.17)
		_scatter(rubble,Vector2(1.4,1.23),variant,36,.25)
		for i in range(3):
			_stone(rubble,Vector3(-.9+i*.65,.22,-.8),Vector3(.5,.3,.4),i)
	cache[key]={"intact":intact.mesh(),"rubble":rubble.mesh()}
	var material:=ShaderMaterial.new()
	material.shader=load("res://assets/shaders/ruin_cardboard.gdshader")
	material.set_shader_parameter("paper_grain",load("res://assets/textures/pigment_noise.png"))
	cache[key].intact.surface_set_material(0,material)
	cache[key].rubble.surface_set_material(0,material)
	return cache[key]

static func _stone(mesh, center: Vector3, size: Vector3, salt: int) -> void:
	var half: Vector3=size*.5
	var chip: float=.024+float(posmod(salt*7,4))*.006
	var profile: Array=[Vector2(-half.x+chip,-half.y),Vector2(half.x-chip*.7,-half.y),Vector2(half.x,-half.y+chip),Vector2(half.x-chip*.4,half.y-chip),Vector2(half.x-chip*1.6,half.y),Vector2(-half.x+chip,half.y-chip*.3),Vector2(-half.x,half.y-chip*1.7),Vector2(-half.x,-half.y+chip)]
	var tint:=Color("cbb58f").lightened(float(posmod(salt*13,7)-3)*.022)
	var edges: Dictionary={}
	for i in range(profile.size()):edges[i]=Color("aa865a").lightened(float(i%3)*.025)
	mesh.prism(profile,size.z,center,tint,false,edges)
	for side in [-1.0,1.0]:
		var depth: float=side*(half.z+.003)
		for i in range(profile.size()):
			var a: Vector2=profile[i]
			var b: Vector2=profile[(i+1)%profile.size()]
			mesh.line(center+Vector3(a.x,a.y,depth),center+Vector3(b.x,b.y,depth),.011,Color("60472f"))
		var u: float=float(posmod(salt*7,5)-2)*size.x*.07
		var v: float=float(posmod(salt*3,5)-2)*size.y*.07
		mesh.face([center+Vector3(u-size.x*.22,v-size.y*.09,depth),center+Vector3(u+size.x*.17,v-size.y*.14,depth),center+Vector3(u+size.x*.08,v+size.y*.15,depth)],tint.darkened(.07),Vector3(0,0,side))
		if salt%2==0:
			mesh.line(center+Vector3(-.05,half.y*.4,depth),center+Vector3(.03,-half.y*.2,depth),.009,Color("987b55"))
	mesh.line(center+Vector3(-half.x+chip,-half.y,-half.z-.002),center+Vector3(half.x-chip,-half.y,-half.z-.002),.008,Color("6f5135"))
	if salt%3==0:
		mesh.line(center+Vector3(-.05,half.y*.4,-half.z-.004),center+Vector3(.03,-half.y*.2,-half.z-.004),.007,Color("8a6c49"))
	mesh.line(center+Vector3(-half.x+chip,half.y-chip*.3,-half.z-.003),center+Vector3(half.x-chip*1.6,half.y,-half.z-.003),.009,Color("eddbb4"))

static func _scatter(mesh, half: Vector2, variant: int, count: int, scale: float) -> void:
	for i in range(count):
		var x: float=sin(i*2.41+variant)*half.x*.94
		var z: float=cos(i*3.73+variant)*half.y*.92
		var size: float=scale*(.65+float(i%4)*.15)
		_stone(mesh,Vector3(x,size*.35+.02,z),Vector3(size*1.3,size*.7,size),i+variant)
