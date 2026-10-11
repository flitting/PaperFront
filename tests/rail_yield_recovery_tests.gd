extends SceneTree
const Sim = preload("res://tests/rule_test_simulation.gd")
const Rail = preload("res://scripts/rail_network.gd")
var rules: Dictionary
var checks := 0
var failures: Array[String] = []
var evidence: Array[Dictionary] = []
func _initialize() -> void:call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label)
func fixture(native_mode: bool):
	var sim=Sim.new()
	var factions: Array[String]=["iron","kestrel"]
	sim.setup_multiteam(rules,"dev",733,factions,false)
	if sim.entities.size()!=2:
		check(false,"simulation setup completed");return null
	sim.native_kernels_enabled=native_mode;sim.native_unit_dispatch_enabled=native_mode
	sim.native_movement_enabled=native_mode;sim.native_geometry_enabled=native_mode
	sim.vision_enabled=false
	for id in sim.entities.keys():sim._kill_entity(id,false)
	for row in sim.map.terrain:row.fill(0)
	for row in sim.map.heights:row.fill(0.0)
	sim.mines.clear();sim.ruins.clear();sim.bridges.clear()
	sim._refresh_mine_spatial();sim._refresh_ruin_spatial();sim._prepare_terrain_cache()
	sim._spawn(0,"iron_hq",Vector2(6,6),true)
	sim._spawn(1,"kestrel_hq",Vector2(42,42),true)
	sim._nav_dirty=true
	return sim
func finish_fixture(sim) -> void:
	if sim._path_worker!=null:sim._path_worker.close()
func partial_cell_departure(native_mode: bool) -> void:
	var sim=fixture(native_mode)
	if sim==null:return
	for point: Vector2 in [Vector2(43.5,31.5),Vector2(43.5,32.5)]:sim._spawn(0,"iron_rail",point,true)
	sim._rail_network.rebuild(sim)
	# Same subcell geometry as the failing save, translated 60 cells north.
	var miner: int=sim._spawn(0,"iron_harvester",Vector2(43.5,31.7),true)
	var scout: int=sim._spawn(0,"iron_scout",Vector2(44.95315,30.20804),true)
	sim.issue([scout],"hold",sim.entities[scout].pos)
	sim._rebuild_spatial()
	var unit: Dictionary=sim.entities[miner]
	var origin: Vector2=unit.pos
	var goal:=Vector2(43.5,32.5)
	var route: Array=sim._rail_network.traversable_path(sim,unit,origin,goal)
	var label: String=" native="+str(native_mode)
	check(not route.is_empty() and (route[0] as Vector2).is_equal_approx(goal),"partial rail origin does not backtrack to a passed center"+label)
	check(sim._movement_clear(unit,origin,origin+Vector2(0,.1)),"forward first stride has actual collision clearance"+label)
	check(not sim._movement_clear(unit,origin,Vector2(43.5,31.5)),"backtracking first stride is genuinely obstructed by off-rail scout"+label)
	sim.issue([miner],"move",goal)
	var speed_ok:=true
	var rail_ok:=true
	var separation_ok:=true
	var scout_origin: Vector2=sim.entities[scout].pos
	for frame in range(30):
		var before: Vector2=unit.pos
		sim.step(.05)
		speed_ok=speed_ok and before.distance_to(unit.pos)<=float(sim.data_for(unit.spec).speed)*2.0*.05+.0001
		rail_ok=rail_ok and not sim._rail_network.at(0,unit.pos).is_empty()
		separation_ok=separation_ok and (unit.pos as Vector2).distance_to(sim.entities[scout].pos)>=sim._radius(unit)+sim._radius(sim.entities[scout])-.001
		sim.events.clear()
	check((unit.pos as Vector2).distance_to(goal)<.01,"rail miner physically advances away from the scout"+label)
	check(speed_ok and rail_ok and separation_ok,"continuous movement retains rail speed, owner rail and body clearance"+label)
	check((sim.entities[scout].pos as Vector2).is_equal_approx(scout_origin),"held off-rail blocker is not moved"+label)
	evidence.append({"scenario":"partial_source_cell","native":native_mode,"route":str(route),"origin":str(origin),"final":str(unit.pos),"speed_ok":speed_ok,"owner_rail_ok":rail_ok,"separation_ok":separation_ok})
	finish_fixture(sim)
func rail_only_yield(native_mode: bool,own_retreat: bool) -> void:
	var sim=fixture(native_mode)
	if sim==null:return
	sim._spawn(0,"iron_rail",Vector2(43.5,31.5),true)
	if own_retreat:sim._spawn(0,"iron_rail",Vector2(43.5,32.5),true)
	# Ownership adversary: a terrain-valid retreat near the source lies on
	# enemy track. It must never grant this owner a rail movement destination.
	sim._spawn(1,"iron_rail",Vector2(42.5,31.5),true)
	sim._rail_network.rebuild(sim)
	var miner: int=sim._spawn(0,"iron_harvester",Vector2(43.5,31.5),true)
	var scout: int=sim._spawn(0,"iron_scout",Vector2(43.5,29.4),true)
	sim.issue([scout],"move",Vector2(43.5,37.5))
	sim._rebuild_spatial()
	var unit: Dictionary=sim.entities[miner]
	var source: Dictionary=sim.entities[scout]
	# This case exercises a legal foreground request. Ordinary combat traffic
	# may no longer displace an actively working economy vehicle.
	sim.set_player_navigation_priority([scout])
	sim._request_movement_yield(source,unit,source.pos,source.pos+Vector2(0,.1))
	var destination: Vector2=unit.get("yield_goal",Vector2.INF)
	var label: String=" native="+str(native_mode)+" own_retreat="+str(own_retreat)
	check(sim._rail_network.at(0,Vector2(42.5,31.5)).is_empty() and sim._rail_network.traversable_path(sim,unit,unit.pos,Vector2(42.5,31.5)).is_empty(),"enemy track does not supply an owned route"+label)
	if own_retreat:
		check(destination.is_finite(),"an available connected rail retreat can be requested"+label)
		check(destination.is_finite() and not sim._rail_network.at(0,destination).is_empty() and destination.is_equal_approx(Rail.center(Rail.key(destination))),"rail-only yield uses an owned track center"+label)
		check(destination.is_finite() and not sim._rail_network.traversable_path(sim,unit,unit.pos,destination).is_empty(),"rail-only yield has a physically traversable owned route"+label)
		# Stop the requester after its request; the existing miner yield must
		# finish through ordinary simulation movement without another order.
		sim.issue([scout],"hold",source.pos)
		var speed_ok:=true
		var rail_ok:=true
		for frame in range(40):
			var before: Vector2=unit.pos
			sim.step(.05)
			speed_ok=speed_ok and before.distance_to(unit.pos)<=float(sim.data_for(unit.spec).speed)*2.0*.05+.0001
			rail_ok=rail_ok and not sim._rail_network.at(0,unit.pos).is_empty()
			sim.events.clear()
		check(destination.is_finite() and (unit.pos as Vector2).distance_to(destination)<.01,"requested rail retreat physically completes"+label)
		check(speed_ok and rail_ok,"yield never teleports or leaves owned rail"+label)
	else:
		check(not destination.is_finite(),"no connected owned retreat leaves rail miner unassigned rather than using enemy/off-rail ground"+label)
	evidence.append({"scenario":"rail_only_yield","native":native_mode,"own_retreat":own_retreat,"yield_goal":str(destination),"final":str(unit.pos)})
	finish_fixture(sim)
func economy_traffic_priority(native_mode: bool) -> void:
	var sim=fixture(native_mode)
	if sim==null:return
	sim.match_options.slots[0].control="ai"
	# Earlier combat ID versus a later economy ID reproduces the arbitration
	# direction from the long soak without depending on favorable insertion.
	var tank: int=sim._spawn(0,"iron_tank",Vector2(20.5,24.4),true)
	sim._spawn(0,"iron_rail",Vector2(20.5,26.5),true)
	sim._spawn(0,"iron_rail",Vector2(20.5,25.5),true)
	sim._rail_network.rebuild(sim)
	var miner: int=sim._spawn(0,"iron_harvester",Vector2(20.5,26.5),true)
	var regular: int=sim._spawn(1,"kestrel_harvester",Vector2(12,30),true)
	var infantry: int=sim._spawn(1,"kestrel_rifle",Vector2(12,34),true)
	var unit: Dictionary=sim.entities[miner]
	var combat: Dictionary=sim.entities[tank]
	sim.issue([tank],"move",Vector2(20.5,33.5))
	sim._rebuild_spatial()
	var label: String=" native="+str(native_mode)
	check(unit.commands.is_empty() and sim._working_miner(unit) and sim._traffic_priority(unit)==42,"empty-command autonomous rail miner is active traffic42"+label)
	check(sim.entities[regular].commands.is_empty() and sim._working_miner(sim.entities[regular]) and sim._traffic_priority(sim.entities[regular])==42,"ordinary autonomous ground miner is also active traffic42"+label)
	check(sim._traffic_vehicle(unit) and not sim._is_ground_vehicle(unit) and not bool(unit.can_crush) and not sim._can_crush_target(unit,sim.entities[infantry]),"rail-only traffic is a vehicle while crushing classification remains exempt"+label)
	check(tank<miner and sim._traffic_priority(combat)==40,"earlier ordinary AI combat vehicle retains traffic40"+label)
	sim._request_movement_yield(combat,unit,combat.pos,combat.pos+Vector2(0,.1))
	check(not sim._traffic_may_yield(combat,unit) and not (unit.get("yield_goal",Vector2.INF) as Vector2).is_finite(),"ordinary combat request cannot evict a working autonomous miner"+label)
	check(sim._traffic_may_yield(unit,combat),"later-born working miner can request earlier ordinary combat traffic to yield"+label)
	var proxy: int=sim._spawn(0,"iron_harvester",Vector2(20.5,25.5),true)
	var chain: Dictionary=sim.entities[proxy]
	chain.yield_goal=Vector2(20.5,26.5);chain.yield_root=tank
	sim._request_movement_yield(chain,unit,chain.pos,chain.pos+Vector2(0,.1))
	check(not sim._traffic_may_yield(chain,unit) and not (unit.get("yield_goal",Vector2.INF) as Vector2).is_finite(),"yield chain inherits root40 rather than its proxy miner42"+label)
	sim.issue([miner],"stop",Vector2.ZERO)
	check(unit.commands.is_empty() and not sim._working_miner(unit) and sim._traffic_priority(unit)==10 and sim._traffic_may_yield(combat,unit),"genuinely stopped miner remains idle and can yield"+label)
	sim.issue([miner],"hold",unit.pos)
	check(not sim._traffic_may_yield(combat,unit),"explicit hold is still protected from traffic requests"+label)
	sim.mines.append({"pos":Vector2(20.5,28.5),"amount":3000.0,"capacity":3000.0,"miner":-1})
	sim._refresh_mine_spatial()
	sim.issue([miner],"harvest",sim.mines[0].pos,0)
	check(not unit.commands.is_empty() and unit.commands[0].kind=="harvest" and sim._working_miner(unit) and sim._traffic_priority(unit)==42,"ordinary harvest order retains working traffic42"+label)
	sim.issue([miner],"return_miner",unit.pos)
	check(not unit.commands.is_empty() and unit.commands[0].kind=="return_miner" and sim._working_miner(unit) and sim._traffic_priority(unit)==42,"ordinary refinery return retains working traffic42"+label)
	sim.match_options.slots[0].control="human"
	sim.set_player_navigation_priority([tank])
	check(sim._navigation_priority(tank)==3 and sim._traffic_priority(combat)==43,"selected human vehicle retains foreground traffic43"+label)
	check(not sim._traffic_may_yield(unit,combat),"working miner42 cannot evict selected human vehicle43"+label)
	check(sim._traffic_may_yield(combat,unit),"selected human vehicle43 can request working miner42 to yield"+label)
	evidence.append({"scenario":"economy_traffic_priority","native":native_mode,"autonomous_priority":42,"ordinary_combat_priority":40,"selected_human_priority":sim._traffic_priority(combat),"rail_crush_exempt":not bool(unit.can_crush)})
	finish_fixture(sim)
func run() -> void:
	rules=RulesLoader.load_rules("res://data/rules.json",false)
	for native_mode in [false,true]:
		partial_cell_departure(native_mode)
		rail_only_yield(native_mode,true)
		rail_only_yield(native_mode,false)
		economy_traffic_priority(native_mode)
	var report: Dictionary={"checks":checks,"failures":failures,"evidence":evidence,"source_sha256":{"simulation":FileAccess.get_sha256("res://scripts/simulation.gd"),"rail_network":FileAccess.get_sha256("res://scripts/rail_network.gd")}}
	var args:=OS.get_cmdline_user_args()
	if args.size()==2 and args[0]=="--output":
		DirAccess.make_dir_recursive_absolute(args[1].get_base_dir())
		FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("RAIL_YIELD_RECOVERY "+JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
