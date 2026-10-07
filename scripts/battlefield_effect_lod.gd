extends RefCounted

## Cheap, opaque pieces preserve the original shard bounds and averaged paint.
## Mesh/RID construction happens on the main thread after CPU clipping completes.
static func fragment_tiers(source: Mesh) -> Array:
	var paint := Color(0,0,0,1)
	var samples: int = 0
	for surface: int in source.get_surface_count():
		var arrays: Array = source.surface_get_arrays(surface)
		if not arrays[Mesh.ARRAY_COLOR] is PackedColorArray: continue
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var count: int = mini(96,colors.size())
		for index: int in count:
			var color: Color = colors[index*colors.size()/count]
			paint.r+=color.r;paint.g+=color.g;paint.b+=color.b
			samples+=1
	paint = Color(paint.r/samples,paint.g/samples,paint.b/samples,1) if samples>0 else Color.WHITE
	var material: Material = source.surface_get_material(0) if source.get_surface_count()>0 else null
	var bounds: AABB = source.get_aabb()
	var far: Mesh = solid(bounds,paint,1,material)
	var extreme: Mesh = solid(bounds,paint,2,material)
	# An already tiny paper sliver is cheaper than a box. Never inflate its draw.
	if triangles(source)<triangles(far): far=source
	if triangles(far)<triangles(extreme): extreme=far
	return [source,far,extreme]

static func triangles(mesh: Mesh) -> int:
	var count: int = 0
	for surface: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
		count+=(indices.size() if not indices.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())/3
	return count

static func solid(bounds: AABB, paint: Color, tier: int, material: Material = null) -> ArrayMesh:
	var center: Vector3 = bounds.get_center()
	var half: Vector3 = bounds.size.max(Vector3(.015,.015,.015))*.5
	var corners: Array[Vector3] = []
	var faces: Array[int]
	if tier==2:
		corners=[Vector3(1,1,1),Vector3(1,-1,-1),Vector3(-1,1,-1),Vector3(-1,-1,1)]
		faces=[0,2,1,0,1,3,0,3,2,1,2,3]
	else:
		corners=[Vector3(-1,-1,-1),Vector3(1,-1,-1),Vector3(1,1,-1),Vector3(-1,1,-1),Vector3(-1,-1,1),Vector3(1,-1,1),Vector3(1,1,1),Vector3(-1,1,1)]
		faces=[0,2,1,0,3,2,4,5,6,4,6,7,0,1,5,0,5,4,3,7,6,3,6,2,0,4,7,0,7,3,1,2,6,1,6,5]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for triangle: int in range(0,faces.size(),3):
		var a: Vector3 = corners[faces[triangle]]*half+center
		var b: Vector3 = corners[faces[triangle+1]]*half+center
		var c: Vector3 = corners[faces[triangle+2]]*half+center
		var normal: Vector3 = (b-a).cross(c-a).normalized()
		if normal.dot((a+b+c)/3.0-center)<0.0: normal=-normal
		# Match the game's CraftMesh convention: clockwise front faces and
		# outward lighting normals. Neither cheap tier can expose its inside.
		var face: Array=[a,c,b] if (b-a).cross(c-a).dot(normal)>0.0 else [a,b,c]
		for point: Vector3 in face:
			vertices.append(point);normals.append(normal);colors.append(paint)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_COLOR]=colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	if material!=null: mesh.surface_set_material(0,material)
	return mesh

static func octahedron() -> ArrayMesh:
	var points: Array[Vector3] = [Vector3(.5,0,0),Vector3(-.5,0,0),Vector3(0,.5,0),Vector3(0,-.5,0),Vector3(0,0,.5),Vector3(0,0,-.5)]
	var faces: Array[int] = [2,0,4,2,4,1,2,1,5,2,5,0,3,4,0,3,1,4,3,5,1,3,0,5]
	var vertices := PackedVector3Array();var normals := PackedVector3Array();var colors := PackedColorArray()
	for index: int in faces:
		vertices.append(points[index]);normals.append(points[index].normalized());colors.append(Color.WHITE)
	var arrays: Array = [];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_COLOR]=colors
	var mesh := ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh
