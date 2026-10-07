extends RefCounted

## Meshoptimizer runs only in authoring tools. Runtime callers build the baked
## index buffers against intact source attributes, materials and skin weights.
const TARGETS := {"far": 0.55, "extreme": 0.22}
const TIERS := ["far", "extreme"]

static func signature(source: Mesh, owner: Color = Color.TRANSPARENT) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(source.get_class()))
	for surface in range(source.get_surface_count()):
		context.update(var_to_bytes([source.surface_get_primitive_type(surface), source.surface_get_format(surface)]))
		var arrays: Array = source.surface_get_arrays(surface)
		for attribute in range(Mesh.ARRAY_MAX):
			var value: Variant = arrays[attribute]
			if attribute == Mesh.ARRAY_COLOR and value != null and owner.a > 0.0:
				var colors: PackedColorArray = (value as PackedColorArray).duplicate()
				for index in range(colors.size()):
					if colors[index].is_equal_approx(owner): colors[index] = Color(1, 0, 1, 1)
				value = colors
			context.update(var_to_bytes(value))
		context.update(var_to_bytes(source.surface_get_blend_shape_arrays(surface)))
		context.update(var_to_bytes(_resource_signature(source.surface_get_material(surface))))
	return context.finish().hex_encode()

static func _resource_signature(resource: Resource) -> Variant:
	if resource == null: return null
	if resource is Shader: return [resource.get_class(), resource.code]
	if resource is Texture:
		var path: String = resource.resource_path
		return [resource.get_class(), path, FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""]
	var properties: Array = [resource.get_class()]
	for property in resource.get_property_list():
		if not int(property.usage) & PROPERTY_USAGE_STORAGE or str(property.name) in ["resource_name", "resource_local_to_scene", "script"]: continue
		var value: Variant = resource.get(property.name)
		if value is Resource: value = _resource_signature(value)
		elif typeof(value) == TYPE_OBJECT: continue
		properties.append([str(property.name), value])
	return properties

static func source_indices(source: Mesh, surface: int) -> PackedInt32Array:
	var arrays: Array = source.surface_get_arrays(surface)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if not indices.is_empty(): return indices
	indices.resize(source.surface_get_array_len(surface))
	for index in range(indices.size()): indices[index] = index
	return indices

static func bake(source: Mesh, owner: Color = Color.TRANSPARENT, paper: Color = Color.TRANSPARENT, options: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {"far": [], "extreme": [], "counts": {"full": 0, "far": 0, "extreme": 0}}
	if not source is ArrayMesh: return result
	var importers: Array[ImporterMesh] = []
	# Keep authored hard face boundaries. Wider normal merges can collapse
	# opposite room/wing faces into lines while preserving only their bounds.
	for merge_angle in options.get("merge_angles", [30.0]):
		var importer := ImporterMesh.new()
		for shape in range(source.get_blend_shape_count()): importer.add_blend_shape(source.get_blend_shape_name(shape))
		for surface in range(source.get_surface_count()):
			var arrays: Array = source.surface_get_arrays(surface)
			arrays[Mesh.ARRAY_INDEX] = source_indices(source, surface)
			importer.add_surface(source.surface_get_primitive_type(surface), arrays, source.surface_get_blend_shape_arrays(surface), {}, source.surface_get_material(surface), "", source.surface_get_format(surface))
		importer.generate_lods(merge_angle, 25.0, [])
		importers.append(importer)
	for surface in range(source.get_surface_count()):
		var arrays: Array = source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var full: PackedInt32Array = source_indices(source, surface)
		var protected: PackedInt32Array = _protected_triangles(arrays, full, owner, paper)
		var opaque: Dictionary = opaque_planes(arrays, full, options.get("decorative_color", Color.TRANSPARENT)) if bool(options.get("preserve_opaque_planes", false)) else {"planes": {}, "indices": PackedInt32Array()}
		var candidates: Array[PackedInt32Array] = [full]
		for importer in importers:
			for level in range(importer.get_surface_lod_count(surface)):
				var candidate: PackedInt32Array = importer.get_surface_lod_indices(surface, level)
				if bool(options.get("orient_to_source_normals", false)): candidate = _orient_indices(arrays, candidate)
				candidate = restore_opaque_planes(arrays, candidate, opaque)
				candidate = _with_protected(candidate, protected)
				if candidate.size() < full.size() and _valid_indices(candidate, vertices.size()) and _silhouette_safe(vertices, full, candidate) and (not bool(options.get("reject_reversed_faces", false)) or reversed_faces(arrays, candidate) == 0): candidates.append(candidate)
		candidates.sort_custom(func(first: PackedInt32Array, second: PackedInt32Array): return first.size() > second.size())
		var far: PackedInt32Array = _choose(candidates, float(full.size()) * TARGETS.far)
		var extreme: PackedInt32Array = _choose(candidates, float(full.size()) * TARGETS.extreme)
		# Preserve a genuine intermediate tier whenever native simplification
		# offers more than one safe topology, rather than duplicating extreme.
		if far == extreme and candidates.size() > 2:
			for candidate in candidates:
				if candidate.size() < full.size() and candidate.size() > extreme.size(): far = candidate; break
		if far == extreme and far.size() < full.size() and bool(options.get("distinct_component_intermediate", false)):
			var intermediate: PackedInt32Array = component_intermediate(arrays, full, extreme, float(full.size()) * TARGETS.far)
			if intermediate.size() > extreme.size() and intermediate.size() < full.size() and reversed_faces(arrays, intermediate) == 0: far = intermediate
		result.far.append(far)
		result.extreme.append(extreme)
		result.counts.full += full.size() / 3
		result.counts.far += far.size() / 3
		result.counts.extreme += extreme.size() / 3
	return result

static func _component_root(parents: Dictionary, index: int) -> int:
	var current: int = index
	while int(parents[current]) != current: current = int(parents[current])
	var root: int = current
	current = index
	while int(parents[current]) != current:
		var following: int = int(parents[current])
		parents[current] = root
		current = following
	return root

## If native simplification offers one safe distant topology, enrich only the
## intermediate tier with complete original detail islands. Replace every
## coarse face from an island before restoring it, avoiding coplanar overlap.
static func component_intermediate(arrays: Array, full: PackedInt32Array, coarse: PackedInt32Array, target: float) -> PackedInt32Array:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var parents: Dictionary = {}
	var positions: Dictionary = {}
	for index in range(vertices.size()):
		parents[index] = index
		var point: Vector3 = vertices[index]
		var key := Vector3i(roundi(point.x * 100000.0), roundi(point.y * 100000.0), roundi(point.z * 100000.0))
		if positions.has(key): parents[index] = int(positions[key])
		else: positions[key] = index
	for offset in range(0, full.size(), 3):
		var first: int = _component_root(parents, full[offset])
		for corner in [1, 2]:
			var other: int = _component_root(parents, full[offset + corner])
			if other != first: parents[other] = first
	var components: Dictionary = {}
	for offset in range(0, full.size(), 3):
		var id: int = _component_root(parents, full[offset])
		if not components.has(id): components[id] = {"indices": PackedInt32Array(), "coarse": 0, "bounds": AABB(vertices[full[offset]], Vector3.ZERO), "blocked": false}
		for corner in range(3):
			components[id].indices.append(full[offset + corner])
			components[id].bounds = components[id].bounds.expand(vertices[full[offset + corner]])
	for offset in range(0, coarse.size(), 3):
		var first: int = _component_root(parents, coarse[offset])
		var second: int = _component_root(parents, coarse[offset + 1])
		var third: int = _component_root(parents, coarse[offset + 2])
		if first == second and first == third: components[first].coarse += 3
		else:
			for id in [first, second, third]:
				if components.has(id): components[id].blocked = true
	var ordered: Array = components.keys()
	ordered.sort_custom(func(first: int, second: int): return (components[first].bounds as AABB).size.length_squared() > (components[second].bounds as AABB).size.length_squared())
	var selected: Dictionary = {}
	var size: int = coarse.size()
	for id in ordered:
		var component: Dictionary = components[id]
		var increase: int = component.indices.size() - int(component.coarse)
		if component.blocked or increase <= 0 or size + increase >= full.size(): continue
		if not selected.is_empty() and float(size + increase) > target: continue
		if float(size + increase) > target * 1.25: continue
		selected[id] = true
		size += increase
	if selected.is_empty(): return coarse
	var result := PackedInt32Array()
	for offset in range(0, coarse.size(), 3):
		if selected.has(_component_root(parents, coarse[offset])): continue
		for corner in range(3): result.append(coarse[offset + corner])
	for id in selected: result.append_array(components[id].indices)
	return result

static func _orient_indices(arrays: Array, indices: PackedInt32Array) -> PackedInt32Array:
	if arrays[Mesh.ARRAY_NORMAL] == null: return indices
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var result: PackedInt32Array = indices.duplicate()
	for offset in range(0, result.size(), 3):
		var a: int = result[offset]
		var b: int = result[offset + 1]
		var c: int = result[offset + 2]
		var cross: Vector3 = (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
		# Godot's visible front face is clockwise. Native coarse triangles can
		# bridge several smooth faces; keep their original outward shading side.
		if cross.dot(normals[a] + normals[b] + normals[c]) > 0.000001:
			result[offset + 1] = c
			result[offset + 2] = b
	return result

static func _choose(candidates: Array[PackedInt32Array], target: float) -> PackedInt32Array:
	var chosen: PackedInt32Array = candidates[0]
	var difference: float = INF
	for candidate in candidates:
		if candidates.size() > 1 and candidate.size() == candidates[0].size(): continue
		var distance: float = absf(float(candidate.size()) - target)
		if distance < difference: chosen = candidate; difference = distance
	return chosen

static func _plane_key(vertices: PackedVector3Array, a: int, b: int, c: int) -> String:
	var cross: Vector3 = (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
	if cross.length_squared() < 0.0000000001: return ""
	var normal: Vector3 = -cross.normalized()
	return "%d:%d:%d:%d" % [roundi(normal.x * 10000.0), roundi(normal.y * 10000.0), roundi(normal.z * 10000.0), roundi(normal.dot(vertices[a]) * 10000.0)]

## Preserve complete major opaque patches, not just supporting corner vertices.
## Roofs, walls, decks and wing plates must retain actual filled surfaces after
## simplification; a matching AABB alone also permits a wireframe silhouette.
static func opaque_planes(arrays: Array, full: PackedInt32Array, decorative_color: Color = Color.TRANSPARENT) -> Dictionary:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var largest: float = 0.0
	for offset in range(0, full.size(), 3): largest = maxf(largest, (vertices[full[offset + 1]] - vertices[full[offset]]).cross(vertices[full[offset + 2]] - vertices[full[offset]]).length() * 0.5)
	var groups: Dictionary = {}
	for offset in range(0, full.size(), 3):
		var a: int = full[offset]
		var b: int = full[offset + 1]
		var c: int = full[offset + 2]
		var area: float = (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]).length() * 0.5
		if area < 0.0000001: continue
		if decorative_color.a > 0.0 and not colors.is_empty() and area < largest * 0.035 and colors[a].is_equal_approx(decorative_color) and colors[b].is_equal_approx(decorative_color) and colors[c].is_equal_approx(decorative_color): continue
		var key: String = _plane_key(vertices, a, b, c)
		if not groups.has(key): groups[key] = {"area": 0.0, "largest": 0.0, "indices": PackedInt32Array()}
		groups[key].area += area
		groups[key].largest = maxf(groups[key].largest, area)
		groups[key].indices.append_array(PackedInt32Array([a, b, c]))
	var result: Dictionary = {"planes": {}, "indices": PackedInt32Array()}
	for key in groups:
		if groups[key].area >= largest * 0.10 and groups[key].largest >= largest * 0.025:
			result.planes[key] = true
			result.indices.append_array(groups[key].indices)
	return result

static func restore_opaque_planes(arrays: Array, candidate: PackedInt32Array, opaque: Dictionary) -> PackedInt32Array:
	if opaque.planes.is_empty(): return candidate
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var result := PackedInt32Array()
	for offset in range(0, candidate.size(), 3):
		if opaque.planes.has(_plane_key(vertices, candidate[offset], candidate[offset + 1], candidate[offset + 2])): continue
		for corner in range(3): result.append(candidate[offset + corner])
	return _with_protected(result, opaque.indices)

static func reversed_faces(arrays: Array, indices: PackedInt32Array) -> int:
	if arrays[Mesh.ARRAY_NORMAL] == null: return 0
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var reversed: int = 0
	for offset in range(0, indices.size(), 3):
		var a: int = indices[offset]
		var b: int = indices[offset + 1]
		var c: int = indices[offset + 2]
		if (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]).dot(normals[a] + normals[b] + normals[c]) > 0.000001: reversed += 1
	return reversed

static func _protected_triangles(arrays: Array, full: PackedInt32Array, owner: Color, paper: Color) -> PackedInt32Array:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var anchors: Dictionary = {}
	# Supporting vertices in 26 directions retain the original silhouette
	# envelope, including turret barrels, aircraft wings and roof peaks.
	for direction in _directions():
		var support: float = -INF
		var anchor: int = -1
		for index in full:
			var projection: float = vertices[index].dot(direction)
			if projection > support: support = projection; anchor = index
		if anchor >= 0: anchors[anchor] = true
	var protected := PackedInt32Array()
	for offset in range(0, full.size(), 3):
		var keep: bool = false
		for corner in range(3):
			var index: int = full[offset + corner]
			if anchors.has(index): keep = true
			if not colors.is_empty() and ((owner.a > 0.0 and colors[index].is_equal_approx(owner)) or (paper.a > 0.0 and colors[index].is_equal_approx(paper))): keep = true
		if keep:
			for corner in range(3): protected.append(full[offset + corner])
	return protected

static func _with_protected(indices: PackedInt32Array, protected: PackedInt32Array) -> PackedInt32Array:
	var result: PackedInt32Array = indices.duplicate()
	var triangles: Dictionary = {}
	for offset in range(0, indices.size(), 3): triangles[_triangle_key(indices, offset)] = true
	for offset in range(0, protected.size(), 3):
		var key: String = _triangle_key(protected, offset)
		if triangles.has(key): continue
		triangles[key] = true
		for corner in range(3): result.append(protected[offset + corner])
	return result

static func _triangle_key(indices: PackedInt32Array, offset: int) -> String:
	var first: int = indices[offset]
	var second: int = indices[offset + 1]
	var third: int = indices[offset + 2]
	if second < first and second < third: return "%d:%d:%d" % [second, third, first]
	if third < first and third < second: return "%d:%d:%d" % [third, first, second]
	return "%d:%d:%d" % [first, second, third]

static func _directions() -> Array[Vector3]:
	var directions: Array[Vector3] = []
	for x in range(-1, 2):
		for y in range(-1, 2):
			for z in range(-1, 2):
				if x != 0 or y != 0 or z != 0: directions.append(Vector3(x, y, z).normalized())
	return directions

static func _silhouette_safe(vertices: PackedVector3Array, full: PackedInt32Array, candidate: PackedInt32Array) -> bool:
	for direction in _directions():
		var original_support: float = -INF
		var reduced_support: float = -INF
		for index in full: original_support = maxf(original_support, vertices[index].dot(direction))
		for index in candidate: reduced_support = maxf(reduced_support, vertices[index].dot(direction))
		if absf(original_support - reduced_support) > 0.0001: return false
	return true

static func _valid_indices(indices: PackedInt32Array, vertex_count: int) -> bool:
	if indices.is_empty() or indices.size() % 3 != 0: return false
	for index in indices:
		if index < 0 or index >= vertex_count: return false
	return true

static func build_mesh(source: Mesh, surfaces: Array) -> Mesh:
	if not source is ArrayMesh or surfaces.size() != source.get_surface_count(): return source
	var reduced: bool = false
	for surface in range(source.get_surface_count()):
		if not surfaces[surface] is PackedInt32Array or not _valid_indices(surfaces[surface], source.surface_get_array_len(surface)): return source
		if surfaces[surface].size() > source_indices(source, surface).size(): return source
		reduced = reduced or surfaces[surface].size() < source_indices(source, surface).size()
	if not reduced: return source
	var mesh := ArrayMesh.new()
	for shape in range(source.get_blend_shape_count()): mesh.add_blend_shape(source.get_blend_shape_name(shape))
	mesh.blend_shape_mode = source.blend_shape_mode
	for surface in range(source.get_surface_count()):
		var arrays: Array = source.surface_get_arrays(surface)
		arrays[Mesh.ARRAY_INDEX] = surfaces[surface]
		mesh.add_surface_from_arrays(source.surface_get_primitive_type(surface), arrays, source.surface_get_blend_shape_arrays(surface), {}, source.surface_get_format(surface))
		mesh.surface_set_material(surface, source.surface_get_material(surface))
	mesh.custom_aabb = source.get_aabb()
	return mesh
