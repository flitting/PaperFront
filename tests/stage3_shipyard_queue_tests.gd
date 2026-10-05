extends SceneTree

const Sim=preload("res://tests/rule_test_simulation.gd")
var failures:Array[String]=[]
var checks:int=0

func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message)

func _initialize()->void:
	var rules:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/rules.json"))
	if not rules is Dictionary:push_error("rules unavailable");quit(1);return
	var sim=Sim.new()
	sim.setup_multiteam(rules,"islands",17,["rivet","kestrel"],false,[],Callable(),{"players":2})
	var home:Dictionary={}
	for harbor:Dictionary in sim.map.harbors:
		if int(harbor.get("team",-1))==1 and harbor.get("role")=="home":home=harbor;break
	var site:=Vector2.INF
	for ring in range(21):
		for side in range(24):
			var wanted:Vector2=home.water_pos+Vector2.from_angle(float(side)*TAU/24)*float(ring)*.9
			var point:=Vector2(roundf(wanted.x),roundf(wanted.y))
			if sim.NavalOperations.shipyard_site_error(sim,1,sim.data_for("kestrel_shipyard"),point).is_empty():site=point;break
		if site.is_finite():break
	check(site.is_finite(),"queue fixture uses an authorized full-water shipyard site")
	if not site.is_finite():quit(1);return
	var yard_id:int=sim._spawn(1,"kestrel_shipyard",site,true)
	var yard:Dictionary=sim.entities[yard_id]
	var original:Vector2=yard.pos
	check(sim.NavalOperations.spawn_point(sim,yard,"kestrel_ship_transport").is_finite(),"shipyard starts with a legal water exit")
	var before:float=sim.money[1]
	check(sim.produce(yard_id,"kestrel_ship_transport").is_empty(),"transport enters normal paid production queue")
	var paid:float=sim.money[1]
	check(is_equal_approx(before-paid,float(sim.data_for("kestrel_ship_transport").cost)),"production charges standard cost once")
	# Move the test dock inland only while checking the no-exit queue branch.
	# This forces the same INF result as a fully obstructed harbor exit.
	yard.pos=sim._team_start(1)
	sim.step(float(sim.data_for("kestrel_ship_transport").build_time)+0.1)
	check(yard.queue.size()==1 and bool(yard.queue[0].ready),"completed ship waits in queue when exit is blocked")
	check(is_equal_approx(float(sim.money[1]),paid),"blocked exit does not charge production again")
	yard.pos=original
	sim.step(0.1)
	check(yard.queue.is_empty(),"ship leaves queue when the water exit clears")
	var produced:bool=false
	for e in sim.entities.values():
		if int(e.team)==1 and e.spec=="kestrel_ship_transport":produced=true
	check(produced and is_equal_approx(float(sim.money[1]),paid),"one ship spawns for one standard payment")
	print("STAGE3_SHIPYARD_QUEUE ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
