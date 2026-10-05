extends RefCounted

## Exact mesh picking keeps parked aircraft selectable without ignoring roofs.
## Mesh triangles are cached by resource ID; transforms remain live per model.
static func ray_hit(sim, world, origin: Vector3, direction: Vector3, cache: Dictionary, accepts: Callable) -> Dictionary:
	var nearest: Dictionary = {"id": -1, "depth": INF}
	if world == null: return nearest
	for entity in sim.entities.values():
		if not accepts.call(entity) or not world.models.has(entity.id): continue
		var model: Dictionary = world.models[entity.id]
		if not model.get("volumetric", false): continue
		for graphic in model.volume.meshes:
			var transform: Transform3D = graphic.global_transform
			if absf(transform.basis.determinant()) < .000001: continue
			var inverse: Transform3D = transform.affine_inverse()
			var local_origin: Vector3 = inverse * origin
			var local_direction: Vector3 = (inverse.basis * direction).normalized()
			var mesh: Mesh = graphic.mesh
			var posed: Dictionary = {}
			if bool(model.get("direct_skinned", false)) and graphic is MeshInstance3D and graphic.skin != null:
				posed = _skinned_surface(graphic, model.volume, cache)
				if posed.is_empty(): continue
			var bounds: AABB = posed.get("bounds", mesh.get_aabb())
			if bounds.intersects_ray(local_origin, local_direction) == null: continue
			var key: int = mesh.get_instance_id()
			var surfaces: Array
			if not posed.is_empty():
				surfaces = posed.surfaces
			else:
				if not cache.has(key): cache[key] = _surfaces(mesh)
				surfaces = cache[key]
			for surface in surfaces:
				var vertices: PackedVector3Array = surface.vertices
				var indices: PackedInt32Array = surface.indices
				var count: int = indices.size() if not indices.is_empty() else vertices.size()
				for index in range(0, count - 2, 3):
					var a: int = indices[index] if not indices.is_empty() else index
					var b: int = indices[index + 1] if not indices.is_empty() else index + 1
					var c: int = indices[index + 2] if not indices.is_empty() else index + 2
					var hit: Variant = Geometry3D.ray_intersects_triangle(local_origin, local_direction, vertices[a], vertices[b], vertices[c])
					if not hit is Vector3: continue
					var depth: float = (transform * (hit as Vector3) - origin).dot(direction)
					if depth >= 0.0 and depth < float(nearest.depth): nearest = {"id": int(entity.id), "depth": depth}
	return nearest

static func _skinned_surface(graphic: MeshInstance3D, volume: Dictionary, cache: Dictionary) -> Dictionary:
	# Skin the rare hero on the CPU for picking only: no GPU readback stall,
	# and exactly the same bind/pose transforms also work in headless checks.
	var key: String = "skin:" + str(graphic.get_instance_id())
	var revision: Array = [Engine.get_process_frames(), volume.get("pose_version", 0)]
	var entry: Dictionary = cache.get(key, {})
	if entry.get("revision", []) == revision: return entry
	var skeleton: Skeleton3D = volume.get("skeleton")
	if skeleton == null or graphic.skin == null: return {}
	var skin: Skin = graphic.skin
	var to_mesh: Transform3D = graphic.global_transform.affine_inverse() * skeleton.global_transform
	var palette: Array[Transform3D] = []
	for index: int in skin.get_bind_count():
		var bone: int = skin.get_bind_bone(index)
		if bone < 0: bone = skeleton.find_bone(skin.get_bind_name(index))
		if bone < 0 or bone >= skeleton.get_bone_count(): return {}
		palette.append(to_mesh * skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(index))
	var rest_key: String = "skin_rest:" + str(graphic.mesh.get_instance_id())
	if not cache.has(rest_key):
		var rest: Array = []
		for index: int in graphic.mesh.get_surface_count():
			var arrays: Array = graphic.mesh.surface_get_arrays(index)
			rest.append({"vertices":arrays[Mesh.ARRAY_VERTEX], "indices":arrays[Mesh.ARRAY_INDEX],
				"bones":arrays[Mesh.ARRAY_BONES], "weights":arrays[Mesh.ARRAY_WEIGHTS]})
		cache[rest_key] = rest
	var surfaces: Array = []
	var bounds := AABB()
	var first: bool = true
	for surface: Dictionary in cache[rest_key]:
		var source: PackedVector3Array = surface.vertices
		var posed := PackedVector3Array()
		posed.resize(source.size())
		var bones: Variant = surface.bones
		var weights: Variant = surface.weights
		var stride: int = int(bones.size() / maxi(1, source.size())) if bones != null else 0
		for vertex: int in source.size():
			var point := Vector3.ZERO
			var total: float = 0.0
			if stride > 0 and weights != null:
				for influence: int in stride:
					var slot: int = vertex * stride + influence
					var weight: float = float(weights[slot])
					if weight <= 0.0: continue
					var bind: int = int(bones[slot])
					if bind < 0 or bind >= palette.size(): continue
					point += (palette[bind] * source[vertex]) * weight
					total += weight
			point = point / total if total > .00001 else source[vertex]
			posed[vertex] = point
			if first:
				bounds = AABB(point, Vector3.ZERO)
				first = false
			else: bounds = bounds.expand(point)
		surfaces.append({"vertices":posed, "indices":surface.indices if surface.indices != null else PackedInt32Array()})
	if first: return {}
	entry = {"revision":revision, "bounds":bounds, "surfaces":surfaces}
	cache[key] = entry
	return entry

static func _surfaces(mesh: Mesh) -> Array:
	var surfaces: Array = []
	for surface in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		surfaces.append({"vertices": arrays[Mesh.ARRAY_VERTEX], "indices": arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()})
	return surfaces
