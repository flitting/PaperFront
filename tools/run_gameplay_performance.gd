extends SceneTree

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var config: Dictionary = {"case": "normal", "map": "mountains640", "seconds": 30.0, "warmup": 8.0, "resolution": Vector2i(1920, 1080), "render_scale": 1.0}
	var helper: String = "res://scripts/gameplay_performance.gd"
	for arg in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.trim_prefix("--").split("=", true, 1)
		if parts.size() != 2: continue
		if parts[0] in ["case", "map", "output", "quality"]: config[parts[0]] = parts[1]
		elif parts[0] in ["seconds", "warmup", "render_scale"]: config[parts[0]] = float(parts[1])
		elif parts[0] == "helper": helper = parts[1]
		elif parts[0] == "fullscreen": config.fullscreen = parts[1] == "true"
		elif parts[0] == "resolution":
			var dimensions: PackedStringArray = parts[1].split("x")
			config.resolution = Vector2i(int(dimensions[0]), int(dimensions[1]))
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	var probe: Node = load(helper).new()
	game.add_child(probe)
	game.gameplay_performance = probe
	probe.setup(game, config)
