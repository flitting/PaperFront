extends SceneTree

var errors:Array[String]=[]

func _initialize() -> void:
	call_deferred("run")

func check(ok:bool,label:String) -> void:
	if not ok:errors.append(label)

func press_key(game,keycode:int) -> void:
	var event:=InputEventKey.new()
	event.keycode=keycode
	event.pressed=true
	game._unhandled_input(event)

func click_at(game,screen:Vector2) -> void:
	var event:=InputEventMouseButton.new()
	event.position=screen
	event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=true
	game._unhandled_input(event)

func command_is(sim,id:int,kind:String,target:int) -> bool:
	return sim.entities.has(id) and sim.entities[id].commands.size()==1 and sim.entities[id].commands[0].kind==kind and int(sim.entities[id].commands[0].target)==target

func run() -> void:
	var game=load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.start_match("dev",73026,"rivet",true)
	game.audio.muted=true
	game.hud.show_menu(false)
	var sim:WarSimulation=game.sim
	sim.ai_enabled=false
	# Keep input dispatch independent of whether this compact map seed has room
	# for randomly generated stone compounds beside its bases and forests.
	for item in [["wall",Vector2(28.5,42.5),Vector2(1.5,.34)],["house",Vector2(33.5,42.5),Vector2(1.5,1.35)]]:
		sim.ruins.append({"id":sim.ruins.size(),"kind":item[0],"pos":item[1],"half":item[2],"hp":360.0,"max_hp":360.0,"yaw":0.0,"variant":0})
	sim._refresh_ruin_spatial()
	for old_mode:String in ["handmade","random","mountains","mountains640"]:
		game.hud.select_map("snow")
		game.hud.select_map(old_mode)
		check(game.hud.selected_map()=="forest" and game.hud.map_option.get_item_text(game.hud.map_option.selected).contains("320×320"),"历史地图不再作为新局菜单选项，恢复选择回退翠林溪谷："+old_mode)
	var tank:int=sim.debug_spawn(0,"rivet_tank",Vector2(8.5,42.5))
	var friend:int=sim.debug_spawn(0,"rivet_rifle",Vector2(12.5,42.5))
	game.selected=[tank]
	game.focus=sim.entities[friend].pos
	game.distance=24.0
	game.yaw=0.0
	game.update_camera()
	var friend_screen:Vector2=game.project_world_to_screen(game.entity_visual_center(sim.entities[friend]))
	press_key(game,KEY_H)
	check(game.command_mode=="force_attack","H进入强制攻击光标")
	click_at(game,friend_screen)
	check(command_is(sim,tank,"force_attack",friend) and game.command_mode.is_empty(),"H左键友方目标派发强制攻击")
	press_key(game,KEY_F)
	check(game.command_mode=="force_move","F进入强制移动光标")
	click_at(game,friend_screen)
	check(command_is(sim,tank,"force_move",friend),"F左键步兵携带目标以指定碾压")
	var ground:=Vector2(20.5,42.5)
	game.focus=ground
	game.update_camera()
	press_key(game,KEY_H)
	click_at(game,game.project_world_to_screen(Vector3(ground.x,MapData.height_at(sim.map,ground)+.003,ground.y)))
	check(command_is(sim,tank,"force_attack",-1),"H左键空地派发地点强制攻击")
	for kind in ["wall","house","tree"]:
		var neutral:Dictionary={}
		for ruin in sim.ruins:
			if str(ruin.kind)==kind:neutral=ruin;break
		check(not neutral.is_empty(),"输入场景存在中立目标 "+kind)
		if neutral.is_empty():continue
		var target:int=sim.RUIN_TARGET_BASE-int(neutral.id)
		game.right_command(neutral.pos,target,false)
		check(command_is(sim,tank,"move",-1),"普通右键中立障碍不派发攻击 "+kind)
		game.focus=neutral.pos
		game.update_camera()
		press_key(game,KEY_H)
		var height:float=.45 if kind=="wall" else 1.1
		var visible_point:=Vector3(neutral.pos.x,MapData.height_at(sim.map,neutral.pos)+height,neutral.pos.y)
		if kind=="tree":
			for piece in game.world.landscape.tree_visuals.get(int(neutral.id),[]):
				var mesh:Mesh=(piece.multi as MultiMesh).mesh
				var bounds:AABB=mesh.get_aabb()
				var canopy:Vector3=game.world.landscape.global_transform*piece.transform*(bounds.get_center()+Vector3(0,bounds.size.y*.35,0))
				if canopy.y>visible_point.y:visible_point=canopy
			check(visible_point.y>MapData.height_at(sim.map,neutral.pos)+1.1,"树冠测试使用实际树模型上部可见位置")
		click_at(game,game.project_world_to_screen(visible_point))
		check(command_is(sim,tank,"force_attack",target),"H左键中立障碍派发明确目标 "+kind)
	var engineer:int=sim.debug_spawn(0,"rivet_engineer",Vector2(38.5,41.5))
	sim.debug_spawn(0,"rivet_power",Vector2(14.5,24.5))
	game.selected=[engineer]
	game.hud.refresh(sim,game.selected,game.camera,true,"",0)
	var funds:float=float(sim.money[0])
	await process_frame
	var deployment_press := InputEventMouseButton.new()
	deployment_press.button_index = MOUSE_BUTTON_LEFT
	deployment_press.pressed = true
	deployment_press.position = game.hud.deploy_outpost_button.get_global_rect().get_center()
	root.push_input(deployment_press, true)
	var deployment_release: InputEventMouseButton = deployment_press.duplicate()
	deployment_release.pressed = false
	root.push_input(deployment_release, true)
	await process_frame
	check(game.placing and sim.building_orders[0].get("ready",false) and is_equal_approx(float(sim.money[0]),funds),"工程兵建造卡立即选址且不预扣资金")
	var site:=Vector2.INF
	for z in range(7,43):
		for x in range(7,43):
			var candidate:=Vector2(x+.5,z+.5)
			if sim.placement_error(0,candidate).is_empty():site=candidate;break
		if site.is_finite():break
	check(site.is_finite(),"分基地存在合法部署位置")
	if site.is_finite():
		sim.entities[engineer].pos=site+Vector2(2.2,0)
		game.focus=site
		game.update_camera()
		click_at(game,game.project_world_to_screen(Vector3(site.x,MapData.height_at(sim.map,site)+.003,site.y)))
		check(not game.placing and sim.building_orders[0].is_empty() and command_is(sim,engineer,"deploy_outpost",-1),"左键选址派发前往部署并清除选址订单")
		var scaffold:int=-1
		for tick in range(180):
			sim.step(1.0/30.0)
			for entity in sim.entities.values():
				if entity.has("construction"):scaffold=int(entity.id);break
			if scaffold>=0:break
			await process_frame
		check(scaffold>=0,"工兵抵达后生成未完工脚手架")
		if scaffold>=0:
			game.selected=[scaffold]
			game.hud.refresh(sim,game.selected,game.camera,true,"",0)
			check(game.hud.dismantle_button.visible and not game.hud.maintenance_row.visible and not game.hud.production_panel.visible,"未完工分基地提供拆除且不显示生产目录")
			check(game.hud.info_label.text.contains("施工") and game.hud.info_label.text.contains("已付"),"脚手架显示施工进度与已付资金")
			var replacement:int=sim.debug_spawn(0,"rivet_engineer",site+Vector2(-2.2,0))
			game.selected=[replacement]
			game.right_command(sim.entities[scaffold].pos,scaffold,false)
			check(command_is(sim,replacement,"resume_outpost",scaffold),"另一工程兵右键己方脚手架接手施工")
			game.selected=[scaffold]
			game.hud.refresh(sim,game.selected,game.camera,true,"",0)
			game.handle_action("dismantle_outpost",null)
			check(not sim.entities.has(scaffold),"拆除脚手架按钮移除未完工分基地")
	print("CONSTRUCTION_FORCE_INPUT ","PASS" if errors.is_empty() else errors)
	for error in errors:push_error(error)
	game.queue_free()
	await process_frame
	quit(0 if errors.is_empty() else 1)
