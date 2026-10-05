extends RefCounted

## Original neutral cut-paper art. The mesh is a printed silhouette, never a
## volumetric body; existing landscape batches still own routes and ground pose.
static var _meshes: Dictionary = {}
static var _material: ShaderMaterial

static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = preload("res://assets/civilians/paper_civilian.gdshader")
	return _material

static func face_camera(view: Camera3D) -> void:
	var right := Vector3(view.global_basis.x.x, 0, view.global_basis.x.z).normalized()
	material().set_shader_parameter("camera_right", right)

static func mesh(variant: int) -> ArrayMesh:
	variant = posmod(variant, 3)
	if _meshes.has(variant): return _meshes[variant]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var cloth: Color = [Color("ab7767"), Color("648b8c"), Color("a89870")][variant]
	var ink := Color("514a41")
	var paper := Color("efe0bd")
	# The outer cut leaves a narrow warm paper rim around the full silhouette.
	_polygon([Vector2(-.23,0),Vector2(-.25,.09),Vector2(-.15,.50),Vector2(-.20,.54),Vector2(-.28,.51),Vector2(-.34,.60),Vector2(-.28,.99),Vector2(-.20,1.07),Vector2(-.12,1.10),Vector2(-.14,1.29),Vector2(-.17,1.33),Vector2(-.17,1.38),Vector2(.13,1.38),Vector2(.16,1.31),Vector2(.12,1.26),Vector2(.13,1.10),Vector2(.24,1.06),Vector2(.32,.96),Vector2(.30,.55),Vector2(.22,.51),Vector2(.16,.56),Vector2(.14,.47),Vector2(.24,.10),Vector2(.25,0),Vector2(.07,0),Vector2(0,.36),Vector2(-.06,0)], paper, 0.0, vertices, normals, colors)
	_polygon([Vector2(-.17,.04),Vector2(-.19,.12),Vector2(-.11,.54),Vector2(.10,.54),Vector2(.18,.11),Vector2(.19,.04),Vector2(.10,.04),Vector2(0,.44),Vector2(-.10,.04)], ink, .001, vertices, normals, colors)
	var hem: float = .42 if variant == 2 else .54
	_polygon([Vector2(-.19,1.03),Vector2(-.10,1.09),Vector2(.09,1.09),Vector2(.23,1.01),Vector2(.26,.60),Vector2(.20,.57),Vector2(.17,.85),Vector2(.16,hem),Vector2(-.16,hem),Vector2(-.18,.87),Vector2(-.25,.57),Vector2(-.28,.62),Vector2(-.23,.98)], cloth, .002, vertices, normals, colors)
	_polygon([Vector2(-.10,1.09),Vector2(-.11,1.25),Vector2(-.07,1.32),Vector2(.08,1.32),Vector2(.11,1.23),Vector2(.08,1.10),Vector2(0,1.06)], Color("cfa986"), .003, vertices, normals, colors)
	_polygon([Vector2(-.13,1.31),Vector2(-.12,1.35),Vector2(.10,1.35),Vector2(.12,1.28),Vector2(.04,1.27),Vector2(.02,1.31)], ink, .004, vertices, normals, colors)
	_polygon([Vector2(-.095,.96),Vector2(-.067,.96),Vector2(-.038,.58),Vector2(-.068,.58)], cloth.darkened(.24), .004, vertices, normals, colors)
	_polygon([Vector2(-.08,1.05),Vector2(0,.95),Vector2(.08,1.05),Vector2(.05,1.085),Vector2(0,1.03),Vector2(-.06,1.085)], paper, .004, vertices, normals, colors)
	# A small eye and bag are printed ink/pigment on the same paper face.
	_polygon([Vector2(.04,1.22),Vector2(.065,1.22),Vector2(.065,1.24),Vector2(.04,1.24)], ink, .005, vertices, normals, colors)
	if variant == 1:
		_polygon([Vector2(.07,.76),Vector2(.27,.77),Vector2(.28,.57),Vector2(.09,.54)], Color("9b7654"), .005, vertices, normals, colors)
		_polygon([Vector2(-.12,1.03),Vector2(-.09,1.04),Vector2(.19,.73),Vector2(.16,.71)], ink, .006, vertices, normals, colors)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	result.surface_set_material(0, material())
	# Shader turns the paper about its foot, so allow its horizontal sweep.
	result.custom_aabb = AABB(Vector3(-.36, 0, -.36), Vector3(.72, 1.40, .72))
	result.set_meta("representation", "flat_cut_paper")
	result.set_meta("paper_depth", .006)
	_meshes[variant] = result
	return result

static func _polygon(points: Array, color: Color, depth: float, vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray) -> void:
	var outline := PackedVector2Array(points)
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(outline)
	for index: int in indices:
		var point: Vector2 = outline[index]
		vertices.append(Vector3(point.x, point.y, depth))
		normals.append(Vector3.BACK)
		colors.append(color)
