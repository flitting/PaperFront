extends RefCounted

## No scene, renderer, audio or UI is instantiated here. Commands go through
## the exact simulation methods used by the game. A duration limit is unfinished,
## never an invented draw. The caller can also step `sim` directly in later tools.
const Simulation = preload("res://scripts/simulation.gd")
const Loader = preload("res://scripts/rules_loader.gd")
const IndependentAI = preload("res://scripts/independent_ai_runtime.gd")
const MAPS := ["symmetric", "dev", "handmade", "random", "mountains", "mountains640", "forest", "desert", "snow", "city", "random_city", "islands"]
const FACTIONS := ["kestrel", "rivet", "iron", "sky"]
const STYLES := ["balanced", "pressure", "armor"]
const ACTIONS := ["build", "place", "produce", "issue", "sell", "cancel_build", "cancel_production", "rally"]
const ORDERS := ["move", "attack", "attack_move", "force_attack", "force_move", "stop", "hold", "harvest", "repair", "return", "board", "unload_move", "capture", "garrison", "patrol", "land"]
var sim
var command_log: Array[Dictionary] = []
var stop_reason := ""
var run_options: Dictionary = {}

func start(options: Dictionary = {}) -> String:
	var mode := str(options.get("map", "symmetric"))
	var ids: Array[String] = []
	if not options.get("factions", ["kestrel", "rivet"]) is Array: return "factions must be an array"
	for value: Variant in options.get("factions", ["kestrel", "rivet"]):
		if str(value) not in FACTIONS: return "Unknown faction: " + str(value)
		ids.append(str(value))
	if mode not in MAPS: return "Unknown map: " + mode
	if ids.size() < 2 or ids.size() > 4: return "Expected two to four factions"
	if mode not in ["forest", "desert", "snow", "city", "random_city", "islands"] and ids.size() != 2:
		return "This map requires exactly two factions"
	var ai_mode := str(options.get("ai", "both" if options.has("ai-modules") else "off"))
	if ai_mode not in ["off", "both", "left", "right"]: return "ai must be off, both, left or right"
	if ids.size() != 2 and ai_mode not in ["off", "both"]: return "left/right AI controls require two factions"
	var difficulty := str(options.get("difficulty", "normal"))
	if difficulty not in ["easy", "normal", "hard"]: return "Invalid difficulty"
	var starts_mode := str(options.get("starts", "default"))
	if starts_mode not in ["default", "swap"] or (starts_mode == "swap" and ids.size() != 2): return "starts must be default or swap (1v1)"
	if not str(options.get("load", "")).is_empty() and starts_mode != "default": return "A loaded match retains its original side mapping; starts swap is only valid for a new match"
	if not options.get("ai-styles", ["balanced"]) is Array: return "ai-styles must be an array"
	var styles: Array = options.get("ai-styles", ["balanced"]).duplicate()
	var requested_style_count: int = styles.size()
	if str(options.get("load", "")).is_empty() and styles.size() != 1 and styles.size() != ids.size(): return "ai-styles needs one entry or one per faction"
	if styles.is_empty() or styles.size()>4: return "ai-styles needs one to four supported styles"
	for style: Variant in styles:
		if str(style) not in STYLES: return "Unknown AI style: " + str(style)
	if styles.size() == 1:
		var style: String = str(styles[0]);styles=[]
		for _index in ids.size(): styles.append(style)
	var module_paths: Array = []
	if options.has("ai-modules"):
		if not options["ai-modules"] is Array: return "ai-modules must be an array"
		module_paths = options["ai-modules"].duplicate()
		if str(options.get("load", "")).is_empty() and module_paths.size()!=ids.size(): return "ai-modules requires one path per faction"
		for path: Variant in module_paths:
			if not path is String: return "AI module paths must be strings"
	run_options=options.duplicate(true)
	run_options.requested_factions=ids.duplicate()
	if starts_mode == "swap": ids.reverse();styles.reverse();module_paths.reverse()
	var slots: Array = []
	for team in ids.size():
		var controlled: bool = ai_mode == "both" or (ai_mode == "left" and team==0) or (ai_mode == "right" and team==1)
		slots.append({"faction":ids[team],"control":"ai" if controlled else "human","difficulty":difficulty,"ai_style":str(styles[team]),"ai_seed":int(options.get("seed",1))})
	var config: Dictionary = Loader.load_rules(str(options.get("rules", "res://data/rules.json")), false)
	if config.is_empty(): return "Invalid rules: " + "; ".join(Loader.errors)
	sim = Simulation.new()
	# Wall-clock scheduling is excluded from logic regression runs. Movement,
	# collision, costs, fog and combat still use the normal simulation rules.
	sim.synchronous_path_tests = true
	if not str(options.get("load", "")).is_empty():
		var problem: String = sim.load_game(str(options.load))
		if not problem.is_empty(): return problem
		if sim.factions.size()!=2 and ai_mode not in ["off","both"]: return "left/right AI controls require a two-faction saved match"
		if options.has("ai-styles") and requested_style_count!=1 and requested_style_count!=sim.factions.size(): return "ai-styles needs one entry or one per saved faction"
		sim.ai_enabled = ai_mode != "off"
		sim.match_options.allow_player_ai=true
		sim.match_options.explicit_controls=true
		if not sim.match_options.get("slots") is Array or sim.match_options.slots.size()!=sim.factions.size():
			sim.match_options.slots=[]
			for faction: String in sim.factions: sim.match_options.slots.append({"faction":faction,"control":"human","difficulty":difficulty})
		for team in sim.factions.size():
			var slot: Dictionary=sim.match_options.slots[team]
			slot.control="ai" if ai_mode=="both" or (ai_mode=="left" and team==0) or (ai_mode=="right" and team==1) else "human"
			slot.difficulty=difficulty
			slot.ai_style=str(styles[mini(team,styles.size()-1)])
	else:
		var starts: Array[Vector2] = []
		sim.setup_multiteam(config, mode, int(options.get("seed", 1)), ids, ai_mode!="off", starts, Callable(), {"vision_enabled":true,"slots":slots,"allow_player_ai":true,"explicit_controls":true})
	if sim.map.is_empty() or (str(options.get("load", "")).is_empty() and not bool(sim.map.get("valid", false))): return "Map setup or validation failed"
	if module_paths.is_empty() and ai_mode!="off":
		for slot: Dictionary in sim.match_options.slots: module_paths.append(str(slot.get("ai_module","builtin")))
	if not module_paths.is_empty():
		var runtime := IndependentAI.new()
		var module_error: String = runtime.configure(sim,module_paths)
		if not module_error.is_empty(): return module_error
		if not runtime.modules.is_empty(): sim.independent_ai = runtime
		run_options.resolved_ai_modules = runtime.identities.duplicate(true)
	command_log.clear()
	stop_reason = ""
	return ""

func validate_commands(commands: Variant) -> String:
	if not commands is Array: return "Commands JSON must be an array"
	var previous := -1.0
	for raw: Variant in commands:
		if not raw is Dictionary: return "Each command must be an object"
		if not (raw.get("at") is float or raw.get("at") is int): return "Each command needs numeric at (absolute game seconds)"
		var at: float = float(raw.at)
		if not is_finite(at) or at < previous or at < 0: return "Command times must be finite, nonnegative and sorted"
		previous = at
		var action := str(raw.get("action", ""))
		if action not in ACTIONS: return "Unknown command action: " + action
		if not (raw.get("team") is int or raw.get("team") is float) or float(raw.team) != floorf(float(raw.team)):
			return "Each command needs an integer team"
		if int(raw.team) < 0 or int(raw.team) >= sim.factions.size(): return "Command team is out of range"
		if action in ["build", "produce"] and not raw.get("spec") is String: return "Command needs spec"
		if action in ["place", "rally"] or (action == "issue" and str(raw.get("kind", "")) not in ["stop", "hold", "return"]):
			if not _valid_position(raw.get("pos")): return "Command needs finite pos: [x, z]"
		if action == "issue" and str(raw.get("kind", "")) not in ORDERS: return "Unknown issue kind"
		if action in ["produce", "sell", "cancel_production", "rally", "issue"] and not raw.has("id") and not raw.has("selector"):
			return "Command needs id or selector (owned entity spec)"
		if raw.has("id") and (not (raw.id is int or raw.id is float) or float(raw.id) != floorf(float(raw.id))):
			return "Entity id must be an integer"
		if raw.has("selector") and not raw.selector is String: return "selector must be an entity spec string"
		if raw.has("target") and (not (raw.target is int or raw.target is float) or float(raw.target) != floorf(float(raw.target))):
			return "Target id must be an integer"
		for key: String in ["builder", "index"]:
			if raw.has(key) and (not (raw[key] is int or raw[key] is float) or not is_finite(float(raw[key])) or float(raw[key]) != floorf(float(raw[key]))):
				return key + " must be an integer"
		for key: String in ["append", "confirmed"]:
			if raw.has(key) and not raw[key] is bool: return key + " must be a boolean"
	return ""

func run_for(duration: float, delta: float = 1.0 / 30.0, commands: Array = []) -> String:
	if sim == null: return "Match has not started"
	if not is_finite(duration) or duration <= 0 or duration > 86400: return "Duration must be in (0, 86400] seconds"
	if not is_finite(delta) or delta < .001 or delta > .1: return "dt must be in [0.001, 0.1] seconds"
	var problem := validate_commands(commands)
	if not problem.is_empty(): return problem
	if not commands.is_empty() and float(commands[0].at) < float(sim.time) - .000001:
		return "Command precedes the loaded match time"
	var end_time: float = float(sim.time) + duration
	var next := 0
	while sim.result.is_empty():
		while next < commands.size() and float(commands[next].at) <= float(sim.time) + .000001:
			var command: Dictionary = commands[next]
			problem = execute(command)
			sim.statistics.sample(sim)
			command_log.append({"time":sim.time, "command":command.duplicate(true), "ok":problem.is_empty(), "error":problem})
			next += 1
			if not problem.is_empty():
				stop_reason = "command_error"
				sim.statistics.sample(sim, true)
				return "Command %d at %.3f: %s" % [next, sim.time, problem]
			if not sim.result.is_empty(): break
		if not sim.result.is_empty() or float(sim.time) >= end_time - .000001: break
		var tick: float = minf(delta, end_time - float(sim.time))
		if next < commands.size(): tick = minf(tick, float(commands[next].at) - float(sim.time))
		sim.step(tick)
		if sim.independent_ai != null and not str(sim.independent_ai.error).is_empty():
			stop_reason = "ai_error"
			sim.statistics.sample(sim,true)
			return str(sim.independent_ai.error)
		# Telemetry has consumed logical events before visual consumers would.
		sim.events.clear()
		sim.notices.clear()
	stop_reason = "result" if not sim.result.is_empty() else "duration_limit"
	sim.statistics.sample(sim, true)
	return ""

func execute(command: Dictionary) -> String:
	var team := int(command.team)
	var selected: Array = []
	if command.has("id"):
		var id := int(command.id)
		if not sim.entities.has(id) or int(sim.entities[id].team) != team: return "Entity is missing or belongs to another team"
		selected.append(id)
	elif command.has("selector"):
		for entity: Dictionary in sim.entities.values():
			if int(entity.team) == team and str(entity.spec) == str(command.selector) and float(entity.hp) > 0: selected.append(int(entity.id))
		selected.sort()
		if selected.is_empty(): return "No owned entity matches selector: " + str(command.selector)
	var pos := Vector2.ZERO
	if command.has("pos"): pos = Vector2(float(command.pos[0]), float(command.pos[1]))
	var channel := str(command.get("channel", "auto"))
	if channel not in ["auto", "normal", "defense"]: return "Invalid channel"
	var id: int = int(selected[0]) if not selected.is_empty() else -1
	match str(command.action):
		"build":
			var builder := int(command.get("builder", -1))
			if builder >= 0 and not sim._builder_valid(team, builder): return "Invalid owned builder"
			return sim.build(team, str(command.spec), builder)
		"place": return sim.place_building(team, pos, channel)
		"produce": return sim.produce(id, str(command.spec))
		"sell": return sim.sell(id, bool(command.get("confirmed", false)))
		"cancel_build": return sim.cancel_build(team, channel)
		"cancel_production": return sim.cancel_production(id, int(command.get("index", 0)))
		"rally": sim.set_rally(id, pos)
		"issue": sim.issue(selected, str(command.kind), pos, int(command.get("target", -1)), bool(command.get("append", false)))
	return ""

func _valid_position(value: Variant) -> bool:
	return value is Array and value.size() == 2 and (value[0] is int or value[0] is float) and (value[1] is int or value[1] is float) and is_finite(float(value[0])) and is_finite(float(value[1]))
