extends SceneTree

var errors:Array[String]=[]

func _initialize() -> void:
	call_deferred("run")

func check(ok:bool,label:String) -> void:
	if not ok:errors.append(label)

func run() -> void:
	var game=load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.start_match("dev",73026,"rivet",true)
	game.sim.ai_enabled=false
	game.audio.muted=true
	game.hud.show_menu(false)
	var sim:WarSimulation=game.sim
	sim.debug_spawn(0,"rivet_power",Vector2(14.5,24.5))
	var engineer:int=sim.debug_spawn(0,"rivet_engineer",Vector2(19.5,31.5))
	var tank:int=sim.debug_spawn(0,"rivet_tank",Vector2(17.5,33.5))
	var tower:int=sim.debug_spawn(1,"kestrel_tower",Vector2(28.5,31.5))
	game.selected=[engineer,tank]
	game.right_command(sim.entities[tower].pos,tower,false)
	check(sim.entities[engineer].commands.size()==1 and sim.entities[engineer].commands[0].kind=="capture" and sim.entities[engineer].commands[0].target==tower,"工程兵右键敌防御塔派发占领")
	check(sim.entities[tank].commands.size()==1 and sim.entities[tank].commands[0].kind=="attack" and sim.entities[tank].commands[0].target==tower,"混编右键保留武装单位攻击")
	for spec in ["kestrel_wall","kestrel_barricade"]:
		var barrier:int=sim.debug_spawn(1,spec,Vector2(32.5,31.5))
		sim.issue([engineer],"stop",Vector2.ZERO)
		game.selected=[engineer]
		game.right_command(sim.entities[barrier].pos,barrier,false)
		check(sim.entities[engineer].commands.is_empty() and game.feedback.back().contains("不能占领"),"围墙 / 拒马禁止工程兵占领 "+spec)
	var enemy_hq:int=-1
	var friendly_hq:int=-1
	for e in sim.entities.values():
		if sim.data_for(e.spec).get("role","")=="hq":
			if int(e.team)==0:friendly_hq=int(e.id)
			else:enemy_hq=int(e.id)
	game.right_command(sim.entities[enemy_hq].pos,enemy_hq,false)
	check(sim.entities[engineer].commands.is_empty() and game.feedback.back().contains("一个总部"),"已有总部时占领另一个总部给明确提示")
	sim.entities[friendly_hq].hp=100.0
	game.right_command(sim.entities[friendly_hq].pos,friendly_hq,false)
	check(sim.entities[engineer].commands.size()==1 and sim.entities[engineer].commands[0].kind=="repair_building" and game.feedback.back().contains("立即修满"),"工程兵右键友方受损建筑派发立即修复")
	game.hud.refresh(sim,[engineer],game.camera,true,"",0)
	var funds_before:float=float(sim.money[0])
	game.handle_action("build","rivet_outpost")
	check(not sim.building_orders[0].is_empty() and sim.building_orders[0].get("builder",-1)==engineer and sim.building_orders[0].get("ready",false),"工程兵分基地卡立即创建带builder的选址订单")
	check(game.placing and is_equal_approx(float(sim.money[0]),funds_before) and game.feedback.back().contains("逐步付款"),"分基地立即选址且无需预付款或等待")
	game.placing=false
	sim.cancel_build(0)
	var rifle:int=sim.debug_spawn(0,"rivet_rifle",Vector2(11.5,39.5))
	var scout:int=sim.debug_spawn(0,"rivet_scout",Vector2(13.5,39.5))
	sim.issue([scout],"hold",Vector2.ZERO)
	game.selected=[rifle]
	game.right_command(sim.entities[scout].pos,scout,false)
	check(sim.entities[rifle].commands.size()==1 and sim.entities[rifle].commands[0].kind=="board" and sim.entities[rifle].commands[0].target==scout,"普通步兵右键侦察车派发上车")
	for tick in range(240):
		sim.step(1.0/30.0)
		if int(sim.entities[rifle].get("transport_id",-1))==scout:break
		await process_frame
	check(int(sim.entities[rifle].get("transport_id",-1))==scout,"近距离上车完成")
	game.selected=[rifle,scout]
	game.hud.refresh(sim,game.selected,game.camera,true,"",0)
	check(game.friendly_units()==[scout] and game.hud.selection==[scout],"已上车步兵不再单独接收命令或出现在HUD选择")
	check(game.hud.unload_button.visible and game.hud.info_label.text.contains("搭载 1/1"),"侦察车显示一名乘员与卸载按钮")
	game.focus=sim.entities[scout].pos
	game.distance=30.0
	game.yaw=0.0
	game.update_camera()
	var center:Vector2=game.project_world_to_screen(game.entity_visual_center(sim.entities[scout]))
	check(game.pick_entity(center)!=rifle,"点选不命中已上车步兵")
	game.box_select(game.battlefield_rect(),false)
	check(rifle not in game.selected,"框选排除已上车步兵")
	game.selected=[scout]
	game.handle_action("unload",null)
	check(int(sim.entities[rifle].get("transport_id",-1))<0 and sim.entities[scout].passengers.is_empty(),"卸载按钮恢复步兵独立实体")
	game.hud.refresh(sim,[scout],game.camera,true,"",0)
	check(not game.hud.unload_button.visible and game.hud.info_label.text.contains("搭载 0/1"),"卸载后侦察车计数及按钮更新")
	print("ENGINEER_TRANSPORT_INPUT ","PASS" if errors.is_empty() else errors)
	for error in errors:push_error(error)
	game.queue_free()
	await process_frame
	quit(0 if errors.is_empty() else 1)
