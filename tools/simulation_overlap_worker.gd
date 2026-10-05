extends RefCounted
## Diagnostic persistent worker; both semaphores are ownership handoffs.
var thread:=Thread.new()
var wake:=Semaphore.new()
var done:=Semaphore.new()
var active:bool=false
var stopping:bool=false
var simulation:RefCounted
var step_delta:float=0.0
var duration_ms:float=0.0
func start()->void:thread.start(_run)
func dispatch(sim:RefCounted,delta:float)->void:
	assert(not active)
	simulation=sim;step_delta=delta;active=true;wake.post()
func collect()->float:
	assert(active)
	done.wait();active=false
	var result:float=duration_ms
	simulation=null
	return result
func close()->void:
	if active:collect()
	if not thread.is_started():return
	stopping=true;wake.post();thread.wait_to_finish()
func _run()->void:
	while true:
		wake.wait()
		if stopping:return
		var began:int=Time.get_ticks_usec()
		simulation.step(step_delta)
		duration_ms=float(Time.get_ticks_usec()-began)/1000.0
		done.post()
