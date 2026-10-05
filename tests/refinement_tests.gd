extends SceneTree
const Sim=preload("res://tests/rule_test_simulation.gd")
const Rules=preload("res://scripts/rules_loader.gd")
var checks:=0
var failures: Array[String]=[]
func check(ok: bool, message: String):
	checks+=1
	if not ok:failures.append(message)
func tick(sim,seconds:float):
	for i in range(roundi(seconds*30)):
		sim.step(1.0/30);sim.events.clear()
func _initialize():
	var config:=Rules.load_rules()
	var sim=Sim.new();sim.setup(config,"handmade",73026,"rivet",false)
	print("RUINS ",sim.ruins.size())
	check(sim.ruins.size()>=6,"new map contains grouped destructible compounds")
	var groups:Dictionary={}
	for ruin in sim.ruins:
		if ruin.kind not in ["wall", "house"]: continue
		groups[ruin.group]=int(groups.get(ruin.group,0))+1
	check(groups.values().all(func(n):return n in [2,3]),"same-kind scenery remains clustered")
	for group_id in groups:
		var members:Array=sim.ruins.filter(func(r):return r.kind in ["wall", "house"] and r.group==group_id)
		check(members.all(func(r):return r.kind==members[0].kind),"walls and houses never share a scenery cluster")
	check(sim.map.decorations.all(func(item):return item.kind not in ["rock","ruin"]),"solitary rock and ruin decorations removed")
	if not sim.ruins.is_empty():
		var ruin:Dictionary=sim.ruins[0]
		var target:int=sim.RUIN_TARGET_BASE-int(ruin.id)
		check(sim._target_alive(target) and sim._target_position(target)==ruin.pos,"neutral ruin is a valid attack target")
		check(not sim._standing(ruin.pos,.35,-1,false),"intact ruin blocks movement")
		var unit:int=sim.debug_spawn(0,"rivet_tank",ruin.pos+Vector2(-5,0))
		var hp_before: float = float(ruin.hp)
		sim.issue([unit],"attack",ruin.pos,target)
		tick(sim,2)
		check(float(ruin.hp)==hp_before,"ordinary attack cannot damage neutral scenery")
		sim.issue([unit],"force_attack",ruin.pos,target)
		tick(sim,40)
		check(float(ruin.hp)==0,"tank actually destroys targeted neutral ruin")
		check(sim._standing(ruin.pos,.75,-1,false),"destroyed ruin opens vehicle navigation")
		check(not sim._target_alive(target),"destroyed ruin no longer targetable")
		var save: String="/tmp/paperfront-refinement.pfront"
		check(sim.save_game(save).is_empty(),"ruin state saves")
		var restored=Sim.new()
		var error:String=restored.load_game(save)
		print("RUIN_SAVE ",error)
		check(error.is_empty() and restored.ruins[0].hp==0,"destroyed ruin remains cleared after load")
	# Active mining commands must override an earlier stop/move and retain the chosen mine.
	sim=Sim.new();sim.setup(config,"dev",7,"rivet",false)
	var mine:Dictionary=sim.mines[1]
	var truck:int=sim.debug_spawn(0,"rivet_harvester",mine.pos+Vector2(4,0))
	sim.issue([truck],"stop",Vector2.ZERO)
	sim.issue([truck],"harvest",mine.pos,1)
	tick(sim,7)
	check(sim.entities[truck].cargo>0 and sim.entities[truck].harvest_mine==1,"explicit harvest command gathers requested ore")
	check(sim.entities[truck].commands[0].kind=="harvest","manual harvest remains active for repeated trips")
	var refine:int=sim.debug_spawn(0,"rivet_refinery",Vector2(12,42))
	sim.entities[refine].gift_pending=false
	var funds:float=sim.money[0]
	tick(sim,60)
	check(sim.money[0]>funds,"ordered miner delivers a paid load")
	check(sim.entities[truck].preferred_mine==1,"ordered miner remembers preferred field after delivery")
	sim.issue([truck],"stop",Vector2.ZERO)
	var cargo:float=sim.entities[truck].cargo
	tick(sim,2)
	check(sim.entities[truck].cargo==cargo,"stop cancels active harvest")
	# Recovery from a destination occupied after the order was issued.
	var mover:int=sim.debug_spawn(0,"rivet_engineer",Vector2(5,43))
	sim.issue([mover],"move",Vector2(19,43))
	sim.debug_spawn(0,"rivet_power",Vector2(19.5,43.5))
	tick(sim,20)
	check(sim.entities[mover].commands.is_empty() and sim.entities[mover].pos.x>15,"new building at destination does not strand moving unit")
	print("REFINEMENT ",checks-failures.size(),"/",checks)
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
