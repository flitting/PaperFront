extends SceneTree

## Opt-in renderer evidence. No simulation ticks, edited pixels, resized
## thumbnails, substituted materials, or gameplay camera changes are involved.
## --dry-run validates catalog coverage and actual submitted triangle counts
## headlessly. Omit it only when a real GPU/display has been assigned.
const OUTPOST = preload("res://scripts/outpost_construction.gd")
const FACTIONS: Array[String] = ["rivet", "kestrel", "iron", "sky"]
const TIER_NAMES: Array[String] = ["full", "far", "extreme"]
const WINDOW_SIZE := Vector2i(1920,1080)
const TILE_SIZE := Vector2i(144,112)
class ProbeLogger:
	extends Logger
	var faults: Array[Dictionary] = []
	var lock := Mutex.new()
	func _log_error(function_name: String, file_name: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		lock.lock()
		faults.append({"function":function_name,"file":file_name,"line":line,"code":code,"rationale":rationale,"type":error_type})
		lock.unlock()
	func snapshot() -> Array[Dictionary]:
		lock.lock()
		var result: Array[Dictionary] = faults.duplicate(true)
		lock.unlock()
		return result
var engine_logger: ProbeLogger
var game: Node
var world: PaperWorld
var sim: WarSimulation
var inspection: SubViewport
var camera: Camera3D
var floor_node: MeshInstance3D
var canvas: CanvasLayer
var sheet: Control
var entries: Array[Dictionary] = []
var records: Array[Dictionary] = []
var images: Array[Dictionary] = []
var errors: Array[String] = []
var output := "res://artifacts/wasd_camera_20261005/lod_visual"
var dry_run := false
var quick := false
var warmup := 2
var selected: Dictionary = {}

func _initialize() -> void:
	engine_logger = ProbeLogger.new()
	OS.add_logger(engine_logger)
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	dry_run = "--dry-run" in args
	quick = "--quick" in args
	for index: int in range(args.size()-1):
		if args[index] == "--output": output = args[index+1]
		elif args[index] == "--warmup": warmup = maxi(1,int(args[index+1]))
	if not dry_run and (DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "forward_plus"):
		push_error("LOD visual capture requires a real display and Forward+; --dry-run is CPU evidence only")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = WINDOW_SIZE
	root.content_scale_size = WINDOW_SIZE
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game._flush_render_simulation()
	game.audio.muted = true
	game.started = false
	game.hud.hide()
	game.overlay.hide()
	game.performance_overlay.hide()
	game.resize_battlefield()
	game.set_render_scale(1.0)
	game.set_graphics_quality("native")
	game.lens.dof_blur_near_enabled = false
	game.lens.dof_blur_far_enabled = false
	game.battlefield_display.hide()
	game.battlefield_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	world = game.world
	sim = game.sim
	sim.ai_enabled = false
	sim.time = 0.0
	sim.events.clear()
	sim.projectiles.clear()
	sim.entities.clear()
	sim._building_entities.clear()
	for row: Array in sim.map.heights: row.fill(0.0)
	for row: Array in sim.map.terrain: row.fill(MapData.LAND)
	for model: Dictionary in world.models.values(): model.root.free()
	world.models.clear()
	world.landscape.hide()
	world.elapsed = 0.0
	world.frame_delta = 0.0
	world.lod_enabled = true
	world._begin_batches()
	world._flush_batches()
	_make_preview()
	_make_catalog()
	if not _catalog_valid("initial catalog"):
		_write_manifest(true)
		quit(1)
		return
	if "--test-error-recorder" in args: _exercise_runtime_error()
	for entry: Dictionary in entries:
		var counts: Array[int] = []
		for tier: int in range(3): counts.append(_model_triangles(world.models[int(entry.id)],tier))
		records.append({"spec":entry.spec,"kind":entry.kind,"faction":entry.faction,"scaffold":entry.scaffold,
			"entity_id":entry.id,"triangles":counts,"far_fraction":float(counts[1])/maxi(1,counts[0]),
			"extreme_fraction":float(counts[2])/maxi(1,counts[0])})
	if dry_run:
		for entry: Dictionary in entries:
			var model: Dictionary = world.models[int(entry.id)]
			_prepare_tile(entry,64.0)
			for tier: int in range(3):
				_submit_only(entry,tier)
				if int(model.lod_tier) != tier: errors.append(str(entry.spec)+": forced tier was not submitted")
		await _scene_views()
		_catalog_valid("after representative scene submissions")
		_write_manifest(true)
		print("LOD_VISUAL_DRY_RUN ",JSON.stringify({"models":entries.size(),"catalog_units":sim.rules.units.size(),"catalog_buildings":sim.rules.buildings.size(),"scaffolds":4,"errors":errors,"engine_errors":engine_logger.snapshot()}))
	else:
		var catalog: Array[Dictionary] = _representatives() if quick else entries
		await _contact_sheets(catalog,64.0,TILE_SIZE,4,6,"catalog")
		await _contact_sheets(catalog,20.0,TILE_SIZE,4,6,"catalog")
		await _contact_sheets(_representatives(),160.0,Vector2i(256,208),2,4,"near")
		await _scene_views()
		_catalog_valid("after representative scene captures")
		var expected_images: int = ceili(float(catalog.size())/24.0)*2+ceili(float(_representatives().size())/8.0)+9
		if images.size() != expected_images: errors.append("incomplete image set: "+str(images.size())+"/"+str(expected_images))
		_write_manifest(true)
		print("LOD_VISUAL_CAPTURE ",JSON.stringify({"models":entries.size(),"images":images.size(),"output":ProjectSettings.globalize_path(output),"errors":errors,"engine_errors":engine_logger.snapshot()}))
	game.queue_free()
	inspection.queue_free()
	canvas.queue_free()
	await process_frame
	# Keep runtime faults visible in the exit code as well as the manifest. The
	# launcher must still reject parse errors and shutdown diagnostics in its log.
	var success: bool = errors.is_empty() and engine_logger.snapshot().is_empty()
	OS.remove_logger(engine_logger)
	quit(0 if success else 1)

func _exercise_runtime_error() -> void:
	# Diagnostic self-check: caller continues after a real GDScript fault, which
	# must result in an unsuccessful manifest and a nonzero process exit code.
	var missing: Dictionary = {}
	print(missing["intentional_logger_test"])

func _catalog_valid(context: String) -> bool:
	var valid := true
	var expected: int = sim.rules.units.size()+sim.rules.buildings.size()+FACTIONS.size()
	if entries.size() != expected:
		errors.append(context+": incomplete catalog count "+str(entries.size())+"/"+str(expected))
		valid = false
	for index: int in entries.size():
		var entry: Dictionary = entries[index]
		if not entry.has_all(["id","spec","kind","faction","scaffold"]):
			errors.append(context+": invalid entry "+str(index))
			valid = false
		elif not world.models.has(int(entry.id)) or not sim.entities.has(int(entry.id)):
			errors.append(context+": missing actual model/entity "+str(entry.spec))
			valid = false
	return valid

func _make_preview() -> void:
	inspection = SubViewport.new()
	inspection.name = "LodNativePixelPreview"
	inspection.size = TILE_SIZE
	inspection.world_3d = game.battlefield_viewport.world_3d
	inspection.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	inspection.msaa_3d = game.battlefield_viewport.msaa_3d
	inspection.screen_space_aa = game.battlefield_viewport.screen_space_aa
	inspection.use_taa = game.battlefield_viewport.use_taa
	inspection.mesh_lod_threshold = 0.0
	root.add_child(inspection)
	camera = Camera3D.new()
	camera.near = .2
	camera.far = 500.0
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	inspection.add_child(camera)
	camera.current = true
	world.camera = camera
	floor_node = MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(240,.1,240)
	floor_node.mesh = plane
	floor_node.position = Vector3(24,-.08,32)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("d5c7a6")
	paint.roughness = 1.0
	floor_node.material_override = paint
	game.add_child(floor_node)
	canvas = CanvasLayer.new()
	canvas.layer = 40
	root.add_child(canvas)

func _make_catalog() -> void:
	for faction: String in FACTIONS:
		for kind: String in ["unit","building"]:
			var catalog: Dictionary = sim.rules.units if kind == "unit" else sim.rules.buildings
			var keys: Array = catalog.keys()
			keys.sort()
			for spec_id: String in keys:
				if str(catalog[spec_id].faction) != faction: continue
				_add_entry(spec_id,kind,faction,false)
		_add_entry(faction+"_outpost","building",faction,true)

func _add_entry(spec_id: String, kind: String, faction: String, scaffold: bool) -> void:
	var id: int = sim._spawn(0,spec_id,Vector2(24,32),true)
	var entity: Dictionary = sim.entities[id]
	entity.pos = Vector2(24,32)
	entity.alpha = 25.0 if kind == "unit" else 0.0
	entity.turret_alpha = entity.alpha
	entity.visible_to = 3
	if str(sim.data_for(spec_id).get("domain","ground")) == "air":
		entity.flight_height = .35
		entity.airborne = false
		entity.flight_state = "landed"
	if str(sim.data_for(spec_id).get("art","")) == "harvester": entity.cargo = float(sim.rules.economy.harvester_capacity)*.5
	if scaffold:
		OUTPOST.initialize(sim,entity,-1)
		entity.construction.progress = .4
		entity.hp = OUTPOST.health_cap(sim,entity)
	var model: Dictionary = world._create_entity(entity)
	world.models[id] = model
	model.root.visible = false
	entries.append({"id":id,"spec":spec_id,"kind":kind,"faction":faction,"scaffold":scaffold})

func _representatives() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _catalog_valid("representative selection"): return result
	for faction: String in FACTIONS:
		for wanted: String in ["tank","fighter","rifle","naval_signature","hq","factory","scaffold"]:
			for entry: Dictionary in entries:
				if entry.faction != faction: continue
				var art: String = str(sim.data_for(entry.spec).art)
				if (wanted == "scaffold" and entry.scaffold) or (wanted != "scaffold" and not entry.scaffold and art == wanted):
					result.append(entry)
					break
	for entry: Dictionary in entries:
		if str(sim.data_for(entry.spec).art) == "creator_hand": result.append(entry)
	return result

func _prepare_tile(entry: Dictionary, pixels: float) -> void:
	if not selected.is_empty(): world.models[int(selected.id)].root.visible = false
	# Dictionary assignment aliases the original catalog row. Keep selection
	# private so clearing it can never erase required catalog fields.
	selected = entry.duplicate()
	var model: Dictionary = world.models[int(entry.id)]
	var entity: Dictionary = sim.entities[int(entry.id)]
	entity.pos = Vector2(24,32)
	# Ground and naval meshes use the same display datum. This is a geometry
	# comparison plate, not a claim about a playable shore or vessel navigation.
	model.terrain_height = 0.0
	model.last_terrain_pos = entity.pos
	model.last_pos = Vector2.INF
	model.fog_hidden = false
	model.view_culled = false
	model.root.visible = true
	var center := Vector3(24,float(entity.get("flight_height",0.0))+float(model.dimensions.y)*.5,32)
	var diameter: float = (model.dimensions as Vector2).length()
	camera.size = float(inspection.size.y)*diameter/pixels
	camera.position = center + Vector3(8,12,19).normalized()*60.0
	camera.look_at(center,Vector3.UP)
	world.camera_yaw = atan2(camera.global_basis.z.x,camera.global_basis.z.z)
	world._lod_view = ModelLod.view(camera)
	world._cache_view_planes()
	floor_node.position.y = -.08

func _submit_only(entry: Dictionary, tier: int) -> void:
	world.lod_override = tier
	world.elapsed = 0.0
	world.frame_delta = 0.0
	world._lod_counts.fill(0)
	world._begin_batches()
	world._sync_entity(world.models[int(entry.id)],sim.entities[int(entry.id)],false)
	world._flush_batches()

func _contact_sheets(source: Array[Dictionary], pixels: float, tile_size: Vector2i, columns: int, rows: int, prefix: String) -> void:
	inspection.size = tile_size
	var capacity: int = columns*rows
	for page: int in range(ceili(float(source.size())/capacity)):
		_new_sheet("%s · %.0f px projected model diameter · page %d" % [prefix,pixels,page+1])
		var first: int = page*capacity
		var last: int = mini(source.size(),first+capacity)
		var cell_width: float = 1840.0/columns
		var cell_height: float = 944.0/rows
		for index: int in range(first,last):
			var entry: Dictionary = source[index]
			var local: int = index-first
			var origin := Vector2(40+(local%columns)*cell_width,88+(local/columns)*cell_height)
			_label(str(entry.spec)+(" · scaffold 40%" if entry.scaffold else ""),origin,Vector2(cell_width-8,24),17)
			_prepare_tile(entry,pixels)
			for tier: int in range(3):
				_submit_only(entry,tier)
				await _warm_frames()
				var img: Image = inspection.get_texture().get_image()
				var texture := TextureRect.new()
				texture.texture = ImageTexture.create_from_image(img)
				texture.stretch_mode = TextureRect.STRETCH_KEEP
				texture.position = origin+Vector2(tier*(tile_size.x+6),25)
				texture.size = Vector2(tile_size)
				sheet.add_child(texture)
				_label("%s · %d tri" % [TIER_NAMES[tier],_model_triangles(world.models[int(entry.id)],tier)],texture.position+Vector2(4,3),Vector2(tile_size.x-8,18),12)
		var filename := "%s_%dpx_%02d.png" % [prefix,roundi(pixels),page+1]
		await _save_root(filename,{"mode":"contact_sheet","projected_diameter_pixels":pixels,"first":first,"last":last,"native_tile_pixels":[tile_size.x,tile_size.y]})
		print("LOD_VISUAL_PAGE ",filename," ",last,"/",source.size())
		_write_manifest(false)

func _scene_views() -> void:
	if is_instance_valid(sheet): sheet.queue_free()
	sheet = null
	inspection.render_target_update_mode = SubViewport.UPDATE_DISABLED
	world.camera = game.camera
	game.battlefield_display.show()
	game.battlefield_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	selected = {}
	var representatives := _representatives()
	if representatives.size() != 29:
		errors.append("representative scenes require all 29 models; found "+str(representatives.size()))
		return
	var positions: Dictionary = {}
	for index: int in range(representatives.size()):
		var entry: Dictionary = representatives[index]
		positions[int(entry.id)] = Vector2(18+(index%4)*24,14+(index/4)*13)
	for model: Dictionary in world.models.values(): model.root.visible = false
	for entry: Dictionary in representatives:
		var entity: Dictionary = sim.entities[int(entry.id)]
		var model: Dictionary = world.models[int(entry.id)]
		entity.pos = positions[int(entry.id)]
		model.last_terrain_pos = entity.pos
		model.last_pos = Vector2.INF
		model.terrain_height = 0.0
		model.root.visible = true
		model.fog_hidden = false
		model.view_culled = false
	for view: String in ["overview","middle","near"]:
		var target := Vector3(54,1,56) if view == "overview" else Vector3(54,1,40) if view == "middle" else Vector3(54,1,14)
		var distance: float = 185.0 if view == "overview" else 100.0 if view == "middle" else 60.0
		var direction := Vector3(.2,.7,1.0).normalized()
		game.camera.position = target+direction*distance
		game.camera.look_at(target,Vector3.UP)
		game.camera.fov = 42.0
		world.camera_yaw = atan2(game.camera.global_basis.z.x,game.camera.global_basis.z.z)
		world._lod_view = ModelLod.view(game.camera)
		world._cache_view_planes()
		for tier: int in range(3):
			world.lod_override = tier
			world._begin_batches()
			for entry: Dictionary in representatives: world._sync_entity(world.models[int(entry.id)],sim.entities[int(entry.id)],false)
			world._flush_batches()
			_new_sheet("",false)
			_label("Actual PaperWorld renderer · %s · forced %s · fixed pose/light/paint/shadows/MSAA" % [view,TIER_NAMES[tier]],Vector2(30,20),Vector2(1850,32),22)
			for entry: Dictionary in representatives:
				var model: Dictionary = world.models[int(entry.id)]
				var anchor: Vector3 = model.root.global_position+Vector3(0,-.15,2)
				if not game.camera.is_position_behind(anchor): _label(str(entry.spec),game.project_world_to_screen(anchor)-Vector2(75,0),Vector2(150,22),12)
			await _save_root("scene_%s_%s.png" % [view,TIER_NAMES[tier]],{"mode":"perspective_scene","view":view,"tier":tier,"representatives":representatives.size()})

func _new_sheet(title: String, background: bool = true) -> void:
	if is_instance_valid(sheet): sheet.free()
	sheet = Control.new()
	sheet.size = Vector2(WINDOW_SIZE)
	canvas.add_child(sheet)
	if background:
		var fill := ColorRect.new()
		fill.color = Color("f0e9d9")
		fill.size = Vector2(WINDOW_SIZE)
		sheet.add_child(fill)
		_label(title,Vector2(40,22),Vector2(1840,30),25)
		_label("Each row: FULL / FAR / EXTREME at matched original pixels. Simulation and visual clocks = 0; DOF off. No thumbnail resizing.",Vector2(40,55),Vector2(1840,24),17)

func _label(value: String, position: Vector2, dimensions: Vector2, font_size: int) -> void:
	var label := Label.new()
	label.text = value
	label.position = position
	label.size = dimensions
	label.clip_text = true
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",Color("32291f"))
	label.add_theme_color_override("font_shadow_color",Color("eee5d4"))
	label.add_theme_constant_override("shadow_offset_x",1)
	label.add_theme_constant_override("shadow_offset_y",1)
	sheet.add_child(label)

func _warm_frames() -> void:
	for frame: int in warmup: await process_frame
	await RenderingServer.frame_post_draw

func _save_root(filename: String, metadata: Dictionary) -> void:
	if dry_run: return
	await _warm_frames()
	var img: Image = root.get_texture().get_image()
	if img.get_size() != WINDOW_SIZE: errors.append(filename+": actual window image is not the requested 1920x1080")
	if root.get_visible_rect().size != Vector2(WINDOW_SIZE): errors.append(filename+": canvas scale is not 1:1; native pixel comparison invalid")
	metadata.camera_position = [world.camera.position.x,world.camera.position.y,world.camera.position.z]
	metadata.camera_rotation = [world.camera.rotation.x,world.camera.rotation.y,world.camera.rotation.z]
	metadata.camera_projection = world.camera.projection
	metadata.camera_fov = world.camera.fov
	var path: String = output.path_join(filename)
	var error: Error = img.save_png(path)
	if error != OK: errors.append(filename+": PNG save "+str(error))
	metadata.path = ProjectSettings.globalize_path(path)
	metadata.sha256 = FileAccess.get_sha256(path) if error == OK else ""
	metadata.width = img.get_width()
	metadata.height = img.get_height()
	images.append(metadata)

func _mesh_triangles(mesh: Mesh) -> int:
	var total := 0
	for surface: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var indices = arrays[Mesh.ARRAY_INDEX]
		total += (indices.size() if indices != null and indices.size() > 0 else arrays[Mesh.ARRAY_VERTEX].size())/3
	return total

func _model_triangles(model: Dictionary, tier: int) -> int:
	var count := 0
	if bool(model.get("direct_skinned",false)):
		for item: Dictionary in model.get("skinned_lods",[]): count += _mesh_triangles(item.meshes[tier])
	elif model.volumetric:
		for part: Dictionary in model.render_parts:
			count += _mesh_triangles(part.lod_batches[tier].multi.mesh)
			if part.has("ink_lod_batches"):
				count += _mesh_triangles(part.ink_lod_batches[tier].multi.mesh)
				count += _mesh_triangles(part.paper_lod_batches[tier].multi.mesh)
		for cargo: Array in model.get("cargo_lod_batches",[]): count += _mesh_triangles(cargo[tier].multi.mesh)
	else: count = _mesh_triangles(model.paper_lod_batches[tier].multi.mesh)
	return count

func _write_manifest(complete: bool) -> void:
	if not _catalog_valid("manifest catalog"):
		complete = false
	var hashes: Dictionary = {}
	for path: String in ["res://tools/lod_visual_probe.gd","res://scripts/paper_world.gd","res://scripts/model_lod.gd","res://scripts/volume_models.gd","res://scripts/naval_models.gd","res://scripts/iron_models.gd","res://scripts/sky_models.gd","res://scripts/creator_hand_models.gd","res://data/rules.json","res://assets/models/unit_lod_indices.res"]:
		if FileAccess.file_exists(path): hashes[path] = FileAccess.get_sha256(path)
	for entry: Dictionary in entries:
		if not entry.has("id") or not world.models.has(int(entry.id)): continue
		var model: Dictionary = world.models[int(entry.id)]
		if not model.volumetric:
			var path: String = world._texture_path(model.spec,"idle")
			if FileAccess.file_exists(path): hashes[path] = FileAccess.get_sha256(path)
	var faults: Array[Dictionary] = engine_logger.snapshot()
	var success: bool = errors.is_empty() and faults.is_empty()
	var manifest := {"complete":complete and success,"work_finished":complete,"passed":complete and success,"dry_run":dry_run,"quick":quick,"scope":"Actual PaperWorld single-model and representative-scene submissions; native renderer pixels copied 1:1 into a Godot label canvas; no FPS claim",
		"godot":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"window_pixels":[root.size.x,root.size.y],"logical_pixels":[root.get_visible_rect().size.x,root.get_visible_rect().size.y],
		"simulation_time":sim.time,"visual_time":world.elapsed,"dof":false,"msaa_3d":inspection.msaa_3d,"render_scale":1.0,"forced_tiers":[0,1,2],
		"catalog_count":entries.size(),"catalog_units":sim.rules.units.size(),"catalog_buildings":sim.rules.buildings.size(),"scaffolds":4,"triangle_scope":"body/skin/card plus ink/paper border and cargo resources; excludes shared floor, contact-shadow and health/progress bars",
		"models":records,"images":images,"errors":errors,"engine_errors":faults,"source_hashes":hashes}
	var file := FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE)
	if file == null:
		errors.append("cannot write manifest: "+output)
		return
	file.store_string(JSON.stringify(manifest,"  "))
	file.close()
