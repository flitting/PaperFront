extends SceneTree
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func run()->void:
	var game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_physics_process(false);game.audio.muted=true
	for row in game.sim.map.heights:row.fill(0.0)
	for row in game.sim.map.terrain:row.fill(MapData.LAND)
	game._camera_local_clearance.buckets.clear()
	game.focus=Vector2(24,22);game.distance=20;game.camera_pitch=20;game.yaw=0;game.update_camera()
	var y:float=game.camera.position.y
	game.focus+=Vector2(.3,0);game.update_camera()
	check(is_equal_approx(y,game.camera.position.y),"flat-area panning preserves camera height")
	for row in game.sim.map.heights:row.fill(20.0)
	game.update_camera()
	check(is_equal_approx(game.camera.position.y,y+20),"high ground changes the local reference without disabling close zoom")
	check(is_equal_approx(game.camera_actual_distance,20),"close orbit uses requested distance when eye is clear")
	game.distance=80;game.update_camera()
	check(game.camera.position.y>y+20,"zooming out raises the actual camera")
	game.quit_pending=true;game.audio.stop_all();await create_timer(.2).timeout
	game.queue_free();await process_frame
	print("CAMERA_HEIGHT_TESTS ",JSON.stringify({"checks":checks,"failures":failures}))
	call_deferred("finish")
func finish()->void:
	await create_timer(.2).timeout
	for failure:String in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
