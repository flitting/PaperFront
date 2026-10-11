extends SceneTree
const Match = preload("res://scripts/headless_match.gd")
const Simulation = preload("res://scripts/simulation.gd")
const Loader = preload("res://scripts/rules_loader.gd")
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)
func run() -> void:
	var first := Match.new()
	var error: String=first.start({"map":"symmetric","factions":["kestrel","rivet"],"ai":"both","ai-styles":["pressure","armor"],"starts":"swap","seed":733})
	check(error.is_empty(), "AI 1v1 initializes normally: "+error)
	if not error.is_empty():finish();return
	check(first.sim.factions==["rivet","kestrel"] and first.sim.map.starts==[[32.0,96.0],[160.0,96.0]],"side swap reverses faction slots while preserving authored mine/layout geometry")
	check(first.sim.match_options.slots[0].ai_style=="armor" and first.sim.match_options.slots[1].ai_style=="pressure","strategy profiles stay attached to requested factions through side swap")
	var supplied_styles: Array=["pressure","armor"]
	var copy_probe:=Match.new()
	check(copy_probe.start({"ai-styles":supplied_styles,"starts":"swap"}).is_empty() and supplied_styles==["pressure","armor"],"swapping profile assignment leaves caller options unchanged")
	check(first.run_for(20,.05).is_empty(), "both AI slots execute")
	check(int(first.sim.ai_state[0].get("decisions",0))>0 and int(first.sim.ai_state[1].get("decisions",0))>0, "slot zero and slot one both make ordinary decisions")
	check(first.sim.money.all(func(value):return value>=0),"AI never creates negative budgets")
	var right_only := Match.new()
	check(right_only.start({"ai":"right","seed":733}).is_empty() and right_only.run_for(8,.05).is_empty(),"right-only AI control starts")
	check(right_only.sim.ai_state[0].get("decisions",0)==0 and right_only.sim.ai_state[1].get("decisions",0)>0,"human slot remains idle when only opponent AI enabled")
	var mirror := Match.new()
	check(mirror.start({"map":"symmetric","factions":["kestrel","rivet"],"ai":"both","ai-styles":["pressure","armor"],"starts":"swap","seed":733}).is_empty() and mirror.run_for(20,.05).is_empty(),"identical replay initializes")
	check(JSON.stringify(first.sim.match_statistics().history)==JSON.stringify(mirror.sim.match_statistics().history),"identical AI, styles, side mapping and seed reproduce history")
	var bot0: int=first.sim._spawn(0,"rivet_rifle",Vector2(50,96),true)
	var bot1: int=first.sim._spawn(1,"kestrel_rifle",Vector2(142,96),true)
	first.sim.issue([bot0],"move",Vector2(64,96))
	first.sim.issue([bot1],"move",Vector2(128,96))
	check(first.sim._navigation_priority(bot0)==0 and first.sim._navigation_priority(bot1)==0,"both AI slots receive the same ordinary command navigation priority")
	first.sim._navigation_command_until[bot0]=first.sim.time+3
	first.sim.set_player_navigation_priority([bot0])
	check(first.sim._navigation_priority(bot0)==0 and first.sim._player_navigation_ids.is_empty(),"AI slot zero ignores stale saved player boosts and UI selection boosts")
	var ordinary := Simulation.new()
	var factions: Array[String]=["kestrel","rivet"]
	var starts: Array[Vector2]=[]
	ordinary.setup_multiteam(Loader.load_rules("res://data/rules.json",false),"symmetric",733,factions,true,starts,Callable(),{"slots":[{"faction":"kestrel","control":"ai","difficulty":"normal"},{"faction":"rivet","control":"ai","difficulty":"normal"}]})
	check(ordinary.match_options.slots[0].control=="human","normal game retains human player even if a slot asks for AI")
	var human: int=ordinary._spawn(0,"kestrel_rifle",Vector2(50,96),true)
	ordinary.issue([human],"move",Vector2(64,96))
	check(ordinary._navigation_priority(human)==2,"normal human orders retain their recent-command navigation priority")
	ordinary.set_player_navigation_priority([human])
	check(ordinary._navigation_priority(human)==3,"normal human selection retains foreground navigation priority")
	check(not Match.new().start({"ai":"cheat"}).is_empty() and not Match.new().start({"ai-styles":["invalid"]}).is_empty(),"invalid AI modes and styles reject cleanly")
	first=null;right_only=null;mirror=null;ordinary=null;copy_probe=null
	finish()
func finish() -> void:
	print("HEADLESS_AI_CONTROLS "+JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
