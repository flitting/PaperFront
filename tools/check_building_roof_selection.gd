extends SceneTree

## Probe real game picking at visible, substantial upward body triangles.
## Run: godot --headless --path . --script res://tools/check_building_roof_selection.gd
## This deliberately does not alter the picking implementation or rules.
const OUTPUT_DIR := "res://artifacts/building_repair/interaction"
const ARTS := ["hq", "factory", "tech", "command", "airfield"]
var game: Node3D
var records: Array[Dictionary] = []
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func find_fixture(size: float) -> Vector2:
	var half: float = size * .5
	for z: int in range(32, 45):
		for x: int in range(7, 40):
			var pos := Vector2(roundf(float(x) - half) + half, roundf(float(z) - half) + half)
			var valid: bool = true
			for dz: int in range(-3, 4):
				for dx: int in range(-3, 4):
					var sample := pos + Vector2(dx, dz)
					if MapData.terrain_at(game.sim.map, sample) not in [MapData.LAND, MapData.ROAD] or absf(MapData.height_at(game.sim.map, sample)) > .01:
						valid = false
			for entity: Dictionary in game.sim.entities.values():
				if entity.pos.distance_to(pos) < 7.0: valid = false
			for ruin: Dictionary in game.sim.ruins:
				if ruin.pos.distance_to(pos) < 4.5: valid = false
			if valid: return pos
	return Vector2.INF

func body_triangles(model: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var instance: Variant = model.volume.meshes[0]
	var mesh: ArrayMesh = instance.mesh
	for surface: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null: indices = arrays[Mesh.ARRAY_INDEX]
		var count: int = indices.size() if not indices.is_empty() else vertices.size()
		for i: int in range(0, count - 2, 3):
			var points: Array[Vector3] = []
			for j: int in range(3):
				points.append(instance.global_transform * vertices[indices[i + j] if not indices.is_empty() else i + j])
			var cross_product: Vector3 = (points[1] - points[0]).cross(points[2] - points[0])
			var area: float = cross_product.length() * .5
			if area < .000001: continue
			var normal: Vector3 = -cross_product.normalized()
			var center: Vector3 = (points[0] + points[1] + points[2]) / 3.0
			result.append({"points": points, "center": center, "normal": normal, "area": area})
	return result

func is_visible(center: Vector3, triangles: Array[Dictionary]) -> bool:
	var origin: Vector3 = game.camera.global_position
	var ray_end: Vector3 = center - (center - origin).normalized() * .005
	for triangle: Dictionary in triangles:
		var points: Array = triangle.points
		if Geometry3D.segment_intersects_triangle(origin, ray_end, points[0], points[1], points[2]) != null:
			return false
	return true

func sample_roofs(id: int, faction: String, art: String, zoom: float, dome_supplement: bool = false) -> void:
	var entity: Dictionary = game.sim.entities[id]
	var triangles: Array[Dictionary] = body_triangles(game.world.models[id])
	var candidates: Array[Dictionary] = []
	for triangle: Dictionary in triangles:
		if triangle.normal.y > .45 and triangle.area > (.005 if dome_supplement else .3) and triangle.center.y > .8:
			candidates.append(triangle)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(a.center.y, b.center.y): return a.center.y > b.center.y
		return a.area > b.area)
	var sampled: Array[Vector3] = []
	for triangle: Dictionary in candidates:
		var center: Vector3 = triangle.center
		if not is_visible(center, triangles): continue
		var duplicate: bool = false
		for prior: Vector3 in sampled:
			if prior.distance_to(center) < .2: duplicate = true
		if duplicate: continue
		var screen: Vector2 = game.project_world_to_screen(center)
		var selected_id: int = game.pick_entity(screen)
		var ground: Vector2 = game.ground_at(screen)
		var fixed_center: Vector2 = game.project_world_to_screen(game.entity_visual_center(entity))
		var passed: bool = selected_id == id
		var record := {
			"faction": faction, "art": art, "building_id": id, "camera_distance": zoom,
			"strict_area_threshold_met": triangle.area > .3, "dome_supplement": dome_supplement,
			"roof_height": center.y, "roof_area": triangle.area,
			"roof_normal": [triangle.normal.x, triangle.normal.y, triangle.normal.z],
			"world_center": [center.x, center.y, center.z], "screen": [screen.x, screen.y],
			"ground_at_screen": [ground.x, ground.y], "ground_distance_to_entity": ground.distance_to(entity.pos),
			"fixed_center_screen_distance": fixed_center.distance_to(screen),
			"selected_id": selected_id, "passed": passed,
		}
		records.append(record)
		print("ROOF_PICK_SAMPLE ", JSON.stringify(record))
		if not passed: failures.append("%s_%s distance=%.0f roof=%.2f picked=%d expected=%d" % [faction, art, zoom, center.y, selected_id, id])
		sampled.append(center)
		if sampled.size() >= 3: break
	if sampled.is_empty() and not dome_supplement:
		print("ROOF_PICK_DOME_SUPPLEMENT ", faction, "_", art, " distance=", zoom, " no visible area>.3; visibly tessellated roof faces tested separately")
		sample_roofs(id, faction, art, zoom, true)
	elif sampled.is_empty(): failures.append("%s_%s distance=%.0f has no visible upward roof triangle" % [faction, art, zoom])

func run() -> void:
	root.size = Vector2i(1600, 900)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.audio.muted = true
	game.start_match("dev", 73026, "kestrel", true)
	game.set_process(false)
	game.set_physics_process(false)
	game.hud.show_menu(false)
	for i: int in range(4): await process_frame
	var fixture: Vector2 = find_fixture(5.0)
	if not fixture.is_finite():
		failures.append("No clear dev south plain fixture")
		finish()
		return
	for faction: String in ["kestrel", "rivet"]:
		for art: String in ARTS:
			var id: int = game.sim.debug_spawn(0, faction + "_" + art, fixture)
			if id < 0:
				failures.append("Cannot spawn " + faction + "_" + art)
				continue
			var entity: Dictionary = game.sim.entities[id]
			entity.gift_pending = false
			game.focus = entity.pos
			game.camera_pitch = 30.0
			game.yaw = .3
			for zoom: float in [25.0, 44.0]:
				game.distance = zoom
				game.update_camera()
				game.world.sync(0.0, [], {})
				for frame: int in range(2): await process_frame
				sample_roofs(id, faction, art, zoom)
			game.world.models[id].root.queue_free()
			game.world.models.erase(id)
			game.sim.entities.erase(id)
	finish()

func finish() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var report := {
		"method": "Real main.pick_entity at visible upward body triangles area>.3; explicitly flagged tessellated-dome supplement if no strict sample exists; no changes to picking or rules",
		"pitch": 30.0, "yaw": .3, "distances": [25.0, 44.0],
		"checks": records.size(), "passed": records.filter(func(record: Dictionary) -> bool: return record.passed).size(),
		"failures": failures, "samples": records,
		"building_source_sha256": FileAccess.get_file_as_string("res://scripts/faction_building_models.gd").sha256_text(),
		"main_source_sha256": FileAccess.get_file_as_string("res://scripts/main.gd").sha256_text(),
	}
	var file := FileAccess.open(OUTPUT_DIR + "/roof_selection.json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t"))
	print("ROOF_PICK_PROBE ", JSON.stringify({"checks": report.checks, "passed": report.passed, "failures": failures}))
	game.quit_game(0 if failures.is_empty() else 1)
