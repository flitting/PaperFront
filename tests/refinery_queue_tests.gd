extends SceneTree
const Sim=preload("res://tests/rule_test_simulation.gd")
const Dock=preload("res://scripts/refinery_docking.gd")
var checks: int=0
var failures: Array[String]=[]
var rules: Dictionary
var evidence: Array=[]
func _initialize() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok: failures.append(message)
func fixture(faction: String,native_mode: bool):
	var sim=Sim.new(); sim.setup(rules.duplicate(true),"dev",7,faction,false)
	sim.native_kernels_enabled=native_mode; sim.native_unit_dispatch_enabled=native_mode; sim.native_movement_enabled=native_mode; sim.native_geometry_enabled=native_mode
	sim.vision_enabled=false
	for row in sim.map.terrain: row.fill(0)
	for row in sim.map.heights: row.fill(0.0)
	for id in sim.entities.keys(): sim._kill_entity(id,false)
	sim._spawn(0,faction+"_hq",Vector2(6,6),true); sim._spawn(1,"rivet_hq",Vector2(42,42),true)
	sim.bridges.clear(); sim.ruins.clear(); sim._refresh_ruin_spatial()
	sim.mines=[{"pos":Vector2(18,31),"amount":50000.0,"capacity":50000.0,"miner":-1},{"pos":Vector2(29,31),"amount":50000.0,"capacity":50000.0,"miner":-1}]
	sim._refresh_mine_spatial(); sim._prepare_terrain_cache(); sim._nav_dirty=true
	return sim
func close(sim) -> void:
	if sim._path_worker!=null: sim._path_worker.close()
func pair_cycle(faction: String,native_mode: bool) -> void:
	var sim=fixture(faction,native_mode)
	var field: int=sim._spawn(0,faction+"_refinery",Vector2(23.5,21.5),true)
	sim.entities[field].gift_pending=false
	var empty: int=sim._spawn(0,faction+"_harvester",Vector2(23.5,24.250),true)
	var full: int=sim._spawn(0,faction+"_harvester",Vector2(21.1,26.8),true)
	var e: Dictionary=sim.entities[empty]; var f: Dictionary=sim.entities[full]
	var outside: Vector2=Dock.entrance(sim,e,sim.entities[field])
	e.cargo=0; e.harvest_refinery=field; e.preferred_mine=0
	e.refinery_docking={"source":field,"phase":"exit","outside":outside,"inside":Vector2(23.5,22.25),"remaining":0.0,"credited":true}
	f.cargo=500; f.harvest_refinery=field; f.preferred_mine=1
	sim.entities[field].dock_unit=empty; sim.entities[field].production_door=1.0
	var deliveries: Dictionary={empty:0,full:0}
	var unload_started: Dictionary={}
	var earned: float=0; var initial: float=sim.money[0]
	var minimum_gap: float=INF; var maximum_stride: float=0; var staged: bool=false; var cleared: bool=false
	var timely: bool=true; var inside: bool=true
	for frame in range(3200):
		var before: Dictionary={empty:e.pos,full:f.pos}
		var old_jobs: Dictionary={empty:e.get("refinery_docking",{}).duplicate(),full:f.get("refinery_docking",{}).duplicate()}
		sim.step(.05)
		minimum_gap=minf(minimum_gap,(e.pos as Vector2).distance_to(f.pos))
		for unit in [e,f]:
			maximum_stride=maxf(maximum_stride,(unit.pos as Vector2).distance_to(before[int(unit.id)]))
			var job: Dictionary=unit.get("refinery_docking",{})
			if job.get("phase","")=="unload" and old_jobs[int(unit.id)].get("phase","")!="unload": unload_started[int(unit.id)]=sim.time
			if job.get("phase","")=="clear": cleared=true
			if not unit.get("refinery_waiting",{}).is_empty():
				var goal: Vector2=unit.refinery_waiting.get("goal",Vector2.INF)
				staged=staged or (goal.is_finite() and absf(goal.x-outside.x)>=1.5)
		for event in sim.events:
			if event.kind!="delivery" or not deliveries.has(int(event.id)): continue
			deliveries[int(event.id)]+=1; earned+=float(event.amount)
			timely=timely and float(sim.time)-float(unload_started.get(int(event.id),-INF))>=1.999
			inside=inside and bool(event.get("inside",false)) and event.pos.y<float(sim.entities[field].pos.y)+2.5
		sim.events.clear()
		if deliveries[empty]>=2 and deliveries[full]>=2: break
	check(deliveries[empty]>=2 and deliveries[full]>=2,"both miners complete at least two deliveries: "+faction+" native="+str(native_mode))
	check(staged and cleared,"arrivals queue beside door while empty miner clears departure lane")
	check(minimum_gap>=sim._radius(e)+sim._radius(f)-.001,"two2x2 miners never overlap during waiting/entering/exiting")
	check(maximum_stride<=.151,"all docking motion is continuous and speed bounded")
	check(timely and inside,"each delivery follows two full seconds of unloading inside")
	check(is_equal_approx(float(sim.money[0]),initial+earned),"only completed actual cargo is credited exactly once")
	evidence.append({"faction":faction,"native":native_mode,"seconds":sim.time,"deliveries":deliveries,"minimum_separation":minimum_gap,"maximum_stride":maximum_stride,"earned":earned,"positions":[str(e.pos),str(f.pos)],"jobs":[e.get("refinery_docking",{}),f.get("refinery_docking",{})]})
	close(sim)
func gifted_exit() -> void:
	var sim=fixture("kestrel",true)
	var field: int=sim._spawn(0,"kestrel_refinery",Vector2(23.5,21.5),true)
	# The normal factory/refinery gift path is left active, not manually moved.
	var full: int=sim._spawn(0,"kestrel_harvester",Vector2(23.5,27.3),true)
	sim.entities[full].cargo=500; sim.entities[full].harvest_refinery=field; sim.entities[full].preferred_mine=1
	var produced: int=-1; var delivery: bool=false; var min_gap: float=INF
	for frame in range(1600):
		sim.step(.05)
		for event in sim.events:
			if event.kind=="produce" and event.spec=="kestrel_harvester": produced=int(event.id)
			if event.kind=="delivery" and int(event.id)==full: delivery=true
		if produced>0: min_gap=minf(min_gap,(sim.entities[produced].pos as Vector2).distance_to(sim.entities[full].pos))
		sim.events.clear()
		if delivery and produced>0 and not bool(sim.entities[produced].emerging): break
	check(produced>0 and delivery,"initial free miner exits normally before queued loaded miner docks")
	check(produced>0 and min_gap>=sim._radius(sim.entities[produced])+sim._radius(sim.entities[full])-.001,"gift production and incoming2x2 miner preserve actual-body separation")
	close(sim)
func save_reservations() -> void:
	var sim=Sim.new(); sim.setup(rules.duplicate(true),"dev",7,"kestrel",false)
	var field: int=sim._spawn(0,"kestrel_refinery",Vector2(23.5,21.5),true); sim.entities[field].gift_pending=false
	var first: int=sim._spawn(0,"kestrel_harvester",Vector2(23.5,22.25),true)
	var second: int=sim._spawn(0,"kestrel_harvester",Vector2(26.15,25.85),true)
	for id in [first,second]: sim.entities[id].cargo=500; sim.entities[id].harvest_refinery=field
	sim.entities[first].refinery_docking={"source":field,"phase":"unload","outside":Vector2(23.5,25.15),"inside":Vector2(23.5,22.25),"remaining":1.5,"credited":false}
	sim.entities[field].dock_unit=first; sim.entities[field].dock_ticket=2
	sim.entities[second].refinery_waiting={"source":field,"ticket":2,"mode":"","goal":Vector2(26.15,25.85)}
	check(sim.save_game("user://refinery_queue_test.save").is_empty(),"queue and reserved bay save")
	var restored=Sim.new(); var error: String=restored.load_game("user://refinery_queue_test.save")
	check(error.is_empty(),"reserved lane snapshot restores: "+error)
	if error.is_empty():
		check(restored.entities[field].dock_unit==first and restored.entities[first].refinery_docking==sim.entities[first].refinery_docking,"occupied bay and uncredited unload countdown survive restore")
		check(restored.entities[second].refinery_waiting==sim.entities[second].refinery_waiting,"waiting order and lateral target survive restore")
	close(restored); close(sim)
func run() -> void:
	rules=RulesLoader.load_rules()
	for faction in ["kestrel","sky"]:
		for native_mode in [false,true]: pair_cycle(faction,native_mode)
	gifted_exit(); save_reservations()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/rts_revision_v2_20261007/navigation"))
	var file:=FileAccess.open("res://artifacts/rts_revision_v2_20261007/navigation/refinery_queue.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"cycles":evidence},"  ")); file.close()
	print("REFINERY_QUEUE ",JSON.stringify({"checks":checks,"failures":failures,"cycles":evidence}))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
