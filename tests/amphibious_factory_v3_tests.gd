extends SceneTree
const Sim=preload("res://tests/rule_test_simulation.gd")
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func run()->void:
	for q in range(4):
		var sim=Sim.new();sim.map_generation_config={}
		sim.setup_multiteam(RulesLoader.load_rules(),"dev",17,["rivet","kestrel"],false)
		for id in sim.entities.keys():sim._kill_entity(id,false)
		sim._spawn(0,"rivet_hq",Vector2(18,50),true);sim._spawn(1,"kestrel_hq",Vector2(82,50),true)
		sim._spawn(0,"rivet_power",Vector2(37,42),true)
		var factory:int=sim._spawn(0,"rivet_factory",Vector2(30,35),true,q)
		sim.money[0]=10000
		var price:float=sim.data_for("rivet_amphibious").cost
		check(sim.produce(factory,"rivet_amphibious").is_empty(),"factory accepts real amphibious order q"+str(q))
		check(sim.money[0]==10000-price,"actual amphibious purchase charged once q"+str(q))
		var file:String="user://amphibious_factory_queue.save"
		check(sim.save_game(file).is_empty(),"amphibious pending queue saves q"+str(q))
		var restored=Sim.new();var problem:String=restored.load_game(file)
		check(problem.is_empty(),"dual-producer queue loads q"+str(q)+" "+problem)
		if restored._path_worker!=null:restored._path_worker.close()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
		var id:int=-1
		for tick in range(1800):
			sim.step(.05);sim.events.clear()
			for e in sim.entities.values():
				if e.spec=="rivet_amphibious":id=int(e.id);break
			if id>0:break
		check(id>0,"factory produces actual amphibious unit q"+str(q))
		if id>0:
			var e:Dictionary=sim.entities[id]
			check(bool(e.get("emerging",false)) and (e.pos as Vector2).distance_to(sim.entities[factory].pos)<3,"amphibious starts inside the factory q"+str(q))
			var expected:Vector2=sim.BuildingOrientation.front(sim.entities[factory])
			var door_open:=false
			for tick in range(240):
				sim.step(.05);sim.events.clear();door_open=door_open or float(sim.entities[factory].production_door)>.99
				if not bool(e.get("emerging",false)):break
			check(door_open and not bool(e.get("emerging",false)),"real door opens and unit completes traversal q"+str(q))
			check((e.pos as Vector2).distance_to(sim.entities[factory].pos)>=4.0 and ((e.pos as Vector2)-(sim.entities[factory].pos as Vector2)).normalized().dot(expected)>.99,"unit exits the rotated front q"+str(q))
		if sim._path_worker!=null:sim._path_worker.close()
	print("AMPHIBIOUS_FACTORY_V3 ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
