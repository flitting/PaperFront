extends SceneTree
## Four paid aircraft lifecycles under the frozen production runtime.
## Initial bases/power are seeded test infrastructure; the aircraft is never
## spawned, teleported, assigned flight state, refuelled or given free money.
const Sim=preload("res://tests/rule_test_simulation.gd")
const SOURCES=["res://scripts/simulation.gd","res://scripts/building_orientation.gd","res://scripts/production_lifecycle.gd","res://scripts/aircraft_operations.gd","res://scripts/air_navigation.gd","res://data/rules.json","res://assets/native/libpaper_front_kernels.so"]
var checks:int=0
var failures:Array[String]=[]
var cases:Array=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func fixture(q:int):
	var sim=Sim.new();sim.setup(RulesLoader.load_rules(),"dev",446,"kestrel",false,{"vision_enabled":false})
	for id in sim.entities.keys():sim._kill_entity(id,false)
	for row in sim.map.terrain:row.fill(0)
	for row in sim.map.heights:row.fill(0.0)
	sim.mines.clear();sim.bridges.clear();sim.map.bridges.clear();sim.ruins.clear();sim._refresh_ruin_spatial();sim._prepare_terrain_cache()
	sim._spawn(0,"kestrel_hq",Vector2(8,8),true)
	sim._spawn(1,"rivet_hq",Vector2(43,43),true)
	for point in [Vector2(8,18),Vector2(14,18),Vector2(20,18)]:sim._spawn(0,"kestrel_power",point,true)
	sim._spawn(0,"kestrel_barracks",Vector2(8.5,26.5),true)
	sim._spawn(0,"kestrel_factory",Vector2(15,30),true)
	var field:int=sim._spawn(0,"kestrel_airfield",Vector2(28.5,28.5),true,q)
	sim.money[0]=10000;sim.events.clear();sim.result=""
	return {"sim":sim,"field":field}
func snapshot(e:Dictionary)->Dictionary:
	return {"pos":[e.pos.x,e.pos.y],"height":e.get("flight_height",-1),"airborne":e.get("airborne",true),"flight_state":e.get("flight_state",""),"state":e.state,"heading":e.alpha,"ammo":e.get("ammo",-1),"home":e.get("home_airfield",-1)}
func run()->void:
	var source_before:Dictionary={}
	for path:String in SOURCES:source_before[path]=FileAccess.get_sha256(path)
	# Independently authored expected world coordinates. The test never calls
	# the orientation/slot helper to construct its expected result.
	var expected_positions:Array[Vector2]=[Vector2(26.9,26.9),Vector2(30.1,26.9),Vector2(30.1,30.1),Vector2(26.9,30.1)]
	for q in range(4):
		var item:Dictionary=fixture(q)
		var sim=item.sim
		var field:int=item.field
		var aircraft:int=-1
		var money_before:float=sim.money[0]
		var price:float=float(sim.data_for("kestrel_fighter").cost)
		var error:String=sim.produce(field,"kestrel_fighter")
		check(error.is_empty(),"q%d actual paid fighter production: %s"%[q,error])
		check(is_equal_approx(money_before-sim.money[0],price),"q%d deducts fighter price exactly once"%q)
		for tick in range(1600):
			sim.step(.05)
			for e in sim.entities.values():
				if e.spec=="kestrel_fighter":aircraft=int(e.id)
			if aircraft>0 and sim.entities[aircraft].state=="parked":break
		check(aircraft>0,"q%d produced real aircraft entity"%q)
		if aircraft<0:continue
		var e:Dictionary=sim.entities[aircraft]
		var produced:Dictionary=snapshot(e)
		check((e.pos as Vector2).distance_to(expected_positions[q])<.03,"q%d actual first apron position matches authored rotated stand"%q)
		check(not bool(e.airborne) and is_equal_approx(float(e.flight_height),.35),"q%d produced fighter is parked at apron altitude"%q)
		check(e.state=="parked" and e.flight_state=="rearming","q%d initial parked service state is reached"%q)
		check(absf(wrapf(float(e.alpha)-float(q)*90,-180,180))<.1,"q%d produced parked nose follows airfield heading"%q)
		check(int(e.home_airfield)==field,"q%d production assigns actual home airfield"%q)
		var away:Vector2=expected_positions[q]+Vector2(8,-8)
		sim.issue([aircraft],"move",away)
		var airborne_seen:bool=false
		var maximum_distance:float=0.0
		var maximum_height:float=0.0
		for tick in range(300):
			sim.step(.05)
			maximum_distance=maxf(maximum_distance,(e.pos as Vector2).distance_to(expected_positions[q]))
			maximum_height=maxf(maximum_height,float(e.flight_height))
			airborne_seen=airborne_seen or (bool(e.airborne) and e.flight_state=="airborne")
			if (e.pos as Vector2).distance_to(away)<.2:break
		var flying:Dictionary=snapshot(e)
		check(airborne_seen and maximum_height>=float(sim.data_for(e.spec).flight_height),"q%d real move order takes off to flying altitude"%q)
		check(maximum_distance>8 and (e.pos as Vector2).distance_to(away)<.2,"q%d aircraft physically flies to away destination"%q)
		check(absf(wrapf(float(e.alpha)+45,-180,180))<1,"q%d nose turns toward actual outbound flight direction"%q)
		sim.issue([aircraft],"return",sim.entities[field].pos)
		var returning_seen:bool=e.flight_state=="returning"
		var rearming_seen:bool=false
		for tick in range(1000):
			sim.step(.05)
			returning_seen=returning_seen or e.flight_state=="returning"
			rearming_seen=rearming_seen or (e.flight_state=="rearming" and e.state=="rearm")
			if e.state=="parked" and not bool(e.airborne):break
		var returned:Dictionary=snapshot(e)
		check(returning_seen and rearming_seen,"q%d explicit return traverses real returning and rearm states"%q)
		check(e.state=="parked" and not bool(e.airborne) and is_equal_approx(float(e.flight_height),.35),"q%d return finishes parked at apron altitude"%q)
		check((e.pos as Vector2).distance_to(expected_positions[q])<.11,"q%d aircraft physically returns to selected rotated stand"%q)
		check(absf(wrapf(float(e.alpha)-float(q)*90,-180,180))<.1,"q%d returned parked nose realigns with rotated airfield"%q)
		check(int(e.ammo)==int(sim.data_for(e.spec).ammo_capacity),"q%d normal rearm completes"%q)
		check(is_equal_approx(sim.money[0],money_before-price),"q%d healthy roundtrip has no duplicate charge or fabricated income"%q)
		cases.append({"q":q,"price_paid":money_before-sim.money[0],"expected_parking":[expected_positions[q].x,expected_positions[q].y],"produced":produced,"outbound":flying,"returned":returned,"max_distance":maximum_distance,"max_flight_height":maximum_height,"seconds":sim.time,"native_units":sim.native_unit_dispatch_enabled})
		await process_frame
	var changed:Array=[]
	for path:String in SOURCES:
		if FileAccess.get_sha256(path)!=source_before[path]:changed.append(path)
	check(changed.is_empty(),"frozen runtime sources remain unchanged")
	DirAccess.make_dir_recursive_absolute("res://artifacts/building_orientation")
	FileAccess.open("res://artifacts/building_orientation/aircycle.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":cases,"loaded_source_sha256":source_before,"changed_sources":changed,"test_sha256":FileAccess.get_sha256("res://tests/building_orientation_aircycle_tests.gd"),"scope":"Seeded real bases/power, four single-aircraft paid production + move/takeoff + explicit return/rearm/parking cycles. No direct aircraft spawn, teleport or flight-state writes."},"  "))
	print("BUILDING_ORIENTATION_AIRCYCLE ",JSON.stringify({"checks":checks,"failures":failures,"cases":cases}))
	quit(0 if failures.is_empty() else 1)
