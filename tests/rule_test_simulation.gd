extends "res://scripts/simulation.gd"
# Deterministic mechanics adapter, never loaded by the game or benchmarks.
# Thread scheduling and frame budgets have their own real-worker tests.
func _init()->void:
	synchronous_path_tests=true
	map_generation_config={"legacy_dev48":true}
