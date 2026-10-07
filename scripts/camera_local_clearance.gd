extends RefCounted

const CELL := 8.0
var buckets: Dictionary = {}

func rebuild(landscape: Node3D) -> void:
	buckets.clear()
	if not is_instance_valid(landscape): return
	var pending: Array[Node] = [landscape]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is MultiMeshInstance3D and node.multimesh != null and node.multimesh.mesh != null:
			var shape: AABB = node.multimesh.mesh.get_aabb()
			for index: int in node.multimesh.instance_count:
				_add(node.global_transform * node.multimesh.get_instance_transform(index) * shape)
		elif node is MeshInstance3D and node.mesh != null:
			_add(node.global_transform * node.mesh.get_aabb())
		for child: Node in node.get_children(): pending.append(child)

func _add(bounds: AABB) -> void:
	# Terrain and river meshes span whole chunks/maps. Their conservative AABB
	# would reintroduce the distant-mountain zoom bug; sample real terrain instead.
	if bounds.size.x > 16.0 or bounds.size.z > 16.0 or bounds.size.y < .1: return
	var area := Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z)).grow(.6)
	for z: int in range(floori(area.position.y / CELL), floori(area.end.y / CELL) + 1):
		for x: int in range(floori(area.position.x / CELL), floori(area.end.x / CELL) + 1):
			var key := Vector2i(x, z)
			if not buckets.has(key): buckets[key] = []
			buckets[key].append({"area":area,"top":bounds.end.y})

func height_at(sim, point: Vector2) -> float:
	var top: float = MapData.height_at(sim.map, point)
	for offset: Vector2 in [Vector2(-.7,0),Vector2(.7,0),Vector2(0,-.7),Vector2(0,.7)]:
		top = maxf(top, MapData.height_at(sim.map, point + offset))
	for record: Dictionary in buckets.get(Vector2i(floori(point.x/CELL),floori(point.y/CELL)),[]):
		if record.area.has_point(point): top=maxf(top,float(record.top))
	for entity in sim._nearby_entities(point, 6.0):
		if str(entity.kind) != "building" or float(entity.hp) <= 0.0: continue
		var info: Dictionary = sim.data_for(str(entity.spec))
		var half: float = float(info.get("size",1.0))*.5+.6
		if absf(point.x-entity.pos.x) <= half and absf(point.y-entity.pos.y) <= half:
			top=maxf(top,MapData.height_at(sim.map,entity.pos)+float(info.get("camera_height",maxf(4.0,float(info.get("size",1.0))*1.5))))
	return top
