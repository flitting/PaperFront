extends SceneTree
const Sim=preload("res://tests/rule_test_simulation.gd")
const Expansion=preload("res://scripts/air_naval_expansion.gd")
const Amphib=preload("res://scripts/amphibious_navigation.gd")
const Models=preload("res://scripts/air_naval_models.gd")
const Volume=preload("res://scripts/volume_models.gd")
var rules:Dictionary
var checks:int=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func _initialize()->void:call_deferred("run")
func tick(sim,seconds:float)->void:
	for i in range(ceili(seconds*20)):sim.step(.05)
func fixture(native:bool=false):
	var sim=Sim.new()
	sim.setup_multiteam(rules,"dev",7,["kestrel","rivet"],false)
	sim.native_kernels_enabled=native
	sim.vision_enabled=false
	for id in sim.entities.keys():sim._kill_entity(int(id),false)
	sim.ruins.clear();sim.mines.clear();sim.bridges.clear()
	sim.map.bridges=[];sim.map.mines=[];sim.map.decorations=[]
	for z in range(int(sim.map.size)):
		for x in range(int(sim.map.size)):
			sim.map.terrain[z][x]=1 if x>=16 and x<32 else 0
			sim.map.heights[z][x]=0.0 if x>=16 and x<32 else -2.4
	sim._spawn(0,"kestrel_hq",Vector2(6,7),true)
	sim._spawn(1,"rivet_hq",Vector2(41,7),true)
	sim.NavalOperations.initialize(sim)
	sim._nav_dirty=true;sim._rebuild_nav();sim._rebuild_spatial()
	sim.money.assign([100000.0,100000.0])
	sim.result=""
	return sim
func run()->void:
	rules=RulesLoader.load_rules("res://data/rules.json",false)
	check(not rules.is_empty(),"schema: "+str(RulesLoader.errors))
	if rules.is_empty():finish();return
	for faction in rules.factions:
		var count:int=0
		for info:Dictionary in rules.units.values():
			if info.faction==faction and info.get("domain","")=="air" and not info.get("internal_only",false):count+=1
		check(count>=4,"four buildable aircraft "+faction)
		for art in ["helicopter","naval_submarine","naval_amphibious","naval_hovercraft","naval_support","naval_carrier"]:
			var model:Dictionary=Models.make(Volume.CraftMesh.new(),art,faction,0,"unit")
			check(not model.is_empty() and model.body_mesh.get_surface_count()>0,"solid silhouette "+faction+art)
	for native in [false,true]:
		test_flight(native)
		test_amphibious(native)
		test_submarine(native)
		test_carrier(native)
	test_island_shore()
	test_save()
	finish()
func test_flight(native:bool)->void:
	var sim=fixture(native)
	var heli:int=sim._spawn(0,"kestrel_helicopter",Vector2(10,30),true)
	var zepp:int=sim._spawn(1,"rivet_zeppelin",Vector2(35,40),true)
	sim.entities[heli].ammo=0;sim.entities[zepp].ammo=0
	tick(sim,.2)
	check(sim.entities[heli].airborne and sim.entities[zepp].airborne,"permanent airborne "+str(native))
	check(sim.entities[heli].home_airfield<0 and sim.entities[heli].ammo>0,"heli no airport ammo dependency")
	check(not sim.AircraftOperations.land_error(sim,sim.entities[zepp],Vector2(35,40)).is_empty(),"zeppelin cannot land")
	var enemy:int=sim._spawn(1,"rivet_tank",Vector2(13,30),true)
	var old_hp:float=sim.entities[enemy].hp
	sim.issue([heli],"attack",sim.entities[enemy].pos,enemy)
	tick(sim,3)
	check(not sim.entities.has(enemy) or sim.entities[enemy].hp<old_hp,"helicopter fires without rearm")
	check(sim.entities[heli].ammo>0 and sim.entities[heli].flight_state=="airborne","unlimited ammunition actually retained")
	if sim.entities.has(enemy):sim._kill_entity(enemy,false)
	var plane:int=sim._spawn(0,"kestrel_recon",Vector2(10,20),true)
	var start:Vector2=sim.entities[plane].pos
	tick(sim,1.0)
	check(sim.entities[plane].pos.distance_to(start)>1,"fixed wing circles while idle "+str(native))
	sim.issue([plane],"hold",sim.entities[plane].pos)
	start=sim.entities[plane].pos;tick(sim,1.0)
	check(sim.entities[plane].pos.distance_to(start)>1,"hold is orbit "+str(native))
	sim.issue([plane],"move",Vector2(36,20))
	for i in range(150):
		sim.step(.05)
		if sim.entities[plane].commands.is_empty():break
	check(sim.entities[plane].pos.distance_to(Vector2(36,20))<.3,"ordered flight unaffected by orbit")
func test_amphibious(native:bool)->void:
	var sim=fixture(native)
	var unit:int=sim._spawn(0,"kestrel_amphibious",Vector2(10,30),true)
	var previous:Vector2=sim.entities[unit].pos
	sim.issue([unit],"move",Vector2(38,30))
	var swept:bool=true
	for i in range(220):
		sim.step(.05)
		var point:Vector2=sim.entities[unit].pos
		swept=swept and Amphib.segment_clear(sim,previous,point,1.0,unit,false)
		previous=point
	check(sim.entities[unit].pos.distance_to(Vector2(38,30))<.4,"amphib crosses both shores "+str(native))
	check(swept,"every amphib step preserves full radius")
	check(sim._target_domain(sim.entities[unit])=="ground","amphib exposes ground domain on land")
	var wall:int=sim._spawn(0,"kestrel_wall",Vector2(22,30),true)
	check(not Amphib.segment_clear(sim,Vector2(20,30),Vector2(24,30),1.0,unit,false),"shore path rejects solid wall")
	sim._kill_entity(wall,false)
	var hover:int=sim._spawn(0,"kestrel_hovercraft",Vector2(10,37),true)
	var soldier:int=sim._spawn(0,"kestrel_rifle",Vector2(7.5,37),true)
	sim.issue([soldier],"board",sim.entities[hover].pos,hover)
	tick(sim,3)
	check(int(sim.entities[soldier].get("transport_id",-1))==hover,"hovercraft real embark "+str(native))
	sim.issue([hover],"unload_move",Vector2(38,37))
	tick(sim,9)
	check(int(sim.entities[soldier].get("transport_id",-1))<0 and sim.entities[soldier].pos.x>32,"hovercraft crosses and disembarks "+str(native))
	var factory:int=sim._spawn(1,"rivet_factory",Vector2(8,17),true)
	var yard:int=sim._spawn(1,"rivet_shipyard",Vector2(24,17),true)
	check(sim.availability(1,"rivet_amphibious",-1,factory).is_empty(),"factory offers amphibious")
	check(sim.availability(1,"rivet_amphibious",-1,yard).is_empty(),"shipyard offers amphibious")
	check(sim.produce(factory,"rivet_amphibious").is_empty(),"factory accepts real order")
	check(sim.produce(yard,"rivet_amphibious").is_empty(),"shipyard accepts real order")
	tick(sim,80)
	var factory_spawn:bool=false;var ship_spawn:bool=false
	for e:Dictionary in sim.entities.values():
		if e.spec=="rivet_amphibious" and sim._terrain(e.pos)!=MapData.WATER:factory_spawn=true
		if e.spec=="rivet_amphibious" and sim._terrain(e.pos)==MapData.WATER:ship_spawn=true
	check(factory_spawn and ship_spawn,"both production queues deliver")
func test_submarine(native:bool)->void:
	var sim=fixture(native)
	var sub:int=sim._spawn(1,"rivet_submarine",Vector2(25,27),true)
	var tank:int=sim._spawn(0,"kestrel_amphibious",Vector2(18,27),true)
	check(not sim._weapon_can_target(sim.entities[tank],sub),"ordinary weapon cannot shoot submerged submarine")
	var frigate:int=sim._spawn(0,"kestrel_ship_frigate",Vector2(20,31),true)
	check(Expansion.detected(sim,0,sim.entities[sub]),"escort sonar detects submarine")
	check(sim._weapon_can_target(sim.entities[frigate],sub),"escort has real ASW target permission")
	var hp:float=sim.entities[sub].hp
	sim.issue([frigate],"attack",sim.entities[sub].pos,sub)
	tick(sim,4)
	check(not sim.entities.has(sub) or sim.entities[sub].hp<hp,"ASW deals real damage "+str(native))
func test_carrier(native:bool)->void:
	var sim=fixture(native)
	var carrier:int=sim._spawn(0,"kestrel_carrier",Vector2(24,34),true)
	var target:int=sim._spawn(1,"rivet_tank",Vector2(37,34),true)
	var hp:float=sim.entities[target].hp
	sim.issue([carrier],"attack",sim.entities[target].pos,target)
	tick(sim,2.0)
	var planes:Array=sim.entities.values().filter(func(e):return int(e.get("carrier_id",-1))==carrier)
	check(planes.size()==2,"carrier launches two actual aircraft "+str(native))
	if not planes.is_empty():check(sim._target_domain(planes[0])=="air","carrier plane vulnerable to AA")
	tick(sim,10)
	check(not sim.entities.has(target) or sim.entities[target].hp<hp,"carrier airstrike inflicts damage "+str(native))
	if sim.entities.has(target):sim._kill_entity(target,false)
	tick(sim,5)
	planes=sim.entities.values().filter(func(e):return int(e.get("carrier_id",-1))==carrier)
	check(planes.is_empty() and int(sim.entities[carrier].get("carrier_ready",0))==2,"carrier recovers airwing "+str(native))
func test_island_shore()->void:
	var sim=Sim.new();sim.setup_multiteam(rules,"islands",31,["kestrel","rivet"],false)
	for harbor:Dictionary in sim.map.harbors:
		if harbor.role!="home":continue
		var team:int=int(harbor.team)
		var id:int=sim._spawn(team,sim.factions[team]+"_amphibious",harbor.land_pos,true)
		sim.issue([id],"move",harbor.water_pos)
		tick(sim,7)
		check(sim.entities[id].pos.distance_to(harbor.water_pos)<.4,"real authored island beach crossed team "+str(team))
func test_save()->void:
	var sim=Sim.new();sim.setup(rules,"dev",7,"rivet",false)
	var id:int=sim._spawn(0,"rivet_helicopter",Vector2(12,30),true)
	var carrier:int=sim._spawn(0,"rivet_carrier",Vector2(18,35),true)
	var target:int=sim._spawn(1,"kestrel_tank",Vector2(32,35),true)
	Expansion.carrier_fire(sim,sim.entities[carrier],target)
	var planes:Array=sim.entities.values().filter(func(e):return int(e.get("carrier_id",-1))==carrier)
	check(planes.size()==1 and int(sim.entities[carrier].carrier_pending_count)==1,"save fixture contains a rolling plane and queued launch")
	check(sim.save_game("user://v3_airnaval.save").is_empty(),"air naval save writes")
	var loaded=Sim.new();var error:String=loaded.load_game("user://v3_airnaval.save")
	check(error.is_empty(),"air naval snapshot validates: "+error)
	if error.is_empty():
		tick(loaded,.2)
		check(loaded.entities[id].airborne,"permanent flight survives load")
		var restored:Array=loaded.entities.values().filter(func(e):return int(e.get("carrier_id",-1))==carrier)
		check(restored.size()==1 and int(loaded.entities[carrier].carrier_ready)==1 and int(loaded.entities[carrier].carrier_pending_count)==1,"carrier deck roll and pending sortie survive load")
func finish()->void:
	print("V3_AIR_NAVAL ",JSON.stringify({"checks":checks,"failures":failures}))
	for message in failures:push_error(message)
	quit(0 if failures.is_empty() else 1)
