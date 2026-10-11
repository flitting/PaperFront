extends SceneTree
const Sim = preload("res://tests/rule_test_simulation.gd")
const Dock = preload("res://scripts/refinery_docking.gd")
var rules: Dictionary
var checks := 0
var failures: Array[String] = []
var evidence: Array[Dictionary] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func fixture(faction: String,native_mode: bool):
	var sim = Sim.new()
	sim.setup(rules,"dev",733,faction,false)
	if sim.entities.size()!=2:
		check(false,"simulation fixture setup completed")
		return null
	sim.native_kernels_enabled=native_mode;sim.native_unit_dispatch_enabled=native_mode
	sim.native_movement_enabled=native_mode;sim.native_geometry_enabled=native_mode
	sim.vision_enabled=false
	for id in sim.entities.keys():sim._kill_entity(id,false)
	for row in sim.map.terrain:row.fill(0)
	for row in sim.map.heights:row.fill(0.0)
	sim.mines.clear();sim.ruins.clear();sim.bridges.clear()
	sim._refresh_mine_spatial();sim._refresh_ruin_spatial();sim._prepare_terrain_cache()
	sim._spawn(0,faction+"_hq",Vector2(6,6),true)
	sim._spawn(1,"rivet_hq",Vector2(42,42),true)
	sim._nav_dirty=true
	return sim
func scenario(faction: String,native_mode: bool,kind: String) -> void:
	var sim = fixture(faction,native_mode)
	if sim == null:return
	var field: int=sim._spawn(0,faction+"_refinery",Vector2(23.5,21.5),true)
	sim.entities[field].gift_pending=false
	var outside := Vector2(23.5,25.15)
	var inside := Vector2(23.5,22.25)
	var miner: int=sim._spawn(0,faction+"_harvester",outside if kind=="clear" else inside,true)
	var unit: Dictionary=sim.entities[miner]
	var blocked_goal := outside+Vector2(0,2.65)
	var blocker_pos := blocked_goal if kind=="clear" else outside+Vector2(0,1.75)
	var blocker: int=sim._spawn(0,faction+"_tank",blocker_pos,true)
	if kind=="clear":sim.issue([blocker],"hold",blocker_pos)
	unit.refinery_docking={"source":field,"phase":kind,"outside":outside,"inside":inside,"remaining":0.0,"credited":true,"clearance":blocked_goal}
	sim.entities[field].dock_unit=miner;sim.entities[field].production_door=1.0
	var full: int=sim._spawn(0,faction+"_harvester",outside+Vector2(-2.65,.7),true)
	sim.entities[full].cargo=500.0;sim.entities[full].harvest_refinery=field
	sim._rebuild_spatial()
	var start_money: float=sim.money[0]
	var maximum_stride := 0.0
	var maximum_speed_fraction := 0.0
	var minimum_gap := INF
	var delivered := false
	var released := false
	var blocker_origin: Vector2=sim.entities[blocker].pos
	for frame in range(400):
		var before := {}
		for id in [miner,full,blocker]:before[id]=sim.entities[id].pos
		sim.step(.05)
		for id in [miner,full,blocker]:
			var stride: float=(sim.entities[id].pos as Vector2).distance_to(before[id])
			maximum_stride=maxf(maximum_stride,stride)
			maximum_speed_fraction=maxf(maximum_speed_fraction,stride/(float(sim.data_for(sim.entities[id].spec).speed)*.05))
		minimum_gap=minf(minimum_gap,(unit.pos as Vector2).distance_to(sim.entities[blocker].pos))
		if unit.get("refinery_docking",{}).is_empty():released=true
		for event in sim.events:
			if event.kind=="delivery" and int(event.id)==full:delivered=true
		sim.events.clear()
		if delivered and released:break
	var label := faction+" native="+str(native_mode)+" "+kind
	check(released,"docking reservation eventually releases after "+label)
	check(delivered,"queued loaded miner delivers after "+label)
	check(maximum_speed_fraction<=1.001,"all movement remains speed bounded: "+label)
	check(minimum_gap>=1.999,"docking preserves actual vehicle separation: "+label)
	check(is_equal_approx(sim.money[0],start_money+(500.0 if delivered else 0.0)),"only the real cargo is credited once: "+label)
	if kind=="clear":check((sim.entities[blocker].pos as Vector2).is_equal_approx(blocker_origin),"hold-position blocker retains its order: "+label)
	else:check((sim.entities[blocker].pos as Vector2).distance_to(blocker_origin)>.2,"idle blocker yields through ordinary movement: "+label)
	evidence.append({"faction":faction,"native":native_mode,"scenario":kind,"seconds":sim.time,"released":released,"delivered":delivered,"minimum_gap":minimum_gap,"maximum_stride":maximum_stride,"maximum_speed_fraction":maximum_speed_fraction,"job":str(unit.get("refinery_docking",{})),"blocker_moved":(sim.entities[blocker].pos as Vector2).distance_to(blocker_origin)})
	if sim._path_worker!=null:sim._path_worker.close()
func run() -> void:
	rules=RulesLoader.load_rules("res://data/rules.json",false)
	for faction: String in ["kestrel","sky"]:
		for native_mode in [false,true]:
			for kind: String in ["clear","exit"]:scenario(faction,native_mode,kind)
	print("REFINERY_DYNAMIC_BLOCKAGE "+JSON.stringify({"checks":checks,"failures":failures,"evidence":evidence}))
	quit(0 if failures.is_empty() else 1)
