extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const SlowSim=preload("res://tests/slow_path_simulation.gd")
const Worker=preload("res://scripts/path_worker.gd")
var checks:=0
var failures:Array[String]=[]
var rows:Array[Dictionary]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func fixture(slow:bool=false):
	var sim=SlowSim.new() if slow else Sim.new()
	sim.setup(RulesLoader.load_rules(),"dev",7,"iron",false)
	for id in sim.entities.keys():sim._kill_entity(id,false)
	sim.mines.clear();sim.bridges.clear();sim.ruins.clear();sim._refresh_ruin_spatial()
	for z in range(48):
		for x in range(48):sim.map.terrain[z][x]=0;sim.map.heights[z][x]=0.0
	sim._spawn(0,"iron_hq",Vector2(5,43),true);sim._spawn(1,"kestrel_hq",Vector2(43,43),true)
	sim._prepare_terrain_cache();sim._nav_initialized=false;sim._rebuild_nav();sim._rebuild_spatial()
	return sim
func priority_dispatch()->void:
	var sim=fixture(true);var background:Array=[]
	for i in range(32):background.append(sim.debug_spawn(1,"kestrel_rifle",Vector2(5+i%8*1.5,5+int(i/8)*1.5)))
	var selected:int=sim.debug_spawn(0,"iron_tank",Vector2(5,18))
	sim.issue(background,"move",Vector2(30,10))
	sim._in_step=true;sim._path_plans_remaining=32
	for id in background:sim._background_path(sim.entities[id].pos,sim.entities[id].commands[0].pos,sim._radius(sim.entities[id]),id)
	sim._submit_path_jobs()
	check(sim._path_in_flight>0 and sim._path_in_flight<=28,"background submissions leave four genuine foreground slots without increasing32-job cap")
	check(not sim._planning_queue.is_empty(),"real slow background queue remains before foreground order")
	sim.issue([selected],"move",Vector2(28,18));sim.set_player_navigation_priority([selected])
	sim._background_path(sim.entities[selected].pos,Vector2(28,18),sim._radius(sim.entities[selected]),selected)
	sim._path_plans_remaining=32;sim._submit_path_jobs()
	check(sim._path_requests[selected].status=="running" and sim._planning_queue.any(func(id):return background.has(id)),"selected new order dispatches ahead of a real slow AI backlog")
	check(sim._navigation_priority(selected)==3,"selection receives foreground navigation priority")
	sim.set_player_navigation_priority([])
	check(sim._navigation_priority(selected)==2,"deselected recent player order retains short command priority")
	sim.time=4.0
	check(sim._navigation_priority(selected)==0,"short command priority expires")
	sim._in_step=false;sim._path_worker.close()
	# Queued work changes priority in place; leaving selection removes its boost.
	var worker=Worker.new()
	worker._jobs.assign([{"id":1,"token":1,"priority":0,"base_priority":0},{"id":2,"token":2,"priority":2,"base_priority":2},{"id":3,"token":3,"priority":0,"base_priority":0}])
	worker.prioritize({3:true})
	check(worker._jobs[0].id==3 and worker._jobs[1].id==2,"already queued selected work passes background work")
	worker.prioritize({})
	check(worker._jobs[0].id==2 and worker._jobs[1].id==1 and worker._jobs[2].id==3,"deselection restores base priority and equal-priority FIFO")
func vehicle_yield()->void:
	var sim=fixture();sim.synchronous_path_tests=true
	var infantry:int=sim.debug_spawn(0,"iron_rifle",Vector2(13.3,12))
	var tank:int=sim.debug_spawn(0,"iron_tank",Vector2(12,12))
	var e:Dictionary=sim.entities[tank];var other:Dictionary=sim.entities[infantry]
	sim.issue([infantry],"move",Vector2(24,12));sim.issue([tank],"move",Vector2(28,12))
	other.path=[Vector2(24,12)];other.path_goal=Vector2(24,12)
	sim._rebuild_spatial();sim._request_movement_yield(e,other,e.pos,e.pos+Vector2(.1,0))
	var retreat:Vector2=other.yield_goal
	check(retreat.is_finite() and tank>infantry,"later-spawned vehicle can ask an earlier moving infantry body to yield")
	check(other.commands[0].pos==Vector2(24,12) and other.hp==float(sim.data_for(other.spec).hp),"gentle yield preserves infantry destination and health")
	check(sim._segment_static(other.pos,retreat,sim._radius(other),infantry),"whole retreat connector preserves original body radius")
	var original_goal:Vector2=other.commands[0].pos
	other.pos=retreat;sim._complete_movement_yield(other)
	check(not other.yield_goal.is_finite() and not other.has("yield_root") and other.path==[original_goal],"yield completion clears inherited precedence and rejoins visible route suffix")
	other.yield_goal=Vector2.INF;other.hold_position=true
	sim._request_movement_yield(e,other,e.pos,e.pos+Vector2(.1,0))
	check(not other.yield_goal.is_finite(),"hold-position infantry is not pushed aside")
	other.hold_position=false;other.commands.clear();sim.set_player_navigation_priority([infantry])
	check(sim._traffic_may_yield(e,other),"selected but arrived idle teammate still yields to active rear traffic")
	other.commands=[{"kind":"move","pos":Vector2(24,12),"target":-1}];other.team=1
	check(not sim._traffic_may_yield(e,other) and bool(e.can_crush) and bool(other.crushable),"ordinary friendly yielding does not replace enemy crushing rules")
	other.team=0;sim.map.heights[floori(other.pos.y)][floori(other.pos.x)]=2.0;sim._prepare_terrain_cache()
	check(not sim._traffic_may_yield(e,other),"yield precedence never crosses different terrain levels")
	sim.map.heights[floori(other.pos.y)][floori(other.pos.x)]=0.0;sim._prepare_terrain_cache();other.yield_saved_path=[Vector2(24,12)];other.yield_saved_goal=Vector2(24,12);other.yield_saved_revision=sim._static_geometry_revision
	sim.issue([infantry],"move",Vector2(20,20))
	check(not other.has("yield_saved_path"),"a new command cannot resurrect an obsolete pre-yield route")

	sim._path_worker.close()
func chase(native_backend:bool,blocked:bool)->void:
	var sim=fixture()
	sim.native_unit_dispatch_enabled=native_backend;sim.native_geometry_enabled=native_backend;sim.native_movement_enabled=native_backend
	var pursuer:int=sim.debug_spawn(0,"iron_tank",Vector2(7,12) if blocked else Vector2(6,20))
	var target:int=sim.debug_spawn(1,"kestrel_tank",Vector2(28,12) if blocked else Vector2(19,20))
	if blocked:
		sim.ruins=[{"id":0,"kind":"wall","pos":Vector2(18,12),"half":Vector2(.8,7),"hp":10000.0,"max_hp":10000.0}]
		sim._refresh_ruin_spatial();sim._nav_dirty=true;sim._rebuild_nav()
	sim.rules.units.iron_tank.hp=100000.0;sim.rules.units.kestrel_tank.hp=100000.0
	sim.entities[target].hp=100000.0;sim.entities[pursuer].hp=100000.0
	sim.issue([pursuer],"attack",sim.entities[target].pos,target)
	sim.issue([target],"move",Vector2(35,24) if blocked else Vector2(43,20))
	var fires:=0;var waiting:=0;var moving:=0;var unsafe:=0;var max_jobs:=0
	for tick in range(900 if blocked else 600):
		var before:Vector2=sim.entities[pursuer].pos
		sim.step(1.0/30.0)
		var e:Dictionary=sim.entities[pursuer]
		if str(e.state)=="waiting":waiting+=1
		if float(e.motion)>.0001:moving+=1
		if not sim._segment_static(before,e.pos,sim._radius(e),pursuer):unsafe+=1
		for event:Dictionary in sim.events:
			if event.kind=="fire" and int(event.get("id",-1))==pursuer:fires+=1
		max_jobs=maxi(max_jobs,sim._path_in_flight);sim.events.clear();OS.delay_usec(1000)
	check(fires>=3 and moving>100,"%s/%s moving-target pursuit reaches repeated firing range"%[native_backend,blocked])
	check(waiting<180 if blocked else waiting<10,"%s/%s pursuit does not repeatedly stop for stale path_wait"%[native_backend,blocked])
	check(unsafe==0 and max_jobs<=32,"%s/%s pursuit retains swept static safety and global job cap"%[native_backend,blocked])
	check(int(sim.navigation_stats.submitted)<80 and sim.navigation_pursuit_refreshes<=155,"%s/%s target movement keeps replanning and approach refresh bounded"%[native_backend,blocked])
	rows.append({"native":native_backend,"blocked":blocked,"fires":fires,"moving_frames":moving,"waiting_frames":waiting,"unsafe":unsafe,"requests":sim.navigation_stats.submitted,"refreshes":sim.navigation_pursuit_refreshes})
	sim._path_worker.close()
func run()->void:
	priority_dispatch();vehicle_yield()
	for native_backend in [false,true]:
		for blocked in [false,true]:chase(native_backend,blocked)
	var report:Dictionary={"checks":checks,"failures":failures,"rows":rows}
	var path:="res://artifacts/navigation_revision_20261007/checks/priority_pursuit.json"
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("NAVIGATION_PRIORITY_PURSUIT ",JSON.stringify(report))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
