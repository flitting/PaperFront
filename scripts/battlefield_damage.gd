extends RefCounted

## Cached cosmetic variants retain the authored paint, mesh topology and LODs.
## No shared source arrays are mutated; repairing restores the original meshes.
const EFFECT_LOD = preload("res://scripts/battlefield_effect_lod.gd")
static var world_users: int = 0
static var damaged_meshes: Dictionary = {}
static var fragment_meshes: Dictionary = {}
static var fragment_arrays: Dictionary = {}
static var fragment_builds: Dictionary = {}
static var fragment_tasks: Dictionary = {}
static var fragment_mutex := Mutex.new()

static func acquire_world() -> void:
	fragment_mutex.lock();world_users+=1;fragment_mutex.unlock()

static func release_world() -> void:
	fragment_mutex.lock();world_users-=1
	var last: bool = world_users<=0
	var tasks: Array = fragment_tasks.values().duplicate() if last else []
	fragment_mutex.unlock()
	if not last: return
	for task: int in tasks: WorkerThreadPool.wait_for_task_completion(task)
	fragment_mutex.lock()
	fragment_tasks.clear();fragment_meshes.clear();fragment_arrays.clear();fragment_builds.clear();damaged_meshes.clear()
	fragment_mutex.unlock()

static func queue_fragments(source: Mesh) -> void:
	if not source is ArrayMesh: return
	var key: int = source.get_instance_id()
	fragment_mutex.lock()
	var needed: bool = not fragment_meshes.has(key) and not fragment_tasks.has(key)
	fragment_mutex.unlock()
	if not needed: return
	# All source Resource/RenderingServer access happens here, on the caller's
	# main thread. Workers only clip copied packed arrays and publish CPU data.
	var input: Dictionary = _snapshot(source)
	fragment_mutex.lock()
	fragment_tasks[key] = WorkerThreadPool.add_task(_build_fragment_task.bind(key,input),false,"Paper destruction geometry")
	fragment_mutex.unlock()

static func _snapshot(source: Mesh) -> Dictionary:
	var surfaces: Array = []
	for surface: int in source.get_surface_count():
		surfaces.append({"arrays":source.surface_get_arrays(surface),"material":source.surface_get_material(surface)})
	return {"bounds":source.get_aabb(),"surfaces":surfaces}

static func _build_fragment_task(key: int, input: Dictionary) -> void:
	var pieces: Array = _build_fragment_arrays(input)
	fragment_mutex.lock()
	fragment_arrays[key] = pieces
	fragment_mutex.unlock()


static func damage_stage(hp_fraction: float) -> int:
	return 2 if hp_fraction <= .25 else 1 if hp_fraction <= .5 else 0

static func damaged(source: Mesh, stage: int) -> Mesh:
	if stage <= 0 or not source is ArrayMesh: return source
	var key: String = str(source.get_instance_id()) + ":" + str(stage)
	if damaged_meshes.has(key): return damaged_meshes[key]
	var result := ArrayMesh.new()
	var bounds: AABB = source.get_aabb()
	var dimensions: Vector3 = bounds.size.max(Vector3(.001,.001,.001))
	for surface: int in source.get_surface_count():
		var arrays: Array = source.surface_get_arrays(surface).duplicate(true)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] is PackedColorArray else PackedColorArray()
		if colors.size() != vertices.size():
			colors.resize(vertices.size())
			colors.fill(Color.WHITE)
		for index: int in vertices.size():
			var normalized: Vector3 = (vertices[index] - bounds.position) / dimensions - Vector3(.5,0,.5)
			# Two ragged shell scars buckle a roof and expose charred paper edges.
			var first: float = (normalized - Vector3(.28,.64,.39)).length()
			var second: float = (normalized - Vector3(-.21,.85,-.13)).length()
			var scar: float = minf(first, second * 1.1)
			var ragged: float = sin(normalized.x*41.0+normalized.z*33.0+normalized.y*21.0)*.035
			var damage: float = 1.0 - smoothstep(.18, .48 + .035 * stage, scar + ragged)
			var char_color := Color(.105,.087,.066,colors[index].a)
			colors[index] = colors[index].lerp(char_color, damage * (.77 if stage == 1 else .94))
			if damage > .72 and sin(normalized.x*73.0+normalized.z*67.0) > .62:
				colors[index] = colors[index].lerp(Color("b5a084"),.45)
			var buckle: float = damage * smoothstep(.48,.90,normalized.y)
			vertices[index].y -= dimensions.y * buckle * (.045 if stage == 1 else .11)
			vertices[index].x += dimensions.x * buckle * .016 * sin(normalized.z*19.0)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_COLOR] = colors
		result.add_surface_from_arrays(source.surface_get_primitive_type(surface),arrays)
		result.surface_set_material(surface,source.surface_get_material(surface))
	damaged_meshes[key] = result
	return result

static func peek_fragments(source: Mesh) -> Array:
	fragment_mutex.lock()
	var pieces: Array=fragment_meshes.get(source.get_instance_id(),[])
	fragment_mutex.unlock()
	return pieces

static func finalize_ready(budget_us: int = 1000) -> void:
	var started: int=Time.get_ticks_usec()
	while Time.get_ticks_usec()-started<budget_us:
		if fragment_builds.is_empty():
			fragment_mutex.lock()
			var keys: Array=fragment_arrays.keys()
			if keys.is_empty(): fragment_mutex.unlock();return
			var key: int=keys.back()
			fragment_builds[key]={"data":fragment_arrays[key],"index":0,"pieces":[]}
			fragment_arrays.erase(key)
			fragment_mutex.unlock()
		var key: int=fragment_builds.keys()[0]
		_step_fragment_build(key)

static func _step_fragment_build(key: int) -> void:
	var build: Dictionary=fragment_builds[key]
	build.pieces.append_array(_make_fragment_meshes([build.data[int(build.index)]]))
	build.index+=1
	if int(build.index)>=build.data.size():
		fragment_mutex.lock();fragment_meshes[key]=build.pieces;fragment_mutex.unlock()
		fragment_builds.erase(key)

static func fragments(source: Mesh) -> Array:
	if not source is ArrayMesh: return []
	var key: int = source.get_instance_id()
	fragment_mutex.lock()
	var ready: Array = fragment_meshes.get(key,[])
	var data: Array = fragment_arrays.get(key,[])
	var task: int = int(fragment_tasks.get(key,-1))
	fragment_mutex.unlock()
	if not ready.is_empty(): return ready
	if fragment_builds.has(key):
		while fragment_builds.has(key): _step_fragment_build(key)
		return peek_fragments(source)
	if data.is_empty() and task>=0:
		WorkerThreadPool.wait_for_task_completion(task)
		fragment_mutex.lock()
		data = fragment_arrays.get(key,[])
		fragment_tasks.erase(key)
		fragment_mutex.unlock()
	if data.is_empty(): data=_build_fragment_arrays(_snapshot(source))
	# Mesh/RID creation stays on the main thread in every renderer backend.
	var pieces: Array = _make_fragment_meshes(data)
	fragment_mutex.lock()
	fragment_meshes[key] = pieces
	fragment_arrays.erase(key)
	fragment_mutex.unlock()
	return pieces

static func _make_fragment_meshes(data: Array) -> Array:
	var pieces: Array = []
	for piece: Dictionary in data:
		var mesh := ArrayMesh.new()
		for surface: Dictionary in piece.surfaces:
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,surface.arrays)
			mesh.surface_set_material(mesh.get_surface_count()-1,surface.material)
		pieces.append({"mesh":mesh,"lod_meshes":EFFECT_LOD.fragment_tiers(mesh),"center":piece.center})
	return pieces

static func _build_fragment_arrays(input: Dictionary) -> Array:
	var bounds: AABB = input.bounds
	var size: Vector3 = bounds.size.max(Vector3(.001,.001,.001))
	var groups: Dictionary = {}
	for surface: int in input.surfaces.size():
		var arrays: Array = input.surfaces[surface].arrays
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array else PackedVector3Array()
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] is PackedColorArray else PackedColorArray()
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
		var count: int = indices.size() if not indices.is_empty() else vertices.size()
		for triangle: int in range(0,count-2,3):
			var corners: Array[int] = []
			var center := Vector3.ZERO
			for corner: int in 3:
				var index: int = indices[triangle+corner] if not indices.is_empty() else triangle+corner
				corners.append(index)
				center += vertices[index] / 3.0
			var low: Vector3 = (vertices[corners[0]]-bounds.position)/size
			var high: Vector3 = low
			for index: int in corners:
				var local: Vector3 = (vertices[index]-bounds.position)/size
				low=low.min(local);high=high.max(local)
			var polygon: Array = []
			var face_normal: Vector3 = (vertices[corners[1]]-vertices[corners[0]]).cross(vertices[corners[2]]-vertices[corners[0]]).normalized()
			for index: int in corners:
				polygon.append({"point":vertices[index],"normal":normals[index] if normals.size()==vertices.size() else face_normal,"color":colors[index] if colors.size()==vertices.size() else Color.WHITE})
			var upper := Vector3i(int(low.x*4.0) if absf(high.x-low.x)<.000001 else ceili(high.x*4.0)-1,int(low.y*2.0) if absf(high.y-low.y)<.000001 else ceili(high.y*2.0)-1,int(low.z*2.0) if absf(high.z-low.z)<.000001 else ceili(high.z*2.0)-1)
			for z: int in range(clampi(int(low.z*2.0),0,1),clampi(upper.z,0,1)+1):
				for y: int in range(clampi(int(low.y*2.0),0,1),clampi(upper.y,0,1)+1):
					for x: int in range(clampi(int(low.x*4.0),0,3),clampi(upper.x,0,3)+1):
						var cell: int = x+y*4+z*8
						var cell_min: Vector3 = bounds.position+Vector3(float(x)/4.0,float(y)/2.0,float(z)/2.0)*size
						var cell_max: Vector3 = cell_min+size/Vector3(4,2,2)
						var clipped: Array = polygon
						for axis: int in 3:
							clipped=_clip(clipped,axis,cell_min[axis],true)
							clipped=_clip(clipped,axis,cell_max[axis],false)
						if clipped.size()<3: continue
						if not groups.has(cell): groups[cell] = {}
						if not groups[cell].has(surface): groups[cell][surface] = {"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"colors":PackedColorArray()}
						var group: Dictionary = groups[cell][surface]
						for index: int in range(1,clipped.size()-1):
							if ((clipped[index].point-clipped[0].point) as Vector3).cross(clipped[index+1].point-clipped[0].point).length_squared()<.000000001: continue
							for corner: Dictionary in [clipped[0],clipped[index],clipped[index+1]]:
								group.vertices.append(corner.point)
								group.normals.append(corner.normal)
								group.colors.append(corner.color)
	var pieces: Array = []
	for cell: int in groups:
		var surfaces: Array = []
		var center := bounds.position + Vector3((float(cell%4)+.5)/4.0,(float((cell/4)%2)+.5)/2.0,(float(cell/8)+.5)/2.0)*size
		for surface: int in groups[cell]:
			var group: Dictionary = groups[cell][surface]
			var vertices: PackedVector3Array = group.vertices
			if vertices.is_empty(): continue
			for index: int in vertices.size(): vertices[index] -= center
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = group.normals
			arrays[Mesh.ARRAY_COLOR] = group.colors
			surfaces.append({"arrays":arrays,"material":input.surfaces[surface].material})
		if not surfaces.is_empty(): pieces.append({"surfaces":surfaces,"center":center})
	return pieces


static func _clip(polygon: Array, axis: int, boundary: float, lower: bool) -> Array:
	if polygon.is_empty(): return []
	var result: Array = []
	var previous: Dictionary = polygon.back()
	var previous_inside: bool = previous.point[axis]>=boundary-.00001 if lower else previous.point[axis]<=boundary+.00001
	for current: Dictionary in polygon:
		var inside: bool = current.point[axis]>=boundary-.00001 if lower else current.point[axis]<=boundary+.00001
		if inside != previous_inside:
			var denominator: float = current.point[axis]-previous.point[axis]
			var t: float = clampf((boundary-previous.point[axis])/denominator,0,1) if absf(denominator)>.000001 else 0.0
			result.append({"point":(previous.point as Vector3).lerp(current.point,t),"normal":(previous.normal as Vector3).lerp(current.normal,t).normalized(),"color":(previous.color as Color).lerp(current.color,t)})
		if inside: result.append(current)
		previous=current;previous_inside=inside
	return result
