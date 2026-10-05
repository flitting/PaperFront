extends "res://scripts/simulation.gd"
func _create_path_worker():
	return preload("res://tests/slow_path_worker.gd").new()
