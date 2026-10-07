extends SceneTree

const Worker=preload("res://scripts/path_worker.gd")
const TerrainGeometry=preload("res://scripts/path_terrain_geometry.gd")
var checks:int=0
var failures:Array[String]=[]

func _initialize()->void:
	_test_direct_routes()
	_test_obstacle_detours()
	_test_terrain_detours()
	_test_revision_updates()
	_test_invalid_endpoint_and_edge()
	_test_thin_obstacle_retries()
	_test_bucket_sweep_parity()
	_test_flat_terrain_clearance()
	_test_long_winding_detour()
	_test_forest_snapshot_replacement()
	_test_corridor_cache_hits_and_isolation()
	_test_corridor_cluster_walls_and_endpoints()
	_test_corridor_cache_disabled()
	_test_terrain_volume_output()
	_test_continuous_bridge_clearance()
	print("Any-angle worker checks: ",checks-failures.size()," passed, ",failures.size()," failed")
	for failure:String in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message)

func _worker(water:Array[int]=[],cliff:Array[int]=[],size:int=12):
	var worker=Worker.new()
	var ids:=PackedInt64Array()
	var edges:=PackedInt64Array()
	var heights:=PackedFloat32Array()
	heights.resize(size*size);heights.fill(0.0)
	var terrain:=PackedByteArray()
	terrain.resize(size*size);terrain.fill(0)
	var land:=PackedByteArray()
	land.resize(size*size);land.fill(1)
	for id:int in water:
		land[id]=0
		terrain[id]=1
	for id:int in cliff:heights[id]=2.0
	for z:int in range(size):
		for x:int in range(size):
			var id:int=z*size+x
			if land[id]==0:continue
			ids.append(id)
			if x<size-1 and land[id+1]!=0 and absf(heights[id]-heights[id+1])<=.8:edges.append_array([id,id+1])
			if z<size-1 and land[id+size]!=0 and absf(heights[id]-heights[id+size])<=.8:edges.append_array([id,id+size])
	worker._data={"size":size,"ids":ids,"edges":edges,"heights":heights,"masks":{.35:[],.95:[]},
		"extra_positions":{},"extra_cells":{},"terrain":terrain,"land":land}
	_refresh_flat_mask(worker)
	return worker

func _refresh_flat_mask(worker)->void:
	var size:int=worker._data.size
	var flat:=PackedByteArray()
	flat.resize(size*size);flat.fill(0)
	for z:int in range(1,size-1):
		for x:int in range(1,size-1):
			var good:bool=true
			var level:float=worker._data.heights[z*size+x]
			for dz:int in range(-1,2):
				for dx:int in range(-1,2):
					var id:int=(z+dz)*size+x+dx
					if int(worker._data.land[id])==0 or int(worker._data.terrain[id]) not in [0,3] or absf(float(worker._data.heights[id])-level)>.01:
						good=false
						break
				if not good:break
			if good:flat[z*size+x]=1
	worker._flat_safe=flat

func _job(start:Vector2,goal:Vector2,radius:float=.35,hard:Array=[],vehicles:Array=[],chunks:Array=[])->Dictionary:
	return {"radius":radius,"vehicle":radius>=.9,"revision":1,"start":start,"goal":goal,"start_height":0.0,"goal_height":0.0,
		"geometry":{"hard":hard,"vehicles":vehicles,"ruin_chunks":chunks}}

func _safe_route(worker,job:Dictionary,path:Array)->bool:
	if path.is_empty() or not (path.back() as Vector2).is_equal_approx(job.goal):return false
	var previous:Vector2=job.start
	for point:Vector2 in path:
		if not worker._connector_clear(previous,point,job.radius,worker._graph(job.radius,bool(job.vehicle))):return false
		previous=point
	return true

func _test_direct_routes()->void:
	var worker=_worker()
	for radius:float in [.35,.95]:
		var goal:=Vector2(10.2,8.6)
		var job:Dictionary=_job(Vector2(1.3,2.4),goal,radius)
		var path:Array=worker._search(job)
		_check(path==[goal],"clear arbitrary-angle route uses the exact goal as its only waypoint for radius "+str(radius))
		_check(_safe_route(worker,job,path),"direct route validates the complete footprint for radius "+str(radius))

func _test_obstacle_detours()->void:
	var worker=_worker()
	var obstacle:=Rect2(Vector2(4,3),Vector2(2,2))
	var start:=Vector2(1.3,2.4)
	var goal:=Vector2(10.2,8.6)
	var job:Dictionary=_job(start,goal,.95,[obstacle])
	var path:Array=worker._search(job)
	_check(path.size()>1,"a vehicle detours around a building instead of crossing its volume")
	_check(_safe_route(worker,job,path),"every building detour leg is swept with vehicle clearance")
	_check(path.size()<6,"building detour removes the long cardinal staircase")
	if not path.is_empty():
		var direction:Vector2=(path[0] as Vector2)-start
		_check(absf(direction.x)>.01 and absf(direction.y)>.01,"the first vehicle detour leg can use an arbitrary angle")
	job=_job(Vector2(1.4,1.7),Vector2(10.5,10.4),.35,[],[],[{"revision":1,"rectangles":[Rect2(Vector2(4.8,4.8),Vector2(.4,.4))]}])
	path=worker._search(job)
	_check(path.size()>1 and _safe_route(worker,job,path),"string pulling respects a small forest obstacle at a diagonal grid corner")
	var barricade:=Rect2(Vector2(4,4),Vector2(2,2))
	var infantry=_worker()
	job=_job(Vector2(1.5,1.5),Vector2(10.5,10.5),.35,[],[barricade])
	_check(infantry._search(job)==[job.goal],"infantry retains its existing ability to pass barricades")
	job.radius=.95;job.vehicle=true
	path=infantry._search(job)
	_check(path.size()>1 and _safe_route(infantry,job,path),"vehicles retain barricade collision while using arbitrary-angle detours")

func _test_terrain_detours()->void:
	var barrier:Array[int]=[]
	for z:int in range(3,12):barrier.append(z*12+5)
	var worker=_worker(barrier)
	var job:Dictionary=_job(Vector2(1.4,7.5),Vector2(10.3,8.2))
	var path:Array=worker._search(job)
	_check(path.size()>1 and _safe_route(worker,job,path),"water forces a land detour with radius clearance")
	worker=_worker([],barrier)
	path=worker._search(job)
	_check(path.size()>1 and _safe_route(worker,job,path),"an impassable height change cannot be shortcut by any-angle smoothing")

func _test_revision_updates()->void:
	var worker=_worker()
	var job:Dictionary=_job(Vector2(1.5,2.5),Vector2(10.5,8.5))
	_check(worker._search(job)==[job.goal],"an initial empty geometry snapshot has a direct route")
	job.revision=2;job.geometry.hard=[Rect2(Vector2(4,3),Vector2(2,2))]
	var path:Array=worker._search(job)
	_check(path.size()>1 and _safe_route(worker,job,path),"a new building revision blocks the old straight route")
	job.revision=3;job.geometry.hard=[]
	_check(worker._search(job)==[job.goal],"removing a building restores the direct route in the next revision")

func _test_invalid_endpoint_and_edge()->void:
	var worker=_worker()
	var obstacle:=Rect2(Vector2(4,4),Vector2(2,2))
	var job:Dictionary=_job(Vector2(1.5,1.5),Vector2(5,5),.35,[obstacle])
	_check(worker._search(job).is_empty(),"a goal inside a building is never appended without validation")
	job.start=Vector2(5,5);job.goal=Vector2(10.5,10.5)
	_check(worker._search(job).is_empty(),"a source inside a building cannot connect through its collision volume")
	job=_job(Vector2(1.5,5),Vector2(10.5,5),.35,[Rect2(Vector2(5.9,0),Vector2(.2,12))])
	job.revision=2
	_check(worker._search(job).is_empty(),"a wall covering the map width cannot yield a crossing route through unblocked graph centers")
	var graph:Dictionary=worker._graphs[Vector2(.35,0)]
	_check(worker._smooth_path(Vector2(5.5,5.5),[Vector2(6.5,5.5)],.35,graph).is_empty(),"an adjacent candidate edge across a thin wall is rejected instead of becoming an unchecked fallback")

func _test_thin_obstacle_retries()->void:
	var worker=_worker()
	var tree:=Rect2(Vector2(5.95,5.35),Vector2(.1,.3))
	var job:Dictionary=_job(Vector2(1.5,5.5),Vector2(10.5,5.5),.35,[],[],[{"revision":1,"rectangles":[tree]}])
	var path:Array=worker._search(job)
	var graph:Dictionary=worker._graphs[Vector2(.35,0)]
	_check(path.size()>1 and _safe_route(worker,job,path),"a small tree between safe graph centers triggers a usable detour")
	_check(not graph.rejected_edges.is_empty() and not graph.nav.are_points_connected(65,66),"a rejected crossing edge stays disabled within its geometry revision")
	_check(_safe_route(worker,job,worker._search(job)),"later jobs reuse the safe graph after an edge rejection")
	job.revision=2;job.geometry.ruin_chunks=[{"revision":2,"rectangles":[]}]
	_check(worker._search(job)==[job.goal],"removing a thin obstacle restores direct travel")
	_check(graph.rejected_edges.is_empty() and graph.nav.are_points_connected(65,66),"a new geometry revision reconnects rejected edges for future detours")

func _brute_rectangles_clear(worker,start:Vector2,finish:Vector2,radius:float,rectangles:Array)->bool:
	# Deliberately bypass every spatial bucket: this isolates broad-phase misses
	# while retaining the established continuous swept-volume collision oracle.
	for rectangle:Rect2 in rectangles:
		if worker._swept_circle_rect(start,finish,radius+.02,rectangle):return false
	return true

func _test_bucket_sweep_parity()->void:
	var worker=_worker()
	var segments:Array=[
		[Vector2(.001,1.999999),Vector2(87.999999,81.999999)],
		[Vector2(-8.000001,80.000001),Vector2(88.000001,-6.000001)],
		[Vector2(-8,2.000001),Vector2(88,2.000001)],
		[Vector2(1.999999,-8),Vector2(1.999999,88)],
		[Vector2(2,2),Vector2(2,2)],
		[Vector2(1.9,2.1),Vector2(2.1,1.9)]]
	for radius:float in [.35,.95,1.2]:
		for segment:Array in segments:
			var start:Vector2=segment[0]
			var finish:Vector2=segment[1]
			var direction:Vector2=(finish-start).normalized()
			var normal:Vector2=Vector2(-direction.y,direction.x) if start!=finish else Vector2.RIGHT
			var rectangles:Array=[]
			for fraction:float in [0.0,.013,.127,.503,.999,1.0]:
				for offset:float in [0.0,.7,1.0001,1.6]:
					var center:Vector2=start.lerp(finish,fraction)+normal*(radius+.02)*offset
					rectangles.append(Rect2(center-Vector2(.001,.0015),Vector2(.002,.003)))
			# Exact cell boundaries, including negative coordinates, exercise floor
			# rounding independently of the segment's uniformly spaced samples.
			for boundary:Vector2 in [Vector2(2,2),Vector2(40,40),Vector2(-2,2),Vector2(82,80)]:
				rectangles.append(Rect2(boundary-Vector2(.0001,.0001),Vector2(.0002,.0002)))
			var cells:Array[Vector2i]=worker._connector_cells(start,finish,radius)
			var seen:Dictionary={}
			for cell:Vector2i in cells:seen[cell]=true
			_check(seen.size()==cells.size(),"along-segment bucket traversal does not duplicate cells at radius "+str(radius))
			for rectangle:Rect2 in rectangles:
				var single:Array=[rectangle]
				var cache:Dictionary=worker._collision_buckets(single)
				var expected:bool=_brute_rectangles_clear(worker,start,finish,radius,single)
				_check(worker._connector_rectangles_clear(start,finish,radius,cache,cells)==expected,
					"bucket sweep matches brute capsule collision for radius "+str(radius)+", segment "+str(segment)+", rectangle "+str(rectangle))
				_check(worker._connector_rectangles_clear(start,finish,radius,cache)==expected,
					"independent bucket sweeps do not reuse a previous segment's default cells for radius "+str(radius)+", rectangle "+str(rectangle))
			var all_cache:Dictionary=worker._collision_buckets(rectangles)
			_check(worker._connector_rectangles_clear(start,finish,radius,all_cache)==_brute_rectangles_clear(worker,start,finish,radius,rectangles),
				"combined tiny obstacles preserve bucket/brute parity with internally generated cells at radius "+str(radius))

func _terrain_reference(worker,point:Vector2,radius:float)->bool:
	# Original footprint predicate without the new flat-mask shortcut.
	var size:int=worker._data.size
	var height:float=worker._height_at(point)
	for offset:Vector2 in [Vector2.ZERO,Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN,Vector2(.707,.707),Vector2(-.707,.707),Vector2(.707,-.707),Vector2(-.707,-.707)]:
		var sample:Vector2=point+offset*radius
		if sample.x<0 or sample.y<0 or sample.x>=size or sample.y>=size:return false
		var id:int=floori(sample.y)*size+floori(sample.x)
		if int(worker._data.land[id])==0 or absf(worker._height_at(sample)-height)>.8:return false
	return true

func _check_terrain_parity(worker,points:Array[Vector2],label:String)->void:
	for radius:float in [0.0,.35,.95,1.2]:
		for point:Vector2 in points:
			_check(worker._terrain_clear(point,radius)==_terrain_reference(worker,point,radius),
				label+" preserves footprint clearance at "+str(point)+", radius "+str(radius))

func _test_flat_terrain_clearance()->void:
	var worker=_worker()
	_check(worker._flat_safe[5*12+5]==1 and worker._terrain_clear(Vector2(5.3,5.7),.95),"flat field fixture exercises the safe interior mask")
	_check_terrain_parity(worker,[Vector2(.05,5.5),Vector2(1.05,1.95),Vector2(5.3,5.7),Vector2(11.95,5.5),Vector2(-.01,5.5)],"flat and map-edge mask")
	var heights:PackedFloat32Array=worker._data.heights
	for z:int in range(12):
		for x:int in range(6,12):heights[z*12+x]=2.0
	worker._data.heights=heights
	_refresh_flat_mask(worker)
	_check(worker._flat_safe[5*12+5]==0 and not worker._terrain_clear(Vector2(5.6,5.5),.95),"cliff neighbor disables the flat shortcut and preserves radius clearance")
	_check(worker._flat_safe[5*12+4]==1 and not worker._terrain_clear(Vector2(4.9,5.5),1.2),"radii above the mask's one-cell guarantee still detect a distant cliff")
	_check_terrain_parity(worker,[Vector2(4.9,5.5),Vector2(5.05,5.5),Vector2(5.95,5.5),Vector2(6.05,5.5),Vector2(7.1,5.5)],"cliff mask")

	worker=_worker()
	var terrain:PackedByteArray=worker._data.terrain
	var land:PackedByteArray=worker._data.land
	for z:int in range(12):
		for x:int in [5,6]:
			terrain[z*12+x]=1
			land[z*12+x]=1 if z in [5,6] else 0
	worker._data.terrain=terrain;worker._data.land=land
	_refresh_flat_mask(worker)
	_check(worker._flat_safe[5*12+5]==0 and worker._terrain_clear(Vector2(5.5,6),.95),"bridge land remains legal through detailed checks without marking water terrain flat")
	_check(not worker._terrain_clear(Vector2(5.5,5.1),.35),"bridge-edge clearance cannot extend into neighboring water")
	_check_terrain_parity(worker,[Vector2(4.8,6),Vector2(5.1,5.05),Vector2(5.5,6),Vector2(6.9,6),Vector2(5.5,4.95)],"bridge and shore mask")

	worker=_worker()
	heights=worker._data.heights
	terrain=worker._data.terrain
	for z:int in range(12):
		for x:int in range(12):
			heights[z*12+x]=float(clampi(z-4,0,3))*.7
			if z in [5,6]:terrain[z*12+x]=2
	worker._data.heights=heights;worker._data.terrain=terrain
	_refresh_flat_mask(worker)
	_check(worker._flat_safe[5*12+5]==0 and absf(worker._height_at(Vector2(5.5,5.9))-.98)<.00001,"ramp cells retain interpolated height and cannot use the flat mask")
	_check_terrain_parity(worker,[Vector2(5.5,4.95),Vector2(5.5,5.05),Vector2(5.5,5.9),Vector2(5.5,6.1),Vector2(5.5,6.95),Vector2(5.5,7.05)],"ramp mask")
	var graph:Dictionary=worker._graph(.35,false)
	_check(worker._connector_clear(Vector2(5.5,3.5),Vector2(5.5,8.5),.35,graph),"a valid interpolated ramp still permits continuous travel")
	heights=worker._data.heights
	for z:int in range(7,12):
		for x:int in range(12):heights[z*12+x]=3.0
	worker._data.heights=heights
	_refresh_flat_mask(worker)
	_check(not worker._connector_clear(Vector2(5.5,3.5),Vector2(5.5,8.5),0.0,graph),"radius-zero land checks retain the independent centerline height-jump rejection after a ramp")

func _test_long_winding_detour()->void:
	var water:Array[int]=[]
	for z:int in range(43):water.append(z*64+20)
	for z:int in range(20,64):water.append(z*64+42)
	var worker=_worker(water,[],64)
	var job:Dictionary=_job(Vector2(5.5,5.5),Vector2(58.5,58.5))
	var path:Array=worker._search(job)
	_check(path.size()>2 and _safe_route(worker,job,path),"long alternating shoreline barriers produce a complete safe winding route")
	var cross_first:bool=false
	var cross_second:bool=false
	var previous:Vector2=job.start
	for point:Vector2 in path:
		if previous.x<20.5 and point.x>=20.5:cross_first=true
		if previous.x<42.5 and point.x>=42.5:cross_second=true
		previous=point
	_check(cross_first and cross_second,"long route reaches both alternating barrier openings")

func _test_forest_snapshot_replacement()->void:
	var worker=_worker()
	var obstacle:=Rect2(Vector2(4,4),Vector2(2,2))
	var job:Dictionary=_job(Vector2(1.5,5.5),Vector2(10.5,5.5),.35,[],[],[{"revision":1,"rectangles":[obstacle]}])
	var path:Array=worker._search(job)
	var graph:Dictionary=worker._graphs[Vector2(.35,0)]
	_check(path.size()>1 and _safe_route(worker,job,path) and not graph.ruin_occupancy.is_empty(),"nonempty forest snapshot installs both swept collision and node occupancy")
	job.revision=2;job.geometry.ruin_chunks=[]
	_check(worker._search(job)==[job.goal],"replacing forest chunks with an empty snapshot removes the old swept collision")
	_check(graph.ruin_chunks.is_empty() and graph.ruin_occupancy.is_empty() and not graph.nav.is_point_disabled(65),"removed forest chunks release every node occupancy reference")

	# Truncating only the final chunk must preserve occupancy belonging to the
	# retained chunk, including nodes that were shared by overlapping obstacles.
	job.revision=3
	job.geometry.ruin_chunks=[{"revision":3,"rectangles":[obstacle]},{"revision":3,"rectangles":[obstacle]}]
	worker._search(job)
	job.revision=4;job.geometry.ruin_chunks=[{"revision":3,"rectangles":[obstacle]}]
	path=worker._search(job)
	_check(path.size()>1 and _safe_route(worker,job,path) and graph.ruin_chunks.size()==1,"forest chunk truncation preserves the retained obstacle's collision")
	_check(int(graph.ruin_occupancy.get(65,0))==1 and graph.nav.is_point_disabled(65),"overlapping retained forest occupancy stays disabled with one remaining reference")

func _corridor_fixture()->Dictionary:
	var worker=_worker([],[],32)
	var obstacle:=Rect2(Vector2(12,8),Vector2(4,12))
	var job:Dictionary=_job(Vector2(4.5,14.5),Vector2(27.5,14.5),.35,[obstacle])
	return {"worker":worker,"job":job}

func _route_avoids_rectangles(worker,job:Dictionary,path:Array)->bool:
	if path.is_empty() or not (path.back() as Vector2).is_equal_approx(job.goal):return false
	var rectangles:Array=job.geometry.hard.duplicate()
	if float(job.radius)>.5:rectangles.append_array(job.geometry.vehicles)
	for chunk:Dictionary in job.geometry.ruin_chunks:rectangles.append_array(chunk.rectangles)
	var previous:Vector2=job.start
	for point:Vector2 in path:
		if not _brute_rectangles_clear(worker,previous,point,job.radius,rectangles):return false
		previous=point
	return true

func _test_corridor_cache_hits_and_isolation()->void:
	var fixture:Dictionary=_corridor_fixture()
	var worker=fixture.worker
	var base:Dictionary=fixture.job
	var initial:Array=worker._search(base)
	var graph:Dictionary=worker._graphs[Vector2(.35,0)]
	_check(initial.size()>1 and _safe_route(worker,base,initial),"corridor fixture first plans a real obstacle detour")
	_check(not graph.corridors.get(worker._corridor_key(base.goal),[]).is_empty() and int(worker._metrics.astar_searches)>0,"a completed detour populates the destination corridor cache")
	var follow:Dictionary=base.duplicate(true)
	follow.start=Vector2(4.8,14.8);follow.goal=Vector2(27.2,15.1)
	var before_searches:int=worker._metrics.astar_searches
	var before_hits:int=worker._metrics.corridor_hits
	var reused:Array=worker._search(follow)
	_check(int(worker._metrics.corridor_hits)==before_hits+1 and int(worker._metrics.astar_searches)==before_searches,"nearby units with the same destination cluster reuse a corridor without another AStar search")
	_check(_safe_route(worker,follow,reused) and _route_avoids_rectangles(worker,follow,reused),"reused corridor validates every actual leg including its new entrance and exact new exit")
	_check(not reused.is_empty() and (reused[0] as Vector2).distance_to(follow.start)>.00001 and (reused.back() as Vector2).is_equal_approx(follow.goal),"corridor reuse retains the projected entrance and the newly requested endpoint")

	follow.radius=.95;follow.vehicle=true
	before_searches=worker._metrics.astar_searches;before_hits=worker._metrics.corridor_hits
	var vehicle:Array=worker._search(follow)
	_check(int(worker._metrics.corridor_hits)==before_hits and int(worker._metrics.astar_searches)>before_searches,"vehicle radius cannot reuse a cached infantry corridor")
	_check(_safe_route(worker,follow,vehicle) and _route_avoids_rectangles(worker,follow,vehicle),"separate vehicle corridor preserves its larger swept footprint")
	_check(worker._graphs.has(Vector2(.35,0)) and worker._graphs.has(Vector2(.95,1)) and not worker._graphs[Vector2(.95,1)].corridors.is_empty(),"different radii maintain their own populated corridor graphs")

	# The new wall cuts a cached interior leg. A revision change must prevent
	# reusing that leg even though its old entrance and exit are still clear.
	follow.radius=.35;follow.vehicle=false;follow.revision=2
	follow.geometry.hard.append(Rect2(Vector2(10,0),Vector2(.8,32)))
	before_hits=worker._metrics.corridor_hits
	var blocked:Array=worker._search(follow)
	_check(blocked.is_empty() and int(worker._metrics.corridor_hits)==before_hits,"new static geometry cannot reuse a corridor across an added full-height wall")
	_check(graph.corridors.is_empty() and int(graph.revision)==2,"static revision changes remove all old destination corridors before searching")

func _test_corridor_cluster_walls_and_endpoints()->void:
	var fixture:Dictionary=_corridor_fixture()
	var worker=fixture.worker
	var base:Dictionary=fixture.job
	base.goal=Vector2(25.5,13.5)
	base.geometry.hard.append(Rect2(Vector2(27,0),Vector2(.5,32)))
	var initial:Array=worker._search(base)
	_check(initial.size()>1 and _safe_route(worker,base,initial),"same-cluster wall fixture caches a valid route on the wall's near side")
	var beyond:Dictionary=base.duplicate(true)
	beyond.goal=Vector2(29.5,13.5)
	_check(worker._corridor_key(base.goal)==worker._corridor_key(beyond.goal),"opposite sides of the full-height wall belong to the same eight-meter destination cluster")
	var before_hits:int=worker._metrics.corridor_hits
	_check(worker._search(beyond).is_empty() and int(worker._metrics.corridor_hits)==before_hits,"a cached corridor cannot connect its final turn or its old endpoint through a same-cluster wall")

	var bad_goal:Dictionary=base.duplicate(true)
	bad_goal.goal=Vector2(27.25,13.5)
	_check(worker._search(bad_goal).is_empty() and int(worker._metrics.corridor_hits)==before_hits,"the exact new endpoint inside a wall is rejected before corridor reuse returns a path")
	var bad_start:Dictionary=base.duplicate(true)
	bad_start.start=Vector2(14,14)
	_check(worker._search(bad_start).is_empty() and int(worker._metrics.corridor_hits)==before_hits,"the first entrance from inside a building cannot join a nearby cached corridor")
	var other_side:Dictionary=base.duplicate(true)
	other_side.start=Vector2(29.5,13.5)
	_check(worker._search(other_side).is_empty() and int(worker._metrics.corridor_hits)==before_hits,"a nearby entrance projection across a full-height wall cannot reuse the cached route")

func _test_corridor_cache_disabled()->void:
	var fixture:Dictionary=_corridor_fixture()
	var worker=fixture.worker
	var job:Dictionary=fixture.job
	worker.route_cache_enabled=false
	var initial:Array=worker._search(job)
	_check(_safe_route(worker,job,initial) and worker._graphs[Vector2(.35,0)].corridors.is_empty(),"disabling corridor caching still plans a safe detour without storing it")
	var before_searches:int=worker._metrics.astar_searches
	var follow:Dictionary=job.duplicate(true)
	follow.start=Vector2(4.8,14.8);follow.goal=Vector2(27.2,15.1)
	var fresh:Array=worker._search(follow)
	_check(_safe_route(worker,follow,fresh) and int(worker._metrics.corridor_hits)==0 and int(worker._metrics.astar_searches)>before_searches,"disabled caching performs a new AStar search for a nearby repeated order")

	worker.route_cache_enabled=true
	worker._search(job)
	_check(not worker._graphs[Vector2(.35,0)].corridors.is_empty(),"enabling cache on the same worker populates a real corridor")
	worker.route_cache_enabled=false
	before_searches=worker._metrics.astar_searches
	var before_hits:int=worker._metrics.corridor_hits
	fresh=worker._search(follow)
	_check(_safe_route(worker,follow,fresh) and int(worker._metrics.corridor_hits)==before_hits and int(worker._metrics.astar_searches)>before_searches,"disabling cache also bypasses corridors that were populated earlier")

func _water_cells_as_rectangles(worker)->Array[Rect2]:
	var rectangles:Array[Rect2]=[]
	var size:int=worker._data.size
	for z:int in range(size):
		for x:int in range(size):
			if int(worker._data.land[z*size+x])==0:rectangles.append(Rect2(Vector2(x,z),Vector2.ONE))
	return rectangles

func _test_terrain_volume_output()->void:
	var water:Array[int]=[]
	for z:int in range(1,4):
		for x:int in range(2,5):water.append(z*8+x)
	for z:int in range(5,7):
		for x:int in range(1,3):water.append(z*8+x)
	var worker=_worker(water,[],8)
	var rectangles:Array[Rect2]=TerrainGeometry.build(worker._data)
	_check(rectangles.size()==2 and rectangles.has(Rect2(Vector2(2,1),Vector2(3,3))) and rectangles.has(Rect2(Vector2(1,5),Vector2(2,2))),"equal consecutive water runs merge into exact larger terrain rectangles")
	for z:int in range(8):
		for x:int in range(8):
			var covered:bool=false
			for rectangle:Rect2 in rectangles:
				if rectangle.has_point(Vector2(x+.5,z+.5)):covered=true
			_check(covered==(int(worker._data.land[z*8+x])==0),"merged water volumes cover exactly the nonland cells at "+str(Vector2i(x,z)))
	var cells:Array[Rect2]=_water_cells_as_rectangles(worker)
	for radius:float in [.35,.95,1.2]:
		for segment:Array in [[Vector2(.6,.6),Vector2(7.4,7.4)],[Vector2(.6,7.4),Vector2(7.4,.6)],[Vector2(.6,4.5),Vector2(7.4,4.5)]]:
			var start:Vector2=segment[0]
			var finish:Vector2=segment[1]
			_check(_brute_rectangles_clear(worker,start,finish,radius-.02,rectangles)==_brute_rectangles_clear(worker,start,finish,radius-.02,cells),"merging water preserves continuous capsule collision for radius "+str(radius))

	worker=_worker([],[],8)
	var heights:PackedFloat32Array=worker._data.heights
	for z:int in range(8):
		for x:int in range(4,8):heights[z*8+x]=2.0
	worker._data.heights=heights
	rectangles=TerrainGeometry.build(worker._data)
	_check(rectangles==[Rect2(Vector2(4,0),Vector2(0,8))],"vertical land-to-land cliff edges merge into one zero-width boundary")
	var cache:Dictionary=worker._collision_buckets(rectangles)
	_check(not worker._connector_rectangles_clear(Vector2(2.5,3.5),Vector2(5.5,3.5),.35-.02,cache),"continuous terrain collision rejects a line crossing a zero-width cliff")
	_check(not worker._connector_rectangles_clear(Vector2(3.75,1.5),Vector2(3.75,6.5),.35-.02,cache),"a footprint cannot run parallel while overlapping the adjacent cliff face")
	_check(worker._connector_rectangles_clear(Vector2(3.6,1.5),Vector2(3.6,6.5),.35-.02,cache),"a footprint with real cliff clearance remains traversable")
	var land:PackedByteArray=worker._data.land
	land[3*8+3]=0;worker._data.land=land
	rectangles=TerrainGeometry.build(worker._data)
	_check(rectangles.size()==3 and rectangles.has(Rect2(Vector2(3,3),Vector2.ONE)) and rectangles.has(Rect2(Vector2(4,0),Vector2(0,3))) and rectangles.has(Rect2(Vector2(4,4),Vector2(0,4))),"a water gap splits a cliff run and keeps its own solid water footprint")

	worker=_worker([],[],8)
	heights=worker._data.heights
	for z:int in range(4,8):
		for x:int in range(8):heights[z*8+x]=2.0
	worker._data.heights=heights
	rectangles=TerrainGeometry.build(worker._data)
	_check(rectangles==[Rect2(Vector2(0,4),Vector2(8,0))],"horizontal land-to-land cliff edges merge into one zero-height boundary")
	cache=worker._collision_buckets(rectangles)
	_check(not worker._connector_rectangles_clear(Vector2(3.5,2.5),Vector2(3.5,5.5),.35-.02,cache),"continuous terrain collision also rejects zero-height cliff crossings")

	worker=_worker([],[],8)
	heights=worker._data.heights
	var terrain:PackedByteArray=worker._data.terrain
	for z:int in range(8):
		for x:int in range(8):
			heights[z*8+x]=float(z)*.7
			terrain[z*8+x]=2
	worker._data.heights=heights;worker._data.terrain=terrain
	_check(TerrainGeometry.build(worker._data).is_empty(),"legal ramp height increments do not become artificial cliff boundaries")

func _sampled_footprints_clear(worker,start:Vector2,finish:Vector2,radius:float)->bool:
	var count:int=maxi(1,ceili(start.distance_to(finish)/.4))
	for index:int in range(count+1):
		if not _terrain_reference(worker,start.lerp(finish,float(index)/count),radius):return false
	return true

func _test_continuous_bridge_clearance()->void:
	var water:Array[int]=[]
	for z:int in range(12):
		if z in [5,6]:continue
		for x:int in [5,6]:water.append(z*12+x)
	var worker=_worker(water)
	var terrain:PackedByteArray=worker._data.terrain
	for z:int in [5,6]:
		for x:int in [5,6]:terrain[z*12+x]=1
	worker._data.terrain=terrain
	var rectangles:Array[Rect2]=TerrainGeometry.build(worker._data)
	_check(rectangles.size()==2 and rectangles.has(Rect2(Vector2(5,0),Vector2(2,5))) and rectangles.has(Rect2(Vector2(5,7),Vector2(2,5))),"bridge land interrupts otherwise merged river collision volumes")
	var cache:Dictionary=worker._collision_buckets(rectangles)
	_check(worker._connector_rectangles_clear(Vector2(2,6),Vector2(10,6),.95-.02,cache),"the exact footprint leaves a legal two-meter bridge open for radius-.95 vehicles")
	_check(worker._connector_rectangles_clear(Vector2(4.64,7.2),Vector2(4.64,10.8),.35-.02,cache),"terrain collision uses the physical radius without adding the building clearance margin")
	_check(not worker._connector_rectangles_clear(Vector2(4.66,7.2),Vector2(4.66,10.8),.35-.02,cache),"parallel river-edge travel is rejected when its circle actually overlaps water")

	# This legal-endpoint diagonal clips the water corner between the old .4m
	# footprint samples. Continuous capsule collision must reject that missed leg.
	var direction:Vector2=Vector2(1,-1).normalized()
	var closest:Vector2=Vector2(5,7)-Vector2.ONE*(.349/sqrt(2.0))
	var start:Vector2=closest-direction*1.11
	var finish:Vector2=closest+direction*.89
	_check(_terrain_reference(worker,start,.35) and _terrain_reference(worker,finish,.35),"water-corner regression starts and ends at individually legal bridge/bank positions")
	_check(_sampled_footprints_clear(worker,start,finish,.35),"the bridge-corner regression reproduces a leg missed by the original spaced footprint checks")
	_check(not _brute_rectangles_clear(worker,start,finish,.35-.02,rectangles) and not worker._connector_rectangles_clear(start,finish,.35-.02,cache),"continuous terrain capsules reject the water-corner overlap between sampled standing positions")
	var units:Array[Rect2]=_water_cells_as_rectangles(worker)
	for radius:float in [.35,.95,1.2]:
		for segment:Array in [[start,finish],[Vector2(2,6),Vector2(10,6)],[Vector2(2,5.3),Vector2(10,6.7)]]:
			_check(worker._connector_rectangles_clear(segment[0],segment[1],radius-.02,cache)==_brute_rectangles_clear(worker,segment[0],segment[1],radius-.02,units),"merged river buckets agree with individual water-cell capsule checks at radius "+str(radius))
