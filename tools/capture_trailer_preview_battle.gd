extends SceneTree
## Local-only high-resolution battle preview. Does not touch media/ or exports.
## Actual main/PaperWorld/current rules/original Forest 320 terrain; controlled
## initial deployments, followed only by normal attack_move and sim.step calls.
const OUTPUT := "res://artifacts/trailer_preview_v3_20261011/battle"
const SIZE := Vector2i(3840,2160)
const FPS: int = 30
var game
var frames: int = 210
var camera_transform: Transform3D
var camera_fov: float
var map_hash: String
var events: Array[Dictionary] = []
var counts: Dictionary = {}
var ledger: Array[Dictionary] = []
var deployments: Array[Dictionary] = []
var commands: Array[Dictionary] = []

func progress(message: String) -> void:
	print("PREVIEW_BATTLE ",message)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var file := FileAccess.open(OUTPUT.path_join("progress.txt"),FileAccess.WRITE)
	file.store_string(message);file.close()

func _initialize() -> void:
	if OS.get_environment("PAPER_FRONT_CAPTURE_OFFSCREEN") != "1" or DisplayServer.get_name() != "X11":
		root.hide();printerr("Use the private X11 offscreen launcher for this local-only capture.");quit(2);return
	var override: int = int(OS.get_environment("PAPER_FRONT_PREVIEW_BATTLE_FRAMES"))
	if override > 0: frames = override
	call_deferred("run")

func geometry_hash() -> String:
	return JSON.stringify({"size":game.sim.map.size,"terrain":game.sim.map.terrain,"heights":game.sim.map.heights,"bridges":game.sim.map.bridges,"roads":game.sim.map.get("road_mark_cells",{})}).sha256_text()

func deploy(team: int, spec: String, point: Vector2, squad: bool = false) -> int:
	var id: int = game.sim.debug_spawn_squad(team,spec,point) if squad else game.sim.debug_spawn(team,spec,point)
	assert(id >= 0,"Legal midgame deployment failed: " + spec)
	deployments.append({"team":team,"spec":spec,"leader":id,"position":var_to_str(game.sim.entities[id].pos),"squad":squad})
	return id

func presentation_only_hide_ui() -> void:
	game.hud.visible = false
	game.overlay.hide()
	game.debug_panel.hide()
	game.performance_overlay.screen.hide()
	game.performance_overlay.process_mode = Node.PROCESS_MODE_DISABLED
	game.hud.fps_label.hide()
	# These are visual health-indicator nodes, not entity health or simulation.
	# Collapsing only their local transform keeps impact flashes/explosions and
	# the authored vehicle/infantry geometry completely intact.
	for model: Dictionary in game.world.models.values():
		model.hp_root.scale = Vector3.ZERO

func quality() -> void:
	root.msaa_3d = Viewport.MSAA_4X
	root.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	root.use_taa = false
	game.set_graphics_quality("native")
	game.set_render_scale(1.0)
	game.set_depth_of_field(false)
	game.world.lod_enabled = false
	game.world.lod_override = 0
	game.world.landscape.scenery_lod_enabled = false
	game.world.configure_quality("native")
	game.battlefield_viewport.size = SIZE
	game.battlefield_viewport.scaling_3d_scale = 1.0
	game.battlefield_viewport.msaa_3d = Viewport.MSAA_4X
	game.battlefield_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	game.battlefield_viewport.use_taa = false
	game.battlefield_viewport.mesh_lod_threshold = 0.0

func quality_evidence() -> Dictionary:
	return {"root_size":[root.size.x,root.size.y],"battlefield_viewport":[game.battlefield_viewport.size.x,game.battlefield_viewport.size.y],"internal_3d_pixels":[game.battlefield_viewport.size.x*game.battlefield_viewport.scaling_3d_scale,game.battlefield_viewport.size.y*game.battlefield_viewport.scaling_3d_scale],"render_scale":game.render_scale,"scaling_3d_scale":game.battlefield_viewport.scaling_3d_scale,"quality":game.graphics_quality,"world_quality":game.world.quality_policy,"lod_enabled":game.world.lod_enabled,"lod_override":game.world.lod_override,"scenery_lod_enabled":game.world.landscape.scenery_lod_enabled,"mesh_lod_threshold":game.battlefield_viewport.mesh_lod_threshold,"msaa_enum":game.battlefield_viewport.msaa_3d,"msaa_samples":4,"screen_space_aa":game.battlefield_viewport.screen_space_aa,"taa":game.battlefield_viewport.use_taa,"dof_near":game.lens.dof_blur_near_enabled,"dof_far":game.lens.dof_blur_far_enabled,"hud_visible":game.hud.visible,"overlay_visible":game.overlay.visible}

func run() -> void:
	progress("Creating fresh production main scene")
	root.size = SIZE
	root.content_scale_size = SIZE
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false);game.set_physics_process(false)
	game.set_process_input(false);game.set_process_unhandled_input(false)
	game.render_overlap_enabled = false
	game.audio.muted = true
	for warm: int in 4: await process_frame
	progress("Loading unmodified Forest 320")
	var match_options: Dictionary = {"vision_enabled":false,"slots":[{"faction":"kestrel","control":"human","difficulty":"normal","color":"#347dd0"},{"faction":"rivet","control":"human","difficulty":"normal","color":"#d85140"}]}
	assert(await game.start_match_with_loading("forest",73026,"kestrel",match_options))
	assert(int(game.sim.map.size) == 320)
	game.sim.ai_enabled = false
	game.sim.synchronous_path_tests = true
	map_hash = geometry_hash()
	var base: Vector2 = game.sim._team_start(0)
	# A nearby formal clearing avoids the old shot's foreground tree cluster.
	var center: Vector2 = game.standable_near(base + Vector2(6,17),2.0)
	var allies: Array = []
	var enemies: Array = []
	for i: int in 3: allies.append(deploy(0,"kestrel_tank",center+Vector2(-7,-4+i*4)))
	for i: int in 2: allies.append(deploy(0,"kestrel_artillery",center+Vector2(-11,-3+i*6)))
	for i: int in 2: allies.append(deploy(0,"kestrel_rifle",center+Vector2(-3,-7+i*14),true))
	for i: int in 3: enemies.append(deploy(1,"rivet_tank",center+Vector2(7,-4+i*4)))
	for i: int in 2: enemies.append(deploy(1,"rivet_rifle",center+Vector2(4,-7+i*14),true))
	game.sim.issue(allies,"attack_move",center+Vector2(7,0))
	game.sim.issue(enemies,"attack_move",center+Vector2(-7,0))
	commands=[{"kind":"attack_move","team":0,"ids":allies,"position":var_to_str(center+Vector2(7,0))},{"kind":"attack_move","team":1,"ids":enemies,"position":var_to_str(center+Vector2(-7,0))}]
	quality()
	game.selected.clear()
	game.focus = center + Vector2(0,1)
	game.distance = 35.0
	game.yaw = -0.10
	game.camera_pitch_mode = "fixed"
	game.camera_pitch = 42.0
	game._camera_pitch_blending = false
	game._refresh_camera_reference()
	game.update_camera()
	game.set_depth_of_field(false)
	game.world.sync(0.0,[],{})
	presentation_only_hide_ui()
	game.world.sync(0.0,[],{})
	game.sim.events.clear()
	for warm: int in 8: await process_frame
	await RenderingServer.frame_post_draw
	camera_transform = game.camera.global_transform
	camera_fov = game.camera.fov
	var settings: Dictionary = quality_evidence()
	assert(game.battlefield_viewport.size == SIZE and game.battlefield_viewport.scaling_3d_scale == 1.0)
	assert(not game.lens.dof_blur_near_enabled and not game.lens.dof_blur_far_enabled)
	progress("Recording %d true-4K frames" % frames)
	for frame: int in frames:
		game.sim.step(1.0/float(FPS))
		for event: Dictionary in game.sim.events:
			var kind: String = str(event.get("kind",""))
			counts[kind] = int(counts.get(kind,0))+1
			if kind in ["fire","impact","death"]: events.append({"frame":frame,"kind":kind,"sim_time":game.sim.time,"weapon":event.get("weapon",""),"spec":event.get("spec",""),"position":var_to_str(event.get("pos",Vector2.ZERO))})
		presentation_only_hide_ui()
		game.world.sync(1.0/float(FPS),[],{})
		game.sim.events.clear()
		assert(game.camera.global_transform.is_equal_approx(camera_transform) and is_equal_approx(game.camera.fov,camera_fov))
		assert(game.battlefield_viewport.size == SIZE and game.battlefield_viewport.scaling_3d_scale == 1.0)
		var tiers: Dictionary = {}
		var model_projections: Array[Dictionary] = []
		for id in game.world.models:
			var model: Dictionary = game.world.models[id]
			var tier: int = int(model.get("lod_tier",0))
			tiers[str(tier)] = int(tiers.get(str(tier),0))+1
			assert(tier == 0)
			if game.sim.entities.has(id) and str(game.sim.entities[id].spec) in ["kestrel_tank","rivet_tank","kestrel_artillery"]:
				model_projections.append({"id":id,"spec":game.sim.entities[id].spec,"lod":tier,"projected_diameter_pixels":model.get("lod_pixels",0.0)})
		ledger.append({"frame":frame,"sim_time":game.sim.time,"entities":game.sim.entities.size(),"camera_fixed":true,"camera_transform":var_to_str(game.camera.global_transform),"camera_fov":game.camera.fov,"viewport":[SIZE.x,SIZE.y],"lod_counts":tiers,"model_projections":model_projections})
		await process_frame
		await RenderingServer.frame_post_draw
		var pixels: Image = game.battlefield_viewport.get_texture().get_image()
		assert(pixels.get_size() == SIZE)
		assert(pixels.save_png(OUTPUT.path_join("%04d.png" % frame)) == OK)
		if frame % 30 == 0: progress("Frame %d/%d, real sim %.2fs" % [frame,frames,game.sim.time])
	var manifest: Dictionary={"local_preview_only":true,"source_type":"Direct Battlefield SubViewport readback, not a root screenshot or cropped/upscaled UI video","resolution":[SIZE.x,SIZE.y],"fps":FPS,"frames":frames,"duration_s":float(frames)/FPS,"simulation_multiplier":1.0,"renderer":RenderingServer.get_current_rendering_method(),"device":RenderingServer.get_video_adapter_name(),"display":DisplayServer.get_name(),"map_mode":game.sim.map.mode,"map_size":game.sim.map.size,"map_geometry_sha256":map_hash,"geometry_unchanged":geometry_hash()==map_hash,"player_slots":game.sim.match_options.slots,"capture_settings":settings,"settings_end":quality_evidence(),"camera_fixed_every_frame":true,"camera_distance":game.distance,"camera_pitch":game.camera_pitch,"camera_yaw":game.yaw,"event_counts":counts,"event_timeline":events,"deployments":deployments,"commands":commands,"frames_ledger":ledger,"rules_sha256":FileAccess.get_sha256("res://data/rules.json"),"disclosure":"Local-only controlled true-4K gameplay demonstration. Initial midgame armies are authored legal deployments; all subsequent movement, damage, casualties, shells and impacts come from normal attack_move commands and 1/30-second simulation ticks. Original Forest 320 terrain is unchanged. Capture forces complete native-quality LOD0 geometry, 100% render scale, 4x MSAA, no TAA/FXAA, and disables both near/far DOF. HUD, selection/command overlays and visual health indicators are hidden without changing entity health or any game rule. Camera is fixed and PNGs come directly from the actual 3840x2160 3D SubViewport."}
	assert(bool(manifest.geometry_unchanged))
	if frames >= 180: assert(int(counts.get("fire",0)) > 0 and int(counts.get("impact",0)) > 0 and int(counts.get("death",0)) > 0)
	var file := FileAccess.open(OUTPUT.path_join("capture_manifest.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest,"\t"));file.close()
	progress("Complete, actual events " + str(counts))
	game.audio.stop_all();game.free();game=null
	await process_frame;await process_frame
	quit()
