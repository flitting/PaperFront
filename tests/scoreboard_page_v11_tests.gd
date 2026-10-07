extends SceneTree
const Score=preload("res://scripts/match_scoreboard.gd")
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func run()->void:
	var score=Score.new();root.add_child(score);await process_frame
	var stats:Dictionary={"duration":185,"map_mode":"forest","history_complete":false,"teams":[{"team":0,"faction":"sky","units_killed":42,"units_lost":12,"funds_earned":12300},{"team":1,"faction":"rivet","units_killed":12,"units_lost":42},{"team":2,"faction":"iron"},{"team":3,"faction":"kestrel"}]}
	var action_log:Array=[];score.action.connect(func(k,v):action_log.append(k))
	var initial_windows:int=root.find_children("","Window",true,false).size()
	for dimensions:Vector2i in [Vector2i(1100,700),Vector2i(1440,810),Vector2i(1920,1080),Vector2i(3840,2160)]:
		root.size=dimensions;score.show_result(stats,"win")
		for frame in range(4):await process_frame
		check(score.get_window()==root and root.find_children("","Window",true,false).size()==initial_windows,"settlement adds no second window at "+str(dimensions))
		check(score.get_global_rect().is_equal_approx(root.get_visible_rect()),"settlement fills original game viewport")
		check(score.physical_body_font>=17.9,"table body remains readable at "+str(dimensions))
		check(score.result_label.get_theme_font_size("font_size")>=48,"title stays enlarged instead of shrinking for layout")
		check(score.get_global_rect().encloses(score.menu_button.get_global_rect()) and score.get_global_rect().encloses(score.quit_button.get_global_rect()),"all actions remain visible at "+str(dimensions))
		check(score.displayed_stats==stats and score.summary_label.text.contains("从读取时开始统计"),"display preserves authoritative ledger and historical-save note")
		var labels:Array=[]
		for node:Node in score.tables.find_children("","Label",true,false):labels.append(node.text)
		check(labels.has("42") and labels.has("净投入") and labels.has("击杀部队"),"readable page contains actual score values")
	score.menu_button.pressed.emit();check(not score.visible and action_log.back()=="entry_home","menu returns through ordinary product navigation")
	score.show_result(stats,"lose");score.new_battle_button.pressed.emit();check(not score.visible and action_log.back()=="entry_play","new battle returns through ordinary product navigation")
	score.show_result(stats,"draw");score.quit_button.pressed.emit();check(action_log.back()=="quit","exit retains ordinary application shutdown action")
	score.queue_free();await process_frame;await process_frame
	print("SCOREBOARD_PAGE_V11 ",JSON.stringify({"checks":checks,"failures":failures}))
	for label:String in failures:push_error(label)
	quit(0 if failures.is_empty() else 1)
