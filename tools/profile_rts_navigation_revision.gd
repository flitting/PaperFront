extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
var output:="res://artifacts/rts_revision_navigation/after.json"
var rows:Array[Dictionary]=[]
var mixed_seconds:=40.0
var mixed_rows:=6
var full_window:=false
func _initialize()->void:call_deferred("run")
func fixture():
	var sim=Sim.new();sim.setup(RulesLoader.load_rules(),"dev",7,"iron",false)
	for id in sim.entities.keys():sim._kill_entity(id,false)
	sim.mines.clear();sim.bridges.clear();sim.ruins.clear();sim._refresh_ruin_spatial()
	sim.map.size=96
	sim.map.terrain=[]; sim.map.heights=[]
	for z in range(96):
		var terrain:Array=[]; var heights:Array=[]
		terrain.resize(96); terrain.fill(0); heights.resize(96); heights.fill(0.0)
		sim.map.terrain.append(terrain); sim.map.heights.append(heights)
	sim.debug_spawn(0,"iron_hq",Vector2(6,89));sim.debug_spawn(1,"kestrel_hq",Vector2(89,89)) # Remote from final96-unit parking; preserve ordinary victory/damage rules.
	sim._prepare_terrain_cache();sim._nav_initialized=false;sim._rebuild_nav();sim._rebuild_spatial()
	return sim
func sample(sim,ids:Array,seconds:float)->Dictionary:
	var start:int=Time.get_ticks_usec();var tick_us:Array=[];var completion:Dictionary={};var max_wait:=0.0;var max_local:=0;var max_admin:=0;var blocked_frames:=0;var unsafe:=0;var max_flight:=0;var original_hp:Dictionary={};var late_tracks:Dictionary={}
	for id in ids:original_hp[id]=sim.entities[id].hp
	for tick in range(roundi(seconds*30)):
		var previous:Dictionary={}
		for id in ids:previous[id]=sim.entities[id].pos
		var before:int=Time.get_ticks_usec();sim.step(1.0/30.0);tick_us.append(Time.get_ticks_usec()-before)
		for id in ids:
			if not sim.entities.has(id):continue
			var e:Dictionary=sim.entities[id]
			if e.commands.is_empty() and not completion.has(id):completion[id]=sim.time
			if str(e.state)=="waiting" and not e.commands.is_empty():blocked_frames+=1
			if sim.time>80 and tick%10==0 and not e.commands.is_empty():
				if not late_tracks.has(id):late_tracks[id]=[]
				late_tracks[id].append({"time":sim.time,"pos":e.pos,"alpha":e.alpha,"motion":e.motion,"state":e.state,"avoid_until":e.get("avoid_until",0),"yield":e.get("yield_goal",Vector2.INF)})
				if late_tracks[id].size()>90:late_tracks[id].pop_front()
			if (e.pos as Vector2).distance_to(previous[id])>.0001 and not sim._segment_static(previous[id],e.pos,sim._radius(e),id):unsafe+=1
		max_wait=maxf(max_wait,float(sim._planning_max_wait));max_local=maxi(max_local,int(sim.navigation_stats.get("local_us",0)));max_admin=maxi(max_admin,int(sim.navigation_stats.get("main_us",0)));max_flight=maxi(max_flight,int(sim.navigation_stats.get("in_flight",0)))
		sim.events.clear();OS.delay_usec(1000)
		if (completion.size()==ids.size() and not full_window) or sim.result!="":break
	tick_us.sort()
	var health_unchanged:=true
	for id in original_hp:
		if not sim.entities.has(id) or sim.entities[id].hp!=original_hp[id]:health_unchanged=false
	return {"late_tracks":late_tracks,"result":str(sim.result),"requested_simulation_seconds":seconds,"units":ids.size(),"arrived":completion.size(),"arrival_ratio":float(completion.size())/maxi(1,ids.size()),"simulation_seconds":sim.time,"wall_seconds":float(Time.get_ticks_usec()-start)/1000000.0,"completion_times":completion.values(),"blocked_unit_frames":blocked_frames,"unsafe_segments":unsafe,"health_unchanged":health_unchanged,"max_wait":max_wait,"tick_p95_us":tick_us[int(tick_us.size()*.95)] if not tick_us.is_empty() else 0,"local_max_us":max_local,"admin_max_us":max_admin,"max_flight":max_flight,"navigation":sim.navigation_stats.duplicate()}
func mixed()->void:
	var sim=fixture();var ids:Array=[]
	# Alternate bodies in tightly spaced rows, including tank/support/wheeled
	# vehicles and small infantry; every initial footprint is legal/nonoverlap.
	var roles:Array=["rifle","engineer","tank","scout","aa","repair_vehicle","artillery","anti"]
	for row in range(mixed_rows):
		for col in range(8):
			var id:int=sim.debug_spawn(0,"iron_"+str(roles[col]),Vector2(8.0+col*2.4,8.0+row*2.4));ids.append(id)
	# Real static blockers funnel the mixed group through an eight-metre gate.
	sim.ruins=[{"id":0,"kind":"wall","pos":Vector2(40,12),"half":Vector2(1,12),"hp":10000.0,"max_hp":10000.0},{"id":1,"kind":"wall","pos":Vector2(40,64),"half":Vector2(1,32),"hp":10000.0,"max_hp":10000.0}]
	sim._refresh_ruin_spatial();sim._nav_dirty=true;sim._rebuild_nav();sim.issue(ids,"move",Vector2(67,35))
	var row:Dictionary=sample(sim,ids,mixed_seconds)
	row.stalled=[]
	for id in ids:
		var e:Dictionary=sim.entities[id]
		if not e.commands.is_empty():row.stalled.append({"id":id,"spec":e.spec,"pos":e.pos,"goal":e.commands[0].pos,"path":e.path,"state":e.state,"stuck":e.stuck,"yield":e.get("yield_goal",Vector2.INF),"yield_root":e.get("yield_root",-1),"alpha":e.alpha,"neighbors":sim._neighbors(e.pos).map(func(other):return {"id":other.id,"pos":other.pos,"spec":other.spec,"state":other.state,"commands":other.commands,"yield":other.get("yield_goal",Vector2.INF)})})
	row.case="%d_mixed_eight_metre_gate"%ids.size();row.passed_gate=ids.all(func(id):return sim.entities[id].pos.x>42.0);rows.append(row)
	sim._path_worker.close();sim=null
func trapped()->void:
	var sim=fixture();var id:int=sim.debug_spawn(0,"iron_tank",Vector2(12,12));var blockers:Array=[]
	for p:Vector2 in [Vector2(13.65,12),Vector2(12,13.65),Vector2(12,10.35),Vector2(10.35,12)]:blockers.append(sim.debug_spawn(0,"iron_rifle",p))
	for blocker in blockers:sim.issue([blocker],"move",Vector2(19,12))
	sim.issue([id],"move",Vector2(28,12))
	if sim.has_method("set_player_navigation_priority"):sim.set_player_navigation_priority([id])
	var row:Dictionary=sample(sim,[id],20);row.case="selected_tank_in_moving_infantry";rows.append(row)
	sim._path_worker.close();sim=null
func chase()->void:
	var sim=fixture();var pursuer:int=sim.debug_spawn(0,"iron_tank",Vector2(6,20));var target:int=sim.debug_spawn(1,"kestrel_tank",Vector2(19,20))
	sim.entities[target].hp=100000.0;sim.entities[pursuer].hp=100000.0
	sim.issue([pursuer],"attack",sim.entities[target].pos,target);sim.issue([target],"move",Vector2(43,20))
	var moving_frames:=0;var waiting_frames:=0;var fires:=0;var errors:=0
	var start:int=Time.get_ticks_usec()
	for tick in range(600):
		sim.step(1.0/30.0)
		if float(sim.entities[pursuer].motion)>.0001:moving_frames+=1
		if str(sim.entities[pursuer].state)=="waiting":waiting_frames+=1
		for event:Dictionary in sim.events:
			if event.kind=="fire" and int(event.get("id",-1))==pursuer:fires+=1
		if not sim._standing(sim.entities[pursuer].pos,sim._radius(sim.entities[pursuer]),pursuer,false):errors+=1
		sim.events.clear();OS.delay_usec(1000)
	rows.append({"case":"tank_pursues_moving_tank","moving_frames":moving_frames,"waiting_frames":waiting_frames,"fires":fires,"unsafe_positions":errors,"pursuer_position":sim.entities[pursuer].pos,"target_position":sim.entities[target].pos,"distance":(sim.entities[pursuer].pos as Vector2).distance_to(sim.entities[target].pos),"wall_seconds":float(Time.get_ticks_usec()-start)/1000000.0,"navigation":sim.navigation_stats.duplicate()})
	sim._path_worker.close();sim=null
func run()->void:
	var args:=OS.get_cmdline_user_args();full_window="--full-window" in args;var index:int=args.find("--output");if index>=0 and index+1<args.size():output=args[index+1]
	for arg:String in args:
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	var duration_index:int=args.find("--mixed-seconds")
	if duration_index>=0 and duration_index+1<args.size():mixed_seconds=float(args[duration_index+1])
	var rows_index:int=args.find("--mixed-rows")
	if rows_index>=0 and rows_index+1<args.size():mixed_rows=int(args[rows_index+1])
	mixed();trapped();chase()
	var report:Dictionary={"scope":"Real asynchronous/native simulation fixtures; no rendering/FPS claim. One worker pool per case. Fixed30Hz sim;1ms wall yielding permits real workers to advance.","simulation_sha256":FileAccess.get_sha256("res://scripts/simulation.gd"),"native_sha256":FileAccess.get_sha256("res://assets/native/libpaper_front_kernels.so"),"rows":rows}
	DirAccess.make_dir_recursive_absolute(output.get_base_dir());var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "))
	print("MIXED_NAVIGATION ",JSON.stringify(rows))
	var mixed_row: Dictionary = rows[0]
	quit(0 if int(mixed_row.arrived) == int(mixed_row.units) and int(mixed_row.unsafe_segments) == 0 and bool(mixed_row.health_unchanged) and str(mixed_row.result).is_empty() and bool(mixed_row.passed_gate) else 1)
