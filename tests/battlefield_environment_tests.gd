extends SceneTree
const MAP = preload("res://scripts/map_data.gd")
const SIM = preload("res://scripts/simulation.gd")
const LANDSCAPE = preload("res://scripts/landscape.gd")
var checks: int = 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _initialize() -> void:
	for mode: String in ["city", "snow", "islands"]:
		var sim = SIM.new()
		sim.map = MAP.generate(mode, 7, {"players": 3})
		sim.ruins = sim.map.ruins.duplicate(true)
		var before: Dictionary = sim.map.duplicate(true)
		var landscape = LANDSCAPE.new()
		landscape._initialize_build(sim)
		landscape._build_environment()
		for ruin: Dictionary in sim.ruins: landscape._build_ruin(ruin)
		landscape._flush_batches()
		landscape.sync_resources(sim)
		check(before == sim.map, mode + " renderer leaves topology and entities unchanged")
		check(landscape.stats.environment_props == sim.map.environment_props.size(), mode + " all environmental props enter real mesh batches")
		check(landscape.stats.prop_draws < sim.map.environment_props.size() + sim.map.ruins.size(), mode + " complete models share spatial batches")
		var house: Array = sim.ruins.filter(func(r): return r.has("archetype"))
		if not house.is_empty():
			var neutral: Dictionary = house[0]
			var visual: Dictionary = landscape.ruin_visuals[int(neutral.id)]
			check(visual.intact.current_transform.basis != Basis.IDENTITY.scaled(Vector3.ZERO) and visual.rubble.current_transform.basis == Basis.IDENTITY.scaled(Vector3.ZERO), "intact architecture rendered and rubble initially hidden")
			neutral.hp = 0.0
			landscape._sync_ruin(neutral)
			check(visual.intact.current_transform.basis == Basis.IDENTITY.scaled(Vector3.ZERO) and visual.rubble.current_transform.basis != Basis.IDENTITY.scaled(Vector3.ZERO), "destroyed city geometry atomically swaps to real debris")
		if mode == "city":
			check(landscape._civilian_batches.size() == 3, "pedestrian models have actual variant MultiMeshes")
			check(landscape.stats.environment_people == sim.map.civilians.size(), "all neutral pedestrians are rendered")
			landscape.sync_environment(5.0)
		else:
			var tree: Dictionary = sim.ruins.filter(func(r): return r.kind == "tree")[0]
			check(landscape.tree_visuals.has(int(tree.id)), "biome vegetation renders and owns destruction slots")
			tree.hp = 0.0
			landscape._sync_ruin(tree)
			check(landscape.tree_visuals[int(tree.id)].all(func(p): return p.current_transform.basis == Basis.IDENTITY.scaled(Vector3.ZERO)), "destroyed environmental trees hide complete mesh slots")
		print("ENVIRONMENT %s %s" % [mode, str(landscape.stats)])
		landscape.free()
	print("Battlefield environment checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
