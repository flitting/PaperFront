extends RefCounted

# Sculpted tabletop pine from the supplied front/side/back/top reference.
# A dark enclosed heart supports thick, drooping, overlapping branch lobes.
# Each lobe is a closed volume; no crossed cards, stacked cones or open fins.
static func crown(builder: Node3D, target: Dictionary, variant: int) -> void:
	var height_scale: float = [0.80, 0.84, 0.88][variant]
	var phase: float = variant * 0.89
	var heart: Dictionary = builder._data()
	var profile: Array[Vector2] = [Vector2(0.42,0.12),Vector2(0.70,0.30),Vector2(1.08,0.29),Vector2(1.48,0.22),Vector2(1.86,0.16),Vector2(2.22,0.09),Vector2(2.47,0.0)]
	var rings: Array = []
	for p: Vector2 in profile:
		var ring: Array[Vector3] = []
		for i: int in 16:
			var a: float = TAU * float(i) / 16.0
			ring.append(Vector3(cos(a)*p.y, p.x*height_scale, sin(a)*p.y))
		rings.append(ring)
	for row: int in range(rings.size()-1):
		for i: int in 16:
			var j: int = (i+1)%16
			builder._quad(heart,rings[row][i],rings[row][j],rings[row+1][j],rings[row+1][i],Color("263e2d"),Vector3(rings[row][i].x,0,rings[row][i].z))
	for i: int in 16:
		builder._triangle(heart,Vector3(0,0.42*height_scale,0),rings[0][i],rings[0][(i+1)%16],Color("243829"),Vector3.DOWN)
	_smooth(heart)
	_append(target,heart)
	# radius, high root, drooping outer end, tangential half-width, lobe count.
	var whorls: Array = [
		[0.566, 1.25, 0.43, 0.194, 9],
		[0.473, 1.68, 0.87, 0.169, 8],
		[0.365, 2.04, 1.30, 0.143, 7],
		[0.249, 2.44, 1.76, 0.111, 6],
	]
	for layer: int in whorls.size():
		var plan: Array = whorls[layer]
		for lobe: int in int(plan[4]):
			var a: float = TAU * float(lobe) / float(plan[4]) + phase + float(layer)*1.13
			a += sin(float(lobe)*3.73+phase)*0.055
			var irregular: float = sin(float(lobe)*4.13 + float(layer)*2.67 + phase)
			var radius: float = float(plan[0]) * (0.96 + irregular * 0.045)
			var top: float = (float(plan[1]) + irregular*0.045) * height_scale
			var low: float = (float(plan[2]) + sin(a*3.0+phase)*0.055) * height_scale
			var width: float = float(plan[3]) * (0.97 + cos(a*4.0+phase)*0.065)
			_lobe(builder,target,a,radius,top,low,width,variant,layer,lobe)

static func _lobe(builder: Node3D, target: Dictionary, angle: float, radius: float, high: float, low: float, width: float, variant: int, layer: int, number: int) -> void:
	var data: Dictionary = builder._data()
	var out := Vector3(cos(angle),0,sin(angle))
	var across := Vector3(-out.z,0,out.x)
	# Broad rounded terminal pads, not sharp triangular leaf tips.
	var profile: Array[Vector3] = [Vector3(0,0,0),Vector3(.16,.42,.52),Vector3(.39,.79,.88),Vector3(.64,1,1),Vector3(.82,.91,.91),Vector3(.94,.58,.63),Vector3(1,0,0)]
	var rings: Array = []
	var centres: Array[Vector3] = []
	var tangent: Vector3 = (out*(radius-.045)+Vector3.DOWN*(high-low)).normalized()
	var upper: Vector3 = across.cross(tangent).normalized()
	if upper.y<0:upper=-upper
	var green: Color = [Color("304c36"),Color("35503b"),Color("2c4834")][variant]
	green=green.lerp(Color("4d6235") if (number+layer)%3 == 0 else Color("274739"), .14)
	green=green.lightened(float((number+layer)%3)*.012)
	for sample: Vector3 in profile:
		var t: float = sample.x
		var centre: Vector3 = out * lerpf(.035, radius, t) + Vector3.UP * lerpf(high,low,t)
		centre += upper * sin(t*PI) * width * .28
		centre += across * sin(t*PI) * sin(float(number)*2.3+layer) * width*.12
		centres.append(centre)
		var ring: Array[Vector3] = []
		for side: int in 10:
			var a: float = TAU*float(side)/10.0
			var bevel: float = 1.0 + sin(a*3.0+number)*.045
			ring.append(centre + across*cos(a)*width*sample.y*bevel + upper*sin(a)*width*.40*sample.z)
		rings.append(ring)
	for row: int in range(profile.size()-1):
		for side: int in 10:
			var next: int = (side+1)%10
			var a: Vector3 = rings[row][side]
			var b: Vector3 = rings[row][next]
			var c: Vector3 = rings[row+1][next]
			var d: Vector3 = rings[row+1][side]
			var normal: Vector3 = ((a+b+c+d)*.25-(centres[row]+centres[row+1])*.5).normalized()
			var upperness: float = normal.dot(upper)
			var color: Color = green.lerp(Color("71803f"),maxf(0,upperness)*.23)
			if upperness < -.12:color=color.darkened(.18)
			# Limited geometric pigment regions follow each branch, not a global camo.
			if side in [1,2,3] and row in [3,4]:color=color.lightened(.045)
			builder._quad(data,a,b,c,d,color,normal)
	_smooth(data)
	# Parameterise branch painting in its own across/length frame. UV is derived
	# after winding resolution so every duplicated corner keeps the right stroke.
	data["uvs"]=[]
	for vertex: Vector3 in data.vertices:
		var t: float = clampf((vertex-Vector3.UP*high).dot(tangent) / maxf(.1,Vector3(radius,high-low,0).length()),0,1)
		data.uvs.append(Vector2(vertex.dot(across)/maxf(width,.01)*.5+.5,t))
	_append(target,data)

static func _smooth(data: Dictionary) -> void:
	var sums: Dictionary={}
	for index: int in data.vertices.size():
		var p: Vector3=data.vertices[index]
		var key:=Vector3i(roundi(p.x*100000),roundi(p.y*100000),roundi(p.z*100000))
		sums[key]=(sums.get(key,Vector3.ZERO) as Vector3)+data.normals[index]
	for index: int in data.vertices.size():
		var p: Vector3=data.vertices[index]
		var key:=Vector3i(roundi(p.x*100000),roundi(p.y*100000),roundi(p.z*100000))
		data.normals[index]=(sums[key] as Vector3).normalized()

static func _append(target: Dictionary, data: Dictionary) -> void:
	if not target.has("uvs"):target["uvs"]=[]
	for index: int in data.vertices.size():
		target.vertices.append(data.vertices[index] * Vector3(1.04,1.0,1.04))
		target.normals.append((data.normals[index] / Vector3(1.04,1.0,1.04)).normalized())
		target.colors.append(data.colors[index])
		target.uvs.append(data.uvs[index] if data.has("uvs") else Vector2(.5,.2))

static func trunk(builder: Node3D, data: Dictionary, detailed: bool = true, ink: bool = true) -> void:
	# A short, flared brown trunk is visible below the lower drooping branches.
	var levels: Array[Vector2]=[Vector2(.025,.19),Vector2(.15,.13),Vector2(.39,.086),Vector2(.73,.069)]
	var rings: Array=[]
	for p: Vector2 in levels:
		var ring: Array[Vector3]=[]
		for i: int in 10:
			var a: float=TAU*float(i)/10.0
			var r: float=p.y*(1+sin(a*5.0+1.1)*.13)
			ring.append(Vector3(cos(a)*r,p.x,sin(a)*r))
		rings.append(ring)
	for row: int in range(levels.size()-1):
		for i: int in 10:
			var j: int=(i+1)%10
			var normal:=Vector3(rings[row][i].x,0,rings[row][i].z).normalized()
			builder._quad(data,rings[row][i],rings[row][j],rings[row+1][j],rings[row+1][i],Color("705238").lightened(float(i%3)*.055),normal)
			if ink:builder._ink_strip(data,rings[row][i].lerp(rings[row][j],.32),rings[row+1][i].lerp(rings[row+1][j],.46),normal,Color("3c3026"),.013)
	for i: int in 5:
		var a: float=float(i)*TAU/5.0+.33
		var out:=Vector3(cos(a),0,sin(a))
		var side:=Vector3(-out.z,0,out.x)*.058
		builder._triangle(data,out*.09+Vector3.UP*.29,out*.30+Vector3.UP*.016,out*.1+side,Color("61452f"),Vector3.UP)
		builder._triangle(data,out*.09+Vector3.UP*.29,out*.1-side,out*.30+Vector3.UP*.016,Color("85643f"),Vector3.UP)
	# Unequal stones and a few leaves, no round pedestal or identical plant pots.
	for i: int in 3:
		var rock: Dictionary=builder._data()
		if detailed:
			builder._rock(rock,i)
		else:
			# The three root stones are only a few pixels beyond 45m. Retain
			# their separate positions and volume without the subpixel chipping.
			builder._box(rock,Vector3(0,.24,0),Vector3(.68,.48,.60),Color("8b8064"))
		var a: float=float(i)*2.27+.51
		var centre:=Vector3(cos(a)*.26,0,sin(a)*.26)
		var scale:=Vector3(.28,.20,.24)*(1+float(i%2)*.25)
		for j: int in rock.vertices.size():
			data.vertices.append(centre+rock.vertices[j]*scale)
			data.normals.append((rock.normals[j]/scale).normalized())
			data.colors.append(rock.colors[j].darkened(.12))
