extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const SlowSim=preload("res://tests/slow_path_simulation.gd")
const Rules=preload("res://scripts/rules_loader.gd")
var failures:Array[String]=[]
var checks:int=0
func check(ok:bool,message:String):
	checks+=1
	if not ok:failures.append(message)
func _initialize()->void:
	var config:Dictionary=Rules.load_rules()
	var sim=SlowSim.new();sim.setup(config,"dev",7,"rivet",false)
	var ids:Array=[]
	for i in range(Sim.PATH_IN_FLIGHT+16):ids.append(sim.debug_spawn(0,"rivet_engineer",Vector2(4+(i%8)*1.05,40+(i/8)*1.05)))
	sim.issue(ids,"move",Vector2(17,42))
	check(ids.all(func(id):return not sim.entities[id].commands[0].has("formation")),"group reservations are no longer created")
	sim.build(1,"kestrel_power") # Rivet buildings use engineer placement; test a real paid classic order.
	var time_before:float=sim.time
	var build_before:float=sim.building_orders[1].remaining
	var worst:int=0
	var collect_max:int=0
	for i in range(60):
		var start:int=Time.get_ticks_usec()
		sim.step(1.0/30)
		worst=maxi(worst,Time.get_ticks_usec()-start)
		collect_max=maxi(collect_max,int(sim.navigation_stats.main_us))
		check(sim._path_in_flight<=Sim.PATH_IN_FLIGHT,"worker submissions stay bounded")
		sim.events.clear()
	check(worst<30000,"a 200ms background search cannot block a simulation tick")
	check(collect_max<5000,"main thread only exchanges bounded path messages")
	check(absf(sim.time-time_before-2)<.001 and absf(build_before-sim.building_orders[1].remaining-2)<.001,"simulation and construction advance while paths wait")
	check(not sim._planning_queue.is_empty(),"excess path requests wait instead of running synchronously")
	var first:int=ids[0]
	sim.issue([first],"stop",Vector2.ZERO)
	var pos:Vector2=sim.entities[first].pos
	# Allow an obsolete result to finish, then collect it without moving the unit.
	for i in range(80):
		OS.delay_msec(5)
		sim.step(1.0/30);sim.events.clear()
	check(sim.entities[first].commands.is_empty() and sim.entities[first].pos==pos,"a cancelled worker result cannot restart a stopped unit")
	check(int(sim.navigation_stats.discarded)>0,"obsolete request tokens are discarded")
	var original_revision:int=sim._path_revision
	sim.debug_spawn(0,"rivet_power",Vector2(17.5,43.5))
	var stamp:int=Time.get_ticks_usec();sim.step(1.0/30)
	check(Time.get_ticks_usec()-stamp<30000 and sim._path_revision>original_revision,"topology edits publish snapshots without rebuilding a live graph on the game thread")
	print("DELAYED_WORKER worst_tick_ms=",worst/1000.0," admin_ms=",collect_max/1000.0," stats=",sim.navigation_stats)
	var normal=Sim.new();normal.setup(config,"dev",7,"rivet",false)
	var unit:int=normal.debug_spawn(0,"rivet_engineer",Vector2(5.5,43.5))
	normal.issue([unit],"move",Vector2(18.5,43.5))
	for i in range(360):
		normal.step(1.0/30);normal.events.clear();OS.delay_msec(1)
	check(normal.entities[unit].commands.is_empty() and normal.entities[unit].pos.distance_to(Vector2(18.5,43.5))<.4,"a real worker path reaches a legal destination")
	var save:String="/tmp/paperfront-budget-save.pfront"
	normal.issue([unit],"move",Vector2(6.5,43.5));normal.step(1.0/30)
	check(normal.save_game(save).is_empty(),"saving while a path is pending succeeds")
	var loaded=Sim.new()
	check(loaded.load_game(save).is_empty() and loaded.entities[unit].commands==normal.entities[unit].commands,"save/load retains the order and restarts derived path work")
	for i in range(360):loaded.step(1.0/30);loaded.events.clear();OS.delay_msec(1)
	check(loaded.entities[unit].commands.is_empty(),"restored pending orders complete")
	var file=FileAccess.open(save,FileAccess.READ)
	var legacy:Dictionary=file.get_var(false);file.close()
	legacy.group_navigation={"groups":{},"gates":[],"plans":0,"grants":0,"waits":0}
	legacy.next_formation=8
	legacy.entities[unit].commands[0].formation=7
	legacy.entities[unit].commands[0].formation_goal=legacy.entities[unit].commands[0].pos
	legacy.entities[unit].traffic_active=true
	legacy.entities[unit].yield_goal=Vector2(20,43)
	file=FileAccess.open(save,FileAccess.WRITE);file.store_var(legacy);file.close()
	check(loaded.load_game(save).is_empty(),"legacy reservation saves remain loadable")
	check(not loaded.entities[unit].commands[0].has("formation") and not loaded.entities[unit].has("traffic_active") and loaded.entities[unit].yield_goal==Vector2.INF,"legacy gate and micro-yield state is discarded without dropping the command")
	print("PATH_BUDGET ",checks-failures.size(),"/",checks)
	for failure in failures:push_error(failure)
	# Closing the test trees also joins their worker threads cleanly.
	sim=null;normal=null;loaded=null
	quit(0 if failures.is_empty() else 1)
