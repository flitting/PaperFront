extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game = load("res://main.tscn").instantiate()
	game.set_script(load("res://tools/wasd_camera_probe.gd"))
	root.add_child(game)
