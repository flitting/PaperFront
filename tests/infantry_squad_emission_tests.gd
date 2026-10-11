extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const Production = preload("res://scripts/production_lifecycle.gd")
var checks: int = 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func flatten(sim) -> void:
	for z: int in range(sim.map.size):
		for x: int in range(sim.map.size): sim.map.terrain[z][x] = 0; sim.map.heights[z][x] = 0
	sim.mines.clear(); sim.bridges.clear(); sim.ruins.clear()
	sim._refresh_ruin_spatial(); sim._refresh_mine_spatial(); sim._prepare_terrain_cache()
	sim._nav_dirty = true

func fixture() -> Dictionary:
	var sim = Sim.new()
	sim.setup(RulesLoader.load_rules(), "dev", 41, "kestrel", false)
	var authored: Dictionary = sim.map.duplicate(true)
	flatten(sim)
	sim.money[0] = 20000.0
	var barracks: int = sim.debug_spawn(0, "kestrel_barracks", Vector2(14,22))
	sim.entities[barracks].rally = Vector2(18,31)
	return {"sim":sim,"barracks":barracks,"authored":authored}

func ready(sim, barracks: int, spec: String = "kestrel_rifle") -> void:
	check(sim.produce(barracks,spec).is_empty(), "valid paid production order: " + spec)
	sim.entities[barracks].queue[0].remaining = 0.0

func produced(sim) -> Array:
	return sim.entities.values().filter(func(e): return e.spec == "kestrel_rifle" and int(e.team) == 0)

func two_inside(sim, barracks: int) -> void:
	for tick: int in range(150):
		sim.step(.02)
		if sim.entities[barracks].get("production_members", []).size() >= 2: return

func finish_batch(sim, barracks: int) -> void:
	for tick: int in range(500):
		sim.step(.02)
		if sim.entities[barracks].queue.is_empty() and sim.entities[barracks].get("production_members", []).is_empty(): return

func _initialize() -> void:
	var f: Dictionary = fixture()
	var sim = f.sim
	var barracks: int = int(f.barracks)
	var balance: float = sim.money[0]
	ready(sim,barracks)
	check(is_equal_approx(balance - sim.money[0], sim.production_cost("kestrel_rifle")), "squad price is charged once before emergence")
	var spawn_times: Array = []
	var maximum_active: int = 0
	var safe: bool = true
	var door_held: bool = true
	var once_open: bool = false
	for tick: int in range(500):
		sim.step(.02)
		for event: Dictionary in sim.events:
			if event.kind == "produce" and event.spec == "kestrel_rifle": spawn_times.append(sim.time)
		sim.events.clear()
		var active: Array = sim.entities[barracks].get("production_members", [])
		maximum_active = maxi(maximum_active, active.size())
		if float(sim.entities[barracks].get("production_door",0.0)) >= .999: once_open = true
		if once_open and (not active.is_empty() or Production.pending_batch(sim.entities[barracks])): door_held = door_held and float(sim.entities[barracks].production_door) >= .999
		for a: int in active:
			for b: int in active:
				if b <= a: continue
				safe = safe and sim.entities[a].pos.distance_to(sim.entities[b].pos) >= 1.019
		if sim.entities[barracks].queue.is_empty() and active.is_empty(): break
	check(maximum_active >= 2, "next soldier starts before its predecessor finishes traversal")
	check(safe, "simultaneously emerging people retain physical body clearance")
	check(door_held, "door stays open for the entire squad procession")
	check(spawn_times.size() == 5 and produced(sim).size() == 5, "one ready order emits exactly its five paid soldiers")
	if spawn_times.size() == 5:
		var longest: float = 0.0
		for index: int in range(1,5): longest = maxf(longest, float(spawn_times[index]) - float(spawn_times[index-1]))
		check(longest < 1.1, "headway does not include a full door reopen and individual traversal")
		check(float(spawn_times[4]) - float(spawn_times[0]) < 2.2, "whole squad starts its exit as one short continuous procession")
	check(int(sim.statistics.to_dict().teams[0].units_produced) == 5, "statistics still count every independently produced soldier")

	f = fixture(); sim = f.sim; barracks = int(f.barracks)
	ready(sim,barracks); two_inside(sim,barracks)
	var active: Array = sim.entities[barracks].get("production_members", []).duplicate()
	check(active.size() == 2 and int(sim.entities[barracks].queue[0].spawned) == 2, "save fixture catches two soldiers in the doorway with three queued internally")
	check(sim.events.filter(func(e): return e.kind == "squad_ready").size() == 1, "trained squad emits one group-ready event")
	var before: Dictionary = {}
	for id: int in active: before[id] = sim.entities[id].pos
	var save_path: String = "user://squad_emission_test.save"
	var flat_map: Dictionary = sim.map
	sim.map = f.authored
	check(sim.save_game(save_path).is_empty(), "save concurrent doorway procession")
	sim.map = flat_map
	var restored = Sim.new()
	var error: String = restored.load_game(save_path)
	check(error.is_empty(), "load concurrent doorway procession: " + error)
	if error.is_empty():
		check(restored.entities[barracks].production_members == active and active.all(func(id): return restored.entities[id].pos == before[id]), "load retains exact real positions and active batch membership")
		flatten(restored)
		finish_batch(restored,barracks)
		check(produced(restored).size() == 5 and int(restored.statistics.to_dict().teams[0].units_produced) == 5, "saved remainder resumes without duplication or free replacements")
		check(restored.events.filter(func(e): return e.kind == "squad_ready").is_empty(), "loading an emitting squad does not repeat its ready event")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	var corrupt: Dictionary = {"entities":sim.entities.duplicate(true),"factions":sim.factions}
	corrupt.entities[barracks].production_members.append(active[0])
	check(not Production.validate_snapshot(corrupt).is_empty(), "duplicate active doorway members are rejected")
	var count_before: int = produced(sim).size()
	sim.entities[barracks].emp_until = sim.time + 1.0
	for tick: int in range(30): sim.step(.02)
	check(produced(sim).size() == count_before and active.all(func(id): return sim.entities[id].pos == before[id]), "producer EMP pauses the entire procession and queued remainder")
	sim.entities[barracks].emp_until = 0.0
	finish_batch(sim,barracks)
	check(produced(sim).size() == 5 and sim.entities[barracks].queue.is_empty(), "procession resumes after producer EMP")

	f = fixture(); sim = f.sim; barracks = int(f.barracks)
	ready(sim,barracks); two_inside(sim,barracks)
	var exit: Vector2 = sim.entities[sim.entities[barracks].production_members[0]].production_exit
	var blocker: int = sim._spawn(0,"kestrel_engineer",exit+Vector2(0,.7),true)
	sim.entities[blocker].hold_position = true
	for tick: int in range(150): sim.step(.02)
	check(int(sim.entities[barracks].queue[0].spawned) <= 2 and produced(sim).size() <= 2, "blocked exit keeps the remaining paid soldiers queued without stacking them")
	sim._kill_entity(blocker,false)
	finish_batch(sim,barracks)
	check(produced(sim).size() == 5 and sim.entities[barracks].queue.is_empty(), "clearing the doorway resumes the same squad batch")

	f = fixture(); sim = f.sim; barracks = int(f.barracks)
	ready(sim,barracks); two_inside(sim,barracks)
	active = sim.entities[barracks].production_members.duplicate()
	sim._kill_entity(int(active[0]),true)
	check(sim.entities[barracks].production_members.size() == 1, "individual death removes only that active member")
	var survivor: int = int(active[1])
	var survivor_pos: Vector2 = sim.entities[survivor].pos
	var paid_balance: float = sim.money[0]
	sim._kill_entity(barracks,true)
	check(is_equal_approx(sim.money[0],paid_balance), "destroying producer cannot refund its trained staged soldiers")
	check(sim.entities[survivor].pos == survivor_pos and not bool(sim.entities[survivor].emerging), "surviving real soldier leaves destroyed producer from its actual position")
	for tick: int in range(100): sim.step(.02)
	check(produced(sim).size() == 1 and sim.entities[survivor].pos.distance_to(survivor_pos) > .5, "unstaged remainder is lost and the survivor walks out without teleporting")
	f = fixture(); sim = f.sim; barracks = int(f.barracks)
	ready(sim,barracks,"kestrel_engineer"); finish_batch(sim,barracks)
	check(sim.entities.values().filter(func(e): return e.spec == "kestrel_engineer").size() == 1 and sim.events.filter(func(e): return e.kind == "squad_ready").is_empty(), "engineer production remains one independent person")
	f = fixture(); sim = f.sim; barracks = int(f.barracks)
	sim.entities[barracks].rotation_quarters = 1
	sim.entities[barracks].rally = sim.BuildingOrientation.point(sim.entities[barracks],Vector2(0,8))
	var rotated_balance: float = sim.money[0]
	ready(sim,barracks); ready(sim,barracks)
	for order: Dictionary in sim.entities[barracks].queue: order.remaining = 0.0
	var one_batch: bool = true
	var heading_correct: bool = true
	var rotated_safe: bool = true
	var rotated_active: int = 0
	for tick: int in range(750):
		sim.step(.02)
		active = sim.entities[barracks].get("production_members", [])
		rotated_active = maxi(rotated_active,active.size())
		var groups: Dictionary = {}
		for id: int in active:
			var unit: Dictionary = sim.entities[id]
			groups[int(unit.squad_id)] = true
			heading_correct = heading_correct and is_equal_approx(float(unit.alpha),180.0)
			for other: int in active:
				if other <= id: continue
				rotated_safe = rotated_safe and unit.pos.distance_to(sim.entities[other].pos) >= 1.019
		one_batch = one_batch and groups.size() <= 1
		if sim.entities[barracks].queue.is_empty() and active.is_empty(): break
	check(rotated_active >= 2 and rotated_safe and heading_correct, "90-degree barracks streams concurrent non-overlapping soldiers through its rotated central doorway")
	check(one_batch, "next distinct order waits until the previous active batch finishes its doorway traversal")
	check(produced(sim).size() == 10 and int(sim.statistics.to_dict().teams[0].units_produced) == 10, "two consecutive squads emit exactly ten individually tracked paid members")
	check(is_equal_approx(rotated_balance-sim.money[0],sim.production_cost("kestrel_rifle")*2.0) and sim.events.filter(func(e): return e.kind == "squad_ready").size() == 2, "two trained squad orders pay twice and announce ready once each")
	f = fixture(); sim = f.sim; barracks = int(f.barracks)
	ready(sim,barracks); two_inside(sim,barracks)
	active = sim.entities[barracks].production_members.duplicate()
	var capturing: int = sim.debug_spawn(1,"rivet_engineer",sim.entities[barracks].pos+Vector2(2.1,0),true)
	var capture_positions: Dictionary = {}
	for id: int in active: capture_positions[id] = sim.entities[id].pos
	sim._step_capture(sim.entities[capturing],{"kind":"capture","target":barracks,"pos":sim.entities[barracks].pos},.02)
	check(int(sim.entities[barracks].team) == 1 and int(sim.entities[barracks].production_owner_team) == 0, "capturing producer records the active batch's original owner")
	check(active.all(func(id): return bool(sim.entities[id].emerging) and int(sim.entities[id].team) == 0 and sim.entities[id].pos == capture_positions[id]), "capture preserves old-owner bodies and safe physical traversal")
	flat_map = sim.map; sim.map = f.authored
	check(sim.save_game(save_path).is_empty(), "save immediately after capturing concurrent doorway batch")
	sim.map = flat_map
	var captured_restore = Sim.new()
	error = captured_restore.load_game(save_path)
	check(error.is_empty(), "captured producer and old-owner active batch reload: " + error)
	if error.is_empty():
		flatten(captured_restore)
		for tick: int in range(300):
			captured_restore.step(.02)
			if active.all(func(id): return not bool(captured_restore.entities[id].get("emerging",false))): break
		check(active.all(func(id): return int(captured_restore.entities[id].team) == 0 and not bool(captured_restore.entities[id].emerging) and captured_restore.entities[id].pos.distance_to(capture_positions[id]) > .2), "loaded old-owner soldiers finish actual doorway egress from captured building")
		check(captured_restore.entities[barracks].production_members.is_empty() and not captured_restore.entities[barracks].has("production_owner_team"), "old batch ownership clears after its final physical exit")
	var legacy_file: FileAccess = FileAccess.open(save_path,FileAccess.READ)
	var legacy_capture: Dictionary = legacy_file.get_var(false)
	legacy_file.close()
	legacy_capture.entities[barracks].erase("production_owner_team")
	legacy_file = FileAccess.open(save_path,FileAccess.WRITE); legacy_file.store_var(legacy_capture,false); legacy_file.close()
	var legacy_captured_restore = Sim.new()
	check(legacy_captured_restore.load_game(save_path).is_empty(), "older captured-doorway save derives original batch ownership from reciprocal records")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	print("SQUAD_EMISSION ",JSON.stringify({"checks":checks,"failures":failures,"spawn_times":spawn_times,"maximum_active":maximum_active}))
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
