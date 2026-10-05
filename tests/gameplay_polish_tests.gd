extends SceneTree
const Sim = preload("res://tests/rule_test_simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
const Volume = preload("res://scripts/volume_models.gd")
var failures: Array[String] = []
var checks := 0
var config: Dictionary
func _initialize() -> void:
	config = Rules.load_rules()
	check(not config.is_empty(), "new defense rules validate")
	defenses()
	commands()
	crowd()
	cargo()
	print("Gameplay polish: %d passed, %d failed" % [checks-failures.size(),failures.size()])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func fresh():
	var sim = Sim.new()
	sim.setup(config,"dev",7,"rivet",false)
	for z in range(48):
		for x in range(48):
			sim.map.terrain[z][x] = 0
			sim.map.heights[z][x] = 0.0
	sim.mines.clear()
	sim.bridges.clear()
	sim._prepare_terrain_cache()
	sim._nav_initialized = false
	sim._rebuild_nav()
	return sim
func tick(sim, seconds: float) -> void:
	for i in range(roundi(seconds*30)):
		sim.step(1.0/30)
		sim.events.clear()
func ready(sim, spec: String) -> void:
	sim.defense_orders[0] = {}
	check(sim.build(0,spec).is_empty(),"defense order accepted")
	tick(sim,4)
func defenses() -> void:
	var sim = fresh()
	sim.money[0] = 10000
	var start := Vector2(15.5,30.5)
	ready(sim,"rivet_wall")
	check(sim.place_building(0,start).is_empty(),"wall places within base radius")
	tick(sim,2)
	ready(sim,"rivet_wall")
	var finish := start + Vector2(6,0)
	check(sim.defense_extension(0,finish).size()==6,"six cells extend from existing wall")
	var funds: float = sim.money[0]
	check(sim.place_building(0,finish).is_empty(),"complete six-cell extension succeeds")
	check(is_equal_approx(funds-sim.money[0],300),"extra five cells billed once")
	check(sim.defense_extension(0,finish+Vector2(7,0)).size()==1,"seven-cell auto-extension disallowed")
	tick(sim,2)
	ready(sim,"rivet_barricade")
	var blocking: int = sim.debug_spawn(0,"rivet_engineer",Vector2(23.5,30.5))
	funds = sim.money[0]
	var count: int = sim.entities.size()
	check(not sim.place_building(0,Vector2(26.5,30.5)).is_empty(),"occupied intermediate cell blocks whole extension")
	check(sim.entities.size()==count and sim.money[0]==funds and not sim.defense_orders[0].is_empty(),"failed extension preserves funds/order/entities")
	sim._kill_entity(blocking,false)
	var barricade: int = sim.debug_spawn(0,"rivet_barricade",Vector2(25.5,20.5))
	sim._rebuild_nav()
	check(sim._standing(Vector2(25.5,20.5),.35,-1,false),"infantry can stand in barricade")
	check(not sim._standing(Vector2(25.5,20.5),.75,-1,false),"tank blocked by barricade")
	check(not sim._standing(start,.35,-1,false),"wall blocks infantry")
	var infantry: int = sim.debug_spawn(0,"rivet_engineer",Vector2(25.5,20.5))
	var e: Dictionary = sim.entities[infantry]
	e.alpha=0
	sim.issue([infantry],"move",Vector2(28.5,20.5))
	tick(sim,.1)
	check(e.pos.x>25.5 and e.pos.x<25.60,"barricade slows moving infantry")
	check(sim._path_between(Vector2(22.5,20.5),Vector2(29.5,20.5),.75,-1).size()>0,"tank finds route around barricade")
	check(sim.entities.has(barricade),"crossing does not destroy barricade")
func commands() -> void:
	var sim = Sim.new()
	sim.setup(config,"dev",7,"rivet",false)
	var id: int = sim.debug_spawn(0,"rivet_engineer",Vector2(8.5,40.5))
	sim.issue([id],"patrol",Vector2(14.5,40.5))
	tick(sim,4)
	check(sim.entities[id].commands.size()==2,"patrol continues after arrival")
	check(sim.entities[id].commands[0].pos.x<10,"patrol reverses to origin")
	sim.issue([id],"hold",Vector2.ZERO)
	var pos: Vector2 = sim.entities[id].pos
	tick(sim,2)
	check(sim.entities[id].pos==pos and sim.entities[id].commands.is_empty() and sim.entities[id].hold_position,"hold cancels queue and stays in place")
	sim.issue([id],"move",Vector2(16.5,40.5))
	sim.issue([id],"move",Vector2(20.5,40.5),-1,true)
	check(sim.entities[id].commands.size()==2 and not sim.entities[id].hold_position,"waypoints append and release hold")
	sim.issue([id],"patrol",Vector2(12.5,40.5))
	var path := "/tmp/paperfront-polish-save.pfront"
	check(sim.save_game(path).is_empty(),"patrol snapshot writes")
	var restored = Sim.new()
	var error: String = restored.load_game(path)
	if not error.is_empty(): print("Save error: ",error)
	check(error.is_empty() and restored.entities[id].commands.size()==2,"patrol snapshot restores")
func crowd() -> void:
	var sim = fresh()
	# This fixture measures navigation for the entire 65 seconds. The default
	# opposing HQ at (39,31) is within automatic turret range of the arriving
	# formation; destroying it ends the match and freezes unfinished movement.
	# Keep it away from the route without changing unit movement or collision.
	for e in sim.entities.values():
		if e.team == 1 and e.kind == "building": e.pos = Vector2(39,8)
	var army: Array = []
	# A convex building corner, with a dense mixed-radius formation approaching.
	sim.debug_spawn(0,"rivet_factory",Vector2(22,39))
	for z in range(5):
		for x in range(6):
			army.append(sim.debug_spawn(0,"rivet_tank" if x%2==0 else "rivet_engineer",Vector2(7+x*1.9,35+z*1.9)))
	sim._rebuild_nav()
	sim.issue(army,"move",Vector2(32,39))
	var unique: Dictionary = {}
	for id in army: unique[sim.entities[id].commands[0].pos] = true
	check(unique.size()==army.size(),"dense mixed army has distinct formation destinations")
	tick(sim,65)
	check(sim.result.is_empty() and absf(sim.time-65.0)<0.1,"crowd simulation runs full duration without incidental combat victory")
	var reached := 0
	var stuck: Array = []
	for id in army:
		if sim.entities[id].pos.x>25: reached+=1
		else: stuck.append([id,sim.entities[id].pos,sim.entities[id].state])
	print("Corner traffic reached ",reached,"/",army.size()," remaining ",stuck)
	check(reached==army.size(),"all thirty units clear building corner")
func cargo() -> void:
	var model: Dictionary = Volume.create_model(config.units.rivet_harvester,"unit",0)
	for pair in [[0,0],[250,6],[500,12]]:
		Volume.update_model(model,{"cargo":pair[0],"state":"harvest"},.1)
		check(model.cargo_count==pair[1],"cargo geometry count follows load %s"%pair[0])
	check(model.drill.rotation.z!=0,"harvesting animates cutter")
	model.root.free()
