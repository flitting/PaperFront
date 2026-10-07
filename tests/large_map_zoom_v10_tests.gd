extends SceneTree
var game
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func actual_pitch()->float:return rad_to_deg(asin(absf(game.camera.global_basis.z.normalized().y)))
func run()->void:
	game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_physics_process(false);game.audio.muted=true
	for mode:String in ["dev","forest"]:
		check(game.start_match(mode,7291,"kestrel",false),"real map starts: "+mode)
		game.sim.ai_enabled=false
		game.focus=game.sim._team_start(0)+Vector2(0,6)
		game.camera_pitch_mode="dynamic";game.yaw=0.0
		game._refresh_camera_reference()
		game.distance=60;game.update_camera()
		var far_height:float=game.camera.position.y
		var ground:Vector3=Vector3(game.focus.x,MapData.height_at(game.sim.map,game.focus),game.focus.y)
		var far_pixels:float=game.camera.unproject_position(ground+Vector3.RIGHT).distance_to(game.camera.unproject_position(ground))
		game.distance=20;game.update_camera()
		var near_pixels:float=game.camera.unproject_position(ground+Vector3.RIGHT).distance_to(game.camera.unproject_position(ground))
		check(near_pixels>far_pixels*2.9,"near zoom truly magnifies on "+mode)
		check(game.camera.position.y<far_height,"physical camera descends at close zoom on "+mode)
		check(absf(actual_pitch()-20.0)<.001,"near zoom retains dynamic low viewing angle on "+mode)
		check(game.camera_actual_distance<game.camera_clearance_height/sin(deg_to_rad(20.0)) or is_equal_approx(game.camera_actual_distance,20),"distant whole-map peak no longer fixes the orbit on "+mode)
		check(is_equal_approx(game.camera_actual_distance,20),"occlusion preserves physical close zoom on "+mode)
		var picked:Vector2=game.ground_at(game.project_world_to_screen(ground))
		check(picked.distance_to(game.focus)<.15,"focused ground remains correctly pickable on "+mode)
	# Controlled valley with a remote tall obstacle: its global height cannot
	# force close zoom above it. A local obstacle still protects the camera.
	game.sim.map.terrain=[];game.sim.map.heights=[];game.sim.map.size=320
	for z in range(320):
		var h:Array=[];h.resize(320);h.fill(0.0);game.sim.map.heights.append(h)
		var t:Array=[];t.resize(320);t.fill(MapData.LAND);game.sim.map.terrain.append(t)
	game.sim.map.heights[250][250]=150.0
	game.sim._size=320
	game.focus=Vector2(40,40);game.distance=20;game.yaw=0;game.camera_pitch_mode="dynamic"
	game._refresh_camera_reference();game.update_camera()
	check(game.camera_clearance_height>=152 and game.camera.position.y<30,"remote150m peak cannot pin the valley camera high")
	var eye:Vector2=Vector2(game.camera.position.x,game.camera.position.z)
	for z in range(floori(eye.y)-1,floori(eye.y)+2):
		for x in range(floori(eye.x)-1,floori(eye.x)+2):game.sim.map.heights[z][x]=18.0
	game.update_camera()
	check(is_equal_approx(game.camera_actual_distance,20),"local obstacle fades instead of raising the orbit (supersedes v10 clearance)")
	game.quit_pending=true;game.audio.stop_all();await create_timer(.2).timeout
	game.queue_free();await process_frame
	print("LARGE_MAP_ZOOM_V10 ",JSON.stringify({"checks":checks,"failures":failures}))
	call_deferred("finish")
func finish()->void:
	await process_frame;await create_timer(.2).timeout
	for failure:String in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
