extends SceneTree

const Map = preload("res://scripts/map_data.gd")
var failures: Array[String] = []
var checks: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _initialize() -> void:
	var seeds: Array = [7] if "--quick" in OS.get_cmdline_user_args() else [0, 7, 73026, -2147483648, 2147483647]
	for seed in seeds:
		var started: int = Time.get_ticks_msec()
		var map: Dictionary = Map.generate("mountains640", seed)
		check(map.size == 640 and map.mode == "mountains640" and map.valid, "640 mountain seed %d validates: %s" % [seed, str(map.get("validation_errors", []))])
		check(Map.validate(map).is_empty(), "640 mountain ramps, ore and permanent dry routes remain accessible")
		var trees: int = 0
		var buildings: int = 0
		var tree_ground: bool = true
		for ruin in map.ruins:
			if ruin.kind == "tree":
				trees += 1
				tree_ground = tree_ground and Map.terrain_at(map, ruin.pos) == Map.LAND
			else: buildings += 1
		check(trees >= 19000 and buildings >= 450, "640 map retains fourfold forest and neutral scenery content")
		check(tree_ground and map.mines.size() == 52, "all trees are removable over persistent ground and resources scale across the map")
		for start in map.starts: check(Map.height_at(map, Vector2(start[0], start[1])) == 4.0, "both 640 headquarters retain high starting shelves")
		print("MOUNTAINS640 ", JSON.stringify({"seed": seed, "size": map.size, "trees": trees, "neutral_buildings": buildings, "mines": map.mines.size(), "starts": map.starts, "generation_and_validation_ms": Time.get_ticks_msec() - started}))
	print("Mountain640 checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
