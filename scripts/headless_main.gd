extends Node

const Match = preload("res://scripts/headless_match.gd")
const Exporter = preload("res://scripts/match_statistics_exporter.gd")

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var parsed := _parse(OS.get_cmdline_user_args())
	if parsed.has("error"):
		_fail(str(parsed.error)); return
	if parsed.has("help"):
		print("Paper Front logic-only runner\n--map symmetric --seed 1 --factions kestrel,rivet --duration 60 --dt 0.0333333333333333\n--ai off|both|left|right --difficulty normal --starts default|swap --ai-styles balanced|pressure|armor\n--ai-modules res://ai/alpha.gd,res://ai/beta.gd (one path per faction; builtin is supported)\n--output /absolute/path/report_prefix --commands /path/commands.json\n--load /path/match.pfront --save-final /path/final.pfront\nAI styles accept one value or a comma-separated value per faction. Commands use absolute game seconds.\nA duration limit leaves result empty. Run with --headless --audio-driver Dummy.\nReports: JSON, timeseries/summary/events CSV; independent AI decisions are included in JSON.")
		get_tree().quit(0); return
	if DisplayServer.get_name() != "headless":
		_fail("Use --headless to run without a window or rendering."); return
	var runner := Match.new()
	var problem := runner.start(parsed)
	if not problem.is_empty(): _fail(problem); return
	var commands: Variant = []
	if parsed.has("commands"):
		var source := FileAccess.open(str(parsed.commands), FileAccess.READ)
		if source == null: _fail("Cannot read commands: " + error_string(FileAccess.get_open_error())); return
		var json := JSON.new()
		if json.parse(source.get_as_text()) != OK: _fail("Invalid commands JSON at line %d: %s" % [json.get_error_line(),json.get_error_message()]); return
		commands = json.data
		problem = runner.validate_commands(commands)
		if not problem.is_empty(): _fail(problem); return
	var began := Time.get_ticks_usec()
	problem = runner.run_for(float(parsed.get("duration", 60.0)), float(parsed.get("dt", 1.0 / 30.0)), commands)
	var snapshot: Dictionary = runner.sim.match_statistics()
	snapshot.headless = {"stop_reason":runner.stop_reason, "ai_enabled":runner.sim.ai_enabled, "ai_state":runner.sim.ai_state.duplicate(true), "options":runner.run_options, "dt":float(parsed.get("dt",1.0/30.0)), "command_log":runner.command_log, "wall_seconds":(Time.get_ticks_usec()-began)/1000000.0, "error":problem}
	if runner.sim.independent_ai != null: snapshot.headless.independent_ai = runner.sim.independent_ai.snapshot(runner.sim)
	var prefix := str(parsed.get("output", "user://match_reports/headless_%d_%d" % [int(Time.get_unix_time_from_system()), OS.get_process_id()]))
	var exported: Dictionary = Exporter.export_snapshot(snapshot, prefix)
	if not bool(exported.get("ok", false)):
		_fail(str(exported.get("error", "Export failed"))); return
	if parsed.has("save-final"):
		var save_problem: String = runner.sim.save_game(str(parsed["save-final"]))
		if not save_problem.is_empty(): _fail(save_problem); return
	print("HEADLESS_RESULT " + JSON.stringify({"ok":problem.is_empty(), "result":runner.sim.result, "stop_reason":runner.stop_reason, "duration":runner.sim.time, "paths":exported.paths, "error":problem}))
	get_tree().quit(0 if problem.is_empty() else 1)

func _fail(message: String) -> void:
	printerr("HEADLESS_ERROR " + message)
	get_tree().quit(1)

func _parse(arguments: PackedStringArray) -> Dictionary:
	var options: Dictionary = {}
	var index := 0
	while index < arguments.size():
		var argument: String = arguments[index]
		if argument in ["--help", "-h"]: return {"help":true}
		if not argument.begins_with("--"): return {"error":"Expected --option: " + argument}
		var parts := argument.trim_prefix("--").split("=", true, 1)
		var key: String = parts[0]
		if key not in ["map", "seed", "factions", "duration", "dt", "output", "commands", "load", "save-final", "rules", "ai", "difficulty", "starts", "ai-styles", "ai-modules"]:
			return {"error":"Unknown option: --" + key}
		if options.has(key): return {"error":"Duplicate option: --" + key}
		var value := ""
		if parts.size() == 2: value = parts[1]
		else:
			index += 1
			if index >= arguments.size() or arguments[index].begins_with("--"): return {"error":"Missing value: --" + key}
			value = arguments[index]
		if value.is_empty(): return {"error":"Empty value: --" + key}
		if key == "seed":
			if not value.is_valid_int(): return {"error":"seed must be an integer"}
			options[key] = int(value)
		elif key in ["duration", "dt"]:
			if not value.is_valid_float() or not is_finite(float(value)): return {"error":key + " must be finite numeric seconds"}
			options[key] = float(value)
		elif key in ["factions", "ai-styles", "ai-modules"]: options[key] = Array(value.split(","))
		else: options[key] = value
		index += 1
	return options
