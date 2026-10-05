extends SceneTree
const Sim=preload("res://tests/rule_test_simulation.gd")
var checks:int=0
var failures:Array[String]=[]
func compare(sim,method:String,args:Array,label:String)->void:
	sim.native_geometry_enabled=true
	var fast:Variant=sim.callv(method,args)
	sim.native_geometry_enabled=false
	var expected:Variant=sim.callv(method,args)
	checks+=1
	if fast!=expected and failures.size()<20:failures.append(label+": "+str(fast)+" != "+str(expected))
func prepare(sim)->void:
	sim._spec_cache=sim.rules.units.duplicate();sim._spec_cache.merge(sim.rules.buildings)
	sim._in_step=true;sim.native_geometry_enabled=true;sim._prepare_native_queries()
	if not sim._native_geometry_ready:failures.append("native geometry configuration did not activate")
func _initialize()->void:
	if not ClassDB.class_exists("PaperFrontKernels"):
		push_error("Native geometry kernel missing");quit(1);return
	var sim=Sim.new()
	sim.setup(RulesLoader.load_rules(),"dev",7,"rivet",false)
	var rng:=RandomNumberGenerator.new();rng.seed=73026
	for i in range(24):sim._spawn(i%2,sim.factions[i%2]+("_tank" if i%3==0 else "_rifle"),Vector2(3.5+i*1.6,43.5),true)
	var wall:int=sim._spawn(0,"rivet_barricade",Vector2(16.5,40.5),true)
	prepare(sim)
	for stage in range(3):
		if stage==1:
			for i in range(20):sim.mines.append({"pos":Vector2(3.25+float(i)*1.9,39.25),"amount":1000.0,"capacity":1000.0,"miner":-1})
			sim._refresh_mine_spatial();prepare(sim)
		if stage==2:
			sim.bridges[0].alive=false
			sim._kill_entity(wall,true)
			for ruin in sim.ruins:
				if ruin.kind=="tree":ruin.hp=0.0;break
			prepare(sim)
		for i in range(1500):
			var p:=Vector2(rng.randf_range(-1,49),rng.randf_range(-1,49))
			var radius:float=[0.0,.35,.5,.75,.85,1.1,2.2][i%7]
			compare(sim,"_standing",[p,radius,-1,i%2==0],"standing stage %d sample %d"%[stage,i])
			var end:Vector2=p+Vector2.from_angle(rng.randf_range(-PI,PI))*rng.randf_range(0,8)
			compare(sim,"_segment_static",[p,end,radius,-1],"segment stage %d sample %d"%[stage,i])
			if i%15==0:compare(sim,"_near_stand",[p,radius,-1,2.4,i%2==0],"nearest stand stage %d sample %d"%[stage,i])
		for unit in sim.entities.values():
			if unit.kind!="unit":continue
			var original:Vector2=unit.pos
			unit.pos+=Vector2(.8,0);sim._spatial_move(unit,original,unit.pos)
			compare(sim,"_standing",[unit.pos,.35,int(unit.id),true],"live spatial movement")
	sim._in_step=false
	print("NATIVE_GEOMETRY ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
