extends SceneTree
const Sim=preload("res://scripts/simulation.gd")
const Worker=preload("res://scripts/path_worker.gd")
var checks:=0
var failures:Array[String]=[]
var evidence:Array=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func fixture():
	var sim=Sim.new();sim.map_generation_config={"legacy_dev48":true};sim.setup(RulesLoader.load_rules(),"dev",707,"iron",false)
	check(int(sim.map.size)==48,"historical corridor fixture explicitly remains48x48, so wall cannot be bypassed")
	for id in sim.entities.keys():sim._kill_entity(id,false)
	sim.mines.clear();sim.bridges.clear();sim.map.bridges.clear();sim.ruins.clear();sim._refresh_ruin_spatial();sim._refresh_mine_spatial()
	for row in sim.map.terrain:row.fill(0)
	for row in sim.map.heights:row.fill(0.0)
	sim._prepare_terrain_cache();sim._nav_initialized=false;sim._rebuild_nav();sim._rebuild_spatial()
	return sim
func prepare_native(sim)->void:
	sim._spec_cache=sim.rules.units.duplicate();sim._spec_cache.merge(sim.rules.buildings)
	sim._rebuild_spatial();sim._in_step=true;sim._prepare_native_queries()
func close(sim)->void:
	sim._in_step=false
	if sim._path_worker!=null:sim._path_worker.close()
func classifications()->void:
	var sim=fixture();sim.synchronous_path_tests=true
	var infantry:int=sim._spawn(0,"iron_rifle",Vector2(8,10),true)
	var tank:int=sim._spawn(0,"iron_tank",Vector2(8,14),true)
	var heavy:int=sim._spawn(0,"iron_heavy_tank",Vector2(8,18),true)
	var barrier:int=sim._spawn(0,"rivet_barricade",Vector2(20.5,20.5),true)
	var center:Vector2=sim.entities[barrier].pos
	sim._rebuild_nav();prepare_native(sim)
	check(sim.entities[infantry].radius==.5 and sim.entities[tank].radius==1.0 and sim.entities[heavy].radius==1.0,"current ordinary and heavy vehicles both have radius1 while infantry remains.5")
	check(sim._query_is_infantry(infantry) and not sim._is_ground_vehicle(sim.entities[infantry]),"infantry classified independently of radius")
	check(sim._is_ground_vehicle(sim.entities[tank]) and not sim._query_is_infantry(tank),"ordinary tank explicitly remains a ground vehicle")
	var crushable_armor:Dictionary=sim.rules.units.iron_tank.duplicate(true);crushable_armor.crushable=true
	sim._configure_crushing(sim.entities[tank],crushable_armor)
	check(sim._is_ground_vehicle(sim.entities[tank]) and not sim._query_is_infantry(tank),"explicit armored class wins over legacy crushable hint")
	sim._configure_crushing(sim.entities[tank],sim.rules.units.iron_tank)
	for backend in [false,true]:
		sim.native_geometry_enabled=backend;sim.native_movement_enabled=backend
		check(sim._building_clear(center,.5,infantry),"infantry passes barricade backend="+str(backend))
		check(not sim._building_clear(center,.5,tank),"same-radius tank blocked by barricade backend="+str(backend))
		check(not sim._building_clear(center,.5,-1),"unknown factory exit query conservative backend="+str(backend))
		check(sim._segment_static(center-Vector2(2,0),center+Vector2(2,0),.5,infantry),"infantry swept route crosses barricade backend="+str(backend))
		check(not sim._segment_static(center-Vector2(2,0),center+Vector2(2,0),.5,tank),"ordinary tank swept route rejects barricade backend="+str(backend))
		var e:Dictionary=sim.entities[tank];e.pos=Vector2(8,14);e.alpha=90.0;e.path=[Vector2(16,14)];e.path_goal=Vector2(16,14);e.path_wait=0;e.commands=[{"kind":"move","pos":Vector2(16,14),"target":-1}]
		var start:Vector2=e.pos;sim._move_to(e,Vector2(16,14),.01)
		check(e.pos==start and e.alpha<90 and e.state=="waiting","ordinary vehicle aligns before moving backend="+str(backend))
		var walker:Dictionary=sim.entities[infantry];walker.pos=center;walker.alpha=0;walker.path=[center+Vector2(3,0)];walker.path_goal=center+Vector2(3,0);walker.path_wait=0
		sim._rebuild_spatial();var before:Vector2=walker.pos;sim._move_to(walker,walker.path_goal,.02)
		var expected:float=float(sim.rules.units.iron_rifle.speed)*.02*.35
		check(is_equal_approx(before.distance_to(walker.pos),expected),"only infantry receives barricade walking slowdown backend="+str(backend))
		walker.pos=Vector2(8,10);sim._rebuild_spatial()
	sim._in_step=false
	sim.issue([infantry],"move",Vector2(18,10));sim.issue([tank],"move",Vector2(18,14))
	check(sim._traffic_priority(sim.entities[tank])>sim._traffic_priority(sim.entities[infantry]),"same-radius vehicles retain traffic precedence")
	var start:=Vector2(17.5,20.5);var goal:=Vector2(23.5,20.5)
	var first:int=sim._nav_point_for_radius(start,.5,infantry);var last:int=sim._nav_point_for_radius(goal,.5,infantry)
	var foot_path:Array=sim._wide_path(first,last,.5,infantry,goal,start)
	var tank_path:Array=sim._wide_path(first,last,.5,tank,goal,start)
	check(not foot_path.is_empty() and not tank_path.is_empty(),"both classes find valid routes with same radius")
	check(sim._wide_masks.has(Vector2(.5,0)) and sim._wide_masks.has(Vector2(.5,1)),"synchronous blocked-node caches separate radius and vehicle class")
	for point:Vector2 in tank_path:check(sim._building_clear(point,.5,tank),"tank detour contains no barricade node")
	close(sim)
func threaded_worker()->void:
	var size:=12;var ids:=PackedInt64Array();var edges:=PackedInt64Array();var terrain:=PackedByteArray();var land:=PackedByteArray();var heights:=PackedFloat32Array()
	terrain.resize(size*size);terrain.fill(0);land.resize(size*size);land.fill(1);heights.resize(size*size);heights.fill(0)
	for y in size:
		for x in size:
			var id:int=y*size+x;ids.append(id)
			if x<size-1:edges.append_array([id,id+1])
			if y<size-1:edges.append_array([id,id+size])
	var worker=Worker.new();worker.start({"size":size,"ids":ids,"edges":edges,"terrain":terrain,"land":land,"heights":heights,"masks":{.5:[]},"extra_positions":{},"extra_cells":{}})
	for n in range(3):
		var vehicle:bool=n==1
		var job:Dictionary={"id":n+1,"token":n+1,"revision":1,"radius":.5,"vehicle":vehicle,"start":Vector2(2.5,5.5),"goal":Vector2(9.5,5.5),"start_height":0.0,"goal_height":0.0,"geometry":{"hard":[],"vehicles":[Rect2(5,0,1,12)],"ruin_chunks":[]}}
		while not worker.submit(job):OS.delay_usec(100)
	var result:Dictionary={};var deadline:int=Time.get_ticks_msec()+10000
	while result.size()<3 and Time.get_ticks_msec()<deadline:
		for item in worker.collect():result[int(item.id)]=item.path
		OS.delay_usec(500)
	worker.close()
	check(result.size()==3,"all three real background jobs completed")
	if result.size()==3:
		check(result[1]==[Vector2(9.5,5.5)] and result[3]==result[1],"infantry path remains passable before and after tank job")
		check(result[2].is_empty(),"same-radius vehicle cannot cross full-height barricade wall")
	check(worker._graphs.size()==2 and worker._graphs.has(Vector2(.5,0)) and worker._graphs.has(Vector2(.5,1)),"real worker caches two different collider graphs for one radius")
func mixed_stress()->void:
	var sim=fixture();sim._spawn(0,"iron_hq",Vector2(5,43),true);sim._spawn(1,"kestrel_hq",Vector2(43,43),true)
	for y in range(48):
		if y in [22,23,24,25]:continue
		for x in range(21,27):sim.map.terrain[y][x]=4
	sim._prepare_terrain_cache();sim._nav_initialized=false;sim._rebuild_nav()
	var ids:Array[int]=[];var initial:Dictionary={}
	for n in range(48):
		var pos:=Vector2(3.5+(n%8)*2.05,6.5+int(n/8)*2.3)
		var id:int=sim._spawn(0,"iron_heavy_tank" if n%4==0 else "iron_tank",pos,true)
		# This is a navigation fixture: arrived tanks must not destroy the
		# remote enemy HQ and freeze the match before the last vehicles cross.
		# Movement, turning, yielding, radii and collision remain unmodified.
		sim.entities[id].cooldown=10000.0
		check(sim.entities[id].radius==1.0 and int(sim.data_for(sim.entities[id].spec).logical_size)==2,"stress vehicle has actual2x2 body")
		ids.append(id);initial[id]=pos
	sim._rebuild_spatial();sim.issue(ids,"move",Vector2(37,24))
	var unsafe:=0;var crossed:=0;var tick_count:=0;var start_ms:int=Time.get_ticks_msec()
	for tick in range(5400):
		var before:Dictionary={}
		for id in ids:before[id]=sim.entities[id].pos
		sim.step(1.0/30.0);sim.events.clear();crossed=0;tick_count=tick+1
		for id in ids:
			var e:Dictionary=sim.entities[id]
			if e.pos.x>27.1:crossed+=1
			if not sim._segment_static(before[id],e.pos,sim._radius(e),id):unsafe+=1
		if crossed==48 or not sim.result.is_empty():break
		OS.delay_usec(400)
	check(sim.result.is_empty(),"navigation fixture remains live until every vehicle crosses")
	check(is_equal_approx(sim.time,float(tick_count)/30.0),"all stress ticks advance actual simulation time")
	check(crossed==48,"48 ordinary/heavy vehicles all at2x2 cross the four-cell passage")
	check(unsafe==0,"48-unit mixed stress preserves swept physical clearance")
	check(sim.navigation_stats.max_in_flight<=32,"mixed stress retains existing background job limit")
	var remaining:Array=[]
	for id in ids:
		var e:Dictionary=sim.entities[id]
		if e.pos.x>27.1:continue
		var diagnostic:Dictionary={}
		for field in ["id","spec","pos","alpha","state","path","path_goal","commands","motion","stuck","path_wait","yield_goal","yield_root","yield_until","reversing","avoid_dir","avoid_until"]:diagnostic[field]=e.get(field)
		diagnostic.worker=sim._path_requests.get(id,{})
		diagnostic.neighbors=[]
		for other_id in ids:
			var other:Dictionary=sim.entities[other_id]
			if other_id!=id and (other.pos as Vector2).distance_to(e.pos)<4:diagnostic.neighbors.append({"id":other.id,"pos":other.pos,"state":other.state,"path":other.path,"radius":other.radius})
		remaining.append(diagnostic)
	evidence.append({"units":48,"ordinary":36,"heavy":12,"corridor_cells":4,"crossed":crossed,"ticks":tick_count,"simulation_seconds":sim.time,"match_result":sim.result,"remaining":remaining,"unsafe_segments":unsafe,"wall_ms":Time.get_ticks_msec()-start_ms,"navigation":sim.navigation_stats})
	close(sim)
func run()->void:
	check(ClassDB.class_exists("PaperFrontKernels"),"native collision and movement kernel loaded")
	classifications();threaded_worker();mixed_stress()
	var result:Dictionary={"checks":checks,"failures":failures,"evidence":evidence}
	var file:=FileAccess.open("res://artifacts/rts_revision_v2_20261007/navigation/navigation_classification_checks.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	print("NAVIGATION_CLASSIFICATION ",JSON.stringify(result))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
