extends SceneTree

## Derive separate distant casters from the already verified visual pine LODs.
## This never rewrites pine_*.res or their base-geometry equivalence evidence.
const OUTPUT_DIR: String = "res://assets/models"
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var report: Dictionary = {"format": 1, "purpose": "distant shadow-only pine casters", "variants": []}
	for variant in range(3):
		var source_path: String = OUTPUT_DIR + "/pine_%d.res" % variant
		var source: ArrayMesh = ResourceLoader.load(source_path, "ArrayMesh", ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh
		if source == null:
			failures.append("Missing verified pine: " + source_path)
			continue
		var importer: ImporterMesh = ImporterMesh.from_mesh(source)
		var count: int = importer.get_surface_lod_count(0)
		if count == 0:
			failures.append("Pine has no verified distance LOD: " + source_path)
			continue
		var indices: PackedInt32Array = importer.get_surface_lod_indices(0, count - 1)
		var original: Array = source.surface_get_arrays(0)
		var repair: Dictionary = _coherent_lod_arrays(original, indices)
		var arrays: Array = repair.arrays
		var caster := ArrayMesh.new()
		caster.resource_name = "DistantPineShadow_%d" % variant
		caster.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		caster.set_meta("pine_shadow_source_sha256", FileAccess.get_sha256(source_path))
		caster.set_meta("pine_shadow_selected_lod", count)
		caster.set_meta("pine_shadow_triangles", indices.size() / 3)
		var output: String = OUTPUT_DIR + "/pine_shadow_%d.res" % variant
		var error: Error = ResourceSaver.save(caster, output, ResourceSaver.FLAG_COMPRESS)
		if error != OK:
			failures.append("Cannot save caster: " + output)
			continue
		var saved: ArrayMesh = ResourceLoader.load(output, "ArrayMesh", ResourceLoader.CACHE_MODE_IGNORE) as ArrayMesh
		var saved_arrays: Array = saved.surface_get_arrays(0)
		var same: bool = _same_triangle_positions(original, indices, saved_arrays) and saved.get_aabb() == source.get_aabb() and _valid_face_normals(saved_arrays)
		if not same: failures.append("Distant caster changed selected pine geometry/bounds: " + output)
		report.variants.append({"variant": variant, "source": source_path, "source_sha256": FileAccess.get_sha256(source_path), "caster": output, "triangles": indices.size() / 3, "selected_lod": count, "triangle_positions_and_bounds_unchanged": same, "winding_repairs": repair.winding_repairs, "normal_repairs": repair.normal_repairs})
	report.failures = failures
	var file: FileAccess = FileAccess.open(OUTPUT_DIR + "/pine_shadow_meshes.json", FileAccess.WRITE)
	if file == null: failures.append("Cannot write distant pine report")
	else: file.store_string(JSON.stringify(report, "\t") + "\n")
	print("PINE_SHADOW_BAKE ", JSON.stringify(report))
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _coherent_lod_arrays(original: Array, source_indices: PackedInt32Array) -> Dictionary:
	var arrays: Array = original.duplicate()
	var vertices: PackedVector3Array = original[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = original[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = original[Mesh.ARRAY_COLOR]
	var uvs: PackedVector2Array = original[Mesh.ARRAY_TEX_UV]
	var tangents: PackedFloat32Array = original[Mesh.ARRAY_TANGENT] if original[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	var indices := PackedInt32Array()
	var winding_repairs: int = 0
	var normal_repairs: int = 0
	for offset in range(0, source_indices.size(), 3):
		var a: int = source_indices[offset]
		var b: int = source_indices[offset + 1]
		var c: int = source_indices[offset + 2]
		var cross: Vector3 = (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
		# Simplification can span several original smooth faces. Their original
		# corner normals still identify the outward side, but not necessarily the
		# new face winding. Reorient the same three positions, never move them.
		if cross.dot(normals[a] + normals[b] + normals[c]) >= 0.0:
			var temporary: int = b
			b = c
			c = temporary
			cross = -cross
			winding_repairs += 1
		if cross.dot(normals[a]) >= 0.0 or cross.dot(normals[b]) >= 0.0 or cross.dot(normals[c]) >= 0.0:
			var outward: Vector3 = -cross.normalized()
			for id in [a, b, c]:
				indices.append(vertices.size())
				vertices.append(vertices[id])
				normals.append(outward)
				colors.append(colors[id])
				uvs.append(uvs[id])
				if not tangents.is_empty():
					for component in range(4): tangents.append(tangents[int(id) * 4 + component])
			normal_repairs += 1
		else:
			indices.append_array(PackedInt32Array([a, b, c]))
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	if not tangents.is_empty(): arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_INDEX] = indices
	return {"arrays": arrays, "winding_repairs": winding_repairs, "normal_repairs": normal_repairs}


func _same_triangle_positions(original: Array, indices: PackedInt32Array, saved: Array) -> bool:
	var saved_indices: PackedInt32Array = saved[Mesh.ARRAY_INDEX]
	if saved_indices.size() != indices.size(): return false
	for offset in range(0, indices.size(), 3):
		var positions: Dictionary = {}
		for corner in range(3):
			var point: Vector3 = original[Mesh.ARRAY_VERTEX][indices[offset + corner]]
			positions[point] = int(positions.get(point, 0)) + 1
		for corner in range(3):
			var point: Vector3 = saved[Mesh.ARRAY_VERTEX][saved_indices[offset + corner]]
			if int(positions.get(point, 0)) == 0: return false
			positions[point] -= 1
	return true


func _valid_face_normals(arrays: Array) -> bool:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for offset in range(0, indices.size(), 3):
		var a: int = indices[offset]
		var b: int = indices[offset + 1]
		var c: int = indices[offset + 2]
		if (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]).dot(normals[a]) >= 0.0: return false
	return true
