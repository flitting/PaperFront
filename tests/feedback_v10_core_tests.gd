extends SceneTree
const Sim=preload("res://tests/rule_test_simulation.gd")
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func run()->void:
	var rules:Dictionary=RulesLoader.load_rules()
	var sim=Sim.new();sim.setup(rules,"dev",7,"kestrel",false)
	var bullet: int=sim._spawn(0,"kestrel_rifle",Vector2(20,20),true)
	var foot: int=sim._spawn(1,"rivet_rifle",Vector2(22,20),true)
	sim.events.clear();sim._add_damage(foot,100000,false,{"source":bullet,"source_team":0,"weapon":"kestrel_rifle","explosive":false});sim._apply_damage();sim._damage.clear()
	var deaths:Array=sim.events.filter(func(e):return e.kind=="death")
	check(deaths.size()==1 and deaths[0].death_style=="infantry_fall","bullet casualty uses authored fall without an explosion")
	foot=sim._spawn(1,"rivet_rifle",Vector2(22,20),true)
	sim.events.clear();sim._add_damage(foot,100000,false,{"source":bullet,"source_team":0,"weapon":"kestrel_tank","explosive":true});sim._apply_damage();sim._damage.clear()
	deaths=sim.events.filter(func(e):return e.kind=="death")
	check(deaths.size()==1 and deaths[0].death_style=="infantry_shatter","explosive casualty scatters paper debris")
	var stats:Dictionary=sim.match_statistics()
	check(stats.teams[0].units_killed==2 and stats.teams[1].units_lost==2,"confirmed lethal cause credits actual kills and losses")
	check(is_equal_approx(float(stats.teams[0].damage_dealt),float(rules.units.rivet_rifle.hp)*2),"overkill cannot inflate damage statistics")
	foot=sim._spawn(1,"rivet_rifle",Vector2(22,20),true)
	sim._damage.clear();sim._add_damage(foot,100000,false,{"source_team":0,"weapon":"shell","explosive":true});sim._add_damage(foot,10,false,{"source_team":1,"weapon":"rifle","explosive":false});sim.events.clear();sim._apply_damage();sim._damage.clear()
	deaths=sim.events.filter(func(e):return e.kind=="death")
	check(deaths[0].death_style=="infantry_shatter" and deaths[0].cause.source_team==0,"later queued hits do not overwrite the already-lethal blow")
	var factory:int=sim._spawn(0,"kestrel_factory",Vector2(20,26),true)
	var lost_before:int=int(sim.match_statistics().teams[0].buildings_lost)
	check(sim.sell(factory,true).is_empty(),"actual sell action succeeds")
	check(sim.match_statistics().teams[0].buildings_lost==lost_before,"selling is not recorded as a combat building loss")
	sim.statistics.add(0,"funds_earned",250);sim.money[0]+=250
	var snapshot:String="/tmp/paper-front-v10-statistics.pfront"
	check(sim.save_game(snapshot).is_empty(),"score statistics persist in ordinary save")
	var restored=Sim.new();check(restored.load_game(snapshot).is_empty(),"new statistics save loads normally")
	check(restored.match_statistics().teams[0].units_killed==sim.match_statistics().teams[0].units_killed and restored.match_statistics().teams[0].funds_earned==250,"restored score ledger preserves confirmed values")
	var snapshot_file:=FileAccess.open(snapshot,FileAccess.READ)
	var saved:Dictionary=snapshot_file.get_var(false);snapshot_file.close()
	var corrupt:Dictionary=saved.duplicate(true);corrupt.match_statistics.teams[0].damage_dealt="invalid"
	check(not preload("res://scripts/sim_save_validator.gd").check(corrupt).is_empty(),"invalid score data is rejected before replacing a running match")
	var legacy:Dictionary=saved.duplicate(true);legacy.erase("match_statistics")
	check(preload("res://scripts/sim_save_validator.gd").check(legacy).is_empty(),"older saves without a score ledger remain valid")
	var before:Array=sim.money.duplicate();sim.statistics.snapshot(sim)
	check(sim.money==before,"reading the scoreboard never mutates game economy")
	var power_sim=Sim.new();power_sim.setup(rules,"dev",7,"kestrel",false);power_sim.ai_enabled=false
	var remote:=Vector2(41,41)
	power_sim._spawn(0,"kestrel_factory",remote,true)
	power_sim.events.clear();power_sim.notices.clear();power_sim.step(.05)
	check(power_sim.events.any(func(e):return e.kind=="low_power" and int(e.team)==0) and power_sim.notices.any(func(s):return "电力不足" in s),"real power shortage emits a player alert and explanatory text")
	power_sim.events.clear();power_sim.step(.05)
	check(not power_sim.events.any(func(e):return e.kind=="low_power" and int(e.team)==0),"a continuing shortage does not repeat the transition alert")
	power_sim._spawn(0,"kestrel_power",Vector2(35,35),true)
	power_sim.events.clear();power_sim.notices.clear();power_sim.step(.05)
	check(power_sim.events.any(func(e):return e.kind=="power_restored" and int(e.team)==0) and power_sim.notices.any(func(s):return "电力恢复" in s),"restoring actual power emits recovery audio metadata and text")
	sim=null;restored=null;power_sim=null;await process_frame
	print("FEEDBACK_V10_CORE ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure:String in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
