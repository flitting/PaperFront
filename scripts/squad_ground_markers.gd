extends RefCounted

## Ground-only squad bases: four independent L corners, no connecting edges.
const Map = preload("res://scripts/map_data.gd")
const Palette = preload("res://scripts/volume_models.gd")
const FOOT_MARGIN := .16
const INK_WIDTH := .085
const COLOR_WIDTH := .045
const MAX_ARM := .48
const LIFT := .045

static func collect(sim, selection: Array) -> Array[Dictionary]:
	var groups: Dictionary = {}
	for raw: Variant in selection:
		var id := int(raw)
		var e: Dictionary = sim.entities.get(id, {})
		if e.is_empty() or int(e.get("squad_capacity", 1)) <= 1 or float(e.get("hp",0)) <= 0: continue
		if int(e.get("transport_id",-1)) >= 0 or int(e.get("garrison_id",-1)) >= 0 or bool(e.get("emerging",false)): continue
		if not sim.entity_visible_to(0,id): continue
		var group := int(e.get("squad_id", id))
		if not groups.has(group): groups[group] = {"positions":PackedVector2Array(),"radius":.0,"capacity":int(e.squad_capacity),"team":int(e.team),"sniper":sim.data_for(e.spec).get("squad_role", "") == "sniper"}
		var entry: Dictionary = groups[group]
		entry.positions.append(e.pos)
		entry.radius = maxf(float(entry.radius),float(sim.data_for(e.spec).get("radius",.5)))
	var result: Array[Dictionary] = []
	for group: int in groups:
		var item: Dictionary = groups[group]
		var frame := footprint(item.positions,float(item.radius)+FOOT_MARGIN)
		var segments := corners(frame)
		var points := PackedVector3Array()
		for corner: Vector2 in frame.corners:
			points.append(Vector3(corner.x,Map.height_at(sim.map,corner)+LIFT,corner.y))
		result.append({"id":group,"count":item.positions.size(),"capacity":item.capacity,"team":item.team,"color":Palette.player_color(item.team),"sniper":item.sniper,"frame":frame,"segments":segments,"points":points})
	return result

static func footprint(positions: PackedVector2Array, margin: float) -> Dictionary:
	var right := Vector2.RIGHT
	var forward := Vector2.DOWN
	var best := INF
	var bounds := Rect2()
	var hull: PackedVector2Array = Geometry2D.convex_hull(positions)
	# Choose the smallest rectangle around actual feet, including rotated rows.
	var directions: Array[Vector2] = [Vector2.RIGHT]
	for i in range(maxi(0,hull.size()-1)):
		var edge := hull[i+1]-hull[i]
		if edge.length_squared()>.001: directions.append(edge.normalized())
	for axis: Vector2 in directions:
		var across := axis.orthogonal()
		var low := Vector2(INF,INF)
		var high := Vector2(-INF,-INF)
		for pos: Vector2 in positions:
			var local := Vector2(pos.dot(axis),pos.dot(across))
			low = low.min(local); high = high.max(local)
		var candidate := Rect2(low,high-low).grow(margin)
		var area := candidate.size.x*candidate.size.y
		if area < best-.0001:
			best=area; bounds=candidate; right=axis; forward=across
	var corners := PackedVector2Array()
	for local: Vector2 in [bounds.position,Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)]:
		corners.append(right*local.x+forward*local.y)
	return {"bounds":bounds,"right":right,"forward":forward,"corners":corners}

static func corners(frame: Dictionary) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var points: PackedVector2Array = frame.corners
	for i in range(4):
		var corner: Vector2 = points[i]
		for adjacent: int in [(i+1)%4,(i+3)%4]:
			var edge := points[adjacent]-corner
			var length := minf(MAX_ARM,edge.length()*.28)
			result.append(PackedVector2Array([corner,corner+edge.normalized()*length]))
	return result

static func mesh(markers: Array[Dictionary], map: Dictionary) -> ArrayMesh:
	var output := ArrayMesh.new()
	for stroke in [0,1]:
		var vertices := PackedVector3Array()
		var colors := PackedColorArray()
		var normals := PackedVector3Array()
		for marker: Dictionary in markers:
			var color: Color = Color("352d24") if stroke==0 else marker.color
			var width: float = INK_WIDTH if stroke==0 else COLOR_WIDTH
			var lift: float = LIFT-.012 if stroke==0 else LIFT
			for segment: PackedVector2Array in marker.segments:
				_ribbon(vertices,colors,normals,segment,width,lift,color,map)
		if vertices.is_empty(): continue
		var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals; arrays[Mesh.ARRAY_COLOR]=colors
		output.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var material := StandardMaterial3D.new()
		material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo=true
		material.vertex_color_is_srgb=true
		material.cull_mode=BaseMaterial3D.CULL_DISABLED
		output.surface_set_material(output.get_surface_count()-1,material)
	return output

static func _ribbon(vertices: PackedVector3Array, colors: PackedColorArray, normals: PackedVector3Array, segment: PackedVector2Array, width: float, lift: float, color: Color, map: Dictionary) -> void:
	var direction := segment[1]-segment[0]
	var normal := direction.normalized().orthogonal()*width*.5
	var steps := maxi(1,ceili(direction.length()/.10))
	for i in range(steps):
		var a := segment[0]+direction*(float(i)/steps)
		var b := segment[0]+direction*(float(i+1)/steps)
		var q: Array[Vector2] = [a-normal,b-normal,b+normal,a+normal]
		var heights: Array[float] = []
		for point in q: heights.append(Map.height_at(map,point))
		# Never bridge a cliff with a vertical floating curtain.
		if heights.max()-heights.min()>.76: continue
		for index: int in [0,1,2,0,2,3]:
			var p: Vector2=q[index]
			vertices.append(Vector3(p.x,heights[index]+lift,p.y))
			colors.append(color); normals.append(Vector3.UP)
