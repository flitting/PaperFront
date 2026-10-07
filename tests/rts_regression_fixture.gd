extends RefCounted

## Fixed four-owner flat arena. Buildings and ore are controlled initial
## conditions; purchases, queues, exits, mining, orders and damage are real.
const Sim = preload("res://tests/rule_test_simulation.gd")
const FACTIONS: Array[String] = ["kestrel","rivet","iron","sky"]
var sim
var failures: Array[String] = []
var checks: int = 0
var evidence: Dictionary = {"fixture":"four factions, fixed flat dev arena; initial infrastructure is seeded, all exercised commands use live rules"}
var ids: Dictionary = {}
var emitted: Dictionary = {}
var deliveries_by_owner: Dictionary = {}
var max_door: float = 0
var emerged: Dictionary = {}
var mine_money: Array = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func setup() -> void:
	var rules: Dictionary = RulesLoader.load_rules()
	sim = Sim.new()
	var positions: Array[Vector2] = [Vector2(9,9),Vector2(55,9),Vector2(9,55),Vector2(55,55)]
	sim.setup_multiteam(rules,"dev",117,FACTIONS,false,positions,Callable(),{"vision_enabled":false})
	# The standard dev map is48cells; this deliberately documented review
	# arena is64cells so all four production yards are genuinely in bounds.
	sim.map.size = 64
	sim.map.terrain = []; sim.map.heights = []; sim.map.starts = []
	for point: Vector2 in positions: sim.map.starts.append([point.x, point.y])
	for row in 64:
		var terrain: Array[int] = []; terrain.resize(64); terrain.fill(0)
		var heights: Array[float] = []; heights.resize(64); heights.fill(0.0)
		sim.map.terrain.append(terrain); sim.map.heights.append(heights)
	sim.mines.clear();sim.bridges.clear();sim.ruins.clear()
	sim._nav_initialized = false
	sim._refresh_ruin_spatial();sim._prepare_terrain_cache()
	sim.money.assign([20000.0,20000.0,20000.0,20000.0])
	sim.statistics.reset(sim.factions,sim.money)
	var layouts: Array = [
		[Vector2(8.5,20.5),Vector2(20.5,8.5),Vector2(19,16),Vector2(22,22),Vector2(29.5,22.5)],
		[Vector2(55.5,20.5),Vector2(43.5,8.5),Vector2(45,16),Vector2.ZERO,Vector2(40.5,23.5)],
		[Vector2(8.5,43.5),Vector2(20.5,55.5),Vector2(16,53),Vector2(22,43),Vector2(29.5,43.5)],
		[Vector2(55.5,43.5),Vector2(43.5,55.5),Vector2(45,48),Vector2(42,42),Vector2(34.5,42.5)]
	]
	var power_sites: Array[Vector2] = [Vector2(32,8),Vector2(45,16),Vector2(17,31),Vector2(42,32)]
	for team in range(4):
		var f: String = FACTIONS[team]
		ids[f+"_factory"] = sim._spawn(team,f+"_factory",layouts[team][0],true)
		if f == "rivet":
			for e: Dictionary in sim.entities.values():
				if e.team == team and e.spec == "rivet_hq": ids[f+"_barracks"] = int(e.id); break
		else: ids[f+"_barracks"] = sim._spawn(team,f+"_barracks",layouts[team][1],true)
		ids[f+"_power"] = sim._spawn(team,f+"_power",power_sites[team],true)
		sim._spawn(team,f+"_power",power_sites[team]+Vector2(0,-6) if team == 1 else power_sites[team]+Vector2(7,0),true)
		sim.mines.append({"pos":layouts[team][4],"capacity":3000.0,"amount":3000.0,"miner":-1})
		if team != 1:
			ids[f+"_refinery"] = sim._spawn(team,f+"_refinery",layouts[team][3],true)
			sim.entities[ids[f+"_refinery"]].gift_pending = false
		# Ground producers face their real south door. Separate the infantry
		# rally from the vehicle staging lane for the revised1/2-cell units.
		var barracks: Dictionary = sim.entities[ids[f+"_barracks"]]
		var barracks_half: float = float(sim.data_for(barracks.spec).size) * .5
		var infantry_radius: float = float(sim.data_for(f+"_rifle").radius)
		var vehicle_radius: float = float(sim.data_for(f+"_tank").radius)
		var factory_half: float = float(sim.data_for(f+"_factory").size)*.5
		barracks.rally = barracks.pos + Vector2(infantry_radius*3+2, barracks_half+infantry_radius*3+3)
		if f == "rivet": barracks.rally = barracks.pos+Vector2(barracks_half+infantry_radius+3,barracks_half+infantry_radius*6)
		var side: float = 1.0 if team in [0,2] else -1.0
		sim.entities[ids[f+"_factory"]].rally = layouts[team][0]+Vector2((factory_half+vehicle_radius*2+1.5)*side,factory_half+vehicle_radius*2+2.5)
	sim._refresh_mine_spatial();sim._rail_network.rebuild(sim);sim._nav_dirty=true
	advance(2)
	check(sim.factions.size()==4,"four actual owners participate")

func advance(seconds: float) -> void:
	for frame in range(ceili(seconds*20)):
		sim.step(.05)
		for e in sim.entities.values():
			if bool(e.get("emerging",false)): emerged[e.spec]=true
			if e.kind=="building": max_door=maxf(max_door,float(e.get("production_door",0)))
		for event in sim.events:
			var kind: String = str(event.kind)
			emitted[kind] = int(emitted.get(kind,0))+1
			if kind == "delivery":
				var owner: int = int(event.get("team", -1))
				deliveries_by_owner[owner] = int(deliveries_by_owner.get(owner, 0))+1
		sim.events.clear();sim.notices.clear()

func wait_for(done: Callable, seconds: float) -> void:
	for i in range(ceili(seconds*2)):
		if done.call(): return
		advance(.5)

func find(faction: String, art: String) -> int:
	for e in sim.entities.values():
		if str(e.spec)==faction+"_"+art and e.kind=="unit": return int(e.id)
	return -1

func lay_rail(point: Vector2) -> bool:
	if not sim._rail_network.at(2,point).is_empty(): return true
	var error: String = sim.build(2,"iron_rail")
	if not error.is_empty(): failures.append("rail purchase: "+error);return false
	wait_for(func():return bool(sim.order_for_team(2,"defense").get("ready",false)),5)
	error=sim.place_building(2,point,"defense")
	if not error.is_empty(): failures.append("rail placement "+str(point)+": "+error);sim.cancel_build(2,"defense");return false
	advance(1.6)
	return true

func produce_phase() -> void:
	for team in range(4):
		var f: String = FACTIONS[team]
		check(sim.produce(ids[f+"_factory"],f+"_tank").is_empty(),f+" paid tank queue")
		check(sim.produce(ids[f+"_barracks"],f+"_rifle").is_empty(),f+" paid infantry queue")
		check(sim.produce(ids[f+"_barracks"],f+"_engineer").is_empty(),f+" paid engineer queue")
	wait_for(func():return find("sky","tank")>0 and find("sky","engineer")>0,55)
	advance(4)
	for f in FACTIONS:
		for art in ["rifle","engineer","tank"]:
			var id: int = find(f,art)
			ids[f+"_"+art] = id
			check(id>0 and not bool(sim.entities.get(id,{}).get("emerging",false)),f+" "+art+" physically exits")
			if id>0 and art!="engineer":sim.issue([id],"hold",sim.entities[id].pos)
	check(max_door>.99,"production opens a real doorway")
	check(emerged.size()>=12,"all twelve productions passed an inside phase")
	evidence.production_time=sim.time

func economy_phase() -> void:
	sim._rail_network.auto_refinery(sim, sim.entities[ids.iron_refinery])
	var eng: int = int(ids.rivet_engineer)
	check(sim.build(1,"rivet_drill",eng).is_empty(),"heavy engineer buys live drill construction")
	check(sim.place_building(1,sim.mines[1].pos).is_empty(),"heavy engineer receives normal scaffold placement")
	for f in ["kestrel","iron","sky"]:check(sim.produce(ids[f+"_factory"],f+"_harvester").is_empty(),f+" buys its ordinary/rail miner")
	# Connect the factory to the independently, automatically laid mine branch.
	var factory_exit: Vector2 = sim._rail_network.exit_cell(sim,sim.entities[ids.iron_factory])
	var refinery_exit: Vector2 = sim._rail_network.exit_cell(sim,sim.entities[ids.iron_refinery])
	for x in range(floori(factory_exit.x),floori(refinery_exit.x)):
		if not lay_rail(Vector2(x+.5,factory_exit.y)):break
	if not is_equal_approx(factory_exit.y,refinery_exit.y): lay_rail(Vector2(refinery_exit.x-1,refinery_exit.y))
	wait_for(func():return find("iron","harvester")>0 and find("sky","harvester")>0 and int(sim.mines[1].get("drill",-1))>0,60)
	advance(15)
	for team in [0,2,3]:
		var id: int = find(FACTIONS[team],"harvester")
		ids[FACTIONS[team]+"_harvester"]=id
		check(id>0,FACTIONS[team]+" miner really produced")
		if id>0: sim.issue([id],"harvest",sim.mines[team].pos,team)
	mine_money=sim.money.duplicate()
	var deliveries_before: Dictionary = deliveries_by_owner.duplicate()
	evidence.economy_trace = []
	for interval in range(8):
		advance(20)
		var miners: Array[Dictionary] = []
		for unit: Dictionary in sim.entities.values():
			if str(sim.data_for(unit.spec).get("art", "")) != "harvester": continue
			miners.append({"owner":unit.team,"pos":[unit.pos.x,unit.pos.y],"hp":unit.hp,"state":unit.state,"cargo":unit.cargo,"mine":unit.harvest_mine,"refinery":unit.harvest_refinery,"commands":str(unit.commands),"path":str(unit.path),"path_goal":str(unit.path_goal)})
		evidence.economy_trace.append({"time":sim.time,"money":sim.money.duplicate(),"miners":miners})
	for team in range(4):
		check(sim.money[team]>float(mine_money[team]),FACTIONS[team]+" economic cycle produces actual money")
		if team != 1: check(int(deliveries_by_owner.get(team,0))-int(deliveries_before.get(team,0))>=2,FACTIONS[team]+" completes at least two full mining/return/unload cycles during the long window")
	var drill: int = int(sim.mines[1].get("drill",-1))
	check(drill>0 and sim.entities.has(drill) and not sim.entities[drill].has("construction"),"heavy drill is a completed independent structure")
	check(not sim._mine_available(1,-1),"occupied ore cannot be harvested by another miner")
	evidence.economic_income=[]
	for team in range(4): evidence.economic_income.append(sim.money[team]-float(mine_money[team]))
	evidence.economy_time=sim.time
	evidence.deliveries_by_owner = deliveries_by_owner.duplicate()

func capture_phase() -> void:
	var eng: int = int(ids.kestrel_engineer)
	# Explicit cooldown represents a tower between shots, so the controlled
	# capture scene verifies walking and ownership rather than solo-engineer
	# survival against a fully primed lethal defense.
	var tower: int = sim._spawn(1,"rivet_tower",sim.entities[eng].pos+Vector2(5,0),true)
	sim.entities[tower].cooldown = 4.0
	ids.capture_tower=tower
	sim.entities[tower].cooldown=60.0 # A quiet observation window isolates walking/ownership transfer from combat.
	check(sim.capture_error(eng,tower).is_empty(),"hostile defense tower permits engineering capture")
	sim.issue([eng],"capture",sim.entities[tower].pos,tower)
	wait_for(func():return sim.entities.has(tower) and sim.entities[tower].team==0,25)
	check(sim.entities.has(tower) and sim.entities[tower].team==0,"walking engineer transfers tower ownership under live orders")

func combat_phase() -> void:
	var starts: Array[Vector2] = [Vector2(24,27),Vector2(39,27),Vector2(24,37),Vector2(39,37)]
	for team in range(4):
		var tank: int = int(ids[FACTIONS[team]+"_tank"])
		var infantry: int = int(ids[FACTIONS[team]+"_rifle"])
		if sim.entities.has(tank):sim.issue([tank],"attack_move",starts[team])
		if sim.entities.has(infantry):sim.issue([infantry],"attack_move",Vector2(31,32))
	advance(15)
	evidence.combat_first_time=sim.time
	advance(25)
	check(int(emitted.get("fire",0))>0 and int(emitted.get("impact",0))>0,"live orders resolve actual weapon fire and impacts")
	check(sim.statistics.teams.any(func(row):return float(row.damage_dealt)>0),"combat records real damage")
	check(int(emitted.get("death",0))>0,"four-faction combat resolves real unit deaths")
	evidence.combat_events=emitted.duplicate()

func rail_destruction_phase() -> void:
	var factory_exit: Vector2 = sim._rail_network.exit_cell(sim,sim.entities[ids.iron_factory])
	var rail_point: Vector2 = Vector2(16.5,factory_exit.y)
	var rail: Dictionary = sim._rail_network.at(2,rail_point)
	check(not rail.is_empty(),"rail destruction fixture has a connected live rail")
	if rail.is_empty(): return
	var attacker: int = sim._spawn(3,"sky_tank",Vector2(16.5,53.5),true)
	var before: int = sim._rail_network.revision
	sim.issue([attacker],"force_attack",rail.pos,rail.id)
	wait_for(func():return not sim.entities.has(int(rail.id)),30)
	check(not sim.entities.has(int(rail.id)),"forced attack physically destroys rail")
	check(sim._rail_network.revision>before and sim._rail_network.at(2,rail_point).is_empty(),"rail destruction immediately revises authoritative connectivity")
	var miner: int = int(ids.get("iron_harvester",-1))
	if sim.entities.has(miner):
		sim.issue([miner],"move",factory_exit);advance(3)
		# A rail miner temporarily leaves the rail grid while physically inside
		# its refinery. Finish that live doorway trip before testing the rails.
		evidence.rail_destruction_docking_before = sim.entities[miner].get("refinery_docking", {}).duplicate(true)
		wait_for(func(): return sim.entities[miner].get("refinery_docking", {}).is_empty(), 10)
		check(sim.entities[miner].get("refinery_docking", {}).is_empty(), "rail miner completes its legitimate refinery interior trip after the remote rail break")
		var vehicle: Dictionary = sim.entities[miner]
		evidence.rail_destruction_miner = {"pos":str(vehicle.pos), "state":vehicle.state, "commands":vehicle.commands.duplicate(true), "refinery_docking":vehicle.get("refinery_docking", {}).duplicate(true), "rail_cell":sim._rail_network.at(2, vehicle.pos).duplicate(true), "factory_exit":str(factory_exit), "destroyed_rail":str(rail_point)}
		check(sim._rail_network.usable(sim,sim.entities[miner],sim.entities[miner].pos),"rail-only miner remains on surviving owner rails after break")

func result_phase() -> void:
	# Deterministic terminal damage is explicit fixture cleanup, separate from
	# the preceding live battle. It checks owner/infrastructure win bookkeeping.
	for e in sim.entities.values().duplicate():
		if int(e.team)>0 and not sim.RailNetwork.is_rail(sim.data_for(e.spec)): sim._add_damage(int(e.id),100000)
	sim._apply_damage();sim._damage.clear();sim._check_result()
	check(sim.result=="win","only hostile rail infrastructure remaining does not block victory")
	check(sim._building_entities.any(func(e):return e.team==2 and sim.RailNetwork.is_rail(sim.data_for(e.spec))),"terminal fixture still contains enemy owner rails")
	evidence.result=sim.result
	evidence.statistics=sim.statistics.snapshot(sim)
	evidence.checks=checks;evidence.failures=failures
