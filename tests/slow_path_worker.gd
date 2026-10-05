extends "res://scripts/path_worker.gd"
# Deliberately stall a search on the background thread, not the game thread.
func _search(job:Dictionary)->Array:
	OS.delay_msec(200)
	return super._search(job)
