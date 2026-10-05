extends SceneTree

# Reproduce main.setup_benchmark without a renderer at the same 30 Hz rules.
# godot --headless --path . --script tools/profile_simulation.gd -- --seconds=65
var unit_count: int = 224
var seconds: float = 65.0
var probe_script: String = ""
var output: String = ""
var snapshot_path: String = ""
var report: Dictionary = {}

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--units="): unit_count = int(arg.substr(8))
		elif arg.begins_with("--seconds="): seconds = float(arg.substr(10))
		elif arg.begins_with("--probe-script="): probe_script = arg.substr(15)
		elif arg.begins_with("--output="): output = arg.substr(9)
		elif arg.begins_with("--snapshot="): snapshot_path = arg.substr(11)
	if unit_count < 2 or unit_count % 2 != 0 or seconds <= 5.0:
		push_error("Use an even unit count >=2 and --seconds greater than the five-second warmup.")
		quit(1)
		return
	var sim: WarSimulation = WarSimulation.new() if probe_script.is_empty() else load(probe_script).new()
	sim.setup(RulesLoader.load_rules("res://data/rules.json", false), "handmade", 73026, "rivet", false)
	_setup_units(sim)
	sim.profile_enabled = true
	var samples: Array[int] = []
	var phases: Dictionary = {"prepare_us": 0, "entities_us": 0, "damage_us": 0}
	var event_counts: Dictionary = {}
	var slow: Array = []
	var started: int = Time.get_ticks_usec()
	for tick: int in range(ceili(seconds * 30.0)):
		if tick == 150 and not probe_script.is_empty(): sim.probe_enabled = true
		var before: int = Time.get_ticks_usec()
		sim.step(1.0 / 30.0)
		var elapsed: int = Time.get_ticks_usec() - before
		if tick >= 150:
			samples.append(elapsed)
			for key: String in phases: phases[key] += int(sim.profile[key])
			if elapsed > 20000: slow.append({"sim_time": sim.time, "us": elapsed, "phases": sim.profile.duplicate(), "entities": sim.entities.size()})
		for event: Dictionary in sim.events:
			event_counts[event.kind] = int(event_counts.get(event.kind, 0)) + 1
		sim.events.clear()
	var wall: float = (Time.get_ticks_usec() - started) / 1000000.0
	samples.sort()
	var total: int = 0
	for value: int in samples: total += value
	for key: String in phases: phases[key] = float(phases[key]) / maxi(1, samples.size()) / 1000.0
	report = {"units": unit_count, "buildings": 32, "ticks_per_second": 30, "seconds": sim.time, "wall_seconds": wall, "sample_ticks": samples.size(), "mean_ms": float(total) / maxi(1, samples.size()) / 1000.0, "p95_ms": samples[int(samples.size() * 0.95)] / 1000.0, "p99_ms": samples[int(samples.size() * 0.99)] / 1000.0, "max_ms": samples.back() / 1000.0, "mean_phases_ms": phases, "slow_ticks": slow, "events": event_counts, "final_entities": sim.entities.size(), "planning_max_wait_seconds": sim._planning_max_wait, "path_plans_per_tick": WarSimulation.PATH_PLANS_PER_TICK}
	if not probe_script.is_empty(): report["functions"] = sim.probe_totals
	if not snapshot_path.is_empty(): report["snapshot_error"] = sim.save_game(snapshot_path)
	print(JSON.stringify(report))
	if not output.is_empty():
		var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	quit()

func _setup_units(sim: WarSimulation) -> void:
	sim.money = [100000.0, 100000.0]
	for team: int in range(2):
		var base := Vector2(sim.map.starts[team][0], sim.map.starts[team][1])
		for n: int in range(15):
			var role: String = ["power", "refinery", "barracks", "factory", "tower"][n % 5]
			var id: int = sim.debug_spawn(team, sim.factions[team] + "_" + role, _standable(sim, base + Vector2((n % 5 - 2) * 7, (n / 5 + 1) * 7), 3.0))
			sim.entities[id].gift_pending = false
		var ids: Array = []
		for n: int in range(unit_count / 2):
			var role: String = "rifle"
			if n % 7 == 0: role = "tank"
			elif n % 11 == 0: role = "harvester"
			elif n % 5 == 0: role = "anti"
			var id: int = sim.debug_spawn(team, sim.factions[team] + "_" + role, _standable(sim, base + Vector2((n % 12 - 6) * 1.8, (n / 12 - 5) * 1.8)))
			if role != "harvester": ids.append(id)
		var enemy := Vector2(sim.map.starts[1-team][0], sim.map.starts[1-team][1])
		sim.issue(ids, "attack_move", enemy)
		for e: Dictionary in sim.entities.values():
			if e.kind == "building" and int(e.team) == team:
				if sim.data_for(e.spec).role == "barracks": sim.produce(e.id, sim.factions[team] + "_rifle")
				if sim.data_for(e.spec).role == "factory": sim.produce(e.id, sim.factions[team] + "_tank")

func _standable(sim: WarSimulation, pos: Vector2, radius: float = 0.8) -> Vector2:
	for ring: int in range(16):
		for index: int in range(maxi(1, ring * 8)):
			var p: Vector2 = pos + Vector2.from_angle(float(index) / maxi(1, ring * 8) * TAU) * ring * 1.8
			if p.x < 2 or p.y < 2 or p.x > sim.map.size - 2 or p.y > sim.map.size - 2: continue
			if MapData.terrain_at(sim.map, p) in [1, 4]: continue
			var available: bool = true
			for e: Dictionary in sim.entities.values():
				var info: Dictionary = sim.data_for(e.spec)
				var er: float = float(info.get("size", 1)) * 0.73 if e.kind == "building" else float(info.radius)
				if e.pos.distance_to(p) < er + radius + 0.1:
					available = false
					break
			if available: return p
	return pos
