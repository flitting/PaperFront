extends SceneTree

const Sim = preload("res://tests/rule_test_simulation.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var started: int = Time.get_ticks_msec()
	var sim = Sim.new()
	sim.setup(RulesLoader.load_rules(), "mountains", 7, "rivet", false)
	var setup_ms: int = Time.get_ticks_msec() - started
	started = Time.get_ticks_msec()
	var landscape: Node3D = PaperLandscape.build(sim)
	root.add_child(landscape)
	var build_ms: int = Time.get_ticks_msec() - started
	var trees: int = sim.ruins.filter(func(e): return e.kind == "tree").size()
	if int(landscape.stats.ground_chunks) != 100: failures.append("320-cell terrain must use 100 regional ground chunks")
	if landscape.tree_visuals.size() != trees: failures.append("every interactable tree must own persistent rendering slots")
	if int(landscape.stats.prop_draws) >= 1000: failures.append("large forests require regional instancing, not a draw per tree")
	started = Time.get_ticks_usec()
	for i in range(100): landscape.sync_resources(sim)
	var sync_mean_us: float = float(Time.get_ticks_usec() - started) / 100.0
	print("LARGE_LANDSCAPE ", JSON.stringify({"map_size": sim.map.size, "trees": trees, "setup_ms": setup_ms, "landscape_build_ms": build_ms, "resource_sync_mean_us": sync_mean_us, "stats": landscape.stats, "nodes": landscape.get_child_count()}))
	landscape.queue_free()
	await process_frame
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
