extends RefCounted
class_name BackgroundPaths

# Owns every AStar object it touches. Jobs contain immutable value snapshots;
# this thread never reads the live simulation or accesses rendering nodes.
var _thread:=Thread.new()
var _mutex:=Mutex.new()
var _wake:=Semaphore.new()
var _jobs:Array[Dictionary]=[]
var _results:Array[Dictionary]=[]
var _stopping:bool=false
var _data:Dictionary
var _graphs:Dictionary={}

func start(data:Dictionary)->void:
	_data=data
	_thread.start(_run,Thread.PRIORITY_LOW)

func submit(job:Dictionary)->bool:
	if not _mutex.try_lock():return false
	_jobs.append(job)
	_mutex.unlock()
	_wake.post()
	return true

func collect()->Array[Dictionary]:
	if not _mutex.try_lock():return []
	var result:Array[Dictionary]=_results
	_results=[]
	_mutex.unlock()
	return result

func close()->void:
	if not _thread.is_started():return
	_mutex.lock();_stopping=true;_jobs.clear();_mutex.unlock()
	_wake.post()
	_thread.wait_to_finish()

func _run()->void:
	while true:
		_wake.wait()
		_mutex.lock()
		var stop:bool=_stopping
		var job:Dictionary={} if _jobs.is_empty() else _jobs.pop_front()
		_mutex.unlock()
		if stop:return
		if job.is_empty():continue
		var before:int=Time.get_ticks_usec()
		var path:Array=_search(job)
		var result:Dictionary={"id":job.id,"token":job.token,"revision":job.revision,"path":path,"worker_us":Time.get_ticks_usec()-before}
		_mutex.lock();_results.append(result);_mutex.unlock()
		# Leave CPU time for rendering even during a sustained command burst.
		OS.delay_usec(1000)

func _graph(radius:float)->Dictionary:
	if _graphs.has(radius):return _graphs[radius]
	var nav:=AStar2D.new()
	nav.reserve_space(_data.ids.size())
	var size:int=int(_data.size)
	for raw_id in _data.ids:
		var id:int=int(raw_id)
		nav.add_point(id,_data.extra_positions[id] if _data.extra_positions.has(id) else Vector2(id%size+.5,id/size+.5))
	var edges:PackedInt64Array=_data.edges
	for i in range(0,edges.size(),2):nav.connect_points(edges[i],edges[i+1])
	var terrain:Array=_data.masks.get(radius,[]).duplicate()
	for id in terrain:nav.set_point_disabled(id,true)
	var terrain_set: Dictionary = {}
	for id in terrain: terrain_set[id] = true
	var entry:Dictionary={"nav":nav,"revision":-1,"terrain":terrain,"terrain_set":terrain_set,"dynamic":[],"ruin_chunks":{},"ruin_occupancy":{},"extra_positions":_data.extra_positions.duplicate(),"extra_cells":_data.extra_cells.duplicate(true),"detail_rectangles":{},"collision_hard":{},"collision_vehicles":{}}
	_graphs[radius]=entry
	return entry

func _search(job:Dictionary)->Array:
	var radius:float=job.radius
	var graph:Dictionary=_graph(radius)
	var nav:AStar2D=graph.nav
	if int(graph.revision)!=int(job.revision):
		# New buildings/mines gain local samples entirely on this worker. Their
		# real footprint still disables points with radius+.02 clearance.
		if _detail_hard_obstacles(graph, job.geometry.hard, radius):
			# New samples must also inherit unchanged nearby forest occupancy.
			for old_chunk in graph.ruin_chunks.values(): old_chunk.revision = -1
		for id in graph.dynamic:
			if not graph.terrain_set.has(id) and not graph.ruin_occupancy.has(id): nav.set_point_disabled(id,false)
		# Forest chunks keep reference-counted occupancy: removing a tree cannot
		# accidentally reopen a node still covered by a neighboring tree or wall.
		var chunks: Array = job.geometry.get("ruin_chunks", [])
		for index in range(chunks.size()):
			var chunk: Dictionary = chunks[index]
			var old: Dictionary = graph.ruin_chunks.get(index, {})
			if int(old.get("revision", -1)) == int(chunk.revision): continue
			for id in old.get("nodes", []):
				var remaining: int = int(graph.ruin_occupancy[id]) - 1
				if remaining > 0: graph.ruin_occupancy[id] = remaining
				else:
					graph.ruin_occupancy.erase(id)
					if not graph.terrain_set.has(id): nav.set_point_disabled(id, false)
			var nodes: Array = _rectangle_nodes(nav, chunk.rectangles, radius, graph)
			for id in nodes:
				graph.ruin_occupancy[id] = int(graph.ruin_occupancy.get(id, 0)) + 1
				nav.set_point_disabled(id, true)
			graph.ruin_chunks[index] = {"revision": chunk.revision, "nodes": nodes, "collision":_collision_buckets(chunk.rectangles)}
		var rectangles:Array=job.geometry.hard
		if radius>.5:rectangles=rectangles+job.geometry.vehicles
		graph.dynamic=_rectangle_nodes(nav, rectangles, radius, graph)
		for id in graph.dynamic:nav.set_point_disabled(id,true)
		graph.collision_hard=_collision_buckets(job.geometry.hard)
		graph.collision_vehicles=_collision_buckets(job.geometry.vehicles)
		graph.revision=job.revision
	var start:int=_nearest(nav,job.start,float(job.start_height),graph,radius)
	var finish:int=_nearest(nav,job.goal,float(job.goal_height),graph,radius)
	if start<0 or finish<0:return []
	var points:PackedVector2Array=nav.get_point_path(start,finish)
	if points.is_empty():return []
	# Only remove collinear points. No main-thread ray casting or lane search.
	var path:Array=[]
	for i in range(points.size()):
		if i>0 and i<points.size()-1 and (points[i]-points[i-1]).normalized().is_equal_approx((points[i+1]-points[i]).normalized()):continue
		path.append(points[i])
	if (path.back() as Vector2).distance_to(job.goal)>.05:path.append(job.goal)
	return path

func _rectangle_nodes(nav: AStar2D, rectangles: Array, radius: float, graph: Dictionary) -> Array:
	var disabled: Dictionary = {}
	var size: int = int(_data.size)
	var clearance: float = radius + .02
	for rect: Rect2 in rectangles:
		var bounds: Rect2 = rect.grow(clearance)
		for z in range(maxi(0, floori(bounds.position.y)), mini(size, ceili(bounds.end.y))):
			for x in range(maxi(0, floori(bounds.position.x)), mini(size, ceili(bounds.end.x))):
				for id: int in _nodes_in_cell(nav, Vector2i(x,z), graph):
					var p: Vector2 = nav.get_point_position(id)
					if p.clamp(rect.position, rect.end).distance_squared_to(p) < clearance * clearance: disabled[id] = true
	return disabled.keys()

func _nearest(nav:AStar2D,point:Vector2,height:float,graph:Dictionary,radius:float)->int:
	var size:int=int(_data.size)
	var cell:=Vector2i(floori(point.x),floori(point.y))
	var best:int=-1
	var distance:float=INF
	for z in range(maxi(0,cell.y-2),mini(size,cell.y+3)):
		for x in range(maxi(0,cell.x-2),mini(size,cell.x+3)):
			for id: int in _nodes_in_cell(nav, Vector2i(x,z), graph):
				if nav.is_point_disabled(id) or absf(_height_at(nav.get_point_position(id))-height)>.8:continue
				var d:float=point.distance_squared_to(nav.get_point_position(id))
				if d<distance and _connector_clear(point,nav.get_point_position(id),radius,graph):best=id;distance=d
	return best

func _nodes_in_cell(nav: AStar2D, cell: Vector2i, graph: Dictionary) -> Array[int]:
	var answer: Array[int] = []
	var id: int = cell.y * int(_data.size) + cell.x
	if nav.has_point(id): answer.append(id)
	answer.append_array(graph.extra_cells.get(cell, []))
	return answer

func _height_at(point: Vector2) -> float:
	var size: int = int(_data.size)
	var x: int = clampi(floori(point.x), 0, size-1)
	var z: int = clampi(floori(point.y), 0, size-1)
	var height: float = float(_data.heights[z*size+x])
	if int(_data.terrain[z*size+x]) == 2:
		var fraction: float = point.y - (z+.5)
		var next_z: int = z + (1 if fraction>=0 else -1)
		if next_z>=0 and next_z<size:
			var other: float = float(_data.heights[next_z*size+x])
			if absf(other-height)<=.75: height=lerpf(height,other,absf(fraction))
	return height

func _terrain_clear(point: Vector2, radius: float) -> bool:
	var size: int = int(_data.size)
	var height: float = _height_at(point)
	for offset in [Vector2.ZERO, Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN, Vector2(.707,.707), Vector2(-.707,.707), Vector2(.707,-.707), Vector2(-.707,-.707)]:
		var sample: Vector2 = point + offset*radius
		if sample.x<0 or sample.y<0 or sample.x>=size or sample.y>=size: return false
		var id: int = floori(sample.y)*size+floori(sample.x)
		if int(_data.land[id])==0 or absf(_height_at(sample)-height)>.8: return false
	return true

func _detail_id(point: Vector2) -> int:
	var size: int = int(_data.size)
	return size*size + roundi(point.y*2.0)*(size*2+1) + roundi(point.x*2.0)

func _detail_hard_obstacles(graph: Dictionary, rectangles: Array, radius: float) -> bool:
	var nav: AStar2D = graph.nav
	var size: int = int(_data.size)
	var added: Array[int] = []
	for rect: Rect2 in rectangles:
		if graph.detail_rectangles.has(rect): continue
		graph.detail_rectangles[rect] = true
		var bounds: Rect2 = rect.grow(1.5)
		for z in range(maxi(1,ceili(bounds.position.y*2)), mini(size*2,floori(bounds.end.y*2))+1):
			for x in range(maxi(1,ceili(bounds.position.x*2)), mini(size*2,floori(bounds.end.x*2))+1):
				var point := Vector2(x,z)*.5
				if rect.has_point(point) or (x%2==1 and z%2==1): continue
				var id: int = _detail_id(point)
				if nav.has_point(id) or not _terrain_clear(point,.2): continue
				nav.add_point(id,point)
				graph.extra_positions[id] = point
				var cell := Vector2i(floori(point.x),floori(point.y))
				if not graph.extra_cells.has(cell): graph.extra_cells[cell]=[]
				graph.extra_cells[cell].append(id)
				if not _terrain_clear(point,radius):
					graph.terrain.append(id)
					graph.terrain_set[id]=true
					nav.set_point_disabled(id,true)
				added.append(id)
	for id in added:
		var point: Vector2 = graph.extra_positions[id]
		for offset in [Vector2(.5,0),Vector2(-.5,0),Vector2(0,.5),Vector2(0,-.5)]:
			var other: Vector2 = point+offset
			if other.x<0 or other.y<0 or other.x>=size or other.y>=size: continue
			var regular: bool = is_equal_approx(fposmod(other.x,1.0),.5) and is_equal_approx(fposmod(other.y,1.0),.5)
			var other_id: int = floori(other.y)*size+floori(other.x) if regular else _detail_id(other)
			if not nav.has_point(other_id) or nav.are_points_connected(id,other_id): continue
			var legal := true
			var previous: Vector2 = point
			for sample in range(1,5):
				var current: Vector2 = point.lerp(other,float(sample)/4.0)
				if not _terrain_clear(current,.2) or absf(_height_at(current)-_height_at(previous))>.8:
					legal=false
					break
				previous=current
			if legal: nav.connect_points(id,other_id)
	return not added.is_empty()

# Arbitrary real positions are not graph centers. A nearby legal node may still
# be across a rounded footprint corner; select a legal connector on this worker.
func _collision_buckets(rectangles: Array) -> Dictionary:
	var buckets: Dictionary={}
	var bounds:=Rect2()
	for index in range(rectangles.size()):
		var rectangle: Rect2=rectangles[index]
		bounds=rectangle if index==0 else bounds.merge(rectangle)
		var first:=Vector2i(floori(rectangle.position.x/2.0),floori(rectangle.position.y/2.0))
		var last:=Vector2i(floori(rectangle.end.x/2.0),floori(rectangle.end.y/2.0))
		for z in range(first.y,last.y+1):
			for x in range(first.x,last.x+1):
				var key:=Vector2i(x,z)
				if not buckets.has(key):buckets[key]=[]
				buckets[key].append(rectangle)
	return {"bounds":bounds,"buckets":buckets}

func _connector_rectangles_clear(start: Vector2, finish: Vector2, radius: float, cache: Dictionary) -> bool:
	if cache.is_empty() or (cache.buckets as Dictionary).is_empty():return true
	var clearance: float=radius+.02
	var padded: float=sqrt(clearance*clearance+.00001)
	var low: Vector2=start.min(finish)-Vector2.ONE*padded
	var high: Vector2=start.max(finish)+Vector2.ONE*padded
	var bounds: Rect2=cache.bounds
	if high.x<bounds.position.x or high.y<bounds.position.y or low.x>bounds.end.x or low.y>bounds.end.y:return true
	var first:=Vector2i(floori(low.x/2.0),floori(low.y/2.0))
	var last:=Vector2i(floori(high.x/2.0),floori(high.y/2.0))
	var checked: Dictionary={}
	for z in range(first.y,last.y+1):
		for x in range(first.x,last.x+1):
			for rectangle: Rect2 in cache.buckets.get(Vector2i(x,z),[]):
				if checked.has(rectangle):continue
				checked[rectangle]=true
				if _swept_circle_rect(start,finish,clearance,rectangle):return false
	return true

func _connector_clear(start: Vector2, finish: Vector2, radius: float, graph: Dictionary) -> bool:
	if not _connector_rectangles_clear(start,finish,radius,graph.collision_hard):return false
	if radius>.5 and not _connector_rectangles_clear(start,finish,radius,graph.collision_vehicles):return false
	for chunk in graph.ruin_chunks.values():
		if not _connector_rectangles_clear(start,finish,radius,chunk.collision):return false
	var distance: float=start.distance_to(finish)
	var checks: int=maxi(1,ceili(distance/.25))
	var previous:=start
	for n in range(1,checks+1):
		var point: Vector2=start.lerp(finish,float(n)/float(checks))
		if not _terrain_clear(point,0.0) or absf(_height_at(point)-_height_at(previous))>.8:return false
		previous=point
	checks=maxi(1,ceili(distance/.4))
	for n in range(checks+1):
		if not _terrain_clear(start.lerp(finish,float(n)/float(checks)),radius):return false
	return true

func _swept_circle_rect(start: Vector2, finish: Vector2, radius: float, rectangle: Rect2) -> bool:
	var padded_radius: float=sqrt(radius*radius+.00001)
	var low: Vector2=start.min(finish)-Vector2.ONE*padded_radius
	var high: Vector2=start.max(finish)+Vector2.ONE*padded_radius
	if high.x<rectangle.position.x or high.y<rectangle.position.y or low.x>rectangle.end.x or low.y>rectangle.end.y:return false
	if _segment_crosses_rect(start,finish,rectangle):return true
	var closest: Vector2=start.clamp(rectangle.position,rectangle.end)
	if start.distance_squared_to(closest)<radius*radius+.00001:return true
	closest=finish.clamp(rectangle.position,rectangle.end)
	if finish.distance_squared_to(closest)<radius*radius+.00001:return true
	for corner in [rectangle.position,rectangle.end,Vector2(rectangle.position.x,rectangle.end.y),Vector2(rectangle.end.x,rectangle.position.y)]:
		closest=Geometry2D.get_closest_point_to_segment(corner,start,finish)
		if (corner as Vector2).distance_squared_to(closest)<radius*radius+.00001:return true
	return false

func _segment_crosses_rect(start: Vector2, end: Vector2, rectangle: Rect2) -> bool:
	var direction: Vector2=end-start
	var first:=0.0;var last:=1.0
	for axis in range(2):
		if absf(direction[axis])<.000001:
			if start[axis]<rectangle.position[axis] or start[axis]>rectangle.end[axis]:return false
		else:
			var a: float=(rectangle.position[axis]-start[axis])/direction[axis]
			var b: float=(rectangle.end[axis]-start[axis])/direction[axis]
			first=maxf(first,minf(a,b));last=minf(last,maxf(a,b))
			if first>last:return false
	return true
