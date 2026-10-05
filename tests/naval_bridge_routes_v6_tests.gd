extends SceneTree
const Sim=preload("res://tests/rule_test_simulation.gd")
const Navigation=preload("res://scripts/naval_navigation.gd")
var checks:int=0
var failures:Array[String]=[]
var records:Array[Dictionary]=[]
func _initialize()->void:
	var rules:Dictionary=RulesLoader.load_rules("res://data/rules.json",false)
	for mode:String in ["city","random_city","forest","desert","snow"]:
		var args:PackedStringArray=OS.get_cmdline_user_args()
		if not args.is_empty() and mode!=args[0]:continue
		var sim=Sim.new()
		sim.setup(rules,mode,17,"rivet",false)
		var nav=Navigation.new()
		nav.configure(sim.map,sim.bridges)
		var bridges:Array=sim.bridges.duplicate()
		bridges.sort_custom(func(a,b):return float(a.bounds[1])<float(b.bounds[1]))
		check(not bridges.is_empty(),mode+" supplies bridge crossings")
		if bridges.is_empty():continue
		var points:Array[Vector2]=[]
		for bridge:Dictionary in bridges:
			var center:Vector2=Vector2(bridge.bounds[0]+bridge.bounds[2]*.5,bridge.bounds[1]+bridge.bounds[3]*.5)
			check(float(bridge.get("naval_clearance",0))>=2.25,mode+" bridge "+str(bridge.id)+" preserves required air draft")
			check(sim._terrain(center)==MapData.WATER and nav.water_clear(sim,center,3.25,2.25,-1,false),mode+" bridge "+str(bridge.id)+" retains entire largest hull water footprint")
			points.append(center)
		var start:Vector2=nav.near_water(sim,points[0]+Vector2(0,-10),3.25,2.25,-1,16,false)
		var goal:Vector2=nav.near_water(sim,points.back()+Vector2(0,10),3.25,2.25,-1,16,false)
		check(start.is_finite() and goal.is_finite(),mode+" north/south bridge approaches fit largest hull")
		if not start.is_finite() or not goal.is_finite():continue
		points.push_front(start)
		points.append(goal)
		var ship:int=sim.debug_spawn(0,"rivet_ship_signature",start)
		check(ship>0,mode+" actual max-radius vessel launches")
		if ship<1:continue
		var complete:bool=true
		var blocked:Dictionary={}
		for index in range(1,points.size()):
			var route:Array[Vector2]=nav.path_between(sim,sim.entities[ship].pos,points[index],3.25,2.25,ship)
			check(not route.is_empty() and route.back().is_equal_approx(points[index]),mode+" connected whole-hull route to crossing "+str(index))
			sim.issue([ship],"move",points[index])
			for tick in range(3000):
				sim.step(.1)
				if sim.entities[ship].commands.is_empty():break
			var reached:bool=sim.entities[ship].pos.distance_to(points[index])<1.3 and nav.water_clear(sim,sim.entities[ship].pos,3.25,2.25,ship,false)
			check(reached,mode+" largest actual vessel physically passes crossing "+str(index))
			if not reached:
				complete=false
				blocked={"target":points[index],"state":sim.entities[ship].state,"path":sim.entities[ship].get("naval_path",[]),"alpha":sim.entities[ship].alpha}
				break
		records.append({"mode":mode,"bridges":bridges.size(),"completed":complete,"simulation_seconds":sim.time,"position":sim.entities[ship].pos,"blocked":blocked})
	print("V6_NAVAL_BRIDGE_ROUTES ",JSON.stringify({"checks":checks,"failures":failures,"routes":records}))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
