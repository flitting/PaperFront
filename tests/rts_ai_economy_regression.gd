extends SceneTree

## Ordinary generated four-player forest and default starting funds. The
## harness runs the existing planner for owner0 as well, because the product
## correctly leaves that slot human. No free units, buildings, rails or money.
const Sim = preload("res://tests/rule_test_simulation.gd")
const FACTIONS: Array[String] = ["kestrel", "rivet", "iron", "sky"]
var checks := 0
var failures: Array[String] = []
var ever_roles: Array[Dictionary] = [{},{},{},{}]
var ever_units: Array[Dictionary] = [{},{},{},{}]
var trace: Array[Dictionary] = []
var events: Dictionary = {}
var notices: Array[String] = []
var duration := 600.0
const SOURCES := ["res://data/rules.json","res://scripts/simulation.gd","res://scripts/rail_network.gd","res://scripts/ai_controller.gd","res://scripts/mining_drills.gd","res://scripts/production_clearance.gd","res://scripts/production_lifecycle.gd","res://scripts/refinery_docking.gd","res://scripts/armor_combat.gd","res://scripts/beam_weapons.gd","res://scripts/zeppelin_weapons.gd","res://scripts/map_data.gd","res://scripts/competitive_layout.gd","res://scripts/rules_loader.gd","res://scripts/naval_operations.gd","res://scripts/aircraft_operations.gd","res://scripts/faction_traits.gd","res://scripts/faction_support.gd","res://scripts/tech_availability.gd","res://scripts/local_power.gd","res://scripts/field_construction.gd","res://scripts/building_construction.gd","res://scripts/unique_unit_rules.gd","res://tests/rule_test_simulation.gd","res://tests/rts_ai_economy_regression.gd","res://assets/native/libpaper_front_kernels.so"]
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func observe(sim) -> void:
	for entity: Dictionary in sim.entities.values():
		var team: int = int(entity.team)
		var info: Dictionary = sim.data_for(entity.spec)
		if entity.kind == "building" and float(entity.construct_remaining) <= 0 and not entity.has("construction"): ever_roles[team][str(info.get("role", ""))] = true
		elif entity.kind == "unit": ever_units[team][str(info.get("art", ""))] = true
	for event: Dictionary in sim.events:
		var key: String = str(event.kind)
		events[key] = int(events.get(key,0))+1
		if key == "produce" and int(event.get("team",-1)) in range(4):
			ever_units[int(event.team)][str(sim.data_for(str(event.get("spec",""))).get("art",""))] = true
	sim.events.clear()
	for notice in sim.notices:
		notices.append(str(notice))
		if notices.size() > 100: notices.pop_front()
	sim.notices.clear()
func run() -> void:
	var began: int = Time.get_ticks_msec()
	var source_hashes: Dictionary = {}
	for path: String in SOURCES: source_hashes[path] = FileAccess.get_sha256(path)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--duration="): duration = float(arg.trim_prefix("--duration="))
	var rules: Dictionary = RulesLoader.load_rules()
	var sim = Sim.new()
	var positions: Array[Vector2] = []
	var slots: Array = []
	for faction: String in FACTIONS: slots.append({"faction":faction,"control":"ai","difficulty":"normal"})
	sim.setup_multiteam(rules, "forest", 73026, FACTIONS, true, positions, Callable(), {"players":4,"slots":slots})
	var clock := 0.0
	var next_observation := 0.0
	var next_trace := 30.0
	while sim.time < duration and sim.result.is_empty():
		clock += .1
		var state: Dictionary = sim.ai_state[0]
		state.attack_clock += .1; state.scout_clock += .1; state.naval_clock += .1
		if clock >= 2.0:
			clock = 0.0
			sim.AIController._plan(sim, 0, sim.AIController.SETTINGS.normal, state)
		sim.step(.1)
		if sim.time >= next_observation:
			next_observation += 1.0; observe(sim)
		if sim.time >= next_trace:
			next_trace += 30.0
			var row: Dictionary = {"time":sim.time,"money":sim.money.duplicate(),"earned":[],"completed_roles":ever_roles.duplicate(true),"unit_types":ever_units.duplicate(true)}
			for statistic: Dictionary in sim.statistics.teams: row.earned.append(statistic.funds_earned)
			trace.append(row)
			print("RTS_AI_PROGRESS ", JSON.stringify({"time":roundi(sim.time),"earned":row.earned,"roles":row.completed_roles,"units":sim.entities.size()}))
			await process_frame
	observe(sim)
	for team in range(4):
		var faction: String = FACTIONS[team]
		check(float(sim.statistics.teams[team].funds_earned) > 0.0, faction + " earns real economic income from default starting resources")
		check(ever_roles[team].has("drill" if faction == "rivet" else "refinery"), faction + " completes its real faction economic facility")
		check(ever_roles[team].has("factory"), faction + " builds a real vehicle factory")
		check(ever_units[team].has("tank"), faction + " produces tanks under live price and technology rules")
		if faction == "iron": check(ever_roles[team].has("rail") and ever_units[team].has("harvester"), "iron AI connects and launches actual owner railway miners")
	var diagnostics: Array[Dictionary] = []
	var unit_diagnostics: Array[Dictionary] = []
	for entity: Dictionary in sim.entities.values():
		if entity.kind == "unit":
			unit_diagnostics.append({"team":entity.team,"spec":entity.spec,"pos":[entity.pos.x,entity.pos.y],"state":entity.state,"cargo":entity.get("cargo",0),"harvest_mine":entity.get("harvest_mine",-1),"harvest_refinery":entity.get("harvest_refinery",-1),"rail_goal":str(entity.get("rail_goal",Vector2.INF)),"rail_route":str(entity.get("rail_route",[])),"commands":entity.commands})
			unit_diagnostics.back()["refinery_docking"] = entity.get("refinery_docking", {}).duplicate(true)
			unit_diagnostics.back()["refinery_waiting"] = entity.get("refinery_waiting", {}).duplicate(true)
			unit_diagnostics.back()["path_goal"] = str(entity.get("path_goal", Vector2.INF))
			unit_diagnostics.back()["yield_goal"] = str(entity.get("yield_goal", Vector2.INF))
		if entity.kind != "building": continue
		diagnostics.append({"team":entity.team,"spec":entity.spec,"pos":[entity.pos.x,entity.pos.y],"construct_remaining":entity.construct_remaining,"construction":entity.get("construction",{}),"gift_pending":entity.get("gift_pending",false),"rail_auto_done":entity.get("rail_auto_done",false),"rail_auto_error":entity.get("rail_auto_error",""),"queue":entity.queue,"exit_rail":sim._rail_network.at(int(entity.team),sim._rail_network.exit_cell(sim,entity)).get("id",-1)})
		diagnostics.back()["dock_unit"] = int(entity.get("dock_unit", -1))
		diagnostics.back()["production_door"] = float(entity.get("production_door", 0.0))
	var report := {"checks":checks,"failures":failures,"duration":sim.time,"wall_seconds":float(Time.get_ticks_msec()-began)/1000.0,"map":"forest/73026/4","initial_funds":sim.statistics.initial_money,"scope":"Ordinary four-player generated forest, default economy, all four existing normal planners; owner0 planner driven by test harness; no seeded buildings, rails, free funds or units. Requested simulation seconds or earlier genuine match result.","ever_completed_roles":ever_roles,"ever_unit_types":ever_units,"events":events,"statistics":sim.statistics.snapshot(sim),"trace":trace,"buildings":diagnostics,"notices":notices,"normal_orders":sim.building_orders}
	report.units = unit_diagnostics
	report.loaded_source_hashes = source_hashes
	report.sources_unchanged_during_run = true
	report.changed_sources_during_run = []
	for path: String in SOURCES:
		if FileAccess.get_sha256(path) != source_hashes[path]:
			report.sources_unchanged_during_run = false
			report.changed_sources_during_run.append(path)
	DirAccess.make_dir_recursive_absolute("res://artifacts/rts_revision_v2_20261007")
	var path := "res://artifacts/rts_revision_v2_20261007/ai_four_faction_economy%s.json" % ("" if duration == 600.0 else "_%d" % int(duration))
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")); file.close()
	print("RTS_AI_ECONOMY ", JSON.stringify({"checks":checks,"failures":failures,"duration":sim.time,"wall_seconds":report.wall_seconds,"roles":ever_roles,"unit_types":ever_units}))
	for failure: String in failures: push_error(failure)
	sim = null; await process_frame
	quit(0 if failures.is_empty() else 1)
