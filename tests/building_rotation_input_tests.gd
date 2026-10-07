extends SceneTree
var checks:=0
var failures:Array[String]=[]
var game
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func frames(count:int=3)->void:
	for _i in range(count):await process_frame
func press_r()->void:
	var e:=InputEventKey.new();e.keycode=KEY_R;e.physical_keycode=KEY_R;e.pressed=true
	root.push_input(e,true)
	e=e.duplicate();e.pressed=false;root.push_input(e,true)
	await frames()
func run()->void:
	root.size=Vector2i(1440,900);root.gui_embed_subwindows=true
	game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_physics_process(false);await frames()
	check(game.start_match("dev",9007,"kestrel",true),"actual developer match starts")
	game.sim.ai_enabled=false
	game.audio.set_mix({"muted":true});game.hud.show_entry(false);game.hud.show_menu(false)
	game.sim.money[0]=10000
	var before_money:float=game.sim.money[0]
	game.handle_action("build","kestrel_barracks")
	var order:Dictionary=game.sim.order_for_team(0,"normal")
	check(not order.is_empty() and game.sim.money[0]==before_money-float(game.sim.data_for("kestrel_barracks").cost),"real building card action pays normal price")
	game.sim.BuildingConstruction.advance(game.sim,0,"normal",100,1)
	game.handle_action("build","kestrel_barracks")
	check(game.placing and game.placement_channel=="normal","ready card action enters actual building preview mode")
	var pitch:float=game.effective_camera_pitch()
	for turn in range(1,5):
		await press_r()
		check(int(order.get("rotation_quarters",-1))==turn%4,"actual R input rotates preview quarter "+str(turn))
		check(game.effective_camera_pitch()==pitch,"placing R does not alter camera pitch "+str(turn))
	check(game.sim.money[0]==before_money-float(game.sim.data_for("kestrel_barracks").cost),"four rotations never pay twice")
	game.hud.show_placement_reason("","barracks",3)
	check(game.hud.placement_label.text.contains("R") and game.hud.placement_label.text.contains("270"),"placement HUD describes current right-angle orientation")
	check(game.hud.spec_tooltip(game.sim.data_for("kestrel_factory")).contains("R每次旋转90"),"all building tooltips expose rotate control")
	game.placing=false;game.camera_pitch=30.0;await press_r()
	check(game.camera_pitch==32,"R outside preview retains pitch shortcut")
	game.quit_pending=true;game.audio.stop_all()
	if game.sim._path_worker!=null:game.sim._path_worker.close()
	await create_timer(.2).timeout;game.queue_free();await frames();await create_timer(.15).timeout
	print("BUILDING_ROTATION_INPUT ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
