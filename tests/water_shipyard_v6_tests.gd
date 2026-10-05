extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const Operations = preload("res://scripts/naval_operations.gd")
const Saves = preload("res://scripts/sim_save_validator.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func footprint_water(sim, point: Vector2, size: int = 4) -> bool:
	var origin := Vector2i(roundi(point.x-size*.5),roundi(point.y-size*.5))
	for z in range(origin.y,origin.y+size):
		for x in range(origin.x,origin.x+size):
			if x<0 or z<0 or x>=sim.map.size or z>=sim.map.size or int(sim.map.terrain[z][x]) != MapData.WATER: return false
	return true

func find_site(sim, team: int, info: Dictionary, water: bool = true) -> Vector2:
	for harbor: Dictionary in sim.map.get("harbors", []):
		if int(harbor.get("team",-1)) != team or harbor.get("role") != "home": continue
		var center: Vector2 = harbor.water_pos if water else harbor.shore_pos
		for ring in range(21):
			for step in range(1 if ring==0 else 24):
				var wanted: Vector2 = center+Vector2.from_angle(TAU*float(step)/24.0)*float(ring)*.9
				var point := Vector2(roundf(wanted.x),roundf(wanted.y))
				if Operations.shipyard_site_error(sim,team,info,point).is_empty(): return point
	return Vector2.INF

func snapshot(sim) -> Dictionary:
	var path := "user://v6_water_shipyard_test.pfront"
	check(sim.save_game(path).is_empty(), "shipyard snapshot writes")
	var file := FileAccess.open(path,FileAccess.READ)
	var state: Dictionary = file.get_var(false)
	file.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return state

func run() -> void:
	var rules: Dictionary = RulesLoader.load_rules("res://data/rules.json",false)
	check(not rules.is_empty(), "current water shipyard rules validate")
	if rules.is_empty():
		failures.append(str(RulesLoader.errors)); finish(); return
	for faction: String in ["kestrel","rivet","iron","sky"]:
		var info: Dictionary = rules.buildings[faction+"_shipyard"]
		check(info.get("domain") == "naval", faction+" shipyard uses naval surface")
		var sim = Sim.new()
		sim.setup(rules,"islands",17,faction,false)
		var home: Dictionary = home_harbor(sim,0)
		var enemy_home: Dictionary = home_harbor(sim,1)
		var site: Vector2 = find_site(sim,0,info)
		check(site.is_finite(), faction+" protected home harbor admits all-water yard")
		if not site.is_finite(): continue
		check(footprint_water(sim,site), faction+" every footprint cell is independently verified water")
		var legacy_info: Dictionary = info.duplicate(true)
		legacy_info.erase("domain"); legacy_info.coast_split = .5
		var coast: Vector2 = find_site(sim,0,legacy_info,false)
		check(coast.is_finite() and not footprint_water(sim,coast), faction+" legacy coast fixture remains mixed")
		if coast.is_finite(): check(not Operations.shipyard_site_error(sim,0,info,coast).is_empty(), faction+" new placement rejects old mixed footprint")
		check(not Operations.shipyard_site_error(sim,0,info,sim._team_start(0)).is_empty(), faction+" inland placement rejected")
		check(not Operations.shipyard_site_error(sim,0,info,Vector2(-2,site.y)).is_empty(), faction+" boundary placement rejected")
		var harbors: Array = sim.map.harbors
		sim.map.harbors = []
		check(not Operations.shipyard_site_error(sim,0,info,site).is_empty(), faction+" open sea does not bypass construction range")
		sim.map.harbors = harbors
		var factory: int = sim.debug_spawn(0,faction+"_factory",sim._team_start(0)+Vector2(0,8))
		check(factory>0, faction+" real prerequisite factory exists")
		var before: float = sim.money[0]
		check(sim.build(0,faction+"_shipyard").is_empty(), faction+" shipyard enters normal paid construction")
		check(is_equal_approx(before-sim.money[0],float(info.cost)), faction+" normal shipyard price charged")
		sim.step(80.0)
		check(bool(sim.order_for_team(0).get("ready",false)), faction+" shipyard construction finishes normally")
		check(sim.place_building(0,site).is_empty(), faction+" real water placement succeeds")
		var yard_id: int = -1
		for e in sim.entities.values():
			if e.team==0 and e.spec==faction+"_shipyard": yard_id=int(e.id)
		check(yard_id>0, faction+" completed order creates a shipyard entity")
		if yard_id<1: continue
		var yard: Dictionary = sim.entities[yard_id]
		check(sim._target_domain(yard)=="ground" and not sim._is_naval(yard), faction+" building keeps ground combat domain")
		check(is_equal_approx(sim._source_height(yard),-2.65) and is_equal_approx(sim._target_height(yard_id),-1.55), faction+" projectiles and death offset follow water surface")
		check(not Operations.shipyard_site_error(sim,0,info,site).is_empty(), faction+" another building cannot overlap occupied yard")
		check(not Operations._nav(sim).water_clear(sim,site,.8,1.35,-1,false), faction+" yard footprint blocks ship movement")
		check(not sim._building_clear(site,.8,-1), faction+" script building geometry blocks its footprint")
		sim.step(2.0)
		if sim._kernels != null:
			check(not sim._kernels.building_clear(site,.8,-1), faction+" native building geometry agrees")
		for role: String in ["transport","frigate","signature"]:
			var spec: String = faction+"_ship_"+role
			var spawn: Vector2 = Operations.spawn_point(sim,yard,spec)
			check(spawn.is_finite() and Operations._nav(sim).water_clear(sim,spawn,float(sim.data_for(spec).radius),float(sim.data_for(spec).naval_air_draft),-1,true), faction+" "+role+" has a legal whole-hull exit")
		var ship_spec: String = faction+"_ship_transport"
		before = sim.money[0]
		check(sim.produce(yard_id,ship_spec).is_empty(), faction+" transport uses normal paid production")
		check(is_equal_approx(before-sim.money[0],float(sim.data_for(ship_spec).cost)), faction+" normal ship price charged once")
		sim.step(60.0)
		var produced: Dictionary = {}
		for e in sim.entities.values():
			if e.team==0 and e.spec==ship_spec: produced=e;break
		check(not produced.is_empty() and yard.queue.is_empty(), faction+" completed transport really leaves water yard")
		if not produced.is_empty():
			check(not Operations.coast_pair(sim,produced,null,home.land_pos).is_empty(), faction+" open-water shipyard preserves reachable shore unloading")
			var soldier: int = sim.debug_spawn(0,faction+"_rifle",home.land_pos)
			sim.issue([soldier],"board",produced.pos,int(produced.id))
			for tick in range(700):
				sim.step(.1)
				if int(sim.entities[soldier].get("transport_id",-1))==int(produced.id): break
			var boarded: bool = int(sim.entities[soldier].get("transport_id",-1))==int(produced.id)
			check(boarded, faction+" produced ship physically reaches shore and boards infantry")
			if boarded:
				var shore: Vector2 = enemy_home.land_pos
				sim.issue([int(produced.id)],"unload_move",shore)
				for tick in range(2200):
					sim.step(.1)
					if int(sim.entities[soldier].get("transport_id",-1))<0: break
				check(int(sim.entities[soldier].get("transport_id",-1))<0 and sim._terrain(sim.entities[soldier].pos)!=MapData.WATER and sim.entities[soldier].pos.distance_to(shore)<24.0, faction+" paid-production transport sails across islands and unloads on actual shore")
		var state: Dictionary = snapshot(sim)
		check(Saves.check(state).is_empty(), faction+" water shipyard snapshot validates")
		var restored = Sim.new()
		var path := "user://v6_water_shipyard_restore.pfront"
		check(sim.save_game(path).is_empty() and restored.load_game(path).is_empty() and restored.entities[yard_id].pos==site, faction+" water yard save/load restores position")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		var invalid: Dictionary = rules.duplicate(true)
		invalid.buildings[faction+"_hq"].domain = "naval"
		check(not RulesLoader.validate(invalid,false).is_empty(), faction+" validator rejects naval surface on ordinary buildings")
	bridge_contract(rules)
	contact_contract(rules)
	legacy_snapshot(rules)
	finish()

func legacy_snapshot(rules: Dictionary) -> void:
	var legacy: Dictionary = rules.duplicate(true)
	for faction: String in ["kestrel","rivet","iron","sky"]:
		legacy.buildings[faction+"_shipyard"].erase("domain")
		legacy.buildings[faction+"_shipyard"].coast_split = .5
	check(RulesLoader.validate(legacy,false).is_empty(), "old coast shipyard rule snapshot still validates")
	var sim = Sim.new()
	sim.setup(legacy,"islands",31,"rivet",false)
	var site: Vector2 = find_site(sim,0,legacy.buildings.rivet_shipyard,false)
	check(site.is_finite(), "old coast yard has a valid historical site")
	if not site.is_finite(): return
	var id: int = sim._spawn(0,"rivet_shipyard",site,true)
	var path := "user://v6_legacy_coast_shipyard.pfront"
	var restored = Sim.new()
	check(sim.save_game(path).is_empty() and restored.load_game(path).is_empty(), "old mixed-coast shipyard snapshot loads without new-placement rejection")
	check(restored.entities.has(id) and restored.data_for("rivet_shipyard").get("domain","ground")=="ground", "loaded old yard preserves its historical ground surface")
	check(Operations.spawn_point(restored,restored.entities[id],"rivet_ship_transport").is_finite(), "old coast yard retains working ship exit after load")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func finish() -> void:
	print("V6_WATER_SHIPYARD ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func bridge_contract(rules: Dictionary) -> void:
	var sim = Sim.new()
	sim.setup(rules,"city",17,"rivet",false)
	check(not sim.bridges.is_empty(), "new city has actual naval passage bridges")
	for bridge: Dictionary in sim.bridges:
		var original: Dictionary = {}
		for source: Dictionary in sim.map.bridges:
			if source.id==bridge.id: original=source;break
		check(not original.is_empty() and is_equal_approx(float(bridge.get("naval_clearance",0)),float(original.get("naval_clearance",0))), "simulation preserves authored bridge clearance")
	var state: Dictionary = snapshot(sim)
	if not state.bridges.is_empty():
		var invalid: Dictionary = state.duplicate(true)
		invalid.bridges[0].naval_clearance = NAN
		check(not Saves.check(invalid).is_empty(), "snapshot rejects NaN naval bridge clearance")
		invalid.bridges[0].naval_clearance = -1.0
		check(not Saves.check(invalid).is_empty(), "snapshot rejects negative naval bridge clearance")
		invalid = state.duplicate(true)
		for bridge: Dictionary in invalid.bridges: bridge.erase("naval_clearance")
		check(Saves.check(invalid).is_empty(), "old bridge snapshots without clearance remain valid")

func contact_contract(rules: Dictionary) -> void:
	var sim = Sim.new()
	sim.setup(rules,"dev",7,"sky",false)
	var id: int = sim.debug_spawn(0,"sky_creator_hand",Vector2(12.5,40.5))
	check(id>0,"contact save test uses actual hero entity")
	if id<1:return
	var state: Dictionary = snapshot(sim)
	for field: String in ["hand_contact_height","hand_ground_height"]:
		state.entities[id][field] = -1.55
		check(Saves.check(state).is_empty(),"hero save accepts finite negative "+field)
		state.entities[id][field] = NAN
		check(not Saves.check(state).is_empty(),"hero save rejects NaN "+field)
		state.entities[id][field] = INF
		check(not Saves.check(state).is_empty(),"hero save rejects infinite "+field)
		state.entities[id][field] = 100000.0
		check(not Saves.check(state).is_empty(),"hero save rejects extreme finite "+field)
		state.entities[id].erase(field)
		check(Saves.check(state).is_empty(),"old hero save without "+field+" remains valid")

func home_harbor(sim,team:int)->Dictionary:
	for harbor:Dictionary in sim.map.harbors:
		if int(harbor.get("team",-1))==team and harbor.get("role")=="home":return harbor
	return {}
