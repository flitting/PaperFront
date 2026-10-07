extends SceneTree

var game
var checks: int = 0
var failures: Array[String] = []
var backups: Dictionary = {}
var capture_output: String = ""
var trajectory: Array = []

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func frames(count: int = 3) -> void:
	for _frame in range(count): await process_frame
func reset_zoom(value: float) -> void:
	game.camera_pitch_mode = "dynamic"
	game.distance = value
	game.update_camera()
func wheel(direction: int, factor: float = 1.0, position: Vector2 = Vector2.INF) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_DOWN if direction > 0 else MOUSE_BUTTON_WHEEL_UP
	event.pressed = true; event.factor = factor
	event.position = game.battlefield_rect().get_center() if not position.is_finite() else position
	root.push_input(event, true)
func advance(seconds: float, hz: int = 60) -> void:
	var elapsed: float = 0.0
	while elapsed < seconds - .00000001:
		var dt: float = minf(1.0 / float(hz), seconds - elapsed)
		game._advance_camera_zoom(dt); game.update_camera()
		elapsed += dt
func actual_pitch() -> float:
	return rad_to_deg(asin(clampf(absf(game.camera.global_basis.z.normalized().y),0.0,1.0)))
func preserve_files() -> void:
	for path in ["user://settings.cfg","user://skirmish_v1.pfront"]: backups[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null
func restore_files() -> void:
	for path in backups:
		if backups[path] == null: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		else:
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file != null: file.store_buffer(backups[path]); file.close()
	backups.clear()
func _finalize() -> void: restore_files()

func run() -> void:
	if OS.get_environment("XDG_DATA_HOME").is_empty(): push_error("camera_smoothing_tests requires isolated XDG_DATA_HOME"); quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-smoothing="): capture_output = arg.trim_prefix("--capture-smoothing=")
	preserve_files(); root.size = Vector2i(1600,900)
	game = load("res://main.tscn").instantiate(); root.add_child(game)
	game.set_process(false); game.set_physics_process(false)
	await frames()
	game.started = true; game.hud.is_started = true
	game.hud.show_entry(false); game.hud.show_menu(false)
	game.hud.refresh(game.sim, [], game.camera, false, "", 0.0, -1, false)
	await frames()
	_test_real_input()
	_test_fractional_input()
	_test_frame_rate_invariance()
	_test_reverse_and_limits()
	_test_full_range_scroll_count()
	await _test_modal_input_and_pitch()
	await _test_resets()
	await _capture_trajectory()
	game.audio.stop_all(); await create_timer(.15).timeout
	game.quit_pending = true; game.queue_free(); await process_frame; game = null
	restore_files(); call_deferred("finish")

func _test_real_input() -> void:
	reset_zoom(40)
	var before_pitch: float = actual_pitch()
	var before_outline: PackedVector2Array = game.hud.mini._outline_world.duplicate()
	wheel(1)
	check(is_equal_approx(game.distance,40) and is_equal_approx(game.zoom_target_distance,41.2),"real viewport wheel sets a 3-percent target without moving the displayed view")
	check(is_equal_approx(actual_pitch(),before_pitch),"dynamic pitch does not jump to the queued target")
	var previous: float = game.distance
	var heights: Array = []
	for frame in range(12):
		game._advance_camera_zoom(1.0/60.0); game.update_camera()
		check(game.distance > previous and game.distance < game.zoom_target_distance,"successive display frames approach the queued zoom monotonically frame="+str(frame))
		check(log(game.distance/previous) <= 1.5/60.0+.000001,"each frame stays within the physical logarithmic zoom rate")
		check(absf(actual_pitch()-lerpf(20,45,smoothstep(20,60,game.distance)))<.001,"dynamic pitch tracks the displayed interpolated zoom")
		check(game.camera.position.y >= game.camera_clearance_height-.001,"smoothed view keeps terrain/scenery clearance")
		heights.append(game.camera.position.y); previous=game.distance
	check(game.hud.mini._outline_world != before_outline,"minimap camera footprint changes on interpolation frames")
	advance(2)
	check(is_equal_approx(game.distance,game.zoom_target_distance),"zoom reaches and settles exactly on its target")
	check(not game._advance_camera_zoom(.016),"settled camera performs no further motion")

func _test_fractional_input() -> void:
	reset_zoom(40);wheel(1,.25)
	check(absf(game.zoom_target_distance-40*pow(1.03,.25))<.000001,"fractional wheel factor preserves high-resolution scroll amount")
	reset_zoom(40);wheel(1,.5);wheel(1,.5)
	check(absf(game.zoom_target_distance-41.2)<.000001,"two half wheel increments equal one full increment")
	reset_zoom(40);game._queue_camera_zoom(1,.00001)
	check(absf(game.zoom_target_distance-40*pow(1.03,.00001))<.000001,"tiny nonzero wheel amounts never become an accidental full notch")
	reset_zoom(40);game._queue_camera_zoom(1,0)
	check(absf(game.zoom_target_distance-41.2)<.000001,"unsupported zero wheel factor safely falls back to one step")
	reset_zoom(40);game._queue_camera_zoom(1,-.25)
	check(absf(game.zoom_target_distance-40*pow(1.03,.25))<.000001,"negative factor uses magnitude while button controls direction")
	var target:float=game.zoom_target_distance;game._queue_camera_zoom(1,NAN)
	check(game.zoom_target_distance==target,"nonfinite wheel amount never changes camera targets")

func _test_frame_rate_invariance() -> void:
	var results:Array=[]
	for hz in [15,30,60,144,240]:
		reset_zoom(20);game._queue_camera_zoom(1,50);advance(.75,hz)
		results.append([game.distance,actual_pitch(),game.camera.fov])
	for result in results:check(absf(result[0]-results[0][0])<.00001 and absf(result[1]-results[0][1])<.002 and absf(result[2]-results[0][2])<.0001,"equal elapsed time yields the same zoom, pitch and projection across frame rates")
	reset_zoom(20);game._queue_camera_zoom(1,50)
	var elapsed:float=0.0;var intervals:Array=[.013,.047,.009,.061,.003,.083];var index:int=0
	while elapsed < .75-.00000001:
		var dt:float=minf(intervals[index%intervals.size()],.75-elapsed)
		game._advance_camera_zoom(dt);game.update_camera();elapsed+=dt;index+=1
	check(absf(game.distance-results[0][0])<.00001,"variable frame times preserve the exact elapsed-time trajectory")
	reset_zoom(40);game._queue_camera_zoom(1,20)
	var target:float=game.zoom_target_distance
	var boundary:float=(log(target/40)-.15)/1.5
	advance(boundary,60);var at_boundary:float=game.distance
	game._advance_camera_zoom(.001);game.update_camera()
	check(game.distance>at_boundary and log(game.distance/at_boundary)<=.0015+.000001,"rate-limited and easing phases join continuously without a speed jump")

func _test_reverse_and_limits() -> void:
	reset_zoom(40);game._queue_camera_zoom(1,30);advance(.2)
	var current:float=game.distance;game._queue_camera_zoom(-1)
	check(absf(game.zoom_target_distance-current/1.03)<.000001,"reversing discards unfinished old travel and rebases on the visible zoom")
	game._advance_camera_zoom(.016);game.update_camera()
	check(game.distance<current,"the first reverse frame immediately moves in the new direction")
	for direction in [-1,1]:
		reset_zoom(40);game._queue_camera_zoom(direction,1000)
		var target:float=8 if direction<0 else 110
		var safe:bool=true;var previous:float=game.distance
		for _frame in range(360):
			game._advance_camera_zoom(1.0/60.0);game.update_camera()
			safe=safe and game.distance>=8 and game.distance<=110 and (game.distance<=previous if direction<0 else game.distance>=previous)
			previous=game.distance
		check(safe and is_equal_approx(game.distance,target),"large wheel burst reaches its limit monotonically without overshoot direction="+str(direction))

func _test_full_range_scroll_count() -> void:
	reset_zoom(20);var steps:int=0
	while game.zoom_target_distance < 110-.000001 and steps<100:game._queue_camera_zoom(1);steps+=1
	check(steps==58,"full minimum-to-maximum zoom requires fifty-eight ordinary wheel notches")
	check(is_equal_approx(game.distance,20),"queuing the complete range never teleports the displayed camera")
	advance(6)
	check(is_equal_approx(game.distance,110),"the complete queued range still settles at the maximum")

func _test_modal_input_and_pitch() -> void:
	reset_zoom(40)
	var panel_point := Vector2.INF
	for panel: Control in game.hud.ui_panels:
		if panel.is_visible_in_tree():panel_point=panel.get_global_rect().get_center();break
	check(panel_point.is_finite(),"scroll test targets a visible HUD panel")
	wheel(1,1,panel_point)
	check(is_equal_approx(game.zoom_target_distance,40),"HUD scrolling changes neither current zoom nor its hidden target")
	game.handle_action("settings_open",null);wheel(1)
	check(is_equal_approx(game.zoom_target_distance,40),"settings modal consumes wheel input without queuing background zoom")
	var before:float=actual_pitch();game.handle_action("pitch",20.0)
	check(game.camera_pitch_mode=="fixed" and is_equal_approx(game.camera_pitch,20) and absf(actual_pitch()-before)<.001,"fixed angle setting changes its target but preserves the currently displayed angle")
	game._process(.016)
	check(actual_pitch()<before and actual_pitch()>20,"fixed angle interpolation advances even while settings is open")
	check(before-actual_pitch()<=90*.016+.001,"large angle changes obey the maximum angular speed on the first frame")
	advance(2)
	check(absf(actual_pitch()-20)<.001,"fixed angle interpolation settles precisely")
	before=actual_pitch();game.handle_action("camera_pitch_mode","dynamic")
	check(absf(actual_pitch()-before)<.001,"changing to dynamic mode does not instantly rotate the camera")
	advance(2)
	check(absf(actual_pitch()-32.5)<.001,"dynamic-mode transition settles at the current displayed zoom's angle")
	game.camera_pitch=45;game.update_camera()
	check(absf(actual_pitch()-45)<.001,"direct diagnostic angle assignment remains immediate")
	game._close_settings()

func _test_resets() -> void:
	reset_zoom(40);game._queue_camera_zoom(1,20);game.distance=25;game.update_camera();advance(2)
	check(is_equal_approx(game.distance,25) and is_equal_approx(game.zoom_target_distance,25),"direct diagnostic zoom cancels pending wheel movement")
	game._queue_camera_zoom(1,20);await game._begin_loading("测试加载","取消旧镜头输入")
	check(is_equal_approx(game.zoom_target_distance,game.distance),"loading begins by discarding any pending zoom")
	await game._finish_loading(false);var current:float=game.distance;advance(1)
	check(is_equal_approx(game.distance,current),"cancelled loading cannot resume stale zoom travel")
	game._queue_camera_zoom(1,20);check(game.start_match("dev",29,"rivet",true),"new small match starts while zoom was pending")
	current=game.distance;advance(1)
	check(is_equal_approx(game.distance,current) and is_equal_approx(game.zoom_target_distance,current),"new match resets current and target zoom together")
	check(game.sim.save_game(game.SAVE_PATH).is_empty(),"isolated reset snapshot writes")
	game._queue_camera_zoom(1,20);await game.load_game_with_loading();current=game.distance;advance(1)
	check(not game.loading and is_equal_approx(game.distance,current) and is_equal_approx(game.zoom_target_distance,current),"restored saved match cannot inherit previous camera travel")

func _capture_trajectory() -> void:
	if capture_output.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(capture_output)
	reset_zoom(40)
	for frame in range(120):
		if frame%8==0:wheel(1 if frame<64 else -1)
		game._advance_camera_zoom(1.0/60.0);game.update_camera();game.world.sync(0,[])
		await RenderingServer.frame_post_draw
		trajectory.append({"frame":frame,"distance":game.distance,"target":game.zoom_target_distance,"pitch":actual_pitch(),"fov":game.camera.fov})
		if frame in [0,8,24,48,64,72,88,119]:check(root.get_texture().get_image().save_png(capture_output.path_join("frame_%03d.png"%frame))==OK,"actual rendered smoothing frame saves "+str(frame))
	var file:=FileAccess.open(capture_output.path_join("trajectory.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(trajectory,"\t"));file.close()

func finish() -> void:
	await process_frame;await create_timer(.2).timeout
	print("CAMERA_SMOOTHING ",JSON.stringify({"checks":checks,"failures":failures,"capture_output":capture_output,"trajectory_frames":trajectory.size()}))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
