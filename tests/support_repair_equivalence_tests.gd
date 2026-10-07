extends SceneTree
const Sim=preload("res://tests/rule_test_simulation.gd")
const Teams=preload("res://scripts/performance_factions.gd")
var failures:Array[String]=[]
var checks:int=0
func _initialize()->void:
	var sim=Sim.new()
	sim.setup_multiteam(Teams.make_rules(RulesLoader.load_rules()),"dev",7,Teams.ids(),false)
	var rng:=RandomNumberGenerator.new()
	rng.seed=73026
	var units:Array[int]=[]
	var stations:Array[int]=[]
	var plants:Array[int]=[]
	for team in range(8):
		plants.append(sim._spawn(team,sim.factions[team]+"_power",Vector2(15.5+team*2,18.5),true))
		for i in range(4):
			stations.append(sim._spawn(team,sim.factions[team]+"_repair",Vector2(15.5+i*5,24.5),true))
		for i in range(24):
			var role:String=["tank","rifle","engineer","fighter","scout"][i%5]
			units.append(sim._spawn(team,sim.factions[team]+"_"+role,Vector2(rng.randf_range(10,40),rng.randf_range(15,32)),true))
	# Use the original full scan as an independent behavioral oracle. Compare
	# exact money and HP, including priority when multiple units compete for funds.
	for scenario in range(80):
		sim._field_repairers.clear()
		for team in range(8):
			sim.money[team]=[0.0,.03,1.0,100000.0][(team+scenario)%4]
			sim.entities[plants[team]].emp_until=sim.time+1.0 if (scenario+team)%5==0 else 0.0
		for i in range(stations.size()):
			var station:Dictionary=sim.entities[stations[i]]
			station.team=(i/4+scenario)%8
			station.construct_remaining=1.0 if (i+scenario)%6==0 else 0.0
			station.hp=float(sim.data_for(station.spec).hp)*.5
			if i%9==0:sim._field_repairers[station.id]=9.0
		for i in range(units.size()):
			var e:Dictionary=sim.entities[units[i]]
			e.hp=float(sim.data_for(e.spec).hp)*[0.0,.25,.999,1.0][(i+scenario)%4]
			e.transport_id=12345 if (i+scenario)%17==0 else -1
			if (i+scenario)%7==0:sim._field_repairers[e.id]=24.0
			if i%19==0:e.pos=Vector2(20.5,24.5) # Exact radius boundary.
		sim._spec_cache=sim.rules.units.duplicate()
		sim._spec_cache.merge(sim.rules.buildings)
		sim._air_specs.clear()
		for spec_id in sim.rules.units:
			if sim.rules.units[spec_id].get("domain","ground")=="air":sim._air_specs[spec_id]=true
		sim._invalidate_base_cache()
		sim._ensure_base_cache()
		sim._in_step=true
		var before:Dictionary={}
		for id in sim.entities:before[id]=sim.entities[id].hp
		var money_before:Array=sim.money.duplicate()
		reference(sim,1.0/30.0)
		var expected:Dictionary={}
		for id in sim.entities:expected[id]=sim.entities[id].hp;sim.entities[id].hp=before[id]
		var expected_money:Array=sim.money.duplicate()
		sim.money.assign(money_before)
		sim._step_support(1.0/30.0,[])
		checks+=1
		if sim.money!=expected_money or sim.entities.keys().any(func(id):return sim.entities[id].hp!=expected[id]):
			failures.append("support scan differs in scenario "+str(scenario))
	print("SUPPORT_EQUIVALENCE ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
func reference(sim,delta:float)->void:
	var stations:Array=[]
	for building in sim._building_entities:
		if float(building.construct_remaining)<=0.0 and not sim.building_low_power(building) and sim.data_for(building.spec).get("role","")=="repair":stations.append(building)
	if stations.is_empty() and sim._field_repairers.is_empty():return
	for e in sim.entities.values():
		if e.kind!="unit" or sim._is_air(e) or int(e.get("transport_id",-1))>0 or float(e.hp)<=0.0:continue
		var rate:float=float(sim._field_repairers.get(int(e.id),0.0))
		for station in stations:
			var info:Dictionary=sim.data_for(station.spec)
			var armor:String=str(sim.data_for(e.spec).get("armor_class","infantry" if e.crushable else "armored"))
			if station.team!=e.team or float(station.construct_remaining)>0.0 or info.get("role","")!="repair" or sim.building_low_power(station) or armor!="armored":continue
			if (e.pos as Vector2).distance_to(station.pos)<=float(info.get("repair_radius",5.0)):rate=maxf(rate,float(info.get("repair_rate",12.0)))
		if rate>0.0:sim._repair_health(e,rate*delta)
	for id in sim._field_repairers:
		if sim.entities.has(id) and sim.entities[id].kind=="building":sim._repair_health(sim.entities[id],float(sim._field_repairers[id])*delta)
