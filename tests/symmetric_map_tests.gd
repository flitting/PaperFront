extends SceneTree

const MAP = preload("res://scripts/map_data.gd")
const CATALOG = preload("res://scripts/battlefield_catalog.gd")
const LAYOUT = preload("res://scripts/symmetric_layout.gd")
const THUMBNAIL = preload("res://scripts/map_thumbnail.gd")
var checks: int = 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func _initialize() -> void:
	var map: Dictionary = MAP.generate("symmetric", 73026)
	check(map.valid and MAP.validate(map).is_empty(), "land-only symmetry map validates: %s" % str(map.validation_errors))
	check(map.size == 192 and map.starts.size() == 2, "compact competitive map has exactly two real starts")
	check(map.bridges.is_empty() and map.harbors.is_empty() and map.profile.water_fraction == 0.0, "no sea, river or naval-only infrastructure")
	check(map.ruins.filter(func(r): return r.kind == "house").size() == 4 and map.decorations.size() == 48, "four neutral cottages and twelve small mirrored tree stands keep the field open")
	var mirrored: bool = true
	var all_land: bool = true
	for z: int in map.size:
		for x: int in map.size:
			if map.terrain[z][x] == MAP.WATER: all_land = false
			if map.terrain[z][x] != map.terrain[z][map.size-1-x] or map.heights[z][x] != map.heights[z][map.size-1-x] or map.terrain[z][x] != map.terrain[map.size-1-z][x] or map.heights[z][x] != map.heights[map.size-1-z][x]: mirrored = false
	check(mirrored and all_land, "every terrain and height cell mirrors across both axes")
	var reachable: PackedByteArray = LAYOUT.flood(map, Vector2i(32,96))
	check(reachable.count(1) == map.size*map.size, "all land cells and all four height levels are accessible through legal slopes")
	for team: int in 2:
		var start: Vector2 = Vector2(map.starts[team][0],map.starts[team][1])
		var near: Array = map.mines.filter(func(m): return m.team == team and m.tier == "near")
		check(near.size() == 2 and near.all(func(m): return Vector2(m.pos[0],m.pos[1]).distance_to(start) < 18), "both headquarters have two equally close mining sites")
		var apron_clear: bool = true
		for z: int in range(76,116):
			for x: int in range(int(start.x)-20,int(start.x)+20):
				if map.heights[z][x] != 0 or map.terrain[z][x] not in [MAP.LAND,MAP.ROAD]: apron_clear = false
		check(apron_clear, "each base keeps forty metres of flat terrain for construction")
	var another_seed: Dictionary = MAP.generate("symmetric", -17, {"players":4})
	check(another_seed.terrain == map.terrain and another_seed.heights == map.heights and another_seed.mines == map.mines and another_seed.ruins == map.ruins and another_seed.starts == map.starts, "seeds preserve the fixed comparison layout and requested four-player config cannot add unfair starts")
	check(another_seed.seed == -17, "requested seed remains in exported match provenance")
	check(CATALOG.selectable_mode("symmetric") == "symmetric" and CATALOG.entries().any(func(e): return e.id == "symmetric" and e.players == [2] and e.size == 192), "map is publicly selectable with its actual dimensions and fixed participant count")
	var thumbnail: Dictionary = THUMBNAIL._generate({"mode":"symmetric","seed":73026,"players":2,"key":"test"})
	check(thumbnail.map_size == 192 and thumbnail.starts == map.starts and thumbnail.pixels.size() == 192*192*3, "menu thumbnail uses actual symmetry map geometry")
	var damaged: Dictionary = map.duplicate(true)
	damaged.heights[96][64] = 1.0
	check(not MAP.validate(damaged).is_empty(), "asymmetric height edit is rejected")
	damaged = map.duplicate(true)
	damaged.mines[0].capacity += 1
	check(not MAP.validate(damaged).is_empty(), "unequal economic capacity is rejected")
	damaged = map.duplicate(true)
	damaged.ruins[0].half.x += .5
	check(not MAP.validate(damaged).is_empty(), "unequal neutral collision footprint is rejected")
	damaged = map.duplicate(true)
	for z: int in [0,191]:
		for x: int in [0,191]: damaged.terrain[z][x] = MAP.WATER
	check(not MAP.validate(damaged).is_empty(), "symmetric sea additions are rejected by the land-only requirement")
	damaged = map.duplicate(true)
	damaged.starts.pop_back()
	check(not MAP.validate(damaged).is_empty(), "missing second base is rejected without indexing invalid data")
	print("Symmetric map checks: %d passed, %d failed" % [checks-failures.size(),failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
