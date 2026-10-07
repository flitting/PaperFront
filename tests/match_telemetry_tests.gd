extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
const Statistics = preload("res://scripts/match_statistics.gd")
const Exporter = preload("res://scripts/match_statistics_exporter.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func run() -> void:
	var rules: Dictionary = RulesLoader.load_rules()
	var sim = Sim.new()
	sim.setup(rules, "dev", 73, "kestrel", false)
	check(sim.statistics.history.size() == 1 and sim.statistics.history[0].time == 0.0, "setup captures genuine time-zero state")
	check(sim.statistics.history[0].teams[0].building_total == 1 and sim.statistics.history[0].teams[1].building_total == 1 and sim.statistics.history[0].teams[0].infantry_total == 0, "initial bases and empty infantry are observed after deployment")
	check(sim.statistics.metadata.map_width == sim.map.size and sim.statistics.metadata.map_height == sim.map.size and sim.statistics.metadata.rules_sha256.length() == 64, "metadata contains actual dimensions and rules fingerprint")
	for tick: int in range(9): sim.step(0.1)
	check(sim.statistics.history.size() == 1, "subsecond ticks do not duplicate full-world samples")
	sim.step(0.1)
	check(sim.statistics.history.size() == 2 and absf(float(sim.statistics.history.back().time) - 1.0) < 0.000001, "simulation time drives one-second sampling")
	var barracks: int = sim.debug_spawn(0, "kestrel_barracks", Vector2(19, 24))
	check(sim.produce(barracks, "kestrel_rifle").is_empty(), "actual paid infantry production begins")
	if not sim.entities[barracks].queue.is_empty(): sim.entities[barracks].queue[0].remaining = 0.01
	sim.step(0.05)
	var production: Array = sim.statistics.events.filter(func(event): return event.kind == "produce")
	check(production.size() == 1 and absf(float(production[0].time) - 1.05) < 0.000001, "production inside throttle window survives presentation draining")
	check(sim.statistics.teams[0].units_produced_by_spec.get("kestrel_rifle", 0) == 1 and sim.statistics.teams[0].infantry_produced == 1, "per-spec and infantry production counters use confirmed production")
	var produced: int = int(production[0].id) if not production.is_empty() else -1
	var event_count: int = sim.statistics.events.size()
	sim.statistics.sample(sim)
	sim.statistics.sample(sim)
	check(sim.statistics.events.size() == event_count and sim.statistics.teams[0].infantry_produced == 1, "retained events are ingested exactly once")
	sim.events.clear()
	var attacker: int = sim.debug_spawn(1, "rivet_rifle", Vector2(24, 20))
	if produced > 0:
		sim._damage.clear()
		sim._add_damage(produced, 100000.0, false, {"source": attacker, "source_team": 1, "weapon": "rivet_rifle", "explosive": false})
		sim._apply_damage()
		sim._damage.clear()
	var observed: Dictionary = sim.match_statistics()
	check(observed.teams[0].funds_spent == float(rules.units.kestrel_rifle.cost) and observed.teams[0].money_remaining == float(rules.economy.initial_money) - float(rules.units.kestrel_rifle.cost), "economic curve records the actual prepaid unit cost and remaining spendable funds")
	check(observed.teams[0].infantry_lost == 1 and observed.teams[1].infantry_killed == 1 and observed.teams[0].units_lost_by_spec.get("kestrel_rifle", 0) == 1, "authoritative casualty hook records detailed losses and credit")
	check(observed.teams[0].units_lost_value == float(rules.units.kestrel_rifle.cost) and observed.teams[1].enemy_units_destroyed_value == float(rules.units.kestrel_rifle.cost), "nominal destroyed values are explicit and capped to one casualty")
	check(observed.teams[0].damage_received == float(rules.units.kestrel_rifle.hp) and observed.teams[1].damage_dealt == float(rules.units.kestrel_rifle.hp), "received and dealt damage both exclude overkill")
	check(observed.history.back().teams[0].infantry_total == 0 and observed.history.back().teams[1].infantry_total == 1, "live infantry curve counts current surviving units on each side")
	var history_size: int = sim.statistics.history.size()
	var wallet: Array = sim.money.duplicate()
	var positions: Dictionary = {}
	for id: int in sim.entities: positions[id] = sim.entities[id].pos
	sim.match_statistics()
	sim.match_statistics()
	check(sim.statistics.history.size() == history_size and sim.money == wallet, "repeated reads at one instant keep one endpoint and leave economy unchanged")
	check(sim.entities.keys().all(func(id): return sim.entities[id].pos == positions[id]), "statistics do not move any entities")
	observed.teams[0].money_remaining = -999
	observed.history[0].teams[0].building_total = -999
	check(sim.statistics.history[0].teams[0].building_total == 1 and sim.match_statistics().teams[0].money_remaining >= 0, "returned data is deeply isolated from the internal ledger")
	sim.step(0.45)
	var save_path: String = "user://telemetry-tests/match.pfront"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://telemetry-tests"))
	check(sim.save_game(save_path).is_empty(), "ordinary save persists complete telemetry")
	var saved_stats: Dictionary = sim.statistics.to_dict()
	var restored = Sim.new()
	check(restored.load_game(save_path).is_empty(), "telemetry-bearing save restores through ordinary loader")
	check(restored.statistics.history == saved_stats.history and restored.statistics.events == saved_stats.events and restored.statistics.teams == saved_stats.teams, "save/load preserves every historical sample, milestone and cumulative counter")
	restored.step(0.5)
	check(restored.statistics.history.back().time > float(saved_stats.history.back().time), "restored match appends observations instead of resetting history")
	var legacy: Dictionary = saved_stats.duplicate(true)
	legacy.erase("schema_version")
	legacy.erase("history")
	var migrated = Statistics.new()
	migrated.restore(legacy, restored)
	var legacy_result: Dictionary = migrated.snapshot(restored)
	check(legacy_result.history_complete and not legacy_result.telemetry_history_complete and legacy_result.history_since_time == restored.time and legacy_result.history.size() == 1, "legacy totals remain valid while missing curves are honestly partial")
	check(legacy_result.teams[0].units_lost == saved_stats.teams[0].units_lost, "legacy cumulative totals are retained")
	var corrupt: Dictionary = saved_stats.duplicate(true)
	corrupt.history[0].teams[0].money_remaining = "damaged"
	var recovered = Statistics.new()
	recovered.restore(corrupt, restored)
	var recovered_stats: Dictionary = recovered.snapshot(restored)
	check(not recovered_stats.telemetry_history_complete and recovered_stats.history.size() == 1 and recovered_stats.history_since_time == restored.time, "malformed historical values fall back to an honest current-only series")
	var absent = Statistics.new()
	absent.restore({}, restored)
	var absent_result: Dictionary = absent.snapshot(restored)
	check(not absent_result.history_complete and not absent_result.telemetry_history_complete and absent_result.since_time == restored.time, "save without any ledger starts both scopes at load time")
	# Final tick occurs between ordinary sampling instants.
	for id: int in restored.entities.keys():
		if int(restored.entities[id].team) == 1 and restored.entities[id].kind == "building": restored._kill_entity(id, true)
	restored._check_result()
	var final_stats: Dictionary = restored.match_statistics()
	check(final_stats.finished and final_stats.result == "win" and final_stats.history[0].time == 0.0 and final_stats.history.back().time == restored.time and final_stats.history.back().teams[1].building_total == 0, "final result retains full time-zero-to-final curve including decisive state")
	check(final_stats.winner_teams_known and final_stats.winner_teams == [0] and final_stats.eliminated_teams == [1], "winner and eliminated owners are explicit without changing player-relative result")
	check(final_stats.metadata.rules_snapshot == rules, "report embeds the actual full rules snapshot for later balance comparisons")
	var prefix: String = "user://telemetry-tests/report"
	var exported: Dictionary = Exporter.export_snapshot(final_stats, prefix)
	check(exported.ok and exported.paths.size() == 4, "JSON and three analysis CSV files export as one report bundle")
	if exported.ok:
		var json: Variant = JSON.parse_string(FileAccess.get_file_as_string(exported.paths.json))
		check(json is Dictionary and int(json.schema_version) == 2 and json.history.size() == final_stats.history.size() and json.metadata.map_starts is Array and json.metadata.replay_included == false, "JSON is portable schema-versioned telemetry with honest replay scope")
		var csv: FileAccess = FileAccess.open(exported.paths.timeseries_csv, FileAccess.READ)
		var csv_header: PackedStringArray = csv.get_csv_line()
		var csv_count := 0
		while not csv.eof_reached():
			var row: PackedStringArray = csv.get_csv_line()
			if row.size() > 1:
				csv_count += 1
				check(row.size() == csv_header.size(), "CSV nested fields and quoting preserve column counts")
		csv.close()
		check(csv_header.has("infantry_total") and csv_header.has("building_total") and csv_header.has("units_lost_by_spec") and csv_count == final_stats.history.size() * final_stats.teams.size(), "CSV contains exactly one row per sampled owner and required analysis fields")
		check(Exporter.export_snapshot(final_stats, prefix).ok, "manual export can refresh an existing automatic report")
	var blocker: FileAccess = FileAccess.open("user://telemetry-tests/blocker", FileAccess.WRITE)
	blocker.store_string("ordinary file"); blocker.close()
	var failed: Dictionary = Exporter.export_snapshot(final_stats, "user://telemetry-tests/blocker/report")
	check(not failed.ok and not str(failed.error).is_empty() and failed.paths.is_empty(), "unwritable export reports actionable error and no false success")
	check(not Exporter.export_snapshot({}, prefix).ok and not Exporter.export_snapshot(final_stats, "").ok, "invalid data and empty export paths fail cleanly")
	var malformed: Dictionary = final_stats.duplicate(true)
	malformed.history = ["invalid sample"]
	check(not Exporter.export_snapshot(malformed, prefix).ok, "malformed nested export data returns an error instead of a script exception")
	var relative: Dictionary = Exporter.export_snapshot(final_stats, ".godot/telemetry-tests/relative_report.json")
	check(relative.ok and relative.paths.values().all(func(path): return str(path).is_absolute_path()) and str(relative.paths.json).ends_with("relative_report.json"), "relative export prefixes normalize to absolute paths and accept a JSON suffix")
	var four_owner = Sim.new()
	four_owner.setup_multiteam(rules, "forest", 73, ["kestrel", "rivet", "iron", "sky"], false)
	four_owner.step(1.0)
	var four_stats: Dictionary = four_owner.match_statistics()
	check(four_stats.teams.size() == 4 and four_stats.history.size() == 2 and four_stats.history.all(func(item): return item.teams.size() == 4), "telemetry retains all four owners and factions through each observation")
	check(four_stats.metadata.match_options.slots.size() == 4 and four_stats.metadata.profile.id == "forest" and four_stats.metadata.layout.size() == 4, "competitive-map profile, layout and reviewed owner slots survive into provenance")
	var ore: int = int(four_owner.map.layout[1].near_mines[0])
	var drill_position: Vector2 = four_owner.mines[ore].pos
	four_owner.debug_spawn(1, "rivet_power", drill_position + Vector2(6, 0))
	four_owner.debug_spawn(1, "rivet_drill", drill_position)
	four_owner.step(1.0)
	var economy: Dictionary = four_owner.match_statistics().teams[1]
	check(is_equal_approx(float(economy.funds_earned), float(rules.economy.drill_income_rate)) and is_equal_approx(float(economy.money_remaining), float(rules.economy.initial_money) + float(rules.economy.drill_income_rate)), "actual drill production updates sampled resource income and spendable economy")
	check(is_equal_approx(float(economy.income_per_minute), float(rules.economy.drill_income_rate) * 60.0) and economy.funds_spent == 0.0, "income rate uses observed simulation interval without treating debug deployment as expenditure")
	sim = null; restored = null; migrated = null; absent = null; recovered = null; four_owner = null
	await process_frame
	print("MATCH_TELEMETRY ", JSON.stringify({"checks": checks, "failures": failures}))
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
