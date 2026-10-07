extends SceneTree
const Sim=preload("res://tests/rule_test_simulation.gd")
const O=preload("res://scripts/building_orientation.gd")
var game
var failures:Array[String]=[]
var evidence:Array=[]
const OUT="res://artifacts/building_orientation"
func _initialize()->void:
	if OS.get_environment("PAPER_FRONT_CAPTURE_OFFSCREEN")!="1":quit(2);return
	call_deferred("run")
func frames(n:int=4)->void:
	for i in range(n):await process_frame
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label)
func press_r()->void:
	var key:=InputEventKey.new();key.keycode=KEY_R;key.physical_keycode=KEY_R;key.pressed=true;root.push_input(key,true)
	key=key.duplicate();key.pressed=false;root.push_input(key,true);await frames(2)
func save(name:String,placement:Dictionary={})->void:
	game.world.sync(.016,[],placement)
	game.hud.fps_label.hide()
	await frames()
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(OUT+"/"+name+".png")
func aim(pos:Vector2,distance:float,pitch:float=55)->void:
	game.focus=pos;game.distance=distance;game.zoom_target_distance=distance;game.camera_pitch=pitch;game.camera_pitch_mode="fixed";game._camera_pitch_blending=false;game.update_camera()
func click_world(pos:Vector2)->void:
	var screen:Vector2=game.project_world_to_screen(Vector3(pos.x,0,pos.y))
	var click:=InputEventMouseButton.new();click.position=screen;click.global_position=screen;click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;root.push_input(click,true)
	click=click.duplicate();click.pressed=false;root.push_input(click,true);await frames()
func run()->void:
	root.size=Vector2i(1600,1000);root.content_scale_size=root.size
	DirAccess.make_dir_recursive_absolute(OUT)
	game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_physics_process(false);await frames()
	game.start_match("dev",771,"iron",true);game.sim.ai_enabled=false
	game.hud.show_entry(false);game.hud.show_menu(false);game.audio.set_mix({"muted":true})
	var sim=Sim.new();sim.setup(RulesLoader.load_rules(),"dev",441,"iron",false,{"vision_enabled":false})
	for id in sim.entities.keys():sim._kill_entity(id,false)
	for row in sim.map.terrain:row.fill(0)
	for row in sim.map.heights:row.fill(0.0)
	sim.mines.clear();sim.bridges.clear();sim.map.bridges.clear();sim.ruins.clear();sim.map.decorations.clear();sim._refresh_ruin_spatial();sim._prepare_terrain_cache();sim.money[0]=20000
	sim._spawn(0,"iron_hq",Vector2(12,12),true);sim._spawn(1,"kestrel_hq",Vector2(43,43),true)
	game.sim=sim;game.world.setup(sim,game.camera);game.selected=[]
	aim(Vector2(25,25),20)
	var anchor:=Vector2(25.5,25.5)
	sim._spawn(0,"iron_rail",anchor,true);sim._rail_network.rebuild(sim)
	for q in [0,2]:
		game.handle_action("build","iron_rail")
		sim.BuildingConstruction.advance(sim,0,"defense",1,1)
		game.handle_action("build","iron_rail")
		for i in range(q):await press_r()
		var target:Vector2=anchor+O.offset(Vector2.RIGHT,q)*3
		var order:Dictionary=sim.order_for_team(0,"defense")
		check(game.placing and O.quarters(order)==q,"actual R rotates live railway preview q"+str(q))
		var preview:Dictionary={"spec":"iron_rail","pos":target,"valid":sim.placement_error(0,target,"defense").is_empty(),"channel":"defense","rotation_quarters":q}
		game.hud.show_placement_reason("","rail",q)
		await save("rail_preview_"+str(q),preview)
		var before:float=sim.money[0]
		await click_world(target)
		for i in range(40):sim.step(.05)
		check(not sim._rail_network.at(0,target).is_empty(),"real mouse click extends selected railway side q"+str(q))
		check(is_equal_approx(before-sim.money[0],50),"actual clicked extension pays two extra cells")
		evidence.append({"rotation":q,"clicked_world":target,"paid_extra":before-sim.money[0],"rail_target_exists":not sim._rail_network.at(0,target).is_empty()})
		await save("rail_built_"+str(q))
	# Render all four actual placed entity transforms through normal PaperWorld
	# and native batching, including LOD switching and active opening leaves.
	for id in sim.entities.keys():
		if sim.entities[id].spec=="iron_rail":sim._kill_entity(id,false)
	var ids:Array[int]=[]
	for q in range(4):
		var pos:Vector2=Vector2(22+float(q%2)*9,21+float(q/2)*10)
		var id:int=sim._spawn(0,"sky_factory",pos,true,q);sim.entities[id].production_door=.65;ids.append(id)
	aim(Vector2(26.5,26),30,48)
	for tier in range(3):
		game.world.lod_override=tier
		await save("factory_four_directions_lod"+str(tier))
		for q in range(4):
			var model:Dictionary=game.world.models[ids[q]]
			check(is_equal_approx(model.root.rotation.y,-deg_to_rad(q*90)),"live world rotation q%d lod%d"%[q,tier])
	print("BUILDING_ORIENTATION_RENDER ",JSON.stringify({"failures":failures,"clicks":evidence,"renderer":RenderingServer.get_current_rendering_method(),"native_world":game.world.native_world_sync_enabled}))
	FileAccess.open(OUT+"/render_and_clicks.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"clicks":evidence},"  "))
	game.quit_pending=true;game.audio.stop_all();game.queue_free();await frames();quit(0 if failures.is_empty() else 1)
