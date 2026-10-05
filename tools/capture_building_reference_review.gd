extends "res://tools/capture_faction_roster.gd"

const Probe = preload("res://tools/check_faction_buildings.gd")
const FIXED_VIEWPORT := Vector2i(1200, 900)
const FIXED_CAMERA_SIZE: float = 9.0
const PITCH: float = 30.0
const YAW: float = 22.0

func run() -> void:
	capture_viewport = SubViewport.new()
	capture_viewport.size = FIXED_VIEWPORT
	capture_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	capture_viewport.msaa_3d = Viewport.MSAA_2X
	root.add_child(capture_viewport)
	rules = RulesLoader.load_rules()
	output = "res://artifacts/building_repair/reference_review_v1"
	var arts: Array = ["hq", "factory", "repair"]
	if "--all" in OS.get_cmdline_user_args(): arts = Probe.Buildings.ARTS
	for phase: String in ["before", "after"]:
		if "--before-only" in OS.get_cmdline_user_args() and phase != "before": continue
		if "--after-only" in OS.get_cmdline_user_args() and phase != "after": continue
		var source_path: String = "res://artifacts/building_repair/before/faction_building_models.gd.txt" if phase == "before" else "res://scripts/faction_building_models.gd"
		# Compile a frozen copy so an authoring edit cannot alter a capture batch.
		var source: String = FileAccess.get_file_as_string(source_path)
		var builder := GDScript.new()
		builder.source_code = source
		if builder.reload() != OK: push_error("Capture builder failed to parse: " + source_path); quit(1); return
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output + "/" + phase))
		var manifest: Dictionary = {"source_sha256": source.sha256_text(), "source_path": source_path, "viewport": [FIXED_VIEWPORT.x, FIXED_VIEWPORT.y], "camera_projection": "orthogonal", "camera_vertical_world_span": FIXED_CAMERA_SIZE, "pitch": PITCH, "yaw": YAW, "building_position": [-1.4, 0.0, 0.0], "tank_position": [3.7, 0.0, .8], "paper_position": [2.8, 0.0, 2.7], "note": "Every building has identical camera and physical scale. Grid spacing 1 world unit. Reference art has no absolute metric calibration.", "models": {}}
		for faction: String in ["kestrel", "rivet"]:
			for art: String in arts:
				var id: String = faction + "_" + art
				var spec: Dictionary = rules.buildings[id]
				prepare(("正典军团" if faction == "kestrel" else "重锤军团") + " / " + str(spec.name) + (" · 修复前" if phase == "before" else " · 修复后"), 2, 1)
				# Titles live outside the rendered frame in the comparison compositor.
				for child in overlay.get_children(): child.queue_free()
				# Fixed angle and camera span across all 22 models and both versions.
				camera.size = FIXED_CAMERA_SIZE
				var target := Vector3(0.0, .55, .1)
				var pitch: float = deg_to_rad(PITCH)
				var yaw: float = deg_to_rad(YAW)
				camera.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * 14.0
				camera.look_at(target)
				add_grid()
				var mesh := VolumeModels.CraftMesh.new()
				var recipe: Dictionary = builder.make(mesh, faction, art, 0)
				add_recipe(recipe, Vector3(-1.4, 0, 0))
				add_footprint(float(spec.size), Vector3(-1.4, 0, 0))
				catalog_model(rules.units[faction + "_tank"], "unit", 0, Vector3(3.7, 0, .8), "当前坦克 / 原始世界尺寸")
				catalog_model(rules.units[faction + "_rifle"], "unit", 0, Vector3(2.8, 0, 2.7), "当前纸兵 / 原始世界尺寸")
				for record: Dictionary in labels: record.pos.z -= 1.3
				var image_path: String = output + "/" + phase + "/" + id + "_scale.png"
				if phase == "before" and FileAccess.file_exists(image_path):
					print("PRESERVED_BASELINE ", image_path)
				else: await finish(image_path)
				manifest.models[id] = Probe.measure_vertices(Probe.recipe_vertices(recipe), float(spec.size))
		var manifest_path: String = output + "/" + phase + "/scale_capture_manifest.json"
		var file := FileAccess.open(manifest_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(manifest, "\t"))
		file.close()
	await cleanup_capture()
	print("BUILDING_REFERENCE_REVIEW_CAPTURE ", ProjectSettings.globalize_path(output))
	quit()

func add_recipe(recipe: Dictionary, position: Vector3) -> void:
	var holder := Node3D.new()
	scene.add_child(holder)
	holder.position = position
	var body := MeshInstance3D.new()
	body.mesh = recipe.body_mesh
	holder.add_child(body)
	if recipe.has("turret_mesh"):
		var turret := MeshInstance3D.new()
		turret.mesh = recipe.turret_mesh
		turret.position = recipe.turret_pos
		holder.add_child(turret)

func add_grid() -> void:
	var grid := VolumeModels.CraftMesh.new()
	var grid_color := Color("bdaa89")
	for i in range(-7, 8):
		grid.box(Vector3(i, -.006, 0), Vector3(.014, .008, 11.0), grid_color, false)
	for i in range(-5, 6):
		grid.box(Vector3(0, -.006, i), Vector3(14.0, .008, .014), grid_color, false)
	var graphic := MeshInstance3D.new()
	graphic.mesh = grid.mesh()
	scene.add_child(graphic)

func add_footprint(size: float, position: Vector3) -> void:
	var outline := VolumeModels.CraftMesh.new()
	for side: float in [-1.0, 1.0]:
		outline.box(position + Vector3(side * size * .5, .018, 0), Vector3(.035, .015, size), Color("796345"), false)
		outline.box(position + Vector3(0, .018, side * size * .5), Vector3(size, .015, .035), Color("796345"), false)
	var graphic := MeshInstance3D.new()
	graphic.mesh = outline.mesh()
	scene.add_child(graphic)
