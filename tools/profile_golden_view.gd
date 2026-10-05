extends SceneTree

# Frozen render-only profile. Run only after other GPU captures have finished:
# godot --path . --script res://tools/profile_golden_view.gd -- --golden-visual --golden-view gameplay --golden-fixture res://data/golden_visual_paintedforest_v9.json --render-scale 1.0
# Uses main.tscn's existing fixture/camera/HUD path. No AI or simulation advances;
# these timings must not be reported as normal gameplay/skirmish performance.
const FIXTURE := "res://data/golden_visual_paintedforest_v9.json"
const OUTPUT_DIR := "res://artifacts/visual_iteration/v44_reference_rebuild"
const WARMUP_FRAMES := 16
const SAMPLE_SECONDS := 8.0
var game: Node3D

func _initialize() -> void:
	call_deferred("run")

func fail_profile(message: String) -> void:
	push_error("FROZEN_RENDER_PROFILE: " + message)
	if is_instance_valid(game): game.quit_game(2)
	else: quit(2)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not "--golden-visual" in args:
		fail_profile("Pass --golden-visual --golden-view gameplay --golden-fixture " + FIXTURE)
		return
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	if game.quit_pending: return
	if not game.golden_mode or game.golden_view != "gameplay" or game.golden_fixture != FIXTURE:
		fail_profile("The exact frozen gameplay fixture/view is required")
		return
	if not game.golden_output.is_empty() or not game.golden_capture_dir.is_empty():
		fail_profile("Omit golden capture output arguments; this profiler owns its screenshot after sampling")
		return
	# Native golden setup already selects the real 1920x1080 window and 100%.
	# Deferred resize/layout completes before measuring actual completed draws.
	for frame in range(WARMUP_FRAMES):
		await RenderingServer.frame_post_draw
	if root.size != Vector2i(1920, 1080) or not is_equal_approx(game.render_scale, 1.0):
		fail_profile("Expected the unchanged golden 1920x1080 / 100% render setup")
		return
	if game.started or game.benchmark or game.sim.ai_enabled:
		fail_profile("The source scene must remain a frozen render-only fixture")
		return
	var frozen_time: float = game.sim.time
	var frozen_visual_time: float = game.world.elapsed
	var frozen_tick: int = game.golden_state.tick
	var initial_camera := {"focus": game.focus, "pitch": game.camera_pitch, "yaw": game.yaw, "distance": game.distance, "position": game.camera.position, "rotation": game.camera.rotation, "fov": game.camera.fov}
	var intervals_ms: Array[float] = []
	var began_us := Time.get_ticks_usec()
	var previous_us := began_us
	var finished_us := began_us
	while float(finished_us - began_us) / 1000000.0 < SAMPLE_SECONDS:
		await RenderingServer.frame_post_draw
		finished_us = Time.get_ticks_usec()
		intervals_ms.append(float(finished_us - previous_us) / 1000.0)
		previous_us = finished_us
	var duration := float(finished_us - began_us) / 1000000.0
	var final_camera := {"focus": game.focus, "pitch": game.camera_pitch, "yaw": game.yaw, "distance": game.distance, "position": game.camera.position, "rotation": game.camera.rotation, "fov": game.camera.fov}
	if game.sim.time != frozen_time or game.world.elapsed != frozen_visual_time or game.golden_state.tick != frozen_tick or initial_camera != final_camera:
		fail_profile("Simulation, visual time, or camera changed during the static profile")
		return
	if intervals_ms.is_empty():
		fail_profile("No completed draw intervals were sampled")
		return
	var ordered := intervals_ms.duplicate()
	ordered.sort()
	var p95_index := clampi(int(ceil(ordered.size() * 0.95)) - 1, 0, ordered.size() - 1)
	# Image readback, encoding and metadata collection happen after the timer.
	var img: Image = root.get_texture().get_image()
	if img.is_empty() or img.get_size() != Vector2i(1920, 1080):
		fail_profile("The post-profile screenshot is not a real 1920x1080 draw")
		return
	var directory_error := DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	if directory_error != OK:
		fail_profile("Cannot create output directory, code " + str(directory_error))
		return
	var image_path := OUTPUT_DIR.path_join("normal_render_profile.png")
	var image_error := img.save_png(image_path)
	if image_error != OK:
		fail_profile("Cannot save screenshot, code " + str(image_error))
		return
	var metadata: Dictionary = game.golden_metadata(img)
	metadata["warmup_frames"] = WARMUP_FRAMES
	metadata["measurement_completed_draws"] = intervals_ms.size()
	metadata["profile_scope"] = "frozen gameplay fixture; render-only; no AI or simulation advancement"
	var metadata_path := OUTPUT_DIR.path_join("normal_render_profile.metadata.json")
	var metadata_file := FileAccess.open(metadata_path, FileAccess.WRITE)
	if metadata_file == null:
		fail_profile("Cannot save screenshot metadata")
		return
	metadata_file.store_string(JSON.stringify(metadata, "  "))
	metadata_file.close()
	var report := {
		"profile_kind": "frozen_static_render_only",
		"normal_gameplay_performance": false,
		"scope": "Real main.tscn and frozen gameplay camera/HUD; no AI, moving units, economic ticks or combat simulation. Includes the normal frozen scene render/update path.",
		"godot": Engine.get_version_info().string,
		"renderer": RenderingServer.get_current_rendering_method(),
		"display_server": DisplayServer.get_name(),
		"fixture": game.golden_fixture,
		"fixture_hash": game.golden_state.fixture_hash,
		"view": game.golden_view,
		"window_pixels": [root.size.x, root.size.y],
		"render_scale": game.render_scale,
		"warmup_completed_draws": WARMUP_FRAMES,
		"sampling_clock": "Time.get_ticks_usec at RenderingServer.frame_post_draw",
		"requested_sampling_seconds": SAMPLE_SECONDS,
		"measured_sampling_seconds": duration,
		"sampled_frames": intervals_ms.size(),
		"average_fps": float(intervals_ms.size()) / duration,
		"mean_frame_ms": duration * 1000.0 / float(intervals_ms.size()),
		"frame_p95_ms": ordered[p95_index],
		"max_frame_ms": ordered.back(),
		"simulation_time_before": frozen_time,
		"simulation_time_after": game.sim.time,
		"visual_time_before": frozen_visual_time,
		"visual_time_after": game.world.elapsed,
		"fixture_tick": frozen_tick,
		"camera_unchanged": initial_camera == final_camera,
		"camera": metadata.camera,
		"screenshot": image_path,
		"screenshot_metadata": metadata_path,
		"screenshot_metadata_matches_profile_camera": true,
		"frame_intervals_ms": intervals_ms,
	}
	var output_path := OUTPUT_DIR.path_join("normal_render_profile.json")
	var output := FileAccess.open(output_path, FileAccess.WRITE)
	if output == null:
		fail_profile("Cannot write render profile")
		return
	output.store_string(JSON.stringify(report, "  "))
	output.close()
	print("FROZEN_RENDER_PROFILE ", JSON.stringify({"average_fps": report.average_fps, "frame_p95_ms": report.frame_p95_ms, "sampled_frames": report.sampled_frames, "measured_sampling_seconds": duration, "normal_gameplay_performance": false, "output": output_path, "screenshot": image_path}))
	game.quit_game()
