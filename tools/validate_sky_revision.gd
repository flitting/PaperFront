extends SceneTree

func _initialize() -> void:
	var author = load("res://scripts/sky_models.gd")
	var failures: Array[String] = []
	var count: int = 0
	var triangles: int = 0
	for kind: String in ["building", "unit"]:
		for art: String in author.BUILDINGS if kind == "building" else author.UNITS:
			var made: Array[Dictionary] = []
			for team: int in [0, 1]:
				var recipe: Dictionary = author.make(VolumeModels.CraftMesh.new(), art, team, kind)
				made.append(recipe)
				if recipe.is_empty(): failures.append(kind + "/" + art + ": empty recipe"); continue
				if not recipe.dimensions.is_finite() or recipe.dimensions.min_axis_index() < 0: failures.append(art + ": bad bounds")
				for field: String in ["body_mesh", "turret_mesh"]:
					if not recipe.has(field): continue
					var arrays: Array = recipe[field].surface_get_arrays(0)
					var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
					triangles += vertices.size() / 3
					if vertices.is_empty() or vertices.size() != normals.size(): failures.append(art + ": missing vertices/normals")
					for i: int in range(0, vertices.size(), 3):
						var area: Vector3 = (vertices[i+1] - vertices[i]).cross(vertices[i+2] - vertices[i])
						if area.length_squared() < 0.0000000001: failures.append(art + "/" + field + ": degenerate triangle " + str(i / 3))
						if area.dot(normals[i]) > 0.000001: failures.append(art + ": inward triangle")
						for j: int in range(i, i+3):
							if not vertices[j].is_finite() or absf(normals[j].length() - 1.0) > .001: failures.append(art + ": nonfinite vertex/bad normal")
				if recipe.has("turret_mesh") and not recipe.has("muzzle_pos"): failures.append(art + ": turret missing muzzle")
				count += 1
			if made.size() == 2:
				for field: String in ["body_mesh", "turret_mesh"]:
					if not made[0].has(field): continue
					var a: Array = made[0][field].surface_get_arrays(0)
					var b: Array = made[1][field].surface_get_arrays(0)
					if a[Mesh.ARRAY_VERTEX] != b[Mesh.ARRAY_VERTEX]: failures.append(art + ": player changed geometry")
	print("SKY_SOURCE_VALIDATION ", JSON.stringify({"recipes": count, "triangles": triangles, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
