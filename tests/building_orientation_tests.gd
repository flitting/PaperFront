extends SceneTree
const Sim=preload("res://tests/rule_test_simulation.gd")
const O=preload("res://scripts/building_orientation.gd")
var failures:Array[String]=[]
var checks:int=0
var records:Array=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func _initialize()->void:call_deferred("run")
func fixture(faction:String="kestrel"):
	var sim=Sim.new();sim.setup(RulesLoader.load_rules(),"dev",441,faction,false,{"vision_enabled":false})
	for id in sim.entities.keys():sim._kill_entity(id,false)
	for row in sim.map.terrain:row.fill(0)
	for row in sim.map.heights:row.fill(0.0)
	sim.mines.clear();sim.map.mines.clear();sim.bridges.clear();sim.map.bridges.clear();sim.ruins.clear();sim._refresh_ruin_spatial();sim._prepare_terrain_cache()
	sim.money[0]=50000
	sim._spawn(0,faction+"_hq",Vector2(8,8),true)
	sim._spawn(1,"rivet_hq",Vector2(42,42),true)
	for p in [Vector2(6,18),Vector2(12,18),Vector2(18,18)]:sim._spawn(0,faction+"_power",p,true)
	if faction != "rivet":sim._spawn(0,faction+"_barracks",Vector2(8.5,26.5),true)
	sim.events.clear();sim.result=""
	return sim
func advance(sim,seconds:float)->void:
	for tick in range(ceili(seconds/.05)):sim.step(.05)
func purchase(sim,spec:String,pos:Vector2,q:int)->int:
	var error:String=sim.build(0,spec)
	check(error.is_empty(),spec+" paid construction order "+error)
	if not error.is_empty():return -1
	var channel:String=sim.construction_channel(spec)
	check(sim.rotate_build_order(0,q,channel).is_empty(),"rotation accepted")
	advance(sim,float(sim.data_for(spec).build_time)+1)
	error=sim.place_building(0,pos,channel)
	check(error.is_empty(),spec+" actual placement q"+str(q)+" "+error)
	if not error.is_empty():return -1
	advance(sim,2)
	for e in sim.entities.values():
		if e.spec==spec and (e.pos as Vector2).distance_to(pos)<1:return int(e.id)
	return -1
func run()->void:
	for q in range(4):
		var sim=fixture()
		var factory:int=purchase(sim,"kestrel_factory",Vector2(28,18),q)
		if factory<0:continue
		var b:Dictionary=sim.entities[factory]
		check(int(b.rotation_quarters)==q,"placed entity retains orientation")
		check((b.rally-b.pos).normalized().is_equal_approx(O.front(b)),"default rally is outside actual doorway")
		var paid:float=sim.money[0]
		check(sim.produce(factory,"kestrel_tank").is_empty(),"paid tank production q"+str(q))
		check(is_equal_approx(paid-sim.money[0],float(sim.data_for("kestrel_tank").cost)),"tank costs its real price")
		advance(sim,24)
		var tank:int=-1
		for e in sim.entities.values():
			if e.spec=="kestrel_tank":tank=int(e.id)
		check(tank>0,"tank physically produced")
		if tank>0:
			var t:Dictionary=sim.entities[tank]
			check(not bool(t.get("emerging",false)),"tank completed traversal q"+str(q))
			check((t.pos-b.pos).dot(O.front(b))>float(sim.data_for(b.spec).size)*.5,"tank exits the rotated front q"+str(q))
			sim._kill_entity(tank,false)
		# A separate refinery exercises two full door reservations and releases.
		var refinery:int=sim._spawn(0,"kestrel_refinery",Vector2(32.5,31.5),true,q)
		var r:Dictionary=sim.entities[refinery];r.gift_pending=false
		var truck:int=sim._spawn(0,"kestrel_harvester",O.point(r,Vector2(0,6.5)),true)
		for trip in range(2):
			var t:Dictionary=sim.entities[truck];t.cargo=100.0;t.harvest_refinery=refinery;t.commands=[]
			var income:float=sim.money[0]
			var phases:Dictionary={}
			var entered:bool=false
			for step in range(600):
				sim.step(.05)
				var job:Dictionary=t.get("refinery_docking",{})
				if not job.is_empty():phases[str(job.phase)]=true
				if (t.pos-r.pos).dot(O.front(r))<float(sim.data_for(r.spec).size)*.5:entered=true
				if sim.money[0]>=income+99.9 and job.is_empty():break
			check(entered and phases.has("unload") and phases.has("exit"),"real truck enters/unloads/exits q%d trip%d"%[q,trip])
			check(is_equal_approx(sim.money[0]-income,100),"each trip credited once q%d trip%d"%[q,trip])
			check(int(r.get("dock_unit",-1))==-1,"dock released q%d trip%d"%[q,trip])
		sim._kill_entity(truck,false)
		var depot:int=sim._spawn(0,"kestrel_repair",Vector2(16,30),true,q)
		var d:Dictionary=sim.entities[depot]
		tank=sim._spawn(0,"kestrel_tank",O.point(d,Vector2(0,6)),true)
		sim.entities[tank].hp=float(sim.data_for("kestrel_tank").hp)*.70
		paid=sim.money[0]
		sim.issue([tank],"service",d.pos,depot)
		advance(sim,32)
		check(float(sim.entities[tank].hp)>float(sim.data_for("kestrel_tank").hp)*.95,"rotated repair bay heals actual vehicle q"+str(q))
		check(sim.money[0]<paid,"repair charged actual money")
		check(sim.entities[tank].get("refinery_docking",{}).is_empty(),"repair vehicle exits and releases bay")
		var airfield:int=sim._spawn(0,"kestrel_airfield",Vector2(35.5,10.5),true,q)
		var slots:Array[Vector2]=sim.AircraftOperations.slots(sim,sim.entities[airfield])
		check(slots[0].is_equal_approx(O.point(sim.entities[airfield],Vector2(-1.6,-1.6))),"airport first parking slot rotates q"+str(q))
		var save_sim=Sim.new();save_sim.setup(RulesLoader.load_rules(),"dev",441,"kestrel",false,{"vision_enabled":false})
		var saved_factory:int=save_sim._spawn(0,"kestrel_factory",Vector2(25,16),true,q)
		var save:String="user://orientation_q%d.save"%q
		check(save_sim.save_game(save).is_empty(),"save q"+str(q))
		var loaded=Sim.new()
		var load_error:String=loaded.load_game(save)
		check(load_error.is_empty(),"load q%d %s"%[q,load_error])
		if load_error.is_empty():check(O.quarters(loaded.entities[saved_factory])==q and O.front(loaded.entities[saved_factory]).is_equal_approx(O.front(save_sim.entities[saved_factory])),"save preserves real rotated outlet")
		var saved:Dictionary=FileAccess.open(save,FileAccess.READ).get_var(false)
		for bad in [4,1.5,45]:
			saved.entities[saved_factory].rotation_quarters=bad
			var broken:String="user://orientation_invalid.save"
			var handle:=FileAccess.open(broken,FileAccess.WRITE);handle.store_var(saved,false);handle.close()
			check(not Sim.new().load_game(broken).is_empty(),"invalid orientation rejected: "+str(bad))
		saved.entities[saved_factory].erase("rotation_quarters")
		var legacy_file:=FileAccess.open("user://orientation_legacy.save",FileAccess.WRITE);legacy_file.store_var(saved,false);legacy_file.close()
		var legacy=Sim.new()
		check(legacy.load_game("user://orientation_legacy.save").is_empty(),"old saves without orientation remain readable")
		check(O.quarters(legacy.entities[saved_factory])==0,"missing building orientation defaults to zero")
		records.append({"q":q,"factory":b.pos,"outlet":sim._spawn_point(b,"kestrel_tank"),"refinery_outlet":sim.RefineryDocking.entrance(sim,{"id":-1,"spec":"kestrel_harvester","team":0,"radius":1.0},r)})
		await process_frame
	for q in range(4):
		var sea=fixture()
		for y in range(20,41):
			for x in range(20,41):sea.map.terrain[y][x]=MapData.WATER
		sea._prepare_terrain_cache()
		sea._spawn(0,"kestrel_factory",Vector2(12,33),true)
		var yard:int=sea._spawn(0,"kestrel_shipyard",Vector2(30,30),true,q)
		var ship_exit:Vector2=sea._spawn_point(sea.entities[yard],"kestrel_ship_transport")
		var expected:Vector2=O.offset(Vector2.RIGHT,q)
		check(ship_exit.is_finite() and (ship_exit-sea.entities[yard].pos).normalized().is_equal_approx(expected),"shipyard outlet follows rotated slipway q"+str(q))
		check(sea.produce(yard,"kestrel_ship_transport").is_empty(),"ship production uses real paid queue q"+str(q))
		advance(sea,35)
		var vessel:int=-1
		for e in sea.entities.values():
			if e.spec=="kestrel_ship_transport":vessel=int(e.id)
		check(vessel>0,"ship really launches q"+str(q))
		if vessel>0:check((sea.entities[vessel].pos-sea.entities[yard].pos).dot(expected)>2.0,"launched ship is outside its selected mouth")
		var rail_sim=fixture("iron")
		var depot:int=rail_sim._spawn(0,"iron_refinery",Vector2(31.5,31.5),true,q)
		var d:Dictionary=rail_sim.entities[depot];d.gift_pending=false
		var outlet:Vector2=rail_sim._rail_network.exit_cell(rail_sim,d)
		check((outlet-d.pos).dot(O.front(d))>=float(rail_sim.data_for(d.spec).size)*.5+1.15,"rail outlet rounds outward q"+str(q))
		for j in range(4):rail_sim._spawn(0,"iron_rail",outlet+O.front(d)*j,true)
		rail_sim._rail_network.rebuild(rail_sim)
		var miner:int=rail_sim._spawn(0,"iron_harvester",outlet+O.front(d)*3,true)
		for trip in range(2):
			var cash:float=rail_sim.money[0]
			var e:Dictionary=rail_sim.entities[miner];e.cargo=100;e.harvest_refinery=depot;e.commands=[]
			advance(rail_sim,24)
			check(is_equal_approx(rail_sim.money[0]-cash,100),"rail miner unloads exactly once q%d trip%d"%[q,trip])
			check(e.get("refinery_docking",{}).is_empty(),"rail miner clears rotated refinery q%d trip%d"%[q,trip])
		await process_frame
	# Paid rail batch extension in both directions from the same original rail.
	var sim=fixture("iron")
	var anchor:Vector2=Vector2(22.5,23.5)
	sim._spawn(0,"iron_rail",anchor,true);sim._rail_network.rebuild(sim)
	for q in [0,2]:
		check(sim.build(0,"iron_rail").is_empty(),"pay for rail seed q"+str(q))
		sim.rotate_build_order(0,q,"defense");advance(sim,1)
		var target:Vector2=anchor+O.offset(Vector2.RIGHT,q)*3
		check(sim.defense_extension(0,target,"defense").size()==3,"selected direction yields three actual rail cells q"+str(q))
		var cash:float=sim.money[0]
		var result:String=sim.place_building(0,target,"defense")
		check(result.is_empty(),"place rail in rotated direction "+str(q)+" "+result)
		check(is_equal_approx(cash-sim.money[0],50),"extra two railway cells really charged")
		advance(sim,2)
		check(not sim._rail_network.at(0,target).is_empty(),"track reaches selected side")
	check(sim._rail_network.path(0,anchor+Vector2(-3,0),anchor+Vector2(3,0)).size()==7,"both extensions form a real usable owner rail route")
	DirAccess.make_dir_recursive_absolute("res://artifacts/building_orientation")
	FileAccess.open("res://artifacts/building_orientation/mechanics.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"records":records},"  "))
	print("BUILDING_ORIENTATION ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
