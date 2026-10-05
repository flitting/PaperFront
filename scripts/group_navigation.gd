extends RefCounted
class_name GroupNavigation

# Shared static A* route + narrow-passage reservations. Units are traffic,
# never permanent obstacles in the strategic graph. Derived state is rebuilt
# from command formation IDs on load or when the static topology changes.
var groups: Dictionary = {}
var gates: Array[Dictionary] = []
var plans: int = 0
var grants: int = 0
var waits: int = 0
const BATCH := 8

func clear() -> void:
	groups.clear()
	gates.clear()

func begin_tick(sim) -> void:
	var active: Dictionary={}
	for e in sim.entities.values():
		if not e.commands.is_empty() and e.commands[0].has("formation"):active[int(e.commands[0].formation)]=true
	for gid in groups.keys():
		if not active.has(gid):groups.erase(gid)
	for gate in gates:
		for gid in gate.queues.keys():
			gate.queues[gid] = (gate.queues[gid] as Array).filter(func(id):return _active(sim,id,int(gid)))
			if gate.queues[gid].is_empty():gate.queues.erase(gid)
		gate.owners = (gate.owners as Array).filter(func(id):return _active(sim,id,int(gate.active)) or (sim.entities.has(id) and gate.bounds.grow(sim._radius(sim.entities[id])+.1).has_point(sim.entities[id].pos)))
		if int(gate.active)>=0 and gate.owners.is_empty() and (not gate.queues.has(gate.active) or int(gate.batch)>=BATCH):
			gate.last_group=gate.active
			gate.active=-1
			gate.batch=0

func _active(sim, id: int, gid: int) -> bool:
	return sim.entities.has(id) and not sim.entities[id].commands.is_empty() and int(sim.entities[id].commands[0].get("formation",-1))==gid

func _point(route: Array, distance: float) -> Vector2:
	for i in range(1,route.size()):
		var length: float=route[i-1].distance_to(route[i])
		if distance<=length:return (route[i-1] as Vector2).lerp(route[i],maxf(0,distance)/maxf(length,.001))
		distance-=length
	return route.back()

func _length(route: Array) -> float:
	var result: float=0
	for i in range(1,route.size()):result+=route[i-1].distance_to(route[i])
	return result

func _narrow(sim, point: Vector2, direction: Vector2, radius: float) -> bool:
	if not sim._standing(point,radius,-1,false):return false
	var width: float=0
	for sign_value in [-1.0,1.0]:
		for i in range(1,13):
			var test: Vector2=point+direction.orthogonal()*sign_value*i*.25
			if not sim._segment_static(point,test,radius,-1):break
			width+=.25
	return width<radius*2+.25

func _register_portal(sim, group: Dictionary, route: Array, start: float, finish: float) -> void:
	var middle: float=(start+finish)*.5
	var center: Vector2=_point(route,middle).snapped(Vector2(.5,.5))
	var direction: Vector2=(_point(route,middle+.4)-_point(route,maxf(0,middle-.4))).normalized()
	if absf(direction.x)>absf(direction.y)*1.5:direction=Vector2(signf(direction.x),0)
	elif absf(direction.y)>absf(direction.x)*1.5:direction=Vector2(0,signf(direction.y))
	if direction.length_squared()<.5:return
	if not sim._standing(center,float(group.radius),-1,false):center=_point(route,middle)
	var a: Vector2=center
	var b: Vector2=center
	for i in range(1,65):
		var p: Vector2=center-direction*i*.25
		if not _narrow(sim,p,direction,float(group.radius)):break
		a=p
	for i in range(1,65):
		var p: Vector2=center+direction*i*.25
		if not _narrow(sim,p,direction,float(group.radius)):break
		b=p
	var entry: Vector2=a-direction*(float(group.radius)*2+.8)
	var exit: Vector2=b+direction*(float(group.radius)*2+.8)
	if not sim._segment_static(entry,exit,float(group.radius),-1):
		entry=_point(route,maxf(0,start-float(group.radius)*2-.8))
		exit=_point(route,finish+float(group.radius)*2+.8)
		direction=(exit-entry).normalized()
	var bounds:=Rect2(a,Vector2.ZERO).expand(b).grow(float(group.radius)+.4)
	var gate_id: int=-1
	for i in range(gates.size()):
		if gates[i].bounds.intersects(bounds):gate_id=i;break
	if gate_id<0:
		gate_id=gates.size()
		var incumbents: Array=[]
		for entity in sim.entities.values():
			if entity.kind=="unit" and not sim._is_air(entity) and bounds.has_point(entity.pos) and _narrow(sim,entity.pos,direction,float(group.radius)):incumbents.append(int(entity.id))
		incumbents.sort_custom(func(x,y):return (sim.entities[x].pos-entry).dot(direction)>(sim.entities[y].pos-entry).dot(direction))
		gates.append({"bounds":bounds,"queues":{},"owners":incumbents,"active":int(group.id) if not incumbents.is_empty() else -1,"last_group":-1,"batch":0,"entries":{},"spacing":float(group.radius)*2+.3})
	var gate: Dictionary=gates[gate_id]
	var spacing: float=float(gate.spacing)
	var reserved: Array[Vector2]=[]
	for id in group.members:
		var order: Dictionary=sim.entities[id].commands[0]
		if (order.pos-exit).dot(direction)>=spacing:reserved.append(order.pos)
	for id in group.members:
		var member: Dictionary=sim.entities[id]
		var order: Dictionary=member.commands[0]
		if (order.pos-exit).dot(direction)>=spacing:continue
		var found: bool=false
		for ring in range(1,21):
			for angle in range(24):
				var point: Vector2=order.pos+direction.rotated(angle*TAU/24.0)*spacing*ring
				if (point-exit).dot(direction)<spacing or not sim._in_bounds(point):continue
				var occupied: bool=false
				for slot in reserved:
					if slot.distance_to(point)<spacing-.01:occupied=true;break
				if not occupied and sim._standing(point,sim._radius(member),int(member.id),false):
					order.pos=point;reserved.append(point);found=true;break
			if found:break
	var pending: Array=[]
	for id in group.members:
		if (sim.entities[id].pos-exit).dot(direction)<-.2:pending.append(id)
	pending.sort_custom(func(x,y):
		var x_owned: bool=gate.owners.has(x)
		var y_owned: bool=gate.owners.has(y)
		if x_owned!=y_owned:return x_owned
		if x_owned:return (sim.entities[x].pos-entry).dot(direction)>(sim.entities[y].pos-entry).dot(direction)
		var da: float=sim.entities[x].pos.distance_squared_to(entry)
		var db: float=sim.entities[y].pos.distance_squared_to(entry)
		return da<db if not is_equal_approx(da,db) else int(x)<int(y))
	gate.queues[group.id]=pending
	gate.entries[group.id]=entry
	var departed: Dictionary={}
	for id in group.members:
		if not pending.has(id):departed[id]=true
	group.portals.append({"gate":gate_id,"entry":entry,"exit":exit,"direction":direction,"departed":departed})

func _plan(sim, e: Dictionary, command: Dictionary) -> bool:
	var gid: int=int(command.formation)
	var members: Array=[]
	var radius: float=.35
	var anchor: Vector2=e.pos
	var distance: float=-1
	var goal: Vector2=command.get("formation_goal",command.pos)
	for other in sim.entities.values():
		if other.kind!="unit" or not _active(sim,int(other.id),gid):continue
		members.append(int(other.id))
		radius=maxf(radius,sim._radius(other))
		if other.pos.distance_squared_to(goal)>distance:
			distance=other.pos.distance_squared_to(goal);anchor=other.pos
	anchor=sim._near_stand(anchor,radius,-1,6.0,false)
	goal=sim._near_stand(goal,radius,-1,10.0,false)
	if not goal.is_finite() or not anchor.is_finite():
		groups[gid]={"id":gid,"members":members,"portals":[],"radius":radius};return true
	var path: Array=sim._path_between(anchor,goal,radius,int(e.id))
	if sim._plan_was_deferred:return false
	plans+=1
	var group: Dictionary={"id":gid,"members":members,"portals":[],"radius":radius}
	groups[gid]=group
	if path.is_empty():return true
	var route: Array=[anchor]
	route.append_array(path)
	var length: float=_length(route)
	var run: float=-1
	for i in range(ceili(length/.5)+1):
		var d: float=minf(i*.5,length)
		var point: Vector2=_point(route,d)
		var direction: Vector2=(_point(route,minf(length,d+.4))-_point(route,maxf(0,d-.4))).normalized()
		var narrow: bool=_narrow(sim,point,direction,radius)
		if narrow and run<0:run=d
		if (not narrow or d>=length) and run>=0:
			if d-run>=.5:_register_portal(sim,group,route,run,d)
			run=-1
	if members.size()==1 and group.portals.is_empty() and goal.distance_to(command.pos)<.05:
		e.path=path.duplicate()
		e.path_goal=goal
		e.path_wait=0.0
	return true

func _choose_group(sim, gate: Dictionary) -> int:
	var chosen: int=-1
	var nearest: float=INF
	for gid in gate.queues:
		var queue: Array=gate.queues[gid]
		if queue.is_empty():continue
		var distance: float=sim.entities[queue[0]].pos.distance_to(gate.entries[gid])
		if distance>float(gate.spacing)*2.5:continue
		var score: float=distance+(100 if int(gid)==int(gate.last_group) and gate.queues.size()>1 else 0)
		if score<nearest:chosen=int(gid);nearest=score
	return chosen

func _queue_point(sim, e: Dictionary, portal: Dictionary, rank: int, spacing: float) -> Vector2:
	var row: int=rank+1
	var column: int=0
	if rank>=3:
		row=4+(rank-3)/3
		column=[0,1,2][(rank-3)%3]
	var target: Vector2=portal.entry-portal.direction*spacing*row+portal.direction.orthogonal()*spacing*column
	if sim._standing(target,sim._radius(e),int(e.id),false) and sim._segment_static(target,portal.entry,sim._radius(e),int(e.id)):return target
	# Keep staging on this side of the portal, including around nearby buildings.
	for back in range(row, row+8):
		for side in [0,-1,1,-2,2,-3,3]:
			var p: Vector2=portal.entry-portal.direction*spacing*back+portal.direction.orthogonal()*spacing*side
			if sim._standing(p,sim._radius(e),int(e.id),false) and sim._segment_static(p,portal.entry,sim._radius(e),int(e.id)):return p
	return e.pos

func directive(sim, e: Dictionary, command: Dictionary) -> Dictionary:
	if not command.has("formation"):return {}
	var gid: int=int(command.formation)
	if not groups.has(gid) and not _plan(sim,e,command):return {"wait":true}
	var group: Dictionary=groups[gid]
	for portal in group.portals:
		var gate: Dictionary=gates[int(portal.gate)]
		var id: int=int(e.id)
		if (e.pos-portal.exit).dot(portal.direction)>=-.45:
			gate.owners.erase(id)
			if gate.queues.has(gid):gate.queues[gid].erase(id)
			if not portal.departed.has(id):
				var along: float=(e.pos-portal.exit).dot(portal.direction)
				var sideways: float=absf((e.pos-portal.exit).dot((portal.direction as Vector2).orthogonal()))
				if along>float(gate.spacing)*1.5 or sideways>float(gate.spacing)*1.5:portal.departed[id]=true
			if not portal.departed.has(id):
				var egress: Vector2=portal.exit+(portal.direction as Vector2).orthogonal()*float(gate.spacing)*2.2
				if e.pos.distance_to(egress)>.4 and sim._standing(egress,sim._radius(e),id,false):
					return {"goal":egress,"strict":false,"gate":int(portal.gate),"rank":-2,"owner":false}
				portal.departed[id]=true
			continue
		if portal.departed.has(id) and (e.pos-portal.entry).dot(portal.direction)<-float(gate.spacing):
			portal.departed.erase(id)
			if not gate.queues.has(gid):gate.queues[gid]=[]
			if not gate.queues[gid].has(id):gate.queues[gid].append(id)
		if not gate.queues.has(gid) or not gate.queues[gid].has(id):continue
		var rank: int=gate.queues[gid].find(id)
		if not gate.owners.has(id):
			if int(gate.active)<0:gate.active=_choose_group(sim,gate)
			var can_enter: bool=int(gate.active)==gid and rank==gate.owners.size() and (int(gate.batch)<BATCH or gate.queues.size()==1)
			if can_enter and not gate.owners.is_empty():
				var tail: Dictionary=sim.entities[gate.owners.back()]
				can_enter=(tail.pos-portal.entry).dot(portal.direction)>float(gate.spacing)
			if can_enter and e.pos.distance_to(portal.entry)<float(gate.spacing)*1.5:
				gate.owners.append(id);gate.batch+=1;grants+=1
		if gate.owners.has(id):
			var axis: Vector2=portal.entry+portal.direction*(e.pos-portal.entry).dot(portal.direction)
			if (e.pos-portal.entry).dot(portal.direction)>=-.5 and e.pos.distance_to(axis)>.02 and sim._segment_static(e.pos,axis,sim._radius(e),id):
				return {"goal":axis,"strict":true,"precision":true,"gate":int(portal.gate),"rank":-1,"owner":true}
			var entering: bool=(e.pos-portal.entry).dot(portal.direction)<-.4
			return {"goal":portal.entry if entering else portal.exit,"strict":not entering,"gate":int(portal.gate),"rank":-1,"owner":true}
		waits+=1
		var target: Vector2=_queue_point(sim,e,portal,maxi(0,rank-(gate.owners.size() if int(gate.active)==gid else 0)),float(gate.spacing))
		var lateral: float=absf((e.pos-portal.entry).dot((portal.direction as Vector2).orthogonal()))
		return {"goal":target,"strict":false,"gate":int(portal.gate),"rank":rank,"owner":false,"heading":rad_to_deg((portal.direction as Vector2).angle())}
	return {}

func snapshot() -> Dictionary:
	return {"groups":groups.duplicate(true),"gates":gates.duplicate(true),"plans":plans,"grants":grants,"waits":waits}

func restore(state: Dictionary) -> void:
	clear()
	groups=state.get("groups",{}).duplicate(true)
	gates.assign(state.get("gates",[]).duplicate(true))
	plans=int(state.get("plans",0));grants=int(state.get("grants",0));waits=int(state.get("waits",0))

static func valid_state(state: Variant) -> bool:
	if not state is Dictionary or not state.get("groups") is Dictionary or not state.get("gates") is Array:return false
	for field in ["plans","grants","waits"]:
		if not state.get(field) is int or state[field]<0:return false
	for gid in state.groups:
		var group: Variant=state.groups[gid]
		if not gid is int or gid<1 or not group is Dictionary or group.get("id")!=gid or not _ids(group.get("members")) or not group.get("portals") is Array:return false
		if not _positive(group.get("radius")):return false
		for portal in group.portals:
			if not portal is Dictionary or not portal.get("gate") is int or portal.gate<0 or portal.gate>=state.gates.size():return false
			for field in ["entry","exit","direction"]:
				if not _vector(portal.get(field)):return false
			if not portal.get("departed") is Dictionary:return false
			for id in portal.departed:
				if not id is int or id<1 or not portal.departed[id] is bool:return false
	for gate in state.gates:
		if not gate is Dictionary or not gate.get("bounds") is Rect2 or not gate.bounds.position.is_finite() or not gate.bounds.size.is_finite():return false
		if not gate.get("queues") is Dictionary or not gate.get("entries") is Dictionary or not _ids(gate.get("owners")):return false
		for field in ["active","last_group","batch"]:
			if not gate.get(field) is int:return false
		if gate.batch<0 or not _positive(gate.get("spacing")):return false
		for gid in gate.queues:
			if not gid is int or gid<1 or not _ids(gate.queues[gid]) or not gate.entries.has(gid):return false
		for gid in gate.entries:
			if not gid is int or gid<1 or not _vector(gate.entries[gid]):return false
	return true

static func _ids(value: Variant) -> bool:
	if not value is Array:return false
	for id in value:
		if not id is int or id<1:return false
	return true
static func _vector(value: Variant) -> bool:
	return value is Vector2 and value.is_finite()
static func _positive(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(value) and value>0

func motion_allowed(id: int, start: Vector2, finish: Vector2, radius: float) -> bool:
	for gate in gates:
		if gate.owners.has(id) or (gate.queues.is_empty() and gate.owners.is_empty()):continue
		var region: Rect2=gate.bounds.grow(radius+.02)
		if not region.has_point(finish):continue
		if not region.has_point(start):return false
		# Incumbents without a ticket may leave, but cannot advance deeper into
		# reserved space. This also applies to avoidance and temporary yielding.
		var old_depth: float=minf(minf(start.x-region.position.x,region.end.x-start.x),minf(start.y-region.position.y,region.end.y-start.y))
		var new_depth: float=minf(minf(finish.x-region.position.x,region.end.x-finish.x),minf(finish.y-region.position.y,region.end.y-finish.y))
		if new_depth>old_depth+.001:return false
	return true

func motion_segment_allowed(id: int, start: Vector2, finish: Vector2, radius: float) -> bool:
	var previous: Vector2=start
	var steps: int=maxi(1,ceili(start.distance_to(finish)/.2))
	for i in range(1,steps+1):
		var point: Vector2=start.lerp(finish,float(i)/steps)
		if not motion_allowed(id,previous,point,radius):return false
		previous=point
	return true
