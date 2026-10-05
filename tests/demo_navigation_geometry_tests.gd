extends SceneTree

const Sim = preload("res://scripts/simulation.gd")
const SyncSim = preload("res://tests/rule_test_simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
class TracedSim:
	extends "res://scripts/simulation.gd"
	var yield_trace: Array[Dictionary] = []
	func _request_movement_yield(e: Dictionary, other: Dictionary, start: Vector2, next: Vector2) -> void:
		var before: Vector2=other.get("yield_goal",Vector2.INF)
		super._request_movement_yield(e,other,start,next)
		var after: Vector2=other.get("yield_goal",Vector2.INF)
		if before!=after and yield_trace.size()<4096:
			yield_trace.append({"event":"assigned","time":time,"requester":e.id,"other":other.id,"requester_pos":str(e.pos),"other_pos":str(other.pos),
				"forward":str((next-start).normalized()),"goal":str(after),"expires":other.get("yield_until",0.0)})
	func step(delta: float) -> void:
		var active: Array[Dictionary]=[]
		for entity in entities.values():
			var before: Vector2=entity.get("yield_goal",Vector2.INF)
			if before.is_finite():active.append({"id":entity.id,"goal":before,"expires":float(entity.get("yield_until",0.0))})
		super.step(delta)
		for old in active:
			var entity: Dictionary=entities.get(old.id,{})
			if not entity.is_empty() and not (entity.get("yield_goal",Vector2.INF) as Vector2).is_finite() and yield_trace.size()<4096:
				yield_trace.append({"event":"expired" if time>=old.expires else "arrived","time":time,"id":old.id,"pos":str(entity.pos),"goal":str(old.goal),"expires":old.expires})
class RouteDiagnosticSim:
	extends "res://scripts/simulation.gd"
	var returned_routes: Array[Dictionary]=[]
	func _background_path(start: Vector2, goal: Vector2, radius: float, id: int) -> Array:
		var submitted: Dictionary=_path_requests.get(id,{}).duplicate(true)
		var path: Array=super._background_path(start,goal,radius,id)
		if not path.is_empty():
			var illegal: Array[Dictionary]=[]
			var swept_illegal: Array[Dictionary]=[]
			var previous:=start
			for index in range(path.size()):
				var point: Vector2=path[index]
				if not _segment_static(previous,point,radius,id):
					illegal.append({"index":index,"from":[previous.x,previous.y],"to":[point.x,point.y]})
				var exact_obstacles: Array[Dictionary]=[]
				for rectangle: Rect2 in _path_geometry.get("hard",[]):
					if _swept_circle_rect(previous,point,radius+.02,rectangle):exact_obstacles.append({"kind":"hard","rectangle":str(rectangle)})
				if radius>.5:
					for rectangle: Rect2 in _path_geometry.get("vehicles",[]):
						if _swept_circle_rect(previous,point,radius+.02,rectangle):exact_obstacles.append({"kind":"barricade","rectangle":str(rectangle)})
				for chunk in _path_geometry.get("ruin_chunks",[]):
					for rectangle: Rect2 in chunk.rectangles:
						if _swept_circle_rect(previous,point,radius+.02,rectangle):exact_obstacles.append({"kind":"ruin","rectangle":str(rectangle)})
				if not exact_obstacles.is_empty():swept_illegal.append({"index":index,"from":[previous.x,previous.y],"to":[point.x,point.y],"obstacles":exact_obstacles})
				previous=point
			returned_routes.append({"id":id,"time":time,"start":[start.x,start.y],"goal":[goal.x,goal.y],"radius":radius,
				"submitted_start":str(submitted.get("start",Vector2.INF)),"path":str(path),"illegal":illegal,"swept_illegal":swept_illegal})
		return path
var rules: Dictionary
var checks := 0
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var output := "res://artifacts/demo_20261004/navigation/geometry_checks.json"

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	for index in range(args.size()-1):
		if args[index] == "--output": output = args[index+1]
	rules = Rules.load_rules()
	if rules.is_empty():
		push_error("Geometry test rules invalid: " + str(Rules.errors))
		quit(2)
		return
	if "--load320-only" in args:
		load320(args)
	elif "--worker-connectors-only" in args:
		worker_connector_sweep("--reverse-connectors" in args)
	elif "--continuous-only" in args:
		continuous_geometry(false)
		continuous_geometry(true)
	elif "--corner-pop-only" in args:
		corner_waypoint_pop(false)
		corner_waypoint_pop(true)
	elif "--turning-connector-only" in args:
		turning_connector(false)
		turning_connector(true)
	elif "--yield-controls-only" in args:
		same_route_follower(false,true)
		same_route_follower(true,true)
		clear_first_hop(false)
		clear_first_hop(true)
	elif "--first-hop-only" in args:
		clear_first_hop(false)
		clear_first_hop(true)
	elif "--stale-only" in args:
		same_route_follower(false,true)
		same_route_follower(true,true)
	elif "--follower-only" in args:
		same_route_follower(false)
		same_route_follower(true)
	elif "--reverse-only" in args:
		reverse_retreat(false)
		reverse_retreat(true)
	elif "--dense-only" in args:
		dense_chain(false)
		dense_chain(true)
		worker_offset_corners()
	else:
		check(is_equal_approx(float(rules.units.rivet_tank.radius),.75), "real tank rules preserve radius .75 / diameter 1.5")
		check(is_equal_approx(float(rules.buildings.rivet_wall.size),1.0), "real wall occupies a one-meter square")
		for walls in [false,true]:
			for width in [2,1]:
				geometry_and_sync(width,walls)
				async_movement(width,walls)
		dense_chain(false)
		dense_chain(true)
		worker_offset_corners()
		reverse_retreat(false)
		reverse_retreat(true)
		same_route_follower(false)
		same_route_follower(true)
		same_route_follower(false,true)
		same_route_follower(true,true)
		clear_first_hop(false)
		clear_first_hop(true)
		yield_budget_controls(false)
		yield_budget_controls(true)
		corner_waypoint_pop(false)
		corner_waypoint_pop(true)
		turning_connector(false)
		turning_connector(true)
		continuous_geometry(false)
		continuous_geometry(true)
		sensitive_rounding_control(false)
		sensitive_rounding_control(true)
	if checks==0:check(false,"No geometry checks executed; test runtime failed before assertions")
	var report := {"schema":1,"checks":checks,"passed":checks-failures.size(),"failures":failures,"rows":rows,
		"tank_radius":rules.units.rivet_tank.radius,"wall_size":rules.buildings.rivet_wall.size,
		"scope":"headless geometry/path/collision rules; no rendered performance claim",
		"source_hashes":{"simulation":FileAccess.get_sha256("res://scripts/simulation.gd"),"worker":FileAccess.get_sha256("res://scripts/path_worker.gd"),"rules":FileAccess.get_sha256("res://data/rules.json")}}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file == null:
		push_error("Cannot write geometry report")
		quit(2)
		return
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("DEMO_NAV_GEOMETRY ",checks-failures.size(),"/",checks," ",JSON.stringify(rows))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func fixture(width: int, walls: bool, synchronous: bool, trace: bool=false):
	var sim = SyncSim.new() if synchronous else TracedSim.new() if trace else Sim.new()
	sim.setup(rules,"dev",7,"rivet",false)
	for z in range(48):
		for x in range(48):
			sim.map.terrain[z][x]=0
			sim.map.heights[z][x]=0.0
	sim.mines.clear()
	sim.bridges.clear()
	sim.ruins.clear()
	sim._refresh_ruin_spatial()
	for id in sim.entities.keys():sim._kill_entity(id,false)
	sim.debug_spawn(0,"rivet_hq",Vector2(4,44))
	sim.debug_spawn(1,"kestrel_hq",Vector2(44,44))
	for z in range(48):
		var in_opening: bool = z>=23 and z<23+width
		if walls: in_opening = z>=22 and z<24+width
		if in_opening:continue
		for x in range(21,27):sim.map.terrain[z][x]=4
	if walls:
		for x in range(21,27):
			sim.debug_spawn(0,"rivet_wall",Vector2(x+.5,22.5))
			sim.debug_spawn(0,"rivet_wall",Vector2(x+.5,23.5+width))
	sim._prepare_terrain_cache()
	sim._nav_initialized=false
	sim._rebuild_nav()
	sim._rebuild_spatial()
	return sim

func geometry_and_sync(width: int, walls: bool) -> void:
	var sim = fixture(width,walls,true)
	var radius: float = float(rules.units.rivet_tank.radius)
	var center := Vector2(24,23+float(width)*.5)
	var legal: bool = sim._standing(center,radius,-1,false)
	var expected: bool = width==2
	var label := ("real_walls" if walls else "terrain")+" width"+str(width)
	check(legal==expected,label+" center clearance follows actual occupied geometry")
	if walls:
		var wall_count := 0
		var bounds_ok := true
		for entity in sim.entities.values():
			if entity.spec!="rivet_wall":continue
			wall_count+=1
			var half: float = float(sim.data_for(entity.spec).size)*.5
			var y: float = float(entity.pos.y)
			bounds_ok = bounds_ok and (is_equal_approx(y+half,23.0) or is_equal_approx(y-half,23.0+width))
		check(wall_count==12 and bounds_ok,label+" twelve real walls define exact 23.."+str(23+width)+" gap")
	var start := Vector2(18.5,center.y)
	var finish := Vector2(29.5,center.y)
	var path: Array = sim._path_between(start,finish,radius,-1)
	check(not path.is_empty() if expected else path.is_empty(),label+" synchronous path availability matches geometry")
	var segments_legal := true
	var previous := start
	for point: Vector2 in path:
		segments_legal = segments_legal and sim._segment_static(previous,point,radius,-1)
		previous=point
	check(segments_legal,label+" every returned synchronous segment preserves real collision")
	rows.append({"case":label,"backend":"synchronous rule adapter","center": [center.x,center.y],"legal":legal,"path_points":path.size(),"segments_legal":segments_legal,
		"base_nodes":sim._terrain_nav_ids.size()-sim._terrain_nav_extra_positions.size(),"detail_nodes":sim._terrain_nav_extra_positions.size(),"occupied_gap_width":width})
	sim=null

func async_movement(width: int, walls: bool) -> void:
	var sim = fixture(width,walls,false)
	var center_y: float = 23.0+float(width)*.5
	var start := Vector2(18.5,center_y)
	var goal := Vector2(29.5,center_y)
	var id: int = sim.debug_spawn(0,"rivet_tank",start)
	check(id>0,"async fixture spawns a real tank")
	sim.issue([id],"move",goal)
	var had_path := false
	var all_segments_legal := true
	var all_positions_legal := true
	var maximum_in_flight := 0
	var started := Time.get_ticks_usec()
	for tick in range(900 if width==2 else 180):
		sim.step(1.0/30.0)
		sim.events.clear()
		OS.delay_usec(1000)
		maximum_in_flight=maxi(maximum_in_flight,sim._path_in_flight)
		var entity: Dictionary = sim.entities[id]
		all_positions_legal=all_positions_legal and sim._standing(entity.pos,float(entity.radius),id,false)
		var previous: Vector2 = entity.pos
		for point: Vector2 in entity.path:
			had_path=true
			all_segments_legal=all_segments_legal and sim._segment_static(previous,point,float(entity.radius),id)
			previous=point
		if entity.commands.is_empty():break
	var entity: Dictionary = sim.entities[id]
	var arrived: bool = entity.commands.is_empty() and (entity.pos as Vector2).distance_to(goal)<.4
	var label := ("real_walls" if walls else "terrain")+" width"+str(width)
	check(arrived if width==2 else not had_path and not arrived,label+" live worker moves through legal gap and refuses sub-diameter gap")
	check(all_positions_legal and all_segments_legal,label+" live worker route and movement keep strict collision")
	check(maximum_in_flight<=Sim.PATH_IN_FLIGHT and sim.navigation_stats.completed>0,label+" real background jobs finish within in-flight limit")
	rows.append({"case":label,"backend":"live asynchronous worker","arrived":arrived,"had_path":had_path,"segments_legal":all_segments_legal,
		"positions_legal":all_positions_legal,"position":[entity.pos.x,entity.pos.y],"sim_seconds":sim.time,"wall_seconds":float(Time.get_ticks_usec()-started)/1000000.0,
		"maximum_in_flight":maximum_in_flight,"navigation":sim.navigation_stats.duplicate()})
	sim=null

func load320(args: PackedStringArray) -> void:
	var simulation_script: GDScript = RouteDiagnosticSim
	var baseline := "--baseline" in args
	if baseline:
		var source := FileAccess.get_file_as_string("res://artifacts/demo_20261004/navigation/source_before_fix/simulation.gd")
		simulation_script=GDScript.new()
		simulation_script.source_code=source.replace("class_name WarSimulation\n","")
		check(simulation_script.reload()==OK,"frozen pre-fix navigation source compiles without registering a second global class")
		if not failures.is_empty():return
	var modes: Array[String]=["forest","desert","snow","city","random_city","islands"]
	for index in range(args.size()-1):
		if args[index]=="--map":modes=[str(args[index+1])]
	for mode in modes:
		var sim = simulation_script.new()
		var memory_before := OS.get_static_memory_usage()
		var start := Time.get_ticks_usec()
		var owners: Array[String]=["kestrel","rivet","iron","sky"]
		sim.setup_multiteam(rules,mode,73026,owners,false)
		var setup_ms := float(Time.get_ticks_usec()-start)/1000.0
		var extra_nodes: int = sim._terrain_nav_extra_positions.size() if "_terrain_nav_extra_positions" in sim else 0
		check(sim.map.size==320 and sim.map.valid,mode+" actual four-faction 320 map starts valid")
		check(sim._nav_initialized and sim._path_worker!=null,mode+" actual navigation and worker initialize")
		var row: Dictionary={"map":mode,"baseline":baseline,"seed":73026,"size":sim.map.size,"teams":sim.factions,"setup_ms":setup_ms,
			"effective_simulation_source_sha256":FileAccess.get_sha256("res://artifacts/demo_20261004/navigation/source_before_fix/simulation.gd" if baseline else "res://scripts/simulation.gd"),
			"startup_profile":sim.startup_profile.duplicate(),"base_nodes":sim._terrain_nav_ids.size()-extra_nodes,"detail_nodes":extra_nodes,"edges":sim._terrain_nav_edges.size()/2,
			"static_memory_before_bytes":memory_before,"static_memory_after_setup_bytes":OS.get_static_memory_usage(),"static_memory_peak_bytes":OS.get_static_memory_peak_usage(),
			"terrain_mask_count":sim._terrain_masks.size(),"path_admin_budget_us":Sim.PATH_ADMIN_BUDGET_US,"path_in_flight_limit":Sim.PATH_IN_FLIGHT,
			"navigation_identity":navigation_identity(sim)}
		if not baseline:row["route_validation"]=validate320_routes(sim,mode)
		row["static_memory_after_routes_bytes"]=OS.get_static_memory_usage()
		rows.append(row)
		sim=null

func signature(value: Variant) -> String:
	var context:=HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(value))
	return context.finish().hex_encode()

func navigation_identity(sim) -> Dictionary:
	# Test-only fingerprints are computed after setup_ms has been captured.
	# All configured ground radii matter even when this fixture has no such unit.
	var radii: Dictionary={}
	for info: Dictionary in rules.units.values():
		if str(info.get("domain","ground"))=="ground":radii[snappedf(float(info.radius),.01)]=true
	var ordered_radii: Array=radii.keys()
	ordered_radii.sort()
	var ground_masks: Dictionary={}
	var complete:=true
	for radius: float in ordered_radii:
		var available: bool=sim._terrain_masks.has(radius)
		complete=complete and available
		var ids: Array=sim._terrain_masks.get(radius,[]).duplicate()
		ids.sort()
		ground_masks[str(radius)]={"present":available,"blocked_count":ids.size(),"sha256":signature(ids)}
	var extra_positions: Array=[]
	if "_terrain_nav_extra_positions" in sim:
		var extra_ids: Array=sim._terrain_nav_extra_positions.keys()
		extra_ids.sort()
		for id in extra_ids:extra_positions.append([int(id),sim._terrain_nav_extra_positions[id]])
	check(complete,"all configured ground terrain masks remain prewarmed")
	return {"terrain_node_ids_sha256":signature(sim._terrain_nav_ids),"terrain_edges_sha256":signature(sim._terrain_nav_edges),
		"detail_positions_sha256":signature(extra_positions),"ground_masks":ground_masks,"all_configured_ground_masks_warm":complete}

func dense_chain(hold_middle: bool) -> void:
	var sim = fixture(2,false,false,true)
	# Three touching safety margins in a legal 2m vertical lane. No vacant
	# endpoint exists for the middle tank; movement must clear the chain over
	# subsequent ticks without bypassing collision or pushing a held tank.
	for z in range(48):
		for x in range(48): sim.map.terrain[z][x]=0 if x in [19,20] else 4
	sim._prepare_terrain_cache()
	sim._nav_initialized=false
	sim._rebuild_nav()
	var ids: Array[int] = []
	for index in range(3):
		var id: int=sim.debug_spawn(0,"rivet_tank",Vector2(20,12+index*1.52))
		ids.append(id)
		sim.entities[id].alpha=90.0
	if hold_middle: sim.issue([ids[1]],"hold",Vector2.ZERO)
	var held_position: Vector2=sim.entities[ids[1]].pos
	sim.issue([ids[0]],"move",Vector2(20,30))
	var legal := true
	var propagated := false
	var budget_bounded := true
	var started := Time.get_ticks_usec()
	for tick in range(1800 if not hold_middle else 180):
		sim.step(1.0/30.0)
		sim.events.clear()
		OS.delay_usec(1000)
		budget_bounded=budget_bounded and sim._yield_requests>=0 and sim._path_in_flight<=Sim.PATH_IN_FLIGHT
		if (sim.entities[ids[1]].get("yield_goal",Vector2.INF) as Vector2).is_finite() and (sim.entities[ids[2]].get("yield_goal",Vector2.INF) as Vector2).is_finite(): propagated=true
		for index in range(ids.size()):
			var entity: Dictionary=sim.entities[ids[index]]
			legal=legal and sim._standing(entity.pos,float(entity.radius),ids[index],false)
			for other_index in range(index+1,ids.size()):
				legal=legal and (entity.pos as Vector2).distance_to(sim.entities[ids[other_index]].pos)>=1.499
		if sim.entities[ids[0]].commands.is_empty():break
	var completed: bool=sim.entities[ids[0]].commands.is_empty()
	check(not completed and sim.entities[ids[1]].pos==held_position if hold_middle else completed,"held chain stays held" if hold_middle else "dense lane leader completes after distributed retreat")
	check(not propagated if hold_middle else propagated,"hold excludes retreat propagation" if hold_middle else "occupied retreat target propagates on later ticks")
	check(legal and budget_bounded,"dense chain keeps original footprint collision and request/in-flight limits")
	var positions: Array=[]
	var unit_diagnostics: Array=[]
	for id in ids:positions.append([sim.entities[id].pos.x,sim.entities[id].pos.y])
	for id in ids:
		var entity: Dictionary=sim.entities[id]
		unit_diagnostics.append({"id":id,"state":entity.state,"alpha":entity.alpha,"stuck":entity.stuck,"path_wait":entity.path_wait,
			"path":str(entity.path),"yield_goal":str(entity.get("yield_goal",Vector2.INF)),"yield_until":entity.get("yield_until",0.0),
			"yield_request_at":entity.get("yield_request_at",0.0),"movement_retry_at":entity.get("movement_retry_at",0.0),"commands":str(entity.commands)})
	rows.append({"case":"dense_chain_hold" if hold_middle else "dense_chain","completed":completed,"propagated":propagated,"legal":legal,"budget_bounded":budget_bounded,
		"positions":positions,"units":unit_diagnostics,"yield_trace":sim.yield_trace,"sim_seconds":sim.time,"wall_seconds":float(Time.get_ticks_usec()-started)/1000000.0,"navigation":sim.navigation_stats.duplicate()})
	sim=null

func worker_offset_corners() -> void:
	var sim=fixture(2,false,false)
	var building: int=sim.debug_spawn(0,"rivet_power",Vector2(12,12))
	sim._rebuild_nav()
	var half: float=float(sim.data_for(sim.entities[building].spec).size)*.5
	var radius: float=float(rules.units.rivet_tank.radius)
	var goal:=Vector2(12+half+1.1,12+half+1.1)
	var tested:=0
	var illegal_paths: Array[Dictionary]=[]
	var missing:=0
	var token:=0
	for index in range(48):
		var angle: float=TAU*float(index)/48.0
		var start:=Vector2(12,12)+Vector2.from_angle(angle)*(half+radius+.14)
		if not sim._standing(start,radius,-1,false):continue
		tested+=1
		token+=1
		var job: Dictionary={"id":-1000-index,"token":token,"revision":sim._path_revision,"start":start,"goal":goal,"radius":radius,
			"start_height":sim._height(start),"goal_height":sim._height(goal),"geometry":sim._path_geometry}
		while not sim._path_worker.submit(job):OS.delay_usec(100)
		var results: Array[Dictionary]=[]
		var deadline: int=Time.get_ticks_msec()+2000
		while results.is_empty() and Time.get_ticks_msec()<deadline:
			OS.delay_usec(1000)
			results=sim._path_worker.collect()
		if results.is_empty():
			missing+=1
			continue
		var path: Array=results[0].path
		var previous:=start
		var legal:=not path.is_empty()
		for point: Vector2 in path:
			legal=legal and sim._segment_static(previous,point,radius,-1)
			previous=point
		if not legal:illegal_paths.append({"start":[start.x,start.y],"goal":[goal.x,goal.y],"path":str(path)})
	check(tested>=16 and missing==0,"real worker offset corner control has sufficient completed real jobs")
	check(illegal_paths.is_empty(),"actual start and goal offsets around a real power building return only collision-legal worker segments")
	rows.append({"case":"worker_offset_building_corners","tested":tested,"missing":missing,"illegal_paths":illegal_paths,"building_size":half*2,"radius":radius})
	sim=null

func reverse_retreat(native_backend: bool) -> void:
	for heading in [-90.0,-120.0]:
		var sim=fixture(2,false,false)
		for z in range(48):
			for x in range(48):sim.map.terrain[z][x]=0 if x in [19,20] else 4
		sim._prepare_terrain_cache()
		sim._nav_initialized=false
		sim._rebuild_nav()
		sim.native_movement_enabled=native_backend
		if native_backend:sim.native_geometry_enabled=true
		var start:=Vector2(20,12)
		var goal:=Vector2(20,14)
		var id: int=sim.debug_spawn(0,"rivet_tank",start)
		var entity: Dictionary=sim.entities[id]
		entity.alpha=heading
		entity.yield_goal=goal
		entity.yield_until=sim.time+2.0
		entity.reversing=true
		entity.path=[goal]
		entity.path_goal=goal
		entity.path_wait=2.0
		sim.step(1.0/30.0)
		var reverse_ok: bool=entity.reversing and entity.pos.y>start.y+.04
		var heading_ok: bool=absf(wrapf(float(entity.alpha)-heading,-180,180))<13.0
		var legal: bool=sim._standing(entity.pos,.75,id,false) and sim._segment_static(start,entity.pos,.75,id)
		var label: String=("native" if native_backend else "script")+" active reverse heading"+str(heading)
		check(not native_backend or sim._kernels!=null,label+" native extension is actually available")
		check(reverse_ok and heading_ok,label+" moves along a clear retreat without clearing its reverse flag or forcing a 180-degree turn")
		check(legal,label+" full/partial turning step preserves unchanged footprint")
		rows.append({"case":"active_reverse","backend":"native" if native_backend else "script","start_heading":heading,"end_heading":entity.alpha,"position":[entity.pos.x,entity.pos.y],"reversing":entity.reversing,"moved":entity.pos.distance_to(start),"legal":legal})
		sim=null

func validate320_routes(sim, mode: String) -> Dictionary:
	var ids: Array[int]=[]
	var cases: Array[Dictionary]=[]
	var found: Dictionary={}
	var had_path: Dictionary={}
	var legal:=true
	var violations: Array[Dictionary]=[]
	var actual_violations: Array[Dictionary]=[]
	var maximum_in_flight:=0
	var maximum_queue:=0
	var maximum_wait:=0.0
	var started:=Time.get_ticks_usec()
	for team in range(4):
		var spec: String=str(sim.factions[team])+"_tank"
		var radius: float=float(rules.units[spec].radius)
		var home: Vector2=sim._team_start(team)
		var nearest:=Vector2.INF
		var distance:=INF
		for mine in sim.mines:
			var candidate: Vector2=mine.pos
			if candidate.distance_squared_to(home)<distance:
				distance=candidate.distance_squared_to(home)
				nearest=candidate
		var start: Vector2=sim._near_stand(home+Vector2(0,8),radius,-1,6.0,false)
		var goal: Vector2=sim._near_stand(nearest+Vector2(0,2),radius,-1,6.0,false)
		var id: int=sim.debug_spawn(team,spec,start) if start.is_finite() and goal.is_finite() else -1
		check(id>0,mode+" team"+str(team)+" has a real tank start and mine-adjacent goal")
		if id<=0:continue
		ids.append(id)
		sim.issue([id],"move",goal)
		cases.append({"team":team,"spec":spec,"radius":radius,"start":[start.x,start.y],"near_mine":[nearest.x,nearest.y],"goal":[goal.x,goal.y]})
	for tick in range(600):
		var before: Dictionary={}
		for id in ids:before[id]=sim.entities[id].pos
		sim.step(1.0/30.0)
		sim.events.clear()
		OS.delay_usec(1000)
		maximum_in_flight=maxi(maximum_in_flight,sim._path_in_flight)
		maximum_queue=maxi(maximum_queue,sim._planning_queue.size())
		for id in ids:
			var entity: Dictionary=sim.entities[id]
			maximum_wait=maxf(maximum_wait,float(entity.planning_wait))
			var position_legal: bool=sim._standing(entity.pos,float(entity.radius),id,false)
			var stride_legal: bool=sim._segment_static(before[id],entity.pos,float(entity.radius),id)
			legal=legal and position_legal
			if not position_legal or not stride_legal:
				if actual_violations.size()<32:actual_violations.append({"tick":tick,"id":id,"time":sim.time,"position_legal":position_legal,"stride_legal":stride_legal,
					"previous":[before[id].x,before[id].y],"current":[entity.pos.x,entity.pos.y],"path":str(entity.path)})
			for violation in violations:
				if int(violation.tick)==tick-1 and int(violation.id)==id:
					violation["next_position"]=[entity.pos.x,entity.pos.y]
					violation["next_path"]=str(entity.path)
			var previous: Vector2=entity.pos
			for index in range(entity.path.size()):
				var point: Vector2=entity.path[index]
				had_path[id]=true
				var segment_legal: bool=sim._segment_static(previous,point,float(entity.radius),id)
				legal=legal and segment_legal
				if not segment_legal and violations.size()<32:
					violations.append({"tick":tick,"id":id,"time":sim.time,"spec":entity.spec,"radius":entity.radius,"index":index,
						"from":[previous.x,previous.y],"to":[point.x,point.y],"actual_previous":[before[id].x,before[id].y],"path":str(entity.path),"state":entity.state,
						"details":explain_segment(sim,previous,point,float(entity.radius),id) if violations.is_empty() else {}})
				previous=point
			if entity.commands.is_empty():found[id]=true
		if found.size()==ids.size():break
	var raw_routes: Array=sim.returned_routes if "returned_routes" in sim else []
	var raw_routes_legal:=raw_routes.size()>=4
	for route: Dictionary in raw_routes:
		raw_routes_legal=raw_routes_legal and route.illegal.is_empty() and route.swept_illegal.is_empty()
	check(ids.size()==4 and had_path.size()==4,mode+" each HQ has a real worker tank route to a nearby mine")
	check(ids.size()==4 and found.size()==4,mode+" all four actual tanks complete their commands within the original 20sim seconds")
	check(raw_routes_legal,mode+" nonempty raw worker routes pass shared and independently exact static collision")
	legal=legal and actual_violations.is_empty() and raw_routes_legal
	check(legal,mode+" all observed worker segments and actual tank positions/strides preserve terrain/tree/mine/wall collision")
	check(maximum_in_flight<=Sim.PATH_IN_FLIGHT,mode+" real worker burst preserves two in-flight jobs")
	return {"cases":cases,"paths_received":had_path.size(),"completed_commands":found.size(),"all_segments_and_positions_legal":legal,"segment_violations":violations,"actual_violations":actual_violations,
		"returned_routes":sim.returned_routes if "returned_routes" in sim else [],"maximum_in_flight":maximum_in_flight,"maximum_queue":maximum_queue,"maximum_planning_wait_sim_seconds":maximum_wait,
		"sim_seconds":sim.time,"wall_seconds":float(Time.get_ticks_usec()-started)/1000000.0,"navigation":sim.navigation_stats.duplicate()}

func same_route_follower(native_backend: bool, stale_waypoint: bool=false) -> void:
	var sim=fixture(2,false,false,true)
	for z in range(48):
		for x in range(48):sim.map.terrain[z][x]=0 if x in [19,20] else 4
	sim._prepare_terrain_cache()
	sim._nav_initialized=false
	sim._rebuild_nav()
	sim.native_movement_enabled=native_backend
	if native_backend:sim.native_geometry_enabled=true
	var follower: int=sim.debug_spawn(0,"rivet_tank",Vector2(20,12))
	var leader: int=sim.debug_spawn(0,"rivet_tank",Vector2(20,13.52))
	for id in [follower,leader]:
		var goal:=Vector2(20,30 if id==follower else 32)
		sim.issue([id],"move",goal)
		sim.entities[id].alpha=90.0
		sim.entities[id].path=[Vector2(20,13.2),goal] if stale_waypoint and id==leader else [goal]
		sim.entities[id].path_goal=goal
		sim.entities[id].path_wait=2.0
	var start: Vector2=sim.entities[leader].pos
	var leader_clear: bool=sim._movement_clear(sim.entities[leader],start,start+Vector2(0,2.8/30.0),false)
	sim.step(1.0/30.0)
	var entity: Dictionary=sim.entities[leader]
	check(not native_backend or sim._kernels!=null,"same-route requested native sample uses an available extension")
	var retains_route: bool=not (entity.get("yield_goal",Vector2.INF) as Vector2).is_finite() and entity.path_goal==Vector2(20,32)
	check(leader_clear,"same-route leader's real next stride was already collision-clear")
	check(retains_route and entity.pos.y>start.y+.04,("native" if native_backend else "script")+" follower leaves the already-clear same-route front tank's path intact")
	check(sim._standing(entity.pos,.75,leader,false) and entity.pos.distance_to(sim.entities[follower].pos)>=1.499,"same-route follow keeps original terrain and unit footprints")
	rows.append({"case":"stale_waypoint_follower" if stale_waypoint else "same_route_follower","backend":"native" if native_backend else "script","leader_clear_before_tick":leader_clear,"retains_route":retains_route,
		"leader_start":[start.x,start.y],"leader_end":[entity.pos.x,entity.pos.y],"leader_path":str(entity.path),"leader_yield_goal":str(entity.get("yield_goal",Vector2.INF)),"trace":sim.yield_trace})
	sim=null

func clear_first_hop(native_backend: bool) -> void:
	var sim=fixture(2,false,false,true)
	sim.native_movement_enabled=native_backend
	sim.native_geometry_enabled=native_backend
	var requester: int=sim.debug_spawn(0,"rivet_tank",Vector2(20.469383,23.288752))
	var blocker: int=sim.debug_spawn(0,"rivet_tank",Vector2(20.458445,24.915398))
	var third: int=sim.debug_spawn(0,"rivet_tank",Vector2(19.099661,24.149736))
	var e: Dictionary=sim.entities[requester]
	var other: Dictionary=sim.entities[blocker]
	var start: Vector2=e.pos
	var next: Vector2=start+Vector2(0,2.8/30.0)
	var candidate: Vector2=other.pos+Vector2(-1,1).normalized()*1.2
	sim._rebuild_spatial()
	sim._in_step=true
	sim._step_delta=1.0/30.0
	sim._yield_requests=Sim.YIELD_REQUESTS_PER_TICK
	sim._avoidance_probes=Sim.AVOIDANCE_PROBES_PER_TICK
	sim._local_nav_us=0
	sim._prepare_native_queries()
	var geometry_legal:=true
	for id in [requester,blocker,third]:geometry_legal=geometry_legal and sim._standing(sim.entities[id].pos,.75,id,false)
	var candidate_static: bool=sim._standing(candidate,.75,blocker,false) and sim._segment_static(other.pos,candidate,.75,blocker)
	var candidate_vacant: bool=sim._standing(candidate,.75,blocker)
	var candidate_stride: Vector2=(other.pos as Vector2).move_toward(candidate,2.8/30.0)
	var candidate_clear: bool=sim._movement_clear(other,other.pos,candidate_stride,false)
	sim._request_movement_yield(e,other,start,next)
	var selected: Vector2=other.get("yield_goal",Vector2.INF)
	var selected_clear: bool=selected.is_finite() and sim._movement_clear(other,other.pos,(other.pos as Vector2).move_toward(selected,2.8/30.0),false)
	check(not native_backend or sim._kernels!=null,"mouth triangle requested native backend is actually available")
	check(geometry_legal,"mouth triangle all three actual .75 footprints are static legal")
	check(candidate_static and candidate_vacant and candidate_clear,"mouth triangle has a vacant diagonal terminal and a real clear first stride")
	check(selected.is_finite(),"mouth triangle blocker receives an original-budget yield")
	check(selected_clear,("native" if native_backend else "script")+" mouth triangle chooses an immediately clear retreat while one is available")
	check(sim._yield_requests>=0 and sim._avoidance_probes>=0,"mouth triangle original request/probe budgets remain bounded")
	rows.append({"case":"mouth_triangle_first_hop","backend":"native" if native_backend else "script","geometry_legal":geometry_legal,
		"requester":[e.pos.x,e.pos.y],"blocker":[other.pos.x,other.pos.y],"third":[sim.entities[third].pos.x,sim.entities[third].pos.y],
		"candidate":[candidate.x,candidate.y],"candidate_static":candidate_static,"candidate_vacant":candidate_vacant,"candidate_clear":candidate_clear,
		"selected":str(selected),"selected_clear":selected_clear,"local_us":sim._local_nav_us,"remaining_probes":sim._avoidance_probes,"remaining_requests":sim._yield_requests})
	sim._in_step=false
	sim=null

func yield_budget_controls(native_backend: bool) -> void:
	for exhausted in ["probes","time"]:
		var sim=fixture(2,false,false,true)
		for z in range(48):
			for x in range(48):sim.map.terrain[z][x]=0 if x in [19,20] else 4
		sim._prepare_terrain_cache();sim._nav_initialized=false;sim._rebuild_nav()
		sim.native_movement_enabled=native_backend;sim.native_geometry_enabled=native_backend
		var follower: int=sim.debug_spawn(0,"rivet_tank",Vector2(20,12))
		var leader: int=sim.debug_spawn(0,"rivet_tank",Vector2(20,13.52))
		var entity: Dictionary=sim.entities[leader]
		sim.issue([leader],"move",Vector2(20,32))
		entity.path=[Vector2(20,13.2),Vector2(20,32)]
		entity.path_goal=Vector2(20,32);entity.path_wait=2.0;entity.alpha=90.0
		sim._rebuild_spatial();sim._in_step=true;sim._step_delta=1.0/30.0;sim._prepare_native_queries()
		sim._yield_requests=Sim.YIELD_REQUESTS_PER_TICK
		sim._avoidance_probes=0 if exhausted=="probes" else Sim.AVOIDANCE_PROBES_PER_TICK
		sim._local_nav_us=Sim.LOCAL_NAV_BUDGET_US if exhausted=="time" else 0
		var started:=Time.get_ticks_usec()
		sim._request_movement_yield(sim.entities[follower],entity,sim.entities[follower].pos,(sim.entities[follower].pos as Vector2)+Vector2(0,2.8/30.0))
		var elapsed:=Time.get_ticks_usec()-started
		var retained: bool=not (entity.get("yield_goal",Vector2.INF) as Vector2).is_finite() and entity.path.size()==2 and entity.path_goal==Vector2(20,32)
		check(retained,("native" if native_backend else "script")+" exhausted "+exhausted+" budget preserves the front unit's route")
		check(sim._avoidance_probes>=0 and sim._yield_requests>=0,"exhausted yield checks keep the original probe/request counts nonnegative")
		check(sim._local_nav_us>0,"exhausted guard return accounts for cost or does no guarded work when local time is already exhausted")
		rows.append({"case":"yield_budget_"+exhausted,"backend":"native" if native_backend else "script","retains_route":retained,"elapsed_us":elapsed,
			"local_us":sim._local_nav_us,"remaining_probes":sim._avoidance_probes,"remaining_requests":sim._yield_requests})
		sim._in_step=false;sim=null

func corner_waypoint_pop(native_backend: bool) -> void:
	var sim=fixture(2,false,false,true)
	sim.native_movement_enabled=native_backend;sim.native_geometry_enabled=native_backend
	var building: int=sim.debug_spawn(0,"rivet_power",Vector2(15.5,16.5))
	var id: int=sim.debug_spawn(0,"rivet_tank",Vector2(17.3,12))
	sim._rebuild_nav();sim._rebuild_spatial()
	var entity: Dictionary=sim.entities[id]
	var start: Vector2=entity.pos
	var corner:=Vector2(18,12)
	var goal:=Vector2(18,20)
	sim.issue([id],"move",goal)
	entity.path=[corner,goal];entity.path_goal=goal;entity.path_wait=2.0;entity.alpha=0.0
	var supplied_route_legal: bool=sim._segment_static(start,corner,.75,id) and sim._segment_static(corner,goal,.75,id)
	var short_lookahead_legal: bool=sim._segment_static(start,start.move_toward(goal,2.0),.75,id)
	var full_connector_legal: bool=sim._segment_static(start,goal,.75,id)
	sim.step(1.0/30.0)
	var resulting_route_legal:=true
	var previous: Vector2=entity.pos
	for point: Vector2 in entity.path:
		resulting_route_legal=resulting_route_legal and sim._segment_static(previous,point,.75,id)
		previous=point
	check(not native_backend or sim._kernels!=null,"corner pop requested native movement uses the real extension")
	check(is_equal_approx(float(sim.data_for(sim.entities[building].spec).size),3.0),"corner pop obstacle is a real size3 power building")
	check(supplied_route_legal and short_lookahead_legal and not full_connector_legal,"corner control proves legal original path and 2m lookahead while shortcut to following crosses actual building footprint")
	check(entity.path.size()==2 and entity.path[0]==corner and resulting_route_legal,("native" if native_backend else "script")+" keeps a necessary nearby corner instead of producing an illegal active connector")
	check(sim._standing(entity.pos,.75,id,false) and sim._segment_static(start,entity.pos,.75,id),"corner pop actual stride still observes original collision footprint")
	rows.append({"case":"corner_waypoint_pop","backend":"native" if native_backend else "script","power_size":sim.data_for(sim.entities[building].spec).size,
		"start":[start.x,start.y],"position":[entity.pos.x,entity.pos.y],"path":str(entity.path),"supplied_route_legal":supplied_route_legal,
		"two_meter_lookahead_legal":short_lookahead_legal,"full_connector_legal":full_connector_legal,"resulting_route_legal":resulting_route_legal})
	sim=null


func turning_connector(native_backend: bool) -> void:
	var sim=fixture(2,false,false,true)
	sim.native_movement_enabled=native_backend;sim.native_geometry_enabled=native_backend
	var building: int=sim.debug_spawn(0,"rivet_power",Vector2(15.5,16.5))
	var id: int=sim.debug_spawn(0,"rivet_tank",Vector2(17.78,20))
	sim._rebuild_nav();sim._rebuild_spatial()
	var entity: Dictionary=sim.entities[id]
	var goal:=Vector2(17.78,12)
	var start: Vector2=entity.pos
	sim.issue([id],"move",goal)
	entity.path=[goal];entity.path_goal=goal;entity.path_wait=2.0;entity.alpha=-120.0
	var initial_clear: bool=sim._segment_static(start,goal,.75,id)
	var actual_clear:=true
	var connector_clear:=true
	var trace: Array[Dictionary]=[]
	for tick in range(6):
		var previous: Vector2=entity.pos
		sim.step(1.0/30.0)
		actual_clear=actual_clear and sim._standing(entity.pos,.75,id,false) and sim._segment_static(previous,entity.pos,.75,id)
		var step_connector_clear: bool=sim._segment_static(entity.pos,goal,.75,id)
		connector_clear=connector_clear and step_connector_clear
		trace.append({"tick":tick,"position":[entity.pos.x,entity.pos.y],"alpha":entity.alpha,"path":str(entity.path),"connector_clear":step_connector_clear,"local_us":sim._local_nav_us})
	check(not native_backend or sim._kernels!=null,"turning connector requested native uses the real backend")
	check(initial_clear,"turning connector starts with a fully legal path beside a real size3 power footprint")
	check(actual_clear,"turning connector every actual footprint/stride remains physically legal")
	check(connector_clear,("native" if native_backend else "script")+" partial turning does not bend a valid active route across the future building footprint")
	rows.append({"case":"turning_connector","backend":"native" if native_backend else "script","initial_clear":initial_clear,"actual_clear":actual_clear,"connector_clear":connector_clear,"trace":trace})
	sim=null


func mine_tangent_connector(native_backend: bool) -> void:
	var sim=fixture(2,false,false,true)
	sim.native_movement_enabled=native_backend;sim.native_geometry_enabled=native_backend
	# Exact islands first-failure geometry translated into the same dev fixture.
	var mine_pos:=Vector2(14.085784912109,17.2279205322266)
	sim.mines.append({"pos":mine_pos,"amount":6000.0,"capacity":6000.0,"miner":-1})
	var start:=Vector2(15.245697021484,13.5583801269531)
	var goal:=Vector2(15.5,18.5)
	var id: int=sim.debug_spawn(0,"rivet_tank",start)
	sim._rebuild_nav();sim._rebuild_spatial();sim._spec_cache=rules.units.duplicate();sim._spec_cache.merge(rules.buildings);sim._in_step=true;sim._prepare_native_queries()
	sim._avoidance_probes=Sim.AVOIDANCE_PROBES_PER_TICK;sim._local_nav_us=0
	var sampled_clear: bool=sim._segment_static_sampled(start,goal,.75,id)
	var common_clear: bool=sim._segment_static(start,goal,.75,id)
	var corner: Vector2=mine_pos+Vector2(.55,-.55)
	var closest: Vector2=Geometry2D.get_closest_point_to_segment(corner,start,goal)
	var swept_overlap: bool=corner.distance_squared_to(closest)<.77*.77+.00001
	var connector_clear: bool=sim._turning_connector_clear(sim.entities[id],start,goal)
	check(not native_backend or (sim._kernels!=null and sim._native_geometry_ready),"mine tangent requested native query is actually configured and active")
	check(sampled_clear,"mine tangent reproduces a .4-sampled future connector that misses its brief overlap")
	check(swept_overlap,"mine tangent exact closest point intersects actual .55 half-mine with unchanged radius .75 + .02 clearance")
	check(not common_clear and not connector_clear,("native" if native_backend else "script")+" common actual-stride and optional turning connector refuse swept overlap despite sampled-phase alias")
	check(sim._avoidance_probes>=0 and sim._local_nav_us>0,"mine tangent exact future probe respects original count and accounts elapsed cost")
	rows.append({"case":"mine_tangent_connector","backend":"native" if native_backend else "script","start":[start.x,start.y],"goal":[goal.x,goal.y],"mine":[mine_pos.x,mine_pos.y],
		"sampled_clear":sampled_clear,"swept_overlap":swept_overlap,"closest_distance":corner.distance_to(closest),"connector_clear":connector_clear,"local_us":sim._local_nav_us,"remaining_probes":sim._avoidance_probes})
	sim._in_step=false;sim=null

func continuous_geometry(native_backend: bool) -> void:
	mine_tangent_connector(native_backend)
	var sim=fixture(2,false,false,true)
	sim.native_geometry_enabled=native_backend
	var center:=Vector2(14.085784912109,17.2279205322266)
	sim.mines.append({"pos":center,"amount":6000.0,"capacity":6000.0,"miner":-1})
	sim._rebuild_nav();sim._rebuild_spatial();sim._spec_cache=rules.units.duplicate();sim._spec_cache.merge(rules.buildings);sim._in_step=true;sim._prepare_native_queries()
	var corner: Vector2=center+Vector2(.55,-.55)
	var normal:=Vector2(1,-1).normalized()
	var middle: Vector2=corner+normal*.7695
	var start: Vector2=middle-normal.orthogonal()*.05
	var finish: Vector2=middle+normal.orthogonal()*.05
	var prefix: String="native" if native_backend else "script"
	check(sim._standing(start,.75,-1,false) and sim._standing(finish,.75,-1,false),prefix+" .1m actual stride endpoints retain legal radius+.02 footprint")
	check(sim._segment_static_sampled(start,finish,.75,-1),prefix+" .1m original sampled actual stride aliases the rounded corner")
	check(not sim._segment_static(start,finish,.75,-1),prefix+" common continuous actual stride rejects intermediate rounded-corner intersection")
	check(sim._segment_static(corner+Vector2(.75,-.75),corner+Vector2(.7,-.75),.75,-1),prefix+" grown-AABB corner square does not falsely block a physically clear circle")
	var building: int=sim.debug_spawn(0,"rivet_power",Vector2(30.5,16.5))
	sim._rebuild_spatial();sim._prepare_native_queries()
	var a:=Vector2(28,16.5);var b:=Vector2(34,16.5)
	check(not sim._segment_static(a,b,.75,-1),prefix+" live building remains a mandatory segment obstacle")
	check(sim._segment_static(a,b,.75,building),prefix+" exact building sweep preserves ignore id")
	sim.entities[building].hp=0
	check(sim._segment_static(a,b,.75,-1),prefix+" destroyed live building is ignored")
	var barricade_spec: String=""
	for spec: String in rules.buildings:
		if rules.buildings[spec].get("role","")=="barricade":barricade_spec=spec;break
	check(not barricade_spec.is_empty(),prefix+" barricade parity fixture uses existing rules data")
	if not barricade_spec.is_empty():
		var wall: int=sim.debug_spawn(0,barricade_spec,Vector2(30.5,24.5))
		sim._rebuild_spatial();sim._prepare_native_queries()
		check(sim._segment_static(Vector2(28,24.5),Vector2(33,24.5),.35,-1),prefix+" infantry preserves pass-through barricade rule")
		check(not sim._segment_static(Vector2(28,24.5),Vector2(33,24.5),.75,-1),prefix+" tank still collides with barricade footprint")
		check(sim._segment_static(Vector2(28,24.5),Vector2(33,24.5),.75,wall),prefix+" barricade ignore id preserved")
	sim.geometry_profiling_enabled=true
	sim._geometry_queries=0;sim._geometry_us=0;sim._geometry_rectangles=0
	if sim._kernels!=null:sim._kernels.begin_geometry_measurement(true)
	var started: int=Time.get_ticks_usec()
	for n in range(200):sim._segment_static(corner+Vector2(.75,-.75),corner+Vector2(.7,-.75),.75,-1)
	var measured: Dictionary=sim._kernels.geometry_measurement() if native_backend else {"queries":sim._geometry_queries,"microseconds":sim._geometry_us,"rectangles":sim._geometry_rectangles}
	check(int(measured.queries)==200 and int(measured.rectangles)>=200,prefix+" explicit query instrumentation records actual continuous tests")
	sim._avoidance_probes=0;sim._local_nav_us=Sim.LOCAL_NAV_BUDGET_US
	check(not sim._segment_static(start,finish,.75,-1),prefix+" mandatory actual stride collision still executes when optional probes/time are exhausted")
	rows.append({"case":"continuous_geometry","geometry_measurement":measured,"backend":prefix,"short_start":str(start),"short_end":str(finish),"endpoint_distances":[start.distance_to(corner),finish.distance_to(corner)],"mid_distance":middle.distance_to(corner),"queries":200,"query_us":Time.get_ticks_usec()-started})
	sim._in_step=false;sim=null

func worker_connector_sweep(reverse_only: bool=false) -> void:
	var sim=fixture(2,false,false,true)
	var center:=Vector2(14.085784912109,17.2279205322266)
	sim.mines.append({"pos":center,"amount":6000.0,"capacity":6000.0,"miner":-1})
	sim._rebuild_nav()
	var worker=Sim.PATH_WORKER.new()
	var args: PackedStringArray=OS.get_cmdline_user_args()
	for index in range(args.size()-1):
		if args[index]=="--baseline-worker":
			var script:=GDScript.new()
			script.source_code=FileAccess.get_file_as_string(args[index+1]).replace("class_name BackgroundPaths\n","")
			check(script.reload()==OK,"frozen original worker connector control compiles independently")
			worker=script.new()
	worker._data=sim._path_worker._data.duplicate(true)
	var tested:=0;var empty:=0;var illegal: Array[Dictionary]=[]
	var goals: Array[Vector2]=[Vector2(10,13),Vector2(18,13),Vector2(18,21),Vector2(10,21)]
	for quadrant in range(4):
		var sign_x: float=1.0 if quadrant in [0,3] else -1.0
		var sign_y: float=-1.0 if quadrant in [0,1] else 1.0
		var corner: Vector2=center+Vector2(sign_x*.55,sign_y*.55)
		for angle in range(0,91,3):
			var start: Vector2=corner+Vector2(sign_x*cos(deg_to_rad(angle)),sign_y*sin(deg_to_rad(angle)))*.775
			if not sim._standing(start,.75,-1,false):continue
			for goal in goals:
				if not sim._standing(goal,.75,-1,false):continue
				tested+=1
				var actual_start: Vector2=goal if reverse_only else start
				var actual_goal: Vector2=start if reverse_only else goal
				var path: Array=worker._search({"id":-1,"token":tested,"revision":sim._path_revision,"start":actual_start,"goal":actual_goal,"radius":.75,"start_height":sim._height(actual_start),"goal_height":sim._height(actual_goal),"geometry":sim._path_geometry})
				if path.is_empty():empty+=1;continue
				var previous:=actual_start
				for index in range(path.size()):
					var point: Vector2=path[index]
					if not sim._segment_static(previous,point,.75,-1):
						illegal.append({"index":index,"start":str(actual_start),"goal":str(actual_goal),"from":str(previous),"to":str(point),"path":str(path)})
					previous=point
	check(tested>=400 and empty==0,"connector sweep exercises enough physically valid near-corner real worker paths")
	check(illegal.is_empty(),"worker arbitrary actual start and goal connectors remain exact swept-footprint legal")
	rows.append({"case":"worker_connector_sweep","reverse_connectors":reverse_only,"tested":tested,"empty":empty,"illegal":illegal})
	worker=null;sim=null


func sensitive_rounding_control(native_backend: bool) -> void:
	var sim=fixture(2,false,false)
	# Only the geometry map grows; no 320 navigation setup/rendering is needed.
	var terrain: Array=[];var heights: Array=[]
	for z in range(320):
		var row: Array=[];row.resize(320);row.fill(0)
		terrain.append(row);heights.append(row.duplicate())
	sim.map.size=320;sim.map.terrain=terrain;sim.map.heights=heights
	sim._size=320;sim._flat_safe.resize(320*320);sim._flat_safe.fill(1)
	sim.entities.clear();sim._building_entities.clear();sim._building_spatial.clear();sim._spatial.clear();sim._neighbor_cache.clear()
	var center:=Vector2(135.77590942382812,176.5548858642578)
	var half:=Vector2(.6000000238418579,.4000000059604645)
	sim.ruins=[{"id":777,"pos":center,"half":half,"hp":100.0}]
	sim._refresh_ruin_spatial()
	sim.native_geometry_enabled=native_backend
	sim._spec_cache=rules.units.duplicate();sim._spec_cache.merge(rules.buildings)
	sim._in_step=true;sim._prepare_native_queries()
	var start:=Vector2(137.2241668701172,177.2065887451172)
	var finish:=Vector2(135.6331329345703,177.43565368652344)
	var expected: bool=not sim._swept_circle_rect(start,finish,.37,Rect2(center-half,half*2.0))
	var result: bool=sim._segment_static(start,finish,.35,-1)
	check(not native_backend or sim._native_geometry_ready,"strict epsilon native rounding control actually uses configured geometry")
	check(result==expected,("native" if native_backend else "script")+" strict epsilon Rect2 construction/broadphase/closest use the same real footprint geometry")
	rows.append({"case":"sensitive_rounding","backend":"native" if native_backend else "script","expected_clear":expected,"actual_clear":result})
	sim._in_step=false;sim=null

func explain_segment(sim, start: Vector2, finish: Vector2, radius: float, id: int) -> Dictionary:
	var checks_count: int=maxi(1,ceili(start.distance_to(finish)/.4))
	var invalid: Array[Dictionary]=[]
	for index in range(1,checks_count+1):
		var point: Vector2=start.lerp(finish,float(index)/float(checks_count))
		if sim._standing(point,radius,id,false):continue
		var edges: Array[Dictionary]=[]
		for direction: Vector2 in Sim.CLEARANCE_DIRECTIONS:
			var edge: Vector2=point+direction*radius
			if not sim._land(edge) or absf(sim._height(edge)-sim._height(point))>.8:
				edges.append({"position":[edge.x,edge.y],"land":sim._land(edge),"type":sim._terrain(edge),"height":sim._height(edge),"center_height":sim._height(point)})
		var obstacles: Array[Dictionary]=[]
		for mine in sim.mines:
			if sim._circle_rect(point,radius+.02,mine.pos,sim.MINE_HALF):obstacles.append({"kind":"mine","pos":str(mine.pos),"half":str(sim.MINE_HALF)})
		for ruin in sim.ruins:
			if float(ruin.hp)>0 and sim._circle_rect(point,radius+.02,ruin.pos,ruin.half):obstacles.append({"kind":"ruin","pos":str(ruin.pos),"half":str(ruin.half)})
		for entity in sim.entities.values():
			if entity.kind!="building" or entity.id==id or entity.hp<=0:continue
			var half: Vector2=Vector2.ONE*float(sim.data_for(entity.spec).size)*.5
			if sim._circle_rect(point,radius+.02,entity.pos,half):obstacles.append({"kind":entity.spec,"pos":str(entity.pos),"half":str(half)})
		invalid.append({"index":index,"point":[point.x,point.y],"fast_flat":sim._fast_flat(point,radius),"land":sim._land(point),"edges":edges,
			"building_clear":sim._building_clear(point,radius,id),"obstacles":obstacles,"native_standing":sim._kernels.standing(point,radius,id,false) if sim._kernels!=null else null})
	return {"checks_count":checks_count,"reference_segment_legal":sim._segment_static(start,finish,radius,id),
		"native_segment_legal":sim._kernels.segment_static(start,finish,radius,id) if sim._kernels!=null else null,"terrain_segment_legal":sim._segment_terrain(start,finish),"invalid_standing_samples":invalid}

