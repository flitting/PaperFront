extends SceneTree

var game
var checks: int = 0
var failures: Array[String] = []
var capture_output: String = ""
var preferences_backup: Variant
var preferences_preserved: bool = false

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)
func frames(count: int = 3) -> void:
	for _frame in range(count): await process_frame
func key(code: Key) -> void:
	for pressed in [true,false]:
		var event:=InputEventKey.new();event.keycode=code;event.pressed=pressed
		root.push_input(event,true)
	await frames()
func click(control: Control) -> void:
	var parent:Node=control.get_parent()
	while parent!=null:
		if parent is ScrollContainer:parent.ensure_control_visible(control)
		parent=parent.get_parent()
	await frames()
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=control.get_global_rect().get_center()
		root.push_input(event,true)
	await frames()
func capture(label: String) -> void:
	if capture_output.is_empty() or DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(capture_output)
	check(root.get_texture().get_image().save_png(capture_output.path_join(label+".png"))==OK,"rendered camera capture writes "+label)
func actual_pitch() -> float:
	return rad_to_deg(asin(clampf(absf(game.camera.global_basis.z.normalized().y),0.0,1.0)))
func preserve_preferences() -> void:
	preferences_backup=FileAccess.get_file_as_bytes("user://settings.cfg") if FileAccess.file_exists("user://settings.cfg") else null
	preferences_preserved=true
func restore_preferences() -> void:
	if not preferences_preserved:return
	if preferences_backup==null:DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	else:
		var file:=FileAccess.open("user://settings.cfg",FileAccess.WRITE)
		if file!=null:file.store_buffer(preferences_backup);file.close()
	preferences_preserved=false
func _finalize() -> void: restore_preferences()

func run() -> void:
	if OS.get_environment("XDG_DATA_HOME").is_empty():
		push_error("camera_pitch_tests requires an isolated XDG_DATA_HOME")
		quit(2)
		return
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-camera="):capture_output=argument.trim_prefix("--capture-camera=")
	preserve_preferences()
	root.size=Vector2i(1600,900)
	game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_physics_process(false)
	await frames()
	check(game.camera_pitch_mode=="dynamic","new preferences default to dynamic camera pitch")
	game.started=true;game.hud.is_started=true;game.hud.show_entry(false);game.hud.show_menu(false)
	var saved_clearance:float=game.camera_clearance_height
	var saved_reference:float=game.camera_reference_height
	game.focus=Vector2(24,30)
	game.camera_reference_height=0.0;game.camera_clearance_height=76.0
	game._camera_reference_sim_id=game.sim.get_instance_id()
	for mode in ["dynamic","fixed"]:
		for fixed:float in [20.0,30.0,45.0]:
			game.camera_pitch=fixed;game.camera_pitch_mode=mode
			for zoom:float in [8.0,14.0,20.0,40.0,59.9,60.0,60.1,110.0]:
				game.distance=zoom
				for heading:float in [0.0,1.2,3.14]:
					game.yaw=heading;game.update_camera()
					var expected:float=fixed if mode=="fixed" else (lerpf(10.0,20.0,smoothstep(8.0,20.0,zoom)) if zoom<20.0 else lerpf(20.0,45.0,smoothstep(20.0,60.0,zoom)))
					check(absf(actual_pitch()-expected)<.001,"actual angle matches requested mode/zoom "+str([mode,fixed,zoom,heading]))
					check(is_equal_approx(game.camera_actual_distance,zoom),"occlusion cannot push the physical camera away from requested zoom")
					var target:=Vector3(game.focus.x,MapData.height_at(game.sim.map,game.focus),game.focus.y)
					var viewport_size:Vector2=game.camera.get_viewport().get_visible_rect().size
					check(game.camera.unproject_position(target).distance_to(viewport_size*.5)<.01,"reference focus stays at actual projection center")
					var pixels:float=game.camera.unproject_position(target+game.camera.global_basis.x).distance_to(game.camera.unproject_position(target))
					var dimension:float=viewport_size.y if game.camera.keep_aspect==Camera3D.KEEP_HEIGHT else viewport_size.x
					var expected_pixels:float=dimension/(2.0*zoom*tan(deg_to_rad(game.camera_base_fov)*.5))
					check(absf(pixels-expected_pixels)<.03,"clearance compensation preserves logical near-view pixel size")
					check(game.key_light.directional_shadow_max_distance>=game.camera_actual_distance,"shadows still reach the true camera orbit focus")
					var height:float=game.camera.position.y
					var basis:Basis=game.camera.basis
					game.focus+=Vector2(.3,0);game.update_camera()
					check(game.camera.basis.is_equal_approx(basis),"free panning preserves the requested viewing angle while applying local clearance")
					game.focus-=Vector2(.3,0)
	var stable:float=game.camera.fov
	for _frame in range(50):game.update_camera()
	check(is_equal_approx(game.camera.fov,stable) and is_equal_approx(game.camera_base_fov,42.0),"repeated camera updates never compound compensated FOV")
	game.camera.fov=48.0;game.update_camera()
	check(is_equal_approx(game.camera_base_fov,48.0),"explicit diagnostic FOV assignment resets the stable base")
	game.camera.fov=42.0;game.update_camera()
	game.camera_pitch=20.0;game.distance=game.camera_clearance_height/sin(deg_to_rad(20.0))
	game.update_camera();var before:Vector3=game.camera.position;var before_fov:float=game.camera.fov
	game.distance+=.001;game.update_camera()
	check(game.camera.position.distance_to(before)<.002 and absf(game.camera.fov-before_fov)<.001,"physical orbit and FOV remain continuous at the clearance boundary")
	game.camera_clearance_height=saved_clearance;game.camera_reference_height=saved_reference
	game.camera_pitch_mode="dynamic";game.distance=44.0;game.yaw=0.0;game.update_camera()
	var pitch_before:float=game.effective_camera_pitch()
	await key(KEY_R)
	check(game.camera_pitch_mode=="fixed" and absf(game.camera_pitch-(pitch_before+2))<.001,"R continues from the current dynamic angle rather than stale fixed storage")
	game.camera_pitch_mode="dynamic";game.update_camera();pitch_before=game.effective_camera_pitch()
	await key(KEY_T)
	check(game.camera_pitch_mode=="fixed" and absf(game.camera_pitch-(pitch_before-2))<.001,"T continues from the current dynamic angle")
	game.camera_pitch_mode="dynamic";game.distance=40;game.update_camera()
	var wheel:=InputEventMouseButton.new();wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;wheel.pressed=true;wheel.position=game.battlefield_rect().get_center()
	root.push_input(wheel,true);await frames()
	check(is_equal_approx(game.distance,40) and game.zoom_target_distance>40,"actual wheel input changes the target without jumping the displayed zoom")
	for _frame in range(120):game._advance_camera_zoom(1.0/60.0);game.update_camera()
	check(game.distance>40 and actual_pitch()>32.5,"actual wheel input smoothly advances displayed zoom and dynamic pitch")
	for zoom:float in [8,20,40,60,110]:
		game.camera_pitch_mode="dynamic";game.distance=zoom;game.update_camera();game.world.sync(0,[])
		await capture("dynamic_d"+str(int(zoom)))
	await key(KEY_ESCAPE)
	check(game.hud.settings.pitch_mode.selected==0 and not game.hud.settings.pitch.editable,"settings exposes dynamic mode and an accurately disabled fixed slider")
	var ancestor:Node=game.hud.settings.pitch.get_parent()
	while ancestor!=null:
		if ancestor is ScrollContainer:ancestor.ensure_control_visible(game.hud.settings.pitch)
		ancestor=ancestor.get_parent()
	await frames()
	await capture("settings_dynamic")
	await click(game.hud.settings.pitch_mode)
	var popup:PopupMenu=game.hud.settings.pitch_mode.get_popup();popup.set_focused_item(1)
	var select:=InputEventKey.new();select.keycode=KEY_ENTER;select.pressed=true;select.window_id=popup.get_window_id();Input.parse_input_event(select);await frames()
	check(game.camera_pitch_mode=="fixed" and game.hud.settings.pitch.editable,"actual mode popup switches to fixed controls")
	var slider:HSlider=game.hud.settings.pitch
	await click(slider);slider.grab_focus();await key(KEY_HOME)
	for _frame in range(120):game._advance_camera_zoom(1.0/60.0);game.update_camera()
	check(is_equal_approx(game.camera_pitch,20.0) and absf(actual_pitch()-20.0)<.001,"actual fixed slider input changes the true camera angle while settings is open")
	await capture("settings_fixed")
	game.handle_action("camera_pitch_mode","dynamic")
	game.load_preferences()
	check(game.camera_pitch_mode=="dynamic","dynamic camera mode round-trips through preferences")
	game.handle_action("pitch",27.0);game.load_preferences()
	check(game.camera_pitch_mode=="fixed" and is_equal_approx(game.camera_pitch,27.0),"fixed mode and manual angle round-trip through preferences")
	game._close_settings()
	_test_sky_input()
	game.audio.stop_all()
	await create_timer(.15).timeout
	game.quit_pending=true
	game.queue_free()
	await process_frame
	game=null
	popup=null
	slider=null
	select=null
	restore_preferences()
	# Let run's remaining asynchronous locals release before renderer shutdown.
	call_deferred("finish")

func finish() -> void:
	await process_frame
	await create_timer(.2).timeout
	print("CAMERA_PITCH ",JSON.stringify({"checks":checks,"failures":failures,"dynamic_zoom_range":[8,60],"pitch_range":[10,45],"capture_output":capture_output}))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _test_sky_input() -> void:
	game.camera_clearance_height=2;game.camera_reference_height=0;game.distance=110;game.camera_pitch=20
	game.update_camera()
	var top:Vector2=game.battlefield_to_screen(Vector2(game.battlefield_viewport.size.x*.5,0))
	check(game.camera.project_ray_normal(game.screen_to_battlefield(top)).y>0,"true fixed 20-degree perspective exposes the small upward sky-ray boundary")
	check(not game.ground_at(top).is_finite(),"sky ray returns an invalid ground hit instead of a negative-distance point behind the camera")
	var pick:int=game.pick_entity(top)
	check(pick>=-1 or pick<=game.sim.RUIN_TARGET_BASE,"sky entity picking never sends an infinite region to native grids")
	game.click_select(top,false)
	check(game.inspected_bridge==-1,"sky selection does not inspect a fictitious bridge behind the camera")
	check(not game.command_units("move",Vector2.INF),"invalid sky commands never create a marker or enter navigation")
	var flyer:int=game.sim._spawn(0,"rivet_fighter",Vector2(20,40),true)
	var target:int=game.sim._spawn(1,"kestrel_fighter",Vector2(25,40),true)
	game.selected=[flyer]
	check(game.command_units("force_attack",Vector2.INF,target) and not game.sim.entities[flyer].commands.is_empty() and (game.sim.entities[flyer].commands[0].pos as Vector2).is_finite(),"targeted sky attack resolves a valid aircraft position before native commands or markers")
	game.right_command(Vector2.INF,-1,false)
	game.camera.rotation.x=-.0000001
	var center:Vector2=game.battlefield_rect().get_center()
	check(not game.ground_at(center).is_finite(),"near-horizontal ray safely rejects division into an enormous ground distance")
