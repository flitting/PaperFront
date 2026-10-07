extends RefCounted
## Full-circle amphibious hulls share one land/sea grid. No shore teleport occurs.
const NAVAL = preload("res://scripts/naval_operations.gd")

static func amphibious(sim, unit: Dictionary) -> bool:
	return bool(sim.data_for(unit.spec).get("amphibious", false))

static func point_clear(sim, point: Vector2, radius: float, ignore: int = -1, dynamic: bool = true) -> bool:
	if not point.is_finite() or point.x-radius < 0 or point.y-radius < 0 or point.x+radius >= sim.map.size or point.y+radius >= sim.map.size: return false
	var touched: Dictionary = {}
	for z in range(floori(point.y-radius), floori(point.y+radius)+1):
		for x in range(floori(point.x-radius), floori(point.x+radius)+1):
			var near: Vector2 = point.clamp(Vector2(x,z),Vector2(x+1,z+1))
			if point.distance_squared_to(near) >= radius*radius: continue
			var cell := Vector2(x+.5,z+.5)
			var terrain: int = sim._terrain(cell)
			if terrain not in [0,1,2,3]: return false
			var height: float = MapData.entity_surface_y(sim.map,cell,"naval" if terrain==1 else "ground")
			touched[Vector2i(x,z)] = height
	for cell: Vector2i in touched:
		for offset: Vector2i in [Vector2i.RIGHT,Vector2i.DOWN]:
			if touched.has(cell+offset) and absf(float(touched[cell])-float(touched[cell+offset]))>1.3: return false
	if not sim._building_clear(point,radius,ignore): return false
	if dynamic:
		for other: Dictionary in sim.entities.values():
			if int(other.id)==ignore or other.kind!="unit" or sim._is_air(other) or float(other.hp)<=0 or int(other.get("transport_id",-1))>0: continue
			if point.distance_squared_to(other.pos)<pow(radius+sim._radius(other)+.03,2): return false
	return true

static func segment_clear(sim,a:Vector2,b:Vector2,radius:float,ignore:int=-1,dynamic:bool=false)->bool:
	var samples: int=maxi(1,ceili(a.distance_to(b)/.08))
	var previous: float=MapData.entity_surface_y(sim.map,a,"naval" if sim._terrain(a)==1 else "ground")
	for n in range(samples+1):
		var point:Vector2=a.lerp(b,float(n)/samples)
		if not point_clear(sim,point,radius,ignore,dynamic): return false
		var height:float=MapData.entity_surface_y(sim.map,point,"naval" if sim._terrain(point)==1 else "ground")
		if absf(height-previous)>1.3:return false
		previous=height
	return true

static func _grid(sim, radius: float, region: Rect2i) -> AStarGrid2D:
	var nav = NAVAL._nav(sim)
	var key: String="amphib_grid_%d_%d_%d_%d_%d"%[roundi(radius*100.0),region.position.x,region.position.y,region.size.x,region.size.y]
	var cache: Dictionary=nav.get_meta(key,{})
	var revision: String="%d:%s"%[int(sim._static_geometry_revision),nav._bridge_key()]
	if not cache.is_empty() and cache.revision==revision:return cache.grid
	var grid:=AStarGrid2D.new()
	grid.region=region
	grid.cell_size=Vector2.ONE
	grid.offset=Vector2(.5,.5)
	grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for z in range(region.position.y,region.end.y):
		for x in range(region.position.x,region.end.x):
			grid.set_point_solid(Vector2i(x,z),not point_clear(sim,Vector2(x+.5,z+.5),radius,-1,false))
	var cached_keys:Array=nav.get_meta("amphib_grid_keys",[])
	if key not in cached_keys:cached_keys.append(key)
	while cached_keys.size()>8:nav.remove_meta(str(cached_keys.pop_front()))
	nav.set_meta("amphib_grid_keys",cached_keys)
	nav.set_meta(key,{"revision":revision,"grid":grid})
	return grid

static func _near(sim, point:Vector2,radius:float,ignore:int)->Vector2:
	if point_clear(sim,point,radius,ignore,false):return point
	for ring in range(1,13):
		for n in range(ring*12):
			var candidate:Vector2=point+Vector2.from_angle(TAU*float(n)/(ring*12))*(ring*.5)
			if point_clear(sim,candidate,radius,ignore,false):return candidate
	return Vector2.INF

static func _anchor(sim,grid:AStarGrid2D,point:Vector2,radius:float,ignore:int)->Vector2i:
	var center:=Vector2i(floori(point.x),floori(point.y))
	for ring in range(5):
		var best:=Vector2i(-1,-1)
		var distance:float=INF
		for z in range(center.y-ring,center.y+ring+1):
			for x in range(center.x-ring,center.x+ring+1):
				var cell:=Vector2i(x,z)
				if not grid.is_in_boundsv(cell) or grid.is_point_solid(cell):continue
				var candidate:=Vector2(cell)+Vector2(.5,.5)
				var gap:float=point.distance_squared_to(candidate)
				if gap<distance and segment_clear(sim,point,candidate,radius,ignore):best=cell;distance=gap
		if best.x>=0:return best
	return Vector2i(-1,-1)

static func path(sim,start:Vector2,goal:Vector2,radius:float,ignore:int)->Array[Vector2]:
	var result:Array[Vector2]=[]
	if segment_clear(sim,start,goal,radius,ignore):return [goal]
	var map_rect:=Rect2i(0,0,int(sim.map.size),int(sim.map.size))
	var corner:Vector2=start.min(goal)-Vector2.ONE*12
	var extent:Vector2=start.max(goal)-corner+Vector2.ONE*12
	var local:=Rect2i(Vector2i(corner),Vector2i(extent)+Vector2i.ONE).intersection(map_rect)
	var grid:AStarGrid2D=_grid(sim,radius,local)
	var first:Vector2i=_anchor(sim,grid,start,radius,ignore)
	var last:Vector2i=_anchor(sim,grid,goal,radius,ignore)
	if first.x<0 or last.x<0:return result
	var cells:Array[Vector2i]=grid.get_id_path(first,last)
	if cells.is_empty() and local!=map_rect:
		grid=_grid(sim,radius,map_rect)
		cells=grid.get_id_path(first,last)
	if cells.is_empty():return result
	var previous:Vector2=start
	for cell:Vector2i in cells:
		var point:Vector2=Vector2(cell)+Vector2(.5,.5)
		if point.distance_to(previous)<.1:continue
		if not segment_clear(sim,previous,point,radius,ignore):return []
		result.append(point)
		previous=point
	if segment_clear(sim,previous,goal,radius,ignore):result.append(goal)
	return result

static func move_to(sim,e:Dictionary,requested:Vector2,delta:float)->bool:
	var radius:float=sim._radius(e)
	var goal:Vector2=_near(sim,requested,radius,int(e.id))
	if not goal.is_finite():e.state="unreachable";return false
	if (e.pos as Vector2).distance_to(goal)<.2:e.motion=0.0;return true
	var route:Array=e.get("amphib_path",[])
	if route.is_empty() or (e.get("amphib_goal",Vector2.INF) as Vector2)!=goal or float(e.get("amphib_repath",0.0))<=sim.time:
		route=path(sim,e.pos,goal,radius,int(e.id))
		e.amphib_path=route
		e.amphib_goal=goal
		e.amphib_repath=sim.time+3.0
	if route.is_empty():e.state="unreachable";return false
	while route.size()>1 and (e.pos as Vector2).distance_to(route[0])<.18:route.pop_front()
	var waypoint:Vector2=route[0]
	if route.size()>1 and segment_clear(sim,e.pos,route[1],radius,int(e.id)):route.pop_front();waypoint=route[0]
	var offset:Vector2=waypoint-e.pos
	sim._turn(e,rad_to_deg(offset.angle()),delta)
	var stride:float=float(sim.data_for(e.spec).speed)*delta
	var next:Vector2=(e.pos as Vector2).move_toward(waypoint,stride)
	if not segment_clear(sim,e.pos,next,radius,int(e.id),true):e.state="waiting";e.motion=0.0;return false
	var old:Vector2=e.pos
	var crossing:bool=(sim._terrain(old)==MapData.WATER)!=(sim._terrain(next)==MapData.WATER)
	if crossing:sim._spatial_remove(int(e.id),old)
	e.pos=next
	e.surface_domain="naval" if sim._terrain(next)==MapData.WATER else "ground"
	e.motion=old.distance_to(next)/maxf(delta,.001)
	e.state="move"
	if crossing:sim._spatial_add(int(e.id),next)
	else:sim._spatial_move(e,old,next)
	return next.distance_to(goal)<.2
