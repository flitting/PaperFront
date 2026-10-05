extends SceneTree
const MAP = preload("res://scripts/map_data.gd")
const CATALOG = preload("res://scripts/battlefield_catalog.gd")
const MODELS = preload("res://scripts/city_environment_models.gd")
const CITY = preload("res://scripts/city_layout.gd")
var checks: int = 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func _initialize() -> void:
	for mode: String in CATALOG.MODES:
		for players: int in [2, 3, 4]:
			for seed: int in [7, -93]:
				var started: int = Time.get_ticks_msec()
				var map: Dictionary = MAP.generate(mode, seed, {"players": players})
				check(map.valid, "%s/%d/%d validates %s" % [mode, players, seed, str(map.validation_errors)])
				check(map.size == 320 and map.starts.size() == players, "all actual spawns belong to selected participant count")
				check(map.profile.layout == ("triangle" if players == 3 else "opposed" if players == 2 else "quadrilateral"), "participant-specific topology")
				check(map.mines.size() == players * 5, "two near, two expansion and one contested deposit per participant")
				for harbor: Dictionary in map.harbors:
					check(MAP.terrain_at(map, harbor.water_pos) == MAP.WATER and MAP.water_surface_y(map, harbor.water_pos) == -2.65, "harbour launches onto authoritative sea surface")
					check(is_equal_approx(MAP.height_at(map, harbor.shore_pos), -2.4), "beach meets sea with a 25cm final step")
				check(map.ruins.all(func(r): return MAP.terrain_at(map, r.pos) in [MAP.LAND, MAP.ROAD]), "all neutral scenery occupies usable terrain")
				if mode == "islands": check(map.profile.water_fraction >= .60 and map.profile.water_fraction <= .70, "archipelago approximately65 percent connected water")
				if mode in ["city", "random_city"]:
					check(map.ruins.size() >= 90 and map.environment_props.size() >= 50 and map.civilians.size() >= 10, "city contains solid buildings, lamps, benches and moving pedestrians")
					var person: Dictionary = map.civilians[0] if not map.civilians.is_empty() else {"route": [Vector2.ZERO, Vector2.ONE], "speed": 1.0, "phase": 0.0}
					check(CITY.civilian_sample(person, 0).pos != CITY.civilian_sample(person, 4).pos, "neutral pedestrians really travel streets")
					check(map.ruins.all(func(r): return r.kind != "pedestrian"), "pedestrians do not block army navigation")
				print("PROFILE %s/%d seed%d: %d neutral, %d props, %.3f sea, %dms" % [mode, players, seed, map.ruins.size(), map.environment_props.size(), map.profile.water_fraction, Time.get_ticks_msec() - started])
		var first: Dictionary = MAP.generate(mode, 731, {"players": 3})
		check(first == MAP.generate(mode, 731, {"players": 3}), mode + " generation is deterministic")
		if mode == "random_city": check(first != MAP.generate(mode, 732, {"players": 3}), "seed city changes districts and architecture")
	for archetype: String in ["cottage", "townhouse", "shop", "warehouse"]:
		var models: Dictionary = MODELS.meshes(archetype, 5.1, 1)
		check(models.intact.surface_get_array_len(0) > 4000, "architecture retains complete window and roof geometry: " + archetype)
		check(models.intact.get_aabb().size.y > 5.9, "roof equipment is real volume")
		check(models.intact.get_meta("environment_details").window_frames >= 12, "actual facade frames exist")
		check(models.intact == MODELS.meshes(archetype, 5.1, 1).intact, "architecture reuses exact cached resources")
	for kind: String in ["streetlamp", "bench", "pedestrian", "cactus", "snow_pine", "palm"]:
		var mesh: ArrayMesh = MODELS.prop_mesh(kind)
		check(mesh.get_aabb().size.y > .4 and mesh.surface_get_array_len(0) > 150, "full volumetric environmental prop: " + kind)
	check(MAP.generate("dev", 7).valid and MAP.generate("handmade", 7).valid, "legacy strict maps remain valid")
	var fixture: Dictionary = MAP.generate("islands", 7, {"players": 3})
	var bad: Dictionary = fixture.duplicate(true)
	bad.starts.pop_back()
	check(not MAP.validate(bad).is_empty(), "validator rejects missing actual third spawn")
	bad = fixture.duplicate(true)
	bad.mines[0].capacity = 1.0
	check(not MAP.validate(bad).is_empty(), "validator rejects economic asymmetry")
	bad = fixture.duplicate(true)
	bad.mines[0].pos = [-1, 320]
	check(not MAP.validate(bad).is_empty(), "validator rejects out of bounds resources without crashing")
	bad = fixture.duplicate(true)
	bad.heights[0][0] = 1.0
	check(not MAP.validate(bad).is_empty(), "validator rejects inconsistent connected sea surface")
	bad = fixture.duplicate(true)
	bad.ruins[0].id = 99999
	check(not MAP.validate(bad).is_empty(), "validator rejects sparse neutral IDs")
	print("Battlefield profile checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
