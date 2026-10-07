extends RefCounted

## Cosmetic altitude/velocity only. No entity, navigation or map is mutated.
const MAP = preload("res://scripts/map_data.gd")
const LOOK_SECONDS: float = 2.0
const CLIMB_SLOPE: float = .40
const CLIMB_RATE: float = 5.2
const DESCENT_RATE: float = 2.3

static func required_height(map: Dictionary, pos: Vector2, direction: Vector2, speed: float, clearance: float, footprint: float, terrain_span: float = 0.0) -> float:
	var current: float=MAP.height_at(map,pos)+clearance
	# Begin climbing early enough for the map's highest possible shelf. The
	# envelope slope stays below the available climb rate even for fast planes.
	var slope: float=minf(CLIMB_SLOPE,CLIMB_RATE*.80/maxf(speed+.5,1.0))
	var climb_distance: float=maxf(0,terrain_span)/slope+speed*.5+footprint*.5
	var ahead: float=clampf(maxf(speed*LOOK_SECONDS+footprint*.5,climb_distance),3.0,minf(float(map.size),128.0))
	var lateral: Vector2=direction.orthogonal()*minf(footprint*.25,2.0)
	for index: int in range(0,ceili(ahead)+1):
		var distance: float=minf(float(index),ahead)
		var point: Vector2=pos+direction*distance
		for offset: Vector2 in [Vector2.ZERO,lateral,-lateral]:
			var sample: Vector2=point+offset
			if sample.x<0 or sample.y<0 or sample.x>=float(map.size)-1 or sample.y>=float(map.size)-1:continue
			current=maxf(current,MAP.height_at(map,sample)+clearance-slope*distance)
	return current

static func update(model: Dictionary, entity: Dictionary, map: Dictionary, delta: float) -> void:
	var pos: Vector2=entity.pos
	var terrain: float=MAP.height_at(map,pos)
	var logical: float=float(entity.get("flight_height",model.spec.get("flight_height",0.0)))
	if entity.has("carrier_launch"):
		model.visual_air_y=terrain+logical
		model.logical_flight_height=logical
		model.flight_height=logical
		model.airborne_visual=true
		model.air_motion_pos=pos
		return
	var airborne: bool=bool(entity.get("airborne",true)) and logical>1.8 and int(entity.get("transport_id",-1))<=0
	var previous: Vector2=model.get("air_motion_pos",pos)
	var velocity: Vector2=model.get("visual_air_velocity",Vector2.ZERO)
	if delta>0.0:
		var measured: Vector2=(pos-previous)/maxf(delta,.001)
		if measured.length()<maxf(float(model.spec.get("speed",8.0))*3.0,20.0):
			velocity=velocity.lerp(measured,clampf(delta*12.0,0,1))
			model.visual_air_measured_velocity=measured
	model.visual_air_velocity=velocity
	model.air_motion_pos=pos
	model.airborne_visual=airborne
	var heading: Vector2=Vector2.RIGHT.rotated(deg_to_rad(float(entity.get("alpha",0.0))))
	var direction: Vector2=velocity.normalized() if velocity.length()>.5 else heading
	var speed: float=maxf(velocity.length(),float(model.spec.get("speed",8.0))*.65) if entity.get("state","") in ["move","returning","attack"] else velocity.length()
	var target: float=terrain+logical
	if airborne: target=required_height(map,pos,direction,speed,logical,float(model.dimensions.x),float(model.get("air_terrain_span",0.0)))
	var initialized: bool=model.has("visual_air_y")
	var height: float=float(model.get("visual_air_y",terrain+logical))
	if not airborne or not initialized:
		height=terrain+logical
	elif delta>0.0:
		var rate: float=CLIMB_RATE if target>height else DESCENT_RATE
		height=move_toward(height,target,rate*minf(delta,.1))
		# Terrain safety is a floor, not a change to the rules' flight altitude.
		height=maxf(height,terrain+minf(logical,2.2))
	model.visual_air_y=height
	model.logical_flight_height=logical
	model.flight_height=height-terrain
