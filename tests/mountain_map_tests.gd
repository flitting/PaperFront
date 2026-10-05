extends SceneTree

const Map = preload("res://scripts/map_data.gd")
var checks: int = 0
var failures: Array[String] = []

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _initialize() -> void:
	for seed in [0, 1, 7, 21, 73026, 20260930, -1, -37, -2147483648, 2147483647]:
		var started: int = Time.get_ticks_msec()
		var map: Dictionary = Map.generate("mountains", seed)
		_check(map.size == 320 and map.valid, "mountains seed %d validates: %s" % [seed, str(map.get("validation_errors", []))])
		_check(Map.validate(map).is_empty(), "mountains seed %d preserves permanent land routes and equal resources" % seed)
		for start in map.starts:
			_check(Map.height_at(map, Vector2(start[0], start[1])) == 4.0, "mountain headquarters start on the level-four shelf")
		var trees: int = 0
		var neutral_buildings: int = 0
		var ground_nodes: bool = true
		for ruin in map.ruins:
			if ruin.kind == "tree":
				trees += 1
				ground_nodes = ground_nodes and Map.terrain_at(map, ruin.pos) == Map.LAND
			else: neutral_buildings += 1
		_check(trees > 2000 and neutral_buildings >= 40, "large mountain map supplies forests and separated neutral building clusters")
		_check(ground_nodes, "all destructible trees have permanent ground navigation nodes")
		_check(map.mines.size() >= 16, "large mountain map supplies equal starting patches and remote ore")
		print("Mountain seed %d: %d trees, %d neutral buildings, %d ms" % [seed, trees, neutral_buildings, Time.get_ticks_msec() - started])
	var first: Dictionary = Map.generate("mountains", 7)
	var again: Dictionary = Map.generate("mountains", 7)
	_check(first == again, "mountain map generation is deterministic")
	_check(Map.generate("handmade", 7).size == 160 and Map.generate("dev", 7).size == 48, "existing map modes retain their dimensions")
	var legacy: Dictionary = first.duplicate(true)
	var tree: Dictionary = legacy.ruins.filter(func(e): return e.kind == "tree")[0]
	legacy.terrain[int(tree.pos.y)][int(tree.pos.x)] = Map.BLOCKED
	tree.hp = 0.0
	_check(Map.clear_destroyed_tree(legacy, tree) and Map.terrain_at(legacy, tree.pos) == Map.LAND, "legacy dead trees release their static terrain cell")
	_check(not Map.clear_destroyed_tree(legacy, tree), "fresh dynamic tree death leaves terrain unchanged")
	print("Mountain map checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
