extends RefCounted

# Printed masonry and wood strokes over the bridge's existing closed solids.
# All polygons are clipped to the real flat face, then lifted by only 3 mm.
# This helper authors no collision, transforms, states or navigable geometry.
const MORTAR := Color("514c40")
const OFFSET: float = 0.003


static func plank_segments(length: float) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var count: int = maxi(1, ceili(length / 0.62))
	var half: float = minf(0.58, length) * 0.5
	for index: int in count:
		var center: float = -length * 0.5 + 0.30 + float(index) * 0.62
		var left: float = -length * 0.5 if index == 0 else center - half
		var right: float = length * 0.5 if index == count - 1 else center + half
		if right > left: result.append(Vector2(left, right))
	return result


static func arch(builder, data: Dictionary, length: float, breadth: float, turn: Basis, water_depth: float = 2.65) -> void:
	var radius: float=maxf(1.0,length*.5-.67)
	var inner: float=maxf(.5,radius-.42)
	var centre_y: float=minf(-radius-.14,-water_depth)
	for stone: int in range(13):
		var a: float=float(stone)*PI/13.0
		var b: float=float(stone+1)*PI/13.0
		var oa:=Vector2(cos(a)*radius,centre_y+sin(a)*radius)
		var ob:=Vector2(cos(b)*radius,centre_y+sin(b)*radius)
		var ia:=Vector2(cos(a)*inner,centre_y+sin(a)*inner)
		var ib:=Vector2(cos(b)*inner,centre_y+sin(b)*inner)
		var ring: Array[Vector2]=[oa,ob,ib,ia]
		var fill: Array[Vector2]=[oa,Vector2(oa.x,-.11),Vector2(ob.x,-.11),ob]
		for side: float in [-1.0,1.0]:
			var z: float=side*breadth*.43
			var tint:=Color("b1a083").darkened(float(stone%3)*.027)
			# Broad radial joints make the voussoirs readable at gameplay scale.
			_stroke(builder,data,ring,oa,ia,.067,z,turn,MORTAR)
			_stroke(builder,data,ring,ia,ib,.035,z,turn,MORTAR.lightened(.07))
			if stone%3!=1:
				var patch: Array[Vector2]=[oa.lerp(ia,.19).lerp(ob.lerp(ib,.19),.14),oa.lerp(ia,.22).lerp(ob.lerp(ib,.22),.74),oa.lerp(ia,.59).lerp(ob.lerp(ib,.59),.69),oa.lerp(ia,.66).lerp(ob.lerp(ib,.66),.18)]
				_patch(builder,data,ring,patch,z,turn,tint.lightened(.07 if stone%2==0 else -.07))
			_masonry(builder,data,fill,z,turn,stone)


static func abutments(builder, data: Dictionary, length: float, breadth: float, turn: Basis, water_depth: float = 2.65) -> void:
	for end: float in [-1.0,1.0]:
		var x: float=end*(length*.5-.55)
		var face: Array[Vector2]=[Vector2(x-.425,-water_depth-.04),Vector2(x+.425,-water_depth-.04),Vector2(x+.425,.04),Vector2(x-.425,.04)]
		for side: float in [-1.0,1.0]:
			_masonry(builder,data,face,side*breadth*.5,turn,17+int(end))
		# The outward end cap uses the same real box face in a turned frame.
		# Keeping it independent avoids projecting marks around the corner.
		var cap: Array[Vector2]=[Vector2(-breadth*.5,-water_depth-.04),Vector2(breadth*.5,-water_depth-.04),Vector2(breadth*.5,.04),Vector2(-breadth*.5,.04)]
		_masonry(builder,data,cap,end*(length*.5-.125),turn*Basis(Vector3.UP,PI*.5),23+int(end))


static func planks(builder, data: Dictionary, length: float, breadth: float, turn: Basis) -> void:
	# Existing board tops are exactly y=0. Detail remains within each board.
	var segments: Array[Vector2] = plank_segments(length)
	for index: int in segments.size():
		var segment: Vector2 = segments[index]
		var x: float = (segment.x + segment.y) * 0.5
		var half: float = (segment.y - segment.x) * 0.5
		for side: float in [-1.0,1.0]:
			var z: float=side*breadth*.40
			_nail(builder,data,turn*Vector3(x+side*minf(.17,half*.60),OFFSET,z),turn,minf(.031,half*.25))
		if index%3==1:continue
		var grain_x: float=x+(.08 if index%2==0 else -.09)
		var start: float=-breadth*(.28 if index%2==0 else .12)
		var finish: float=start+breadth*(.26 if index%2==0 else .37)
		var a := Vector2(grain_x, start)
		var b := Vector2(grain_x + .018, finish)
		var offset := Vector2(.018, 0)
		_top_patch(builder, data, [a-offset,b-offset*.50,b+offset*.50,a+offset], segment, breadth, turn, Color("75654b"))
		if index%4==0:
			var pale := Vector2(.085, 0)
			_top_patch(builder, data, [a+pale,b.lerp(a,.40)+pale,b.lerp(a,.40)+pale+offset*.70,a+pale+offset], segment, breadth, turn, Color("bba784"))


static func _nail(builder, data: Dictionary, centre: Vector3, turn: Basis, radius: float = .031) -> void:
	for side: int in range(6):
		var a: float=side*TAU/6.0
		var b: float=(side+1)*TAU/6.0
		builder._triangle(data,centre,centre+turn*Vector3(cos(a)*radius,0,sin(a)*radius),centre+turn*Vector3(cos(b)*radius,0,sin(b)*radius),Color("50493b"),turn*Vector3.UP)


static func _top_patch(builder, data: Dictionary, polygon: Array[Vector2], segment: Vector2, breadth: float, turn: Basis, color: Color) -> void:
	var boundary: Array[Vector2] = [Vector2(segment.x,-breadth*.5),Vector2(segment.y,-breadth*.5),Vector2(segment.y,breadth*.5),Vector2(segment.x,breadth*.5)]
	var clipped: Array[Vector2] = polygon
	for edge: int in boundary.size():
		clipped = _clip(clipped, boundary[edge], boundary[(edge + 1) % boundary.size()], 1.0)
		if clipped.size() < 3: return
	for index: int in range(1, clipped.size() - 1):
		builder._triangle(data, turn*Vector3(clipped[0].x,OFFSET,clipped[0].y), turn*Vector3(clipped[index].x,OFFSET,clipped[index].y), turn*Vector3(clipped[index+1].x,OFFSET,clipped[index+1].y), color, Vector3.UP)


static func _masonry(builder, data: Dictionary, boundary: Array[Vector2], z: float, turn: Basis, variant: int) -> void:
	var low:=Vector2(INF,INF)
	var high:=Vector2(-INF,-INF)
	for point: Vector2 in boundary:
		low=low.min(point)
		high=high.max(point)
	# Staggered horizontal courses continue across the arch's facet boundaries.
	# Only genuine block joints are stroked; clipping creates no false borders.
	var step_y: float=.48
	var step_x: float=.81
	for row: int in range(floori(low.y/step_y),ceili(high.y/step_y)+1):
		var y: float=float(row)*step_y
		var shift: float=.39 if posmod(row,2)==0 else .0
		_stroke(builder,data,boundary,Vector2(low.x-.1,y),Vector2(high.x+.1,y+.018),.050,z,turn,MORTAR)
		for column: int in range(floori((low.x-shift)/step_x),ceili((high.x-shift)/step_x)+1):
			var x: float=float(column)*step_x+shift
			_stroke(builder,data,boundary,Vector2(x,y+.012),Vector2(x+.024,y+step_y-.014),.047,z,turn,MORTAR)
			if posmod(row*3+column*5+variant,5)==0:
				var patch: Array[Vector2]=[Vector2(x+.08,y+.10),Vector2(x+.68,y+.09),Vector2(x+.64,y+.36),Vector2(x+.12,y+.39)]
				_patch(builder,data,boundary,patch,z,turn,Color("a99a82").darkened(.07 if posmod(row+column,2)==0 else -.07))


static func _stroke(builder, data: Dictionary, boundary: Array[Vector2], a: Vector2, b: Vector2, width: float, z: float, turn: Basis, color: Color) -> void:
	var direction: Vector2=(b-a).normalized()
	var edge:=Vector2(-direction.y,direction.x)*width*.5
	var polygon: Array[Vector2]=[a-edge,b-edge,b+edge,a+edge]
	_patch(builder,data,boundary,polygon,z,turn,color)


static func _patch(builder, data: Dictionary, boundary: Array[Vector2], polygon: Array[Vector2], z: float, turn: Basis, color: Color) -> void:
	var clipped: Array[Vector2]=polygon
	var area: float=0.0
	for edge: int in range(boundary.size()):
		area+=boundary[edge].cross(boundary[(edge+1)%boundary.size()])
	var sign_area: float=1.0 if area>=0.0 else -1.0
	for edge: int in range(boundary.size()):
		clipped=_clip(clipped,boundary[edge],boundary[(edge+1)%boundary.size()],sign_area)
		if clipped.size()<3:return
	var normal: Vector3=turn*Vector3(0,0,signf(z))
	for index: int in range(1,clipped.size()-1):
		var a: Vector2=clipped[0]
		var b: Vector2=clipped[index]
		var c: Vector2=clipped[index+1]
		builder._triangle(data,turn*Vector3(a.x,a.y,z)+normal*OFFSET,turn*Vector3(b.x,b.y,z)+normal*OFFSET,turn*Vector3(c.x,c.y,z)+normal*OFFSET,color,normal)


static func _clip(polygon: Array[Vector2], a: Vector2, b: Vector2, sign_area: float) -> Array[Vector2]:
	var result: Array[Vector2]=[]
	if polygon.is_empty():return result
	var edge: Vector2=b-a
	var previous: Vector2=polygon.back()
	var previous_distance: float=edge.cross(previous-a)*sign_area
	for point: Vector2 in polygon:
		var distance: float=edge.cross(point-a)*sign_area
		if (distance>=0.0)!=(previous_distance>=0.0):
			result.append(previous.lerp(point,previous_distance/(previous_distance-distance)))
		if distance>=0.0:result.append(point)
		previous=point
		previous_distance=distance
	return result
