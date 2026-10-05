extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var game=load("res://main.tscn").instantiate()
	game.set_script(load("res://tools/pipelined_game_probe.gd"))
	root.add_child(game)
