extends SceneTree

## Reproducible rendered 320-map pressure fixture, never a normal opening.
## Run: godot --path . --script res://tools/profile_expansion_runtime.gd -- --map forest --output res://artifacts/expansion_v5/runtime/performance_forest.json
## This uses the real main scene, normal rule catalog, AI, and native simulator.
var game: Node
var mode: String = "forest"
var output: String = "user://expansion_performance.json"
var screenshot: String = ""
var frame_times: Array[float] = []
var previous_us: int = 0
var begin_us: int = 0
var measurement_begin_us: int = 0
var finish_pending: bool = false
var initial_counts: Vector2i = Vector2i.ZERO
var active_min: int = 100000
var active_max: int = 0
var visible_min: int = 100000
var visible_max: int = 0
var initial_teams: Array[Dictionary] = []
var minimum_entities: int = 100000
var maximum_entities: int = 0
var failures: Array[String] = []
var source_hashes: Dictionary = {}
var unit_state_ranges: Dictionary = {}
const VOLUME_MODELS=preload("res://scripts/volume_models.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()-1):
		if args[i] == "--map": mode = args[i+1]
		elif args[i] == "--output": output = args[i+1]
		elif args[i] == "--screenshot": screenshot = args[i+1]
	if DisplayServer.get_name() == "headless" or mode not in ["forest","city","islands"]:
		push_error("Expansion GPU probe requires a real display and forest/city/islands")
		quit(2)
		return
	for path: String in ["res://scripts/main.gd","res://scripts/simulation.gd","res://scripts/paper_world.gd","res://scripts/landscape.gd","res://scripts/battlefield_catalog.gd","res://data/rules.json","res://assets/native/libpaper_front_kernels.so","res://tools/profile_expansion_runtime.gd"]:
		if FileAccess.file_exists(path): source_hashes[path] = FileAccess.get_sha256(path)
	root.mode = Window.MODE_WINDOWED
	root.unresizable = true
	root.size = Vector2i(1920,1080)
	root.position = Vector2i.ZERO
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	var slots: Array = []
	var faction_ids: Array[String] = ["kestrel","rivet","iron","sky"]
	var default_factions: Array[String] = []
	var default_hqs: Array[Vector2] = []
	for team in range(4): slots.append({"faction":faction_ids[team],"control":"human" if team == 0 else "ai","difficulty":"normal"})
	if not game.start_match(mode, 73026, "kestrel", true, {}, default_factions, default_hqs, {"players":4,"slots":slots}):
		quit(2)
		return
	game.hud.show_entry(false)
	game.hud.show_menu(false)
	game.audio.muted = true
	game.set_render_scale(1.0)
	game.dof_override = -1
	game.set_graphics_quality("balanced")
	game.resize_battlefield()
	game.pve_paused = true
	populate_fixture()
	game.focus = Vector2(game.sim.map.starts[0][0],game.sim.map.starts[0][1]) + Vector2(13,13)
	game.camera_pitch = 34.0
	game.yaw = .12
	game.distance = 85.0
	game.update_camera()
	game.world.sync(0.0, [], {})
	for team in range(4):
		var counts: Vector2i = game.sim.counts(team)
		initial_counts += counts
		initial_teams.append({"team":team,"faction":game.sim.factions[team],"units":counts.x,"buildings":counts.y,"control":game.sim.match_options.slots[team].control,"difficulty":game.sim.match_options.slots[team].difficulty})
	if initial_counts.x != 128: failures.append("fixture did not contain exactly 128 units")
	if not game.sim.ai_enabled: failures.append("AI was disabled")
	if game.render_scale != 1.0 or game.graphics_quality != "balanced": failures.append("incorrect quality settings")
	if not game.environment.ssao_enabled or not game.lens.dof_blur_near_enabled or not game.lens.dof_blur_far_enabled or game.battlefield_viewport.msaa_3d != Viewport.MSAA_2X: failures.append("balanced SSAO/DOF/MSAA defaults missing")
	if not failures.is_empty():
		for failure in failures: push_error(failure)
		quit(2)
		return
	game.benchmark = true # Only activates the existing main-scene telemetry.
	game.benchmark_seconds = 1000000.0
	game.benchmark_count = 128
	game.benchmark_tick_count = 0
	game.benchmark_elapsed = 0.0
	game.benchmark_previous_frame_us = 0
	game.benchmark_interval_sim_ms = 0.0
	game.benchmark_peak_entities = game.sim.entities.size()
	game.benchmark_events.clear()
	game.frame_samples.clear()
	game.cpu_samples.clear()
	game.world_cpu_samples.clear()
	game.process_samples.clear()
	game.render_cpu_samples.clear()
	game.gpu_samples.clear()
	RenderingServer.viewport_set_measure_render_time(game.get_viewport().get_viewport_rid(), true)
	RenderingServer.viewport_set_measure_render_time(game.battlefield_viewport.get_viewport_rid(), true)
	game.pve_paused = false
	begin_us = Time.get_ticks_usec()
	game.benchmark_started_us = begin_us
	previous_us = 0
	print("EXPANSION_PERFORMANCE_READY ", JSON.stringify({"map":mode,"size":game.sim.map.size,"teams":initial_teams,"fixture":"128 preplaced units, 24 buildings; normal AI/simulation; not normal opening","warmup_seconds":5,"measurement_seconds":30,"resolution":[1920,1080],"quality":"balanced","render_scale":1.0}))

func populate_fixture() -> void:
	for team in range(4):
		var base := Vector2(game.sim.map.starts[team][0],game.sim.map.starts[team][1])
		var faction: String = game.sim.factions[team]
		for i in range(5):
			var role: String = ["power","refinery","barracks","factory","airfield"][i]
			var spec: String = faction + "_" + role
			var info: Dictionary = game.sim.data_for(spec)
			var wanted: Vector2 = base + Vector2((i%3-1)*8,(i/3+1)*9)
			var position: Vector2 = game.sim._near_stand(wanted,float(info.size)*.72,-1,48.0)
			var id: int = game.sim.debug_spawn(team,spec,position) if position.is_finite() else -1
			if id > 0: game.sim.entities[id].gift_pending = false
			else: failures.append("cannot place support building " + spec)
		var fighters: Array[int] = []
		for i in range(32):
			var role: String = "rifle"
			if i % 4 == 0: role = "tank"
			elif i % 8 == 3: role = "anti"
			elif i >= 28: role = "harvester" if i < 30 else "engineer"
			var spec: String = faction + "_" + role
			var info: Dictionary = game.sim.data_for(spec)
			var wanted: Vector2 = base + Vector2((i%8-4)*2.0,-9-float(i/8)*2.1)
			var position: Vector2 = game.sim._near_stand(wanted,float(info.radius),-1,48.0)
			var id: int = game.sim.debug_spawn(team,spec,position) if position.is_finite() else -1
			if id < 1: failures.append("cannot place unit " + spec)
			elif role not in ["harvester","engineer"]: fighters.append(id)
		var next_start: Array = game.sim.map.starts[(team+1)%4]
		game.sim.issue(fighters,"attack_move",Vector2(next_start[0],next_start[1]))
	game.sim._rebuild_spatial()
	preload("res://scripts/team_vision.gd").refresh(game.sim)

func _process(_delta: float) -> bool:
	if begin_us == 0 or finish_pending: return false
	var now: int = Time.get_ticks_usec()
	var elapsed: float = float(now-begin_us)/1000000.0
	if elapsed >= 5.0:
		if measurement_begin_us == 0: measurement_begin_us = now
		if previous_us > 0: frame_times.append(float(now-previous_us)/1000.0)
		var active: int = 0
		var states: Dictionary = {}
		for entity in game.sim.entities.values():
			if entity.kind != "unit": continue
			if entity.state != "idle" or not entity.commands.is_empty(): active += 1
			states[entity.state] = int(states.get(entity.state,0)) + 1
		for state: String in states:
			var record: Dictionary = unit_state_ranges.get(state,{"minimum":100000,"maximum":0,"total":0,"sampled_frames":0})
			record.minimum = mini(record.minimum,states[state])
			record.maximum = maxi(record.maximum,states[state])
			record.total += states[state]
			record.sampled_frames += 1
			unit_state_ranges[state] = record
		active_min = mini(active_min,active)
		active_max = maxi(active_max,active)
		var visible: int = 0
		for model in game.world.models.values():
			if not model.get("view_culled",true): visible += 1
		visible_min = mini(visible_min,visible)
		visible_max = maxi(visible_max,visible)
		minimum_entities = mini(minimum_entities,game.sim.entities.size())
		maximum_entities = maxi(maximum_entities,game.sim.entities.size())
		previous_us = now
	if elapsed >= 35.0:
		finish_pending = true
		call_deferred("finish")
	return false

func stats(values: Array) -> Dictionary:
	if values.is_empty(): return {"samples":0,"mean":null,"p95":null,"p99":null,"maximum":null}
	var sorted: Array = values.duplicate()
	sorted.sort()
	var total: float = 0.0
	for value in values: total += float(value)
	return {"samples":values.size(),"mean":total/values.size(),"p95":sorted[mini(sorted.size()-1,floori(sorted.size()*.95))],"p99":sorted[mini(sorted.size()-1,floori(sorted.size()*.99))],"maximum":sorted.back()}

func finish() -> void:
	var elapsed: float = float(Time.get_ticks_usec()-begin_us)/1000000.0
	game.pve_paused = true
	game._flush_render_simulation()
	game.benchmark = false
	var timing: Dictionary = stats(frame_times)
	var frame_over_16: int = 0
	var frame_over_33: int = 0
	for ms in frame_times:
		if ms > 1000.0/60.0: frame_over_16 += 1
		if ms > 1000.0/30.0: frame_over_33 += 1
	var final_teams: Array[Dictionary] = []
	for team in range(4):
		var counts: Vector2i = game.sim.counts(team)
		final_teams.append({"team":team,"units":counts.x,"buildings":counts.y,"money":game.sim.money[team]})
	for state: String in unit_state_ranges:
		var record: Dictionary = unit_state_ranges[state]
		record.mean_units_per_total_frame = float(record.total)/maxi(1,frame_times.size())
		if record.sampled_frames < frame_times.size(): record.minimum = 0
	var authored_parts: int = 0
	var retained_parts: int = 0
	var retained_materials: int = 0
	var direct_skin_models: int = 0
	var direct_skin_vertices: int = 0
	for model in game.world.models.values():
		if not model.get("volumetric",false): continue
		if bool(model.get("direct_skinned",false)):
			direct_skin_models+=1
			var volume:Dictionary=model.volume
			var graphic:MeshInstance3D=volume.get("skinned_mesh")
			var skeleton:Skeleton3D=volume.get("skeleton")
			if graphic==null or graphic.mesh==null or graphic.skin==null or skeleton==null:
				failures.append("direct skin has missing live mesh/Skin/Skeleton")
				continue
			var recipe:Dictionary=VOLUME_MODELS._recipe(model.spec,"unit",int(model.team))
			authored_parts+=1
			if graphic.mesh==recipe.get("body_mesh"):retained_parts+=1
			var original_materials:bool=true
			for surface in range(graphic.mesh.get_surface_count()):
				direct_skin_vertices+=graphic.mesh.surface_get_array_len(surface)
				original_materials=original_materials and graphic.get_active_material(surface)==graphic.mesh.surface_get_material(surface)
			if original_materials:retained_materials+=1
			if graphic.get_node_or_null(graphic.skeleton)!=skeleton:failures.append("direct skin is bound to a different Skeleton")
			continue
		for part in model.render_parts:
			authored_parts += 1
			if part.batch.multi.mesh == part.node.mesh: retained_parts += 1
			if part.batch.node.material_override == part.node.material_override: retained_materials += 1
	if authored_parts != retained_parts or authored_parts != retained_materials: failures.append("authored model geometry/material retention failed")
	var report: Dictionary = {
		"schema":1,"scope":"real Vulkan GPU runtime pressure fixture","map":mode,"map_size":game.sim.map.size,"seed":73026,
		"fixture":"128 preplaced units and 24 completed buildings across four real starts; not a normal opening",
		"rules_mutated":false,"fixed_population_replenishment":false,"ai_enabled":game.sim.ai_enabled,"initial_teams":initial_teams,"final_teams":final_teams,
		"warmup_seconds":5.0,"requested_measurement_seconds":30.0,"actual_total_seconds":elapsed,"actual_measurement_seconds":float(Time.get_ticks_usec()-measurement_begin_us)/1000000.0,
		"fps_avg":1000.0/float(timing.mean),"frame_ms":timing,"frames_over_16_67_ms":frame_over_16,"frames_over_33_33_ms":frame_over_33,
		"simulation_cpu_ms":stats(game.cpu_samples),"world_cpu_ms":stats(game.world_cpu_samples),"engine_process_ms":stats(game.process_samples),"render_cpu_ms":stats(game.render_cpu_samples),"gpu_ms":stats(game.gpu_samples),
		"sample_count":frame_times.size(),"physics_ticks":game.benchmark_tick_count,"simulation_seconds":game.sim.time,"events":game.benchmark_events,
		"entities_min":minimum_entities,"entities_max":maximum_entities,"active_units_min":active_min,"active_units_max":active_max,"visible_models_min":visible_min,"visible_models_max":visible_max,
		"active_units_definition":"non-idle state or queued commands; waiting/pathfinding units included","unit_state_ranges":unit_state_ranges,
		"window_pixels":[root.size.x,root.size.y],"battlefield_pixels":[game.battlefield_viewport.size.x,game.battlefield_viewport.size.y],"render_scale":game.render_scale,"quality":game.graphics_quality,
		"full_authored_meshes":authored_parts == retained_parts,"materials_retained":authored_parts == retained_materials,"authored_parts_checked":authored_parts,"retained_mesh_parts":retained_parts,"retained_material_parts":retained_materials,"ssao_enabled":game.environment.ssao_enabled,"msaa_3d":game.battlefield_viewport.msaa_3d,"dof":MiniatureLens.metadata(game.lens),"shadow_enabled":game.key_light.shadow_enabled,"scenery":game.scenery_lod_metadata(),
		"direct_skin_models":direct_skin_models,"direct_skin_vertices":direct_skin_vertices,"direct_skin_rendering":"live original MeshInstance3D + Skin + private Skeleton; no Multimesh replacement",
		"camera":{"focus":[game.focus.x,game.focus.y],"distance":game.distance,"pitch":game.camera_pitch,"yaw":game.yaw},
		"native_simulation":game.sim.native_kernels_enabled,"native_render_batches":game.world.native_batches_enabled,"native_world_sync":game.world.native_world_sync_enabled,"simulation_render_overlap":game.render_overlap_enabled,
		"godot":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"display":DisplayServer.get_name(),"gpu_adapter":RenderingServer.get_video_adapter_name(),"processor":OS.get_processor_name(),"engine_process_frames":Engine.get_process_frames(),"engine_drawn_frames":Engine.get_frames_drawn(),
		"source_hashes_at_start":source_hashes,"capture_unix_seconds":Time.get_unix_time_from_system(),
		"draw_calls_last_frame":int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),"primitives_last_frame":int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),"failures":failures,"runtime_log_error_check":"external log review required"
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report,"  "))
	if not screenshot.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(screenshot.get_base_dir()))
		await RenderingServer.frame_post_draw
		game.get_viewport().get_texture().get_image().save_png(screenshot)
	print("EXPANSION_PERFORMANCE ",JSON.stringify(report))
	game.quit_game(0 if failures.is_empty() else 1)
