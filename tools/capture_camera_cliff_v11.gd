extends SceneTree
const OUTPUT:="res://artifacts/feedback_v11_20261007/camera/"
var captures:Array=[]
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func capture(game,name:String)->void:
	for frame:int in 6:await process_frame
	await RenderingServer.frame_post_draw
	var path:String=OUTPUT+name+".png"
	if root.get_texture().get_image().save_png(path)!=OK:failures.append("could not save "+name)
	captures.append({"file":path,"focus":game.focus,"eye_y":game.camera.position.y,"focal_y":game._camera_terrain_transition.focus_height,"orbit":game.camera_actual_distance,"pitch":game.camera_effective_pitch})
func run()->void:
	if DisplayServer.get_name()=="headless":push_error("GPU display required");quit(2);return
	DirAccess.make_dir_recursive_absolute(OUTPUT);root.size=Vector2i(1440,810)
	var game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_physics_process(false);game.audio.muted=true
	if not game.start_match("forest",73026,"kestrel",false):push_error("real forest could not start");quit(2);return
	game.sim.vision_enabled=false;game.hud.show_entry(false);game.hud.show_menu(false)
	var map:Dictionary=game.sim.map;var steep:=0.0;var crossing:=Vector2.ZERO;var direction:=Vector2.RIGHT
	for z:int in range(18,int(map.size)-18):
		for x:int in range(18,int(map.size)-18):
			for offset:Vector2i in [Vector2i.RIGHT,Vector2i.DOWN]:
				var rise:float=float(map.heights[z+offset.y][x+offset.x])-float(map.heights[z][x])
				if rise>steep:steep=rise;crossing=Vector2(x+.5,z+.5);direction=Vector2(offset)
	game.distance=20;game.camera_pitch_mode="dynamic"
	var orbit_direction:Vector2=direction.orthogonal();game.yaw=atan2(orbit_direction.x,orbit_direction.y)
	game.focus=crossing-direction*12;game._refresh_camera_reference();game.update_camera();game.world.sync(0,[])
	await capture(game,"cliff_before")
	var previous_y:float=game.camera.position.y;var maximum_step:=0.0;var minimum_clearance:=INF;var trace:Array=[]
	for frame:int in 180:
		game.focus+=direction*.15;game.update_camera(1.0/60.0);game.world.sync(1.0/60.0,[])
		maximum_step=maxf(maximum_step,absf(game.camera.position.y-previous_y));previous_y=game.camera.position.y
		var point:=Vector2(game.camera.position.x,game.camera.position.z)
		minimum_clearance=minf(minimum_clearance,game.camera.position.y-float(game._camera_local_clearance.height_at(game.sim,point)))
		trace.append({"y":game.camera.position.y,"focal_y":game._camera_terrain_transition.focus_height,"orbit":game.camera_actual_distance})
		if frame==50:await capture(game,"cliff_approach")
		elif frame==90:await capture(game,"cliff_crossing")
	for frame:int in 120:game.update_camera(1.0/60.0);game.world.sync(0,[])
	await capture(game,"cliff_settled")
	if minimum_clearance<1.99:failures.append("local terrain clearance was lost")
	if maximum_step>.75:failures.append("actual forest traverse still jumps vertically")
	var report:Dictionary={"status":"PASS" if failures.is_empty() else "FAIL","failures":failures,"map":"forest320/73026","steepest_rise":steep,"crossing":crossing,"maximum_eye_y_step_60hz":maximum_step,"minimum_local_clearance":minimum_clearance,"captures":captures,"trace":trace,"renderer":RenderingServer.get_current_rendering_method(),"scope":"actual main camera and actual forest geometry; frozen simulation, controlled60Hz pan, screenshots are not an FPS benchmark"}
	var file:=FileAccess.open(OUTPUT+"cliff_capture_report.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("CAMERA_CLIFF_GPU ",JSON.stringify({"status":report.status,"failures":failures,"steepest_rise":steep,"maximum_eye_y_step_60hz":maximum_step,"minimum_local_clearance":minimum_clearance}))
	game.quit_pending=true;game.audio.stop_all();await create_timer(.2).timeout;game.queue_free();await process_frame;await create_timer(.2).timeout
	quit(0 if failures.is_empty() else 1)
