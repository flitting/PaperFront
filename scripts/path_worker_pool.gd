extends RefCounted
class_name BackgroundPathPool

# AStar objects and collision caches belong to individual workers. The pool is
# only touched by the simulation thread and shares immutable input snapshots.
const Worker = preload("res://scripts/path_worker.gd")
const DEFAULT_WORKERS: int = 2
const MAX_WORKERS: int = 4
const MAX_PENDING_PER_WORKER: int = 16

var _workers: Array = []
var _pending: Array[int] = []
var _cursor: int = 0
var route_cache_enabled: bool = true


func start(data: Dictionary) -> void:
	close()
	var snapshot: Dictionary = data.duplicate()
	snapshot.route_cache_enabled = bool(data.get("route_cache_enabled", route_cache_enabled))
	var count: int = clampi(int(data.get("worker_count", DEFAULT_WORKERS)), 2, MAX_WORKERS)
	for index in range(count):
		var worker = Worker.new()
		_workers.append(worker)
		_pending.append(0)
		worker.start(snapshot)


func submit(job: Dictionary) -> bool:
	if _workers.is_empty(): return false
	var tried: Array[int] = []
	for attempt in range(_workers.size()):
		var selected: int = -1
		var lowest: int = MAX_PENDING_PER_WORKER
		for offset in range(_workers.size()):
			var index: int = (_cursor + offset) % _workers.size()
			if tried.has(index) or _pending[index] >= lowest: continue
			selected = index
			lowest = _pending[index]
		if selected < 0: return false
		tried.append(selected)
		# A contended worker lock must not make the game thread wait; another
		# worker can accept the request, or it remains in the simulation queue.
		if not _workers[selected].submit(job): continue
		_pending[selected] += 1
		_cursor = (selected + 1) % _workers.size()
		return true
	return false


func prioritize(ids: Dictionary) -> void:
	for worker in _workers:
		if worker.has_method("prioritize"): worker.prioritize(ids)

func invalidate(revision: int) -> void:
	for worker in _workers: worker.invalidate(revision)


func collect() -> Array[Dictionary]:
	var answer: Array[Dictionary] = []
	for index in range(_workers.size()):
		var results: Array[Dictionary] = _workers[index].collect()
		_pending[index] = maxi(0, _pending[index] - results.size())
		answer.append_array(results)
	return answer


func close() -> void:
	for worker in _workers: worker.close()
	_workers.clear()
	_pending.clear()
	_cursor = 0
