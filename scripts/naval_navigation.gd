extends RefCounted

## Independent water-only navigation. Never adds water nodes to ground A*.
## A grid is cached by hull radius/draft and live bridge state; queries and
## tie-breaking use fixed row-major cells and fixed compass order.
var map: Dictionary = {}
var bridges: Array = []
var _grids: Dictionary = {}
var _shore_rectangles: Dictionary = {}
var _shore_ready := false
const TerrainGeometry = preload("res://scripts/path_terrain_geometry.gd")
var _components: Dictionary = {}
var _bridge_revision: String = ""
var _geometry_revision: int = -1
# Isolated placement probes may query a bounded area with one proposed dock.
# Ordinary sailing leaves both empty and uses the established full-map cache.
var query_footprint := Rect2()
var query_region := Rect2i()
const DIRECTIONS: Array[Vector2] = [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN, Vector2(0.7071068, 0.7071068), Vector2(-0.7071068, 0.7071068), Vector2(0.7071068, -0.7071068), Vector2(-0.7071068, -0.7071068)]

func configure(source_map: Dictionary, source_bridges: Array) -> void:
	map = source_map
	bridges = source_bridges
	_grids.clear()
	_components.clear()
	_shore_rectangles.clear()
	_shore_ready = false
	_bridge_revision = _bridge_key()
	_geometry_revision = -1

func refresh_bridges(source_bridges: Array) -> void:
	bridges = source_bridges
	var revision: String = _bridge_key()
	if revision != _bridge_revision:
		_grids.clear()
		_components.clear()
		_bridge_revision = revision

func _bridge_key() -> String:
	var result: String = ""
	for bridge: Dictionary in bridges:
		result += "%d:%d:%.2f;" % [int(bridge.get("id", 0)), int(bool(bridge.get("alive", true))), float(bridge.get("naval_clearance", 0.0))]
	return result

func is_water(point: Vector2) -> bool:
	if not point.is_finite() or point.x < 0.0 or point.y < 0.0 or point.x >= float(map.get("size", 0)) or point.y >= float(map.get("size", 0)): return false
	return int(map.terrain[int(floorf(point.y))][int(floorf(point.x))]) == 1

func static_clear(point: Vector2, radius: float, draft: float) -> bool:
	if not is_water(point): return false
	if point.x - radius < 0 or point.y - radius < 0 or point.x + radius > float(map.size) or point.y + radius > float(map.size): return false
	# A real circular hull may touch the shore but may not intersect it.
	# Eight circumference samples miss narrow corner overlaps and disagree
	# with the swept connector used while sailing.
	for z in range(maxi(0, floori(point.y-radius)), mini(int(map.size), floori(point.y+radius)+1)):
		for x in range(maxi(0, floori(point.x-radius)), mini(int(map.size), floori(point.x+radius)+1)):
			if int(map.terrain[z][x]) == 1: continue
			var nearest: Vector2 = point.clamp(Vector2(x,z), Vector2(x+1,z+1))
			if point.distance_squared_to(nearest) < radius*radius: return false
	for bridge: Dictionary in bridges:
		if not bool(bridge.get("alive", true)): continue
		var bounds: Array = bridge.get("bounds", [])
		if bounds.size() != 4: continue
		var nearest: Vector2 = point.clamp(Vector2(float(bounds[0]), float(bounds[1])), Vector2(float(bounds[0] + bounds[2]), float(bounds[1] + bounds[3])))
		if nearest.distance_squared_to(point) < radius * radius and float(bridge.get("naval_clearance", 0.0)) + 0.001 < draft: return false
	return true

func water_clear(sim, point: Vector2, radius: float, draft: float, ignore: int = -1, dynamic: bool = true) -> bool:
	if not static_clear(point, radius, draft): return false
	if _query_blocked(point,radius): return false
	for e: Dictionary in sim.entities.values():
		if float(e.get("hp", 0.0)) <= 0.0 or int(e.get("id", -1)) == ignore or int(e.get("transport_id", -1)) > 0: continue
		var info: Dictionary = sim.data_for(str(e.get("spec", "")))
		if e.get("kind", "") == "building":
			if str(info.get("role", "")) in ["rail", "rail_junction"]: continue
			var half: float = float(info.get("size", 0)) * 0.5
			var nearest: Vector2 = point.clamp(e.pos - Vector2.ONE * half, e.pos + Vector2.ONE * half)
			if nearest.distance_squared_to(point) < pow(radius + 0.06, 2): return false
		elif dynamic and str(info.get("domain", "ground")) == "naval":
			var separation: float = radius + float(info.get("radius", 0.8)) + 0.12
			if (e.pos as Vector2).distance_squared_to(point) < separation * separation: return false
	return true

func _query_blocked(point: Vector2, radius: float) -> bool:
	if not query_footprint.has_area(): return false
	var nearest: Vector2 = point.clamp(query_footprint.position,query_footprint.end)
	return nearest.distance_squared_to(point) < pow(radius+.06,2)

## A nearby pond or the far side of a dock is not a usable pickup point. Cache
## exact hull/bridge/building components of the same grid used for sailing;
## coastline search can then reject unreachable candidates with O(1) lookup.
func connected(sim, start: Vector2, goal: Vector2, radius: float, draft: float, ignore: int = -1) -> bool:
	var grid: AStarGrid2D = _grid(sim,radius,draft)
	var key: int = grid.get_instance_id()
	if not _components.has(key):
		var fresh := PackedInt32Array()
		fresh.resize(grid.region.size.x*grid.region.size.y)
		_components[key] = {"labels":fresh,"next":1,"sources":{}}
	var data: Dictionary = _components[key]
	var a: Vector2i
	if data.sources.has(start): a = data.sources[start]
	else:
		a = _nearest_grid_cell(sim,grid,start,radius,draft,ignore)
		if data.sources.size()>64:data.sources.clear()
		data.sources[start] = a
	var b := Vector2i(floori(goal.x),floori(goal.y))
	if not grid.is_in_boundsv(b) or grid.is_point_solid(b) or not segment_clear(sim,Vector2(b)+Vector2(.5,.5),goal,radius,draft,ignore,false): b = _nearest_grid_cell(sim,grid,goal,radius,draft,ignore)
	if a.x<0 or b.x<0:return false
	var labels: PackedInt32Array = data.labels
	var width: int = grid.region.size.x
	var ai: int = (a.y-grid.region.position.y)*width+a.x-grid.region.position.x
	var bi: int = (b.y-grid.region.position.y)*width+b.x-grid.region.position.x
	if labels[ai]==0:
		var component: int = int(data.next)
		data.next = component+1
		labels[ai] = component
		var queue: Array[Vector2i] = [a]
		var cursor: int = 0
		while cursor<queue.size():
			var cell: Vector2i = queue[cursor]
			cursor+=1
			for offset: Vector2i in [Vector2i.RIGHT,Vector2i.LEFT,Vector2i.UP,Vector2i.DOWN,Vector2i(1,1),Vector2i(1,-1),Vector2i(-1,1),Vector2i(-1,-1)]:
				var next: Vector2i = cell+offset
				if not grid.is_in_boundsv(next) or grid.is_point_solid(next): continue
				if offset.x!=0 and offset.y!=0 and (grid.is_point_solid(cell+Vector2i(offset.x,0)) or grid.is_point_solid(cell+Vector2i(0,offset.y))): continue
				var ni: int = (next.y-grid.region.position.y)*width+next.x-grid.region.position.x
				if labels[ni]!=0:continue
				labels[ni] = component
				queue.append(next)
		data.labels = labels
	return labels[ai]>0 and labels[ai]==labels[bi]

func segment_clear(sim, a: Vector2, b: Vector2, radius: float, draft: float, ignore: int = -1, dynamic: bool = false) -> bool:
	if not a.is_finite() or not b.is_finite(): return false
	if not _shore_segment_clear(sim, a, b, radius): return false
	# A ship's swept hull can graze a one-cell shoreline corner for less than
	# a quarter metre. Sample more finely than a movement tick, including both
	# endpoints, so smoothing and actual motion agree at those narrow turns.
	var samples: int = maxi(1, ceili(a.distance_to(b) / 0.08))
	for n in range(samples + 1):
		if not water_clear(sim, a.lerp(b, float(n) / float(samples)), radius, draft, ignore, dynamic): return false
	return true

func _prepare_shore_rectangles() -> void:
	if _shore_ready: return
	_shore_ready = true
	var size: int = int(map.size)
	var water := PackedByteArray()
	water.resize(size*size)
	for z in range(size):
		for x in range(size): water[z*size+x] = 1 if int(map.terrain[z][x]) == 1 else 0
	var rectangles: Array[Rect2] = []
	TerrainGeometry._append_water(rectangles, size, water)
	for rectangle: Rect2 in rectangles:
		var first := Vector2i(floori(rectangle.position.x/8),floori(rectangle.position.y/8))
		var last := Vector2i(floori(rectangle.end.x/8),floori(rectangle.end.y/8))
		for z in range(first.y,last.y+1):
			for x in range(first.x,last.x+1):
				var key := Vector2i(x,z)
				if not _shore_rectangles.has(key): _shore_rectangles[key] = []
				_shore_rectangles[key].append(rectangle)

func _shore_segment_clear(sim, start: Vector2, finish: Vector2, radius: float) -> bool:
	_prepare_shore_rectangles()
	var keys: Dictionary = {}
	var samples: int = maxi(1,ceili(start.distance_to(finish)/4.0))
	# Each swept point is within two metres of a sample. Padding the query
	# by that distance only broadens candidate lookup; hull radius is unchanged.
	var reach: float = radius + 2.0
	for n in range(samples+1):
		var p: Vector2 = start.lerp(finish,float(n)/samples)
		for z in range(floori((p.y-reach)/8),floori((p.y+reach)/8)+1):
			for x in range(floori((p.x-reach)/8),floori((p.x+reach)/8)+1): keys[Vector2i(x,z)] = true
	var checked: Dictionary = {}
	for key: Vector2i in keys:
		for rectangle: Rect2 in _shore_rectangles.get(key,[]):
			if checked.has(rectangle): continue
			checked[rectangle] = true
			if _swept_shore_rect(sim,start,finish,radius,rectangle): return false
	return true

func _swept_shore_rect(sim, start: Vector2, finish: Vector2, radius: float, rectangle: Rect2) -> bool:
	if _segment_crosses_shore(start,finish,rectangle): return true
	if start.distance_squared_to(start.clamp(rectangle.position,rectangle.end)) < radius*radius: return true
	if finish.distance_squared_to(finish.clamp(rectangle.position,rectangle.end)) < radius*radius: return true
	for corner: Vector2 in [rectangle.position,rectangle.end,Vector2(rectangle.position.x,rectangle.end.y),Vector2(rectangle.end.x,rectangle.position.y)]:
		if corner.distance_squared_to(Geometry2D.get_closest_point_to_segment(corner,start,finish)) < radius*radius: return true
	return false

func _segment_crosses_shore(start: Vector2, finish: Vector2, rectangle: Rect2) -> bool:
	var direction: Vector2 = finish - start
	var first := 0.0
	var last := 1.0
	for axis in range(2):
		if absf(direction[axis]) < .000001:
			if start[axis] < rectangle.position[axis] or start[axis] > rectangle.end[axis]: return false
		else:
			var a: float = (rectangle.position[axis]-start[axis])/direction[axis]
			var b: float = (rectangle.end[axis]-start[axis])/direction[axis]
			first = maxf(first,minf(a,b))
			last = minf(last,maxf(a,b))
			if first > last: return false
	return true

func near_water(sim, desired: Vector2, radius: float, draft: float, ignore: int = -1, maximum: float = 8.0, dynamic: bool = true) -> Vector2:
	if water_clear(sim, desired, radius, draft, ignore, dynamic): return desired
	for ring in range(1, ceili(maximum / 0.5) + 1):
		var distance: float = float(ring) * 0.5
		for step in range(24):
			var point: Vector2 = desired + Vector2.from_angle(float(step) * TAU / 24.0) * distance
			if water_clear(sim, point, radius, draft, ignore, dynamic): return point
	return Vector2.INF

func path_between(sim, start: Vector2, goal: Vector2, radius: float, draft: float, ignore: int) -> Array[Vector2]:
	var answer: Array[Vector2] = []
	if segment_clear(sim, start, goal, radius, draft, ignore):
		answer.append(goal)
		return answer
	var grid: AStarGrid2D = _grid(sim, radius, draft)
	var from: Vector2i = _nearest_grid_cell(sim, grid, start, radius, draft, ignore)
	var to: Vector2i = _nearest_grid_cell(sim, grid, goal, radius, draft, ignore)
	if from.x < 0 or to.x < 0: return answer
	var ids: Array[Vector2i] = grid.get_id_path(from, to)
	if ids.is_empty(): return answer
	var raw: Array[Vector2] = []
	for cell: Vector2i in ids:
		var point: Vector2 = Vector2(cell) + Vector2(0.5, 0.5)
		if point.distance_to(start) > 0.00001: raw.append(point)
	if segment_clear(sim, raw.back() if not raw.is_empty() else start, goal, radius, draft, ignore): raw.append(goal)
	var anchor: Vector2 = start
	var index: int = 0
	while index < raw.size():
		var furthest: int = index
		for test in range(mini(raw.size() - 1, index + 8), index, -1):
			if segment_clear(sim, anchor, raw[test], radius, draft, ignore):
				furthest = test
				break
		answer.append(raw[furthest])
		anchor = raw[furthest]
		index = furthest + 1
	return answer

func _nearest_grid_cell(sim, grid: AStarGrid2D, point: Vector2, radius: float, draft: float, ignore: int) -> Vector2i:
	var origin: Vector2i = Vector2i(floori(point.x), floori(point.y))
	var best: Vector2i = Vector2i(-1, -1)
	var best_distance: float = INF
	for ring in range(5):
		for z in range(-ring, ring + 1):
			for x in range(-ring, ring + 1):
				var candidate: Vector2i = origin + Vector2i(x, z)
				if not grid.is_in_boundsv(candidate) or grid.is_point_solid(candidate): continue
				var sample: Vector2 = Vector2(candidate) + Vector2(0.5, 0.5)
				var distance: float = sample.distance_squared_to(point)
				if distance < best_distance and water_clear(sim, sample, radius, draft, ignore, false) and segment_clear(sim,point,sample,radius,draft,ignore,false):
					best_distance = distance
					best = candidate
		if best.x >= 0: return best
	return best

func _grid(sim, radius: float, draft: float) -> AStarGrid2D:
	var revision: int = int(sim.get("_static_geometry_revision"))
	if revision != _geometry_revision:
		_grids.clear()
		_components.clear()
		_geometry_revision = revision
	var key: String = "%.2f/%.2f" % [radius, draft]
	if _grids.has(key): return _grids[key]
	var size: int = int(map.size)
	var grid := AStarGrid2D.new()
	grid.region = query_region.intersection(Rect2i(0,0,size,size)) if query_region.has_area() else Rect2i(0, 0, size, size)
	grid.cell_size = Vector2.ONE
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for z in range(grid.region.position.y,grid.region.end.y):
		for x in range(grid.region.position.x,grid.region.end.x):
			var point := Vector2(x+.5,z+.5)
			if not static_clear(point, radius, draft) or _query_blocked(point,radius): grid.set_point_solid(Vector2i(x, z))
	for e: Dictionary in sim.entities.values():
		if e.get("kind", "") != "building" or float(e.get("hp", 0.0)) <= 0.0 or str(sim.data_for(e.spec).get("role", "")) in ["rail", "rail_junction"]: continue
		var half: float = float(sim.data_for(e.spec).get("size", 1)) * 0.5
		var left: int = maxi(grid.region.position.x, floori(e.pos.x - half - radius - 0.1))
		var right: int = mini(grid.region.end.x - 1, ceili(e.pos.x + half + radius + 0.1))
		var top: int = maxi(grid.region.position.y, floori(e.pos.y - half - radius - 0.1))
		var bottom: int = mini(grid.region.end.y - 1, ceili(e.pos.y + half + radius + 0.1))
		for z in range(top, bottom + 1):
			for x in range(left, right + 1):
				var point: Vector2 = Vector2(x + 0.5, z + 0.5)
				var near: Vector2 = point.clamp(e.pos - Vector2.ONE * half, e.pos + Vector2.ONE * half)
				if near.distance_squared_to(point) < pow(radius + 0.06, 2): grid.set_point_solid(Vector2i(x, z))
	_grids[key] = grid
	return grid
