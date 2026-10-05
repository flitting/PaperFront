extends SceneTree

## Run with a real display and -- --verify-expansion --expansion-hand-only.
## The real main scene owns input, posed continuous-skin picking, simulation
## and direct Skeleton rendering in both native/script world synchronization.
func _initialize() -> void:
	if "--verify-expansion" not in OS.get_cmdline_user_args():
		push_error("Creator input validation requires explicit --verify-expansion")
		quit(2)
		return
	call_deferred("run")

func run() -> void:
	root.add_child(load("res://main.tscn").instantiate())
