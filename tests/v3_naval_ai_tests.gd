extends SceneTree
const Sim=preload("res://tests/rule_test_simulation.gd")
const AI=preload("res://scripts/ai_controller.gd")
var checks:int=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func _initialize()->void:
	var rules:Dictionary=RulesLoader.load_rules()
	for faction in ["kestrel","rivet","iron","sky"]:
		var sim=Sim.new();sim.setup(rules,"dev",7,faction,false)
		sim.map.mode="islands"
		for e:Dictionary in sim.entities.values():
			if e.kind=="building":e.queue.clear()
		var factory:int=sim._spawn(0,faction+"_factory",Vector2(12,30),true)
		var yard:int=sim._spawn(0,faction+"_shipyard",Vector2(25,35),true)
		sim._spawn(0,faction+"_tank",Vector2(12,37),true)
		if faction!="rivet":
			sim._spawn(0,faction+"_harvester",Vector2(9,37),true)
			sim._spawn(0,faction+"_harvester",Vector2(6,37),true)
		sim._spawn(0,faction+"_hovercraft",Vector2(23,41),true)
		check(AI._naval_transport_count(sim,0)==1,faction+" existing hovercraft replaces transport requirement")
		var built:Dictionary={}
		for phase in range(8):
			sim.time=phase*12.0
			sim.money[0]=100000
			for e:Dictionary in sim.entities.values():
				if e.kind=="building":e.queue.clear()
			AI._produce(sim,0,faction,AI.SETTINGS.normal)
			for order:Dictionary in sim.entities[yard].queue:built[order.spec]=true
			check(sim.money[0]<100000,"T2 production spends actual funds "+faction+str(phase))
		check(built.has(faction+"_ship_aa") and built.has(faction+"_ship_frigate"),faction+" T2 basic and dedicated AA catalog")
		for spec:String in built:check(not bool(rules.units[spec].get("roster_hidden",false)),"AI respects faction naval roster "+spec)
		var special:String={"kestrel":"ship_frigate","rivet":"amphibious","iron":"submarine","sky":"hovercraft"}[faction]
		check(built.has(faction+"_"+special),faction+" faction naval specialty is produced")
		check(not built.has(faction+"_carrier") and not built.has(faction+"_support_ship"),faction+" T2 respects advanced ship technology")
		sim._spawn(0,faction+"_tech",Vector2(8,17),true)
		built.clear()
		for phase in [4,5]:
			sim.time=phase*12.0;sim.money[0]=100000
			for e:Dictionary in sim.entities.values():
				if e.kind=="building":e.queue.clear()
			AI._produce(sim,0,faction,AI.SETTINGS.normal)
			for order:Dictionary in sim.entities[yard].queue:built[order.spec]=true
		check(built.has(faction+"_support_ship") and (built.has(faction+"_carrier")== (faction=="kestrel")),faction+" T3 support and exclusive carrier")
		for e:Dictionary in sim.entities.values():
			if e.kind=="building":e.queue.clear()
		sim.time=0.0;sim.money[0]=100000
		AI._produce(sim,0,faction,AI.SETTINGS.normal)
		check(not sim.entities[factory].queue.is_empty() and (sim.entities[factory].queue[0].spec==faction+"_amphibious")== (faction=="rivet"),faction+" island factory respects exclusive amphibious armor")
		for e:Dictionary in sim.entities.values():
			if e.kind=="building":e.queue.clear()
		sim.money[0]=0
		AI._produce(sim,0,faction,AI.SETTINGS.normal)
		check(sim.entities[yard].queue.is_empty() and sim.entities[factory].queue.is_empty() and sim.money[0]==0,faction+" no money creates no ship")
	print("V3_NAVAL_AI ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
