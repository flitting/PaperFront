extends Node
const PRESSURE_FACTIONS = preload("res://scripts/performance_factions.gd")

## Real rendered gameplay. Both cases keep the full simulation and current
## terrain, with the same fixture on any map size; no timer or entity throttling.
var game: Node
var options: Dictionary
var frame_times: Array[float] = []
var windows: Array[float] = []
var previous_us: int = 0
var start_us: int = 0
var window_us: int = 0
var window_frames: int = 0
var ending: bool = false
var initial_counts: Vector2i
var min_units: int = 1000000
var center: Vector2
var team_records: Array[Dictionary] = []
var quality_preset: String = "native"
var production_clock: float = 0.0
var reinforcement_spawns: int = 0
var reinforcement_air_spawns: int = 0
var reinforcement_building_spawns: int = 0
var reinforced_death_ids: Dictionary = {}
var world_stage_totals: Dictionary = {}
var world_stage_frames: int = 0
var reserve_samples: Array[float] = []
var measurement_sim_start: float = 0.0
var minimum_team_counts: Array[Vector3i] = [] # ground, air, buildings
var setup_ms: float = 0.0
var air_spec_ids: Dictionary = {}
var previous_tick_count:int=0
var previous_cpu_index:int=0
var previous_reserve_index:int=0
var frame_tick_histogram:Dictionary={}
var slow_frame_details:Array[Dictionary]=[]

func setup(owner_game: Node, config: Dictionary) -> void:
	var setup_started: int = Time.get_ticks_usec()
	game = owner_game
	options = config.duplicate()
	if DisplayServer.get_name() == "headless":
		push_error("Rendered performance acceptance requires a real display")
		game.quit_game(2)
		return
	var stress: bool = str(options.get("case", "normal")) == "stress"
	var size: Vector2i = options.get("resolution", Vector2i(1920, 1080))
	var fullscreen: bool = bool(options.get("fullscreen", false))
	if fullscreen: size = DisplayServer.screen_get_size(game.get_window().current_screen)
	game.get_window().mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
	game.get_window().unresizable = not fullscreen
	game.get_window().size = size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var mode: String = str(options.get("map", "mountains640"))
	if stress:
		var source_rules: Dictionary = RulesLoader.load_rules()
		if source_rules.is_empty():
			push_error("Performance fixture requires valid imported rules: "+"; ".join(RulesLoader.errors))
			game.quit_game(2)
			return
		var config_rules: Dictionary = preload("res://scripts/performance_factions.gd").make_rules(source_rules)
		var faction_ids: Array[String] = preload("res://scripts/performance_factions.gd").ids()
		var map_size: float = 640.0 if mode == "mountains640" else 320.0
		center = Vector2(map_size * 0.5, map_size * 0.55)
		var hqs: Array[Vector2] = []
		for team in range(8): hqs.append(center + Vector2.from_angle(float(team) * TAU / 8.0) * 70.0)
		if not game.start_match(mode, 73026, "rivet", true, config_rules, faction_ids, hqs):
			game.quit_game(2)
			return
	else:
		if not game.start_match(mode, 73026, "rivet"):
			game.quit_game(2)
			return
		center = Vector2(float(game.sim.map.size) * 0.5, float(game.sim.map.size) * 0.55)
	game.sim.ai_enabled = false
	for spec_id in game.sim.rules.units:
		if game.sim.rules.units[spec_id].get("domain", "ground") == "air": air_spec_ids[spec_id] = true
	for property in game.world.get_property_list():
		if str(property.name) == "profile_enabled": game.world.set("profile_enabled", true)
	for team in range(game.sim.factions.size()): game.sim.money[team] = 100000.0
	game.audio.muted = false
	AudioServer.set_bus_volume_db(0, -80.0)
	game.hud.show_menu(false)
	game.hud.show_entry(false)
	game.set_render_scale(float(options.get("render_scale", 1.0)))
	quality_preset = str(options.get("quality", "native"))
	game.dof_override = -1 # Reproducible benchmark settings, independent of user overrides.
	if game.has_method("set_graphics_quality"): game.set_graphics_quality(quality_preset)
	if game.world.landscape.has_method("configure_quality"): game.world.landscape.configure_quality(quality_preset)
	if game.world.has_method("configure_quality"): game.world.configure_quality(quality_preset)
	if stress: _populate_eight_factions()
	else: _populate_normal()
	game.focus = center
	game.distance = 120.0 if stress else 55.0
	game.camera_pitch = 34.0
	game.yaw = 0.12
	game.update_camera()
	game.benchmark = true
	game.benchmark_count = 800 if stress else 96
	game.benchmark_seconds = 1000000.0
	game.benchmark_started_us = Time.get_ticks_usec()
	game.benchmark_previous_frame_us = 0
	game.benchmark_tick_count = 0
	game.benchmark_events.clear()
	game.frame_samples.clear()
	game.cpu_samples.clear()
	game.world_cpu_samples.clear()
	game.process_samples.clear()
	game.render_cpu_samples.clear()
	game.gpu_samples.clear()
	game.get_viewport().gui_disable_input = true
	RenderingServer.viewport_set_measure_render_time(game.get_viewport().get_viewport_rid(), true)
	RenderingServer.viewport_set_measure_render_time(game.battlefield_viewport.get_viewport_rid(), true)
	initial_counts = Vector2i.ZERO
	team_records.clear()
	for team in range(game.sim.factions.size()):
		var counts: Vector2i = game.sim.counts(team)
		initial_counts += counts
		var air: int = 0
		for e in game.sim.entities.values():
			if int(e.team) == team and game.sim._is_air(e): air += 1
		team_records.append({"team": team, "faction": game.sim.factions[team], "art_template": PRESSURE_FACTIONS.art_template(team) if stress else game.sim.factions[team], "units": counts.x, "buildings": counts.y, "ground_units": counts.x - air, "air_units": air})
		minimum_team_counts.append(Vector3i(counts.x-air, air, counts.y))
	if stress and (initial_counts != Vector2i(800, 160) or team_records.any(func(item): return int(item.units) != 100 or int(item.buildings) != 20 or int(item.air_units) != 20)):
		push_error("Eight-faction stress fixture must contain exactly 100 units and 20 buildings per team, including 20 aircraft")
		game.quit_game(2)
		return
	if not stress and (initial_counts != Vector2i(96,24) or team_records.any(func(item): return item.air_units != 4)):
		push_error("Normal fixture requires 96 units, including 8 aircraft, and 24 buildings")
		game.quit_game(2)
		return
	setup_ms = (Time.get_ticks_usec()-setup_started)/1000.0
	start_us = Time.get_ticks_usec()
	print("PERFORMANCE_READY ", JSON.stringify({"case": options.get("case", "normal"), "map_size": game.sim.map.size, "units": initial_counts.x, "buildings": initial_counts.y, "teams": team_records, "resolution": size, "quality": quality_preset}))

func after_tick() -> void:
	if game == null or start_us == 0 or (options.get("case", "normal") != "stress" and not options.get("fixed_population", true)): return
	# Fixed population is part of the stress workload. Units take real damage,
	# die normally and leave their normal effects; the harness supplies reserves.
	# No health, weapon damage, simulation clocks or unit updates are skipped.
	for event in game.sim.events.duplicate():
		if event.get("kind") != "death": continue
		var death_id: int = int(event.get("id", -1))
		if reinforced_death_ids.has(death_id): continue
		var spec: String = str(event.get("spec", ""))
		var building: bool = game.sim.rules.buildings.has(spec)
		if not building and not game.sim.rules.units.has(spec): continue
		var team: int = int(event.team)
		var id: int = game.sim.debug_spawn(team, spec, event.pos)
		if id < 1 and not building:
			# A casualty may leave a completely blocked local pocket. Reserves
			# still need a legal new position; never overlap blockers or revive IDs.
			var info: Dictionary = game.sim.data_for(spec)
			var stand: Vector2 = game.sim._near_stand(event.pos, float(info.radius), -1, 24.0)
			if stand.is_finite(): id = game.sim.debug_spawn(team, spec, stand)
		if id < 1:
			push_error("Cannot legally replenish the fixed performance fixture: "+spec)
			game.quit_game(2)
			return
		reinforced_death_ids[death_id] = true
		if building:
			reinforcement_building_spawns += 1
			game.sim.entities[id].gift_pending = false
			continue
		reinforcement_spawns += 1
		if game.sim._is_air(game.sim.entities[id]): reinforcement_air_spawns += 1
		if not spec.ends_with("_harvester"):
			if options.get("case", "normal") == "stress":
				var next_angle: float = float((team + 1) % 8) * TAU / 8.0
				game.sim.issue([id], "attack_move", center + Vector2.from_angle(next_angle) * 32.0)
			else: game.sim.issue([id], "attack_move", center + Vector2(24.0 if team == 0 else -24.0, 0.0))

func _building(team: int, role: String, wanted: Vector2) -> int:
	var spec: String = game.sim.building_spec(team, role)
	var pos: Vector2 = game.sim._near_stand(wanted, float(game.sim.data_for(spec).size) * 0.72, -1, 24.0)
	if not pos.is_finite(): pos = wanted
	var id: int = game.sim.debug_spawn(team, spec, pos)
	if id > 0: game.sim.entities[id].gift_pending = false
	return id

func _unit(team: int, role: String, wanted: Vector2) -> int:
	var spec: String = game.sim.factions[team] + "_" + role
	var info: Dictionary = game.sim.data_for(spec)
	var pos: Vector2 = wanted if info.get("domain", "ground") == "air" else game.sim._near_stand(wanted, float(info.radius), -1, 24.0)
	if not pos.is_finite(): return -1
	return game.sim.debug_spawn(team, spec, pos)

func _populate_normal() -> void:
	for team in range(2):
		var side: float = -1.0 if team == 0 else 1.0
		var base: Vector2 = center + Vector2(side * 40.0, 14.0)
		var roles: Array[String] = ["power", "barracks", "factory", "refinery", "tower", "repair", "command", "airfield"]
		for i in range(11): _building(team, roles[i % roles.size()], base + Vector2(side * float(i % 4) * 6.0, float(i / 4) * 6.0))
		var attack_ids: Array[int] = []
		for i in range(48):
			var role: String = "rifle"
			if i % 5 == 0: role = "tank"
			elif i % 11 == 0: role = "harvester"
			elif i % 7 == 0: role = "anti"
			elif i % 13 == 0: role = "scout"
			if i >= 44: role = "fighter" if i < 46 else ("bomber" if team == 0 else "attacker")
			var id: int = _unit(team, role, center + Vector2(side * 24.0 + (float(i % 8) - 3.5) * 1.7, (float(i / 8) - 4.0) * 1.7))
			if id > 0 and role != "harvester": attack_ids.append(id)
		game.sim.issue(attack_ids, "attack_move", center + Vector2(-side * 24.0, 0.0))

func _populate_eight_factions() -> void:
	var roles: Array[String] = ["power", "power", "power", "power", "barracks", "barracks", "factory", "factory", "refinery", "tech", "command", "repair", "tower", "tower", "airfield", "airfield", "airfield", "airfield", "airfield"]
	var land_roles: Array[String] = ["tank", "anti", "rifle", "rifle", "aa", "rifle", "scout", "harvester", "rifle", "engineer"]
	for team in range(8):
		var angle: float = float(team) * TAU / 8.0
		var direction: Vector2 = Vector2.from_angle(angle)
		var base: Vector2 = center + direction * 70.0
		for i in range(roles.size()): _building(team, roles[i], base + Vector2((float(i % 5) - 2.0) * 6.0, float(i / 5) * 6.0 + 8.0).rotated(angle))
		var attack_ids: Array[int] = []
		for i in range(100):
			var role: String = land_roles[i % land_roles.size()] if i < 80 else "fighter"
			if i >= 80 and i % 5 >= 3:
				role = "bomber" if game.sim.rules.units.has(game.sim.factions[team] + "_bomber") else "attacker"
			var wanted: Vector2 = center + direction * 32.0 + Vector2((float(i % 10) - 4.5) * 1.7, (float(i / 10) - 4.5) * 1.7).rotated(angle)
			var id: int = _unit(team, role, wanted)
			if id > 0 and role != "harvester": attack_ids.append(id)
		var next_angle: float = float((team + 1) % 8) * TAU / 8.0
		game.sim.issue(attack_ids, "attack_move", center + Vector2.from_angle(next_angle) * 32.0)

func _maintain_production() -> void:
	var n: int = game.sim.factions.size()
	var ground: Array[int] = []
	var air: Array[int] = []
	var queued: Array[int] = []
	var queued_air: Array[int] = []
	for array in [ground, air, queued, queued_air]:
		array.resize(n)
		array.fill(0)
	for unit in game.sim.entities.values():
		if unit.kind != "unit": continue
		if game.sim._is_air(unit): air[int(unit.team)] += 1
		else: ground[int(unit.team)] += 1
	for building in game.sim._building_entities:
		var team: int = int(building.team)
		queued[team] += building.queue.size()
		for order in building.queue:
			if game.sim.data_for(order.spec).get("domain", "ground") == "air": queued_air[team] += 1
	for team in range(n):
		if ground[team] + air[team] + queued[team] >= (100 if options.get("case", "normal") == "stress" else 48): continue
		for building in game.sim._building_entities:
			if int(building.team) != team or not building.queue.is_empty(): continue
			var role: String = str(game.sim.data_for(building.spec).get("role", ""))
			if role == "airfield" and options.get("case", "normal") == "stress" and air[team] + queued_air[team] < 20:
				game.sim.produce(int(building.id), game.sim.factions[team] + "_fighter")
				break
			if ground[team] + queued[team] - queued_air[team] >= (80 if options.get("case", "normal") == "stress" else 44): continue
			if role == "barracks": game.sim.produce(int(building.id), game.sim.factions[team] + "_rifle")
			elif role == "factory": game.sim.produce(int(building.id), game.sim.factions[team] + "_tank")
			else: continue
			break

func _process(_delta: float) -> void:
	if game == null or start_us == 0 or ending: return
	production_clock += _delta
	if production_clock >= 0.5:
		production_clock = 0.0
		_maintain_production()
	var now: int = Time.get_ticks_usec()
	var elapsed: float = float(now - start_us) / 1000000.0
	var warmup: float = float(options.get("warmup", 8.0))
	if elapsed > warmup:
		if previous_us == 0:
			measurement_sim_start = game.sim.time
			window_us = now
			for samples in [game.cpu_samples, game.world_cpu_samples, game.render_cpu_samples, game.gpu_samples, game.reserve_tick_samples, game.frame_logic_samples]: samples.clear()
			previous_tick_count=game.benchmark_tick_count
			previous_cpu_index=0;previous_reserve_index=0
		else:
			var interval_ms:float=float(now-previous_us)/1000.0
			frame_times.append(interval_ms)
			var interval_ticks:int=game.benchmark_tick_count-previous_tick_count
			frame_tick_histogram[interval_ticks]=int(frame_tick_histogram.get(interval_ticks,0))+1
			var slow_threshold:float=1000.0/(30.0 if options.get("case","normal")=="stress" else 60.0)
			if interval_ms>slow_threshold and slow_frame_details.size()<200:
				var simulation_ms:float=0.0
				var replenishment_ms:float=0.0
				for index in range(previous_cpu_index,game.cpu_samples.size()):simulation_ms+=game.cpu_samples[index]
				for index in range(previous_reserve_index,game.reserve_tick_samples.size()):replenishment_ms+=game.reserve_tick_samples[index]
				slow_frame_details.append({"frame_ms":interval_ms,"simulation_ticks":interval_ticks,"simulation_cpu_sum_ms":simulation_ms,"reserve_cpu_sum_ms":replenishment_ms,"world_ms":game.world_cpu_ms,"frame_logic_ms":game.frame_logic_samples.back() if not game.frame_logic_samples.is_empty() else 0.0,"since_start_s":elapsed,"world_profile":game.world.profile_last.duplicate()})
			previous_tick_count=game.benchmark_tick_count
			previous_cpu_index=game.cpu_samples.size();previous_reserve_index=game.reserve_tick_samples.size()
			window_frames += 1
		if now - window_us >= 1000000:
			windows.append(float(window_frames) * 1000000.0 / float(now - window_us))
			window_us = now
			window_frames = 0
		var population: int = 0
		var counts: Array[Vector3i] = []
		counts.resize(team_records.size()); counts.fill(Vector3i.ZERO)
		for entity in game.sim.entities.values():
			var team: int = int(entity.team)
			if entity.kind == "unit":
				population += 1
				if air_spec_ids.has(entity.spec): counts[team].y += 1
				else: counts[team].x += 1
			else: counts[team].z += 1
		for team in range(counts.size()): minimum_team_counts[team] = minimum_team_counts[team].min(counts[team])
		min_units = mini(min_units, population)
		var profile: Variant = game.world.get("profile_last")
		if profile is Dictionary:
			world_stage_frames += 1
			for key in profile:
				if str(key).ends_with("_us"): world_stage_totals[key] = float(world_stage_totals.get(key, 0.0)) + float(profile[key])
		previous_us = now
		reserve_samples.append(float(game.reserve_cpu_ms))
	if elapsed >= warmup + float(options.get("seconds", 30.0)): _finish()

func _percentile(values: Array, fraction: float) -> float:
	if values.is_empty(): return 0.0
	var sorted: Array = values.duplicate()
	sorted.sort()
	return float(sorted[mini(sorted.size() - 1, int(sorted.size() * fraction))])

func _mean(values: Array) -> float:
	var total: float = 0.0
	for value in values: total += float(value)
	return total / maxi(1,values.size())

func _finish() -> void:
	ending = true
	var total: float = 0.0
	for value in frame_times: total += value
	var one_percent_ms: float = _percentile(frame_times, 0.99)
	var fps: float = 1000.0 * float(frame_times.size()) / maxf(total, 0.001)
	var minimum_second: float = windows.min() if not windows.is_empty() else 0.0
	var target: float = 30.0 if options.get("case", "normal") == "stress" else 60.0
	var activity: Dictionary = game.benchmark_events.duplicate()
	var stage_ms: Dictionary = {}
	for key in world_stage_totals: stage_ms[key] = float(world_stage_totals[key]) / float(maxi(1, world_stage_frames)) / 1000.0
	var result: Dictionary = {
		"report_version": 3, "godot": Engine.get_version_info().string,
		"fixture_version": PRESSURE_FACTIONS.FIXTURE_VERSION if options.get("case", "normal") == "stress" else "normal_fixed_population_v2",
		"native_simulation_kernels": game.sim.native_kernels_enabled and game.sim._kernels != null,
		"native_unit_dispatch": game.sim.native_kernels_enabled and game.sim.native_unit_dispatch_enabled and game.sim._kernels != null,
		"native_geometry_queries": game.sim.native_kernels_enabled and game.sim.native_geometry_enabled and game.sim._kernels != null,
		"native_ground_movement": game.sim.native_kernels_enabled and game.sim.native_geometry_enabled and game.sim.native_movement_enabled and game.sim._kernels != null,
		"simulation_render_overlap": game.render_overlap_enabled,
		"overlap_tick_count": game.overlap_tick_count,
		"overlap_wait_ms": game.overlap_wait_ms,
		"native_volume_poses": game.world.native_kernels_enabled and game.world._kernels != null,
		"native_world_sync": game.world.native_kernels_enabled and game.world.native_world_sync_enabled and game.world._kernels != null,
		"native_render_batches":game.world._uses_native_batches(),
		"native_bulk_buffers":game.world._uses_native_batches() and game.world.native_bulk_buffers_enabled,
		"case": options.get("case", "normal"), "map": game.sim.map.mode, "map_size": game.sim.map.size,
		"warmup_seconds": options.get("warmup", 8.0), "measurement_seconds": total / 1000.0,
		"resolution": game.get_window().size, "render_scale": game.render_scale,
		"output_pixels": [game.get_window().size.x, game.get_window().size.y], "window_mode": game.get_window().mode,
		"fullscreen": bool(options.get("fullscreen", false)), "screen_pixels": DisplayServer.screen_get_size(game.get_window().current_screen),
		"internal_3d_pixels": Vector2i(Vector2(game.battlefield_viewport.size) * game.render_scale),
		"internal_3d_size": [int(game.battlefield_viewport.size.x * game.render_scale), int(game.battlefield_viewport.size.y * game.render_scale)],
		"initial_units": initial_counts.x, "initial_buildings": initial_counts.y, "minimum_measured_units": min_units,
		"faction_count": team_records.size(), "teams": team_records, "quality_preset": quality_preset,
		"fixed_stress_population": options.get("case", "normal") == "stress", "benchmark_reserve_spawns": reinforcement_spawns, "benchmark_air_reserve_spawns": reinforcement_air_spawns,
		"benchmark_building_reserve_spawns": reinforcement_building_spawns,
		"dof_enabled": game.lens.dof_blur_far_enabled,
		"msaa": game.battlefield_viewport.msaa_3d, "screen_space_aa": game.battlefield_viewport.screen_space_aa,
		"mean_fps": fps, "minimum_one_second_fps": minimum_second,
		"p99_fps": 1000.0 / maxf(one_percent_ms, 0.001), "frame_p95_ms": _percentile(frame_times, 0.95), "frame_p99_ms": one_percent_ms,
		"maximum_frame_ms": frame_times.max() if not frame_times.is_empty() else 0.0,
		"simulation_p95_ms": _percentile(game.cpu_samples, 0.95), "world_sync_p95_ms": _percentile(game.world_cpu_samples, 0.95),
		"reserve_p95_ms": _percentile(game.reserve_tick_samples, 0.95),
		"simulation_mean_ms": _mean(game.cpu_samples), "reserve_mean_ms": _mean(game.reserve_tick_samples),
		"world_sync_mean_ms": _mean(game.world_cpu_samples),
		"frame_logic_mean_ms": _mean(game.frame_logic_samples), "frame_logic_p95_ms": _percentile(game.frame_logic_samples,.95),
		"render_cpu_mean_ms": _mean(game.render_cpu_samples), "gpu_mean_ms": _mean(game.gpu_samples),
		"render_cpu_p95_ms": _percentile(game.render_cpu_samples, 0.95), "gpu_p95_ms": _percentile(game.gpu_samples, 0.95),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"simulation_time": game.sim.time, "physics_ticks": game.benchmark_tick_count, "events": activity,
		"measured_simulation_seconds": game.sim.time-measurement_sim_start,
		"simulation_wall_ratio": (game.sim.time-measurement_sim_start)/maxf(total/1000.0,.001),
		"minimum_team_ground_air_buildings": minimum_team_counts,
		"fixed_population": options.get("case", "normal") == "stress" or options.get("fixed_population",true),
		"setup_ms": setup_ms, "startup_phases": game.startup_timings,
		"cpu": OS.get_processor_name(), "gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"vsync_disabled_for_measurement": true, "scene_content_preserved": true, "target_fps": target,
		"audio_logic_enabled": true, "audio_output_silent": true,
		"passed": minimum_second >= target and 1000.0 / maxf(one_percent_ms, 0.001) >= target,
		"navigation": game.sim.navigation_stats.duplicate(), "landscape": game.world.landscape.stats.duplicate()
	}
	result.world_stage_mean_ms = stage_ms
	result.frame_tick_histogram=frame_tick_histogram
	result.slow_frame_details=slow_frame_details
	result.slow_frame_threshold_ms=1000.0/target
	result.slow_frame_details_scope="Completed ticks and their CPU timers in the measured process-to-process interval; overlapping CPU work is not additive to frame time. GPU timestamps are intentionally not attributed to individual rows."
	if FileAccess.file_exists("res://data/performance_build_manifest.json"):
		var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/performance_build_manifest.json"))
		if manifest is Dictionary: result.runtime_identity = manifest.get("runtime_identity", "")
	if game.world.has_method("profile_sections"): result.world_sections = game.world.profile_sections()
	result.passed = result.passed and result.simulation_wall_ratio >= .98
	if result.fixed_population:
		result.passed = result.passed and min_units == initial_counts.x
		for team in range(team_records.size()):
			var item: Dictionary = team_records[team]
			if minimum_team_counts[team] != Vector3i(item.ground_units,item.air_units,item.buildings): result.passed = false
	var screenshot: String = str(options.get("screenshot", ""))
	if not screenshot.is_empty():
		await RenderingServer.frame_post_draw
		result.screenshot_error = game.get_viewport().get_texture().get_image().save_png(screenshot)
	var path: String = str(options.get("output", "user://performance.json"))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(result, "  "))
	print("PERFORMANCE_RESULT ", JSON.stringify(result))
	game.quit_game()
