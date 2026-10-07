extends RefCounted

# A local, anticipatory vertical rig. Ordinary terrain crossings ease in world
# space; explicit setup/diagnostic poses still resolve immediately.
const TAU := .18
const VERTICAL_SPEED := 20.0
const LOOK_SECONDS := 1.2
const LOOK_SAMPLES := 12
var initialized := false
var focus_height := 0.0
var extra_distance := 0.0
var previous_focus := Vector2.INF
var previous_eye := Vector2.INF

func reset()->void:
	initialized=false;previous_focus=Vector2.INF;previous_eye=Vector2.INF;extra_distance=0.0

func _advance(value:float,target:float,delta:float,speed:float)->float:
	var error:float=target-value
	var linear_time:float=minf(delta,maxf(0.0,(absf(error)-speed*TAU)/speed))
	var remaining:float=(absf(error)-speed*linear_time)*exp(-(delta-linear_time)/TAU)
	return target-signf(error)*remaining

func _envelope(point:Vector2,velocity:Vector2,height_query:Callable)->float:
	var high:float=height_query.call(point)
	if velocity.length_squared()<.0001:return high
	for sample:int in range(1,LOOK_SAMPLES+1):
		var seconds:float=LOOK_SECONDS*float(sample)/float(LOOK_SAMPLES)
		# Lead the easing lag itself, not just the upcoming ground. Otherwise the
		# final safety check still needs a small snap at the very edge of a cliff.
		high=maxf(high,float(height_query.call(point+velocity*seconds))-VERTICAL_SPEED*maxf(0.0,seconds-TAU*1.5))
	return high

func pose(sim, focus:Vector2, distance:float, yaw:float, pitch:float, _clearance, delta:float=-1.0)->Dictionary:
	var ground:float=MapData.height_at(sim.map,focus)
	var direction:=Vector2(sin(yaw),cos(yaw))
	var immediate:bool=not initialized or delta<=0.0 or previous_focus.distance_to(focus)>maxf(20.0,distance*.6)
	if immediate:
		focus_height=ground;extra_distance=0.0
	else:
		var velocity:Vector2=(focus-previous_focus)/delta
		var target_height:float=_envelope(focus,velocity,func(p:Vector2)->float:return MapData.height_at(sim.map,p))
		focus_height=_advance(focus_height,target_height,delta,VERTICAL_SPEED)
	# Occlusion is visual now: the eye may cross a roof or hillside without
	# being pushed away from the requested zoom. Only focal terrain height eases.
	extra_distance=0.0
	var actual:float=distance
	previous_focus=focus;previous_eye=focus+direction*actual*cos(pitch);initialized=true
	return {"target":Vector3(focus.x,focus_height,focus.y),"actual_distance":actual,"ground_height":ground}
