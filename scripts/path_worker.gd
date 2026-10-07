extends RefCounted
class_name BackgroundPaths
const TerrainGeometry=preload("res://scripts/path_terrain_geometry.gd")

# Owns every AStar object it touches. Jobs contain immutable value snapshots;
# this thread never reads the live simulation or accesses rendering nodes.
var _thread:=Thread.new()
var _mutex:=Mutex.new()
var _wake:=Semaphore.new()
var _jobs:Array[Dictionary]=[]
var _results:Array[Dictionary]=[]
var _stopping:bool=false
var _minimum_revision:int=-1
var _data:Dictionary
var _graphs:Dictionary={}
var _terrain_collision:Dictionary={}
var _flat_safe:=PackedByteArray()
var _flat_wide_safe:=PackedByteArray()
var route_cache_enabled:bool=true
var _metrics:Dictionary={"astar_searches":0,"corridor_hits":0,"connector_checks":0,"smoothing_probes":0}
const CORRIDOR_CELL_SIZE:float=8.0
const MAX_CORRIDOR_GOALS:int=256
const MAX_CORRIDORS_PER_GOAL:int=4
const CLEARANCE_OFFSETS: Array[Vector2] = [Vector2.ZERO, Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN, Vector2(.707,.707), Vector2(-.707,.707), Vector2(.707,-.707), Vector2(-.707,-.707)]

func start(data:Dictionary)->void:
	_data=data
	_flat_safe=data.get("flat",PackedByteArray())
	_flat_wide_safe=data.get("flat_wide",PackedByteArray())
	route_cache_enabled=bool(data.get("route_cache_enabled",route_cache_enabled))
	_thread.start(_run,Thread.PRIORITY_LOW)

func submit(job:Dictionary)->bool:
	if not _mutex.try_lock():return false
	_minimum_revision=maxi(_minimum_revision,int(job.revision))
	_jobs.append(job)
	_jobs.sort_custom(func(a,b):return int(a.get("priority",0))>int(b.get("priority",0)) if int(a.get("priority",0))!=int(b.get("priority",0)) else int(a.token)<int(b.token))
	_mutex.unlock()
	_wake.post()
	return true

func prioritize(ids:Dictionary)->void:
	if not _mutex.try_lock():return
	for job:Dictionary in _jobs:
		job.priority=3 if ids.has(int(job.id)) else int(job.get("base_priority",job.get("priority",0)))
	_jobs.sort_custom(func(a,b):return int(a.get("priority",0))>int(b.get("priority",0)) if int(a.get("priority",0))!=int(b.get("priority",0)) else int(a.token)<int(b.token))
	_mutex.unlock()

func invalidate(revision:int)->void:
	# Queued obsolete geometry must not delay a new command burst. Running
	# searches finish normally; skipped jobs still return a counted result.
	if not _mutex.try_lock():return
	_minimum_revision=maxi(_minimum_revision,revision)
	_mutex.unlock()

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
		var minimum_revision:int=_minimum_revision
		var job:Dictionary={} if _jobs.is_empty() else _jobs.pop_front()
		_mutex.unlock()
		if stop:return
		if job.is_empty():continue
		var before:int=Time.get_ticks_usec()
		var previous_metrics:Dictionary=_metrics.duplicate()
		var path:Array=[] if int(job.revision)<minimum_revision else _search(job)
		if path.size()>1 and int(job.get("navigation_lane",-1))>=0:path=_spread_group_corners(job,path,_graph(float(job.radius),bool(job.get("vehicle",true))))
		var result:Dictionary={"id":job.id,"token":job.token,"revision":job.revision,"path":path,"worker_us":Time.get_ticks_usec()-before}
		var metrics:Dictionary={}
		for key in _metrics:metrics[key]=int(_metrics[key])-int(previous_metrics[key])
		result.worker_stats=metrics
		_mutex.lock();_results.append(result);_mutex.unlock()
		# Low thread priority and the bounded pool leave scheduling to the OS.
		# Sleeping after every path imposed a fixed delay on large command bursts.

func _graph(radius:float, vehicle:bool=true)->Dictionary:
	var key:=Vector2(radius,1 if vehicle else 0)
	if _graphs.has(key):return _graphs[key]
	if _terrain_collision.is_empty():_terrain_collision=_collision_buckets(TerrainGeometry.build(_data))
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
	var entry:Dictionary={"nav":nav,"vehicle":vehicle,"revision":-1,"terrain":terrain,"terrain_set":terrain_set,"dynamic":[],"ruin_chunks":{},"ruin_occupancy":{},"extra_positions":_data.extra_positions.duplicate(),"extra_cells":_data.extra_cells.duplicate(true),"detail_rectangles":{},"collision_hard":{},"collision_vehicles":{},"collision_ruins":{},"rejected_edges":[],"edge_clear":{},"corridors":{},"endpoint_details":{}}
	_graphs[key]=entry
	return entry

func _search(job:Dictionary)->Array:
	var radius:float=job.radius
	var graph:Dictionary=_graph(radius,bool(job.get("vehicle",true)))
	var nav:AStar2D=graph.nav
	if int(graph.revision)!=int(job.revision):
		# Rejected edges belong to one collision snapshot. A demolished wall or
		# tree must be able to reopen a previously blocked connection.
		for edge:Array in graph.rejected_edges:nav.connect_points(edge[0],edge[1])
		graph.rejected_edges.clear()
		graph.edge_clear.clear()
		graph.corridors.clear()
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
		var ruins_changed: bool = false
		for raw_index in graph.ruin_chunks.keys():
			if int(raw_index)<chunks.size():continue
			ruins_changed=true
			for id in graph.ruin_chunks[raw_index].nodes:
				var remaining:int=int(graph.ruin_occupancy[id])-1
				if remaining>0:graph.ruin_occupancy[id]=remaining
				else:
					graph.ruin_occupancy.erase(id)
					if not graph.terrain_set.has(id):nav.set_point_disabled(id,false)
			graph.ruin_chunks.erase(raw_index)
		for index in range(chunks.size()):
			var chunk: Dictionary = chunks[index]
			var old: Dictionary = graph.ruin_chunks.get(index, {})
			if int(old.get("revision", -1)) == int(chunk.revision): continue
			ruins_changed = true
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
		if ruins_changed:
			var ruins: Array = []
			for chunk: Dictionary in chunks: ruins.append_array(chunk.rectangles)
			graph.collision_ruins = _collision_buckets(ruins)
		var rectangles:Array=job.geometry.hard
		if bool(graph.vehicle):rectangles=rectangles+job.geometry.vehicles
		graph.dynamic=_rectangle_nodes(nav, rectangles, radius, graph)
		for id in graph.dynamic:nav.set_point_disabled(id,true)
		graph.collision_hard=_collision_buckets(job.geometry.hard)
		graph.collision_vehicles=_collision_buckets(job.geometry.vehicles)
		graph.revision=job.revision
	# The graph supplies detour candidates; it does not constrain travel to cell
	# axes. Open terrain uses the exact requested positions in one straight leg.
	if _connector_clear(job.start,job.goal,radius,graph):return [job.goal]
	if route_cache_enabled:
		var reused:Array=_reuse_corridor(job,graph)
		if not reused.is_empty():
			_metrics.corridor_hits+=1
			return reused
	var start:int=_nearest(nav,job.start,float(job.start_height),graph,radius)
	var finish:int=_nearest(nav,job.goal,float(job.goal_height),graph,radius)
	if start<0 or finish<0:
		return _search(job) if _refine_endpoints(job,graph,radius) else []
	while true:
		_metrics.astar_searches+=1
		var nodes:PackedInt64Array=nav.get_id_path(start,finish)
		if nodes.is_empty():return _search(job) if _refine_endpoints(job,graph,radius) else []
		var candidates:Array=[]
		for id:int in nodes:candidates.append(nav.get_point_position(id))
		# Keep the exact endpoint in string pulling so it receives the same swept
		# footprint validation as every detour leg, including rounded corners.
		if (candidates.back() as Vector2)!=job.goal:candidates.append(job.goal)
		var path:Array=_smooth_path(job.start,candidates,radius,graph)
		if not path.is_empty():
			if route_cache_enabled:_remember_corridor(job,path,graph)
			return path
		# A narrow volume can intersect an edge while leaving both graph centers
		# clear. Remove those connections and let AStar find a safe alternative.
		# Each unsuccessful retry removes at least one edge, so this terminates.
		var rejected:bool=false
		for index in range(1,nodes.size()):
			var from:int=nodes[index-1]
			var to:int=nodes[index]
			var edge_key:=Vector2i(mini(from,to),maxi(from,to))
			if not graph.edge_clear.has(edge_key):
				graph.edge_clear[edge_key]=_connector_clear(nav.get_point_position(from),nav.get_point_position(to),radius,graph)
			if bool(graph.edge_clear[edge_key]):continue
			nav.disconnect_points(from,to)
			graph.rejected_edges.append([from,to])
			rejected=true
		if not rejected:return _search(job) if _refine_endpoints(job,graph,radius) else []
	return []

func _spread_group_corners(job:Dictionary,path:Array,graph:Dictionary)->Array:
	# Shared string-pulled routes used to funnel every body into one corner.
	# Give group columns separate, verified connectors inside the same passage.
	# This runs on immutable worker geometry, never on the gameplay thread.
	var answer:Array=path.duplicate()
	var phase:int=int(job.navigation_lane)
	if phase==0:return answer
	var radius:float=float(job.radius)
	var previous:Vector2=job.start
	for index in range(mini(3,answer.size()-1)):
		var point:Vector2=answer[index]
		var following:Vector2=answer[index+1]
		var tangent:Vector2=(following-previous).normalized().orthogonal()
		var distance:float=(radius*2.0+.08)*phase
		for sign_value:float in [1.0,-1.0]:
			var candidate:Vector2=point+tangent*distance*sign_value
			if _connector_clear(previous,candidate,radius,graph) and _connector_clear(candidate,following,radius,graph):
				answer[index]=candidate;break
		previous=answer[index]
	return answer

func _refine_endpoints(job:Dictionary,graph:Dictionary,radius:float)->bool:
	# A legal forest gap can have no connected whole-cell center. Refine
	# disconnected endpoints on demand rather than densifying the whole map.
	var added:bool=false
	for point:Vector2 in [job.start,job.goal]:
		var key:=Vector2i(floori(point.x*2),floori(point.y*2))
		if graph.endpoint_details.has(key):continue
		graph.endpoint_details[key]=true
		added=_detail_hard_obstacles(graph,[Rect2(point-Vector2.ONE*.01,Vector2.ONE*.02)],radius,3.0) or added
	if added:
		# Every new sample must inherit unchanged forest and building masks.
		graph.revision=-1
		for chunk:Dictionary in graph.ruin_chunks.values():chunk.revision=-1
	return added

func _corridor_key(goal:Vector2)->Vector2i:
	return Vector2i(floori(goal.x/CORRIDOR_CELL_SIZE),floori(goal.y/CORRIDOR_CELL_SIZE))

func _remember_corridor(job:Dictionary,path:Array,graph:Dictionary)->void:
	var key:Vector2i=_corridor_key(job.goal)
	if not graph.corridors.has(key):
		if graph.corridors.size()>=MAX_CORRIDOR_GOALS:graph.corridors.clear()
		graph.corridors[key]=[]
	var routes:Array=graph.corridors[key]
	var route:Array=[job.start]
	route.append_array(path)
	routes.push_front(route)
	if routes.size()>MAX_CORRIDORS_PER_GOAL:routes.pop_back()

func _reuse_corridor(job:Dictionary,graph:Dictionary)->Array:
	# Units headed into the same small destination region can enter an already
	# validated corridor from a nearby point. Interior legs retain their exact
	# radius and geometry revision; only entrance/exit connections are new.
	for route:Array in graph.corridors.get(_corridor_key(job.goal),[]):
		var segment:int=-1
		var join:=Vector2.ZERO
		var distance:float=CORRIDOR_CELL_SIZE*CORRIDOR_CELL_SIZE
		for index in range(route.size()-1):
			var point:Vector2=Geometry2D.get_closest_point_to_segment(job.start,route[index],route[index+1])
			var d:float=(job.start as Vector2).distance_squared_to(point)
			if d<distance:distance=d;segment=index;join=point
		if segment<0 or not _connector_clear(job.start,join,job.radius,graph):continue
		var answer:Array=[]
		if job.start!=join:answer.append(join)
		for index in range(segment+1,route.size()):answer.append(route[index])
		# Prefer connecting the final turn directly to the new formation spot.
		var tail:Vector2=join if answer.size()<2 else answer[answer.size()-2]
		if _connector_clear(tail,job.goal,job.radius,graph):
			if not answer.is_empty():answer.pop_back()
			answer.append(job.goal)
			return answer
		if _connector_clear(route.back(),job.goal,job.radius,graph):
			if route.back()!=job.goal:answer.append(job.goal)
			return answer
	return []

func _smooth_path(start:Vector2,points:Array,radius:float,graph:Dictionary)->Array:
	var path:Array=[]
	var position:Vector2=start
	var index:int=0
	while index<points.size():
		# Probe forward at exponentially increasing distances. Reverse scans of
		# every remaining node multiplied long cliff/bridge routes by their length.
		# Visibility need not be monotone: every chosen leg is checked, and a
		# missed shortcut only leaves additional safe waypoints.
		var chosen:int=-1
		var stride:int=1
		var failed:int=-1
		while true:
			var candidate:int=mini(points.size()-1,index+stride-1)
			_metrics.smoothing_probes+=1
			if not _connector_clear(position,points[candidate],radius,graph):
				failed=candidate
				break
			chosen=candidate
			if candidate==points.size()-1:break
			stride*=2
		if chosen<0:return []
		if failed>chosen+1:
			var low:int=chosen+1
			var high:int=failed-1
			for probe in range(4):
				if low>high:break
				var candidate:int=(low+high)/2
				_metrics.smoothing_probes+=1
				if _connector_clear(position,points[candidate],radius,graph):
					chosen=candidate
					low=candidate+1
				else:high=candidate-1
		var point:Vector2=points[chosen]
		if position!=point:path.append(point)
		position=point
		index=chosen+1
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
	if point.x<0 or point.y<0 or point.x>=size or point.y>=size:return false
	var center:int=floori(point.y)*size+floori(point.x)
	if int(_data.land[center])==0:return false
	# The immutable simulation mask excludes shorelines, ramps and height
	# changes across the surrounding 3x3 cells. Keep detailed checks elsewhere.
	if radius<=.99 and not _flat_safe.is_empty() and _flat_safe[center]!=0:return true
	if radius<=1.99 and center<_flat_wide_safe.size() and _flat_wide_safe[center]!=0:return true
	if radius==0.0:return true
	var height: float = _height_at(point)
	for offset: Vector2 in CLEARANCE_OFFSETS:
		var sample: Vector2 = point + offset*radius
		if sample.x<0 or sample.y<0 or sample.x>=size or sample.y>=size: return false
		var id: int = floori(sample.y)*size+floori(sample.x)
		if int(_data.land[id])==0 or absf(_height_at(sample)-height)>.8: return false
	return true

func _detail_id(point: Vector2) -> int:
	var size: int = int(_data.size)
	return size*size + roundi(point.y*2.0)*(size*2+1) + roundi(point.x*2.0)

func _detail_hard_obstacles(graph: Dictionary, rectangles: Array, radius: float, padding:float=1.5) -> bool:
	var nav: AStar2D = graph.nav
	var size: int = int(_data.size)
	var added: Array[int] = []
	for rect: Rect2 in rectangles:
		if graph.detail_rectangles.has(rect): continue
		graph.detail_rectangles[rect] = true
		var bounds: Rect2 = rect.grow(padding)
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

func _connector_cells(start: Vector2, finish: Vector2, radius: float) -> Array[Vector2i]:
	var cells: Array[Vector2i]=[]
	var padding: float=sqrt((radius+.02)*(radius+.02)+.00001)
	var first:=Vector2i(floori((minf(start.x,finish.x)-padding)/2.0),floori((minf(start.y,finish.y)-padding)/2.0))
	var last:=Vector2i(floori((maxf(start.x,finish.x)+padding)/2.0),floori((maxf(start.y,finish.y)+padding)/2.0))
	if (last.x-first.x+1)*(last.y-first.y+1)<=16:
		for z in range(first.y,last.y+1):
			for x in range(first.x,last.x+1):cells.append(Vector2i(x,z))
		return cells
	# Every point on the swept segment lies within .5m of one of these
	# samples. Expanding each sample by clearance+.5 conservatively covers
	# its capsule, while visiting O(length) buckets rather than the AABB area.
	var visited:Dictionary={}
	var count:int=maxi(1,ceili(start.distance_to(finish)))
	padding+=.5
	for sample in range(count+1):
		var point:Vector2=start.lerp(finish,float(sample)/count)
		first=Vector2i(floori((point.x-padding)/2.0),floori((point.y-padding)/2.0))
		last=Vector2i(floori((point.x+padding)/2.0),floori((point.y+padding)/2.0))
		for z in range(first.y,last.y+1):
			for x in range(first.x,last.x+1):
				var key:=Vector2i(x,z)
				if visited.has(key):continue
				visited[key]=true
				cells.append(key)
	return cells

func _connector_rectangles_clear(start: Vector2, finish: Vector2, radius: float, cache: Dictionary, cells: Array[Vector2i]=[]) -> bool:
	if cache.is_empty() or (cache.buckets as Dictionary).is_empty():return true
	var clearance: float=radius+.02
	var padded: float=sqrt(clearance*clearance+.00001)
	var low: Vector2=start.min(finish)-Vector2.ONE*padded
	var high: Vector2=start.max(finish)+Vector2.ONE*padded
	var bounds: Rect2=cache.bounds
	if high.x<bounds.position.x or high.y<bounds.position.y or low.x>bounds.end.x or low.y>bounds.end.y:return true
	if cells.is_empty():cells.assign(_connector_cells(start,finish,radius))
	var checked: Dictionary={}
	for key:Vector2i in cells:
		for rectangle: Rect2 in cache.buckets.get(key,[]):
			if checked.has(rectangle):continue
			checked[rectangle]=true
			if _swept_circle_rect(start,finish,clearance,rectangle):return false
	return true

func _connector_clear(start: Vector2, finish: Vector2, radius: float, graph: Dictionary) -> bool:
	_metrics.connector_checks+=1
	var cells:Array[Vector2i]=[]
	if not _connector_rectangles_clear(start,finish,radius,graph.collision_hard,cells):return false
	if bool(graph.vehicle) and not _connector_rectangles_clear(start,finish,radius,graph.collision_vehicles,cells):return false
	if not _connector_rectangles_clear(start,finish,radius,graph.collision_ruins,cells):return false
	# Continuous water/cliff boundaries prevent tiny sampled corner cuts that
	# otherwise produce a path the per-stride collision guard cannot follow.
	if not _connector_rectangles_clear(start,finish,radius-.02,_terrain_collision,cells):return false
	var distance: float=start.distance_to(finish)
	var checks: int=maxi(1,ceili(distance/.25))
	var previous_height:float=_height_at(start)
	for n in range(1,checks+1):
		var point: Vector2=start.lerp(finish,float(n)/float(checks))
		var height:float=_height_at(point)
		if not _terrain_clear(point,0.0) or absf(height-previous_height)>.8:return false
		previous_height=height
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
