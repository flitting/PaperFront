extends SceneTree
var failures:Array[String]=[]
var checks:int=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var game=load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false);game.set_physics_process(false)
	game.started=true;game.sim.ai_enabled=false
	game.hud.show_entry(false);game.hud.show_menu(false)
	game.render_overlap_enabled=true
	check(game._simulation_overlap.start()==OK,"persistent worker starts")
	var step:float=1.0/30.0
	if DisplayServer.get_name()!="headless":
		var before_draw:float=game.sim.time
		game._physics_process(step)
		await RenderingServer.frame_post_draw
		check(not game._simulation_overlap.active and is_equal_approx(game.sim.time,before_draw+step),"actual renderer barriers publish a complete tick before later frame observers")
		var pause_key:=InputEventKey.new()
		pause_key.pressed=true;pause_key.keycode=KEY_P
		game._physics_process(step)
		game._unhandled_input(pause_key)
		check(game.pve_paused and game._queued_simulation_delta==0,"keyboard pause flushes due work before UI state changes")
		game._unhandled_input(pause_key)
	var began:float=game.sim.time
	game._physics_process(step)
	check(game.sim.time==began and not game._simulation_overlap.active,"last due tick waits until render submission")
	game._physics_process(step);game._physics_process(step)
	check(is_equal_approx(game.sim.time-began,2*step),"catch-up ticks are executed, not dropped")
	game._dispatch_render_simulation()
	check(game._simulation_overlap.active,"dispatch transfers exclusive ownership")
	game._collect_render_simulation()
	check(is_equal_approx(game.sim.time-began,3*step) and not game._simulation_overlap.active,"post-draw collection completes every due tick")
	check(game._simulation_overlap.worker_thread_id!=OS.get_thread_caller_id(),"simulation executes on a distinct persistent thread")
	game._physics_process(step);game._dispatch_render_simulation()
	game.handle_action("pause",null)
	check(game.pve_paused and not game._simulation_overlap.active and is_equal_approx(game.sim.time-began,4*step),"pause joins the in-flight tick before changing state")
	var paused:float=game.sim.time
	game._physics_process(step);game._dispatch_render_simulation();game._collect_render_simulation()
	check(game.sim.time==paused,"paused frames do not accumulate simulation debt")
	game.handle_action("pause",null)
	game._physics_process(step)
	game.handle_action("save",null)
	check(is_equal_approx(game.sim.time-paused,step) and game._queued_simulation_delta==0,"save flushes the last due tick")
	var saved_time:float=game.sim.time
	game._physics_process(step);game._dispatch_render_simulation()
	await game.handle_action("load",null)
	check(not game._simulation_overlap.active and is_equal_approx(game.sim.time,saved_time),"load joins before replacing saved simulation state")
	check(not game.loading and not game.loading_screen.screen.visible,"awaited load closes the loading screen before returning control")
	game._physics_process(step);game._dispatch_render_simulation();game._collect_render_simulation()
	check(is_equal_approx(game.sim.time,saved_time+step),"restored state continues on the persistent worker")
	var infantry:int=game.sim.debug_spawn(0,game.sim.factions[0]+"_rifle",Vector2(15.5,40.5))
	check(infantry>0,"interactive command fixture has a legal unit")
	game.selected=[infantry]
	game.command_units("move",Vector2(20.5,42.5))
	game._physics_process(step);game._dispatch_render_simulation()
	game.handle_action("stop",null)
	check(not game._simulation_overlap.active and game.sim.entities[infantry].commands.is_empty(),"stop command joins active work before changing unit orders")
	var old=game.sim
	game._physics_process(step);game._dispatch_render_simulation()
	check(game.start_match("dev",17,"iron",true),"new match starts after an active job")
	check(not game._simulation_overlap.active and game.sim!=old and game.sim.factions[0]=="iron","changing maps does not leave a worker on the old simulation")
	game.sim.ai_enabled=false
	game._physics_process(step);game._dispatch_render_simulation()
	var worker=game._simulation_overlap
	root.remove_child(game);game.free()
	check(not worker.active and not worker._thread.is_started(),"teardown joins active work and closes the worker without callbacks into freed children")
	worker=null;old=null
	print("SIMULATION_RENDER_OVERLAP ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
