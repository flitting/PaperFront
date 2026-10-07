extends RefCounted
## Render-only neutral ruins, kept outside the map/simulation preload graph.
const VOLUME = preload("res://scripts/volume_models.gd")
static var cache: Dictionary = {}

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
