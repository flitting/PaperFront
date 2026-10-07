extends SceneTree

const Main = preload("res://scripts/main.gd")
const Sim = preload("res://tests/rule_test_simulation.gd")
const Rules = preload("res://scripts/rules_loader.gd")
var config: Dictionary
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	config = Rules.load_rules()
	if config.is_empty():
		push_error("Debug placement fixture requires valid gameplay rules")
		quit(1)
		return
	_test_forest_pocket()
	_test_cliff_footprint()
	_test_mine_footprint()
	print("DEBUG_SPAWN_NAVIGATION ", checks - failures.size(), "/", checks)
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)


func _fixture():
	# Placement needs geometry queries only; this adapter starts no path threads.
	var sim = Sim.new()
	sim.native_kernels_enabled = false
	sim.native_geometry_enabled = false
	sim.setup(config.duplicate(true), "dev", 7, "rivet", false)
	for z: int in range(48):
		for x: int in range(48):
			sim.map.terrain[z][x] = 0
			sim.map.heights[z][x] = 0.0
	sim.mines.clear()
	sim.bridges.clear()
	sim.ruins.clear()
	sim._refresh_mine_spatial()
	sim._refresh_ruin_spatial()
	for id: int in sim.entities.keys(): sim._kill_entity(id, false)
	sim.debug_spawn(0, "rivet_hq", Vector2(4, 44))
	sim.debug_spawn(1, "kestrel_hq", Vector2(44, 44))
	sim._prepare_terrain_cache()
	sim._rebuild_spatial()
	return sim


func _placement(sim, origin: Vector2) -> Vector2:
	# Exercise the actual Debug helper without opening a scene or renderer.
	var game = Main.new()
	game.sim = sim
	var result: Vector2 = game.standable_near(origin)
	game.sim = null
	game.free()
	return result


func _test_forest_pocket() -> void:
	var sim = _fixture()
	var origin := Vector2(24.5, 24.5)
	for offset: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		sim.ruins.append({"id": sim.ruins.size(), "kind": "tree", "pos": origin + offset, "half": Vector2(.48, .48), "hp": 100.0, "max_hp": 100.0, "yaw": 0.0, "variant": 0})
	sim._refresh_ruin_spatial()
	_check(sim._standing(origin, .35, -1, false), "small infantry can stand inside the closed four-tree pocket")
	_check(not sim._standing(origin, .8, -1, false), "the pocket cannot accommodate Debug's reserved spawn footprint")
	var point: Vector2 = _placement(sim, origin)
	_check(not point.is_equal_approx(origin) and sim._standing(point, .8, -1, false), "actual Debug placement chooses a forest-free position with the requested clearance")
	var spawned: int = sim.debug_spawn(0, "rivet_rifle", point)
	_check(spawned >= 0 and (sim.entities[spawned].pos as Vector2).is_equal_approx(point), "real unit spawning retains the clear Debug position")
	sim = null


func _test_cliff_footprint() -> void:
	var sim = _fixture()
	var origin := Vector2(24.5, 24.5)
	for z: int in range(48):
		for x: int in range(25, 48): sim.map.heights[z][x] = 2.0
	sim._prepare_terrain_cache()
	_check(sim._standing(origin, .35, -1, false) and not sim._terrain_clear(origin, .8), "a safe infantry center can still put the reserved footprint over a cliff")
	var point: Vector2 = _placement(sim, origin)
	_check(not point.is_equal_approx(origin) and sim._standing(point, .8, -1, false), "actual Debug placement keeps its complete reserved footprint off the cliff")
	sim = null


func _test_mine_footprint() -> void:
	var sim = _fixture()
	var origin := Vector2(24.5, 24.5)
	sim.mines.append({"pos": origin + Vector2(1.2, 0), "amount": 1000.0, "capacity": 1000.0, "miner": -1})
	sim._refresh_mine_spatial()
	_check(sim._standing(origin, .35, -1, false) and not sim._standing(origin, .8, -1, false), "an apparently clear center can overlap a mine at the requested spawn radius")
	var point: Vector2 = _placement(sim, origin)
	_check(not point.is_equal_approx(origin) and sim._standing(point, .8, -1, false), "actual Debug placement rejects the mine-overlapping footprint")
	sim = null
