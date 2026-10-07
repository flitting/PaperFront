extends RefCounted
## Authoritative deck roll and climb: these are real entity positions and heights.
const AirNavigation=preload("res://scripts/air_navigation.gd")
# Measured from the normalized 3.84m carrier recipe: y=1.0225*0.5383942447.
const DECK_HEIGHT:float=.5505081152
const RUN_START:=Vector2(-1.35,-.080759)
const RUN_END:=Vector2(1.35,-.080759)
const ROLL_SECONDS:float=1.15
const CLIMB_SECONDS:float=1.35
const TOTAL_SECONDS:float=ROLL_SECONDS+CLIMB_SECONDS

static func deck_position(carrier:Dictionary,local:Vector2)->Vector2:
	return (carrier.pos as Vector2)+local.rotated(deg_to_rad(float(carrier.alpha)))

static func deck_height(sim,carrier:Dictionary,point:Vector2)->float:
	return MapData.entity_surface_y(sim.map,carrier.pos,"naval")+float(sim.data_for(carrier.spec).get("carrier_deck_height",DECK_HEIGHT))-sim._height(point)

static func launch_next(sim,carrier:Dictionary)->bool:
	var count:int=int(carrier.get("carrier_pending_count",0))
	if count<=0 or float(carrier.get("carrier_next_launch",0.0))>sim.time:return false
	var target:int=int(carrier.get("carrier_pending_target",-1))
	if not sim._target_alive(target):carrier.carrier_pending_count=0;return false
	if int(carrier.get("carrier_ready",0))<=0:carrier.carrier_pending_count=0;return false
	var spec:String=str(sim.data_for(carrier.spec).faction)+"_carrier_plane"
	var point:Vector2=deck_position(carrier,RUN_START)
	var probe:Dictionary={"id":-1,"spec":spec,"pos":point,"kind":"unit","radius":float(sim.data_for(spec).radius)}
	if not AirNavigation.point_clear(sim,probe,point):return false
	var id:int=sim._spawn(int(carrier.team),spec,point,true)
	var plane:Dictionary=sim.entities[id]
	plane.carrier_id=int(carrier.id)
	plane.sortie_target=target
	plane.carrier_launch={"elapsed":0.0}
	plane.flight_height=deck_height(sim,carrier,point)
	plane.alpha=carrier.alpha
	plane.state="carrier_roll"
	sim._set_home_airfield(plane,-1)
	plane.commands=[{"kind":"attack","target":target,"pos":sim._target_position(target)}]
	carrier.carrier_ready=int(carrier.carrier_ready)-1
	carrier.carrier_pending_count=count-1
	carrier.carrier_next_launch=sim.time+.7
	sim.events.append({"kind":"carrier_launch","id":carrier.id,"aircraft":id,"team":carrier.team,"pos":point})
	return true

static func step(sim,plane:Dictionary,delta:float)->bool:
	if not plane.has("carrier_launch"):return false
	var carrier:Dictionary=sim.entities.get(int(plane.get("carrier_id",-1)),{})
	if carrier.is_empty():
		plane.erase("carrier_launch")
		plane.flight_height=float(sim.data_for(plane.spec).flight_height)
		return false
	var launch:Dictionary=plane.carrier_launch
	var elapsed:float=minf(TOTAL_SECONDS,float(launch.elapsed)+maxf(0,delta))
	var roll:float=clampf(elapsed/ROLL_SECONDS,0,1)
	var climb:float=clampf((elapsed-ROLL_SECONDS)/CLIMB_SECONDS,0,1)
	var local:Vector2=RUN_START.lerp(RUN_END,roll*roll)+Vector2(5.5*climb,0)
	var next:Vector2=deck_position(carrier,local)
	var old:Vector2=plane.pos
	var motion:Vector2=next-old
	var traffic:Array=AirNavigation._traffic(sim,old,motion.length()+sim._radius(plane)+float(sim._max_entity_extent)+2,int(plane.id))
	if not sim._in_bounds(next) or not AirNavigation._motion_clear(sim,plane,old,motion,traffic):
		plane.motion=0.0
		plane.state="waiting_launch"
		return true
	plane.air_motion_from=old
	plane.air_motion_time=sim.time
	plane.pos=next
	plane.alpha=carrier.alpha
	plane.motion=motion.length()/maxf(delta,.001)
	plane.state="carrier_roll" if climb<=0 else "carrier_climb"
	plane.flight_height=lerpf(deck_height(sim,carrier,next),float(sim.data_for(plane.spec).flight_height),smoothstep(0,1,climb))
	launch.elapsed=elapsed
	sim._spatial_move(plane,old,next)
	if elapsed>=TOTAL_SECONDS:
		plane.erase("carrier_launch")
		plane.state="move"
		plane.flight_height=float(sim.data_for(plane.spec).flight_height)
	return true
