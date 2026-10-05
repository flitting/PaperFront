extends "res://scripts/main.gd"
## Experimental driver only. No gameplay/input support is claimed here.
## The rendered performance fixture disables input. Scene state is accessed only
## after joining, and the worker owns only WarSimulation.step during rendering.
var pipeline_thread=preload("res://tools/simulation_overlap_worker.gd").new()
var pipeline_queued_delta:float=0.0
var pipeline_joins:int=0
var pipeline_wait_us:int=0
func _ready()->void:
	super._ready()
	if not "--performance-case" in OS.get_cmdline_user_args():
		push_error("This experimental driver requires --performance-case with input disabled")
		quit_game(2)
		return
	pipeline_thread.start()
	RenderingServer.frame_pre_draw.connect(_pipeline_dispatch)
	RenderingServer.frame_post_draw.connect(_pipeline_collect)
func _pipeline_step(delta:float)->float:
	var began:int=Time.get_ticks_usec()
	sim.step(delta)
	return float(Time.get_ticks_usec()-began)/1000.0
func _pipeline_collect()->void:
	if not pipeline_thread.active:return
	var began:int=Time.get_ticks_usec()
	sim_cpu_ms=pipeline_thread.collect()
	pipeline_joins+=1;pipeline_wait_us+=Time.get_ticks_usec()-began
	reserve_cpu_ms=0.0
	if gameplay_performance!=null:
		began=Time.get_ticks_usec()
		gameplay_performance.after_tick()
		reserve_cpu_ms=float(Time.get_ticks_usec()-began)/1000.0
	if benchmark:
		benchmark_tick_count+=1
		benchmark_interval_sim_ms+=sim_cpu_ms
		if benchmark_elapsed>5:
			cpu_samples.append(sim_cpu_ms)
			reserve_tick_samples.append(reserve_cpu_ms)
func _pipeline_dispatch()->void:
	if quit_pending or pipeline_queued_delta<=0 or pipeline_thread.active:return
	if gameplay_performance==null or not get_viewport().gui_disable_input:return
	var delta:float=pipeline_queued_delta
	pipeline_queued_delta=0.0
	pipeline_thread.dispatch(sim,delta)
func _physics_process(delta:float)->void:
	_pipeline_collect()
	if sim==null or not started or pve_paused:return
	# Never drop catch-up ticks. Keep only the last due tick for render overlap.
	if pipeline_queued_delta>0:super._physics_process(pipeline_queued_delta)
	pipeline_queued_delta=delta
func _process(delta:float)->void:
	_pipeline_collect()
	super._process(delta)
func _unhandled_input(_event:InputEvent)->void:
	pass # An interactive controller needs explicit command ownership first.
func quit_game(exit_code:int=0)->void:
	_pipeline_collect()
	pipeline_queued_delta=0.0
	print("PIPELINE_DIAGNOSTIC ",JSON.stringify({"joins":pipeline_joins,"join_wait_ms":float(pipeline_wait_us)/1000.0,"scope":"experimental performance driver; no interactive acceptance"}))
	super.quit_game(exit_code)
func _exit_tree()->void:
	pipeline_thread.close()
