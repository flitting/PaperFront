extends RefCounted
## Isolated rendered input/startup check; these timings are not battle FPS.
static func summary(values:Array[float])->Dictionary:
	if values.is_empty():return {}
	var ordered:Array[float]=values.duplicate();ordered.sort()
	var total:float=0.0
	for value in values:total+=value
	return {"samples":values.size(),"mean_ms":total/values.size(),"p95_ms":ordered[mini(ordered.size()-1,int(ordered.size()*.95))],"max_ms":ordered.back()}
static func run(game:Node,output:String)->void:
	var failures:Array[String]=[]
	if DisplayServer.get_name()=="headless":push_error("Interaction review requires a display");game.quit_game(2);return
	game._flush_render_simulation();game.set_process(false);game.set_physics_process(false)
	var probe=preload("res://scripts/gameplay_performance.gd").new()
	game.add_child(probe);probe.set_process(false)
	probe.setup(game,{"case":"normal","quality":"balanced","resolution":Vector2i(1920,1080),"render_scale":1.0})
	game.benchmark=false;game.get_viewport().gui_disable_input=false
	var report:Dictionary={"scope":"Rendered 640-map startup, picking and camera checks; frozen rules except explicit first-shot check; not a battle FPS benchmark","startup":game.startup_timings.duplicate(true),"output_pixels":[1920,1080],"render_scale":1.0,"tree_count":game.sim.ruins.filter(func(r):return r.kind=="tree").size()}
	var began:int=Time.get_ticks_usec()
	game.world.sync(0.0,[])
	report.first_roster_model_sync_ms=(Time.get_ticks_usec()-began)/1000.0
	for frame in range(3):await RenderingServer.frame_post_draw
	var actor:int=-1
	var victim:int=-1
	for e in game.sim.entities.values():
		if e.kind=="unit" and str(e.spec).ends_with("_tank"):
			if int(e.team)==0 and actor<0:actor=e.id
			if int(e.team)==1 and victim<0:victim=e.id
	if actor<0 or victim<0:failures.append("Missing actual first-shot actors")
	else:
		var before:int=game.sim.projectiles.size()
		game.sim.entities[actor].alpha=0.0;game.sim.entities[actor].turret_alpha=0.0
		game.world.sync(0.0,[])
		began=Time.get_ticks_usec()
		# A legal nearby ground shot avoids relying on the distant opposing
		# roster being inside this particular tank's weapon range.
		game.sim._launch_shot(game.sim.entities[actor],game.sim.entities[actor].pos+Vector2(3,0),-1,true)
		game.world.sync(.016,[])
		report.first_fire_cpu_ms=(Time.get_ticks_usec()-began)/1000.0
		await RenderingServer.frame_post_draw
		report.first_fire_to_draw_ms=(Time.get_ticks_usec()-began)/1000.0
		if game.sim.projectiles.size()<=before:failures.append("First shot did not create a projectile")
	var tree:Dictionary={}
	var nearest:float=INF
	for ruin in game.sim.ruins:
		if ruin.kind!="tree":continue
		var distance:float=(ruin.pos as Vector2).distance_squared_to(probe.center)
		if distance<nearest:nearest=distance;tree=ruin
	var pick_times:Array[float]=[]
	if tree.is_empty():failures.append("Missing forest tree")
	else:
		game.focus=tree.pos;game.distance=35.0;game.update_camera();game.world.sync(0.0,[])
		for frame in range(2):await RenderingServer.frame_post_draw
		var crown:Vector3=Vector3(tree.pos.x,MapData.height_at(game.sim.map,tree.pos)+1.1,tree.pos.y)
		for piece in game.world.landscape.tree_visuals[tree.id]:
			if piece.get("shadow",false):continue
			var local:AABB=piece.multi.mesh.get_aabb()
			var candidate:Vector3=piece.transform*(local.position+local.size*Vector3(.5,.75,.5))
			if candidate.y>crown.y:crown=candidate
		var pixel:Vector2=game.project_world_to_screen(crown)
		var picked:int=game.pick_entity(pixel)
		if picked>game.sim.RUIN_TARGET_BASE or game.sim.ruin_by_target(picked).get("kind","")!="tree":failures.append("Crown click did not select a visible tree")
		else:
			for sample in range(100):
				began=Time.get_ticks_usec()
				var current:int=game.pick_entity(pixel)
				pick_times.append((Time.get_ticks_usec()-began)/1000.0)
				if current!=picked:failures.append("Repeated crown picking changed without scene changes");break
		report.tree_target=picked;report.tree_pick=summary(pick_times)
	var camera_cpu:Array[float]=[]
	var camera_draw:Array[float]=[]
	game.focus=probe.center
	for frame in range(90):
		began=Time.get_ticks_usec()
		game.focus=probe.center+Vector2(sin(frame*.08)*12.0,cos(frame*.09)*9.0)
		game.distance=43.0+float(frame%45)*1.5
		game.yaw=sin(frame*.06)*.25
		game.update_camera();game.world.sync(.016,[])
		camera_cpu.append((Time.get_ticks_usec()-began)/1000.0)
		await RenderingServer.frame_post_draw
		camera_draw.append((Time.get_ticks_usec()-began)/1000.0)
	report.camera_cpu=summary(camera_cpu);report.camera_to_draw=summary(camera_draw)
	# Exercise the actual fullscreen resize and coordinate conversion path.
	game.get_window().mode=Window.MODE_FULLSCREEN
	for frame in range(3):await RenderingServer.frame_post_draw
	game.resize_battlefield();game.update_camera();game.world.sync(0.0,[])
	for frame in range(2):await RenderingServer.frame_post_draw
	var point:Vector2=game.battlefield_rect().get_center()
	var roundtrip:Vector2=game.battlefield_to_screen(game.screen_to_battlefield(point))
	if point.distance_to(roundtrip)>.01:failures.append("Fullscreen input coordinates do not round-trip")
	report.fullscreen_pixels=[game.get_window().size.x,game.get_window().size.y]
	game.get_window().mode=Window.MODE_WINDOWED;game.get_window().size=Vector2i(1920,1080)
	for frame in range(3):await RenderingServer.frame_post_draw
	report.failures=failures;report.passed=failures.is_empty()
	var manifest:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/performance_build_manifest.json"))
	if manifest is Dictionary:report.runtime_identity=manifest.get("runtime_identity","")
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("INTERACTION_CHECK ",JSON.stringify(report))
	probe.queue_free();game.quit_game(0 if failures.is_empty() else 1)
