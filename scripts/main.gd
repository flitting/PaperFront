extends Node3D

var sim: WarSimulation
var world: PaperWorld
var camera: Camera3D
var lens: CameraAttributesPractical
var battlefield_viewport: SubViewport
var battlefield_display: TextureRect
var environment: Environment
var key_light: DirectionalLight3D
var hud: PaperHUD
var audio: PaperAudio
var overlay: Control
var selected: Array = []
var inspected_bridge:int=-1
var inspected_ruin:int=-1
var groups: Dictionary = {}
var hovered_entity: int = -1
var _hover_clock := 0.0
var focus := Vector2(24,24)
var yaw: float = 0.0
var camera_pitch_mode: String = "dynamic"
var camera_pitch: float = 30.0:
	set(value):
		camera_pitch = clampf(value, 20.0, 45.0)
		# Explicit diagnostic assignments keep their immediate fixed pose.
		camera_pitch_mode = "fixed"
		_camera_pitch_blending = false
var camera_effective_pitch: float = 30.0
var _camera_pitch_blending: bool = false
var camera_actual_distance: float = 44.0
var camera_base_fov: float = 42.0
var _camera_applied_fov: float = -1.0
var zoom_target_distance: float = 44.0
var _zoom_last_direction: int = 0
var _advancing_camera_motion: bool = false
var distance: float = 44.0:
	set(value):
		if not is_finite(value): return
		distance = maxf(value, .001)
		# Map starts, loads and explicit diagnostic poses remain immediate.
		if not _advancing_camera_motion:
			zoom_target_distance = distance
			_zoom_last_direction = 0
			_camera_pitch_blending = false
var camera_reference_height: float = 0.0
var camera_clearance_height: float = 0.0
var _camera_reference_sim_id: int = 0
var _camera_local_clearance = preload("res://scripts/camera_local_clearance.gd").new()
const CAMERA_OCCLUSION = preload("res://scripts/camera_occlusion.gd")
var _camera_terrain_transition = preload("res://scripts/camera_terrain_transition.gd").new()
var _scoreboard_sim_id := 0
var _scoreboard_result := ""
var _statistics_export_sim_id := 0
var _statistics_export_prefix := ""
var _navigation_attention_ids: Array = []
var _navigation_attention_sim_id := 0
var dragging: bool = false
var middle_drag: bool = false
var drag_start := Vector2.ZERO
var placing: bool = false
var placement_channel: String = "normal"
var command_mode: String = ""
var started: bool = false
var loading: bool = false
var loading_screen
var pve_paused: bool = false
var _player_music_paused := false
var wiki_return_to_entry: bool = true
var wiki_pause_before: bool = false
var wiki_return_to_settings: bool = false
var wiki_return_to_menu: bool = false
var entry_pause_before: bool = false
var settings_pause_before: bool = false
var settings_session_active: bool = false
var setup_session_active: bool = false
var setup_pause_before: bool = false
var setup_return_to_entry: bool = false
var audio_scene: String = ""
var _audio_attention_clock := 0.0
var _audio_attention_point := Vector2.INF
var _audio_attention_sim_id := 0
var _audible_movement_entities: Dictionary = {}
var _audibility_sim_id := 0
var _audibility_clock := 0.0
var _key_feedback_ms := -100000
var quit_pending: bool = false
var dev_mode: bool = false
var rules: Dictionary
var feedback: Array[String] = []
var feedback_clock: float = 0.0
var ui_clock: float = 0.0
var sim_cpu_ms: float = 0.0
var reserve_cpu_ms: float = 0.0
var menu_config := {"faction":"kestrel", "mode":"forest", "seed":73026, "match_options":{}}
var command_marker: MeshInstance3D
var marker_time: float = 0.0
var debug_panel: PanelContainer
var debug_metrics: Label
var debug_tools: VBoxContainer
var debug_tools_scroll: ScrollContainer
var debug_instant_toggle: CheckBox
var debug_faction_picker: OptionButton
var debug_building_report: Label
var debug_instant_build: bool = false
const DeveloperTools = preload("res://scripts/developer_tools.gd")
var debug_available: bool = false
var audio_browser_enabled: bool = true
var performance_overlay: CanvasLayer
var debug_clock: float = 0.0
var pointer_in_window: bool = true
var render_scale: float = 1.0
var graphics_quality: String = "balanced"
var dof_override: int = -1 # -1 follows the preset; 0/1 is the player's explicit choice.
var dof_toggle: CheckButton
var render_scale_option: OptionButton
var confirm: ConfirmationDialog
var pending_sell: int = -1
var capture_path: String = ""
var capture_clock: float = 0.0
var capture_delay: float = 3.0
var capture_done: bool = false
var golden_mode: bool = false
var golden_state: Dictionary = {}
var golden_frames: int = 0
var golden_output: String = ""
var golden_label: String = "g0_baseline"
var golden_hold: bool = false
var golden_h_offset: float = 8.10
var golden_view: String = "g0"
var golden_views: Array[String] = []
var golden_capture_dir: String = ""
var golden_capture_started: bool = false
var golden_fixture: String = "res://data/golden_visual_v1.json"
var benchmark: bool = false
var benchmark_seconds: float = 60.0
var benchmark_elapsed: float = 0.0
var frame_samples: Array[float] = []
var cpu_samples: Array[float] = []
var reserve_tick_samples: Array[float] = []
var frame_logic_samples: Array[float] = []
var benchmark_count: int = 224
var benchmark_resolution := Vector2i(1920,1080)
var benchmark_started_us: int = 0
var benchmark_previous_frame_us: int = 0
var frame_wall_seconds: float = 0.0
var benchmark_output:String=""
var world_cpu_samples:Array[float]=[]
var world_cpu_ms:float=0.0
var process_samples: Array[float] = []
var render_cpu_samples: Array[float] = []
var gpu_samples: Array[float] = []
var benchmark_peak_entities:int=0
var benchmark_events: Dictionary = {}
var benchmark_tick_count: int = 0
var benchmark_interval_sim_ms: float = 0.0
var benchmark_slow_frames: Array[Dictionary] = []
var benchmark_frames_over_budget: int = 0
var gameplay_performance: Node
var startup_timings: Dictionary = {}
# Set PAPER_FRONT_RENDER_OVERLAP=0 for the serial comparison path. Headless
# mechanics tests also remain serial unless they explicitly drive the worker.
var render_overlap_enabled:bool=OS.get_environment("PAPER_FRONT_RENDER_OVERLAP")!="0" and DisplayServer.get_name()!="headless"
var _simulation_overlap=preload("res://scripts/simulation_render_overlap.gd").new()
var _queued_simulation_delta:float=0.0
var overlap_wait_ms:float=0.0
var overlap_tick_count:int=0
var angle_clock: float = 0.0
var angle_test_id: int = -1
var angle_index: int = 0
const ANGLES: Array[float] = [0,79,80,81,90,135,180,-135,-90,-81,-80,-79]
const SAVE_PATH: String = "user://skirmish_v1.pfront"
const LENS = preload("res://scripts/miniature_lens.gd")
const TransportCommands = preload("res://scripts/transport_commands.gd")
const EntityPicking = preload("res://scripts/entity_picking.gd")
const Battlefields = preload("res://scripts/battlefield_catalog.gd")
const EDGE_PAN_PIXELS: float = 24.0
const CAMERA_SCENERY_CLEARANCE: float = 2.0
const DYNAMIC_PITCH_NEAR: float = 20.0
const DYNAMIC_PITCH_OVERVIEW: float = 60.0
const CAMERA_ZOOM_MIN: float = 8.0
const CAMERA_ZOOM_MAX: float = 110.0
const CAMERA_WHEEL_RATIO: float = 1.03
const CAMERA_ZOOM_TAU: float = .10
const CAMERA_ZOOM_LOG_SPEED: float = 1.5
const CAMERA_ZOOM_LOG_EPSILON: float = .0001
const CAMERA_PITCH_TAU: float = .12
const CAMERA_PITCH_SPEED: float = 90.0
const CAMERA_PITCH_EPSILON: float = .001
const RENDER_SCALES: Array[float] = [1.0,0.85,0.75]

func _ready() -> void:
	get_tree().auto_accept_quit = false
	# Keep every desktop popup on the native path, including the built-in
	# LineEdit context menu. Individual OptionButton overrides are insufficient
	# for the exported template's embedded parent-focus callback regression.
	if DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS):
		get_viewport().gui_embed_subwindows=false
	debug_available="--debug-panel" in OS.get_cmdline_user_args()
	get_window().mouse_entered.connect(func():pointer_in_window=true)
	get_window().mouse_exited.connect(func():pointer_in_window=false)
	rules = RulesLoader.load_rules()
	if rules.is_empty():
		push_error("规则配置验证失败："+"; ".join(RulesLoader.errors))
		get_tree().quit(2)
		return
	create_battlefield_viewport()
	camera = Camera3D.new()
	camera.fov=42
	camera.near=0.2
	camera.far=500
	lens=LENS.create()
	camera.attributes=lens
	battlefield_viewport.add_child(camera)
	camera.current=true
	var env := WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode=Environment.BG_COLOR
	environment.background_color=Color("443329")
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color("b1b8cd")
	environment.ambient_light_energy=0.20
	environment.ambient_light_sky_contribution=0.0
	environment.reflected_light_source=Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	environment.ssao_enabled=true
	environment.ssao_radius=1.1
	environment.ssao_intensity=1.50
	environment.ssao_power=1.6
	environment.ssao_detail=0.55
	environment.ssao_light_affect=0.15
	env.environment=environment
	add_child(env)
	key_light = DirectionalLight3D.new()
	key_light.rotation_degrees=Vector3(-38,-42,0)
	key_light.light_color=Color("ffdbb0")
	key_light.light_energy=1.55
	key_light.shadow_enabled=true
	key_light.shadow_bias=0.06
	key_light.shadow_normal_bias=0.85
	key_light.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	# Spend the first cascade on the visible tabletop, rather than the empty
	# space immediately in front of this elevated RTS camera.
	key_light.directional_shadow_split_1=0.60
	key_light.directional_shadow_max_distance=105.0
	key_light.directional_shadow_blend_splits=true
	add_child(key_light)
	audio=PaperAudio.new()
	add_child(audio)
	hud=PaperHUD.new()
	add_child(hud)
	hud.action.connect(handle_action)
	hud.set_debug_available(debug_available)
	set_audio_browser_enabled(audio_browser_enabled)
	performance_overlay=preload("res://scripts/performance_overlay.gd").new()
	performance_overlay.name="PerformanceOverlay"
	performance_overlay.fps_label=hud.fps_label
	performance_overlay.paper_theme=hud.theme_paper
	add_child(performance_overlay)
	loading_screen = preload("res://scripts/paper_loading_screen.gd").new()
	add_child(loading_screen)
	loading_screen.screen.theme = hud.theme_paper
	audio.unit_caption.connect(hud.show_voice)
	var overlay_layer:=CanvasLayer.new()
	overlay_layer.name="BattlefieldOverlay"
	# Routes and selection marks belong above the battlefield, below all HUD.
	overlay_layer.layer=2
	add_child(overlay_layer)
	overlay=preload("res://scripts/selection_overlay.gd").new()
	overlay.projector=self
	overlay.clip_contents=true
	overlay_layer.add_child(overlay)
	resize_battlefield()
	make_debug_panel()
	confirm=ConfirmationDialog.new()
	confirm.force_native=true
	confirm.title="出售最后一座建筑"
	confirm.dialog_text="出售后本阵营将立即失败。是否继续？"
	confirm.ok_button_text="出售并认输"
	confirm.cancel_button_text="保留建筑"
	confirm.confirmed.connect(func(): _flush_render_simulation(); report(sim.sell(pending_sell,true)))
	hud.add_child(confirm)
	# The entry menu hides the battlefield. Keep only a small initialization
	# scene here; the chosen map is built once when a match actually starts.
	if not start_match("dev",73026,"kestrel",false):
		get_tree().quit(2)
		return
	hud.show_menu(true)
	load_preferences()
	parse_arguments()
	if not started and not golden_mode and not benchmark:
		hud.show_menu(false)
		hud.show_entry(true)
	if "--verify-factions" in OS.get_cmdline_user_args():
		call_deferred("verify_exported_factions")
	if "--verify-wiki" in OS.get_cmdline_user_args():
		call_deferred("verify_exported_wiki")
	if "--verify-interactions" in OS.get_cmdline_user_args():
		call_deferred("verify_interactions")
	if "--verify-depth-of-field" in OS.get_cmdline_user_args():
		call_deferred("verify_depth_of_field")
	if "--verify-expansion" in OS.get_cmdline_user_args():
		call_deferred("verify_expansion")
	if "--verify-demo" in OS.get_cmdline_user_args():
		call_deferred("verify_demo")
	if "--verify-portable" in OS.get_cmdline_user_args():
		call_deferred("verify_portable")

	# The verified ownership interval is one synchronous renderer draw call.
	# A separately configured render thread uses the established serial path.
	render_overlap_enabled=render_overlap_enabled and RenderingServer.is_on_render_thread()
	if render_overlap_enabled:
		if _simulation_overlap.start()!=OK:
			render_overlap_enabled=false
			push_warning("Cannot start simulation overlap worker; using serial ticks")
		else:
			RenderingServer.frame_pre_draw.connect(_dispatch_render_simulation)
			RenderingServer.frame_post_draw.connect(_collect_render_simulation)

func verify_interactions()->void:
	var output:String="user://interaction_check.json"
	var args:PackedStringArray=OS.get_cmdline_user_args()
	for index in range(args.size()-1):
		if args[index]=="--interaction-output":output=args[index+1]
	await preload("res://scripts/interaction_performance_check.gd").run(self,output)

func verify_exported_factions() -> void:
	# Release templates omit the editor's --script switch. This diagnostic
	# runs through the real application and reads the embedded export resources.
	var report: Dictionary=preload("res://scripts/faction_export_check.gd").verify_game(self)
	print("EXPORTED_FACTIONS ",JSON.stringify(report))
	for failure in report.failures:push_error(failure)
	get_tree().quit(0 if report.failures.is_empty() else 1)

func verify_exported_wiki() -> void:
	var failures: Array[String]=[]
	var catalog_rules:Dictionary=RulesLoader.load_rules()
	var expected:Dictionary={}
	for kind in ["units","buildings"]:
		for id in catalog_rules.get(kind,{}):expected[id]=true
	if expected.is_empty():failures.append("Exported Wiki has no valid rule catalog")
	if not hud.entry_menu.visible:failures.append("Exported entry menu missing")
	audio.muted=true
	handle_action("wiki",null)
	for frame in range(3):await get_tree().process_frame
	var actual_count:int=hud.wiki.current_entries.size()
	if not hud.wiki.visible or actual_count!=expected.size():failures.append("Exported Wiki catalog incomplete")
	var seen:Dictionary={}
	for entry in hud.wiki.current_entries:
		if seen.has(entry.id):failures.append("Duplicate exported Wiki entry: "+entry.id)
		if not expected.has(entry.id):failures.append("Unexpected exported Wiki entry: "+entry.id)
		seen[entry.id]=true
		hud.wiki.select_entry(entry.id)
		if hud.wiki.preview.model_node==null or hud.wiki.displayed_rows.is_empty():failures.append("Exported Wiki page missing: "+entry.id)
	for id in expected:
		if not seen.has(id):failures.append("Missing exported Wiki entry: "+str(id))
	hud.wiki.close_catalog()
	if not hud.entry_menu.visible:failures.append("Wiki did not return to entry")
	handle_action("entry_play",null)
	if not hud.menu.visible:failures.append("Entry could not open match setup")
	if not start_match("dev",24,"kestrel",true):failures.append("Entry game could not start")
	print("EXPORTED_WIKI ",JSON.stringify({"entries":actual_count,"expected_entries":expected.size(),"failures":failures}))
	for failure in failures:push_error(failure)
	quit_game(0 if failures.is_empty() else 1)

func verify_depth_of_field() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var output: String = "user://depth_of_field_check"
	var index: int = args.find("--dof-output")
	if index >= 0 and index + 1 < args.size(): output = args[index + 1]
	await preload("res://scripts/depth_of_field_check.gd").run(self, output)

func verify_expansion() -> void:
	await preload("res://scripts/expansion_runtime_validation.gd").run(self)

func verify_demo() -> void:
	await preload("res://scripts/demo_runtime_validation.gd").run(self)

func verify_portable() -> void:
	await preload("res://scripts/portable_runtime_validation.gd").run(self)

func create_battlefield_viewport() -> void:
	var window_viewport: Viewport = get_viewport()
	battlefield_viewport=SubViewport.new()
	battlefield_viewport.name="BattlefieldViewport"
	battlefield_viewport.world_3d=window_viewport.world_3d
	battlefield_viewport.gui_disable_input=true
	battlefield_viewport.handle_input_locally=false
	battlefield_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	battlefield_viewport.msaa_3d=window_viewport.msaa_3d
	battlefield_viewport.screen_space_aa=window_viewport.screen_space_aa
	battlefield_viewport.use_taa=window_viewport.use_taa
	# Preserve authored geometry even when imported meshes contain baked LODs.
	battlefield_viewport.mesh_lod_threshold=0.0
	add_child(battlefield_viewport)
	# The root composites the battlefield texture and paper HUD. The battlefield
	# rectangle is owned by HUD layout, independently of the 3D render scale.
	window_viewport.disable_3d=true
	var layer_3d := CanvasLayer.new()
	layer_3d.layer=0
	add_child(layer_3d)
	battlefield_display=TextureRect.new()
	battlefield_display.name="BattlefieldDisplay"
	battlefield_display.mouse_filter=Control.MOUSE_FILTER_IGNORE
	battlefield_display.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	battlefield_display.stretch_mode=TextureRect.STRETCH_SCALE
	battlefield_display.texture=battlefield_viewport.get_texture()
	layer_3d.add_child(battlefield_display)
	window_viewport.size_changed.connect(func():call_deferred("resize_battlefield"))
	resize_battlefield()

func battlefield_rect() -> Rect2:
	if hud!=null:return hud.battlefield_rect()
	var size: Vector2 = get_viewport().get_visible_rect().size
	return Rect2(Vector2.ZERO,Vector2(maxf(2.0,size.x-PaperHUD.DOCK_WIDTH),size.y))

func resize_battlefield() -> void:
	if battlefield_viewport==null:return
	var rect: Rect2 = battlefield_rect()
	var logical_size: Vector2 = get_viewport().get_visible_rect().size
	# ViewportTexture.get_size() includes the canvas stretch scale once more.
	# Use client pixels so a 1920x1080 window never allocates a 2304x1296 scene.
	var pixels: Vector2i = get_window().size
	var dock_pixels: int = roundi((logical_size.x-rect.size.x)*float(pixels.x)/maxf(1.0,logical_size.x))
	var render_size := Vector2i(maxi(2,pixels.x-dock_pixels),maxi(2,pixels.y))
	if battlefield_viewport.size!=render_size:battlefield_viewport.size=render_size
	battlefield_display.position=rect.position
	battlefield_display.size=rect.size
	if overlay!=null:
		overlay.position=rect.position
		overlay.size=rect.size

func screen_to_battlefield(screen: Vector2) -> Vector2:
	var rect: Rect2 = battlefield_rect()
	return (screen-rect.position)*Vector2(battlefield_viewport.size)/rect.size

func battlefield_to_screen(pixel: Vector2) -> Vector2:
	var rect: Rect2 = battlefield_rect()
	return rect.position+pixel*rect.size/Vector2(battlefield_viewport.size)

func project_world_to_screen(point: Vector3) -> Vector2:
	return battlefield_to_screen(camera.unproject_position(point))

func set_render_scale(value: float) -> void:
	render_scale=clampf(value,0.5,1.0)
	# Scaling affects only the 3D buffer. The battlefield texture, HUD, mouse
	# coordinates and minimap retain their full client pixel dimensions.
	battlefield_viewport.scaling_3d_mode=Viewport.SCALING_3D_MODE_FSR if render_scale<1.0 else Viewport.SCALING_3D_MODE_BILINEAR
	battlefield_viewport.scaling_3d_scale=render_scale
	battlefield_viewport.fsr_sharpness=0.3
	if render_scale_option!=null:
		for i in range(RENDER_SCALES.size()):
			if is_equal_approx(render_scale,RENDER_SCALES[i]):render_scale_option.select(i);break

func set_graphics_quality(value: String) -> void:
	graphics_quality = value if value in ["native", "balanced", "performance"] else "balanced"
	if world != null and world.has_method("configure_quality"): world.configure_quality(graphics_quality)
	battlefield_viewport.msaa_3d = get_viewport().msaa_3d
	battlefield_viewport.screen_space_aa = get_viewport().screen_space_aa
	_apply_depth_of_field()

func _apply_depth_of_field() -> void:
	var enabled: bool = graphics_quality != "performance" if dof_override < 0 else dof_override == 1
	lens.dof_blur_near_enabled = enabled
	lens.dof_blur_far_enabled = enabled
	if dof_toggle != null: dof_toggle.set_pressed_no_signal(enabled)

func set_depth_of_field(enabled: bool) -> void:
	dof_override = 1 if enabled else 0
	_apply_depth_of_field()

func parse_arguments() -> void:
	var args:=OS.get_cmdline_user_args()
	if "--performance-case" in args:
		var config: Dictionary = {"case": "normal", "map": "mountains640", "seconds": 30.0, "resolution": Vector2i(1920, 1080), "render_scale": 1.0}
		config.fullscreen = "--performance-fullscreen" in args
		config.fixed_population = "--performance-variable-population" not in args
		for i in range(args.size() - 1):
			if args[i] == "--performance-case": config.case = args[i + 1]
			elif args[i] == "--performance-map": config.map = args[i + 1]
			elif args[i] == "--performance-output": config.output = args[i + 1]
			elif args[i] == "--performance-screenshot": config.screenshot = args[i + 1]
			elif args[i] == "--seconds": config.seconds = float(args[i + 1])
			elif args[i] == "--render-scale": config.render_scale = float(args[i + 1])
			elif args[i] == "--quality": config.quality = args[i + 1]
			elif args[i] == "--benchmark-size":
				var dimensions: PackedStringArray = args[i + 1].split("x")
				config.resolution = Vector2i(int(dimensions[0]), int(dimensions[1]))
		gameplay_performance = preload("res://scripts/gameplay_performance.gd").new()
		add_child(gameplay_performance)
		gameplay_performance.call_deferred("setup", self, config)
		return
	if "--benchmark" in args and "--render-scale" not in args:set_render_scale(1.0)
	for i in range(args.size()):
		if args[i]=="--capture" and i+1<args.size():capture_path=args[i+1]
		if args[i]=="--pitch" and i+1<args.size():camera_pitch=clampf(float(args[i+1]),20,45)
		if args[i]=="--benchmark":benchmark=true
		if args[i]=="--benchmark-output" and i+1<args.size():benchmark_output=args[i+1]
		if args[i]=="--capture-after" and i+1<args.size():capture_delay=float(args[i+1])
		if args[i]=="--seconds" and i+1<args.size():benchmark_seconds=float(args[i+1])
		if args[i]=="--stress":benchmark_count=256
		if args[i]=="--render-scale" and i+1<args.size():set_render_scale(float(args[i+1]))
		if args[i]=="--benchmark-size" and i+1<args.size():
			var dimensions: PackedStringArray = args[i+1].to_lower().split("x")
			if dimensions.size()==2 and dimensions[0].is_valid_int() and dimensions[1].is_valid_int():
				benchmark_resolution=Vector2i(maxi(1100,int(dimensions[0])),maxi(700,int(dimensions[1])))
		if args[i]=="--golden-capture" and i+1<args.size():golden_output=args[i+1]
		if args[i]=="--golden-label" and i+1<args.size():golden_label=args[i+1]
		if args[i]=="--golden-fixture" and i+1<args.size():golden_fixture=args[i+1]
		if args[i]=="--golden-view" and i+1<args.size():golden_view=args[i+1].to_lower()
		if args[i]=="--golden-views" and i+1<args.size():
			for view:String in args[i+1].to_lower().split(",",false):golden_views.append(view.strip_edges())
		if args[i]=="--golden-capture-dir" and i+1<args.size():golden_capture_dir=args[i+1]
	if "--golden-visual" in args:
		if not (OS.is_debug_build() or OS.has_feature("development")):
			print("GOLDEN_UNAVAILABLE visual capture requires a development build")
			quit_game(2)
			return
		golden_hold="--golden-hold" in args
		start_golden_visual()
		return
	if "--showcase" in args:
		if not start_match("handmade",73026,"rivet",true):return
		dev_mode=true
		sim.ai_enabled=false
		showcase_diorama("--ready-preview" in args)
		focus=Vector2(80,102)
		distance=42
		yaw=0.32
		hud.show_menu(false)
	hud.pitch_slider.set_value_no_signal(camera_pitch)
	hud.pitch_label.text="镜头俯角 %.0f°" % camera_pitch
	if benchmark:
		# Keep the native benchmark at its stated pixel resolution even if the
		# desktop would otherwise maximize or tile newly created windows.
		get_window().unresizable=true
		get_window().mode=Window.MODE_WINDOWED
		get_window().size=benchmark_resolution
		get_window().position=Vector2i(32,32)
		if not start_match("handmade",73026,"rivet",true):
			get_tree().quit(2)
			return
		dev_mode=true
		setup_benchmark()
		hud.show_menu(false)
	if "--menu-smoke" in args:call_deferred("run_menu_smoke")

func start_golden_visual() -> void:
	# This opt-in fixture never advances a normal match or reads camera preferences.
	if not (OS.is_debug_build() or OS.has_feature("development")):return
	if DisplayServer.get_name()=="headless" or RenderingServer.get_current_rendering_method()!="forward_plus":
		push_error("Golden capture requires a real display and Forward+ rendering")
		quit_game(2)
		return
	if golden_views.is_empty():golden_views.append(golden_view)
	for view:String in golden_views:
		if view not in ["g0","gameplay","gameplay_hq","gameplay_factory","gameplay_barracks","gameplay_empty"]:
			push_error("Unknown golden view: "+view)
			quit_game(2)
			return
	if golden_views.size()>1 and golden_capture_dir.is_empty():
		push_error("Multiple golden views require --golden-capture-dir")
		quit_game(2)
		return
	if "--render-scale" not in OS.get_cmdline_user_args():set_render_scale(1.0)
	if not FileAccess.file_exists(golden_fixture):
		push_error("Requested frozen scene does not exist: "+golden_fixture)
		quit_game(2)
		return
	golden_state=preload("res://scripts/golden_visual.gd").load_or_build(rules,golden_fixture)
	if not str(golden_state.get("error","")).is_empty():
		push_error(str(golden_state.error))
		quit_game(2)
		return
	golden_mode=true
	started=false
	benchmark=false
	sim=golden_state.sim
	hud.mini.invalidate_map()
	selected=golden_state.selection.duplicate()
	remove_child(world)
	world.queue_free()
	world=PaperWorld.new()
	add_child(world)
	world.setup(sim,camera)
	dof_override = -1 # Golden captures use preset defaults, independent of saved preferences.
	set_graphics_quality("native")
	preload("res://scripts/golden_visual.gd").apply_world(world,golden_state.manifest)
	var window:Window=get_window()
	window.unresizable=true
	window.mode=Window.MODE_WINDOWED
	window.size=Vector2i(1920,1080)
	window.position=Vector2i(32,32)
	apply_golden_view(golden_views[0])
	get_viewport().gui_release_focus()
	Input.warp_mouse(Vector2(8,88))
	print("GOLDEN_READY ",JSON.stringify({"fixture_hash":golden_state.fixture_hash,"tick":golden_state.tick,"entities":sim.entities.size(),"visual_time":0.0,"views":golden_views}))

func apply_golden_view(view: String) -> void:
	# Both views use the same frozen midgame fixture, never a claimed economic
	# opening. The gameplay view uses the regular RTS distance and plain HUD.
	golden_view=view
	golden_frames=0
	var gameplay_view: bool = view.begins_with("gameplay")
	selected=golden_state.selection.duplicate()
	if view=="gameplay_empty":selected.clear()
	elif view in ["gameplay_hq","gameplay_factory","gameplay_barracks"]:
		var role: String = view.trim_prefix("gameplay_")
		var nearest: int = -1
		var closest: float = INF
		for entity: Dictionary in sim.entities.values():
			if entity.team==0 and entity.kind=="building" and (sim.data_for(entity.spec).role==role or (role=="barracks" and sim.TechAvailability.producer_matches(sim, entity, role))):
				var separation: float = entity.pos.distance_squared_to(Vector2(73,102))
				if separation<closest:closest=separation;nearest=int(entity.id)
		selected.assign([nearest] if nearest>=0 else [])
	var pose:Dictionary=golden_state.camera
	focus=Vector2(73.0,102.0) if gameplay_view else pose.focus
	yaw=float(pose.yaw)
	camera_pitch=float(pose.pitch)
	distance=43.0 if gameplay_view else float(pose.distance)
	golden_h_offset=float(pose.h_offset)
	camera.fov=float(pose.get("fov",42.0))
	camera.near=float(pose.get("near",0.2))
	camera.far=float(pose.get("far",500.0))
	dev_mode=not gameplay_view
	get_window().title="Paper Front - Frozen RTS Gameplay" if gameplay_view else "Paper Front - Golden Visual G0"
	set_debug_visible(false)
	resize_battlefield()
	update_camera()
	world.elapsed=0.0
	world.sync(0.0,selected,{})
	hud.is_started=gameplay_view
	hud.tab="build"
	hud.cache_key=""
	hud.show_menu(false)
	hud.end_panel.hide()
	var status:String="" if gameplay_view else "Golden G0 · 固定状态\n参考图对比基准；镜头与仿真已冻结。"
	hud.refresh(sim,selected,camera,dev_mode,status,0.0,-1,debug_available)
	hud.build_scroll.scroll_vertical=0
	overlay.sim=sim
	overlay.camera=camera
	overlay.collisions=false
	overlay.command=""

func process_golden_visual() -> void:
	# Warm the renderer while all simulation and visual clocks remain frozen.
	world.sync(0.0,selected,{})
	overlay.refresh_overlay()
	hud.mini.queue_redraw()
	if not golden_capture_started and (not golden_output.is_empty() or not golden_capture_dir.is_empty()):
		golden_capture_started=true
		capture_golden_views()

func capture_golden_views() -> void:
	for view:String in golden_views:
		apply_golden_view(view)
		# Allow the real window resize and deferred HUD layout to finish first.
		await get_tree().process_frame
		resize_battlefield()
		update_camera()
		# Count actual completed draws after the scene and camera are ready.
		# All simulation, effects and model clocks remain frozen throughout.
		for frame:int in range(8):
			world.sync(0.0,selected,{})
			overlay.queue_redraw()
			hud.mini.queue_redraw()
			await RenderingServer.frame_post_draw
			golden_frames+=1
		var output:String=golden_output
		if not golden_capture_dir.is_empty():output=golden_capture_dir.path_join(golden_label+"_"+view+".png")
		DirAccess.make_dir_recursive_absolute(output.get_base_dir())
		var img:Image=get_viewport().get_texture().get_image()
		if img.is_empty():
			push_error("Golden renderer returned an empty image for "+view)
			quit_game(2)
			return
		var err:Error=img.save_png(output)
		var metadata:Dictionary=golden_metadata(img)
		var file:FileAccess=FileAccess.open(output.get_basename()+".json",FileAccess.WRITE)
		if file!=null:file.store_string(JSON.stringify(metadata,"\t"));file.close()
		print("GOLDEN_CAPTURE ",output," code=",err," dimensions=",img.get_size()," view=",view)
		if err!=OK or file==null:
			quit_game(2)
			return
	capture_done=true
	if not golden_hold:quit_game()

func golden_image_probe(img: Image) -> Dictionary:
	# Sample only the real 3D battlefield, so a readable HUD cannot make an
	# empty/loading battlefield pass the automated capture validity check.
	var colors:Dictionary={}
	var min_luma:float=1.0
	var max_luma:float=0.0
	var width:int=mini(img.get_width(),battlefield_viewport.size.x)
	var samples: int = 0
	for y:int in range(40):
		for x:int in range(60):
			var point := Vector2i(mini(width-1,roundi((float(x)+0.5)*width/60.0)),mini(img.get_height()-1,roundi((float(y)+0.5)*img.get_height()/40.0)))
			var logical: Vector2 = Vector2(point) * get_viewport().get_visible_rect().size / Vector2(img.get_size())
			if hud.blocks_world_scroll(logical):continue
			samples+=1
			var pixel:Color=img.get_pixel(point.x,point.y)
			colors[pixel.to_rgba32()]=true
			var luma:float=pixel.r*0.2126+pixel.g*0.7152+pixel.b*0.0722
			min_luma=minf(min_luma,luma)
			max_luma=maxf(max_luma,luma)
	return {"sample_count":samples,"unique_colors":colors.size(),"luminance_range":max_luma-min_luma,"region":"battlefield"}

func scenery_lod_metadata() -> Dictionary:
	var result: Dictionary = {}
	if world == null or world.landscape == null:return result
	for key: String in world.landscape._meshes:
		if key.begins_with("tree_"):
			var mesh: ArrayMesh = world.landscape._meshes[key]
			result[key] = mesh.get_meta("pine_lods", [])
	return result

func golden_metadata(img: Image) -> Dictionary:
	var hashes:Dictionary={}
	# A deliberate terrain round may use another map. Everything outside that
	# map and the resolved prop transforms must still be identical to baseline.
	var fixed_state: Dictionary = bytes_to_var(Marshalls.base64_to_raw(golden_state.manifest.state_base64))
	var map_state_hash: String = preload("res://scripts/golden_visual.gd")._hash_bytes(var_to_bytes(fixed_state.map))
	fixed_state.erase("map")
	var non_map_hash: String = preload("res://scripts/golden_visual.gd")._hash_bytes(var_to_bytes(fixed_state))
	var props_hash: String = JSON.stringify(golden_state.manifest.prop_batches,"",true).sha256_text()
	for path:String in ["res://project.godot","res://scripts/main.gd","res://scripts/miniature_lens.gd","res://scripts/golden_visual.gd","res://scripts/golden_landscape_capture.gd","res://scripts/paper_world.gd","res://scripts/volume_models.gd","res://scripts/landscape.gd","res://assets/textures/pigment_noise.png","res://assets/models/pine_0.res","res://assets/models/pine_1.res","res://assets/models/pine_2.res","res://scripts/pine_model.gd","res://scripts/bridge_craft.gd","res://scripts/scenery_scale.gd","res://scripts/cliff_craft.gd","res://scripts/paper_audio.gd","res://scripts/contextual_props.gd","res://scripts/foreground_grove.gd","res://scripts/north_context.gd","res://scripts/map_data.gd","res://scripts/paper_hud.gd","res://scripts/minimap.gd","res://scripts/paper_ui.gd","res://data/rules.json"]:
		if FileAccess.file_exists(path):hashes[path]=FileAccess.get_sha256(path)
	var sprite_paths: Dictionary = {"res://assets/cards/contours.json":true}
	for spec: Dictionary in sim.rules.units.values():
		if str(spec.art) in ["rifle","anti","engineer","demolition"]:
			for path: String in spec.animations.values():sprite_paths[path]=true
	for path: String in sprite_paths:
		if FileAccess.file_exists(path):hashes[path]=FileAccess.get_sha256(path)
	var position:Vector3=camera.position
	var rotation:Vector3=camera.rotation
	return {"scene":"gameplay" if golden_view.begins_with("gameplay") else "G0","view":golden_view,"scene_role":"frozen_midgame_gameplay" if golden_view.begins_with("gameplay") else "comparison_fixture","fixture_origin":"G0 frozen midgame state; not a normal economic opening","iteration":golden_label,"fixture_hash":golden_state.fixture_hash,"fixture":golden_state.manifest_path,"non_map_state_hash":non_map_hash,"map_state_hash":map_state_hash,"prop_batches_hash":props_hash,"tick":golden_state.tick,"simulation_time":sim.time,"visual_time":world.elapsed,"warmup_frames":golden_frames,"capture_barrier":"frame_post_draw after scene, window layout and camera setup","viewport":[img.get_width(),img.get_height()],"ui_canvas":[1600,900],"renderer":RenderingServer.get_current_rendering_method(),"godot":Engine.get_version_info().string,"selection":selected,"ui":{"dev_mode":dev_mode,"is_started":hud.is_started,"tab":hud.tab,"scroll_vertical":hud.build_scroll.scroll_vertical,"menu_visible":hud.menu.visible,"debug_visible":debug_panel.visible,"placing":placing,"command":command_mode},"camera":{"focus":[focus.x,focus.y],"pitch":camera_pitch,"yaw":yaw,"distance":distance,"h_offset":camera.h_offset,"fov":camera.fov,"near":camera.near,"far":camera.far,"position":[position.x,position.y,position.z],"rotation":[rotation.x,rotation.y,rotation.z]},"lighting":{"rotation":[key_light.rotation_degrees.x,key_light.rotation_degrees.y,key_light.rotation_degrees.z],"key_color":key_light.light_color.to_html(),"key_energy":key_light.light_energy,"ambient_color":environment.ambient_light_color.to_html(),"ambient_energy":environment.ambient_light_energy,"background":environment.background_color.to_html(),"tonemap":environment.tonemap_mode,"ssao":[environment.ssao_radius,environment.ssao_intensity,environment.ssao_power,environment.ssao_detail,environment.ssao_light_affect],"shadow_atlas":ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size"),"shadow_bias":key_light.shadow_bias,"shadow_normal_bias":key_light.shadow_normal_bias,"shadow_distance":key_light.directional_shadow_max_distance,"shadow_split_1":key_light.directional_shadow_split_1,"msaa":battlefield_viewport.msaa_3d},"render_settings":{"configured_shadow_filter_quality":ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"),"shadow_blur":key_light.shadow_blur,"shadow_enabled":key_light.shadow_enabled,"taa":battlefield_viewport.use_taa,"render_scale":render_scale},"photography":LENS.metadata(lens),"layout":{"dock_width":PaperHUD.DOCK_WIDTH,"battlefield_pixels":[battlefield_viewport.size.x,battlefield_viewport.size.y]},"image_check":golden_image_probe(img),"source_hashes":hashes,"scenery_lods":scenery_lod_metadata()}

func run_menu_smoke() -> void:
	# Exercises the actual exported runtime, where Godot's embedded Popup hash
	# regression occurs. This opt-in verification never changes a normal match.
	var failures: Array[String] = []
	var checks: int = 0
	var faction_checks: int = 0
	for frame in range(4):await get_tree().process_frame
	hud.show_menu(true)
	get_window().grab_focus()
	for frame in range(4):await get_tree().process_frame
	for faction_id in hud.faction_buttons:
		var card: Button = hud.faction_buttons[faction_id]
		for pressed: bool in [true, false]:
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = pressed
			click.position = card.get_global_rect().get_center()
			get_viewport().push_input(click, true)
		for frame in range(2):await get_tree().process_frame
		faction_checks += 1
		if hud.selected_faction() != faction_id or not card.button_pressed:
			failures.append("Faction card did not select: " + str(faction_id))
	for option: OptionButton in [hud.map_option]:
		for close_mode: String in ["select","escape","window_close","parent_hide"]:
			for repeat in range(3):
				hud.show_menu(true)
				get_window().grab_focus()
				for frame in range(2):await get_tree().process_frame
				for pressed: bool in [true,false]:
					var click := InputEventMouseButton.new()
					click.button_index = MOUSE_BUTTON_LEFT
					click.pressed = pressed
					click.position = option.get_global_rect().get_center()
					get_viewport().push_input(click,true)
				for frame in range(4):await get_tree().process_frame
				var popup: PopupMenu = option.get_popup()
				checks += 1
				if not popup.visible:failures.append(close_mode+": popup did not open")
				if DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS) and popup.is_embedded():failures.append(close_mode+": popup still embedded")
				var expected: int = (option.selected+1)%option.item_count
				if close_mode in ["select","escape"]:
					popup.set_focused_item(expected)
					var key := InputEventKey.new()
					key.keycode = KEY_ENTER if close_mode=="select" else KEY_ESCAPE
					key.pressed = true
					key.window_id = popup.get_window_id()
					Input.parse_input_event(key)
				elif close_mode=="window_close":popup.notification(NOTIFICATION_WM_CLOSE_REQUEST)
				else:hud.show_menu(false)
				for frame in range(4):await get_tree().process_frame
				if close_mode=="select" and option.selected!=expected:failures.append("selection did not change")
				if popup.visible:failures.append(close_mode+": popup did not close");popup.hide()
	confirm.popup_centered(Vector2i(440,180))
	for frame in range(4):await get_tree().process_frame
	if not confirm.visible:failures.append("confirmation did not open")
	confirm.hide()
	print("MENU_SMOKE ",JSON.stringify({"faction_cards":faction_checks,"popup_cycles":checks,"confirmation":true,"failures":failures}))
	quit_game(0 if failures.is_empty() else 1)

func start_match(mode: String, seed_value: int, faction: String, begin: bool=true, override_rules: Dictionary = {}, match_factions: Array[String] = [], hq_positions: Array[Vector2] = [], match_options: Dictionary = {}) -> bool:
	var timing := {"startup_begin": Time.get_ticks_usec()}
	if not _prepare_match(override_rules): return false
	timing.simulation_begin = Time.get_ticks_usec()
	if match_factions.is_empty(): sim.setup(rules,mode,seed_value,faction,mode!="dev",match_options)
	else: sim.setup_multiteam(rules, mode, seed_value, match_factions, false, hq_positions, Callable(), match_options)
	timing.landscape_begin = Time.get_ticks_usec()
	_create_match_world()
	world.setup(sim, camera)
	timing.landscape_end = Time.get_ticks_usec()
	return _finish_match(mode, seed_value, faction, begin, timing)

func start_match_with_progress(mode: String, seed_value: int, faction: String, progress: Callable, match_options: Dictionary = {}) -> bool:
	var timing := {"startup_begin": Time.get_ticks_usec()}
	if not _prepare_match({}): return false
	timing.simulation_begin = Time.get_ticks_usec()
	await sim.setup_with_progress(rules, mode, seed_value, faction, mode != "dev", func(fraction: float, stage: String): await progress.call(0.04 + fraction * 0.31, stage), match_options)
	if quit_pending: return false
	timing.landscape_begin = Time.get_ticks_usec()
	_create_match_world()
	await world.setup_with_progress(sim, camera, func(fraction: float, stage: String): await progress.call(0.35 + fraction * 0.57, stage))
	if quit_pending: return false
	timing.landscape_end = Time.get_ticks_usec()
	await progress.call(0.94, "部署总部与部队…")
	if quit_pending: return false
	return _finish_match(mode, seed_value, faction, true, timing)

func _prepare_match(override_rules: Dictionary) -> bool:
	if quit_pending: return false
	_flush_render_simulation()
	# A loaded save owns its historical rule snapshot; a new match always uses
	# the current editable configuration. Validate before touching the old game.
	var current_rules:Dictionary=RulesLoader.load_rules() if override_rules.is_empty() else override_rules
	if not override_rules.is_empty() and not RulesLoader.validate(current_rules, false).is_empty(): current_rules = {}
	if current_rules.is_empty():
		var error:String="规则配置验证失败，未开始新局："+"; ".join(RulesLoader.errors)
		push_error(error)
		report(error)
		return false
	_close_settings()
	setup_session_active = false
	_scoreboard_result="";_scoreboard_sim_id=0
	_statistics_export_sim_id=0;_statistics_export_prefix=""
	if hud.get("scoreboard")!=null:hud.scoreboard.close_scoreboard()
	pve_paused = false
	_player_music_paused=false
	if hud != null and hud.pause_button != null: hud.pause_button.text = "暂停"
	rules=current_rules
	audio.reset_field()
	audio.configure_units(rules)
	if world!=null:
		remove_child(world)
		world.queue_free()
	sim=WarSimulation.new()
	return true

func _create_match_world() -> void:
	building_pick_mesh_cache.clear()
	_configure_player_palette()
	world=preload("res://scripts/world_profile_probe.gd").new() if "--profile-world" in OS.get_cmdline_user_args() else PaperWorld.new()
	add_child(world)

func _configure_player_palette() -> void:
	var colors: Array = []
	for index in sim.match_options.get("slots", []).size():
		var slot: Dictionary = sim.match_options.slots[index]
		var value: String = str(slot.get("color", ""))
		colors.append(value if not value.is_empty() else PaperHUD.PLAYER_COLORS[posmod(index, PaperHUD.PLAYER_COLORS.size())])
	VolumeModels.configure_player_colors(colors)

func _finish_match(mode: String, seed_value: int, faction: String, begin: bool, timing: Dictionary) -> bool:
	if quit_pending: return false
	battlefield_display.show()
	set_graphics_quality(graphics_quality)
	selected.clear()
	inspected_bridge=-1
	inspected_ruin=-1
	groups.clear()
	audio.commander.reset(sim)
	feedback.clear()
	placing=false
	command_mode=""
	angle_test_id=-1
	menu_config={"mode":mode,"seed":seed_value,"faction":faction,"match_options":sim.get("match_options")}
	dev_mode=mode=="dev"
	_sync_developer_options()
	started=begin
	audio.set_map(str(sim.map.get("mode",mode)))
	_set_audio_scene("silent" if loading else "battle" if begin else "menu")
	if begin and hud.entry_menu!=null:hud.show_entry(false)
	hud.is_started=begin
	hud.mini.invalidate_map()
	hud.end_panel.hide()
	hud.cache_key=""
	var start_pos:Array=sim.map.starts[0]
	focus=Vector2(start_pos[0],start_pos[1]) + Vector2(4,3)
	distance=43 if mode!="dev" else 40
	yaw=0
	_refresh_camera_reference()
	update_camera()
	if begin:
		if mode == "campaign":
			post("晨雾中，无字桥被炸；重锤军团封锁东岸矿路。正典军团必须恢复补给线。")
			post("先点亮后方。左上方显示任务，点击「查看目标地点」可移动镜头。")
		else:
			post(("基地兵营已部署。资金 %d；选中基地兵营训练步兵，工兵负责建设。" if bool(sim.data_for(sim.factions[0]+"_hq").get("rebuildable", false)) else "总部已展开。资金 %d；电脑使用相同造价、前置和生产速度。") % int(sim.money[0]))
			post("开发工具已启用；作弊仅在试验场生效。" if dev_mode else ("左键选中基地兵营训练工兵；选工兵点击建筑卡选址施工。" if bool(sim.data_for(sim.factions[0]+"_hq").get("rebuildable", false)) else "左键选中总部，点电站卡片建造；完工后再点卡片，在地图左键放置。右键指挥部队。"))
	hud.refresh(sim,selected,camera,dev_mode,"\n".join(feedback),sim_cpu_ms,inspected_bridge,debug_available)
	var first_models_started:int=Time.get_ticks_usec()
	world.sync(0.0,selected,{})
	var first_models_finished:int=Time.get_ticks_usec()
	startup_timings = {"simulation_setup_ms": (timing.landscape_begin-timing.simulation_begin)/1000.0, "world_setup_ms": (timing.landscape_end-timing.landscape_begin)/1000.0, "match_total_ms": (Time.get_ticks_usec()-timing.startup_begin)/1000.0}
	startup_timings.simulation_detail=sim.startup_profile.duplicate()
	startup_timings.world_detail=world.startup_profile.duplicate()
	startup_timings.first_model_sync_ms=(first_models_finished-first_models_started)/1000.0
	return true

func _loading_progress(fraction: float, stage: String) -> void:
	if not quit_pending: loading_screen.update_progress(fraction, stage)
	if DisplayServer.get_name() == "headless":
		await get_tree().process_frame
	else:
		await RenderingServer.frame_post_draw

func _begin_loading(title: String, detail: String) -> void:
	if quit_pending: return
	_flush_render_simulation()
	_reset_camera_motion()
	loading = true
	performance_overlay.set_loading(true)
	dragging = false
	middle_drag = false
	overlay.active = false
	set_debug_visible(false)
	loading_screen.open(title, detail)
	battlefield_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	audio.reset_field()
	_set_audio_scene("silent")
	await _loading_progress(0.02, "准备战场…")

func _finish_loading(success: bool) -> void:
	if quit_pending: return
	if success:
		await _loading_progress(0.98, "准备进入战场…")
		if quit_pending: return
		battlefield_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		await _loading_progress(1.0, "加载完成")
		if quit_pending: return
	loading_screen.close()
	loading = false
	performance_overlay.set_loading(false)
	_sync_audio_scene()
	_update_navigation_attention()

func start_match_with_loading(mode: String, seed_value: int, faction: String, match_options: Dictionary = {}) -> bool:
	if loading or quit_pending: return false
	var faction_name: String = str(rules.factions.get(faction, {}).get("name", faction))
	var map_name: String = "无字桥补给线" if mode == "campaign" else Battlefields.display_name(mode)
	await _begin_loading("正在加载战场", "%s  ·  %s  ·  种子 %d" % [faction_name, map_name, seed_value])
	if quit_pending: return false
	var success: bool = await start_match_with_progress(mode, seed_value, faction, _loading_progress, match_options)
	if quit_pending: return false
	if success: hud.show_menu(false)
	await _finish_loading(success)
	return success and not quit_pending

func load_game_with_loading() -> void:
	if loading or quit_pending: return
	await _begin_loading("正在读取存档", "恢复战场、部队与生产队列")
	if quit_pending: return
	await _loading_progress(0.06, "读取存档数据…")
	if quit_pending: return
	var error: String = sim.load_game(SAVE_PATH)
	if not error.is_empty():
		await _finish_loading(false)
		if quit_pending: return
		if hud.entry_menu.visible: hud.entry_menu.show_notice(error)
		report(error)
		return
	rules = sim.rules
	audio.configure_units(rules)
	audio.commander.reset(sim)
	_configure_player_palette()
	await _loading_progress(0.35, "重建战场…")
	if quit_pending: return
	if world != null:
		remove_child(world)
		world.queue_free()
	world = PaperWorld.new()
	add_child(world)
	await world.setup_with_progress(sim, camera, func(fraction: float, stage: String): await _loading_progress(0.35 + fraction * 0.57, stage))
	if quit_pending: return
	world.restore_visual_memory(sim.visual_memory)
	audio.set_map(str(sim.map.get("mode","forest")))
	set_graphics_quality(graphics_quality)
	hud.mini.invalidate_map()
	selected.clear()
	groups.clear()
	inspected_bridge = -1
	inspected_ruin = -1
	hud.voice_label.hide()
	feedback.clear()
	dragging = false
	middle_drag = false
	placing = false
	command_mode = ""
	started = true
	hud.is_started = true
	battlefield_display.show()
	_close_settings()
	setup_session_active = false
	hud.show_entry(false)
	_scoreboard_result="";_scoreboard_sim_id=0
	_statistics_export_sim_id=0;_statistics_export_prefix=""
	if hud.get("scoreboard")!=null:hud.scoreboard.close_scoreboard()
	_player_music_paused=false
	pve_paused = false
	hud.pause_button.text = "暂停"
	dev_mode = sim.map.mode == "dev"
	_sync_developer_options()
	menu_config = {"mode":sim.map.mode, "seed":sim.map.seed, "faction":sim.factions[0],"match_options":sim.get("match_options")}
	hud.show_menu(false)
	hud.end_panel.hide()
	hud.cache_key = ""
	post("存档已恢复：资金、队列、命令、在途炮弹与桥梁进度延续。")
	await _loading_progress(0.94, "恢复部队与建筑…")
	if quit_pending: return
	_refresh_camera_reference()
	update_camera()
	hud.refresh(sim, selected, camera, dev_mode, "\n".join(feedback), sim_cpu_ms, inspected_bridge, debug_available)
	world.sync(0.0, selected, {})
	await _finish_loading(true)

func _physics_process(delta: float) -> void:
	if quit_pending:return
	_collect_render_simulation()
	if loading or sim==null or not started or pve_paused or (setup_session_active and hud.menu.visible):return
	if not render_overlap_enabled:
		_step_simulation_now(delta)
		return
	# Keep every fixed tick. Earlier catch-up ticks execute before scene reads;
	# only the final due tick overlaps submission of the already-built frame.
	if _queued_simulation_delta>0:_step_simulation_now(_queued_simulation_delta)
	_queued_simulation_delta=delta

func _step_simulation_now(delta:float)->void:
	var before:int=Time.get_ticks_usec()
	sim.step(delta)
	_record_simulation_tick(float(Time.get_ticks_usec()-before)/1000.0)

func _record_simulation_tick(duration_ms:float)->void:
	sim_cpu_ms=duration_ms
	reserve_cpu_ms = 0.0
	if gameplay_performance != null and gameplay_performance.has_method("after_tick"):
		var reserve_started: int = Time.get_ticks_usec()
		gameplay_performance.after_tick()
		reserve_cpu_ms=float(Time.get_ticks_usec()-reserve_started)/1000.0
	if benchmark:
		benchmark_tick_count+=1
		benchmark_interval_sim_ms+=sim_cpu_ms
		if benchmark_elapsed>5:
			cpu_samples.append(sim_cpu_ms)
			reserve_tick_samples.append(reserve_cpu_ms)

func _dispatch_render_simulation()->void:
	if loading:return
	if _queued_simulation_delta<=0 or _simulation_overlap.active:return
	var delta:float=_queued_simulation_delta
	_queued_simulation_delta=0.0
	if quit_pending or sim==null:return
	_simulation_overlap.dispatch(sim,delta)

func _collect_render_simulation()->void:
	if not _simulation_overlap.active:return
	var before:int=Time.get_ticks_usec()
	var duration_ms:float=_simulation_overlap.collect()
	overlap_wait_ms+=float(Time.get_ticks_usec()-before)/1000.0
	overlap_tick_count+=1
	# Reserves, audio/event readers and UI remain on the main thread.
	_record_simulation_tick(duration_ms)

func _flush_render_simulation()->void:
	_collect_render_simulation()
	if _queued_simulation_delta<=0:return
	var delta:float=_queued_simulation_delta
	_queued_simulation_delta=0.0
	if sim!=null and started:_step_simulation_now(delta)

func _exit_tree()->void:
	# Children may already be leaving: join without invoking HUD/test callbacks.
	_simulation_overlap.close()
	_queued_simulation_delta=0.0

func _process(delta: float) -> void:
	if quit_pending:return
	_collect_render_simulation()
	if audio != null and audio.commander != null:
		audio.commander.enabled = started and not loading and not pve_paused and sim != null and sim.result.is_empty() and not hud.modal_catalog_visible()
	if loading:return
	if sim==null:return
	_sync_audio_scene()
	if started and not sim.result.is_empty() and _scoreboard_sim_id==sim.get_instance_id() and _scoreboard_result==sim.result and not benchmark and not golden_mode:
		battlefield_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
		return
	audio.music.set_combat_paused(pve_paused or hud.modal_catalog_visible())
	var logic_started_us:int=Time.get_ticks_usec() if benchmark else 0
	if golden_mode:
		process_golden_visual()
		return
	var camera_changed: bool = _advance_camera_zoom(delta)
	if hud.modal_catalog_visible():
		dragging=false;middle_drag=false;overlay.active=false
		# A settings slider can animate the paused scene. Freeze it again once
		# the camera settles, so an idle menu keeps its existing rendering cost.
		battlefield_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS if camera_changed else SubViewport.UPDATE_DISABLED
		if camera_changed:
			update_camera(delta)
			world.sync(0.0,selected,{})
			overlay.refresh_overlay()
		audio.update_battlefield(delta,{},focus)
		return
	if battlefield_viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED:
		battlefield_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	if dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		dragging=false
		overlay.active=false
	if middle_drag and not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):middle_drag=false
	camera_controls(delta)
	update_camera(delta)
	var placement:Dictionary={}
	if placing and battlefield_rect().has_point(get_viewport().get_mouse_position()):
		var ground:Vector2=ground_at(get_viewport().get_mouse_position())
		var bo:Dictionary=sim.order_for_team(0,placement_channel)
		if not bo.is_empty() and ground.is_finite():
			var p:=sim.snap_build_position(0,ground,placement_channel)
			var reason: String = sim.placement_error(0,p,placement_channel)
			var quarters: int=int(bo.get("rotation_quarters",bo.get("rail_rotation",0)))
			placement={"pos":p,"spec":bo.spec,"valid":reason.is_empty(),"channel":placement_channel,"builder":int(bo.get("builder",-1)),"rail_rotation":int(bo.get("rail_rotation",0)),"rotation_quarters":quarters}
			hud.show_placement_reason(reason, str(sim.data_for(bo.spec).get("role", "")),quarters)
		elif bo.is_empty():placing=false
	if not placing: hud.show_placement_reason("", "", 0)
	var world_start:int=Time.get_ticks_usec()
	world.sync(0.0 if pve_paused else delta,selected,placement)
	world_cpu_ms=float(Time.get_ticks_usec()-world_start)/1000.0
	if benchmark and benchmark_elapsed>5:world_cpu_samples.append(world_cpu_ms)
	_update_audio_attention(delta)
	audio.update_battlefield(delta, _movement_sound_entities(delta) if started and not pve_paused and sim.result.is_empty() else {}, focus)
	for ev in sim.events:
		audio.commander.observe_event(ev, sim)
		var event_kind:String=str(ev.get("kind",""))
		if int(ev.get("team",0)) == 0 or sim.position_visible_to(0,ev.get("pos",Vector2.ZERO),"air" if float(ev.get("height",0.0)) > 2.0 else "naval" if MapData.terrain_at(sim.map,ev.get("pos",Vector2.ZERO)) == MapData.WATER else "ground"):
			audio.play_event(ev)
			audio.music.observe_combat(ev)
		if event_kind in ["produce", "rearm"] and sim.entities.has(int(ev.get("id", -1))):
			var ready_unit: Dictionary = sim.entities[int(ev.id)]
			if int(ready_unit.team) == 0: audio.play_unit_voice(str(ready_unit.spec), "ready", {"id":int(ready_unit.id),"team":int(ready_unit.team),"pos":ready_unit.pos})
		elif event_kind == "return" and int(ev.get("team", -1)) == 0:
			audio.play_unit_voice(str(ev.get("spec", "")), "return", ev)
		if benchmark:benchmark_events[event_kind]=int(benchmark_events.get(event_kind,0))+1
	audio.music.update_engagement(sim)
	# Commands such as selling the last base may end a match between ticks.
	# Consume their logical events before presentation drains the shared queue.
	sim.statistics.sample(sim)
	sim.events.clear()
	while not sim.notices.is_empty(): post(str(sim.notices.pop_front()))
	selected=selected.filter(func(id):return sim.entities.has(id) and int(sim.entities[id].get("transport_id",-1))<0 and sim.entity_visible_to(0,int(id)))
	prune_control_groups()
	if started and not sim.result.is_empty() and not benchmark and not golden_mode:
		_show_battle_scoreboard()
		return
	ui_clock+=delta
	feedback_clock+=delta
	if ui_clock>=0.15:
		ui_clock=0
		hud.refresh(sim,selected,camera,dev_mode,"\n".join(feedback),sim_cpu_ms,inspected_bridge,debug_available)
		hud.refresh_groups(groups)
		_update_battle_information()
		if selected.is_empty() and inspected_ruin<=sim.RUIN_TARGET_BASE:
			var ruin: Dictionary = sim.ruin_by_target(inspected_ruin)
			if not ruin.is_empty() and float(ruin.hp)>0:
				hud.selection_panel.show()
				hud.info_label.text={"wall":"中立低石墙","tree":"中立树木"}.get(str(ruin.kind),"中立房屋 / 半毁建筑")+" · HP %d/%d\nH 后左键强制攻击；摧毁后开放通路"%[int(ruin.hp),int(ruin.max_hp)]
	debug_clock+=delta
	if debug_panel.visible and debug_clock>=0.25:
		debug_clock=0.0
		refresh_debug_metrics()
	overlay.sim=sim
	overlay.camera=camera
	overlay.selection=selected
	if not dev_mode:overlay.collisions=false
	overlay.command="place" if placing else command_mode
	overlay.refresh_overlay()
	if marker_time>0:
		marker_time-=delta
		if command_marker!=null:command_marker.visible=marker_time>0
	if dev_mode and angle_test_id>=0 and sim.entities.has(angle_test_id):
		angle_clock+=delta
		if angle_clock>=2:
			angle_clock=0
			angle_index=(angle_index+1)%ANGLES.size()
			sim.entities[angle_test_id].alpha=ANGLES[angle_index]
	if not capture_path.is_empty() and not capture_done:
		capture_clock+=delta
		if capture_clock>capture_delay:
			capture_done=true
			await RenderingServer.frame_post_draw
			var img:=get_viewport().get_texture().get_image()
			var err:=img.save_png(capture_path)
			print("CAPTURE ",capture_path," code=",err)
			if not benchmark:quit_game()
	if benchmark:
		benchmark_elapsed=float(Time.get_ticks_usec()-benchmark_started_us)/1000000.0
		var now_us:int=Time.get_ticks_usec()
		if benchmark_elapsed>5 and benchmark_previous_frame_us>0:
			var frame_ms:float=float(now_us-benchmark_previous_frame_us)/1000.0
			frame_samples.append(frame_ms)
			if frame_ms>1000.0/60.0:benchmark_frames_over_budget+=1
			if frame_ms>33.333 and benchmark_slow_frames.size()<100:
				benchmark_slow_frames.append({"at_wall_seconds":benchmark_elapsed,"frame_ms":frame_ms,"interval_simulation_cpu_ms":benchmark_interval_sim_ms,"world_sync_cpu_ms":world_cpu_ms,"engine_process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,"entities":sim.entities.size(),"fire_events":benchmark_events.get("fire",0)})
			process_samples.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
			var viewport_rid:RID=battlefield_viewport.get_viewport_rid()
			var composite_rid:RID=get_viewport().get_viewport_rid()
			var render_ms:float=RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid)+RenderingServer.viewport_get_measured_render_time_cpu(composite_rid)+RenderingServer.get_frame_setup_time_cpu()
			var gpu_ms:float=RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid)+RenderingServer.viewport_get_measured_render_time_gpu(composite_rid)
			if render_ms>0:render_cpu_samples.append(render_ms)
			if gpu_ms>0:gpu_samples.append(gpu_ms)
		benchmark_previous_frame_us=now_us
		benchmark_interval_sim_ms=0.0
		benchmark_peak_entities=maxi(benchmark_peak_entities,sim.entities.size())
		if benchmark_elapsed>=benchmark_seconds:finish_benchmark()
		if benchmark_elapsed>5:frame_logic_samples.append((Time.get_ticks_usec()-logic_started_us)/1000.0)

func _set_audio_scene(scene: String) -> void:
	if audio_scene==scene:return
	audio_scene=scene
	audio.set_scene(scene)

func _update_audio_attention(delta: float) -> void:
	if not audio.has_method("set_attention"):return
	if not selected.is_empty():
		audio.set_attention(selected,focus)
		_audio_attention_clock=0.0
		return
	_audio_attention_clock=maxf(0.0,_audio_attention_clock-delta)
	if _audio_attention_clock<=0.0 or _audio_attention_sim_id!=sim.get_instance_id():
		_audio_attention_sim_id=sim.get_instance_id()
		_audio_attention_point=focus
		var pointer: Vector2=get_viewport().get_mouse_position()
		if battlefield_rect().has_point(pointer):
			var hovered: Vector2=ground_at(pointer)
			if hovered.is_finite():_audio_attention_point=hovered
		# Audio focus can follow at 10 Hz without another terrain ray every frame.
		_audio_attention_clock=.1
	audio.set_attention([],_audio_attention_point)

func _show_battle_scoreboard() -> void:
	if _scoreboard_sim_id==sim.get_instance_id() and _scoreboard_result==sim.result:return
	_collect_render_simulation()
	_queued_simulation_delta=0.0
	pve_paused=true
	dragging=false;middle_drag=false;placing=false;overlay.active=false
	audio.reset_field()
	audio.play_event({"kind":"result","result":sim.result})
	battlefield_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	battlefield_display.hide()
	_scoreboard_sim_id=sim.get_instance_id();_scoreboard_result=sim.result
	hud.end_panel.hide()
	if hud.get("scoreboard")!=null:hud.scoreboard.show_result(sim.match_statistics(),sim.result)
	_export_match_statistics()

func _export_match_statistics() -> void:
	if sim==null or sim.map.is_empty():return
	if _statistics_export_sim_id!=sim.get_instance_id():
		_statistics_export_sim_id=sim.get_instance_id()
		var stamp:String=Time.get_datetime_string_from_system().replace(":","-").replace("T","_")
		_statistics_export_prefix="user://match_reports/%s_%s_%d"%[stamp,str(sim.map.get("mode","match")),Time.get_ticks_usec()]
	var exported:Dictionary=preload("res://scripts/match_statistics_exporter.gd").export_snapshot(sim.match_statistics(),_statistics_export_prefix)
	if hud!=null and hud.get("scoreboard")!=null:
		if bool(exported.get("ok",false)):
			hud.scoreboard.show_export_status("统计已导出（JSON / CSV）："+ProjectSettings.globalize_path("user://match_reports"),true)
		else:
			hud.scoreboard.show_export_status("统计导出失败："+str(exported.get("error","未知错误")),false)

func _sync_audio_scene() -> void:
	if quit_pending:return
	if audio!=null and sim!=null and not sim.map.is_empty():audio.set_map(str(sim.map.get("mode","forest")))
	if loading:_set_audio_scene("silent")
	elif hud.entry_menu.visible or not started:_set_audio_scene("menu")
	elif not sim.result.is_empty():_set_audio_scene(sim.result)
	else:_set_audio_scene("battle")
	if audio.music.has_method("set_playback_paused") and not audio.preview_active:
		var paused_context:bool=pve_paused and not hud.entry_menu.visible and not hud.menu.visible and not hud.wiki.visible
		audio.music.set_playback_paused(started and sim.result.is_empty() and (paused_context or (_player_music_paused and pve_paused)))

func _update_navigation_attention() -> void:
	if sim==null or not sim.has_method("set_player_navigation_priority"):return
	if _navigation_attention_sim_id==sim.get_instance_id() and _navigation_attention_ids==selected:return
	_navigation_attention_sim_id=sim.get_instance_id()
	_navigation_attention_ids=selected.duplicate()
	sim.set_player_navigation_priority(selected)

func _movement_sound_entities(delta: float) -> Dictionary:
	if not sim.vision_enabled:return sim.entities
	_audibility_clock-=delta
	if _audibility_clock<=0.0 or _audibility_sim_id!=sim.get_instance_id():
		_audibility_sim_id=sim.get_instance_id();_audibility_clock=.15
		_audible_movement_entities.clear()
		for id:Variant in sim.entities:
			var entity:Dictionary=sim.entities[id]
			if int(entity.team)==0 or sim.entity_visible_to(0,int(id)):_audible_movement_entities[id]=entity
	return _audible_movement_entities

func _refresh_camera_reference() -> void:
	# Cache the map-wide ceiling for cursor ray bounds and diagnostics only.
	# The camera targets local terrain; visual cutaways clear its central view.
	var anchor: Vector2 = focus
	var starts: Array = sim.map.get("starts", [])
	if not starts.is_empty(): anchor = Vector2(float(starts[0][0]), float(starts[0][1]))
	camera_reference_height = MapData.height_at(sim.map, anchor)
	var scenery_top: float = camera_reference_height
	for row: Array in sim.map.heights:
		for height: float in row: scenery_top = maxf(scenery_top, height)
	# Static bounds include tall roofs and crowns when bounding cursor rays.
	if is_instance_valid(world) and is_instance_valid(world.landscape):
		var pending: Array[Node] = [world.landscape]
		while not pending.is_empty():
			var node: Node = pending.pop_back()
			if node is VisualInstance3D:
				var bounds: AABB = node.global_transform * node.get_aabb()
				scenery_top = maxf(scenery_top, bounds.end.y)
			for child: Node in node.get_children(): pending.append(child)
	camera_clearance_height = scenery_top + CAMERA_SCENERY_CLEARANCE
	_camera_local_clearance.rebuild(world.landscape if is_instance_valid(world) else null)
	_camera_reference_sim_id = sim.get_instance_id()
	_camera_terrain_transition.reset()

func _desired_camera_pitch() -> float:
	if camera_pitch_mode == "fixed": return camera_pitch
	if distance < DYNAMIC_PITCH_NEAR: return lerpf(10.0, 20.0, smoothstep(CAMERA_ZOOM_MIN, DYNAMIC_PITCH_NEAR, distance))
	return lerpf(20.0, 45.0, smoothstep(DYNAMIC_PITCH_NEAR, DYNAMIC_PITCH_OVERVIEW, distance))

func effective_camera_pitch() -> float:
	return camera_effective_pitch if _camera_pitch_blending else _desired_camera_pitch()

func _queue_camera_zoom(direction: int, factor: float = 1.0) -> void:
	if direction == 0 or not is_finite(factor): return
	var amount: float = absf(factor) if factor != 0.0 else 1.0
	var sense: int = 1 if direction > 0 else -1
	# Reverse from the currently displayed view, discarding unfinished travel.
	var base: float = distance if _zoom_last_direction != 0 and _zoom_last_direction != sense else zoom_target_distance
	var min_log: float = log(CAMERA_ZOOM_MIN)
	var max_log: float = log(CAMERA_ZOOM_MAX)
	var target_log: float = clampf(log(base)+sense*amount*log(CAMERA_WHEEL_RATIO),min_log,max_log)
	# Keep numeric endpoints exact; exp(log(limit)) can cross them by an ULP.
	zoom_target_distance = CAMERA_ZOOM_MIN if target_log <= min_log else CAMERA_ZOOM_MAX if target_log >= max_log else exp(target_log)
	_zoom_last_direction = sense

func _camera_eased_error(error: float, delta: float, tau: float, speed: float) -> float:
	# Solve both phases exactly, including frames crossing their boundary.
	var linear_time: float = minf(delta,maxf(0.0,(error-speed*tau)/speed))
	return (error-speed*linear_time)*exp(-(delta-linear_time)/tau)

func _advance_camera_zoom(delta: float) -> bool:
	if delta <= 0.0 or not is_finite(delta): return false
	var before_distance: float = distance
	var before_pitch: float = effective_camera_pitch()
	var current_log: float = log(distance)
	var target_log: float = log(zoom_target_distance)
	var error: float = target_log-current_log
	var remaining: float = absf(error)
	if remaining > CAMERA_ZOOM_LOG_EPSILON:
		# Closed-form rate-limited exponential motion. Splitting the constant
		# speed and easing phases makes equal wall time agree at every FPS.
		remaining = _camera_eased_error(remaining,delta,CAMERA_ZOOM_TAU,CAMERA_ZOOM_LOG_SPEED)
		current_log = target_log-signf(error)*remaining
		_advancing_camera_motion = true
		distance = zoom_target_distance if remaining <= CAMERA_ZOOM_LOG_EPSILON else exp(current_log)
		_advancing_camera_motion = false
	elif distance != zoom_target_distance:
		_advancing_camera_motion = true
		distance = zoom_target_distance
		_advancing_camera_motion = false
	if distance == zoom_target_distance: _zoom_last_direction = 0
	if _camera_pitch_blending:
		var desired: float = _desired_camera_pitch()
		var angle_error: float = desired-camera_effective_pitch
		camera_effective_pitch = desired-signf(angle_error)*_camera_eased_error(absf(angle_error),delta,CAMERA_PITCH_TAU,CAMERA_PITCH_SPEED)
		if absf(camera_effective_pitch-desired) <= CAMERA_PITCH_EPSILON:
			camera_effective_pitch = desired
			_camera_pitch_blending = false
	var changed: bool = distance != before_distance or effective_camera_pitch() != before_pitch
	if changed and hud != null and hud.settings.visible: _sync_pitch_controls()
	return changed

func _start_camera_pitch_transition(from: float) -> void:
	camera_effective_pitch = from
	_camera_pitch_blending = absf(_desired_camera_pitch()-from) > CAMERA_PITCH_EPSILON

func _reset_camera_motion() -> void:
	zoom_target_distance = distance
	_zoom_last_direction = 0
	_camera_pitch_blending = false

func _sync_pitch_controls() -> void:
	hud.pitch_slider.set_value_no_signal(camera_pitch)
	hud.pitch_label.text = "固定俯角 %.0f°" % camera_pitch if camera_pitch_mode == "fixed" else "动态俯角 %.0f°" % effective_camera_pitch()
	if hud.settings != null and hud.settings.pitch_mode != null:
		hud.settings.set_pitch_controls(camera_pitch_mode, camera_pitch, effective_camera_pitch())

func update_camera(delta: float=-1.0) -> void:
	if _camera_reference_sim_id != sim.get_instance_id(): _refresh_camera_reference()
	camera_effective_pitch = effective_camera_pitch()
	var pitch:float=deg_to_rad(camera_effective_pitch)
	var pose:Dictionary=_camera_terrain_transition.pose(sim,focus,distance,yaw,pitch,_camera_local_clearance,delta)
	var target:Vector3=pose.target
	camera_actual_distance=float(pose.actual_distance)
	var horizontal:float=camera_actual_distance*cos(pitch)
	camera.position=target+Vector3(sin(yaw)*horizontal,camera_actual_distance*sin(pitch),cos(yaw)*horizontal)
	camera.look_at(target,Vector3.UP)
	# Preserve the visual scale of the logical zoom even above tall scenery.
	# Explicit fixture FOV changes reset the base; our own compensation never
	# becomes the base of the following frame.
	if _camera_applied_fov<0.0 or not is_equal_approx(camera.fov,_camera_applied_fov):camera_base_fov=camera.fov
	camera.fov=rad_to_deg(2.0*atan(tan(deg_to_rad(camera_base_fov)*.5)*distance/camera_actual_distance))
	_camera_applied_fov=camera.fov
	CAMERA_OCCLUSION.update(camera, target)
	# The camera now looks at the centre of its own unobstructed battlefield.
	camera.h_offset=0.0
	var ground_target := Vector3(focus.x,MapData.height_at(sim.map,focus),focus.y)
	LENS.update(camera,lens,ground_target,distance)
	# The overview can move the focal plane beyond the original 105m atlas.
	# Keep its buildings shadowed throughout the supported zoom range.
	key_light.directional_shadow_max_distance=maxf(105.0,camera_actual_distance*1.7)
	if hud != null and hud.mini != null and hud.mini.has_method("update_camera_outline"):
		hud.mini.update_camera_outline(camera,sim,target.y)

func camera_controls(delta: float) -> void:
	if benchmark or golden_mode or hud.menu.visible or hud.modal_catalog_visible() or not started or not sim.result.is_empty():return
	if not get_window().has_focus():return
	var movement:=camera_keyboard_direction()
	if Input.is_physical_key_pressed(KEY_Q):yaw+=delta*1.05
	if Input.is_physical_key_pressed(KEY_E):yaw-=delta*1.05
	if pointer_in_window and not dragging and not middle_drag:
		var logical_size: Vector2 = get_viewport().get_visible_rect().size
		var pixels: Vector2 = Vector2(get_window().size)
		var mouse_pixels: Vector2 = get_viewport().get_mouse_position()*pixels/logical_size
		movement+=edge_pan_direction(mouse_pixels,pixels)
	if movement.length_squared()>1.0:movement=movement.normalized()
	movement=movement.rotated(-yaw)
	focus+=movement*delta*distance*0.45
	focus.x=clampf(focus.x,2,sim.map.size-2)
	focus.y=clampf(focus.y,2,sim.map.size-2)

func camera_keyboard_direction() -> Vector2:
	return Vector2(Input.get_axis("camera_pan_left","camera_pan_right"),Input.get_axis("camera_pan_forward","camera_pan_backward"))

func edge_pan_direction(mouse: Vector2, window_size: Vector2) -> Vector2:
	# The right edge belongs to the whole window, beyond the command dock.
	if not Rect2(Vector2.ZERO,window_size).has_point(mouse):return Vector2.ZERO
	var direction:=Vector2.ZERO
	if mouse.x<EDGE_PAN_PIXELS:direction.x=-1.0
	elif mouse.x>=window_size.x-EDGE_PAN_PIXELS:direction.x=1.0
	if mouse.y<EDGE_PAN_PIXELS:direction.y=-1.0
	elif mouse.y>=window_size.y-EDGE_PAN_PIXELS:direction.y=1.0
	return direction.normalized()

func _open_settings() -> void:
	if hud.settings.visible: return
	settings_pause_before = pve_paused
	settings_session_active = true
	if started: pve_paused = true
	dragging = false
	middle_drag = false
	overlay.active = false
	var values: Dictionary = audio.get_mix()
	values.merge({"quality": graphics_quality, "render_scale": render_scale, "depth_of_field": lens.dof_blur_near_enabled, "pitch": camera_pitch, "pitch_mode": camera_pitch_mode, "effective_pitch": effective_camera_pitch(), "fullscreen": get_window().mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN], "ambient_occlusion": environment.ssao_enabled, "shadows": key_light.shadow_enabled, "debug_enabled": debug_available, "audio_browser_enabled": audio_browser_enabled, "in_match": started, "can_save": started})
	hud.settings.open(values)

func _open_match_setup() -> void:
	_close_settings()
	if setup_session_active and hud.menu.visible: return
	setup_pause_before = pve_paused
	setup_return_to_entry = hud.entry_menu.visible
	setup_session_active = true
	if started: pve_paused = true
	dragging = false
	middle_drag = false
	overlay.active = false
	hud.show_entry(false)
	hud.show_menu(true)

func _close_match_setup() -> void:
	hud.show_menu(false)
	if not setup_session_active: return
	setup_session_active = false
	pve_paused = setup_pause_before
	if setup_return_to_entry: hud.show_entry(true)
	hud.pause_button.text = "继续" if pve_paused else "暂停"

func _close_settings() -> void:
	if hud == null or hud.settings == null: return
	if hud.settings.visible: hud.settings.close()
	# Loading blocks general actions, including the close signal. Complete the
	# same transaction directly when that signal could not reach its handler.
	if settings_session_active: _settings_closed()

func _settings_closed() -> void:
	if not settings_session_active: return
	settings_session_active = false
	pve_paused = settings_pause_before
	hud.pause_button.text = "继续" if pve_paused else "暂停"
	save_preferences()

func _close_top_popup() -> bool:
	var pending: Array[Node] = [hud]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if (node is Popup or node is AcceptDialog) and node.visible:
			node.hide()
			return true
		pending.append_array(node.get_children(true))
	return false

func _escape_menu() -> void:
	if _close_top_popup(): return
	if hud.settings.visible: _close_settings(); return
	if hud.wiki.visible: hud.wiki.close_catalog(); return
	if hud.entry_menu.visible:
		if started and sim.result.is_empty(): handle_action("entry_resume", null)
		return
	if hud.menu.visible:
		if setup_session_active: _close_match_setup()
		else:
			hud.show_menu(false)
			if not started or not sim.result.is_empty(): hud.show_entry(true)
		return
	if placing or not command_mode.is_empty():
		placing = false
		command_mode = ""
		return
	if hud.help_panel.visible: hud.help_panel.hide(); return
	handle_action("settings_open", null)

func _unhandled_input(event: InputEvent) -> void:
	if loading:
		get_viewport().set_input_as_handled()
		return
	_flush_render_simulation()
	if sim==null:return
	if hud.scoreboard!=null and hud.scoreboard.visible:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:handle_action("entry_home",null)
		get_viewport().set_input_as_handled()
		return
	if benchmark:return
	if golden_mode:
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:quit_game()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE,KEY_F2,KEY_F5,KEY_F9,KEY_P,KEY_PAUSE,KEY_Z,KEY_X,KEY_C,KEY_G,KEY_H,KEY_F,KEY_U,KEY_L,KEY_B,KEY_R,KEY_T,KEY_SPACE,KEY_HOME]:
		audio.play("ui_key")
		_key_feedback_ms=Time.get_ticks_msec()
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if not event.echo: _escape_menu()
		get_viewport().set_input_as_handled()
		return
	if hud.settings.visible:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_F5: handle_action("save", null)
			elif event.keycode == KEY_F9: handle_action("load", null)
		return
	if hud.wiki.visible:
		return
	if hud.entry_menu.visible:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F9:
			handle_action("load",null)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_F5:handle_action("save",null);return
		if event.keycode==KEY_F9:handle_action("load",null);return
		if event.keycode in [KEY_P,KEY_PAUSE]:
			if not setup_session_active:handle_action("pause",null)
			return
		if hud.menu.visible:return
		if event.keycode==KEY_R and placing:
			var rotation_error: String=sim.rotate_build_order(0,1,placement_channel)
			if not rotation_error.is_empty():post(rotation_error)
			get_viewport().set_input_as_handled()
			return
		if event.keycode==KEY_Z:handle_action("attack_move",null)
		if event.keycode==KEY_X:handle_action("stop",null)
		if event.keycode==KEY_C:handle_action("waypoint",null)
		if event.keycode==KEY_G:handle_action("patrol",null)
		if event.keycode==KEY_H:handle_action("force_attack",null)
		if event.keycode==KEY_B:handle_action("return",null)
		if event.keycode==KEY_L:handle_action("land",null)
		if event.keycode==KEY_U:handle_action("unload" if inspected_ruin<=sim.RUIN_TARGET_BASE else "unload_move",null)
		if event.keycode==KEY_R:handle_action("pitch",(camera_pitch if _camera_pitch_blending and camera_pitch_mode=="fixed" else effective_camera_pitch())+2)
		if event.keycode==KEY_T:handle_action("pitch",(camera_pitch if _camera_pitch_blending and camera_pitch_mode=="fixed" else effective_camera_pitch())-2)
		if event.keycode==KEY_F:handle_action("force_move",null)
		if event.keycode==KEY_SPACE:focus_hotspot()
		if event.keycode==KEY_V and placing:
			var rotation_error: String = sim.rotate_rail_order(0, 1, placement_channel)
			if not rotation_error.is_empty(): post(rotation_error)
		if event.keycode==KEY_HOME:
			for e in sim.entities.values():
				if e.team==0 and sim.data_for(e.spec).get("role","")=="hq":focus=e.pos;break
		if event.keycode==KEY_F2 and debug_available:set_debug_visible(not debug_panel.visible)
		if event.keycode>=KEY_1 and event.keycode<=KEY_6:
			var num:int=event.keycode-KEY_0
			if event.ctrl_pressed:save_control_group(num)
			else:select_control_group(num)
		return
	if hud.menu.visible or not started or not sim.result.is_empty():return
	if event is InputEventMouseButton:
		if hud.blocks_world_scroll(event.position):
			if not event.pressed and event.button_index==MOUSE_BUTTON_LEFT:dragging=false;overlay.active=false
			if not event.pressed and event.button_index==MOUSE_BUTTON_MIDDLE:middle_drag=false
			return
		if not battlefield_rect().has_point(event.position):
			if not event.pressed and event.button_index==MOUSE_BUTTON_LEFT:dragging=false;overlay.active=false
			if not event.pressed and event.button_index==MOUSE_BUTTON_MIDDLE:middle_drag=false
			return
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			# GUI normally consumes scrolling; this also protects the sidebar edge
			# and controls which deliberately pass a scroll event to their parent.
			if not event.pressed or hud.blocks_world_scroll(event.position):return
			_queue_camera_zoom(-1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1,event.factor)
			get_viewport().set_input_as_handled()
		elif event.button_index==MOUSE_BUTTON_MIDDLE:middle_drag=event.pressed
		elif event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:
			if placing:placing=false;post("已退出放置；就绪建筑仍保留。")
			elif not command_mode.is_empty():command_mode=""
			else:right_command(ground_at(event.position),pick_entity(event.position),event.shift_pressed)
		elif event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed:
				if placing:
					var ground: Vector2 = ground_at(event.position)
					if not ground.is_finite(): return
					var engineer_deployment:bool=int(sim.order_for_team(0,placement_channel).get("builder",-1))>=0
					var err:String=sim.place_building(0,ground,placement_channel)
					if err.is_empty():
						placing=false;audio.play("build")
						post("工程兵前往所选位置部署分基地。" if engineer_deployment else "建筑已落地，1.5 秒后启用。")
					else:report(err)
				elif command_mode == "load_transport":
					var boarding: Dictionary = TransportCommands.load_at(sim, friendly_units(), pick_entity(event.position), event.shift_pressed)
					if not str(boarding.error).is_empty(): report(str(boarding.error))
					else:
						audio.play("command")
						post("%d 名步兵前往装载；可再次点装载补充乘员。" % boarding.passengers.size())
						if not event.shift_pressed: command_mode = ""
				elif command_mode in ["attack_move","patrol","waypoint","force_attack","force_move","land","unload_move"]:
					var target:int=pick_entity(event.position) if command_mode in ["force_attack","force_move"] else -1
					var accepted: bool = command_units("move" if command_mode == "waypoint" else command_mode,ground_at(event.position),target,event.shift_pressed or command_mode == "waypoint")
					if accepted and command_mode != "waypoint": command_mode=""
				else:
					dragging=true
					drag_start=event.position
					overlay.start=drag_start
					overlay.finish=drag_start
			elif dragging:
				dragging=false
				overlay.active=false
				if event.position.distance_to(drag_start)>8:box_select(Rect2(drag_start,event.position-drag_start).abs(),event.shift_pressed)
				else:click_select(event.position,event.shift_pressed)
	elif event is InputEventMouseMotion:
		if middle_drag:
			focus+=Vector2(-event.relative.x,-event.relative.y).rotated(-yaw)*distance/battlefield_rect().size.y
		if dragging:
			overlay.active=event.position.distance_to(drag_start)>8
			overlay.finish=event.position.clamp(battlefield_rect().position,battlefield_rect().end)

func ground_at(screen: Vector2) -> Vector2:
	var pixel: Vector2 = screen_to_battlefield(screen)
	var origin:=camera.project_ray_origin(pixel)
	var direction:=camera.project_ray_normal(pixel)
	if not origin.is_finite() or not direction.is_finite() or direction.y >= -0.00001: return Vector2.INF
	var max_height:float=camera_clearance_height
	var start_t:float=maxf(0,(max_height-origin.y)/direction.y)
	var end_t:float=(0-origin.y)/direction.y+10
	var previous:float=start_t
	for i in range(140):
		var t:float=lerpf(start_t,end_t,float(i)/139)
		var p:Vector3=origin+direction*t
		var pos:=Vector2(p.x,p.z)
		if p.y<=cursor_surface_y(pos):
			var lo:float=previous
			var hi:float=t
			for j in range(8):
				var mid:float=(lo+hi)*0.5
				var v:Vector3=origin+direction*mid
				if v.y<=cursor_surface_y(Vector2(v.x,v.z)):hi=mid
				else:lo=mid
			var hit:Vector3=origin+direction*hi
			var point:=Vector2(hit.x,hit.z)
			return point if sim._in_bounds(point) else Vector2.INF
		previous=t
	var fallback:Vector3=origin+direction*((0-origin.y)/direction.y)
	var point:=Vector2(fallback.x,fallback.z)
	return point if sim._in_bounds(point) else Vector2.INF

func cursor_surface_y(pos: Vector2) -> float:
	return MapData.water_surface_y(sim.map,pos) if MapData.terrain_at(sim.map,pos) == MapData.WATER else MapData.height_at(sim.map,pos)

var building_pick_mesh_cache: Dictionary = {}

func _building_ray_hit(origin: Vector3, direction: Vector3) -> Dictionary:
	return EntityPicking.ray_hit(sim, world, origin, direction, building_pick_mesh_cache, func(entity): return entity.kind == "building" and sim.entity_visible_to(0,int(entity.id)))

func _unit_ray_hit(origin: Vector3, direction: Vector3) -> Dictionary:
	return EntityPicking.ray_hit(sim, world, origin, direction, building_pick_mesh_cache, func(entity): return entity.kind == "unit" and sim.entity_visible_to(0, int(entity.id)) and int(entity.get("transport_id", -1)) < 0)

func _tree_ray_depth(id:int,origin:Vector3,direction:Vector3) -> float:
	if world==null or world.landscape==null:return INF
	var nearest:float=INF
	for piece in world.landscape.tree_visuals.get(id,[]):
		if bool(piece.get("shadow", false)): continue
		var transform:Transform3D=world.landscape.global_transform*piece.transform
		if absf(transform.basis.determinant())<.000001:continue
		var inverse:Transform3D=transform.affine_inverse()
		var local_origin:Vector3=inverse*origin
		var local_direction:Vector3=(inverse.basis*direction).normalized()
		var mesh:Mesh=(piece.multi as MultiMesh).mesh
		var hit:Variant=mesh.get_aabb().intersects_ray(local_origin,local_direction)
		if hit is Vector3:
			var depth:float=(transform*(hit as Vector3)-origin).dot(direction)
			if depth>=0.0:nearest=minf(nearest,depth)
	return nearest

func pick_entity(screen: Vector2) -> int:
	if not battlefield_rect().has_point(screen):return -1
	var pos:=ground_at(screen)
	var pixel: Vector2=screen_to_battlefield(screen)
	var origin: Vector3=camera.project_ray_origin(pixel)
	var direction: Vector3=camera.project_ray_normal(pixel)
	var building_hit: Dictionary=_building_ray_hit(origin,direction)
	var unit_hit: Dictionary = _unit_ray_hit(origin,direction)
	var visible_unit: bool = int(unit_hit.id) >= 0 and float(unit_hit.depth) < float(building_hit.depth)
	var best:int=int(unit_hit.id) if visible_unit else int(building_hit.id)
	var distance_score:float=0.0 if visible_unit else 100000.0
	for e in sim.entities.values():
		if int(e.get("transport_id",-1))>=0:continue
		if not sim.entity_visible_to(0,int(e.id)):continue
		var d:Dictionary=sim.data_for(e.spec)
		var center: Vector3 = entity_visual_center(e)
		if camera.is_position_behind(center):continue
		# Raised roofs are selected from their visible triangles. Existing unit
		# tolerance remains useful, but units behind a hit roof cannot steal it.
		if int(building_hit.id)>=0:
			if e.kind=="building":continue
			if (center-origin).dot(direction)>=float(building_hit.depth)-.12:continue
		var projected:=project_world_to_screen(center)
		var sd:float=projected.distance_to(screen)
		var ground_distance:float=e.pos.distance_to(pos)
		var radius:float=float(d.get("size",1))*0.75 if e.kind=="building" else maxf(float(d.get("radius",0.35)),0.65)
		var airborne: bool = str(d.get("domain", "ground")) == "air" and float(e.get("flight_height", d.get("flight_height", 0.0))) > 0.5
		if sd < 34 or (not airborne and ground_distance < radius):
			var score: float = sd if airborne else minf(sd, ground_distance * 24)
			if score<distance_score:distance_score=score;best=e.id
	if not pos.is_finite(): return best
	# A crown can project behind its trunk's ground point. Include that ray
	# offset and the terrain's height range before precise mesh picking.
	var neutral_reach: float = 16.0 / maxf(absf(direction.y), 0.08) + 3.0
	var neutral_region := Rect2(pos - Vector2.ONE * neutral_reach, Vector2.ONE * neutral_reach * 2.0)
	var ground_ruin:int=sim.ruin_at(pos)
	for ruin in sim.neutral_in_rect(neutral_region):
		if float(ruin.hp)<=0:continue
		var center:=Vector3(ruin.pos.x,MapData.height_at(sim.map,ruin.pos)+(.45 if ruin.kind=="wall" else 1.1),ruin.pos.y)
		if camera.is_position_behind(center):continue
		var tree_depth:float=_tree_ray_depth(int(ruin.id),origin,direction) if ruin.kind=="tree" else INF
		var depth:float=tree_depth if is_finite(tree_depth) else (center-origin).dot(direction)
		if int(building_hit.id)>=0 and depth>=float(building_hit.depth)-.12:continue
		var score:float=tree_depth*.0001 if is_finite(tree_depth) else project_world_to_screen(center).distance_to(screen)
		if ground_ruin==sim.RUIN_TARGET_BASE-int(ruin.id):score=minf(score,20)
		if score<34 and score<distance_score:
			best=sim.RUIN_TARGET_BASE-int(ruin.id);distance_score=score
	return best

func click_select(screen: Vector2, append: bool) -> void:
	if not battlefield_rect().has_point(screen):return
	var id:=pick_entity(screen)
	inspected_ruin=id if id<=sim.RUIN_TARGET_BASE else -1
	var ground:Vector2=ground_at(screen)
	inspected_bridge=sim.bridge_at(ground) if id<0 and inspected_ruin==-1 and ground.is_finite() else -1
	if not append:selected.clear()
	if id>=0:
		if append and id in selected:selected.erase(id)
		else:selected.append(id)
		audio.play("select")
		speak_selection("select")
	hud.cache_key=""

func box_select(rect: Rect2, append: bool) -> void:
	rect=rect.intersection(battlefield_rect())
	if not append:selected.clear()
	for e in sim.entities.values():
		if e.team!=0 or e.kind!="unit" or sim.Transport.is_loaded(e):continue
		var p: Vector3 = entity_visual_center(e)
		if not camera.is_position_behind(p) and rect.has_point(project_world_to_screen(p)) and e.id not in selected:selected.append(e.id)
	audio.play("select")
	speak_selection("select")

# The model root anchors to terrain, while an aircraft body moves above it.
func entity_visual_center(e: Dictionary) -> Vector3:
	var d: Dictionary = sim.data_for(e.spec)
	var height: float = MapData.entity_surface_y(sim.map, e.pos, str(d.get("domain","ground")))
	if str(d.get("domain", "ground")) == "air":
		var air_model: Dictionary=world.models.get(int(e.id),{}) if is_instance_valid(world) else {}
		height=float(air_model.visual_air_y)+.4 if air_model.has("visual_air_y") else height+float(e.get("flight_height",d.get("flight_height",4.0)))+.4
	else:
		height += 1.8 if e.kind == "building" else 0.7
	return Vector3(e.pos.x, height, e.pos.y)

func speak_selection(action_id: String, ids: Array = []) -> void:
	var source: Array = selected if ids.is_empty() else ids
	_update_navigation_attention()
	if action_id=="select":_update_audio_attention(0.0)
	for id in source:
		if sim.entities.has(id):
			var e: Dictionary = sim.entities[id]
			if int(e.team) == 0 and e.kind == "unit":
				if audio.voice_category(str(e.spec))=="infantry" and action_id in ["select","move","attack"] and audio.has_method("play_unit_group_voice"):
					var contexts: Array=[]
					var voice_profile: String=audio.speech_profile_key(str(e.spec))
					for member_id:Variant in source:
						var member:Dictionary=sim.entities.get(int(member_id),{})
						if member.is_empty() or member.kind!="unit" or int(member.team)!=0 or audio.speech_profile_key(str(member.spec))!=voice_profile:continue
						contexts.append({"id":int(member.id),"team":int(member.team),"pos":member.pos})
						if contexts.size()>=3:break
					if contexts.size()>1:
						audio.play_unit_group_voice(str(e.spec),action_id,contexts)
						return
				audio.play_unit_voice(str(e.spec), action_id, {"id":int(e.id),"team":int(e.team),"pos":e.pos})
				return
			elif int(e.team)==0 and e.kind=="building" and action_id=="select":
				audio.play_event({"kind":"select_building","id":int(e.id),"team":int(e.team),"spec":str(e.spec),"pos":e.pos})
				return

func friendly_units() -> Array:
	return selected.filter(func(id):return sim.entities.has(id) and sim.entities[id].team==0 and sim.entities[id].kind=="unit" and not sim.Transport.is_loaded(sim.entities[id]))

func right_command(pos: Vector2, target: int, append: bool) -> void:
	if not pos.is_finite():
		if target>=0 and sim.entities.has(target):pos=sim.entities[target].pos
		else:return
	_flush_render_simulation()
	if target<=sim.RUIN_TARGET_BASE:
		var ruin:Dictionary=sim.ruin_by_target(target)
		if sim.GarrisonOperations.suitable(ruin):
			var troops:Array=friendly_units()
			if troops.is_empty() and int(ruin.get("garrison_team",-1))==0:
				report(sim.GarrisonOperations.unload(sim,target,false,0),"驻军正在从建筑撤出。")
			elif sim.GarrisonOperations.hostile(sim,0,target):
				sim.issue(troops,"attack",ruin.pos,target,append)
			else:
				var boarders:Array=troops.filter(func(id):return sim.GarrisonOperations.board_error(sim,int(id),target).is_empty())
				if boarders.is_empty():post("只有普通步兵可以进驻，工兵不能进驻。")
				else:sim.issue(boarders,"garrison",ruin.pos,target,append)
			return
	if target>=0 and sim.entities.has(target) and int(sim.entities[target].team)==0 and sim.data_for(sim.entities[target].spec).get("role","")=="refinery":
		var miners:Array=friendly_units().filter(func(id):return sim.data_for(sim.entities[id].spec).get("art","")=="harvester")
		if not miners.is_empty():
			sim.issue(miners,"return_miner",sim.entities[target].pos,target,append)
			post("矿车立即回厂卸矿。")
			return
	var bridge_id:int=sim.bridge_at(pos)
	if bridge_id<0:
		for b in sim.bridges:
			if not b.alive:
				for head in b.heads:
					var hpos:Vector2=head if head is Vector2 else Vector2(head[0],head[1])
					if hpos.distance_to(pos)<3.0:bridge_id=b.id
	var units:=friendly_units()
	if not units.is_empty():
		if target>=0 and sim.entities.has(target) and sim.entities[target].team!=0:
			var fighters:Array=units.filter(func(id):return not str(sim.data_for(sim.entities[id].spec).get("weapon","")).is_empty())
			var engineers:Array=units.filter(func(id):return str(sim.data_for(sim.entities[id].spec).get("art",""))=="engineer")
			var capturing:bool=false
			if not fighters.is_empty():sim.issue(fighters,"attack",pos,target,append)
			if not engineers.is_empty() and sim.entities[target].kind=="building":
				var capture_error:String=sim.capture_error(int(engineers[0]),target)
				if capture_error.is_empty():
					sim.issue(engineers,"capture",sim.entities[target].pos,target,append)
					capturing=true
					post("工程兵接近后立即占领敌方建筑。")
					speak_selection("move",engineers)
				else:report(capture_error)
			elif not fighters.is_empty():speak_selection("attack",fighters)
			if not fighters.is_empty() or capturing:
				audio.play("command")
				show_marker(pos)
		elif target >= 0 and sim.entities.has(target) and int(sim.entities[target].team) == 0 and sim.entities[target].kind == "building" and sim.data_for(sim.entities[target].spec).get("role", "") == "repair" and float(sim.data_for(sim.entities[target].spec).get("service_rate", 0.0)) > 0.0:
			var servicing: Array = units.filter(func(id): return sim.service_error(int(id), target).is_empty())
			if servicing.is_empty():
				report(sim.service_error(int(units[0]), target))
			else:
				sim.issue(servicing, "service", sim.entities[target].pos, target, append)
				audio.play("command")
				speak_selection("move", servicing)
				show_marker(sim.entities[target].pos)
				post("%d 辆受损载具前往修理厂；入厂后按实际恢复生命付费维修。" % servicing.size())
		elif target >= 0 and sim.entities.has(target) and int(sim.entities[target].team) == 0 and int(sim.data_for(sim.entities[target].spec).get("transport_capacity",0)) > 0 and not TransportCommands.infantry(sim, units).is_empty():
			var boarding: Dictionary = TransportCommands.board(sim, units, target, append)
			if not str(boarding.error).is_empty(): report(boarding.error)
			else:
				audio.play("command")
				speak_selection("move", boarding.passengers)
				show_marker(sim.entities[target].pos)
				post("%d名步兵前往登乘；该载具可搭载 %d 人。" % [boarding.passengers.size(),int(sim.data_for(sim.entities[target].spec).get("transport_capacity",1))])
		elif target >= 0 and sim.entities.has(target) and int(sim.entities[target].team) == 0 and sim.entities[target].has("construction") and float(sim.entities[target].construct_remaining)>0.0 and units.any(func(id):return sim.data_for(sim.entities[id].spec).get("art","")=="engineer"):
			var engineers:Array=units.filter(func(id):return sim.data_for(sim.entities[id].spec).get("art","")=="engineer")
			sim.issue([engineers[0]],"resume_outpost",sim.entities[target].pos,target,append)
			audio.play("command")
			speak_selection("move",[engineers[0]])
			show_marker(sim.entities[target].pos)
			post("工程兵前往接手分基地施工，资金随进度支付。")
		elif target >= 0 and sim.entities.has(target) and int(sim.entities[target].team) == 0 and units.any(func(id): return sim.data_for(sim.entities[id].spec).has("rescue_radius")) and sim.FactionSupport.vehicle(sim, sim.entities[target]) and float(sim.entities[target].hp) < float(sim.data_for(sim.entities[target].spec).hp):
			var rescuers: Array = units.filter(func(id): return sim.FactionSupport.rescue_error(sim, int(id), target).is_empty())
			sim.issue(rescuers, "rescue", sim.entities[target].pos, target, append)
			var repairers: Array = units.filter(func(id): return sim.FactionSupport.repairer(sim, sim.entities[id], sim.entities[target]))
			sim.issue(repairers, "repair", sim.entities[target].pos, target, append)
			audio.play("command")
			show_marker(sim.entities[target].pos)
			post("拖救车护送受损友军；生命低于60%时提高撤离速度。给友军下达后撤命令。")
		elif target >= 0 and sim.entities.has(target) and int(sim.entities[target].team) == 0 and float(sim.entities[target].hp) < float(sim.data_for(sim.entities[target].spec).hp) and units.any(func(id): return sim.FactionSupport.repairer(sim, sim.entities[id], sim.entities[target])):
			var repairers: Array = units.filter(func(id): return sim.FactionSupport.repairer(sim, sim.entities[id], sim.entities[target]))
			sim.issue(repairers, "repair", sim.entities[target].pos, target, append)
			audio.play("command")
			speak_selection("move", repairers)
			show_marker(sim.entities[target].pos)
			post("工程兵接近后立即修满友方建筑。" if sim.entities[target].kind=="building" else "维修单位接近友军后持续付费维修，多辆维修车不叠加。")
		elif target<=sim.RUIN_TARGET_BASE or sim.ruin_at(pos)<=sim.RUIN_TARGET_BASE:
			command_units("move",pos,-1,append)
			post("中立树木、房屋与石墙需要 H 强制攻击。")
		elif sim.mine_at(pos) >= 0 and units.any(func(id):return str(sim.entities[id].spec).ends_with("_harvester")):
			var mine: int = sim.mine_at(pos)
			var miners: Array = units.filter(func(id):return str(sim.entities[id].spec).ends_with("_harvester"))
			sim.issue(miners,"harvest",sim.mines[mine].pos,mine,append)
			audio.play("command")
			speak_selection("move", miners)
			show_marker(sim.mines[mine].pos)
			post("矿车前往指定矿点，满载后交付并返回采矿。")
		elif bridge_id>=0:
			var engineers:Array=units.filter(func(id):return sim.data_for(sim.entities[id].spec).art=="engineer")
			var bridge:Dictionary=sim._bridge_by_id(bridge_id)
			if not engineers.is_empty() and not bridge.is_empty() and (not bridge.alive or float(bridge.hp)<float(sim.rules.economy.bridge_hp)):
				sim.issue(engineers,"repair_bridge",pos,-1000-bridge_id,append)
				post("工程师正在前往桥头修复，费用按进度支付。")
			else:command_units("attack",pos,-1000-bridge_id,append)
		else:command_units("move",pos,-1,append)
	else:
		for id in selected:
			if sim.entities.has(id) and sim.entities[id].team==0 and sim.entities[id].kind=="building":
				sim.set_rally(id,pos)
				post("集结点已设置。")
				show_marker(pos)

func command_units(kind: String, pos: Vector2, target: int=-1, append: bool=false) -> bool:
	if not pos.is_finite():
		if target>=0 and sim.entities.has(target):pos=sim.entities[target].pos
		else:return false
	_flush_render_simulation()
	var ids:=friendly_units()
	if kind in ["land", "unload_move"]:
		ids = TransportCommands.carriers(sim, ids, kind == "unload_move")
		if kind == "land": ids = ids.filter(func(id): return sim._is_air(sim.entities[id]))
	if ids.is_empty():report("先选择己方移动单位。");return false
	if kind == "unload_move":
		var allowed: Array = []
		var reason: String = ""
		for id in ids:
			var error: String = TransportCommands.destination_error(sim, int(id), pos)
			if error.is_empty(): allowed.append(id)
			else: reason = error
		if allowed.is_empty(): report(reason); return false
		ids = allowed
	sim.issue(ids,kind,pos,target,append)
	audio.play("command")
	if kind != "return": speak_selection("attack" if kind in ["attack", "attack_move", "force_attack"] else "move", ids)
	show_marker(pos)
	return true

func show_marker(pos: Vector2) -> void:
	if command_marker==null:
		command_marker=MeshInstance3D.new()
		var mesh:=TorusMesh.new()
		mesh.inner_radius=0.5
		mesh.outer_radius=0.65
		mesh.rings=18
		mesh.ring_segments=4
		command_marker.mesh=mesh
		var mat:=StandardMaterial3D.new()
		mat.albedo_color=PaperHUD.PLAYER_COLORS[0]
		mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		command_marker.material_override=mat
		add_child(command_marker)
	command_marker.position=Vector3(pos.x,cursor_surface_y(pos)+0.05,pos.y)
	command_marker.visible=true
	marker_time=1.4

func focus_selection() -> void:
	if selected.is_empty():return
	var total:=Vector2.ZERO
	var count:int=0
	for id in selected:
		if sim.entities.has(id):total+=sim.entities[id].pos;count+=1
	if count>0:focus=total/count

func prune_control_groups() -> void:
	for number in groups.keys():
		groups[number] = groups[number].filter(func(id): return sim.entities.has(id) and int(sim.entities[id].team) == 0 and str(sim.entities[id].kind) == "unit" and float(sim.entities[id].hp) > 0.0)
		if groups[number].is_empty(): groups.erase(number)

func save_control_group(number: int) -> void:
	if number < 1 or number > 6: return
	groups[number] = selected.filter(func(id): return sim.entities.has(id) and int(sim.entities[id].team) == 0 and str(sim.entities[id].kind) == "unit" and float(sim.entities[id].hp) > 0.0)
	var count: int = groups[number].size()
	if count == 0: groups.erase(number)
	hud.refresh_groups(groups)
	post("编队 %d 已保存 · %d 单位" % [number, count] if count > 0 else "编队 %d 已清空" % number)

func select_control_group(number: int) -> void:
	if number < 1 or number > 6: return
	prune_control_groups()
	hud.refresh_groups(groups)
	if not groups.has(number): return
	selected = groups[number].filter(func(id): return int(sim.entities[id].get("transport_id", -1)) < 0 and sim.entity_visible_to(0, int(id)))
	hud.refresh(sim, selected, camera, dev_mode, "\n".join(feedback), sim_cpu_ms, inspected_bridge, debug_available)
	audio.play("select"); speak_selection("select")

func focus_hotspot() -> void:
	var point: Vector2 = audio.commander.latest_hotspot(sim)
	if point.is_finite(): focus = point; return
	for entity: Dictionary in sim.entities.values():
		if int(entity.team) == 0 and str(sim.data_for(entity.spec).get("role", "")) == "hq": focus = entity.pos; return

func _update_battle_information() -> void:
	var pointer := get_viewport().get_mouse_position()
	hovered_entity = pick_entity(pointer) if battlefield_rect().has_point(pointer) and not hud.blocks_world_scroll(pointer) else -1
	hud.show_entity_hover(hovered_entity, pointer)
	hud.refresh_base_markers([])

func handle_action(kind: String, value: Variant) -> void:
	if kind == "select_group": select_control_group(int(value)); return
	if kind in ["entry_home","entry_play","quit","new_game"] and hud!=null and hud.get("scoreboard")!=null:
		hud.scoreboard.close_scoreboard()
	if audio!=null and kind not in ["settings_closed","wiki_closed","audio_mix","pitch"] and Time.get_ticks_msec()-_key_feedback_ms>20:
		audio.play("ui_click")
	if quit_pending:return
	if loading:
		if kind == "quit": quit_game()
		return
	_flush_render_simulation()
	if benchmark:
		if kind=="quit":quit_game()
		return
	if golden_mode:
		if kind=="quit":quit_game()
		return
	if kind=="export_statistics":
		_export_match_statistics()
	elif kind=="settings_open":
		_open_settings()
	elif kind=="settings_closed":
		_settings_closed()
	elif kind=="new_game":
		_open_match_setup()
	elif kind=="setup_resume":
		_close_match_setup()
	elif kind=="audio_mix":
		audio.set_mix(value)
		hud.muted=audio.muted
		save_preferences()
	elif kind=="graphics_quality":
		set_graphics_quality(str(value));save_preferences()
	elif kind=="render_scale":
		set_render_scale(float(value));save_preferences()
	elif kind=="depth_of_field":
		set_depth_of_field(bool(value));save_preferences()
	elif kind=="debug_enabled":
		set_debug_enabled(bool(value));save_preferences()
	elif kind=="audio_browser_enabled":
		set_audio_browser_enabled(bool(value));save_preferences()
	elif kind=="ambient_occlusion":
		environment.ssao_enabled=bool(value);save_preferences()
	elif kind=="shadows":
		key_light.shadow_enabled=bool(value);save_preferences()
	elif kind=="fullscreen":
		get_window().mode=Window.MODE_FULLSCREEN if bool(value) else Window.MODE_WINDOWED
		save_preferences()
	elif kind=="entry_play":
		_open_match_setup()
	elif kind=="entry_campaign":
		await start_match_with_loading("campaign", 1, "kestrel")
	elif kind=="campaign_target":
		if value is Vector2: focus = value
	elif kind=="entry_home":
		_close_match_setup()
		_close_settings()
		if hud.entry_menu.visible: return
		audio.reset_field()
		entry_pause_before=pve_paused
		if started:pve_paused=true
		hud.show_entry(true)
	elif kind=="entry_resume":
		if not started or not sim.result.is_empty(): return
		hud.show_entry(false)
		hud.show_menu(false)
		pve_paused=entry_pause_before
		hud.pause_button.text="继续" if pve_paused else "暂停"
	elif kind=="entry_mute":
		hud.muted=not hud.muted
		audio.muted=hud.muted
		save_preferences()
	elif kind=="wiki":
		var catalog_rules: Dictionary=RulesLoader.load_rules()
		if catalog_rules.is_empty():
			var message: String="军团档案读取失败："+"; ".join(RulesLoader.errors)
			if hud.entry_menu.visible:hud.entry_menu.show_notice(message)
			report(message);return
		wiki_return_to_settings=hud.settings.visible
		wiki_return_to_menu=hud.menu.visible
		_close_settings()
		wiki_return_to_entry=hud.entry_menu.visible
		wiki_pause_before=pve_paused
		if started:pve_paused=true
		dragging=false;middle_drag=false;overlay.active=false
		hud.show_entry(false);hud.show_menu(false);hud.help_panel.hide()
		hud.wiki.configure(catalog_rules)
		hud.wiki.configure_audio_browser(audio,audio_browser_enabled)
		hud.wiki.open_catalog()
	elif kind=="wiki_closed":
		pve_paused=wiki_pause_before
		if wiki_return_to_entry:hud.show_entry(true)
		elif wiki_return_to_menu:hud.show_menu(true)
		if wiki_return_to_settings:_open_settings()
		hud.pause_button.text="继续" if pve_paused else "暂停"
	elif kind=="start":
		if not await start_match_with_loading(value.mode,value.seed,value.faction,value.get("match_options",{})):return
		if quit_pending:return
		save_preferences()
	elif kind=="restart":
		await start_match_with_loading(menu_config.mode,menu_config.seed,menu_config.faction,menu_config.get("match_options",{}))
	elif kind=="quit":quit_game()
	elif kind=="debug_panel":
		if debug_available:set_debug_visible(not debug_panel.visible)
	elif kind=="mute":audio.muted=value;save_preferences()
	elif kind=="pitch":
		var from: float = effective_camera_pitch()
		camera_pitch=clampf(float(value),20,45)
		_start_camera_pitch_transition(from)
		_sync_pitch_controls()
		update_camera()
		save_preferences()
	elif kind=="camera_pitch_mode":
		var from: float = effective_camera_pitch()
		camera_pitch_mode="fixed" if str(value)=="fixed" else "dynamic"
		_start_camera_pitch_transition(from)
		_sync_pitch_controls()
		update_camera()
		save_preferences()
	elif kind=="save":
		if not started:report("尚未开始对局。");return
		report(sim.save_game(SAVE_PATH,world.export_visual_memory()),"已保存一致快照："+OS.get_user_data_dir())
	elif kind=="load":
		await load_game_with_loading()
	elif not started or not sim.result.is_empty():return
	elif kind=="build":
		var spec: String = str(value.get("spec", "")) if value is Dictionary else str(value)
		var channel: String = str(value.get("channel", sim.construction_channel(spec))) if value is Dictionary else sim.construction_channel(spec)
		var bo:Dictionary=sim.order_for_team(0,channel)
		if not bo.is_empty() and bo.spec==spec and bo.get("ready",false):
			placement_channel=channel
			placing=true
			post("选择建筑施工位置；R旋转90°，工程兵随后前往建造。" if int(bo.get("builder",-1))>=0 else "选择绿色标记的合法位置；R旋转90°，右键退出放置。")
		else:
			var builder:int=hud.selected_engineer() if sim.TechAvailability.engineer_building(sim, 0, sim.data_for(spec)) else -1
			var error:String=sim.build(0,spec,builder)
			if error.is_empty():audio.play("queue_build")
			if error.is_empty() and builder >= 0:
				placement_channel=channel
				placing=true
				post("左键选择建筑位置，R旋转90°；工程兵到达后搭起脚手架，施工时逐步付款。")
			else:report(error,"已付款并进入%s建造队列。" % ("防御" if channel == "defense" else "常规"))
	elif kind=="produce":
		var spec: String = str(value.get("spec", "")) if value is Dictionary else str(value)
		var producer:int=hud.production_building(spec)
		if producer<0:report("先建设相应的兵营、工厂或机场。");return
		var order_error: String=sim.produce(producer,spec)
		if order_error.is_empty():audio.play("queue_unit")
		report(order_error,"订单已付款，进入该生产设施的独立队列。")
	elif kind=="cancel_build":
		var channel: String = str(value.get("channel", "normal")) if value is Dictionary else (str(value) if value is String else "normal")
		var bo:Dictionary=sim.order_for_team(0,channel)
		var ready:bool=not bo.is_empty() and bo.get("ready",false)
		var choosing_site:bool=int(bo.get("builder",-1))>=0
		report(sim.cancel_build(0,channel),"已取消建筑选址；尚未花费资金。" if choosing_site else ("已取消。就绪建筑不退款。" if ready else "已按未完成进度退款。"))
		if channel==placement_channel:placing=false
	elif kind=="cancel_unit":
		var p:=hud.production_building()
		if p>=0:report(sim.cancel_production(p,0),"已取消首项；按未完成比例退款。")
	elif kind=="cancel_queue":report(sim.cancel_production(value.building,value.index),"订单已取消并按规则退款。")
	elif kind=="pause":
		pve_paused = not pve_paused
		_player_music_paused=pve_paused
		if audio.music.has_method("set_playback_paused"):audio.music.set_playback_paused(pve_paused)
		hud.pause_button.text = "继续" if pve_paused else "暂停"
		post("PVE 已暂停 · 按 P 或继续按钮恢复" if pve_paused else "对局继续")
	elif kind in ["attack_move","patrol","waypoint","force_attack","force_move"]:
		command_mode=kind
		post({"attack_move":"左键指定进攻终点。","patrol":"左键指定巡逻终点；单位往返巡逻并沿路索敌。","waypoint":"连续左键追加路径点；右键或 Esc 完成。","force_attack":"左键目标或地面强制攻击，可攻击友方与中立障碍。","force_move":"左键目标或地面强制移动；坦克可碾压敌方步兵，友方步兵会避让。"}[kind])
	elif kind in ["stop","hold"]:
		sim.issue(friendly_units(),kind,Vector2.ZERO)
		command_mode=""
		audio.play("command")
	elif kind == "return":
		var miners:Array=friendly_units().filter(func(id):return sim.data_for(sim.entities[id].spec).get("art","")=="harvester")
		if not miners.is_empty():sim.issue(miners,"return_miner",Vector2.ZERO,-1);post("矿车立即返回矿厂卸矿。")
		var aircraft: Array = friendly_units().filter(func(id): return str(sim.data_for(sim.entities[id].spec).get("domain", "ground")) == "air" and not bool(sim.data_for(sim.entities[id].spec).get("permanent_air",false)))
		if aircraft.is_empty() and miners.is_empty(): report("选择矿车回厂，或选择固定翼飞机返航。")
		elif not aircraft.is_empty():
			sim.issue(aircraft, "return", Vector2.ZERO)
			audio.play("command")
			post("飞机返航补给维修，完成后停机；移动命令可再次起飞。")
	elif kind=="unload":
		if inspected_ruin<=sim.RUIN_TARGET_BASE:
			report(sim.GarrisonOperations.unload(sim,inspected_ruin,false,0),"驻军撤出。")
			return
		var carriers:Array=friendly_units().filter(func(id):return not sim.entities[id].get("passengers",[]).is_empty())
		if carriers.is_empty():report("先选择搭载步兵的己方运输载具。")
		for id in carriers:report(sim.unload(int(id)),"步兵已在运输载具附近下车。")
	elif kind == "transport":
		hud.show_transport_menu()
	elif kind == "load_transport":
		var state: Dictionary = TransportCommands.menu_state(sim, friendly_units())
		if not bool(state.load): report("先选择有空位的己方运输载具，或选择可登乘的步兵。"); return
		command_mode = kind
		placing = false
		post("左键选择己方步兵装载；选中步兵时左键选择运输载具。Shift 可连续指定，右键或 Esc 退出。")
	elif kind in ["land", "unload_move"]:
		var carriers: Array = TransportCommands.carriers(sim, friendly_units(), kind == "unload_move")
		if kind == "land": carriers = carriers.filter(func(id): return sim._is_air(sim.entities[id]))
		if carriers.is_empty():
			report("先选择运输机。" if kind == "land" else "先选择搭载步兵的己方运输载具。")
			return
		command_mode=kind
		post("左键选择合法空地，运输机将在此降落。" if kind == "land" else "左键选择卸载地点；运输载具抵达后自动下客。")
	elif kind=="dismantle_outpost":
		var id:int=hud.selected_building()
		if id>=0:report(sim.dismantle_outpost(id),"已拆除未完工分基地；已花施工资金不退款。")
	elif kind=="focus":focus_selection()
	elif kind=="repair":
		for id in selected:
			if sim.entities.has(id) and sim.entities[id].team==0 and sim.entities[id].kind=="building":sim.toggle_repair(id)
		post("建筑修理已切换：每秒恢复 2%，按恢复生命扣款。")
	elif kind=="sell":
		for id in selected.duplicate():
			if sim.entities.has(id) and sim.entities[id].team==0 and sim.entities[id].kind=="building":
				if sim.counts(0).y==1:pending_sell=id;confirm.popup_centered(Vector2i(440,180));return
				report(sim.sell(id),"出售完成，返还原价 50%。")
	elif kind=="minimap":
		if value.move:command_units("move",value.pos)
		else:focus=value.pos
	elif kind=="debug" and debug_available:set_debug_visible(not debug_panel.visible)

func report(error: String, success: String="") -> void:
	if hud.settings.visible: hud.settings.show_notice(success if error.is_empty() else error)
	if error.is_empty():
		if not success.is_empty():post(success)
	else:post(error);audio.play("error")

func post(message: String) -> void:
	if message.is_empty():return
	feedback.append(message)
	while feedback.size()>3:feedback.pop_front()

func make_debug_panel() -> void:
	debug_panel=PanelContainer.new()
	debug_panel.theme=hud.theme_paper
	debug_panel.position=Vector2(18,78)
	debug_panel.custom_minimum_size=Vector2(390,0)
	debug_panel.visible=false
	hud.add_child(debug_panel)
	# F2 belongs to this viewport. Treat its paper as HUD input, never a
	# separate desktop Window or a click-through battlefield region.
	debug_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.ui_panels.append(debug_panel)
	var c:=VBoxContainer.new()
	c.add_theme_constant_override("separation",6)
	debug_panel.add_child(c)
	c.add_child(hud.label("调试面板 · F2",18))
	debug_metrics=hud.label("",12)
	debug_metrics.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	c.add_child(debug_metrics)
	# Retained aliases point to the single settings sheet.
	dof_toggle=hud.settings.dof
	render_scale_option=hud.settings.resolution
	debug_tools=VBoxContainer.new()
	debug_tools.visible=dev_mode
	debug_tools_scroll = ScrollContainer.new()
	debug_tools_scroll.custom_minimum_size = Vector2(0,310)
	debug_tools_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	debug_tools_scroll.visible = dev_mode and debug_available
	c.add_child(debug_tools_scroll)
	debug_tools.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	debug_tools_scroll.add_child(debug_tools)
	debug_tools.add_child(hud.label("开发场景 · 规则工具",13))
	debug_tools.add_child(hud.button("重置 100×100 试验场",func():if dev_mode and debug_available:start_match("dev",73026,menu_config.faction);spawn_roster();set_debug_visible(false)))
	var faction_row := HBoxContainer.new()
	debug_tools.add_child(faction_row)
	faction_row.add_child(hud.label("展示阵营",12))
	debug_faction_picker = OptionButton.new()
	for faction: String in ["kestrel","rivet","iron","sky"]:
		debug_faction_picker.add_item(str(rules.factions.get(faction,{}).get("name",faction)))
		debug_faction_picker.set_item_metadata(debug_faction_picker.item_count-1,faction)
	faction_row.add_child(debug_faction_picker)
	faction_row.add_child(hud.button("切换并重置",_debug_switch_faction))
	debug_tools.add_child(hud.button("一键生成本阵营所有建筑",_debug_generate_buildings))
	debug_instant_toggle = CheckBox.new()
	debug_instant_toggle.text = "立即施工 / 生产（仍扣费与检查出口）"
	debug_instant_toggle.toggled.connect(func(value: bool): debug_instant_build=value;_sync_developer_options())
	debug_tools.add_child(debug_instant_toggle)
	debug_building_report = hud.label("建筑工具遵守真实占地，保留两格通道。",12)
	debug_building_report.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	debug_tools.add_child(debug_building_report)
	debug_tools.add_child(hud.button("补充资金 +10000",func():if dev_mode and debug_available:sim.money[0]+=10000;post("开发资金已补充。")))
	debug_tools.add_child(hud.button("双方生成全部兵种",func():if dev_mode and debug_available:spawn_roster()))
	debug_tools.add_child(hud.button("显示 / 隐藏真实占地",func():if dev_mode and debug_available:overlay.collisions=not overlay.collisions))
	debug_tools.add_child(hud.button("80°朝向边界轮检",func():if dev_mode and debug_available:start_angle_test()))
	debug_tools.add_child(hud.button("224 单位 + 32 建筑场景",func():if dev_mode and debug_available:start_match("handmade",73026,"rivet");dev_mode=true;setup_benchmark()))
	c.add_child(hud.button("关闭调试面板",func():set_debug_visible(false)))

func set_debug_enabled(enabled: bool) -> void:
	debug_available=enabled
	_sync_developer_options()
	hud.set_debug_available(enabled)
	hud.dev_button.visible=enabled and started and not hud.entry_menu.visible
	if not enabled:set_debug_visible(false)
	if debug_tools!=null:debug_tools.visible=dev_mode and enabled
	if debug_tools_scroll!=null:debug_tools_scroll.visible=dev_mode and enabled

func set_audio_browser_enabled(enabled: bool) -> void:
	audio_browser_enabled = enabled
	if hud != null and hud.wiki != null and hud.wiki.has_method("configure_audio_browser"):
		hud.wiki.configure_audio_browser(audio,enabled)

func set_debug_visible(show: bool) -> void:
	debug_panel.visible=show and debug_available
	var measure: bool = debug_panel.visible or benchmark
	RenderingServer.viewport_set_measure_render_time(battlefield_viewport.get_viewport_rid(),measure)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),measure)
	if debug_panel.visible:refresh_debug_metrics()

func refresh_debug_metrics() -> void:
	debug_tools.visible=dev_mode and debug_available
	debug_tools_scroll.visible=dev_mode and debug_available
	_sync_developer_options()
	var gpu_ms: float = RenderingServer.viewport_get_measured_render_time_gpu(battlefield_viewport.get_viewport_rid())+RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	var cpu_ms: float = RenderingServer.viewport_get_measured_render_time_cpu(battlefield_viewport.get_viewport_rid())+RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid())+RenderingServer.get_frame_setup_time_cpu()
	var render_size: Vector2i = battlefield_viewport.size
	var window_size: Vector2i = get_window().size
	debug_metrics.text="窗口 %d×%d · 战场 %d×%d\n模拟 %.2f ms · 画面同步 %.2f ms\n渲染CPU %.2f ms · GPU %.2f ms\n实体 %d · 绘制调用 %d\n镜头 距离 %.1f · 俯角 %.0f°\n3D倍率 %.0f%% · UI保持原生分辨率\n地图种子 %d · 实时对局，不暂停" % [window_size.x,window_size.y,render_size.x,render_size.y,sim_cpu_ms,world_cpu_ms,cpu_ms,gpu_ms,sim.entities.size(),int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),distance,effective_camera_pitch(),render_scale*100.0,sim.map.seed]

func _sync_developer_options() -> void:
	if sim == null: return
	var available: bool = dev_mode and debug_available and str(sim.map.get("mode","")) == "dev"
	var instant: bool = available and debug_instant_build
	if bool(sim.match_options.get("developer_debug_enabled",false)) != available or bool(sim.match_options.get("developer_instant_build",false)) != instant:
		_flush_render_simulation()
		sim.match_options.developer_debug_enabled = available
		sim.match_options.developer_instant_build = instant
	if debug_instant_toggle != null: debug_instant_toggle.set_pressed_no_signal(debug_instant_build)
	if debug_faction_picker != null and not sim.factions.is_empty():
		for index: int in debug_faction_picker.item_count:
			if str(debug_faction_picker.get_item_metadata(index)) == str(sim.factions[0]):
				# Preserve an actively selected next faction while the panel is open.
				if not debug_panel.visible: debug_faction_picker.select(index)
				break

func _debug_switch_faction() -> void:
	if not dev_mode or not debug_available: return
	var faction: String = str(debug_faction_picker.get_item_metadata(debug_faction_picker.selected))
	if start_match("dev",73026,faction):
		set_debug_visible(true)
		_debug_generate_buildings()

func _debug_generate_buildings() -> void:
	if not dev_mode or not debug_available: return
	_flush_render_simulation()
	_sync_developer_options()
	var report: Dictionary = DeveloperTools.generate_all_buildings(sim,0)
	var message: String = DeveloperTools.report_text(sim,report)
	debug_building_report.text = message
	post(message)
	world.sync(0.0,selected,{})
	hud.cache_key = ""

func standable_near(pos: Vector2, radius: float=0.8) -> Vector2:
	for ring in range(0,16):
		for j in range(maxi(1,ring*8)):
			var p:Vector2=pos+Vector2.from_angle(float(j)/maxi(1,ring*8)*TAU)*ring*1.8
			if p.x<2 or p.y<2 or p.x>sim.map.size-2 or p.y>sim.map.size-2:continue
			if MapData.terrain_at(sim.map,p) in [1,4]:continue
			# Reserve the requested footprint against forests, mines and cliffs too.
			# A small point-sized forest pocket can have no usable exit.
			if not sim._standing(p,radius,-1,false):continue
			var available:bool=true
			for e in sim.entities.values():
				var d:Dictionary=sim.data_for(e.spec)
				var er:float=float(d.get("size",1))*0.73 if e.kind=="building" else float(d.radius)
				if e.pos.distance_to(p)<er+radius+0.1:available=false;break
			if available:return p
	return pos

func spawn_roster() -> void:
	if not dev_mode:return
	for team in range(2):
		var s:Array=sim.map.starts[team]
		var center:=Vector2(s[0],s[1])+Vector2(5 if team==0 else -5,3)
		var index:int=0
		for spec in sim.rules.units:
			if sim.rules.units[spec].faction!=sim.factions[team]:continue
			var p:=standable_near(center+Vector2((index%3)*2.5,(index/3)*2.5))
			var id:int=sim.debug_spawn(team,spec,p)
			if team==0:selected.append(id)
			index+=1
	post("试验场已加入两阵营独立兵种，右键可移动与交战。")

func start_angle_test() -> void:
	var p:=standable_near(focus)
	angle_test_id=sim.debug_spawn(0,sim.factions[0]+"_rifle",p)
	selected=[angle_test_id]
	sim.entities[angle_test_id].alpha=0.0
	angle_index=0;angle_clock=0
	post("每2秒轮检 0 / ±79 / ±80 / ±81 / ±90 / ±135 / 180°。Q/E 可同时环绕。")

func setup_benchmark() -> void:
	dev_mode=true
	sim.ai_enabled=false
	sim.money=[100000.0,100000.0]
	var total_units:int=benchmark_count
	var attack_groups: Array = [[],[]]
	for team in range(2):
		var s:Array=sim.map.starts[team]
		var base:=Vector2(s[0],s[1])
		for i in range(15):
			var role:String=["power","refinery","barracks","factory","tower"][i%5]
			var p:=standable_near(base+Vector2((i%5-2)*7,(i/5+1)*7),3.0)
			var id:int=sim.debug_spawn(team,sim.building_spec(team,role),p)
			if sim.entities.has(id):
				sim.entities[id].construct_remaining=0.0
				sim.entities[id].gift_pending=false
		var ids:Array=[]
		for i in range(total_units/2):
			var role:String="rifle"
			if i%7==0:role="tank"
			elif i%11==0:role="harvester"
			elif i%5==0:role="anti"
			var p:=standable_near(base+Vector2((i%12-6)*1.8,(i/12-5)*1.8))
			var id:int=sim.debug_spawn(team,sim.factions[team]+"_"+role,p)
			if role!="harvester":ids.append(id)
		var enemy:Array=sim.map.starts[1-team]
		attack_groups[team]=ids
		for e in sim.entities.values():
			if e.team==team and e.kind=="building":
				var role:String=sim.data_for(e.spec).role
				if sim.TechAvailability.producer_matches(sim, e, "barracks"):sim.produce(e.id,sim.factions[team]+"_rifle")
				if role=="factory":sim.produce(e.id,sim.factions[team]+"_tank")
	# Both bases must exist before formation goals are chosen.
	for team in range(2):
		var enemy: Array=sim.map.starts[1-team]
		sim.issue(attack_groups[team],"attack_move",Vector2(enemy[0],enemy[1]))
	focus=Vector2(sim.map.size*0.5,sim.map.size*0.60)
	distance=110
	if benchmark:
		yaw=0.0
		get_viewport().gui_disable_input=true
		get_window().title="Paper Front - Automated graphics stress test"
	benchmark_started_us=Time.get_ticks_usec()
	benchmark_previous_frame_us=0
	frame_samples.clear()
	cpu_samples.clear()
	process_samples.clear()
	render_cpu_samples.clear()
	gpu_samples.clear()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	RenderingServer.viewport_set_measure_render_time(battlefield_viewport.get_viewport_rid(),true)
	world_cpu_samples.clear()
	benchmark_peak_entities=sim.entities.size()
	benchmark_events.clear()
	benchmark_tick_count=0
	benchmark_interval_sim_ms=0.0
	benchmark_slow_frames.clear()
	benchmark_frames_over_budget=0
	post("性能开发场景：%d 个移动单位 + %d 座建筑；移动、采矿、生产和战斗使用正常规则。" % [sim.counts(0).x+sim.counts(1).x,sim.counts(0).y+sim.counts(1).y])

func finish_benchmark() -> void:
	benchmark=false
	frame_samples.sort()
	cpu_samples.sort()
	process_samples.sort()
	world_cpu_samples.sort()
	render_cpu_samples.sort()
	gpu_samples.sort()
	var c0:=sim.counts(0)
	var c1:=sim.counts(1)
	var sum_frame:float=0
	for f in frame_samples:sum_frame+=f
	var sum_cpu:float=0
	for t in cpu_samples:sum_cpu+=t
	var result_data:Dictionary={"godot":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"logical_viewport":get_viewport().get_visible_rect().size,"render_pixels":get_viewport().get_texture().get_image().get_size(),"duration_seconds":benchmark_elapsed,"simulation_seconds":sim.time,"physics_ticks":benchmark_tick_count,"events":benchmark_events,"window_pixels":get_window().size,"initial_moving_units":benchmark_count,"initial_buildings":32,"final_moving_units":c0.x+c1.x,"final_buildings":c0.y+c1.y,"frames_sampled":frame_samples.size(),"mean_fps":1000.0/(sum_frame/maxi(1,frame_samples.size())),"frame_p95_ms":frame_samples[int(frame_samples.size()*0.95)] if not frame_samples.is_empty() else 0,"frame_p99_ms":frame_samples[int(frame_samples.size()*0.99)] if not frame_samples.is_empty() else 0,"max_frame_ms":frame_samples.back() if not frame_samples.is_empty() else 0,"world_sync_p95_ms":world_cpu_samples[int(world_cpu_samples.size()*0.95)] if not world_cpu_samples.is_empty() else 0,"engine_process_p95_ms":process_samples[int(process_samples.size()*0.95)] if not process_samples.is_empty() else 0,"mean_simulation_ms":sum_cpu/maxi(1,cpu_samples.size()),"simulation_p95_ms":cpu_samples[int(cpu_samples.size()*0.95)] if not cpu_samples.is_empty() else 0,"entity_peak":benchmark_peak_entities,"draw_calls":int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),"primitives":int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),"gpu_frame_ms":"pending measured renderer timestamps","processor":OS.get_processor_name()}
	var out_path:String=benchmark_output if not benchmark_output.is_empty() else "user://benchmark_%d.json" % benchmark_count
	result_data["frames_over_16_67_ms"]=benchmark_frames_over_budget
	result_data["slow_frames_over_33_33_ms"]=benchmark_slow_frames
	result_data["path_plans_per_tick"]=WarSimulation.PATH_PLANS_PER_TICK
	result_data["maximum_path_planning_wait_seconds"]=sim._planning_max_wait
	result_data["background_navigation"]=sim.navigation_stats.duplicate()
	result_data["render_cpu_p95_ms"]=render_cpu_samples[int(render_cpu_samples.size()*0.95)] if not render_cpu_samples.is_empty() else "unavailable: renderer readout stayed zero"
	var sum_gpu:float=0.0
	for sample in gpu_samples:sum_gpu+=sample
	result_data["gpu_samples"]=gpu_samples.size()
	result_data["gpu_frame_ms"]="measured: see gpu_mean_ms and gpu_p95_ms" if not gpu_samples.is_empty() else "unavailable: GPU readout stayed zero after measurement was enabled"
	result_data["gpu_mean_ms"]=sum_gpu/gpu_samples.size() if not gpu_samples.is_empty() else null
	result_data["gpu_p95_ms"]=gpu_samples[int(gpu_samples.size()*0.95)] if not gpu_samples.is_empty() else null
	result_data["scenery_lods"]=scenery_lod_metadata()
	result_data["photography"]=LENS.metadata(lens)
	result_data["battlefield_render_pixels"]=battlefield_viewport.size
	result_data["render_scale"]=render_scale
	result_data["internal_3d_pixels"]=Vector2i(Vector2(battlefield_viewport.size)*render_scale)
	result_data["camera"]={"distance":distance,"pitch":effective_camera_pitch(),"pitch_mode":camera_pitch_mode,"fixed_pitch":camera_pitch,"yaw":yaw,"focus":[focus.x,focus.y],"input_locked":get_viewport().gui_disable_input}
	result_data["lighting"]={"key_color":key_light.light_color.to_html(),"key_energy":key_light.light_energy,"rotation_degrees":key_light.rotation_degrees,"ambient_energy":environment.ambient_light_energy,"ssao_enabled":environment.ssao_enabled,"shadow_enabled":key_light.shadow_enabled}
	var file:=FileAccess.open(out_path,FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(result_data,"  "))
	print("BENCHMARK ",JSON.stringify(result_data))
	print("BENCHMARK_FILE ",out_path)
	quit_game()

func load_preferences() -> void:
	var settings:=ConfigFile.new()
	if settings.load("user://settings.cfg")!=OK:return
	set_debug_enabled(bool(settings.get_value("debug","enabled",debug_available)))
	set_audio_browser_enabled(bool(settings.get_value("debug","audio_browser_enabled",true)))
	var mix:Dictionary=audio.get_mix()
	var old_default_mix: Dictionary={"master":.85,"music":.45,"sfx":.90,"voice":.85}
	var legacy_defaults: bool=int(settings.get_value("audio","baseline_version",0))<11
	for key:String in old_default_mix:
		legacy_defaults=legacy_defaults and settings.has_section_key("audio",key) and is_equal_approx(float(settings.get_value("audio",key,-1.0)),float(old_default_mix[key]))
	for key:String in ["master","music","sfx","voice"]:
		mix[key]=1.0 if legacy_defaults else clampf(float(settings.get_value("audio",key,mix[key])),0.0,2.0)
	mix["commander"] = clampf(float(settings.get_value("audio", "commander", .6)), 0.0, 2.0)
	mix["muted"]=bool(settings.get_value("audio","muted",false))
	audio.set_mix(mix)
	hud.muted=audio.muted
	# Stable faction IDs survive menu ordering changes in saved preferences.
	var faction_id: String = str(settings.get_value("game", "faction_id", "rivet" if int(settings.get_value("game", "faction", 1)) == 0 else "kestrel"))
	hud.select_faction(faction_id)
	var map_mode:String=str(settings.get_value("game","map_mode","forest"))
	if not settings.has_section_key("game","map_mode") and settings.has_section_key("game","map"):
		map_mode=["handmade","random","dev"][clampi(int(settings.get_value("game","map",0)),0,2)]
	hud.select_map(map_mode)
	var saved_match: Variant = settings.get_value("game", "match_options", {})
	if saved_match is Dictionary: hud.match_setup.restore(saved_match)
	hud.seed_input.text=str(settings.get_value("game","seed",73026))
	# Loading a preference must not fire the live slider's save handler before
	# the graphics preferences below have been read.
	camera_pitch=clampf(float(settings.get_value("camera","pitch",30.0)),20.0,45.0)
	camera_pitch_mode="fixed" if str(settings.get_value("camera","pitch_mode","dynamic"))=="fixed" else "dynamic"
	_sync_pitch_controls()
	set_render_scale(float(settings.get_value("graphics","render_scale",1.0)))
	dof_override = int(bool(settings.get_value("graphics", "depth_of_field", true))) if settings.has_section_key("graphics", "depth_of_field") else -1
	set_graphics_quality(str(settings.get_value("graphics", "quality", "balanced")))
	environment.ssao_enabled=bool(settings.get_value("graphics","ambient_occlusion",true))
	key_light.shadow_enabled=bool(settings.get_value("graphics","shadows",true))
	if bool(settings.get_value("graphics","fullscreen",false)) and not golden_mode and not benchmark:
		get_window().mode=Window.MODE_FULLSCREEN

func save_preferences() -> void:
	if quit_pending:return
	var settings:=ConfigFile.new()
	for key:String in audio.get_mix():settings.set_value("audio",key,audio.get_mix()[key])
	settings.set_value("audio","baseline_version",11)
	settings.set_value("graphics","fullscreen",get_window().mode in [Window.MODE_FULLSCREEN,Window.MODE_EXCLUSIVE_FULLSCREEN])
	settings.set_value("camera","pitch",camera_pitch)
	settings.set_value("camera","pitch_mode",camera_pitch_mode)
	settings.set_value("graphics","render_scale",render_scale)
	settings.set_value("graphics", "quality", graphics_quality)
	settings.set_value("graphics","ambient_occlusion",environment.ssao_enabled)
	settings.set_value("graphics","shadows",key_light.shadow_enabled)
	settings.set_value("debug","enabled",debug_available)
	settings.set_value("debug","audio_browser_enabled",audio_browser_enabled)
	if dof_override >= 0: settings.set_value("graphics", "depth_of_field", dof_override == 1)
	settings.set_value("game", "faction_id", hud.selected_faction())
	settings.set_value("game","map_mode",hud.selected_map())
	settings.set_value("game","seed",hud.seed_input.text.to_int())
	settings.set_value("game","match_options",hud.match_setup.options(hud.selected_faction()))
	var err:int=settings.save("user://settings.cfg")
	if err!=OK:post("设置写入失败："+error_string(err))

func showcase_base() -> void:
	if not dev_mode:return
	for team in range(2):
		var sx:float=float(sim.map.starts[team][0])
		var sign_x:float=1.0 if team==0 else -1.0
		for item in [["power",Vector2(-4,4)],["barracks",Vector2(0,10)],["refinery",Vector2(6,10)],["tower",Vector2(5,-5)]]:
			var desired:=Vector2(sx+item[1].x*sign_x,float(sim.map.starts[team][1])+item[1].y)
			var p:=standable_near(desired,2.5)
			var id:int=sim.debug_spawn(team,sim.building_spec(team,str(item[0])),p)
			sim.entities[id].gift_pending=false
		var fighters:Array=[]
		for e in sim.entities.values():
			if e.team==team and e.kind=="unit" and sim.data_for(e.spec).weapon!="":fighters.append(e.id)
		sim.issue(fighters,"attack_move",Vector2(24.0+sign_x*3,31.0))

func showcase_diorama(ready_preview: bool=false) -> void:
	# Explicit developer scene: the regular match still begins with one paid HQ.
	selected.clear()
	for team in range(2):
		var mirror:float=1.0 if team==0 else -1.0
		var base:=Vector2(63 if team==0 else 97,92)
		for item in [["hq",Vector2(-5,-3)],["power",Vector2(-8,5)],["barracks",Vector2(-5,14)],["refinery",Vector2(1,15)],["factory",Vector2(1,5)],["tower",Vector2(7,-5)]]:
			var spot:Vector2=standable_near(base+Vector2(item[1].x*mirror,item[1].y),float(sim.rules.buildings[sim.building_spec(team,str(item[0]))].size)*.6)
			var id:int=sim.debug_spawn(team,sim.building_spec(team,str(item[0])),spot)
			sim.entities[id].construct_remaining=0.0
			sim.entities[id].gift_pending=false
		var mine_pos:Vector2=standable_near(base+Vector2(0,21),1.4)
		sim.map.mines.append({"pos":[mine_pos.x,mine_pos.y],"capacity":3000})
		sim.mines.append({"pos":mine_pos,"capacity":3000.0,"amount":3000.0})
	sim.build(0,"rivet_power")
	for i in range(480 if ready_preview else 135):sim.step(1.0/30.0)
	for team in range(2):
		var fighters:Array=[]
		var mirror:float=1.0 if team==0 else -1.0
		var base:=Vector2(70 if team==0 else 90,99)
		for i in range(12):
			var kind:String=["tank","rifle","anti","rifle","tank","engineer","rifle","rifle","harvester","rifle","anti","assault" if team==0 else "demolition"][i]
			var p:Vector2=standable_near(base+Vector2(-float(i%3)*3*mirror,float(i/3)*3),float(sim.rules.units[sim.factions[team]+"_"+kind].radius))
			var id:int=sim.debug_spawn(team,sim.factions[team]+"_"+kind,p)
			sim.entities[id].alpha=0.0 if team==0 else 180.0
			sim.entities[id].turret_alpha=sim.entities[id].alpha
			if kind=="tank" and team==0:selected.append(id)
			if sim.data_for(sim.entities[id].spec).weapon!="":fighters.append(id)
		sim.issue(fighters,"attack_move",Vector2(87 if team==0 else 73,96))
	world.setup(sim,camera)
	feedback.clear()
	post("开发展示场景：前线基地、河桥与独立部队。正常遭遇战仍从总部开局。")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:quit_game()

func quit_game(exit_code: int=0) -> void:
	_collect_render_simulation()
	_queued_simulation_delta=0.0
	if quit_pending:return
	quit_pending=true
	started=false
	benchmark=false
	if is_instance_valid(audio):audio.stop_all()
	# Let the audio mixer release active WAV playback before engine teardown.
	await get_tree().create_timer(0.12).timeout
	get_tree().quit(exit_code)
