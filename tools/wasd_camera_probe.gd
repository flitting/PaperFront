extends "res://scripts/main.gd"

## Diagnostic only: production camera actions and rendering, with isolated
## shadow/tree/post-process/simulation ablations. Never changes game defaults.
const PROBE_ACTIONS = ["camera_pan_left", "camera_pan_right", "camera_pan_forward", "camera_pan_backward"]
var probe_cases: Array[Dictionary] = [
	{"name":"near_idle", "distance":40.0},
	{"name":"near_wasd", "distance":40.0, "pan":true},
	{"name":"far_idle", "distance":110.0},
	{"name":"far_full_models", "distance":110.0, "pan":true, "full_models":true},
	{"name":"far_wasd", "distance":110.0, "pan":true},
	{"name":"far_no_shadows", "distance":110.0, "pan":true, "no_shadows":true},
	{"name":"far_no_trees", "distance":110.0, "pan":true, "no_trees":true},
	{"name":"far_no_simulation", "distance":110.0, "pan":true, "paused":true},
	{"name":"far_no_dof", "distance":110.0, "pan":true, "no_dof":true},
	{"name":"far_key_echo", "distance":110.0, "pan":true, "echo":true},
	{"name":"far_wasd_repeat", "distance":110.0, "pan":true}
]
var probe_index: int = -1
var probe_active: bool = false
var probe_phase_started: int = 0
var probe_previous: int = 0
var probe_seconds: float = 6.0
var probe_warmup: float = 2.0
var probe_rows: Array[Dictionary] = []
var probe_samples: Array[Dictionary] = []
var probe_scenery: Array[Dictionary] = []
var probe_center := Vector2(160.0, 160.5)
var probe_output: String = "res://artifacts/wasd_camera_20261005/rendered.json"
var probe_map: String = "forest"
var probe_vsync: bool = false
var probe_capture: bool = false
var probe_camera_us: int = 0
var probe_control_us: int = 0
var probe_key_echo_at: int = 0
var probe_direction: int = 1
var probe_errors: Array[String] = []

func _ready() -> void:
	super._ready()
	call_deferred("begin_probe")

func begin_probe() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Camera render probe requires a real GPU/display")
		quit_game(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-output="): probe_output = arg.trim_prefix("--probe-output=")
		elif arg.begins_with("--probe-map="): probe_map = arg.trim_prefix("--probe-map=")
		elif arg.begins_with("--probe-seconds="): probe_seconds = float(arg.trim_prefix("--probe-seconds="))
		elif arg == "--probe-vsync": probe_vsync = true
		elif arg == "--probe-capture": probe_capture = true
		elif arg.begins_with("--probe-cases="):
			var names = arg.trim_prefix("--probe-cases=").split(",")
			probe_cases = probe_cases.filter(func(item): return item.name in names)
	get_window().size = Vector2i(1920, 1080)
	get_window().mode = Window.MODE_WINDOWED
	get_window().grab_focus()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if probe_vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	if not start_match(probe_map, 73026, "rivet", true):
		quit_game(2)
		return
	sim.ai_enabled = false
	sim.vision_enabled = false
	probe_center = Vector2(float(sim.map.size) * .5, float(sim.map.size) * .5 + .5)
	hud.show_menu(false)
	hud.show_entry(false)
	pointer_in_window = false
	set_render_scale(1.0)
	dof_override = -1
	set_graphics_quality("balanced")
	AudioServer.set_bus_volume_db(0, -80.0)
	world.profile_enabled = true
	for node in world.landscape.get_children():
		var label: String = str(node.name)
		if label.begins_with("PropBatch_tree_") or label.begins_with("PropBatch_trunk") or label.begins_with("TrunkFar_") or label.begins_with("TrunkDistant_") or label.begins_with("TreeMidVisual_") or label.begins_with("TreeFarVisual_") or label.begins_with("TreeNearCaster_") or label.begins_with("TreeFarCaster_"):
			probe_scenery.append({"node":node,"visible":node.visible})
	RenderingServer.viewport_set_measure_render_time(battlefield_viewport.get_viewport_rid(), true)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	resize_battlefield()
	probe_active = true
	next_probe_case()

func next_probe_case() -> void:
	_flush_render_simulation()
	for action in PROBE_ACTIONS: Input.action_release(action)
	probe_index += 1
	if probe_index >= probe_cases.size():
		finish_probe()
		return
	var config: Dictionary = probe_cases[probe_index]
	world.lod_enabled = not bool(config.get("full_models", false))
	world.landscape.scenery_lod_enabled = world.lod_enabled
	pve_paused = bool(config.get("paused", false))
	key_light.shadow_enabled = not bool(config.get("no_shadows", false))
	dof_override = 0 if bool(config.get("no_dof", false)) else -1
	_apply_depth_of_field()
	for item in probe_scenery: item.node.visible = bool(item.visible) and not bool(config.get("no_trees", false))
	focus = probe_center
	distance = float(config.distance)
	camera_pitch = 34.0
	yaw = 0.0
	update_camera()
	probe_direction = 1
	probe_phase_started = Time.get_ticks_usec()
	probe_previous = 0
	probe_key_echo_at = 0
	probe_samples.clear()
	print("WASD_PROBE_BEGIN ", config.name)

func update_camera() -> void:
	var began: int = Time.get_ticks_usec()
	super.update_camera()
	probe_camera_us += Time.get_ticks_usec() - began

func camera_controls(delta: float) -> void:
	var began: int = Time.get_ticks_usec()
	super.camera_controls(delta)
	probe_control_us += Time.get_ticks_usec() - began

func _process(delta: float) -> void:
	if not probe_active:
		super._process(delta)
		return
	var config: Dictionary = probe_cases[probe_index]
	var now: int = Time.get_ticks_usec()
	var elapsed: float = float(now - probe_phase_started) / 1000000.0
	if elapsed >= probe_warmup + probe_seconds:
		finish_probe_case()
		next_probe_case()
		return
	if bool(config.get("pan", false)):
		if focus.x >= probe_center.x + 24.0: probe_direction = -1
		elif focus.x <= probe_center.x - 24.0: probe_direction = 1
		Input.action_release("camera_pan_left" if probe_direction > 0 else "camera_pan_right")
		Input.action_press("camera_pan_right" if probe_direction > 0 else "camera_pan_left")
		if bool(config.get("echo", false)) and now - probe_key_echo_at >= 33333:
			var event := InputEventKey.new()
			event.pressed = true
			event.echo = true
			event.keycode = KEY_D if probe_direction > 0 else KEY_A
			event.physical_keycode = event.keycode
			Input.parse_input_event(event)
			probe_key_echo_at = now
	probe_camera_us = 0
	probe_control_us = 0
	var previous_focus: Vector2 = focus
	var previous_y: float = camera.position.y
	var began: int = Time.get_ticks_usec()
	super._process(delta)
	var logic_ms: float = float(Time.get_ticks_usec() - began) / 1000.0
	if elapsed >= probe_warmup and probe_previous > 0:
		var viewport_rid: RID = battlefield_viewport.get_viewport_rid()
		var root_rid: RID = get_viewport().get_viewport_rid()
		var sample: Dictionary = {
			"frame_ms":float(now-probe_previous)/1000.0,
			"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid)+RenderingServer.viewport_get_measured_render_time_gpu(root_rid),
			"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid)+RenderingServer.viewport_get_measured_render_time_cpu(root_rid)+RenderingServer.get_frame_setup_time_cpu(),
			"logic_ms":logic_ms,"world_ms":world_cpu_ms,"simulation_ms":sim_cpu_ms,
			"camera_ms":float(probe_camera_us+probe_control_us)/1000.0,
			"focus_step_m":focus.distance_to(previous_focus),"vertical_step_m":absf(camera.position.y-previous_y),
			"window_focused":get_window().has_focus(),"focus":[focus.x,focus.y],
			"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			"world_profile":world.profile_last.duplicate()
		}
		probe_samples.append(sample)
	probe_previous = now

func summary(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {}
	values.sort()
	var total: float = 0.0
	for value in values: total += value
	return {"mean":total/values.size(),"p50":values[values.size()/2],"p95":values[mini(values.size()-1,int(values.size()*.95))],"p99":values[mini(values.size()-1,int(values.size()*.99))],"max":values.back()}

func finish_probe_case() -> void:
	var config: Dictionary = probe_cases[probe_index]
	var row: Dictionary = {"case":config.duplicate(),"samples":probe_samples.size(),"summary":{},"world_profile_mean":{}}
	var changed: int = 0
	var un_focused: int = 0
	var budget: int = 0
	for sample in probe_samples:
		if float(sample.focus_step_m) > .001: changed += 1
		if not sample.window_focused: un_focused += 1
		if float(sample.frame_ms) > 33.333: budget += 1
		for key in sample.world_profile: row.world_profile_mean[key] = float(row.world_profile_mean.get(key,0.0)) + float(sample.world_profile[key])
	for metric in ["frame_ms","gpu_ms","render_cpu_ms","logic_ms","world_ms","simulation_ms","camera_ms","focus_step_m","vertical_step_m","draw_calls","primitives"]:
		var values: Array[float] = []
		for sample in probe_samples: values.append(float(sample[metric]))
		row.summary[metric] = summary(values)
	for key in row.world_profile_mean: row.world_profile_mean[key] /= maxi(1,probe_samples.size())
	row.frames_over_33ms_percent = 100.0 * float(budget) / maxi(1,probe_samples.size())
	row.moving_frames = changed
	row.unfocused_frames = un_focused
	row.landscape_stats = world.landscape.stats.duplicate(true)
	if probe_capture:
		var path: String = probe_output.get_basename()+"_"+str(config.name)+".png"
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var error: Error = get_viewport().get_texture().get_image().save_png(path)
		if error != OK: probe_errors.append("Cannot save camera/LOD capture: "+path)
		else: row.screenshot = path
	if bool(config.get("pan", false)) and changed == 0: probe_errors.append(str(config.name)+": camera did not move")
	row.raw = probe_samples.duplicate(true)
	probe_rows.append(row)
	print("WASD_PROBE_RESULT ", JSON.stringify({"name":config.name,"frames":row.samples,"fps":1000.0/float(row.summary.frame_ms.mean),"frame_p95_ms":row.summary.frame_ms.p95,"gpu_mean_ms":row.summary.gpu_ms.mean,"camera_p95_ms":row.summary.camera_ms.p95,"world_mean_ms":row.summary.world_ms.mean,"vertical_max_m":row.summary.vertical_step_m.max,"unfocused_frames":un_focused}))

func finish_probe() -> void:
	probe_active = false
	DirAccess.make_dir_recursive_absolute(probe_output.get_base_dir())
	var report: Dictionary = {"scope":"Actual main controller, synthetic WASD actions, fresh match, AI off. Ablations affect diagnostic only; source runtime, not export FPS guarantee.","godot":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"map":probe_map,"seed":73026,"resolution":get_window().size,"battlefield_resolution":battlefield_viewport.size,"quality":"balanced","render_scale":1.0,"vsync":probe_vsync,"distance_limits":[40,110],"warmup_seconds":probe_warmup,"sample_seconds":probe_seconds,"entities":sim.entities.size(),"render_overlap":render_overlap_enabled,"source_sha256":{},"rows":probe_rows,"errors":probe_errors}
	for path in ["res://scripts/main.gd","res://scripts/paper_world.gd","res://scripts/landscape.gd","res://scripts/map_data.gd","res://scripts/simulation.gd","res://assets/native/libpaper_front_kernels.so"]: report.source_sha256[path] = FileAccess.get_sha256(path)
	var file = FileAccess.open(probe_output, FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("WASD_PROBE_DONE ",probe_output," errors=",probe_errors)
	quit_game(0 if probe_errors.is_empty() else 1)
