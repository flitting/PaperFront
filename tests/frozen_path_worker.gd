extends RefCounted

# A deterministic pending-path fixture: accept work without creating a thread
# or returning a route. Movement must stay responsive without a worker result.
var submitted: int = 0
var jobs: Array[Dictionary] = []


func start(_data: Dictionary) -> void:
	submitted = 0
	jobs.clear()


func submit(job: Dictionary) -> bool:
	submitted += 1
	jobs.append(job.duplicate())
	return true


func collect() -> Array[Dictionary]:
	return []


func prioritize(_ids: Dictionary) -> void:
	pass


func invalidate(_revision: int) -> void:
	pass


func close() -> void:
	jobs.clear()
