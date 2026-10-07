extends SceneTree
const CUT=preload("res://scripts/camera_occlusion.gd")
const OUTPUT="res://artifacts/rts_revision_v2_20261007/camera_peripheral/"
var game
var checks:Array=[]
func _initialize()->void:call_deferred("run")
func shot(label:String,enabled:bool)->Image:
	game.update_camera()
	CUT.update(game.camera,Vector3(game.focus.x,game._camera_terrain_transition.focus_height,game.focus.y),enabled)
	game.world.sync(0,[])
	for frame in 6:await process_frame
	await RenderingServer.frame_post_draw
	var result:Image=game.battlefield_viewport.get_texture().get_image()
	result.save_png(OUTPUT+label+".png")
	return result
func diff(a:Image,b:Image,rect:Rect2i)->float:
	var total:=0.0
	for y in range(rect.position.y,rect.end.y):
		for x in range(rect.position.x,rect.end.x):
			var c:Color=a.get_pixel(x,y);var d:Color=b.get_pixel(x,y)
			total+=absf(c.r-d.r)+absf(c.g-d.g)+absf(c.b-d.b)
	return total/float(rect.get_area()*3)
func scenario(spec:String,pos:Vector2,zoom:float=8.0)->void:
	for id in game.sim.entities.keys():game.sim._kill_entity(id,false)
	game.sim.events.clear()
	game.distance=zoom
	var id:int=game.sim._spawn(0,spec,pos,true)
	game.sim.entities[id].alpha=90
	# Rebuild the visual reader between independent fixtures so removing the
	# previous specimen cannot leave frozen explosion/debris batches in view.
	game.world.setup(game.sim,game.camera);game._refresh_camera_reference();game.update_camera();game.world.sync(0,[])
func compare(label:String,region:Rect2i,should_fade:bool)->void:
	var before:Image=await shot(label+"_before",false)
	var faded:Image=await shot(label+"_enabled",true)
	var restored:Image=await shot(label+"_restored",false)
	var change:float=diff(before,faded,region)
	var restore:float=diff(before,restored,Rect2i(Vector2i.ZERO,before.get_size()))
	checks.append({"case":label,"zoom":game.distance,"pitch":game.camera_effective_pitch,"region":region,"mean_difference":change,"restored_mean_difference":restore,"expected_fade":should_fade,"pass":(change>.001 if should_fade else change<.00001) and restore<.00001})
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	DirAccess.make_dir_recursive_absolute(OUTPUT);root.size=Vector2i(1440,900)
	game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_physics_process(false);game.audio.stop_all()
	game.start_match("dev",117,"sky",true);game.sim.vision_enabled=false;game.hud.show_entry(false);game.hud.show_menu(false)
	for id in game.sim.entities.keys():game.sim._kill_entity(id,false)
	for row in game.sim.map.heights:row.fill(0.0)
	for row in game.sim.map.terrain:row.fill(MapData.LAND)
	game.sim.mines.clear();game.sim.bridges.clear();game.sim.map.bridges.clear();game.sim.ruins.clear();game.sim.map.decorations.clear()
	game.sim._refresh_ruin_spatial();game.sim._prepare_terrain_cache()
	game.focus=Vector2(40,40);game.yaw=0;game.distance=8;game.camera_pitch_mode="dynamic"
	game.lens.dof_blur_near_enabled=false;game.lens.dof_blur_far_enabled=false
	game.world.setup(game.sim,game.camera);game._refresh_camera_reference();game.update_camera()
	var center:=Rect2i(560,310,320,280);var edge:=Rect2i(1240,140,200,620)
	scenario("sky_barracks",Vector2(40,42.0));await compare("normal_central_building",center,false)
	scenario("sky_tank",Vector2(42.8,43.4));await compare("foreground_edge_vehicle",edge,true)
	# Same normal-distance edge object viewed at tactical zoom restores opacity.
	game.distance=60;await compare("overview_edge_vehicle",Rect2i(0,0,1440,900),false)
	scenario("sky_tank",Vector2(40,46.4));await compare("camera_near_vehicle",center,true)
	scenario("sky_creator_hand",Vector2(40,46),14);await compare("normal_central_hand",center,false)
	scenario("sky_creator_hand",Vector2(40,50),14);await compare("camera_near_hand",center,true)
	for id in game.sim.entities.keys():game.sim._kill_entity(id,false)
	for z in range(43,46):
		for x in range(35,46):game.sim.map.heights[z][x]=6.0
	game.sim._prepare_terrain_cache();game.world.setup(game.sim,game.camera);game._refresh_camera_reference();game.distance=8
	await compare("camera_near_hillside",center,true)
	var ok:=true
	for check in checks:ok=ok and check.pass
	var result:Dictionary={"status":"PASS" if ok else "FAIL","policy":"Only camera-near or peripheral foreground geometry fades; normal centre remains opaque. Zoom adjusts threshold and fade strength.","checks":checks,"renderer":RenderingServer.get_current_rendering_method()}
	var file:=FileAccess.open(OUTPUT+"report.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close();print("CAMERA_PERIPHERAL ",JSON.stringify(result))
	game.quit_pending=true;game.audio.stop_all();await create_timer(.2).timeout;game.queue_free();await process_frame;await create_timer(.2).timeout;quit(0 if ok else 1)
