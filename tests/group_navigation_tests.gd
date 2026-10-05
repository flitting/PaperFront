extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Rules=preload("res://scripts/rules_loader.gd")
var failures:Array[String]=[]
var checks:=0
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label)
func tick(sim,seconds:float):
	for i in range(roundi(seconds*30)):
		sim.step(1.0/30);sim.events.clear()
func fixture()->Dictionary:
	var sim=Sim.new();sim.setup(Rules.load_rules(),"dev",7,"rivet",false)
	# The original valid map is retained. Two real four-cell buildings leave
	# a two-cell-wide southern passage which requires half-cell nav samples.
	sim.debug_spawn(0,"rivet_factory",Vector2(24,38))
	sim.debug_spawn(0,"rivet_factory",Vector2(24,44))
	var ids:Array=[]
	for i in range(6):ids.append(sim.debug_spawn(0,"rivet_tank",Vector2(14+(i%3)*1.9,40+(i/3)*1.9)))
	sim.issue(ids,"move",Vector2(33,41))
	return {"sim":sim,"ids":ids}
func find_owner(sim)->int:
	for i in range(900):
		sim.step(1.0/30);sim.events.clear()
		for gate in sim.group_navigation.gates:
			for id in gate.owners:
				if sim.entities[id].pos.x>22 and sim.entities[id].pos.x<26:return id
	return -1
func _initialize():
	var f:=fixture();var sim=f.sim
	var head:int=find_owner(sim)
	check(head>0,"real building gap creates an occupied shared reservation")
	check(sim.group_navigation.plans==1,"one static route serves the six-unit group")
	if head>0:
		var path: String="/tmp/paperfront-group-save.pfront"
		check(sim.save_game(path).is_empty(),"active queue saves")
		var restored=Sim.new()
		var error:String=restored.load_game(path)
		check(error.is_empty(),"active queue loads: "+error)
		if error.is_empty():
			check(restored.group_navigation.snapshot()==sim.group_navigation.snapshot(),"reservation owners and waiting order restore exactly")
			for i in range(30):sim.step(1.0/30);restored.step(1.0/30)
			check(restored.entities==sim.entities,"restored queue advances without reordering or teleporting")
			var file=FileAccess.open(path,FileAccess.READ);var bad:Dictionary=file.get_var(false);file.close()
			bad.group_navigation.gates[0].owners=["bad"]
			file=FileAccess.open(path,FileAccess.WRITE);file.store_var(bad);file.close()
			var before:Dictionary=restored.entities.duplicate(true)
			check(not restored.load_game(path).is_empty() and restored.entities==before,"corrupt reservations reject atomically")
		sim.debug_spawn(0,"rivet_power",Vector2(41.5,7.5))
		sim.step(1.0/30)
		check(sim.group_navigation.gates.any(func(g):return g.owners.has(head)),"topology refresh preserves incumbents already in the passage")
		# Deliberately hold the lead unit in the neck, then release it.
		var stopped:Vector2=sim.entities[head].pos
		sim.issue([head],"hold",stopped)
		var plans:int=sim.group_navigation.plans
		tick(sim,4)
		check(sim.entities[head].pos==stopped,"hold in passage stays physically occupied")
		check(sim.group_navigation.plans==plans,"followers wait on their existing shared route")
		check(f.ids.all(func(id):return sim.entities[id].state!="unreachable"),"temporary occupation never becomes an unreachable route")
		sim.issue([head],"move",Vector2(33,41))
		tick(sim,110)
		check(f.ids.all(func(id):return sim.entities[id].commands.is_empty()),"resuming the head drains the queue")
	# Death cancels both the membership and reservation without a permanent lock.
	f=fixture();sim=f.sim;head=find_owner(sim)
	if head>0:
		sim._kill_entity(head,true)
		tick(sim,100)
		check(f.ids.all(func(id):return id==head or sim.entities[id].commands.is_empty()),"destroyed leader does not leave a stale passage lock")
	# Random scenery groups contain exactly one type and remain reproducible.
	var a:Dictionary=MapData.generate("handmade",73026)
	var b:Dictionary=MapData.generate("handmade",73026)
	var c:Dictionary=MapData.generate("handmade",73027)
	check(a.ruins==b.ruins and a.ruins!=c.ruins,"seeded scenery is repeatable and changes with the seed")
	var kinds:Dictionary={}
	for ruin in a.ruins:
		if ruin.kind not in ["wall", "house"]: continue
		if not kinds.has(ruin.group):kinds[ruin.group]=ruin.kind
		check(kinds[ruin.group]==ruin.kind,"no mixed wall/building clusters")
	check(kinds.values().has("wall") and kinds.values().has("house"),"both independent scenery types are present")
	print("GROUP_NAVIGATION ",checks-failures.size(),"/",checks)
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
