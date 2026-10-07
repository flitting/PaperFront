extends SceneTree
const Garrison = preload("res://scripts/garrison_operations.gd")
var game
var checks: int = 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures.append(label)
func frames(n: int=2) -> void:
	for i in range(n): await process_frame
func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode=code;event.physical_keycode=code;event.pressed=true
	root.push_input(event,true)
	event=event.duplicate();event.pressed=false;root.push_input(event,true)
	await frames()
func mouse(button: MouseButton,point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index=button;event.position=point;event.pressed=true
	root.push_input(event,true)
	event=event.duplicate();event.pressed=false;root.push_input(event,true)
	await frames()
func tick(seconds: float) -> void:
	for i in range(ceili(seconds*30)): game.sim.step(1.0/30.0)
func wait_delivery(miner: int,amount: float) -> bool:
	var found: bool = false
	for i in range(1500):
		game.sim.events.clear()
		game.sim.step(1.0/30.0)
		for event: Dictionary in game.sim.events:
			if event.kind=="delivery" and int(event.id)==miner:
				check(bool(event.get("inside",false)),"manual return delivers inside refinery")
				check(is_equal_approx(float(event.amount),amount),"manual return delivers exact partial cargo")
				found=true
		if found: return true
	return false
func wait_mining(miner: int) -> bool:
	for i in range(1500):
		game.sim.step(1.0/30.0)
		var e: Dictionary = game.sim.entities[miner]
		if float(e.cargo)>0 and not bool(e.get("manual_unload",false)) and e.get("refinery_docking",{}).is_empty(): return true
	return false
func focus_at(pos: Vector2) -> void:
	game.focus=pos;game.distance=30;game.yaw=0.0;game.update_camera()
	game.world.sync(0.0,game.selected,{})
	game.hud.refresh(game.sim,game.selected,game.camera,false,"",0.0)
	await frames()
func run() -> void:
	root.size=Vector2i(1440,900);root.gui_embed_subwindows=true
	game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_physics_process(false);await frames()
	check(game.start_match("dev",7,"kestrel",true),"actual main scene starts")
	game.audio.set_mix({"muted":true});game.hud.show_menu(false);game.hud.show_entry(false)
	var sim: WarSimulation = game.sim
	sim.ai_enabled=false;sim.vision_enabled=false;sim.synchronous_path_tests=true;sim.money[0]=10000.0
	# A controlled flat arena isolates the real command/UI from terrain variance.
	for y: int in sim.map.size:
		for x: int in sim.map.size:
			sim.map.terrain[y][x]=0;sim.map.heights[y][x]=0.0
	for id: int in sim.entities.keys():
		if sim.entities[id].kind=="unit": sim._kill_entity(id,false)
	sim.mines.clear();sim.ruins.clear();sim.bridges.clear()
	sim.mines.append({"pos":Vector2(34,30),"amount":10000.0,"capacity":10000.0,"miner":-1})
	sim._refresh_mine_spatial();sim._refresh_ruin_spatial();sim._prepare_terrain_cache()
	sim._nav_initialized=false;sim._nav_dirty=true
	var refinery: int = sim._spawn(0,"kestrel_refinery",Vector2(24,22),true)
	sim.entities[refinery].gift_pending=false
	sim._spawn(0,"kestrel_power",Vector2(15,22),true)
	var miner: int = sim._spawn(0,"kestrel_harvester",Vector2(24,30),true)
	var m: Dictionary = sim.entities[miner]
	m.cargo=75.0;m.harvest_mine=0;m.preferred_mine=0;m.harvest_override=true
	var ruin: Dictionary = {"id":0,"kind":"house","pos":Vector2(40,20),"half":Vector2(1.5,1.35),"yaw":0.0,"hp":900.0,"max_hp":900.0,"variant":0}
	sim.ruins.append(ruin);sim._refresh_ruin_spatial();sim._rebuild_nav();sim._rebuild_spatial()
	game.remove_child(game.world);game.world.queue_free();game._create_match_world();game.world.setup(sim,game.camera)
	game.selected=[miner]
	await focus_at(m.pos)
	var before: float = sim.money[0]
	await key(KEY_B)
	check(not m.commands.is_empty() and m.commands[0].kind=="return_miner","real B key sends selected miner home")
	check(float(m.cargo)<float(sim.rules.economy.harvester_capacity),"B operates before full load")
	check(wait_delivery(miner,75),"B return reaches refinery and unloads")
	check(is_equal_approx(float(sim.money[0])-before,75),"B delivery actually credits funds")
	check(wait_mining(miner),"B delivery resumes automatic mining")
	# Interrupt the renewed collection with the actual refinery click route.
	var cargo: float = m.cargo
	game.selected=[miner]
	await focus_at(sim.entities[refinery].pos)
	var refinery_screen: Vector2 = game.project_world_to_screen(game.entity_visual_center(sim.entities[refinery]))
	check(game.pick_entity(refinery_screen)==refinery,"actual picking identifies refinery")
	before=sim.money[0]
	await mouse(MOUSE_BUTTON_RIGHT,refinery_screen)
	check(not m.commands.is_empty() and m.commands[0].kind=="return_miner" and int(m.commands[0].target)==refinery,"real right-click targets selected refinery")
	check(wait_delivery(miner,cargo),"right-click return actually unloads")
	check(is_equal_approx(float(sim.money[0])-before,cargo),"right-click delivery credits exact cargo")
	check(wait_mining(miner),"right-click delivery resumes automatic mining")
	sim.issue([miner],"hold",m.pos)
	var soldier: int = sim._spawn(0,"kestrel_rifle",Vector2(36.5,20),true)
	var engineer: int = sim._spawn(0,"kestrel_engineer",Vector2(36.5,23),true)
	game.selected=[soldier]
	await focus_at(ruin.pos)
	var house_screen: Vector2 = game.project_world_to_screen(Vector3(ruin.pos.x,1.1,ruin.pos.y))
	var target: int = Garrison.BASE-int(ruin.id)
	check(game.pick_entity(house_screen)==target,"actual picking identifies neutral house")
	await mouse(MOUSE_BUTTON_RIGHT,house_screen)
	check(not sim.entities[soldier].commands.is_empty() and sim.entities[soldier].commands[0].kind=="garrison","real house right-click orders garrison")
	for i in range(600):
		sim.step(1.0/30.0)
		if Garrison.loaded(sim.entities[soldier]):break
	check(Garrison.loaded(sim.entities[soldier]),"UI order physically enters house")
	game.world.sync(0,game.selected,{})
	await mouse(MOUSE_BUTTON_LEFT,house_screen)
	check(game.inspected_ruin==target and game.selected.is_empty(),"house selection inspects negative neutral ID without unit selection")
	await key(KEY_U)
	check(not Garrison.loaded(sim.entities[soldier]) and ruin.garrison.is_empty(),"real U key evacuates inspected house")
	game.selected=[engineer];game.right_command(ruin.pos,target,false)
	check(sim.entities[engineer].commands.is_empty() and game.feedback.back().contains("工兵不能"),"engineer house command is rejected with feedback")
	game.selected=[soldier];game.right_command(ruin.pos,target,false)
	for i in range(600):
		sim.step(1.0/30.0)
		if Garrison.loaded(sim.entities[soldier]):break
	game.selected=[];game.right_command(ruin.pos,target,false)
	check(not Garrison.loaded(sim.entities[soldier]),"empty-selection right-click evacuates own garrison")
	var enemy: int = sim._spawn(1,"kestrel_rifle",ruin.pos+Vector2(4,0),true)
	sim.issue([enemy],"garrison",ruin.pos,target)
	for i in range(300):
		sim.step(1.0/30.0)
		if not sim.entities.has(enemy) or Garrison.loaded(sim.entities[enemy]):break
	check(Garrison.loaded(sim.entities.get(enemy,{})) and int(ruin.garrison_team)==1,"enemy can occupy evacuated house")
	game.selected=[soldier];game.right_command(ruin.pos,target,false)
	check(not sim.entities[soldier].commands.is_empty() and sim.entities[soldier].commands[0].kind=="attack" and int(sim.entities[soldier].commands[0].target)==target,"right-click enemy-occupied house orders attack on house")
	game._update_battle_information();await frames()
	check(game.hud.base_marker_layer.get_child_count()==0,"world base marker layer contains no text or identifier children")
	game.quit_pending=true;game.audio.stop_all()
	if sim._path_worker!=null:sim._path_worker.close()
	game.queue_free();await frames();await create_timer(.15).timeout
	print("V3_COMMANDS_INPUT ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure: String in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
