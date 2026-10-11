extends SceneTree
## Controlled in-engine demonstrations on an untouched, selectable battlefield.
## Actual main.tscn, HUD, PaperWorld and paid construction/combat rules are used.
## Initial midgame deployments/funds are authored; all subsequent changes use
## normal commands and sim.step(). No HP or construction-progress assignments.
## Capture one shot with the shared capture.lock and run_offscreen_capture.py.
## Set PAPER_FRONT_ACTION_SHOT=combat or construction, optionally
## PAPER_FRONT_ACTION_FRAMES=3 for QA (full clips are 240 and 210 frames).
## Intel/Xvfb: VK_DRIVER_FILES=/usr/share/vulkan/icd.d/intel_icd.json,
## MESA_VK_WSI_DEBUG=sw, MESA_VK_WSI_HEADLESS_SWAPCHAIN=1.
const L = preload("res://scripts/localization.gd")
const FPS: int = 30
const SIZE := Vector2i(1280, 720)
const OUTPUT := "res://artifacts/trailer_revision_20261011/action"
var game
var shot: String = "combat"
var frame_limit: int = 0
var selected: Array = []
var ledger: Array[Dictionary] = []
var orders: Array[Dictionary] = []
var event_counts: Dictionary = {}
var event_timeline: Array[Dictionary] = []
var construction_id: int = -1
var builder_id: int = -1
var initial_money: float = 0.0
var capture_transform: Transform3D
var capture_fov: float = 0.0
var capture_camera_size: float = 0.0
var frame_camera_consistent: bool = true
var completed_frame: int = -1
var actual_frames: int = 0
var map_geometry_hash: String = ""

func geometry_identity() -> String:
	return JSON.stringify({"size":game.sim.map.size, "terrain":game.sim.map.terrain, "heights":game.sim.map.heights, "bridges":game.sim.map.bridges, "roads":game.sim.map.get("road_mark_cells",{})}).sha256_text()

func background_anchor_rectangles() -> Array:
	# Real fixed geometry, excluding UI counters, actors and the work site.
	return [[170,203,42,38],[270,355,70,55],[855,435,90,50]] if shot == "combat" else [[520,220,115,75],[329,372,40,45],[425,435,90,50]]

func _initialize() -> void:
	if OS.get_environment("PAPER_FRONT_CAPTURE_OFFSCREEN") != "1":
		root.hide()
		printerr("Use tools/run_offscreen_capture.py on a private display.")
		quit(2)
		return
	shot = OS.get_environment("PAPER_FRONT_ACTION_SHOT")
	if shot.is_empty(): shot = "combat"
	frame_limit = int(OS.get_environment("PAPER_FRONT_ACTION_FRAMES"))
	call_deferred("run")

func checkpoint(message: String) -> void:
	print("ACTION_CAPTURE ", shot, " ", message)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var file := FileAccess.open(OUTPUT.path_join(shot + "_progress.txt"), FileAccess.WRITE)
	file.store_string(message)
	file.close()

func spawn(team: int, spec: String, wanted: Vector2, squad: bool = false) -> int:
	var id: int = game.sim.debug_spawn_squad(team, spec, wanted) if squad else game.sim.debug_spawn(team, spec, wanted)
	assert(id >= 0, "Unable to deploy legal midgame unit " + spec)
	return id

func ground_near(wanted: Vector2, radius: float = 1.0) -> Vector2:
	return game.standable_near(wanted, radius)

func configure_camera(center: Vector2, distance: float) -> void:
	game.focus = center
	game.distance = distance
	game.yaw = 0.08
	game.camera_pitch_mode = "fixed"
	game.camera_pitch = 39.0
	game._refresh_camera_reference()
	game.update_camera()
	capture_transform = game.camera.global_transform
	capture_fov = game.camera.fov
	capture_camera_size = game.camera.size

func setup_combat(base: Vector2) -> void:
	var center: Vector2 = ground_near(base + Vector2(22, 19), 2.0)
	var allies: Array = []
	var enemies: Array = []
	for i: int in range(3):
		allies.append(spawn(0, "kestrel_tank", center + Vector2(-8, -4 + i * 4)))
	for i: int in range(2):
		allies.append(spawn(0, "kestrel_artillery", center + Vector2(-13, -3 + i * 6)))
	for i: int in range(2):
		allies.append(spawn(0, "kestrel_rifle", center + Vector2(-4, -7 + i * 14), true))
	for i: int in range(3):
		enemies.append(spawn(1, "rivet_tank", center + Vector2(8, -4 + i * 4)))
	for i: int in range(2):
		enemies.append(spawn(1, "rivet_rifle", center + Vector2(5, -7 + i * 14), true))
	game.sim.issue(allies, "attack_move", center + Vector2(8, 0))
	game.sim.issue(enemies, "attack_move", center + Vector2(-8, 0))
	orders.append({"command":"attack_move", "team":0, "ids":allies.duplicate(), "target":[center.x + 8, center.y]})
	orders.append({"command":"attack_move", "team":1, "ids":enemies.duplicate(), "target":[center.x - 8, center.y]})
	selected = game.selectable_squad(allies)
	configure_camera(center + Vector2(0, 2), 50.0)

func setup_construction(base: Vector2) -> void:
	var wanted: Vector2 = base + Vector2(8, 9)
	var site := Vector2.INF
	var info: Dictionary = game.sim.data_for("rivet_power")
	for radius: int in range(7, 19):
		for direction: Vector2 in [Vector2(1,1), Vector2(1,0), Vector2(0,1), Vector2(-1,1), Vector2(1,-1)]:
			var candidate: Vector2 = base + direction * float(radius)
			candidate = Vector2(roundf(candidate.x - 1.5) + 1.5, roundf(candidate.y - 1.5) + 1.5)
			if game.sim._building_site_error(0, info, candidate, -1).is_empty():
				site = candidate
				break
		if site.is_finite(): break
	assert(site.is_finite(), "Formal map has no legal nearby construction site")
	wanted = ground_near(site + Vector2(-2.2, 0), 0.5)
	builder_id = spawn(0, "rivet_engineer", wanted)
	var problem: String = game.sim.build(0, "rivet_power", builder_id)
	assert(problem.is_empty(), problem)
	problem = game.sim.place_building(0, site)
	assert(problem.is_empty(), problem)
	for entity: Dictionary in game.sim.entities.values():
		if str(entity.spec) == "rivet_power" and int(entity.get("construction",{}).get("builder",-1)) == builder_id:
			construction_id = int(entity.id)
	orders.append({"command":"build", "team":0, "spec":"rivet_power", "builder":builder_id, "error":problem})
	orders.append({"command":"place_building", "team":0, "site":[site.x, site.y], "error":problem})
	selected = [builder_id]
	game.hud.tab = "build"
	configure_camera(base.lerp(site, 0.6) + Vector2(0, 2), 43.0)

func sample_frame(frame: int) -> void:
	var consistent: bool = game.camera.global_transform.is_equal_approx(capture_transform) and is_equal_approx(game.camera.fov, capture_fov) and is_equal_approx(game.camera.size, capture_camera_size) and root.size == SIZE
	frame_camera_consistent = frame_camera_consistent and consistent
	var health: float = 0.0
	for entity: Dictionary in game.sim.entities.values(): health += float(entity.hp)
	var record: Dictionary = {"frame":frame, "sim_time":game.sim.time, "entities":game.sim.entities.size(), "total_hp":health, "money":game.sim.money[0], "selected_ids":selected.duplicate(), "camera_fixed":consistent, "camera_transform":var_to_str(game.camera.global_transform), "camera_fov":game.camera.fov, "camera_size":game.camera.size, "window_size":[root.size.x, root.size.y]}
	if construction_id >= 0 and game.sim.entities.has(construction_id):
		var building: Dictionary = game.sim.entities[construction_id]
		record["construction"] = {"id":construction_id, "remaining":building.construct_remaining, "progress":building.get("construction",{}).get("progress",1.0), "spent":building.get("construction",{}).get("spent",float(game.sim.data_for(building.spec).cost)), "hp":building.hp, "complete":building.get("construction",{}).is_empty()}
		if bool(record.construction.complete) and completed_frame < 0: completed_frame = frame
	ledger.append(record)

func run() -> void:
	assert(shot in ["combat", "construction"])
	checkpoint("Preparing actual main scene")
	L.initialize("en")
	root.size = SIZE
	root.content_scale_size = Vector2i(1600, 900)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.render_overlap_enabled = false
	game.audio.stop_all()
	await process_frame
	var faction: String = "kestrel" if shot == "combat" else "rivet"
	assert(await game.start_match_with_loading("forest", 73026, faction, {"vision_enabled":false}))
	assert(int(game.sim.map.size) == 320 and str(game.sim.map.mode) == "forest")
	map_geometry_hash = geometry_identity()
	game.sim.synchronous_path_tests = true
	game.sim.ai_enabled = false
	game.sim.money[0] = 12000.0
	initial_money = float(game.sim.money[0])
	game.pve_paused = false
	game.started = true
	game.debug_available = false
	game.hud.show_entry(false)
	game.hud.show_menu(false)
	game.debug_panel.hide()
	game.hud.fps_label.hide()
	game.performance_overlay.screen.hide()
	game.performance_overlay.process_mode = Node.PROCESS_MODE_DISABLED
	var start: Array = game.sim.map.starts[0]
	var base := Vector2(float(start[0]), float(start[1]))
	checkpoint("Preparing legal controlled midgame deployments on original terrain")
	if shot == "combat": setup_combat(base)
	else: setup_construction(base)
	game.selected = selected
	game.hud.refresh(game.sim, selected, game.camera, false, "", 0.0, -1, false)
	game.world.sync(0.0, selected, {})
	game.sim.events.clear()
	for warm: int in range(8): await process_frame
	await RenderingServer.frame_post_draw
	var duration: float = 8.0 if shot == "combat" else 7.0
	var multiplier: float = 1.0 if shot == "combat" else 3.0
	var frames: int = int(duration * FPS) if frame_limit <= 0 else frame_limit
	var folder: String = OUTPUT.path_join(shot)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	checkpoint("Recording %d frames at fixed 30 fps simulation cadence" % frames)
	for frame: int in range(frames):
		if shot == "combat": selected = game.selectable_squad(selected)
		game.sim.step(multiplier / float(FPS))
		for event: Dictionary in game.sim.events:
			var kind: String = str(event.get("kind", ""))
			event_counts[kind] = int(event_counts.get(kind,0)) + 1
			if kind in ["fire", "impact", "build", "ready", "deploy", "death"]:
				event_timeline.append({"frame":frame, "sim_time":game.sim.time, "kind":kind, "weapon":event.get("weapon", ""), "spec":event.get("spec", ""), "id":event.get("id", -1), "position":var_to_str(event.get("pos", Vector2.ZERO))})
			if kind == "build" and str(event.get("spec", "")) == "rivet_power":
				construction_id = int(event.id)
				selected = [builder_id, construction_id]
		if shot == "construction" and construction_id >= 0:
			if frame == 45:
				selected = [construction_id]
				orders.append({"command":"select", "frame":frame, "ids":selected.duplicate(), "purpose":"Show the actual scaffold progress, payment and health in the normal HUD"})
			elif frame == 165:
				selected = [builder_id, construction_id]
				orders.append({"command":"select", "frame":frame, "ids":selected.duplicate(), "purpose":"Restore the engineer construction cards beside the completed building"})
		game.world.sync(multiplier / float(FPS), selected, {})
		game.hud.refresh(game.sim, selected, game.camera, false, "", 0.0, -1, false)
		game.sim.events.clear()
		sample_frame(frame)
		await process_frame
		await RenderingServer.frame_post_draw
		var pixels: Image = root.get_texture().get_image()
		assert(pixels.get_size() == SIZE)
		assert(pixels.save_png(folder.path_join("%04d.png" % frame)) == OK)
		actual_frames += 1
		if frame % 30 == 0: checkpoint("Frame %d / %d, sim %.2fs" % [frame, frames, game.sim.time])
	var manifest: Dictionary = {"shot":shot, "renderer":RenderingServer.get_current_rendering_method(), "device":RenderingServer.get_video_adapter_name(), "display":DisplayServer.get_name(), "map_mode":game.sim.map.mode, "map_size":game.sim.map.size, "terrain_edited":false, "map_geometry_sha256":map_geometry_hash, "geometry_unchanged":geometry_identity() == map_geometry_hash, "rules_sha256":FileAccess.get_sha256("res://data/rules.json"), "main_sha256":FileAccess.get_sha256("res://scripts/main.gd"), "resolution":[SIZE.x,SIZE.y], "fps":FPS, "frames":actual_frames, "duration_s":float(actual_frames)/FPS, "simulation_multiplier":multiplier, "sim_time_start":ledger[0].sim_time, "sim_time_end":game.sim.time, "initial_money":initial_money, "final_money":game.sim.money[0], "event_counts":event_counts, "event_timeline":event_timeline, "event_ledger":event_timeline, "orders":orders, "camera_fixed_every_frame":frame_camera_consistent, "construction_complete_frame":completed_frame, "frames_ledger":ledger, "static_background_anchors":{"top_hud_resource_frame":[12,12,190,25],"minimap_paper_frame":[8,526,210,180],"terrain_and_scenery":"All original Forest-map terrain, bridge and scenery transforms remain fixed; only units, visual effects, construction and HUD state change."}, "disclosure":"Controlled in-engine demonstration using actual main.tscn, current rules, actual HUD and original selectable 320-cell Forest map. Initial units and funds are authored. Combat executes ordinary attack_move commands at 1x; construction executes normal engineer build/place commands with actual per-tick payment/progress at 3x simulation speed. No HP or construction progress has been manually changed. Camera transform, FOV and viewport size remain fixed per frame."}
	assert(frame_camera_consistent)
	assert(geometry_identity() == map_geometry_hash)
	if actual_frames == int(duration * FPS):
		assert(completed_frame >= 0 and is_equal_approx(initial_money - float(game.sim.money[0]), 600.0) if shot == "construction" else int(event_counts.get("fire",0)) > 0 and int(event_counts.get("impact",0)) > 0 and int(event_counts.get("death",0)) > 0)
	manifest["static_background_anchor_rects_xywh"] = background_anchor_rectangles()
	manifest["static_background_anchors"] = {"source_resolution":[SIZE.x,SIZE.y], "rectangles_xywh":background_anchor_rectangles(), "scope":"Fixed world geometry; dynamic counters, minimap units, construction and central battle effects are excluded."}
	var file := FileAccess.open(OUTPUT.path_join(shot + "_manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest,"\t"));file.close()
	checkpoint("Complete, events " + str(event_counts))
	game.audio.stop_all()
	game.free()
	game = null
	await process_frame
	await process_frame
	quit()
