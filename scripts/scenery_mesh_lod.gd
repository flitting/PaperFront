extends RefCounted
class_name SceneryMeshLOD

## Only offline-baked indices are used in exported games. Each tier retains
## the source vertices, paint, UVs and materials; an edited mesh stays full.
const RESOURCE_PATH: String = "res://assets/models/scenery_lod_indices.res"
const MESH_LOD = preload("res://scripts/offline_mesh_lod.gd")
static var _resource: Resource
static var _loaded: bool = false
static var _cache: Dictionary = {}
static var _covered: Dictionary = {}

static func variants(source: Mesh) -> Array[Mesh]:
	if source == null: return []
	var id: int = source.get_instance_id()
	if _cache.has(id): return _cache[id]
	var result: Array[Mesh] = [source, source, source]
	_covered[id] = false
	if not _loaded:
		_loaded = true
		if ResourceLoader.exists(RESOURCE_PATH): _resource = load(RESOURCE_PATH)
	if _resource != null and int(_resource.get_meta("scenery_lod_schema", 0)) == 2:
		var records: Dictionary = _resource.get_meta("mesh_tiers", {})
		var record: Dictionary = records.get(MESH_LOD.signature(source), {})
		if not record.is_empty():
			_covered[id] = true
			result[1] = build_mesh(source, record.get("far", []), record.get("far_arrays", []))
			result[2] = build_mesh(source, record.get("extreme", []), record.get("extreme_arrays", []))
	_cache[id] = result
	return result

static func has_bake(source: Mesh) -> bool:
	variants(source)
	return bool(_covered.get(source.get_instance_id(), false))

static func build_mesh(source: Mesh, indices: Array, repaired: Array = []) -> Mesh:
	if repaired.is_empty(): return MESH_LOD.build_mesh(source, indices)
	if repaired.size() != source.get_surface_count(): return source
	for arrays: Array in repaired:
		if arrays.size() != Mesh.ARRAY_MAX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array: return source
		var count: int = arrays[Mesh.ARRAY_VERTEX].size()
		if not arrays[Mesh.ARRAY_INDEX] is PackedInt32Array or not MESH_LOD._valid_indices(arrays[Mesh.ARRAY_INDEX], count): return source
		for attribute: int in [Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV]:
			if arrays[attribute] != null and arrays[attribute].size() != count: return source
		if arrays[Mesh.ARRAY_TANGENT] != null and arrays[Mesh.ARRAY_TANGENT].size() != count * 4: return source
	var mesh := ArrayMesh.new()
	for surface: int in repaired.size():
		mesh.add_surface_from_arrays(source.surface_get_primitive_type(surface), repaired[surface])
		mesh.surface_set_material(surface, source.surface_get_material(surface))
	mesh.custom_aabb = source.get_aabb()
	mesh.set_meta("scenery_coherent_normals", true)
	return mesh

## A coarse pine face can span corners whose former smooth normals point
## through the new face. Preserve their positions/UV/paint, duplicate only
## those corners, and give the coarse triangle a coherent outward normal.
## This runs in the bake tool; exported games load its already repaired arrays.
static func coherent_surface(original: Array, source_indices: PackedInt32Array) -> Array:
	var arrays: Array = original.duplicate(true)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	var indices := PackedInt32Array()
	for offset: int in range(0, source_indices.size(), 3):
		var a: int = source_indices[offset]
		var b: int = source_indices[offset + 1]
		var c: int = source_indices[offset + 2]
		var cross: Vector3 = (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
		if cross.dot(normals[a] + normals[b] + normals[c]) > 0.000001:
			var previous: int = b
			b = c
			c = previous
			cross = -cross
		if cross.length_squared() > 0.0000000001 and (cross.dot(normals[a]) >= 0.0 or cross.dot(normals[b]) >= 0.0 or cross.dot(normals[c]) >= 0.0):
			var outward: Vector3 = -cross.normalized()
			for index: int in [a, b, c]:
				indices.append(vertices.size())
				vertices.append(vertices[index])
				normals.append(outward)
				colors.append(colors[index])
				uvs.append(uvs[index])
				if not tangents.is_empty():
					for component: int in 4: tangents.append(tangents[index * 4 + component])
		else: indices.append_array(PackedInt32Array([a, b, c]))
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	if not tangents.is_empty(): arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays
