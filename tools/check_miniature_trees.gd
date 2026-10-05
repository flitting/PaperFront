extends SceneTree

# A closed canopy must remain within the existing scenery footprint from every
# yaw. Mesh validity matters for shadow casting as well as a front-facing view.
const Landscape = preload("res://scripts/landscape.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var landscape = Landscape.new()
	for variant: int in 3:
		var mesh: ArrayMesh = landscape._prop_mesh("tree_%d" % variant)
		var arrays: Array = mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var element_count: int = indices.size() if not indices.is_empty() else vertices.size()
		var edges: Dictionary = {}
		var radius: float = 0.0
		for index: int in range(0, element_count, 3):
			var a_index: int = indices[index] if not indices.is_empty() else index
			var b_index: int = indices[index + 1] if not indices.is_empty() else index + 1
			var c_index: int = indices[index + 2] if not indices.is_empty() else index + 2
			var cross: Vector3 = (vertices[b_index] - vertices[a_index]).cross(vertices[c_index] - vertices[a_index])
			if cross.length_squared() < 0.000000001:
				failures.append("tree %d has a degenerate triangle" % variant)
			for corner: int in 3:
				var vertex_index: int = indices[index + corner] if not indices.is_empty() else index + corner
				var next_corner: int = index + (corner + 1) % 3
				var next_vertex_index: int = indices[next_corner] if not indices.is_empty() else next_corner
				var point: Vector3 = vertices[vertex_index]
				var normal: Vector3 = normals[vertex_index]
				radius = maxf(radius, Vector2(point.x, point.z).length())
				if not normal.is_finite() or absf(normal.length() - 1.0) > 0.001 or cross.dot(normal) >= 0.0:
					failures.append("tree %d has an invalid outward normal" % variant)
				var a: String = _key(point)
				var b: String = _key(vertices[next_vertex_index])
				var edge: String = a + "/" + b if a < b else b + "/" + a
				edges[edge] = int(edges.get(edge, 0)) + 1
		for count: int in edges.values():
			if count != 2:
				failures.append("tree %d has an open/non-manifold edge" % variant)
		if radius > 0.62:
			failures.append("tree %d grows into the existing path-clearance envelope" % variant)
		print("Tree %d: %d triangles, radius %.4fm, %d closed edges" % [variant, element_count / 3, radius, edges.size()])
	landscape.free()
	for failure: String in failures:
		push_error(failure)
	print("Miniature tree geometry: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _key(p: Vector3) -> String:
	return "%d,%d,%d" % [roundi(p.x * 100000), roundi(p.y * 100000), roundi(p.z * 100000)]
