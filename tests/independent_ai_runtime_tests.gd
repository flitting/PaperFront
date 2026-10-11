extends SceneTree
const MatchRunner=preload("res://scripts/headless_match.gd")
const Runtime=preload("res://scripts/independent_ai_runtime.gd")
const Observer="res://tests/fixtures/independent_ai_observer.gd"
const Builder="res://tests/fixtures/independent_ai_builder.gd"
const Illegal="res://tests/fixtures/independent_ai_illegal.gd"
const Recorder="res://tests/fixtures/independent_ai_observer_recorder.gd"
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func start(paths:Array,factions:Array=["kestrel","rivet"],extra:Dictionary={}):
	var runner=MatchRunner.new()
	var options:Dictionary={"map":"symmetric","seed":733,"factions":factions,"ai-modules":paths}
	options.merge(extra,true)
	var error:String=runner.start(options)
	check(error.is_empty(),"module match configures: "+error)
	return runner if error.is_empty() else null
func close(runner)->void:
	if runner!=null and runner.sim!=null and runner.sim._path_worker!=null:runner.sim._path_worker.close()
func isolation()->void:
	var runner=start([Observer,Observer])
	if runner==null:return
	var sim=runner.sim
	var rules_before:String=JSON.stringify(sim.rules)
	check(sim.independent_ai.modules[0]!=sim.independent_ai.modules[1],"same script creates independent per-team instances")
	check(runner.run_for(2.05,.05).is_empty(),"both modules execute one equal reaction")
	for team:int in range(2):
		var state:Dictionary=sim.ai_state[team]
		check(int(state.independent_memory.calls)==1 and sim.independent_ai.modules[team].local_calls==1,"team%d has independent memory and instance counters"%team)
		check(state.independent_memory.team==team and state.independent_memory.faction==sim.factions[team],"team%d receives its real identity and faction"%team)
		check(float(state.independent_memory.money_seen)==4000.0 and sim.money[team]==4000.0,"team%d observes only its own unmodified budget"%team)
		check(sim.entities[team+1].hp==float(sim.data_for(sim.factions[team]+"_hq").hp) and sim.entities[team+1].queue.is_empty(),"team%d copied entity input cannot mutate live HP or queues"%team)
		check(state.independent_log.size()==1 and is_equal_approx(float(state.independent_log[0].time),2.0),"team%d receipt uses host logical decision time"%team)
		check(float(state.independent_log[0].observation.money)==4000.0,"team%d official observation receipt survives module-local input mutation"%team)
	check(JSON.stringify(sim.rules)==rules_before,"copied public rules cannot mutate gameplay rules")
	sim.ai_state[0].independent_memory.only_team_zero=true
	check(not sim.ai_state[1].independent_memory.has("only_team_zero"),"direct own-memory mutation does not leak to the opponent")
	check(sim.result.is_empty() and runner.stop_reason=="duration_limit","short unfinished module observation is never a win or draw")
	var snapshot:Dictionary=sim.match_statistics()
	check(not snapshot.winner_teams_known and snapshot.winner_teams.is_empty(),"unfinished telemetry has no fabricated winner")
	close(runner)
func fog_and_commands()->void:
	var runner=start([Observer,Observer])
	if runner==null:return
	var sim=runner.sim
	var runtime=sim.independent_ai
	sim.money[1]=9876.0
	var enemy_facility:int=sim._spawn(1,"rivet_hq",Vector2(42,104),true)
	check(sim.produce(enemy_facility,"rivet_rifle").is_empty(),"visible enemy queue fixture uses ordinary paid production")
	var hidden:int=sim._spawn(1,"rivet_rifle",Vector2(162,96),true)
	sim._rebuild_spatial();sim.TeamVision.refresh(sim,true)
	var view:Dictionary=runtime.observation(sim,0)
	check(not sim.entity_visible_to(0,hidden) and not view.visible_enemies.any(func(e):return e.id==hidden),"fog omits unseen enemy entities")
	check(sim.entity_visible_to(0,enemy_facility) and view.visible_enemies.any(func(e):return e.id==enemy_facility),"ordinary sight exposes an enemy building")
	for enemy:Dictionary in view.visible_enemies:
		check(not enemy.has("queue") and not enemy.has("commands") and not enemy.has("money") and not enemy.has("cargo"),"visible enemy record omits private production, orders, budget and cargo")
	check(view.money==sim.money[0] and not view.has("ai_state") and not view.has("enemy_money") and not view.has("teams"),"observation does not expose opponent budget or planner state")
	view.orders.normal["forged"]=true;view.map.starts[0][0]=-999
	check(not sim.order_for_team(0,"normal").has("forged") and sim.map.starts[0][0]==32.0,"orders and map arrays are deep copies")
	var before:Array=sim.money.duplicate()
	for command:Dictionary in [
		{"action":"sell","id":2,"confirmed":true},
		{"action":"produce","id":2,"spec":"kestrel_rifle"},
		{"action":"rally","id":2,"pos":[80,96]},
		{"action":"issue","ids":[1,2],"kind":"stop"},
		{"action":"build","team":1,"spec":"kestrel_power"},
		{"action":"issue","id":1,"kind":"attack","target":hidden,"pos":[162,96]}
	]:check(not runtime.execute(sim,0,command).is_empty(),"ordinary dispatcher rejects foreign ownership/hidden target: "+str(command.action))
	check(sim.money==before and sim.entities.has(2) and sim.entities[2].queue.is_empty(),"rejected commands spend no money and cannot alter enemy HQ")
	check(runtime.execute(sim,0,{"action":"build","spec":"rivet_power"}).is_empty()==false,"normal faction gate rejects another faction's building")
	check(runtime.execute(sim,0,{"action":"build","spec":"kestrel_power"}).is_empty(),"legal owned construction uses ordinary build method")
	check(sim.money[0]==float(before[0])-float(sim.data_for("kestrel_power").cost) and sim.money[1]==before[1],"legal construction pays its exact own rules price once")
	close(runner)
func logging_and_swap()->void:
	var runner=start([Illegal,Observer])
	if runner!=null:
		check(runner.run_for(2.05,.05).is_empty(),"rejected policy actions are logged without inventing a game result")
		var attempts:Array=runner.sim.ai_state[0].independent_log[0].commands
		check(attempts.size()==6 and attempts.all(func(item):return not item.ok and not str(item.error).is_empty()),"every ownership rejection appears in the decision receipt")
		check(runner.sim.money==[4000.0,4000.0] and runner.sim.entities.has(1) and runner.sim.entities.has(2),"malicious action fixture cannot sell or fund either opponent")
		close(runner)
	var swapped=start([Builder,Observer],["kestrel","sky"],{"starts":"swap"})
	if swapped==null:return
	check(swapped.sim.factions==["sky","kestrel"],"start swap reverses actual faction slots")
	check(swapped.sim.independent_ai.identities[0].path==Observer and swapped.sim.independent_ai.identities[1].path==Builder,"modules stay attached to requested factions through swap")
	check(swapped.run_for(2.05,.05).is_empty(),"swapped module condition executes")
	check(swapped.sim.money[0]==4000.0 and swapped.sim.money[1]==4000.0-float(swapped.sim.data_for("kestrel_power").cost),"only the swapped builder faction spends its normal price")
	check(swapped.sim.ai_state[1].independent_memory.faction=="kestrel" and swapped.sim.ai_state[0].independent_memory.faction=="sky","swapped decision identity remains faction correct")
	check(swapped.sim.independent_ai.identities[1].sha256==FileAccess.get_sha256(Builder),"exportable module identity records actual source hash")
	close(swapped)
func save_restore()->void:
	var runner=start([Observer,Observer])
	if runner==null:return
	check(runner.run_for(2.3,.05).is_empty(),"persistent memory fixture executes")
	var path:String="user://independent_ai_runtime_test.pfront"
	check(runner.sim.save_game(path).is_empty(),"independent memory, logs and source identity save normally")
	var resumed=MatchRunner.new()
	check(resumed.start({"load":path,"ai":"both"}).is_empty(),"load discovers saved module paths and validates matching hashes")
	if resumed.sim.independent_ai!=null:
		check(resumed.sim.ai_state[0].independent_memory==runner.sim.ai_state[0].independent_memory and resumed.sim.ai_state[1].independent_memory==runner.sim.ai_state[1].independent_memory,"both memory dictionaries restore independently")
		check(resumed.run_for(1.7,.05).is_empty() and runner.run_for(1.7,.05).is_empty(),"saved reaction remainder resumes on the same logical boundary")
		check(resumed.sim.ai_state[0].independent_memory==runner.sim.ai_state[0].independent_memory and resumed.sim.ai_state[0].independent_log.size()==2,"resumed memory and decision count match uninterrupted policy")
		check(resumed.sim.independent_ai.identities==runner.sim.independent_ai.identities,"restored module identities remain exact")
	var mismatch=MatchRunner.new()
	check(not mismatch.start({"load":path,"ai":"both","ai-modules":[Builder,Observer]}).is_empty(),"saved strategy source hash cannot be silently replaced")
	close(mismatch);close(resumed);close(runner)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
func bad_modules_and_builtin()->void:
	for paths:Array in [[Observer],[Observer,"res://tests/fixtures/missing_module.gd"],[Observer,"res://tests/fixtures/independent_ai_missing_decide.gd"]]:
		var bad=MatchRunner.new()
		check(not bad.start({"ai-modules":paths}).is_empty(),"invalid module count/path/interface rejects cleanly")
		close(bad)
	var bad_return=start(["res://tests/fixtures/independent_ai_bad_return.gd",Observer])
	if bad_return!=null:
		check(not bad_return.run_for(2.05,.05).is_empty() and not str(bad_return.sim.independent_ai.error).is_empty(),"invalid decision return is an explicit module error")
		check(bad_return.sim.result.is_empty() and bad_return.sim.match_statistics().winner_teams.is_empty(),"module failure is not a fabricated opponent victory")
		close(bad_return)
	var legacy=MatchRunner.new()
	var explicit_builtin=MatchRunner.new()
	check(legacy.start({"ai":"both","seed":733}).is_empty() and explicit_builtin.start({"ai":"both","seed":733,"ai-modules":["builtin","builtin"]}).is_empty(),"builtin compatibility conditions start")
	check(legacy.sim.independent_ai==null and explicit_builtin.sim.independent_ai==null,"builtin does not instantiate independent decision runtime")
	check(legacy.run_for(4,.05).is_empty() and explicit_builtin.run_for(4,.05).is_empty(),"legacy builtin planning still executes")
	check(JSON.stringify(legacy.sim.match_statistics().history)==JSON.stringify(explicit_builtin.sim.match_statistics().history),"explicit builtin retains identical legacy logical telemetry")
	close(legacy);close(explicit_builtin)
func recorder_isolation_and_restore()->void:
	var runner=start([Observer,Observer])
	if runner==null:return
	var sim=runner.sim
	check(sim.independent_ai.recorders.size()==2 and sim.independent_ai.recorders[0]!=sim.independent_ai.recorders[1],"companions instantiate separately for the two teams")
	var rules_before:String=JSON.stringify(sim.rules)
	check(runner.run_for(2.3,.05).is_empty(),"recorder and policy share the ordinary two-second reaction")
	for team:int in range(2):
		var state:Dictionary=sim.ai_state[team]
		check(int(state.independent_recording_memory.calls)==1 and int(state.independent_memory.calls)==1,"team%d recorder and policy have separate counters"%team)
		check(state.independent_recording_memory.recorder_only and not state.independent_memory.has("recorder_only"),"team%d recorder-private memory cannot enter policy memory"%team)
		check(state.independent_memory.money_seen==4000.0 and sim.money[team]==4000.0,"team%d recorder view mutation cannot alter policy input or real money"%team)
		check(sim.entities[team+1].queue.is_empty() and sim.entities[team+1].hp==float(sim.data_for(sim.factions[team]+"_hq").hp),"team%d recorder cannot modify live entity fields"%team)
		check(state.independent_log[0].recording.money==4000.0 and state.independent_log[0].recording.home is Vector2,"team%d record output reaches its own decision log"%team)
		check(sim.independent_ai.identities[team].recorder.sha256==FileAccess.get_sha256(Recorder),"team%d recorder identity records actual source hash"%team)
	check(JSON.stringify(sim.rules)==rules_before,"recorder cannot modify live public rule data")
	sim.ai_state[0].independent_recording_memory.only_team_zero=true
	check(not sim.ai_state[1].independent_recording_memory.has("only_team_zero") and not sim.ai_state[0].independent_memory.has("only_team_zero"),"recording memory is isolated from the other recorder and own policy")
	var exported:Dictionary=JSON.parse_string(JSON.stringify(sim.independent_ai.snapshot(sim)))
	check(exported.teams[0].decisions[0].recording.home==[32.0,96.0] and exported.teams[1].decisions[0].recording.home==[160.0,96.0],"record export converts Vector2 homes to JSON coordinate arrays")
	check(exported.teams[0].decisions[0].recording.nested.positions[1]==[1.25,-2.5] and exported.teams[0].recording_memory.last_home==[32.0,96.0],"nested output and private recording-memory vectors export recursively")
	var path:String="user://independent_ai_recorder_test.pfront"
	check(sim.save_game(path).is_empty(),"recorder memory and identities save normally")
	var resumed=MatchRunner.new()
	check(resumed.start({"load":path,"ai":"both"}).is_empty(),"saved companions reconfigure with matching source hashes")
	if resumed.sim.independent_ai!=null:
		check(resumed.sim.ai_state[0].independent_recording_memory==sim.ai_state[0].independent_recording_memory,"recorder-private memory restores exactly")
		check(resumed.run_for(1.7,.05).is_empty() and runner.run_for(1.7,.05).is_empty(),"restored recorder advances at the same pending decision boundary")
		check(resumed.sim.independent_ai.snapshot(resumed.sim)==sim.independent_ai.snapshot(sim),"recorder memory, records and identities match uninterrupted exported state")
	var saved_hash:String=sim.ai_state[0].independent_recorder_sha256
	sim.ai_state[0].independent_recorder_sha256="old-recorder-source-hash"
	var mismatch_path:String="user://independent_ai_recorder_hash_mismatch.pfront"
	check(sim.save_game(mismatch_path).is_empty(),"recorder identity mismatch fixture saves without editing module source")
	sim.ai_state[0].independent_recorder_sha256=saved_hash
	var mismatch=MatchRunner.new()
	var mismatch_error:String=mismatch.start({"load":mismatch_path,"ai":"both"})
	check(mismatch_error.contains("recorder source hash differs"),"recorder source mismatch is rejected independently from policy source hash")
	close(mismatch);close(resumed);close(runner)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(mismatch_path))
func run()->void:
	isolation();fog_and_commands();logging_and_swap();save_restore();bad_modules_and_builtin();recorder_isolation_and_restore()
	print("INDEPENDENT_AI_RUNTIME "+JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
