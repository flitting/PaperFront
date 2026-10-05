extends SceneTree

var failures: Array[String] = []
var checks: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _initialize() -> void:
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/pine_meshes.json"))
	check(base.failures.is_empty() and base.variants.all(func(item): return item.base_geometry_unchanged), "original full pine geometry remains independently verified")
	for variant in range(3):
		var source_path: String = "res://assets/models/pine_%d.res" % variant
		var source: ArrayMesh = load(source_path)
		var mesh: ArrayMesh = load("res://assets/models/pine_shadow_%d.res" % variant)
		check(mesh.get_meta("pine_shadow_source_sha256") == FileAccess.get_sha256(source_path) and mesh.get_aabb() == source.get_aabb(), "distant pine resources retain their verified source and exact bounds")
		var arrays: Array = mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var outward: bool = true
		for i in range(0, indices.size(), 3):
			var a: int = indices[i]
			var b: int = indices[i + 1]
			var c: int = indices[i + 2]
			var cross: Vector3 = (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
			outward = outward and cross.length_squared() > .000000000001 and cross.dot(normals[a]) < 0.0 and cross.dot(normals[b]) < 0.0 and cross.dot(normals[c]) < 0.0
		check(outward, "distant pine faces have correct front winding and outward lighting at every corner")
		var importer: ImporterMesh = ImporterMesh.from_mesh(source)
		var original_indices: PackedInt32Array = importer.get_surface_lod_indices(0, importer.get_surface_lod_count(0) - 1)
		var original: Array = source.surface_get_arrays(0)
		var same: bool = original_indices.size() == indices.size()
		for i in range(0, indices.size(), 3):
			var expected: Dictionary = {}
			for corner in range(3):
				var point: Vector3 = original[Mesh.ARRAY_VERTEX][original_indices[i + corner]]
				expected[point] = int(expected.get(point, 0)) + 1
			for corner in range(3):
				var point: Vector3 = vertices[indices[i + corner]]
				if int(expected.get(point, 0)) == 0: same = false
				else: expected[point] -= 1
		check(same, "winding and lighting repairs leave every selected triangle at its original position")
	print("Pine shadow checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
