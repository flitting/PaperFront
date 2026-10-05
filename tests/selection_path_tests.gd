extends SceneTree
const PATHS = preload("res://scripts/selection_paths.gd")
const OVERLAY = preload("res://scripts/selection_overlay.gd")
class Projector:
	extends Node3D
	var projected: Array[Vector3] = []
	func project_world_to_screen(point: Vector3) -> Vector2:
		projected.append(point)
		return Vector2(point.x * 10, point.z * 20) + Vector2(40, 30)
	func battlefield_rect() -> Rect2: return Rect2(40, 30, 320, 200)
var failures: Array[String] = []
var checks: int = 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var ground: Dictionary = {"id": 1, "kind": "unit", "spec": "tank", "team": 0, "pos": Vector2(1, 2), "hp": 10.0, "path": [Vector2(2, 2), Vector2(2, 4), Vector2(6, 4)], "commands": [{"kind": "move", "pos": Vector2(6, 4)}, {"kind": "attack_move", "pos": Vector2(9, 5)}, {"kind": "patrol", "pos": Vector2(9, 8)}]}
	var entities: Dictionary = {1: ground, 2: {"id": 2, "kind": "building", "pos": Vector2.ZERO, "hp": 10.0}}
	var enemy: Dictionary = ground.duplicate(true)
	enemy.id = 3
	enemy.team = 1
	entities[3] = enemy
	var rules: Dictionary = {"units": {"tank": {"domain": "ground"}}}
	var before: Dictionary = entities.duplicate(true)
	var routes: Array[Dictionary] = PATHS.selected_routes(entities, [1, 2, 999], rules)
	check(routes.size() == 3 and routes[0].points == PackedVector2Array([ground.pos, Vector2(2, 2), Vector2(2, 4), Vector2(6, 4)]), "selected remaining path retains actual obstacle detour")
	check(routes[1].points == PackedVector2Array([Vector2(6, 4), Vector2(9, 5)]) and not routes[1].planned and routes[1].kind == "attack_move", "appended attack movement is a separate unplanned intent leg")
	check(routes[2].kind == "patrol" and routes[2].points[0] == Vector2(9, 5), "queued patrol legs preserve command order")
	check(entities == before, "reading selected paths does not change positions, path or commands")
	check(PATHS.selected_routes(entities, [], rules).is_empty(), "deselection immediately removes all routes")
	check(PATHS.selected_routes(entities, [3], rules).is_empty(), "inspecting a hostile unit cannot reveal its navigation or queued orders")
	check(PATHS.selected_routes(entities, [1, 3], rules).size() == 3, "mixed selection exposes only the viewing team's routes")
	ground.path = [Vector2(3, 2), Vector2(6, 4)]
	check(PATHS.selected_routes(entities, [1], rules)[0].points[1] == Vector2(3, 2), "replanned navigation replaces the displayed detour")
	ground.transport_id = 4
	check(PATHS.selected_routes(entities, [1], rules).is_empty(), "embarked units have no independently visible route")
	ground.erase("transport_id")
	ground.path = []
	ground.commands = [{"kind": "move", "pos": Vector2(8, 8)}]
	check(PATHS.selected_routes(entities, [1], rules).is_empty(), "ground unit awaiting planning does not invent a direct route")
	var aircraft: Dictionary = ground.duplicate(true)
	aircraft.path = [Vector2(50, 50)]
	aircraft.commands = [{"kind": "attack_move", "pos": Vector2(8, 8)}, {"kind": "patrol", "pos": Vector2(2, 2)}, {"kind": "patrol", "pos": Vector2(8, 8)}]
	var air_routes: Array[Dictionary] = PATHS.entity_routes(aircraft, {"domain": "air"}, entities)
	check(air_routes.size() == 3 and air_routes[0].points == PackedVector2Array([aircraft.pos, Vector2(8, 8)]) and air_routes[0].air, "aircraft attack movement ignores ground navigation and uses its direct destination")
	check(air_routes[1].kind == "patrol" and air_routes[2].points[1] == Vector2(8, 8), "aircraft patrol retains both loop destinations")
	aircraft.flight_state = "returning"
	aircraft.home_airfield = 2
	aircraft.service_goal = Vector2(3, 3)
	air_routes = PATHS.entity_routes(aircraft, {"domain": "air"}, entities)
	check(air_routes[0].kind == "return" and air_routes[0].points[1] == Vector2(3, 3), "returning aircraft displays its actual apron service destination")
	check(air_routes.size() == 4 and not air_routes[1].planned and air_routes[1].kind == "attack_move", "flight orders waiting for service remain queued after the return leg")
	aircraft.flight_state = "rearming"
	air_routes = PATHS.entity_routes(aircraft, {"domain": "air"}, entities)
	check(air_routes.size() == 3 and not air_routes[0].planned and air_routes[0].points[0] == aircraft.pos, "aircraft being repaired displays every waiting flight order as queued intent")
	aircraft.flight_state = "airborne"
	aircraft.commands = [{"kind": "land", "pos": Vector2(3, 2)}, {"kind": "unload_move", "pos": Vector2(3, 3)}]
	air_routes = PATHS.entity_routes(aircraft, {"domain": "air"}, entities)
	check(air_routes.size() == 2 and air_routes[0].kind == "land" and air_routes[1].kind == "unload_move", "transport landing and deferred unloading destinations are displayed")
	var terrain: Dictionary = {"size": 4, "terrain": [[0,0,0,0],[0,0,0,0],[0,0,0,0],[0,0,0,0]], "heights": [[0,0,0,0],[0,2,2,0],[0,2,2,0],[0,0,0,0]]}
	var world_points: PackedVector3Array = PATHS.ground_points(PackedVector2Array([Vector2(.5, 1.5), Vector2(3.5, 1.5)]), terrain)
	var elevated: bool = false
	for point in world_points:
		if point.y > 2.0: elevated = true
	check(world_points.size() > 4 and elevated, "long smoothed legs sample intermediate terrain heights")
	var dashes: Array[PackedVector2Array] = PATHS.dashed_segments(PackedVector2Array([Vector2.ZERO, Vector2(6,0), Vector2(20,0)]), 8, 5)
	check(dashes.size() == 3 and dashes[1][1] == Vector2(8,0) and dashes[2][0] == Vector2(13,0), "dash phase continues across route vertices")
	var sim := WarSimulation.new()
	sim.entities = entities
	sim.rules = rules
	sim.map = terrain
	var overlay := OVERLAY.new()
	root.add_child(overlay)
	overlay.position = Vector2(40, 30)
	var projector := Projector.new()
	root.add_child(projector)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(2, 10, 10)
	camera.look_at(Vector3(2, 0, 2))
	overlay.projector = projector
	overlay.camera = camera
	overlay.sim = sim
	overlay.selection = [1]
	ground.path = [Vector2(3, 2)]
	overlay.refresh_overlay()
	check(not overlay._selected_routes.is_empty(), "overlay reads the explicit current selection")
	var sections: Array[PackedVector2Array] = overlay.projected_route_sections(PATHS.ground_points(overlay._selected_routes[0].points, terrain))
	check(not sections.is_empty() and sections[0][0] == Vector2(10, 40) and not projector.projected.is_empty(), "overlay uses the battlefield projector and converts client coordinates to its local rect")
	check(overlay.projected_route_sections(PackedVector3Array([Vector3(0,0,50),Vector3(1,0,50)])).is_empty(), "routes entirely behind the camera cannot create invalid screen lines")
	overlay.selection = []
	overlay.refresh_overlay()
	check(overlay._selected_routes.is_empty(), "overlay clears its cached routes on deselection")
	overlay.queue_free()
	projector.queue_free()
	camera.queue_free()
	await process_frame
	print("SELECTION_PATHS ", JSON.stringify({"checks": checks, "failures": failures}))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
