extends SceneTree

const Map=preload("res://scripts/map_data.gd")
const Motion=preload("res://scripts/aircraft_visual_motion.gd")
var checks: int=0
var failures: Array[String]=[]
var rows: Array=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failures.append(label)
func span(map: Dictionary) -> float:
	var low: float=INF;var high: float=-INF
	for row: Array in map.heights:
		for value in row:low=minf(low,float(value));high=maxf(high,float(value))
	return high-low
func fly(map: Dictionary,start: Vector2,direction: Vector2,distance: float,speed: float,label: String) -> void:
	var model: Dictionary={"spec":{"speed":speed},"dimensions":Vector2(7,2),"air_terrain_span":span(map)}
	var e: Dictionary={"pos":start,"flight_height":5.0,"airborne":true,"state":"move","alpha":rad_to_deg(direction.angle())}
	Motion.update(model,e,map,0)
	var previous: float=model.visual_air_y;var max_delta: float=0;var min_clearance: float=INF
	for frame: int in ceili(distance/speed*30):
		e.pos+=direction*speed/30.0
		var snapshot: Dictionary=e.duplicate(true)
		Motion.update(model,e,map,1.0/30.0)
		max_delta=maxf(max_delta,absf(float(model.visual_air_y)-previous))
		min_clearance=minf(min_clearance,float(model.visual_air_y)-Map.height_at(map,e.pos))
		if e!=snapshot:failures.append(label+" mutated simulation entity");break
		previous=model.visual_air_y
	check(max_delta<=Motion.CLIMB_RATE/30.0+.002,label+" remains continuous at full terrain height and speed")
	check(min_clearance>=2.199,label+" remains safely above terrain without disabling the safety floor")
	rows.append({"fixture":label,"speed":speed,"terrain_span":span(map),"max_frame_delta_y":max_delta,"minimum_clearance":min_clearance})
func run() -> void:
	var real: Dictionary=Map.generate("forest",7)
	check(int(real.size)==320,"forest fixture uses the actual 320m battlefield generator")
	var edge:=Vector2.ZERO;var direction:=Vector2.RIGHT;var largest: float=0
	for z: int in range(70,int(real.size)-70):
		for x: int in range(70,int(real.size)-70):
			for axis: Vector2i in [Vector2i.RIGHT,Vector2i.DOWN]:
				var diff: float=float(real.heights[z+axis.y][x+axis.x])-float(real.heights[z][x])
				if absf(diff)>largest:
					largest=absf(diff);edge=Vector2(x+.5,z+.5);direction=Vector2(axis)*signf(diff)
	for speed: float in [8.0,12.0]:fly(real,edge-direction*64,direction,112,speed,"actual forest320 steepest edge")
	var map: Dictionary=real.duplicate(true)
	for height: float in [14.8,16.0,20.0]:
		for z: int in int(map.size):
			for x: int in int(map.size):map.heights[z][x]=height if x>=160 else 0.0
		for speed: float in [8.0,12.0]:fly(map,Vector2(88,160),Vector2.RIGHT,120,speed,str(height)+"m vertical cliff")
	print("AIRCRAFT_STEEP_TERRAIN ",JSON.stringify({"checks":checks,"failures":failures,"real_max_edge":largest,"rows":rows}))
	for failure: String in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
