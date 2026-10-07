extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
var config: Dictionary
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func fixture(team_count: int = 2):
	var sim = Sim.new()
	var owners: Array[String] = []
	var positions: Array[Vector2] = []
	var names: Array[String] = ["rivet","kestrel","iron","sky"]
	for team: int in team_count:
		owners.append(names[team % names.size()])
		positions.append(Vector2(4.5 + float(team)*5.0, 43.5))
	sim.setup_multiteam(config,"dev",7,owners,false,positions)
	return sim

func obstacle(sim, team: int, spec: String, completed: bool = true) -> int:
	return sim._spawn(team,spec,Vector2(8.5+float(team)*4.0,35.5),completed)

func eliminate_base(sim, team: int) -> void:
	for entity: Dictionary in sim._building_entities.duplicate():
		if int(entity.team) == team and sim._is_victory_building(entity): sim._kill_entity(int(entity.id),true)

func result_events(sim) -> Array:
	return sim.events.filter(func(event: Dictionary): return event.get("kind","") == "result")

func expect_result(sim, expected: String, label: String) -> void:
	sim._check_result()
	check(sim.result == expected, label)
	if expected.is_empty():
		check(result_events(sim).is_empty(), label + " has no result event")
		return
	check(result_events(sim).size() == 1 and result_events(sim)[0].result == expected, label + " emits one matching result event")
	sim._check_result()
	sim.step(1.0/30.0)
	check(result_events(sim).size() == 1, label + " result is terminal/idempotent")

func test_roles_and_sides() -> void:
	for spec: String in config.buildings:
		if config.buildings[spec].get("role","") not in ["wall","barricade"]: continue
		for completed: bool in [true,false]:
			var sim = fixture()
			var id: int = obstacle(sim,1,spec,completed)
			check(sim.entities.has(id) and (completed or float(sim.entities[id].construct_remaining)>0.0), "live obstacle fixture " + spec + str(completed))
			eliminate_base(sim,1)
			expect_result(sim,"win","enemy only obstacle " + spec + str(completed))
			check(sim.entities.has(id) and sim.counts(1).y == 1, "victory does not delete physical obstacle " + spec)
			var own = fixture()
			obstacle(own,0,spec,completed)
			own.debug_spawn(0,"rivet_rifle",Vector2(7.5,30.5))
			eliminate_base(own,0)
			expect_result(own,"lose","player only obstacle and unit " + spec + str(completed))
	var sim = fixture()
	obstacle(sim,0,"rivet_wall",false)
	obstacle(sim,1,"kestrel_barricade",false)
	eliminate_base(sim,0)
	eliminate_base(sim,1)
	expect_result(sim,"draw","both owners only unfinished obstacles")
	# The exclusion follows role rather than a particular catalog name/art.
	sim = fixture()
	sim.rules.buildings.rivet_test_obstacle = sim.rules.buildings.rivet_wall.duplicate(true)
	obstacle(sim,1,"rivet_test_obstacle")
	eliminate_base(sim,1)
	expect_result(sim,"win","renamed wall spec is still an obstacle")

func test_normal_buildings() -> void:
	for spec: String in ["kestrel_tower","kestrel_power","kestrel_barracks"]:
		var sim = fixture()
		var id: int = sim._spawn(1,spec,Vector2(20.5,35.5),false)
		obstacle(sim,1,"kestrel_wall")
		sim._kill_entity(2,true)
		expect_result(sim,"","ordinary building, including unfinished tower, keeps enemy alive " + spec)
		sim._kill_entity(id,true)
		expect_result(sim,"win","ordinary building destruction ends enemy despite wall " + spec)
	var sim = fixture()
	var friend: int = sim.debug_spawn(0,"rivet_power",Vector2(15.5,35.5))
	sim._kill_entity(1,true)
	expect_result(sim,"","same-owner friendly power keeps player base alive")
	sim.entities[friend].hp = 0.0
	expect_result(sim,"lose","zero-hp building never keeps player alive")

func test_multiteam_and_neutral() -> void:
	var sim = fixture(4)
	for team: int in range(1,4): obstacle(sim,team,str(sim.factions[team])+"_wall")
	check(sim.ruins.any(func(ruin: Dictionary): return float(ruin.hp)>0.0), "neutral scenery remains alive in real map fixture")
	var tower: int = sim.debug_spawn(2,"iron_tower",Vector2(20.5,35.5))
	for team: int in range(1,4): sim._kill_entity(team+1,true)
	expect_result(sim,"","one ordinary tower among three foreign owners blocks victory")
	sim.entities[tower].team = 0
	sim.entities[tower].captured = true
	expect_result(sim,"win","captured tower now belongs to player; neutral ruins and enemy walls do not block victory")
	sim = fixture(4)
	obstacle(sim,0,"rivet_barricade")
	eliminate_base(sim,0)
	expect_result(sim,"lose","player obstacles do not survive against independent foreign bases")
	sim = fixture(4)
	for team: int in range(4):
		obstacle(sim,team,str(sim.factions[team])+"_wall")
		eliminate_base(sim,team)
	expect_result(sim,"lose","all four bases eliminated retains existing multiteam outcome")
	sim = fixture(8)
	for team: int in range(1,8):
		obstacle(sim,team,str(sim.factions[team])+"_wall")
		eliminate_base(sim,team)
	expect_result(sim,"win","all seven independent enemy owners only walls permit victory")

func test_sales() -> void:
	for spec: String in ["rivet_wall","rivet_barricade"]:
		var sim = fixture()
		var wall: int = obstacle(sim,0,spec)
		var money: float = sim.money[0]
		check(sim.sell(1) == "CONFIRM_LAST_BUILDING" and sim.entities.has(1) and sim.money[0] == money and sim.result.is_empty(), "HQ with only obstacle requires last-base confirmation " + spec)
		check(sim.sell(1,true).is_empty() and sim.entities.has(wall) and sim.result == "lose", "confirmed HQ sale loses while physical obstacle remains " + spec)
		check(is_equal_approx(sim.money[0],money+float(config.buildings.rivet_hq.cost)*float(config.economy.sell_ratio)), "HQ refund unchanged " + spec)
		sim = fixture()
		wall = obstacle(sim,0,spec)
		money = sim.money[0]
		check(sim.sell(wall).is_empty() and not sim.entities.has(wall) and sim.result.is_empty(), "normal obstacle sale never needs last-base confirmation " + spec)
		check(is_equal_approx(sim.money[0],money+float(config.buildings[spec].cost)*float(config.economy.sell_ratio)), "obstacle refund unchanged " + spec)
	var sim = fixture()
	var tower: int = sim.debug_spawn(0,"rivet_tower",Vector2(15.5,35.5))
	obstacle(sim,0,"rivet_wall")
	check(sim.sell(1).is_empty() and sim.result.is_empty(), "ordinary tower avoids false HQ last-base warning")
	check(sim.sell(tower) == "CONFIRM_LAST_BUILDING", "remaining ordinary tower is last effective building")

func test_legacy_save() -> void:
	for outcome: String in ["win","lose","draw"]:
		var sim = fixture()
		obstacle(sim,0,"rivet_wall",false)
		obstacle(sim,1,"kestrel_barricade",false)
		if outcome in ["lose","draw"]: eliminate_base(sim,0)
		if outcome in ["win","draw"]: eliminate_base(sim,1)
		var path: String = "user://victory_legacy_"+outcome+".pfront"
		check(sim.save_game(path).is_empty(), "write legacy ongoing obstacle-only fixture " + outcome)
		var file: FileAccess = FileAccess.open(path,FileAccess.READ)
		var snapshot: Dictionary = file.get_var(false)
		file.close()
		# Original v1 single-channel saves lack these newer optional fields. The
		# historical embedded rules still own role identity after migration.
		snapshot.erase("defense_orders")
		snapshot.erase("match_options")
		snapshot.erase("team_vision")
		snapshot.result = ""
		file = FileAccess.open(path,FileAccess.WRITE)
		file.store_var(snapshot,false)
		file.close()
		var restored = Sim.new()
		var error: String = restored.load_game(path)
		check(error.is_empty() and restored.result.is_empty(), "load original v1-shaped ongoing state " + outcome + ":" + error)
		if error.is_empty():
			expect_result(restored,outcome,"restored old state uses current obstacle victory rule " + outcome)
			check(restored._building_entities.any(func(entity: Dictionary): return restored.data_for(entity.spec).get("role","") in ["wall","barricade"] and entity.construct_remaining > 0.0), "old unfinished obstacles remain present " + outcome)
		DirAccess.remove_absolute(path)

func test_campaign() -> void:
	var sim = fixture()
	sim.campaign_controller = CampaignController.new()
	sim.campaign_controller.setup(sim)
	obstacle(sim,1,"kestrel_wall")
	eliminate_base(sim,1)
	expect_result(sim,"","campaign still waits for objective completion after enemy economy eliminated")
	sim.campaign_controller.finished = true
	expect_result(sim,"win","campaign objective completion remains authoritative")
	sim = fixture()
	sim.campaign_controller = CampaignController.new()
	sim.campaign_controller.setup(sim)
	sim.debug_spawn(0,"rivet_power",Vector2(15.5,35.5))
	obstacle(sim,0,"rivet_wall")
	sim._kill_entity(1,true)
	expect_result(sim,"lose","campaign HQ destruction still loses despite normal buildings/obstacles")

func run() -> void:
	config = Rules.load_rules()
	check(not config.is_empty(), "rules fixture imports")
	if config.is_empty(): quit(1); return
	test_roles_and_sides()
	test_normal_buildings()
	test_multiteam_and_neutral()
	test_sales()
	test_legacy_save()
	test_campaign()
	print("VICTORY_BUILDINGS_TEST ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
