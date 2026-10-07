extends SceneTree

const Match = preload("res://scripts/headless_match.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)
func run() -> void:
	var before := root.get_child_count()
	var match_a := Match.new()
	check(match_a.start({"map":"symmetric", "seed":733, "factions":["rivet","sky"]}).is_empty(), "headless uses real symmetric game map")
	check(root.get_child_count() == before and not match_a.sim.ai_enabled, "logic runner creates no render/audio/UI nodes and disables AI")
	check(match_a.sim.vision_enabled and match_a.sim.synchronous_path_tests, "normal fog rules and deterministic navigation")
	var initial: Dictionary = match_a.sim.match_statistics()
	check(initial.history.size() == 1 and is_zero_approx(float(initial.history[0].time)), "t0 bases are sampled")
	var commands: Array = [{"at":0.125,"team":0,"action":"produce","selector":"rivet_hq","spec":"rivet_rifle"}]
	check(match_a.run_for(2.35, .05, commands).is_empty(), "real production command is accepted at an exact off-tick timestamp")
	check(is_equal_approx(match_a.sim.time,2.35) and match_a.stop_reason=="duration_limit" and match_a.sim.result.is_empty(), "time limit keeps unfinished match distinct from draw")
	check(is_equal_approx(float(match_a.command_log[0].time),.125), "command boundary splits fixed ticks without delaying input")
	var stats_a: Dictionary = match_a.sim.match_statistics()
	check(is_equal_approx(float(stats_a.history.back().time),2.35), "duration endpoint is retained")
	var match_b := Match.new()
	check(match_b.start({"map":"symmetric", "seed":733, "factions":["rivet","sky"]}).is_empty(), "second deterministic run starts")
	check(match_b.run_for(2.35, .05, commands).is_empty(), "second run executes identical input")
	check(JSON.stringify(match_b.sim.match_statistics().history)==JSON.stringify(stats_a.history), "fixed seed and inputs reproduce complete logical telemetry")
	check(not match_b.run_for(1,.5).is_empty() and not match_b.run_for(-1).is_empty(), "invalid tick and duration are rejected")
	check(not match_b.validate_commands([{"at":3,"action":"sell","team":5,"id":1}]).is_empty(), "invalid owners rejected before execution")
	check(not match_b.validate_commands([{"at":3,"action":"place","team":0,"pos":["bad",2]}]).is_empty(), "invalid positions rejected")
	check(not match_b.validate_commands([{"at":3,"action":"build","team":0,"spec":"rivet_power","builder":1.9}]).is_empty(), "fractional builder ids rejected")
	check(not match_b.validate_commands([{"at":3,"action":"sell","team":0,"id":1,"confirmed":"false"}]).is_empty(), "confirmation requires an explicit boolean")
	check(not match_b.execute({"action":"sell","team":0,"id":2,"confirmed":true}).is_empty(), "headless command ownership is enforced")
	var save_path := "user://headless_match_test.pfront"
	check(match_a.sim.save_game(save_path).is_empty(), "headless saves real game state")
	var resumed := Match.new()
	check(resumed.start({"load":save_path}).is_empty() and not resumed.sim.ai_enabled, "saved state resumes without implicitly enabling legacy AI")
	check(resumed.run_for(.4,.05).is_empty() and is_equal_approx(resumed.sim.time,2.75), "duration on resume is additional game time")
	check(resumed.sim.match_statistics().history[0].time == 0, "save/restore preserves opening history")
	var match_end := Match.new()
	check(match_end.start({"map":"symmetric"}).is_empty(), "result fixture starts")
	check(match_end.run_for(1,.05,[{"at":.2,"team":1,"action":"sell","id":2,"confirmed":true}]).is_empty(), "sale uses real last-building result rule")
	check(match_end.stop_reason=="result" and match_end.sim.result=="win" and is_equal_approx(match_end.sim.time,.2), "game result stops logic loop immediately")
	check(match_end.sim.match_statistics().history.back().teams[1].alive_buildings==0, "settlement samples exact final ownership counts")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	match_a=null;match_b=null;resumed=null;match_end=null
	print("HEADLESS_MATCH_TESTS "+JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
