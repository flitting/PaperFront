extends SceneTree
const MODELS = preload("res://scripts/city_environment_models.gd")
func _initialize() -> void:
	var models: Array[ArrayMesh] = []
	for archetype: String in ["cottage", "townhouse", "shop", "warehouse"]:
		var height: float = 2.9 if archetype == "cottage" else 5.1 if archetype == "townhouse" else 5.9 if archetype == "shop" else 3.7
		for variant: int in 3:
			var recipe: Dictionary = MODELS.meshes(archetype, height, variant)
			models.append(recipe.intact)
			models.append(recipe.rubble)
	for item: Dictionary in [
		{"art":"old_townhouse", "height":5.1}, {"art":"old_shop", "height":5.1},
		{"art":"rowhouse", "height":5.1}, {"art":"terrace", "height":4.8},
		{"art":"modern_block", "height":9.5}, {"art":"modern_shop", "height":5.9},
		{"art":"office_tower", "height":17.0}, {"art":"office_tower", "height":20.0},
		{"art":"civic_hall", "height":10.5}, {"art":"church", "height":13.8},
		{"art":"clock_tower", "height":18.5}, {"art":"rail_station", "height":6.8},
		{"art":"freight_shed", "height":5.4}, {"art":"warehouse", "height":4.2},
	]:
		for variant: int in 3:
			var recipe: Dictionary = MODELS.meshes(item.art, item.height, variant)
			models.append(recipe.intact)
			models.append(recipe.rubble)
	for art: String in MODELS.LANDMARK_ART:
		if art in ["civic_hall", "church", "clock_tower", "rail_station"]: continue
		var height: float = 14.0 if art in ["ranger_tower", "bell_tower"] else 8.5 if art in ["mesa_spire", "moss_spire", "snow_spire"] else 6.5 if art == "stone_fort" else 6.0 if art in ["sawmill", "bazaar", "oasis_village", "freight_depot"] else 4.8 if art in ["fishing_hut", "boat_shed"] else 4.2 if art == "shipwreck" else 4.5
		for variant: int in 3:
			var recipe: Dictionary = MODELS.meshes(art, height, variant)
			models.append(recipe.intact)
			models.append(recipe.rubble)
	# Biome landmarks are lower than their city counterparts.
	for variant: int in 3:
		var recipe: Dictionary = MODELS.meshes("warehouse", 2.9, variant)
		models.append(recipe.intact)
		models.append(recipe.rubble)
	for kind: String in ["streetlamp", "bench", "pedestrian", "cactus", "snow_pine", "palm", "sidewalk", "fountain", "lighthouse", "harbor_crane", "cargo_stack", "rail_track", "log_stack", "market_tent", "fuel_tank", "birch", "moss_boulder", "sandstone", "snow_boulder", "ice_floe", "pier", "coastal_rock", "sea_rock", "buoy", "boat", "quay_wall", "waterfall"]:
		for variant: int in (1 if kind == "sidewalk" else 3): models.append(MODELS.prop_mesh(kind, variant))
	var failures: int = 0
	for mesh: ArrayMesh in models:
		var key: String = str(mesh.get_meta("environment_key"))
		var error: int = ResourceSaver.save(mesh, MODELS.resource_path(key), ResourceSaver.FLAG_COMPRESS)
		if error != OK: failures += 1
	print("ENVIRONMENT_BAKE %d exact meshes, %d failures" % [models.size(), failures])
	quit(0 if failures == 0 else 1)
