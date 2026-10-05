extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
var checks: int = 0
var failures: Array[String] = []
var config: Dictionary

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func fixture(faction: String = "iron"):
	var sim = Sim.new()
	sim.setup(config, "dev", 7, faction, false)
	sim.money.assign([100000.0, 100000.0])
	return sim

func _initialize() -> void:
	config = RulesLoader.load_rules()
	check(not config.is_empty(), "Revised rules validate " + str(RulesLoader.errors))
	if config.is_empty(): quit(1); return
	repairs()
	rescue()
	designation()
	overcharge()
	airlift()
	print("FACTION_REVISION ", JSON.stringify({"checks":checks, "failures":failures}))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func repairs() -> void:
	for native in [false, true]:
		var sim = fixture()
		sim.native_kernels_enabled = native
		var tank: int = sim._spawn(0, "iron_tank", Vector2(14,39), true)
		var a: int = sim._spawn(0, "iron_repair_vehicle", Vector2(12,39), true)
		var b: int = sim._spawn(0, "iron_repair_vehicle", Vector2(14,37), true)
		var infantry: int = sim._spawn(0, "iron_rifle", Vector2(16,39), true)
		sim.entities[tank].hp = 200.0
		sim.entities[infantry].hp = 20.0
		sim.issue([a,b], "repair", sim.entities[tank].pos, tank)
		var funds: float = sim.money[0]
		sim.step(.5)
		check(is_equal_approx(float(sim.entities[tank].hp), 207.0), "Two mobile repairers heal at 14/s, no stacking native="+str(native))
		check(is_equal_approx(funds - float(sim.money[0]), 1.4), "Repair charges existing money per actual HP native="+str(native))
		sim.money[0] = .1
		sim.step(.5)
		check(is_equal_approx(float(sim.entities[tank].hp),207.5) and is_zero_approx(float(sim.money[0])), "Insufficient money limits repair native="+str(native))
		sim.issue([a], "stop", Vector2.ZERO)
		sim.issue([a], "repair", sim.entities[infantry].pos, infantry)
		check(sim.entities[a].commands.is_empty(), "Mobile repair cannot repair infantry")
		var building: int = sim.entities.values().filter(func(e): return e.kind == "building" and e.team == 0)[0].id
		sim.entities[building].hp = 100.0
		sim.issue([a], "repair", sim.entities[building].pos, building)
		check(sim.entities[a].commands.is_empty(), "Mobile repair cannot replace engineer building work")
		check(sim.save_game("user://faction_revision_repair.save").is_empty(), "Repair orders save")
		check(fixture().load_game("user://faction_revision_repair.save").is_empty(), "Repair orders restore")

func rescue() -> void:
	var sim = fixture()
	var tank: int = sim._spawn(0,"iron_tank",Vector2(14,39),true)
	var a: int = sim._spawn(0,"iron_recycler",Vector2(12,39),true)
	var b: int = sim._spawn(0,"iron_recycler",Vector2(14,37),true)
	sim.entities[tank].hp = 200.0
	sim.issue([a,b],"rescue",sim.entities[tank].pos,tank)
	sim.issue([tank],"move",Vector2(18,39))
	sim._rebuild_spatial()
	sim.FactionSupport.prepare(sim,.1)
	check(is_equal_approx(float(sim.entities[tank].rescue_speed_scale),1.25),"Two rescue escorts grant one 25% withdrawal bonus")
	check(sim.save_game("user://faction_revision_rescue.save").is_empty() and fixture().load_game("user://faction_revision_rescue.save").is_empty(),"Rescue command survives save/load")
	sim.entities[tank].hp = 500.0
	sim.FactionSupport.prepare(sim,.1)
	check(is_equal_approx(float(sim.entities[tank].rescue_speed_scale),1.0),"Healthy vehicles do not receive withdrawal bonus")
	sim.entities[tank].hp = 0.0
	check(not sim.FactionSupport.rescue_error(sim,a,tank).is_empty(),"Destroyed vehicles cannot be rescued")

func designation() -> void:
	var sim = fixture("sky")
	var marker: int = sim._spawn(0,"sky_designation",Vector2(12,39),true)
	var marker_b: int = sim._spawn(0,"sky_designation",Vector2(12,37),true)
	var enemy: int = sim._spawn(1,"rivet_tank",Vector2(18,39),true)
	var shooter: int = sim._spawn(0,"sky_tank",Vector2(14,39),true)
	sim._rebuild_spatial()
	sim.FactionSupport.prepare(sim,1.0)
	check(is_equal_approx(sim.FactionSupport.damage_scale(sim,sim.entities[shooter],enemy),1.0),"Designation requires full tracking time")
	sim.FactionSupport.prepare(sim,.5)
	check(is_equal_approx(sim.FactionSupport.damage_scale(sim,sim.entities[shooter],enemy),1.15),"Two designators grant one 15% fire-control bonus")
	sim._fire(sim.entities[shooter],enemy)
	check(not sim.projectiles.is_empty() and is_equal_approx(float(sim.projectiles[0].damage),float(config.weapons.sky_tank.damage)*1.15),"Designated shot stores bonus in projectile")
	sim._spawn(1,"rivet_wall",Vector2(15,39),true)
	sim._spawn(1,"rivet_wall",Vector2(15,38),true)
	sim.FactionSupport.prepare(sim,.1)
	check(is_equal_approx(sim.FactionSupport.damage_scale(sim,sim.entities[shooter],enemy),1.0),"Wall breaks tracking and removes damage bonus")
	check(is_zero_approx(float(sim.entities[marker].designation_progress)) and is_zero_approx(float(sim.entities[marker_b].designation_progress)),"Lost LOS resets tracking")
	var river_sim = fixture("sky")
	river_sim._spawn(0,"sky_designation",Vector2(18,34),true)
	var across: int = river_sim._spawn(1,"rivet_tank",Vector2(28,34),true)
	var gun: int = river_sim._spawn(0,"sky_tank",Vector2(20,34),true)
	river_sim._rebuild_spatial()
	river_sim.FactionSupport.prepare(river_sim,1.5)
	check(is_equal_approx(river_sim.FactionSupport.damage_scale(river_sim,river_sim.entities[gun],across),1.15),"Observation crosses water without requiring ground passage")
	river_sim.map.heights[34][24]=8.0
	river_sim.FactionSupport.prepare(river_sim,.1)
	check(is_equal_approx(river_sim.FactionSupport.damage_scale(river_sim,river_sim.entities[gun],across),1.0),"High terrain occludes observation ray")

func overcharge() -> void:
	var sim = fixture("sky")
	var station: int = sim._spawn(0,"sky_accumulator",Vector2(10,36),true)
	var tank: int = sim._spawn(0,"sky_tank",Vector2(14,39),true)
	sim._spawn(1,"rivet_tank",Vector2(19,39),true)
	sim._rebuild_spatial()
	var funds: float = sim.money[0]
	sim.FactionSupport.prepare(sim,.1)
	check(is_equal_approx(funds-float(sim.money[0]),60.0),"Combat window charges 60 money once")
	check(is_equal_approx(sim.FactionSupport.damage_scale(sim,sim.entities[tank],-1),1.2),"Overcharge boosts nearby weapon by 20%")
	check(is_equal_approx(sim.power(0).y,80.0),"Active window reserves 80 additional power")
	sim.FactionSupport.prepare(sim,5.0)
	check(is_equal_approx(sim.FactionSupport.damage_scale(sim,sim.entities[tank],-1),1.0) and is_equal_approx(float(sim.entities[station].overcharge_cooldown),25.0),"Window ends and has 25 seconds cooldown")
	check(is_equal_approx(sim.money[0],funds-60.0),"Cooldown does not spend money again")
	sim.entities[station].overcharge_cooldown=0.0
	sim.entities[tank].pos=Vector2(27,39)
	sim._spawn(1,"rivet_tank",Vector2(32,39),true)
	sim._rebuild_spatial()
	sim.FactionSupport.prepare(sim,.1)
	check(is_zero_approx(float(sim.entities[station].overcharge_remaining)),"Fighting outside station radius does not trigger or spend money")
	sim.entities[tank].pos=Vector2(14,39)
	sim._rebuild_spatial()
	sim.money[0]=0.0
	sim.FactionSupport.prepare(sim,.1)
	check(is_zero_approx(float(sim.entities[station].overcharge_remaining)),"No funds means no activation")
	sim.money[0]=1000.0
	sim._spawn(0,"sky_factory",Vector2(25,36),true)
	sim._spawn(0,"sky_factory",Vector2(30,36),true)
	sim._spawn(0,"sky_factory",Vector2(35,36),true)
	sim._spawn(0,"sky_factory",Vector2(39,36),true)
	sim.FactionSupport.prepare(sim,.1)
	check(is_zero_approx(float(sim.entities[station].overcharge_remaining)),"Insufficient electrical headroom means no activation")
	check(sim.save_game("user://faction_revision_energy.save").is_empty() and fixture().load_game("user://faction_revision_energy.save").is_empty(),"Energy counters save/load")

func airlift() -> void:
	for faction in ["iron","sky"]:
		var sim = fixture(faction)
		sim._spawn(0,faction+"_power",Vector2(28,39),true)
		var airport: int = sim._spawn(0,faction+"_airfield",Vector2(20,36),true)
		var plane: int = sim._spawn(0,faction+"_air_transport",Vector2(20,36),true)
		var passenger: int = sim._spawn(0,faction+"_rifle",Vector2(20,40),true)
		check(sim.board_error(passenger,plane).is_empty(),"Airborne transport accepts boarding and can find a nearby landing site "+faction)
		sim._set_home_airfield(sim.entities[plane],airport)
		sim.entities[plane].flight_state="rearming"
		sim.entities[plane].rearm_remaining=0.0
		sim.entities[plane].flight_height=.35
		sim.entities[plane].airborne=false
		sim.entities[plane].hp=100.0
		var funds: float = sim.money[0]
		sim._step_aircraft_service(sim.entities[plane],.5)
		check(sim.entities[plane].state=="repair" and not sim.entities[plane].airborne,"Transport stays grounded while airport maintenance is in progress "+faction)
		check(is_equal_approx(float(sim.entities[plane].hp),100.0+float(config.buildings[faction+"_airfield"].aircraft_repair_rate)*.5) and sim.money[0]<funds,"Airfield charges for actual maintenance "+faction)
		sim.issue([passenger],"board",sim.entities[plane].pos,plane)
		sim.Transport.step_board(sim,sim.entities[passenger],sim.entities[passenger].commands[0],.1)
		check(sim.entities[passenger].transport_id==plane,"Infantry boards at airport edge "+faction)
		check(sim.save_game("user://faction_revision_airlift.save").is_empty() and fixture().load_game("user://faction_revision_airlift.save").is_empty(),"Embarked aircraft state restores "+faction)
		var walls: Array[int] = []
		for offset in range(-3,4):
			for side in [-1.0,1.0]:
				walls.append(sim._spawn(0,faction+"_wall",Vector2(20+offset,36+side*3.5),true))
				walls.append(sim._spawn(0,faction+"_wall",Vector2(20+side*3.5,36+offset),true))
		check(not sim.unload(plane).is_empty() and sim.entities[passenger].transport_id==plane,"Airport enclosure prevents unloading through walls "+faction)
		for id in walls: sim._kill_entity(id,false)
		sim.issue([plane],"move",Vector2(28,36))
		sim._step_aircraft_service(sim.entities[plane],.1)
		check(sim.entities[plane].airborne,"Move command launches parked transport "+faction)
		check(not sim.unload(plane).is_empty(),"Airborne unload rejected "+faction)
		sim.entities[plane].flight_state="rearming"
		sim.entities[plane].airborne=false
		sim.entities[plane].flight_height=.35
		sim.entities[plane].commands.clear()
		check(sim.unload(plane).is_empty() and sim.entities[passenger].transport_id<0,"Aircraft unloads onto legal airport perimeter "+faction)
