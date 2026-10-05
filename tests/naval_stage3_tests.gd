extends SceneTree

const Navigation = preload("res://scripts/naval_navigation.gd")
const Operations = preload("res://scripts/naval_operations.gd")
const Models = preload("res://scripts/naval_models.gd")
const Volume = preload("res://scripts/volume_models.gd")

class FakeSim:
	extends RefCounted
	var map: Dictionary = {}
	var bridges: Array = []
	var entities: Dictionary = {}
	var _naval_navigation
	var _static_geometry_revision: int = 0
	var time: float = 0.0
	var mines: Array = []
	var shore_wall: Vector2 = Vector2.INF
	func data_for(spec: String) -> Dictionary:
		return {"radius": 0.8, "naval_air_draft": 1.35, "domain": "naval", "speed": 3.0, "size": 4, "expands": true}.duplicate()
	func _in_bounds(point: Vector2) -> bool:
		return point.x >= 0 and point.y >= 0 and point.x < float(map.size) and point.y < float(map.size)
	func _terrain(point: Vector2) -> int:
		return int(map.terrain[int(point.y)][int(point.x)])
	func _height(point: Vector2) -> float:
		return MapData.height_at(map, point)
	func _land(point: Vector2) -> bool:
		return _in_bounds(point) and _terrain(point) != 1
	func _standing(point: Vector2, radius: float, _ignore: int, _dynamic: bool = true) -> bool:
		if not _land(point): return false
		for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			if not _land(point + direction * radius): return false
		return true
	func _building_clear(point: Vector2, _radius: float, _ignore: int) -> bool:
		return not shore_wall.is_finite() or point.distance_to(shore_wall) > 0.3
	func _radius(e: Dictionary) -> float:
		return float(e.radius)
	func _segment_static(a: Vector2, b: Vector2, radius: float, ignore: int) -> bool:
		for n in range(ceilf(a.distance_to(b) / 0.2) + 1):
			var point: Vector2 = a.lerp(b, float(n) / maxf(1.0, ceilf(a.distance_to(b) / 0.2)))
			if not _standing(point, radius, ignore): return false
		return true
	func bridge_at(_point: Vector2) -> int:
		return -1
	func _nearby_ruins(_point: Vector2, _radius: float) -> Array:
		return []
	func _circle_rect(_point: Vector2, _radius: float, _center: Vector2, _half: Vector2) -> bool:
		return false
	func _eco(_name: String, default: Variant) -> Variant:
		return default
	func _is_air(_e: Dictionary) -> bool:
		return false
	func _turn(e: Dictionary, wanted: float, delta: float) -> void:
		e.alpha = move_toward(float(e.alpha), wanted, 95.0 * delta)
	func _spatial_move(_e: Dictionary, _from: Vector2, _to: Vector2) -> void:
		pass

var checks: int = 0
var failures: Array[String] = []

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _map() -> Dictionary:
	var terrain: Array = []
	var heights: Array = []
	for z in range(24):
		var row: Array[int] = []
		var level: Array[float] = []
		for x in range(24):
			var water: bool = x >= 8 and x <= 17 and z >= 2 and z <= 21
			row.append(1 if water else 0)
			level.append(0.0 if water else -2.4 if x == 7 or x == 18 else -1.8)
		terrain.append(row)
		heights.append(level)
	return {"size": 24, "terrain": terrain, "heights": heights, "bridges": [], "landing_beaches": [{"land_pos": Vector2(7.0, 6.5)}]}

func _initialize() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/rules.json"))
	_check(catalog != null, "rules JSON parses")
	if catalog == null:
		quit(1)
		return
	for faction in ["rivet", "kestrel", "iron", "sky"]:
		_check(catalog.buildings.has(faction + "_shipyard"), faction + " shipyard exists")
		for role in ["transport", "frigate", "signature"]:
			var id: String = faction + "_ship_" + role
			_check(catalog.units.has(id) and catalog.units[id].domain == "naval", id + " naval spec")
			_check(FileAccess.file_exists(catalog.units[id].animations.idle), id + " portrait exists")
		_check("naval" in catalog.weapons[faction + "_tank"].targets, faction + " tank can target naval")
	_check(catalog.units.iron_transport.domain == "ground" and catalog.units.iron_transport.art == "transport", "original Iron armored personnel carrier remains ground-based")
	_check(not catalog.units.has("rivet_transport") and not catalog.units.has("kestrel_transport") and not catalog.units.has("sky_transport"), "ship IDs do not shadow ground transports")
	var sim := FakeSim.new()
	sim.map = _map()
	Operations.initialize(sim)
	var nav = sim._naval_navigation
	var ship: Dictionary = {"id": 1, "kind": "unit", "spec": "rivet_ship_transport", "team": 0, "radius": 0.8, "pos": Vector2(10.5, 6.5), "alpha": 0.0, "hp": 690.0, "commands": []}
	sim.entities[1] = ship
	_check(nav.water_clear(sim, ship.pos, 0.8, 1.35, 1), "hull fits water lane")
	_check(not nav.water_clear(sim, Vector2(7.5, 6.5), 0.8, 1.35, 1), "hull cannot stand on beach")
	var pair: Dictionary = Operations.coast_pair(sim, ship, {"id": 2, "radius": 0.35, "pos": Vector2(6.5, 6.5)})
	_check(not pair.is_empty(), "beach yields adjacent land/water pair")
	if not pair.is_empty():
		_check(pair.land.distance_to(pair.water) < 2.4, "boarding cannot teleport across coast")
		_check(absf(sim._height(pair.land) - MapData.water_surface_y(sim.map, pair.water)) <= 1.25, "coast slope is traversable")
		sim.shore_wall = pair.land.lerp(pair.water, 0.5)
		_check(not Operations.pair_clear(sim, ship, {"id": 2, "radius": 0.35, "pos": Vector2(6.5, 6.5)}, pair), "new shoreline wall invalidates a cached boarding pair")
		sim.shore_wall = Vector2.INF
	for z in range(24):
		for x in range(24):
			if int(sim.map.terrain[z][x]) != 1: sim.map.heights[z][x] = 0.0
	_check(Operations.coast_pair(sim, ship, {"id": 2, "radius": 0.35, "pos": Vector2(6.5, 6.5)}).is_empty(), "high cliff cannot be used as a boarding shore")
	var direct: Array[Vector2] = nav.path_between(sim, Vector2(10.5, 4.5), Vector2(15.5, 17.5), 0.8, 1.35, 1)
	_check(not direct.is_empty(), "water-only path is available")
	sim.bridges = [{"id": 1, "bounds": [8, 11, 10, 2], "alive": true, "naval_clearance": 0.0}]
	nav.refresh_bridges(sim.bridges)
	_check(nav.path_between(sim, Vector2(10.5, 4.5), Vector2(15.5, 17.5), 0.8, 1.35, 1).is_empty(), "low bridge blocks the water channel")
	sim.bridges[0].alive = false
	nav.refresh_bridges(sim.bridges)
	_check(not nav.path_between(sim, Vector2(10.5, 4.5), Vector2(15.5, 17.5), 0.8, 1.35, 1).is_empty(), "destroyed bridge reopens channel")
	var geometry_hashes: Dictionary = {}
	for faction in ["rivet", "kestrel", "iron", "sky"]:
		for art in ["naval_transport", "naval_frigate", "naval_signature", "shipyard"]:
			var mesh = Volume.CraftMesh.new()
			var recipe: Dictionary = Models.make(mesh, art, faction, 0, "building" if art == "shipyard" else "unit")
			_check(not recipe.is_empty() and mesh.vertices.size() > 100 and mesh.shell_vertices.size() > 100, faction + "/" + art + " closed solid recipe")
			if not geometry_hashes.has(art): geometry_hashes[art] = {}
			geometry_hashes[art][hash(mesh.vertices)] = true
			if art == "naval_frigate" or art == "naval_signature": _check(recipe.has("turret_mesh") and recipe.has("muzzle_pos"), faction + "/" + art + " has real gun mount")
	for art: String in geometry_hashes: _check(geometry_hashes[art].size() == 4, art + " has four distinct faction silhouettes")
	var islands := FakeSim.new()
	islands.map = MapData.generate("islands", 31, {"players": 2})
	Operations.initialize(islands)
	var ports: Array = islands.map.get("harbors", [])
	if ports.size() >= 2:
		for draft_and_radius in [[1.35, 2.2], [1.8, 2.65], [2.25, 3.25]]:
			var draft: float = draft_and_radius[0]
			var hull_radius: float = draft_and_radius[1]
			var start: Vector2 = islands._naval_navigation.near_water(islands, ports[0].water_pos, hull_radius, draft, -1, 8.0)
			var goal: Vector2 = islands._naval_navigation.near_water(islands, ports[1].water_pos, hull_radius, draft, -1, 8.0)
			_check(start.is_finite() and goal.is_finite(), "both protected harbors fit hull radius %.2f" % hull_radius)
			if start.is_finite() and goal.is_finite():
				_check(not islands._naval_navigation.path_between(islands, start, goal, hull_radius, draft, -1).is_empty(), "protected harbors share an open sea route for hull radius %.2f" % hull_radius)
	print("Naval Stage3 checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
