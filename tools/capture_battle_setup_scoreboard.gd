extends SceneTree
const HUD=preload("res://scripts/paper_hud.gd")
var output_dir:="res://artifacts/feedback_v11_20261007/battle_ui"
var failures:Array[String]=[]
var images:Array=[]
func _initialize()->void:call_deferred("run")
func frames(count:int=4)->void:
	for i in range(count):await process_frame
	await RenderingServer.frame_post_draw
func capture(view:Viewport,name:String)->void:
	await frames()
	var image:Image=view.get_texture().get_image()
	var path:String=output_dir.path_join(name+".png")
	if image==null or image.is_empty() or image.save_png(path)!=OK:failures.append("Capture failed: "+path)
	else:images.append({"file":path,"size":[image.get_width(),image.get_height()]})
func run()->void:
	if DisplayServer.get_name()=="headless":push_error("Actual GPU display required");quit(2);return
	DirAccess.make_dir_recursive_absolute(output_dir)
	var hud=HUD.new();root.add_child(hud)
	await frames()
	for dimensions:Vector2i in [Vector2i(1100,700),Vector2i(1440,810),Vector2i(1920,1080),Vector2i(3840,2160)]:
		root.size=dimensions
		await frames()
		hud.show_entry(true)
		await capture(root,"entry_%d"%dimensions.x)
		hud.select_faction("sky");hud.select_map("islands");hud.match_setup.players_option.select(1);hud.match_setup.players_option.item_selected.emit(1)
		hud.seed_input.text="73026";hud._request_map_preview();hud.show_menu(true)
		var deadline:int=Time.get_ticks_msec()+30000
		while hud.map_thumbnail.source_key!="islands/73026/3" and Time.get_ticks_msec()<deadline:await process_frame
		await capture(root,"new_battle_%d"%dimensions.x)
		if not hud.menu.get_global_rect().encloses(hud.map_thumbnail.get_global_rect()):failures.append("Map preview overflow")
		var stats:Dictionary={"duration":512.0,"map_mode":"islands","history_complete":true,"teams":[{"team":0,"faction":"sky","units_killed":34,"units_lost":12,"buildings_destroyed":9,"buildings_lost":2,"units_produced":46,"buildings_built":15,"funds_earned":21680,"funds_spent":17840,"money_remaining":3840,"alive_units":34,"alive_buildings":13,"damage_dealt":12650},{"team":1,"faction":"iron","units_killed":8,"units_lost":21,"buildings_destroyed":2,"buildings_lost":6,"units_produced":25,"buildings_built":9,"funds_earned":14200,"funds_spent":13150,"money_remaining":1050,"alive_units":4,"alive_buildings":3,"damage_dealt":4650},{"team":2,"faction":"rivet","units_killed":4,"units_lost":25,"buildings_destroyed":0,"buildings_lost":3,"units_produced":27,"buildings_built":7,"funds_earned":15600,"funds_spent":14380,"money_remaining":1220,"alive_units":2,"alive_buildings":4,"damage_dealt":5930}]}
		hud.scoreboard.show_result(stats,"win")
		await capture(root,"scoreboard_%d"%dimensions.x)
		hud.scoreboard.close_scoreboard()
	var report:Dictionary={"status":"PASS" if failures.is_empty() else "FAIL","failures":failures,"renderer":RenderingServer.get_current_rendering_method(),"scope":"actual same-window scoreboard controls and actual MapData thumbnail; scoreboard statistics are an explicit visual fixture, not a played-round claim","images":images}
	var file:=FileAccess.open(output_dir.path_join("capture_report.json"),FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(report,"  "))
	print("BATTLE_UI_CAPTURE ",JSON.stringify(report))
	hud.queue_free();await frames();quit(0 if failures.is_empty() else 1)
