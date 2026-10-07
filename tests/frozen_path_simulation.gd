extends "res://scripts/simulation.gd"

# Keep production asynchronous dispatch while making pending work independent
# of thread scheduling. This adapter is never loaded by the game or profiler.
func _init() -> void:
	map_generation_config = {"legacy_dev48": true}


func _create_path_worker():
	return preload("res://tests/frozen_path_worker.gd").new()
