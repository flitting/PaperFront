extends RefCounted

## Trusted local strategy plugins receive copied observations, never the live
## simulation. This is an API boundary, not an operating-system sandbox.
const Controller = preload("res://scripts/ai_controller.gd")
const API_VERSION := 1
const REACTION_SECONDS := 2.0
const MAX_COMMANDS := 96
const NUMBERS := {
	"infantry_limit":[0.0,80.0], "wave_scale":[0.25,4.0],
	"attack_scale":[0.25,4.0], "factory_share":[0.0,1.0],
	"tech_after":[0.0,86400.0], "air_after":[0.0,86400.0],
	"builders":[1.0,8.0], "expansion_after":[0.0,86400.0],
	"factory_after":[0.0,86400.0], "tower_limit":[0.0,4.0]
}
const ORDERS := ["move","attack","attack_move","force_move","stop","hold","harvest","repair","return","return_miner","board","unload_move","capture","garrison","patrol","land"]
var modules: Dictionary = {}
var recorders: Dictionary = {}
var identities: Array[Dictionary] = []
var error := ""

func configure(sim, paths: Array) -> String:
	modules.clear(); recorders.clear(); identities.clear(); error = ""
	if paths.size() != sim.factions.size(): return "ai-modules requires one path per faction"
	for team: int in paths.size():
		var path := str(paths[team])
		if path == "builtin" or path.is_empty():
			sim.match_options.slots[team].erase("ai_module")
			for key: String in ["independent_profile","independent_shared_economy","independent_shared_tactics"]: sim.ai_state[team].erase(key)
			continue
		if str(sim.match_options.slots[team].control) != "ai": return "An AI module requires an AI-controlled slot"
		if not path.ends_with(".gd") or not FileAccess.file_exists(path): return "Missing GDScript AI module: " + path
		var script: Variant = load(path)
		if not script is GDScript or not script.can_instantiate(): return "Invalid AI module: " + path
		var module: Variant = script.new()
		if not module is RefCounted or not module.has_method("decide"): return "AI module must extend RefCounted and implement decide(observation, memory)"
		var digest := FileAccess.get_sha256(path)
		var state: Dictionary = sim.ai_state[team]
		if state.has("independent_sha256") and str(state.independent_sha256) != digest:
			return "Saved AI source hash differs: " + path + "; start a new match for a revised strategy"
		modules[team] = module
		sim.match_options.slots[team].ai_module = path
		state.independent_sha256 = digest
		state.independent_memory = state.get("independent_memory", {})
		state.independent_clock = float(state.get("independent_clock", 0.0))
		state.independent_log = state.get("independent_log", [])
		var identity: Dictionary = {"team":team,"path":path,"sha256":digest,"api_version":API_VERSION}
		var recorder_path := path.get_basename()+"_recorder.gd"
		if FileAccess.file_exists(recorder_path):
			var recorder_script: Variant = load(recorder_path)
			if not recorder_script is GDScript or not recorder_script.can_instantiate(): return "Invalid recorder: " + recorder_path
			var recorder: Variant = recorder_script.new()
			if not recorder is RefCounted or not recorder.has_method("record"): return "Recorder must implement record(observation, memory)"
			var recorder_digest := FileAccess.get_sha256(recorder_path)
			if state.has("independent_recorder_sha256") and str(state.independent_recorder_sha256)!=recorder_digest: return "Saved recorder source hash differs: " + recorder_path
			state.independent_recorder_sha256 = recorder_digest
			state.independent_recording_memory = state.get("independent_recording_memory",{})
			recorders[team] = recorder
			identity.recorder = {"path":recorder_path,"sha256":recorder_digest}
		elif state.has("independent_recorder_sha256"): return "Saved AI recorder is missing: " + recorder_path
		identities.append(identity)
	return ""

func observation(sim, team: int) -> Dictionary:
	var own: Array[Dictionary] = []
	var enemies: Array[Dictionary] = []
	var roles: Dictionary = {}
	var counts: Dictionary = {}
	for entity: Dictionary in sim.entities.values():
		if float(entity.hp) <= 0.0: continue
		var mine: bool = int(entity.team) == team
		if not mine and not sim.entity_visible_to(team, int(entity.id)): continue
		var info: Dictionary = sim.data_for(str(entity.spec))
		var item: Dictionary = {"id":int(entity.id),"team":int(entity.team),"spec":str(entity.spec),"kind":str(entity.kind),"pos":entity.pos,"hp":float(entity.hp),"max_hp":sim.max_hp(entity),"role":str(info.get("role","")),"art":str(info.get("art","")),"domain":str(info.get("domain","ground")),"armor_class":str(info.get("armor_class","")),"weapon":str(info.get("weapon","")),"cost":float(info.get("cost",0.0))}
		if mine:
			# Collectors may inspect all of their own unit diagnostics, including
			# docking, yield, route, construction and weapon cooldown state.
			var owned: Dictionary = entity.duplicate(true)
			owned.merge(item,true)
			item = owned
			for key: String in ["commands","queue","construct_remaining","cargo","state","emerging","loaded_in","ai_attacking","ai_traffic_until","flight_state","harvest_mine"]:
				if entity.has(key): item[key] = entity[key]
			own.append(item)
			counts[item.spec] = int(counts.get(item.spec,0)) + 1
			if entity.kind == "building": roles[item.role] = int(roles.get(item.role,0)) + 1
		else: enemies.append(item)
	var ore: Array[Dictionary] = []
	for index: int in sim.mines.size():
		var entry: Dictionary = {"index":index,"pos":sim.mines[index].pos}
		if sim.position_visible_to(team,sim.mines[index].pos): entry.amount = sim.mines[index].amount
		ore.append(entry)
	var stats: Dictionary = sim.statistics.teams[team].duplicate(true)
	var answer: Dictionary = {"api_version":API_VERSION,"time":float(sim.time),"team":team,"faction":sim.factions[team],"money":float(sim.money[team]),"power":sim.power(team),"home":sim._team_start(team),"enemy_start":Controller._public_enemy_start(sim,team),"map":{"mode":str(sim.map.get("mode","")),"size":sim.map.get("size",192),"starts":sim.map.get("starts",[])},"own":own,"visible_enemies":enemies,"roles":roles,"counts":counts,"mines":ore,"orders":{"normal":sim.order_for_team(team,"normal"),"defense":sim.order_for_team(team,"defense")},"statistics":stats,"rules":sim.rules,"last_commands":[]}
	var log: Array = sim.ai_state[team].get("independent_log",[])
	if not log.is_empty(): answer.last_commands = log.back().get("commands",[])
	return answer.duplicate(true)

func step(sim, delta: float) -> void:
	if not error.is_empty(): return
	var pending: Dictionary = {}
	# Both observations and decisions precede either team's new actions.
	for team: int in modules:
		var state: Dictionary = sim.ai_state[team]
		state.independent_clock += delta
		state.attack_clock += delta
		state.scout_clock += delta
		state.naval_clock += delta
		if float(state.independent_clock) + .000001 < REACTION_SECONDS: continue
		state.independent_clock = maxf(0.0,float(state.independent_clock)-REACTION_SECONDS)
		var view: Dictionary = observation(sim,team)
		var observed_summary: Dictionary = {"own_count":view.own.size(),"visible_count":view.visible_enemies.size(),"money":view.money}
		var recorded: Dictionary = {}
		if recorders.has(team):
			var recording_memory: Dictionary = state.independent_recording_memory.duplicate(true)
			var output: Variant = recorders[team].record(view.duplicate(true),recording_memory)
			if not output is Dictionary: error = "AI recorder %d must return a dictionary" % team; return
			recorded = output.duplicate(true)
			state.independent_recording_memory = recording_memory.duplicate(true)
		var memory: Dictionary = state.independent_memory.duplicate(true)
		var decision: Variant = modules[team].decide(view,memory)
		if not decision is Dictionary:
			error = "AI module %d must return a decision dictionary" % team; return
		var problem := validate_decision(sim,team,decision)
		if not problem.is_empty(): error = "AI module %d: %s" % [team,problem]; return
		state.independent_memory = memory.duplicate(true)
		state.independent_profile = decision.get("profile",{}).duplicate(true)
		state.independent_shared_economy = bool(decision.get("shared_economy",true))
		state.independent_shared_tactics = bool(decision.get("shared_tactics",true))
		pending[team] = {"decision":decision.duplicate(true),"recorded":recorded,"own_count":observed_summary.own_count,"visible_count":observed_summary.visible_count,"money":observed_summary.money}
	Controller.step(sim,delta)
	var teams: Array = pending.keys(); teams.sort()
	if int(floorf((float(sim.time)+.000001)/REACTION_SECONDS)) % 2 == 0: teams.reverse()
	for team: int in teams:
		var state: Dictionary = sim.ai_state[team]
		var decision: Dictionary = pending[team].decision
		var settings: Dictionary = Controller.SETTINGS.normal.duplicate(true)
		settings.merge(decision.get("settings",{}),true)
		var before: Dictionary = {}
		for key: String in ["build_orders","production_orders","attack_waves","defense_orders","miner_recovery_orders","traffic_yield_orders"]: before[key] = int(state.get(key,0))
		Controller._plan(sim,team,settings,state)
		var attempts: Array[Dictionary] = []
		for raw: Dictionary in decision.get("commands",[]):
			var result: String = execute(sim,team,raw)
			attempts.append({"command":raw.duplicate(true),"ok":result.is_empty(),"error":result})
		var counters: Dictionary = {}
		for key: String in before: counters[key] = int(state.get(key,0)) - int(before[key])
		state.independent_log.append({"time":sim.time,"team":team,"reason":str(decision.get("reason","")),"profile":state.independent_profile.duplicate(true),"settings":decision.get("settings",{}).duplicate(true),"shared_economy":state.independent_shared_economy,"shared_tactics":state.independent_shared_tactics,"observation":{"own_count":pending[team].own_count,"visible_count":pending[team].visible_count,"money":pending[team].money},"commands":attempts,"shared_actions":counters})
		state.independent_log.back().recording = pending[team].recorded

func validate_decision(sim, team: int, decision: Dictionary) -> String:
	for key: String in decision:
		if key not in ["profile","settings","commands","shared_economy","shared_tactics","reason"]: return "Unknown decision key: " + key
	for key: String in ["shared_economy","shared_tactics"]:
		if decision.has(key) and not decision[key] is bool: return key + " must be boolean"
	if decision.has("reason") and not decision.reason is String: return "reason must be a string"
	if not decision.get("profile",{}) is Dictionary or not decision.get("settings",{}) is Dictionary: return "profile/settings must be dictionaries"
	for key: String in decision.get("profile",{}):
		var value: Variant = decision.profile[key]
		if NUMBERS.has(key):
			if not _number(value,float(NUMBERS[key][0]),float(NUMBERS[key][1])): return "Invalid profile value: " + key
		elif key in ["infantry","vehicles","air"]:
			if not value is Array or value.is_empty() or value.size()>32: return "Unit cycles need 1 to 32 suffixes"
			for suffix: Variant in value:
				if not suffix is String or not sim.rules.units.has(sim.factions[team]+"_"+suffix): return "Unknown faction unit suffix"
		elif key == "style":
			if value not in ["balanced","pressure","armor"]: return "Invalid style"
		else: return "Unknown profile key: " + key
	for key: String in decision.get("settings",{}):
		if key == "wave":
			if not _number(decision.settings[key],1,40): return "wave must be in [1,40]"
		elif key == "attack_gap":
			if not _number(decision.settings[key],2,300): return "attack_gap must be in [2,300]"
		else: return "Unknown settings key: " + key
	if not decision.get("commands",[]) is Array or decision.get("commands",[]).size()>MAX_COMMANDS: return "commands must be a bounded array"
	for raw: Variant in decision.get("commands",[]):
		if not raw is Dictionary: return "Each command must be an object"
	return ""

func _number(value: Variant, low: float, high: float) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value)>=low and float(value)<=high

func execute(sim, team: int, raw: Dictionary) -> String:
	var action := str(raw.get("action",""))
	if raw.has("team") and raw.team != team: return "Cannot command another team"
	var selected: Array = raw.get("ids",[raw.get("id",-1)]) if raw.get("ids",[]) is Array else []
	if action in ["issue","produce","sell","cancel_production","rally"]:
		if selected.is_empty(): return "Missing owned entity ids"
		for id: Variant in selected:
			if not _number(id,0,2147483647) or float(id)!=floorf(float(id)) or not sim.entities.has(int(id)) or int(sim.entities[int(id)].team)!=team: return "Entity is missing or belongs to another team"
	var position: Variant = raw.get("pos",Vector2.ZERO)
	if position is Array and position.size()==2 and _number(position[0],-100000,100000) and _number(position[1],-100000,100000): position = Vector2(float(position[0]),float(position[1]))
	if not position is Vector2 or not position.is_finite(): return "Invalid finite position"
	var channel := str(raw.get("channel","auto"))
	if channel not in ["auto","normal","defense"]: return "Invalid channel"
	var target: Variant = raw.get("target",-1)
	if not _number(target,-1,2147483647) or float(target)!=floorf(float(target)): return "Invalid target"
	var id: int = int(selected[0]) if not selected.is_empty() else -1
	match action:
		"build":
			var builder: Variant = raw.get("builder",-1)
			if not _number(builder,-1,2147483647) or float(builder)!=floorf(float(builder)): return "Invalid builder"
			if int(builder)>=0 and not sim._builder_valid(team,int(builder)): return "Invalid owned builder"
			return sim.build(team,str(raw.get("spec","")),int(builder))
		"place": return sim.place_building(team,position,channel)
		"produce": return sim.produce(id,str(raw.get("spec","")))
		"sell": return sim.sell(id,bool(raw.get("confirmed",false)))
		"cancel_build": return sim.cancel_build(team,channel)
		"cancel_production": return sim.cancel_production(id,int(raw.get("index",0)))
		"rally": sim.set_rally(id,position)
		"issue":
			var kind := str(raw.get("kind",""))
			if kind not in ORDERS: return "Unknown order"
			if int(target)>=0 and kind != "harvest":
				if not sim.entities.has(int(target)) or (int(sim.entities[int(target)].team)!=team and not sim.entity_visible_to(team,int(target))): return "Target is not currently visible"
			for unit: Variant in selected:
				if float(sim.entities[int(unit)].get("ai_traffic_until",0.0)) > float(sim.time): return "Unit is yielding for traffic"
			sim.issue(selected,kind,position,int(target),bool(raw.get("append",false)))
		_: return "Unknown action: " + action
	return ""

func snapshot(sim) -> Dictionary:
	var logs: Array[Dictionary] = []
	for team: int in modules:
		logs.append({"team":team,"memory":sim.ai_state[team].independent_memory.duplicate(true),"recording_memory":sim.ai_state[team].get("independent_recording_memory",{}).duplicate(true),"decisions":sim.ai_state[team].independent_log.duplicate(true)})
	return _json_value({"api_version":API_VERSION,"reaction_seconds":REACTION_SECONDS,"identities":identities.duplicate(true),"teams":logs,"error":error})

func _json_value(value: Variant) -> Variant:
	if value is Vector2: return [value.x,value.y]
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value: result[str(key)] = _json_value(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value: result.append(_json_value(item))
		return result
	return value
