extends SceneTree

const OUTPUT := "res://artifacts/feedback_v10_20261006/camera/"
var rows: Array[Dictionary] = []
var failures: Array[String] = []

func _initialize() -> void:call_deferred("run")

func capture(game, name: String) -> void:
	for frame: int in 8:await process_frame
	await RenderingServer.frame_post_draw
	var image: Image=root.get_texture().get_image()
	if image==null or image.is_empty() or image.save_png(OUTPUT+name+".png")!=OK:
		failures.append("capture failed: "+name)
	var target:=Vector3(game.focus.x,MapData.height_at(game.sim.map,game.focus),game.focus.y)
	var span: float=game.camera.unproject_position(target+Vector3(1,0,0)).distance_to(game.camera.unproject_position(target))
	rows.append({"name":name,"map_size":game.sim.map.size,"requested_distance":game.distance,"actual_distance":game.camera_actual_distance,"pitch":game.camera_effective_pitch,"fov":game.camera.fov,"map_ceiling":game.camera_clearance_height,"focus_height":target.y,"camera_y":game.camera.position.y,"projected_one_meter_pixels":span})

func run() -> void:
	if DisplayServer.get_name()=="headless":push_error("GPU display is required");quit(2);return
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.size=Vector2i(1440,810)
	var game=load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false);game.set_physics_process(false);game.audio.muted=true
	for mode: String in ["dev","forest"]:
		if not game.start_match(mode,73026,"kestrel",false):failures.append("could not start "+mode);continue
		game.sim.ai_enabled=false
		game.hud.show_menu(false);game.hud.show_entry(false)
		game.resize_battlefield()
		game.camera_pitch_mode="dynamic";game.yaw=0.0
		for frame: int in 90:game.world.sync(.016,[]);game.sim.events.clear()
		game.distance=90.0;game.update_camera();game.world.sync(0,[])
		await capture(game,mode+"_overview")
		game.distance=20.0;game.update_camera();game.world.sync(0,[])
		await capture(game,mode+"_close")
		if rows[-1].projected_one_meter_pixels<=rows[-2].projected_one_meter_pixels*3.0:failures.append(mode+" close zoom did not enlarge the battlefield enough")
		if absf(game.camera_effective_pitch-20.0)>.001:failures.append(mode+" close zoom lost its intended low angle")
	var report: Dictionary={"status":"PASS" if failures.is_empty() else "FAIL","failures":failures,"rows":rows,"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"scope":"actual source main Camera3D, full real 48x48 and 320x320 maps; frozen simulation; projection measurement plus GPU captures"}
	var file:=FileAccess.open(OUTPUT+"capture_report.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("LARGE_MAP_ZOOM_V10_CAPTURE ",JSON.stringify(report))
	game.quit_pending=true;game.audio.stop_all();await create_timer(.25).timeout
	game.queue_free();await process_frame;await create_timer(.25).timeout
	quit(0 if failures.is_empty() else 1)
