extends RefCounted
const Orientation=preload("res://scripts/building_orientation.gd")

## A single reserved front doorway owns the checked unloading trip inside.
static func entrance(sim, unit: Dictionary, refinery: Dictionary) -> Vector2:
	if sim.RailNetwork.rail_only(sim.data_for(unit.spec)):
		var rail: Vector2 = sim._rail_network.exit_cell(sim, refinery)
		return rail if not sim._rail_network.at(int(unit.team), rail).is_empty() else Vector2.INF
	var half: float = float(sim.data_for(refinery.spec).size)*.5
	var point: Vector2 = Orientation.point(refinery,Vector2(0,half+sim._radius(unit)+.15))
	return point if sim._standing(point,sim._radius(unit),int(unit.id),false) else Vector2.INF

static func _reservation(sim, refinery: Dictionary) -> int:
	var occupied: int=int(refinery.get("dock_unit",-1))
	var other: Dictionary=sim.entities.get(occupied,{})
	if not other.is_empty() and float(other.hp)>0 and int(other.get("refinery_docking",{}).get("source",-1))==int(refinery.id): return occupied
	refinery.dock_unit=-1
	return -1

static func _waiters(sim, refinery: Dictionary) -> Array:
	var answer: Array=[]
	for other: Dictionary in sim.entities.values():
		var waiting: Dictionary=other.get("refinery_waiting",{})
		if int(waiting.get("source",-1))!=int(refinery.id): continue
		var commands: Array=other.get("commands",[])
		var repair: bool=str(waiting.get("mode",""))=="repair"
		var valid: bool=float(other.hp)>0 and int(other.team)==int(refinery.team)
		if repair: valid=valid and not commands.is_empty() and str(commands[0].kind)=="service" and int(commands[0].target)==int(refinery.id)
		else: valid=valid and (float(other.get("cargo",0))>0 or bool(other.get("manual_unload",false))) and int(other.get("harvest_refinery",-1))==int(refinery.id) and (commands.is_empty() or str(commands[0].kind) in ["harvest","return_miner"])
		if valid: answer.append(other)
		else: other.erase("refinery_waiting")
	answer.sort_custom(func(a: Dictionary,b: Dictionary): return int(a.refinery_waiting.ticket)<int(b.refinery_waiting.ticket))
	return answer

static func _waiting_goal(sim,unit: Dictionary,refinery: Dictionary,outside: Vector2) -> Vector2:
	var waiting: Dictionary=unit.refinery_waiting
	var radius: float=sim._radius(unit)
	var old: Vector2=waiting.get("goal",Vector2.INF)
	if old.is_finite() and sim._standing(old,radius,int(unit.id),false): return old
	var offset: float=((unit.pos as Vector2)-(refinery.pos as Vector2)).dot(Orientation.offset(Vector2.RIGHT,Orientation.quarters(refinery)))
	var side: float=-1.0 if offset<-.1 else 1.0
	var waiters: Array=_waiters(sim,refinery)
	# Queue beside the door, never on its centerline. Prefer the side the
	# arriving vehicle is already on so yielding first increases separation.
	for row in range(5):
		for lateral in [maxf(1.6,radius*2+.65),maxf(2.2,radius*2+1.1)]:
			for sign_side in [side,-side]:
				var point: Vector2=outside+Orientation.offset(Vector2(sign_side*float(lateral),.70+float(row)*(radius*2+.45)),Orientation.quarters(refinery))
				if not sim._standing(point,radius,int(unit.id),false): continue
				var reserved: bool=false
				for other: Dictionary in waiters:
					if int(other.id)==int(unit.id): continue
					var other_goal: Vector2=other.refinery_waiting.get("goal",Vector2.INF)
					if other_goal.is_finite() and point.distance_to(other_goal)<radius+sim._radius(other)+.25: reserved=true; break
				if reserved: continue
				waiting.goal=point
				return point
	return Vector2.INF

static func approach(sim,unit: Dictionary,refinery: Dictionary,delta: float,mode: String="") -> void:
	var outside: Vector2=entrance(sim,unit,refinery)
	if not outside.is_finite():
		if mode!="repair": unit.harvest_refinery=-1
		unit.state="waiting_rail" if sim.RailNetwork.rail_only(sim.data_for(unit.spec)) else "waiting"
		return
	# Rail traffic follows its actual connected exit cell and retains the
	# established rail-only overlap policy; never send it to an off-track queue.
	if sim.RailNetwork.rail_only(sim.data_for(unit.spec)):
		if (unit.pos as Vector2).distance_to(outside)>=.75: sim._move_to(unit,outside,delta); return
		if not begin(sim,unit,refinery,outside): return
	else:
		var waiting: Dictionary=unit.get("refinery_waiting",{})
		if int(waiting.get("source",-1))!=int(refinery.id):
			refinery.dock_ticket=int(refinery.get("dock_ticket",0))+1
			unit.refinery_waiting={"source":int(refinery.id),"ticket":int(refinery.dock_ticket),"mode":mode,"goal":Vector2.INF}
		var queue: Array=_waiters(sim,refinery)
		var busy: bool=_reservation(sim,refinery)>0 or bool(refinery.get("gift_pending",false)) or sim.entities.has(int(refinery.get("production_unit",-1)))
		var first: bool=not queue.is_empty() and int(queue[0].id)==int(unit.id)
		if busy or not first:
			var goal: Vector2=_waiting_goal(sim,unit,refinery,outside)
			if goal.is_finite() and (unit.pos as Vector2).distance_to(goal)>.12: sim._move_to(unit,goal,delta)
			else: unit.state="waiting"
			return
		# Own the lane before approaching it, rather than racing another truck
		# to the same outside point and trying to claim the bay afterwards.
		if not begin(sim,unit,refinery,outside): return
		unit.refinery_docking.phase="approach"
	if mode=="repair":
		unit.refinery_docking.mode="repair"
		unit.refinery_docking.initial_hp=float(unit.hp)
		unit.refinery_docking.finish_service=true
	step_unit(sim,unit,delta)

static func _clearance_goal(sim,unit: Dictionary,field: Dictionary,outside: Vector2) -> Vector2:
	var radius: float=sim._radius(unit)
	var queue: Array=_waiters(sim,field)
	for distance in [maxf(1.65,radius*2+.65),maxf(2.25,radius*2+1.1),maxf(3.0,radius*2+1.8)]:
		for direction in [Vector2(0,1),Vector2(1,1),Vector2(-1,1),Vector2(1,.4),Vector2(-1,.4)]:
			var point: Vector2=outside+Orientation.offset(direction,Orientation.quarters(field))*float(distance)
			if not sim._standing(point,radius,int(unit.id)) or not sim._segment_static(unit.pos,point,radius,int(field.id)): continue
			var reserved: bool=false
			for other: Dictionary in queue:
				var goal: Vector2=other.refinery_waiting.get("goal",Vector2.INF)
				if goal.is_finite() and point.distance_to(goal)<radius+sim._radius(other)+.25: reserved=true; break
			if not reserved: return point
	return Vector2.INF

static func begin(sim, unit: Dictionary, refinery: Dictionary, outside: Vector2) -> bool:
	var occupied: int = _reservation(sim,refinery)
	if occupied > 0 and occupied != int(unit.id) and sim.entities.has(occupied): unit.state="waiting"; return false
	if bool(refinery.get("gift_pending",false)) or sim.entities.has(int(refinery.get("production_unit",-1))): unit.state="waiting"; return false
	var half: float = float(sim.data_for(refinery.spec).size)*.5
	var inside: Vector2 = Orientation.point(refinery,Vector2(0,maxf(0,half-sim._radius(unit)-float(sim._eco("production_inside_margin",.75)))))
	unit.refinery_docking={"source":int(refinery.id),"phase":"align","outside":outside,"inside":inside,"remaining":float(sim._eco("harvester_unload_time",2)),"credited":false}
	refinery.dock_unit=int(unit.id)
	unit.erase("refinery_waiting")
	sim._release_mine(int(unit.id))
	return true

static func active(sim) -> bool:
	for e in sim.entities.values():
		if not e.get("refinery_docking",{}).is_empty(): return true
	return false

static func release(sim, unit: Dictionary) -> void:
	var job: Dictionary=unit.get("refinery_docking",{})
	var field: Dictionary=sim.entities.get(int(job.get("source",-1)),{})
	if not field.is_empty() and int(field.get("dock_unit",-1))==int(unit.id): field.dock_unit=-1
	unit.erase("refinery_docking")
	unit.erase("refinery_waiting")
	unit.erase("unload_remaining")

static func _travel(sim, unit: Dictionary, goal: Vector2, delta: float, ignore_building: int) -> bool:
	var original: Vector2=unit.pos
	var next: Vector2=original.move_toward(goal,float(sim.data_for(unit.spec).speed)*delta)
	if not sim._segment_static(original,next,sim._radius(unit),ignore_building): unit.state="waiting"; return false
	for other in sim._neighbors(next):
		if int(other.id)==int(unit.id): continue
		if sim.RailNetwork.rail_only(sim.data_for(unit.spec)) and int(other.team)==int(unit.team) and sim._rail_network.usable(sim,other,other.pos): continue
		if Geometry2D.get_closest_point_to_segment(other.pos,original,next).distance_to(other.pos)<sim._radius(unit)+sim._radius(other)+.02: unit.state="waiting"; return false
	unit.pos=next
	unit.motion=original.distance_to(next)/maxf(delta,.001)
	if unit.motion>0: unit.alpha=rad_to_deg((next-original).angle()); unit.turret_alpha=unit.alpha
	unit.state="unload"
	sim._spatial_move(unit,original,next)
	return next.distance_to(goal)<.01

static func step_unit(sim, unit: Dictionary, delta: float) -> bool:
	var job: Dictionary=unit.get("refinery_docking",{})
	if job.is_empty(): return false
	var field: Dictionary=sim.entities.get(int(job.source),{})
	if field.is_empty(): release(sim,unit); unit.harvest_refinery=-1; return false
	if int(field.team)!=int(unit.team) or float(field.hp)<=0: job.phase="exit"
	if float(field.get("emp_until",0))>sim.time: unit.state="waiting"; return true
	if sim.RailNetwork.rail_only(sim.data_for(unit.spec)) and sim._rail_network.at(int(unit.team),job.outside).is_empty(): unit.state="waiting_rail"; return true
	if job.phase=="approach":
		if (unit.pos as Vector2).distance_to(job.outside)>.75:
			sim._move_to(unit,job.outside,delta)
			return true
		job.phase="align"
	if job.phase=="align":
		if _travel(sim,unit,job.outside,delta,int(unit.id)): job.phase="open"
		return true
	field.production_door=minf(1,float(field.get("production_door",0))+delta/float(sim._eco("production_door_time",.6)))
	if float(field.production_door)<1: unit.state="waiting_exit"; return true
	if job.phase in ["open","enter"]:
		job.phase="enter"
		if _travel(sim,unit,job.inside,delta,int(field.id)): job.phase="unload"
		return true
	if job.phase=="unload" and job.get("mode","")=="repair":
		unit.state="service"
		if sim.building_low_power(field): return true
		var maximum: float=sim.max_hp(unit)
		var amount: float=minf(maximum-float(unit.hp),float(sim.data_for(field.spec).get("service_rate",30))*delta)
		var price: float=float(sim._eco("repair_cost",.2))
		if price>0: amount=minf(amount,float(sim.money[int(unit.team)])/price)
		unit.hp=minf(maximum,float(unit.hp)+amount)
		sim.money[int(unit.team)]=maxf(0,float(sim.money[int(unit.team)])-amount*price)
		if float(unit.hp)<maximum-.001: return true
		sim.events.append({"kind":"service_complete","id":int(unit.id),"team":unit.team,"pos":unit.pos,"source":int(field.id)})
		job.phase="exit"
	if job.phase=="unload":
		unit.state="unload"
		job.remaining=maxf(0,float(job.remaining)-delta)
		unit.unload_remaining=float(job.remaining)
		unit.unload_progress=1-float(job.remaining)/maxf(.001,float(sim._eco("harvester_unload_time",2)))
		if float(job.remaining)>0: return true
		if not bool(job.credited):
			sim.money[int(unit.team)]+=float(unit.cargo)
			sim.statistics.add(int(unit.team),"funds_earned",float(unit.cargo))
			sim.events.append({"kind":"delivery","id":int(unit.id),"pos":unit.pos,"amount":unit.cargo,"team":unit.team,"refinery":int(field.id),"inside":true})
			unit.cargo=0.0; job.credited=true
		job.phase="exit"
	if job.phase=="exit":
		if not _travel(sim,unit,job.outside,delta,int(field.id)): return true
		if not sim.RailNetwork.rail_only(sim.data_for(unit.spec)):
			job.phase="clear"
			job.clearance=Vector2.INF
			return true
	if job.phase=="clear":
		var goal: Vector2=job.get("clearance",Vector2.INF)
		if not goal.is_finite():
			goal=_clearance_goal(sim,unit,field,job.outside)
			job.clearance=goal
		if not goal.is_finite(): unit.state="waiting"; return true
		if not _travel(sim,unit,goal,delta,int(field.id)): return true
	if job.phase in ["exit","clear"]:
		unit.harvest_mine=int(unit.get("preferred_mine",-1))
		unit.mining_goal=Vector2.INF; unit.path.clear(); unit.path_goal=Vector2.INF
		unit.unload_progress=0.0
		unit.manual_unload=false
		if not unit.commands.is_empty() and unit.commands[0].kind=="return_miner":sim._finish_command(unit)
		var serviced: bool=bool(job.get("finish_service",false))
		release(sim,unit)
		unit.state="idle"
		if serviced and not unit.commands.is_empty() and unit.commands[0].kind=="service": sim._finish_command(unit)
		if unit.commands.size()>1 and unit.commands[0].kind=="harvest": sim._finish_command(unit)
	return true
