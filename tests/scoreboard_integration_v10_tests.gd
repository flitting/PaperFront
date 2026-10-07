extends SceneTree
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func run()->void:
	var game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_physics_process(false);game.audio.muted=true
	check(game.start_match("dev",10,"kestrel",true),"actual source battle starts")
	game.sim.ai_enabled=false;game.hud.show_entry(false);game.hud.show_menu(false)
	var enemies:Array=[]
	for entity in game.sim.entities.values():
		if int(entity.team)==1 and entity.kind=="building":enemies.append(int(entity.id))
	for id:int in enemies:game.sim._kill_entity(id,true)
	game.sim._check_result();game._process(.016)
	check(game.sim.result=="win","actual opposing building elimination produces a victory")
	check(game.hud.scoreboard.visible and game.hud.scoreboard.displayed_result=="win" and game.hud.scoreboard.get_window()==root,"victory opens settlement inside the original game window")
	check(game.pve_paused and game.battlefield_viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"result freezes simulation and disables battlefield rendering")
	check(not game.battlefield_display.visible,"settlement page hides the completed battlefield")
	check(game.hud.scoreboard.displayed_stats.teams.size()==game.sim.factions.size(),"scoreboard displays every participating army's real ledger")
	check(game.hud.scoreboard.displayed_stats.events.any(func(event):return event.kind=="result"),"between-tick result event reaches settlement before visual events are drained")
	check(FileAccess.file_exists(game._statistics_export_prefix+".json") and FileAccess.file_exists(game._statistics_export_prefix+"_timeseries.csv"),"actual settlement automatically exports JSON and CSV")
	game.hud.scoreboard.export_button.pressed.emit()
	check(game.hud.scoreboard.visible and game.hud.scoreboard.export_status.text.contains("已导出"),"manual re-export keeps the page open and reports success")
	var time_before:float=game.sim.time;game._physics_process(1);game._process(1)
	check(game.sim.time==time_before and game.battlefield_viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"finished battle remains frozen on later frames")
	game.hud.scoreboard.menu_button.pressed.emit();await process_frame
	check(not game.hud.scoreboard.visible and game.hud.entry_menu.visible,"settlement page returns directly to the product menu")
	game.handle_action("entry_play",null);await process_frame
	check(game.hud.menu.visible,"a new battle can be configured from the score menu")
	check(game.start_match("dev",11,"kestrel",true),"starting another match clears prior scoreboard state")
	check(game._scoreboard_result.is_empty() and not game.hud.scoreboard.visible and not game.pve_paused and game.battlefield_display.visible,"new match resumes a clean visible battlefield")
	game.quit_pending=true;game.audio.stop_all();await create_timer(.2).timeout
	game.queue_free();await process_frame
	print("SCOREBOARD_INTEGRATION_V10 ",JSON.stringify({"checks":checks,"failures":failures}))
	call_deferred("finish")
func finish()->void:
	await process_frame;await create_timer(.2).timeout
	for failure:String in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
