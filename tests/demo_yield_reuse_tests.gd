extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Rules=preload("res://scripts/rules_loader.gd")
class JobTraceSim:
	extends "res://scripts/simulation.gd"
	var yield_origin_jobs:=0
	var assignments:=0
	func _request_movement_yield(e: Dictionary,other: Dictionary,start: Vector2,next: Vector2)->void:
		var before: Vector2=other.get("yield_goal",Vector2.INF)
		super._request_movement_yield(e,other,start,next)
		if before!=other.get("yield_goal",Vector2.INF):assignments+=1
	func _submit_path_jobs()->void:
		var pending: Dictionary={}
		for id in _planning_queue:
			if entities.has(id) and (entities[id].get("yield_goal",Vector2.INF) as Vector2).is_finite():pending[id]=true
		super._submit_path_jobs()
		for id in pending:
			if _path_requests.has(id) and _path_requests[id].status=="running":yield_origin_jobs+=1
var checks:=0
var failures: Array[String]=[]
var rows: Array[Dictionary]=[]
var output: String="res://artifacts/demo_20261004/navigation/yield_reuse.json"
var expect_reuse:=true
func _initialize()->void:call_deferred("run")
func check(ok: bool,label: String)->void:
	checks+=1
	if not ok:failures.append(label)
func run()->void:
	var args:=OS.get_cmdline_user_args();expect_reuse=not ("--expect-baseline" in args)
	for i in range(args.size()-1):
		if args[i]=="--output":output=args[i+1]
	for native_backend in [false,true]:two_tanks(native_backend)
	var report: Dictionary={"checks":checks,"failures":failures,"rows":rows,"expect_reuse":expect_reuse,"simulation_sha256":FileAccess.get_sha256("res://scripts/simulation.gd"),"worker_sha256":FileAccess.get_sha256("res://scripts/path_worker.gd"),"native_sha256":FileAccess.get_sha256("res://assets/native/libpaper_front_kernels.so")}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file==null:push_error("Cannot save yield reuse evidence");quit(2);return
	file.store_string(JSON.stringify(report,"  "));file.close()
	print("YIELD_REUSE ",checks-failures.size(),"/",checks," ",JSON.stringify(rows))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
func two_tanks(native_backend: bool)->void:
	var sim=JobTraceSim.new();var rules: Dictionary=Rules.load_rules();sim.setup(rules,"dev",7,"rivet",false)
	for id in sim.entities.keys():sim._kill_entity(id,false)
	sim.debug_spawn(0,"rivet_hq",Vector2(4,44));sim.debug_spawn(1,"kestrel_hq",Vector2(44,44))
	sim.mines.clear();sim.bridges.clear();sim.ruins.clear();sim._refresh_ruin_spatial()
	for z in range(48):
		for x in range(48):
			sim.map.terrain[z][x]=0 if x in [19,20] else 4
			sim.map.heights[z][x]=0.0
	sim._prepare_terrain_cache();sim._nav_initialized=false;sim._rebuild_nav()
	var requester: int=sim.debug_spawn(0,"rivet_tank",Vector2(20,12))
	var blocker: int=sim.debug_spawn(0,"rivet_tank",Vector2(20,13.52))
	var e: Dictionary=sim.entities[requester];var other: Dictionary=sim.entities[blocker]
	e.alpha=90.0;other.alpha=90.0
	var goal:=Vector2(20,20);sim.issue([requester],"move",goal)
	e.path=[goal];e.path_goal=goal;e.path_wait=2.0
	sim.native_geometry_enabled=native_backend;sim.native_movement_enabled=native_backend
	sim._rebuild_spatial();sim._spec_cache=rules.units.duplicate();sim._spec_cache.merge(rules.buildings);sim._in_step=true;sim._prepare_native_queries()
	sim._path_plans_remaining=2
	# Queue and really submit the blocker's old path. Cancelling must not
	# prematurely decrement the global running-job count.
	sim._background_path(other.pos,Vector2(20,36),.75,blocker);sim._submit_path_jobs()
	var prior_inflight: int=sim._path_in_flight
	check(prior_inflight==1,"old path request truly entered asynchronous worker")
	sim._avoidance_probes=96;sim._yield_requests=3;sim._local_nav_us=0
	sim._request_movement_yield(e,other,e.pos,(e.pos as Vector2)+Vector2(0,.0933333))
	var retreat: Vector2=other.get("yield_goal",Vector2.INF)
	var old_request_retained: bool=sim._path_requests.has(blocker)
	var direct_installed: bool=other.path==[retreat] and other.path_goal==retreat
	check(retreat.is_finite() and sim._segment_static(other.pos,retreat,.75,blocker),"selected yield retreat has a proven original-radius full static connector")
	check(direct_installed==expect_reuse and old_request_retained!=expect_reuse,"yield path state matches the explicitly requested baseline/reuse variant")
	check(sim._path_in_flight==prior_inflight,"cancel request preserves running count until its real result is collected")
	check(e.commands.size()==1 and e.commands[0].pos==goal and other.commands.is_empty(),"yield assignment preserves both original command queues")
	check(not native_backend or sim._native_geometry_ready,"native two-tank control actually uses configured geometry")
	sim._in_step=false
	var violations:=0;var completed_at: float=-1.0;var max_local:=0;var max_admin:=0
	for tick in range(600):
		var previous_e: Vector2=e.pos;var previous_other: Vector2=other.pos
		sim.step(1.0/30.0);sim.events.clear();OS.delay_usec(1000)
		max_local=maxi(max_local,int(sim.navigation_stats.get("local_us",0)));max_admin=maxi(max_admin,int(sim.navigation_stats.main_us))
		if not sim._standing(e.pos,.75,requester,false) or not sim._standing(other.pos,.75,blocker,false) or not sim._segment_static(previous_e,e.pos,.75,requester) or not sim._segment_static(previous_other,other.pos,.75,blocker) or e.pos.distance_to(other.pos)<1.52-.0001:violations+=1
		if e.commands.is_empty() and e.pos.distance_to(goal)<=.3:completed_at=sim.time;break
	check(completed_at>=0,"two real tanks complete the original move within unchanged 20sim seconds")
	check(violations==0,"every two-tank actual stride/position and pair margin is legal")
	check(sim.yield_origin_jobs==0 if expect_reuse else sim.yield_origin_jobs>0,"already validated yield retreat avoids new origin AStar jobs only in reuse variant")
	check(sim._path_in_flight<=Sim.PATH_IN_FLIGHT and sim._avoidance_probes>=0 and sim._yield_requests>=0 and max_admin<750,"configured worker/probe/request/admin budgets remain bounded")
	rows.append({"backend":"native" if native_backend else "script","completed_at":completed_at,"assignments":sim.assignments,"yield_origin_jobs":sim.yield_origin_jobs,"navigation":sim.navigation_stats.duplicate(),"static_pair_violations":violations,"max_local_us":max_local,"max_admin_us":max_admin,"direct_path_installed":direct_installed,"old_request_retained":old_request_retained,"prior_inflight":prior_inflight,"final_inflight":sim._path_in_flight})
	sim=null
