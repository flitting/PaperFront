extends RefCounted
## One exclusive simulation job between renderer pre/post-draw barriers.
## The main thread never reads or writes the simulation while active. Semaphores
## transfer ownership; no Node, renderer or UI methods execute on this worker.
var _thread:=Thread.new()
var _wake:=Semaphore.new()
var _done:=Semaphore.new()
var active:bool=false
var _stopping:bool=false
var _simulation:WarSimulation
var _delta:float=0.0
var _duration_ms:float=0.0
var worker_thread_id:int=0
func start()->Error:
	if _thread.is_started():return OK
	_stopping=false
	return _thread.start(_run)
func dispatch(simulation:WarSimulation,delta:float)->void:
	assert(_thread.is_started() and not active and not _stopping)
	_simulation=simulation;_delta=delta;active=true
	_wake.post()
func collect()->float:
	assert(active)
	_done.wait()
	active=false
	var result:float=_duration_ms
	_simulation=null
	return result
func close()->void:
	if active:collect()
	if not _thread.is_started():return
	_stopping=true
	_wake.post()
	_thread.wait_to_finish()
func _run()->void:
	worker_thread_id=OS.get_thread_caller_id()
	while true:
		_wake.wait()
		if _stopping:return
		var began:int=Time.get_ticks_usec()
		_simulation.step(_delta)
		_duration_ms=float(Time.get_ticks_usec()-began)/1000.0
		_done.post()
