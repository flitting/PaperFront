extends SceneTree
const Sim=preload("res://tests/rule_test_simulation.gd")
const Nav=preload("res://scripts/naval_navigation.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var sim=Sim.new()
	sim.setup(RulesLoader.load_rules(),"dev",7,"iron",false)
	var map:Dictionary={"size":12,"terrain":[]}
	for z in range(12):
		var row:Array=[]
		for x in range(12):row.append(0 if x>=6 and z>=6 else 1)
		map.terrain.append(row)
	var nav=Nav.new()
	nav.configure(map,[])
	check(not nav.static_clear(Vector2(5.2,5.6),1.0,1.0),"true two-cell ship hull rejects an overlap missed by eight directions")
	check(nav.static_clear(Vector2(4.8,5.6),1.0,1.0),"legal circular hull beside shore retained")
	check(nav.static_clear(Vector2(5,7),1.0,1.0),"exact tangency retains the full one-cell radius")
	check(not nav._shore_segment_clear(sim,Vector2(4.8,5.8),Vector2(5.8,4.8),1.0),"continuous swept hull detects a brief corner intersection")
	check(nav._shore_segment_clear(sim,Vector2(4.4,5.6),Vector2(5.6,4.4),1.0),"clear diagonal offshore connector accepted")
	sim._spawn(0,"iron_rail",Vector2(4.5,4.5),true)
	check(nav.water_clear(sim,Vector2(4.5,4.5),1.0,1.0,-1,false),"deck railway does not block naval hulls below a clear bridge")
	check(not nav._grid(sim,1.0,1.0).is_point_solid(Vector2i(4,4)),"deck railway does not create an invisible water path obstacle")
	var islands=Sim.new()
	islands.setup_multiteam(RulesLoader.load_rules(),"islands",31,["rivet","kestrel"],false)
	var sea=islands.NavalOperations._nav(islands)
	var old_stall:=Vector2(213.3881,150.7578)
	var old_waypoint:=Vector2(214.5,153.5)
	check(not sea.segment_clear(islands,old_stall,old_waypoint,1.0,1.5,-1,false),"actual seed31 former permanently blocked smoothing segment is now rejected")
	var legal_approach: Vector2 = sea.near_water(islands,Vector2(211.692,146.6772),1.0,1.5,-1,4.0,false)
	var legal_goal: Vector2 = sea.near_water(islands,Vector2(222.318,218.2923),1.0,1.5,-1,4.0,false)
	check(sea.static_clear(legal_approach,1.0,1.5),"new full-size approach selected beside the former small-hull position preserves the entire hull")
	var route:Array=sea.path_between(islands,legal_approach,legal_goal,1.0,1.5,-1)
	check(not route.is_empty(),"actual approach has a legal sea route that avoids the former blocked corner")
	var current:Vector2=legal_approach
	for point:Vector2 in route:
		check(sea.segment_clear(islands,current,point,1.0,1.5,-1,false),"every replacement sea waypoint preserves exact swept hull")
		current=point
	print("NAVAL_SHORE_REVISION ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
