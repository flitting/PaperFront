extends "res://tests/v3_air_naval_tests.gd"
const Wiki=preload("res://scripts/wiki_catalog.gd")
const Launch=preload("res://scripts/carrier_launch.gd")
func run()->void:
	rules=RulesLoader.load_rules("res://data/rules.json",false)
	check(not rules.is_empty(),"naval differentiation rules parse")
	if rules.is_empty():finish();return
	var wanted:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://artifacts/v4_naval_rosters.json"))
	for faction:String in wanted:
		var sim=Sim.new();sim.setup(rules,"dev",7,faction,false)
		sim.money[0]=100000
		var factory:int=sim._spawn(0,faction+"_factory",Vector2(8,26),true)
		var yard:int=sim._spawn(0,faction+"_shipyard",Vector2(24,38),true)
		sim._spawn(0,faction+"_tech",Vector2(38,26),true)
		var shown:Dictionary={}
		for entry:Dictionary in Wiki.entries(rules,faction,"unit"):
			if str(entry.spec.get("domain",""))=="naval":shown[entry.id]=true
		check(shown.size()==wanted[faction].size(),faction+" exact visible naval catalog size")
		for spec:String in rules.units:
			var info:Dictionary=rules.units[spec]
			if info.faction!=faction or info.get("domain","")!="naval":continue
			var hidden:bool=bool(info.get("roster_hidden",false))
			check(shown.has(spec)!=hidden,spec+" wiki matches purchasability")
			var money:float=sim.money[0]
			var error:String=sim.produce(yard,spec)
			check(error.is_empty()!=hidden,spec+" actual shipyard purchase gate")
			check((sim.money[0]==money)==hidden,spec+" correct paid/rejected amount")
			if info.get("amphibious",false):
				error=sim.produce(factory,spec)
				check(error.is_empty()!=hidden,spec+" actual factory purchase gate")
			if hidden:
				var old:Dictionary=sim.rules.units[spec].duplicate(true)
				sim.rules.units[spec].erase("roster_hidden")
				check(sim.produce(yard,spec).is_empty(),spec+" old snapshot without roster flag remains available")
				sim.rules.units[spec]=old
	for native:bool in [false,true]:
		test_launch(native)
		test_launch_blocked(native)
		test_dedicated_aa(native)
	test_launch_save()
	finish()
func test_launch(native:bool)->void:
	var sim=fixture(native)
	var carrier:int=sim._spawn(0,"kestrel_carrier",Vector2(23,31),true)
	var target:int=sim._spawn(1,"rivet_tank",Vector2(37,31),true)
	var ship:Dictionary=sim.entities[carrier]
	ship.alpha=90.0
	Expansion.carrier_fire(sim,ship,target)
	var planes:Array=sim.entities.values().filter(func(e):return int(e.get("carrier_id",-1))==carrier)
	check(planes.size()==1 and int(ship.carrier_pending_count)==1,"one deck aircraft launches at a time "+str(native))
	if planes.is_empty():return
	var first:int=int(planes[0].id)
	var start:Vector2=planes[0].pos
	check(start.distance_to(Launch.deck_position(ship,Launch.RUN_START))<.001,"logical spawn lies on stern runway")
	check(absf(sim.entities[first].flight_height-Launch.deck_height(sim,ship,start))<.001,"real deck height includes water depth")
	var roll_moved:bool=false;var climbed:bool=false;var separated:bool=true;var moved_ship:bool=false
	for frame in range(65):
		var old:Vector2=ship.pos
		ship.pos+=Vector2(0,.04)
		sim._spatial_move(ship,old,ship.pos)
		moved_ship=moved_ship or ship.pos.distance_to(Vector2(23,31))>1
		sim.step(.05)
		if sim.entities.has(first):
			var plane:Dictionary=sim.entities[first]
			if plane.has("carrier_launch"):
				var progress:float=float(plane.carrier_launch.elapsed)
				var local:Vector2=((plane.pos as Vector2)-(ship.pos as Vector2)).rotated(-deg_to_rad(float(ship.alpha)))
				if progress>.2 and progress<1.1:roll_moved=roll_moved or local.x>Launch.RUN_START.x+.1
				if progress>1.5:climbed=climbed or float(plane.flight_height)>Launch.deck_height(sim,ship,plane.pos)+.5
		planes=sim.entities.values().filter(func(e):return int(e.get("carrier_id",-1))==carrier)
		if planes.size()==2:separated=separated and (planes[0].pos as Vector2).distance_to(planes[1].pos)>=2.0-.001
	check(roll_moved and climbed and moved_ship,"visible roll+climb follow moving carrier "+str(native))
	check(separated,"staged launch retains collision clearance "+str(native))
	check(planes.size()==2,"two aircraft complete staged launch")
	check(sim.entities.has(first) and not sim.entities[first].has("carrier_launch"),"first aircraft transitions to normal flight")

func test_launch_blocked(native:bool)->void:
	var sim=fixture(native)
	var carrier:int=sim._spawn(0,"kestrel_carrier",Vector2(23,31),true)
	var target:int=sim._spawn(1,"rivet_tank",Vector2(37,31),true)
	var ship:Dictionary=sim.entities[carrier]
	ship.alpha=0
	var blocked:Vector2=Launch.deck_position(ship,Launch.RUN_START)
	var helicopter:int=sim._spawn(0,"kestrel_helicopter",blocked,true)
	sim.entities[helicopter].cooldown=1000.0
	Expansion.carrier_fire(sim,ship,target)
	tick(sim,.3)
	var planes:Array=sim.entities.values().filter(func(e):return int(e.get("carrier_id",-1))==carrier)
	check(planes.is_empty() and int(ship.carrier_pending_count)==2,"blocked runway keeps both flights pending "+str(native))
	check(int(ship.carrier_ready)==2,"blocked takeoff consumes no available aircraft")
	sim._kill_entity(helicopter,false)
	var launched:Dictionary=wait_launches(sim,carrier)
	check(launched.ids.size()==2 and int(ship.carrier_pending_count)==0,"cleared runway releases both staged sorties "+str(native))
	check(launched.complete.size()==2,"both aircraft complete takeoff after obstruction clears")

func test_launch_save()->void:
	var sim=Sim.new();sim.setup_multiteam(rules,"islands",31,["kestrel","rivet"],false)
	var harbor:Dictionary={}
	for place:Dictionary in sim.map.harbors:
		if place.role=="home" and int(place.team)==0:harbor=place;break
	var carrier:int=sim.debug_spawn(0,"kestrel_carrier",harbor.water_pos)
	var target:int=sim.debug_spawn(1,"rivet_ship_frigate",harbor.water_pos+Vector2(8,8))
	check(carrier>0 and target>0,"real island water hosts carrier save fixture")
	if carrier<0 or target<0:return
	var ship:Dictionary=sim.entities[carrier]
	ship.alpha=0
	sim.entities[target].cooldown=1000.0
	Expansion.carrier_fire(sim,ship,target)
	tick(sim,.2)
	var planes:Array=sim.entities.values().filter(func(e):return int(e.get("carrier_id",-1))==carrier)
	check(planes.size()==1 and int(ship.carrier_pending_count)==1,"saved deck roll has one plane and one waiting sortie")
	if planes.is_empty():return
	var first:int=int(planes[0].id)
	var elapsed:float=float(planes[0].carrier_launch.elapsed)
	var height:float=float(planes[0].flight_height)
	check(height<0 and elapsed>0 and elapsed<1.15,"save occurs during actual below-terrain deck roll")
	var path:String="user://v4_carrier_rolling.save"
	check(sim.save_game(path).is_empty(),"rolling carrier snapshot writes")
	var loaded=Sim.new();var error:String=loaded.load_game(path)
	check(error.is_empty(),"rolling carrier snapshot validates "+error)
	if not error.is_empty():return
	check(is_equal_approx(float(loaded.entities[first].flight_height),height) and is_equal_approx(float(loaded.entities[first].carrier_launch.elapsed),elapsed) and int(loaded.entities[carrier].carrier_pending_count)==1,"save preserves height elapsed and staged second plane")
	var launched:Dictionary=wait_launches(loaded,carrier)
	check(launched.ids.size()==2 and launched.ids.has(first) and int(loaded.entities[carrier].carrier_pending_count)==0,"restored flight launches second plane without duplicate or loss")
	check(launched.complete.size()==2,"restored deck roll reaches normal flight")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func wait_launches(sim,carrier:int)->Dictionary:
	var ids:Dictionary={};var complete:Dictionary={}
	var initial:float=sim.time
	for frame in range(200):
		sim.step(.05)
		for plane:Dictionary in sim.entities.values():
			if int(plane.get("carrier_id",-1))!=carrier:continue
			ids[int(plane.id)]=true
			if not complete.has(int(plane.id)) and not plane.has("carrier_launch") and is_equal_approx(float(plane.flight_height),float(sim.data_for(plane.spec).flight_height)):complete[int(plane.id)]=sim.time-initial
		if complete.size()==2:break
	var result:Dictionary={"ids":ids,"complete":complete,"elapsed":sim.time-initial}
	print("CARRIER_STAGE_COMPLETION ",JSON.stringify(result))
	return result

func test_dedicated_aa(native:bool)->void:
	var sim=fixture(native)
	var aa:int=sim._spawn(0,"kestrel_ship_aa",Vector2(24,36),true)
	var basic:int=sim._spawn(0,"kestrel_ship_frigate",Vector2(24,31),true)
	var enemy_ship:int=sim._spawn(1,"rivet_ship_frigate",Vector2(29,36),true)
	var helicopter:int=sim._spawn(1,"rivet_helicopter",Vector2(26,36),true)
	sim.entities[helicopter].cooldown=1000.0;sim.entities[enemy_ship].cooldown=1000.0
	check(sim._weapon_can_target(sim.entities[aa],helicopter) and not sim._weapon_can_target(sim.entities[aa],enemy_ship),"dedicated AA attacks air and rejects ships "+str(native))
	check(not sim._weapon_can_target(sim.entities[basic],helicopter),"basic surface escort does not duplicate AA role")
	var hp:float=float(sim.entities[helicopter].hp)
	sim.issue([aa],"attack",sim.entities[helicopter].pos,helicopter)
	tick(sim,2)
	check(not sim.entities.has(helicopter) or float(sim.entities[helicopter].hp)<hp,"dedicated AA deals actual anti-air damage "+str(native))
