extends SceneTree

const Sim = preload("res://scripts/simulation.gd")
const Tools = preload("res://scripts/developer_tools.gd")
const Rules = preload("res://scripts/rules_loader.gd")
const Maps = preload("res://scripts/map_data.gd")
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	var rules: Dictionary = Rules.load_rules()
	for seed: int in [0,73026,-37,2147483647]:
		var map: Dictionary = Maps.generate("dev",seed)
		_check(map.size == 100 and map.valid,"dev100 map legal for seed %d: %s" % [seed,map.validation_errors])
	_check(Maps.generate("dev",7,{"legacy_dev48":true}).size == 48,"legacy test geometry remains explicit")
	_test_right_bank_orientation(rules)
	for faction: String in ["kestrel","rivet","iron","sky"]:
		var sim = Sim.new()
		sim.synchronous_path_tests = true
		sim.setup(rules,"dev",73026,faction,false)
		_check(sim._segment_terrain(Vector2(42,51.5),Vector2(58,51.5)),"dev bridge has continuous height and real land crossing")
		_check(sim._segment_terrain(Vector2(22,95),Vector2(78,95)),"dev southern bypass is usable without bridge")
		_check(Tools.generate_all_buildings(sim).created.is_empty(),"disabled debug cannot generate buildings")
		sim.match_options.developer_debug_enabled = true
		var report: Dictionary = Tools.generate_all_buildings(sim)
		print(faction+" "+Tools.report_text(sim,report))
		_check(report.failed.is_empty(),faction+" catalog generation has no failed buildings: "+str(report.failed))
		for spec: String in rules.buildings:
			if str(rules.buildings[spec].faction) != faction: continue
			_check(Tools._owned(sim,0,spec) >= 0,faction+" contains "+spec)
		var power: Vector2 = sim.power(0)
		_check(power.x >= power.y,faction+" has sufficient real power")
		for a: Dictionary in sim._building_entities:
			if int(a.team) != 0 or sim.RailNetwork.is_rail(sim.data_for(a.spec)): continue
			for b: Dictionary in sim._building_entities:
				if int(b.team) != 0 or int(a.id) >= int(b.id) or sim.RailNetwork.is_rail(sim.data_for(b.spec)): continue
				var half: float = (float(sim.data_for(a.spec).size)+float(sim.data_for(b.spec).size))*.5
				_check(absf(a.pos.x-b.pos.x) >= half+2 or absf(a.pos.y-b.pos.y) >= half+2,"catalog leaves two-cell gap between %s and %s" % [a.spec,b.spec])
		var refinery: int = Tools._owned(sim,0,faction+"_factory")
		if refinery >= 0:
			var harvester: String = faction+"_tank"
			sim.money[0] = 100000
			var before: float = sim.money[0]
			_check(sim.produce(refinery,harvester).is_empty(),faction+" refinery accepts real production")
			_check(sim.money[0] == before-float(sim.data_for(harvester).cost),faction+" instant production still pays cost")
			sim.match_options.developer_instant_build = true
			Tools.finish_pending(sim)
			sim.step(1.0/30.0)
			_check(sim.entities[refinery].queue.is_empty(),faction+" instant production exits legally")
		var repeated: Dictionary = Tools.generate_all_buildings(sim)
		_check(repeated.created.is_empty() and repeated.failed.is_empty(),faction+" repeat skips existing catalog")
		_test_real_routes(sim,faction)
		# Turning debug off prevents shortening an existing production queue.
		var hq: int = Tools._owned(sim,0,faction+"_hq")
		sim.entities[hq].queue = [{"remaining":100.0,"progress":0.0,"ready":false}]
		sim.match_options.developer_debug_enabled = false
		Tools.finish_pending(sim)
		_check(sim.entities[hq].queue[0].remaining == 100.0,"debug off disables instant production")
		_test_instant_construction(rules,faction)
	print("Developer tools checks: %d passed, %d failed" % [checks-failures.size(),failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _test_right_bank_orientation(rules: Dictionary) -> void:
	var sim = Sim.new()
	sim.synchronous_path_tests = true
	sim.setup(rules,"dev",73026,"rivet",false)
	sim.match_options.developer_debug_enabled = true
	var report: Dictionary = Tools.generate_all_buildings(sim,1)
	_check(report.failed.is_empty(),"opposite bank catalog finds real legal producer orientations")
	var yard: int = Tools._owned(sim,1,"kestrel_shipyard")
	_check(yard > 0 and int(sim.entities[yard].rotation_quarters) != 0,"right bank shipyard turns away from its blocked east-facing launch direction")
	# A fresh real paid AI order must also find a usable nonzero orientation.
	if yard > 0: sim._kill_entity(yard,false)
	sim.money[1] = float(sim.data_for("kestrel_shipyard").cost)
	_check(sim.build(1,"kestrel_shipyard").is_empty(),"AI orientation fixture buys the shipyard at its full live price")
	for frame: int in range(600):
		sim.step(.1)
		if bool(sim.order_for_team(1).get("ready",false)): break
	sim.AIController._place_shipyard(sim,1)
	for frame: int in range(20): sim.step(.1)
	yard = Tools._owned(sim,1,"kestrel_shipyard")
	_check(yard > 0 and int(sim.entities[yard].rotation_quarters) != 0,"AI paid shipyard completes in a legal alternate launch orientation")
	_check(is_zero_approx(float(sim.money[1])),"alternate AI orientation neither grants funds nor discounts the shipyard")

func _test_instant_construction(rules: Dictionary,faction: String) -> void:
	var sim = Sim.new()
	sim.synchronous_path_tests = true
	sim.setup(rules,"dev",73026,faction,false)
	sim.match_options.developer_debug_enabled = true
	sim.match_options.developer_instant_build = true
	sim.money[0] = 100000
	var builder: int = -1
	if faction == "rivet": builder = sim.debug_spawn(0,"rivet_engineer",Vector2(28.5,52.5))
	var spec: String = faction+"_power"
	_check(sim.build(0,spec,builder).is_empty(),faction+" instant mode accepts genuine construction order")
	sim.step(1.0/30.0)
	_check(bool(sim.order_for_team(0).get("ready",false)),faction+" instant building order ready after one tick")
	_check(not sim.placement_error(0,sim._team_start(0)).is_empty(),faction+" instant mode still rejects occupied HQ footprint")
	_check(sim.place_building(0,Vector2(29.5,58.5)).is_empty(),faction+" genuine building placement legal")
	# Engineer construction must approach its real site. The other methods
	# deploy on the next tick; no global simulation-time jump is performed.
	for frame: int in range(300 if builder >= 0 else 1): sim.step(1.0/30.0)
	_check(Tools._owned(sim,0,spec) >= 0,faction+" instant placed building completes normally")
	_check(absf(100000.0-float(sim.money[0])-float(sim.data_for(spec).cost)) < .001,faction+" instant construction pays full actual cost once")
	var hq: int = Tools._owned(sim,0,faction+"_hq")
	sim.entities[hq].queue = [{"remaining":100.0}]
	sim.map.mode = "handmade"
	Tools.finish_pending(sim)
	_check(sim.entities[hq].queue[0].remaining == 100.0,"normal battle ignores instant flags even if restored from debug")

func _test_real_routes(sim,faction: String) -> void:
	var tank: int = sim.debug_spawn(0,faction+"_tank",Vector2(40,51.5))
	_check(tank > 0 and is_equal_approx(sim._radius(sim.entities[tank]),1.0),faction+" real two-cell tank spawns by bridge")
	if tank > 0:
		sim.issue([tank],"move",Vector2(60,51.5))
		for frame: int in range(400):
			sim.step(.05)
			if sim.entities[tank].pos.distance_to(Vector2(60,51.5)) < .7: break
		_check(sim.entities[tank].pos.distance_to(Vector2(60,51.5)) < .7,faction+" real two-cell tank physically crosses bridge")
	var transport_spec: String = ""
	for spec: String in sim.rules.units:
		var info: Dictionary = sim.rules.units[spec]
		if str(info.faction) == faction and str(info.get("domain","ground")) == "naval" and int(info.get("transport_capacity",0)) > 0 and not bool(info.get("roster_hidden",false)) and not bool(info.get("internal_only",false)):
			transport_spec = spec
			break
	_check(not transport_spec.is_empty(),faction+" current public naval roster supplies a real troop transport")
	if transport_spec.is_empty(): return
	var transport: int = sim.debug_spawn(0,transport_spec,Vector2(38,80))
	var soldier: int = sim.debug_spawn(0,faction+"_rifle",Vector2(29.5,74.5))
	_check(transport > 0 and soldier > 0,faction+" real transport and passenger spawn beside catalog dock")
	if transport < 0 or soldier < 0: return
	var request: Dictionary = preload("res://scripts/transport_commands.gd").board(sim,[soldier],transport,false)
	_check(str(request.error).is_empty() and request.passengers.size() == 1,faction+" genuine embark order accepted")
	for frame: int in range(600):
		sim.step(.05)
		if int(sim.entities[soldier].transport_id) == transport: break
	_check(int(sim.entities[soldier].transport_id) == transport,faction+" infantry physically embarks from developer shore")
	if int(sim.entities[soldier].transport_id) != transport: return
	sim.issue([transport],"unload_move",Vector2(70.5,74.5))
	for frame: int in range(900):
		sim.step(.05)
		if int(sim.entities[soldier].transport_id) < 0: break
	_check(int(sim.entities[soldier].transport_id) < 0 and sim.entities[soldier].pos.x > 60,faction+" carrier sails basin and physically unloads at opposite shore")
