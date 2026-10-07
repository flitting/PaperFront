extends SceneTree
var checks:int=0
var failures:int=0
var game:Node3D
func _init() -> void:
	call_deferred("run")
func check(condition:bool,description:String) -> void:
	checks+=1
	if not condition:failures+=1;push_error("FAIL "+description)
	else:print("PASS ",description)
func run() -> void:
	game=load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game.audio.muted=true
	game.start_match("dev",73026,"rivet",true)
	game.hud.show_menu(false)
	await process_frame
	var path_layer: CanvasLayer = game.overlay.get_parent()
	var scene_layer: CanvasLayer = game.battlefield_display.get_parent()
	check(scene_layer.layer < path_layer.layer and path_layer.layer < game.hud.layer,"路径和选择标记位于战场上方且不覆盖HUD")
	check(game.overlay.clip_contents and Rect2(game.overlay.position,game.overlay.size)==game.battlefield_rect(),"路径绘制限定在战场区域内")
	var p:=Vector2(15.5,31.5)
	for pitch in [20.0,24.0,30.0,36.0,45.0]:
		game.camera_pitch=pitch
		for angle in [0.0,0.7,1.57,3.14,4.71]:
			game.yaw=angle
			game.update_camera()
			var v:=Vector3(p.x,MapData.height_at(game.sim.map,p)+0.003,p.y)
			var screen:Vector2=game.project_world_to_screen(v)
			var hit:Vector2=game.ground_at(screen)
			check(hit.distance_to(p)<0.08,"地面点击转换 pitch="+str(pitch)+" yaw="+str(angle))
	var id:int=game.sim.debug_spawn(0,"rivet_rifle",p)
	game.selected=[id]
	for alpha in [0.0,79.0,80.0,81.0,90.0,135.0,180.0,-79.0,-80.0,-81.0,-90.0,-135.0]:
		game.sim.entities[id].alpha=alpha
		game.world.sync(0.0,game.selected,{})
		var model:Dictionary=game.world.models[id]
		check(not model.volumetric and bool(model.root.get_meta("mirrored"))==(absf(alpha)>80.0),"纸片步兵固定80°镜像边界 alpha="+str(alpha))
		var previous:Transform3D=model.root.transform
		game.yaw+=0.6
		game.camera_pitch=20.0+fposmod(absf(alpha),25.0)
		game.update_camera()
		game.world.sync(0.0,game.selected,{})
		check(model.root.transform.is_equal_approx(previous),"镜头不改变单位世界平面 alpha="+str(alpha))
		check(is_equal_approx(model.hp_root.rotation.y,0.0),"纸片步兵血条与世界卡片平行 alpha="+str(alpha))
	var model:Dictionary=game.world.models[id]
	check(not model.volumetric and model.graphic.mesh.get_aabb().size.z>.04,"步兵保留原纸片和薄切边")
	game.yaw=0.0
	game.update_camera()
	game.world.sync(0.0,[id],{})
	var center:=Vector3(p.x,MapData.height_at(game.sim.map,p)+0.7,p.y)
	check(game.pick_entity(game.project_world_to_screen(center))==id,"侧面显示仍可选择单位")
	var tank_id:int=game.sim.debug_spawn(0,"rivet_tank",Vector2(17.5,31.5))
	game.sim.entities[tank_id].alpha=32.0
	game.sim.entities[tank_id].turret_alpha=-55.0
	game.world.sync(0.0,[tank_id],{})
	var tank:Dictionary=game.world.models[tank_id]
	check(tank.volumetric and tank.volume.dimensions.z>1.0,"坦克使用真实有体积几何")
	check(tank.volume.body!=tank.volume.turret and tank.volume.muzzle!=null,"坦克车体与炮塔分离且有真实炮口")
	check(is_equal_approx(tank.volume.turret.rotation.y,deg_to_rad(87.0)),"炮塔相对车体独立旋转")
	check(not tank.root.get_meta("mirrored"),"体积车辆不使用纸片镜像")
	var turret_heading:Vector3=tank.volume.turret.global_basis.x
	var tank_transform:Transform3D=tank.root.transform
	game.yaw+=1.1
	game.update_camera()
	game.world.sync(0.0,[tank_id],{})
	check(tank.root.transform.is_equal_approx(tank_transform) and tank.volume.turret.global_basis.x.is_equal_approx(turret_heading),"环绕镜头不改变车体或炮塔世界朝向")
	var hq:int=-1
	for entity in game.sim.entities.values():
		if entity.team==0 and entity.kind=="building" and entity.spec.ends_with("_hq"):hq=entity.id;break
	var building:Dictionary=game.world.models[hq]
	check(building.volumetric and building.volume.dimensions.z>2.0,"建筑具有屋顶与侧墙的完整体积")
	check(is_zero_approx(building.root.rotation.y),"建筑固定在世界而不朝向摄像机")
	check(game.key_light.shadow_enabled and game.environment.ssao_enabled and game.key_light.light_energy>1.0,"暖色方向光、阴影及SSAO启用")
	game.selected=[hq]
	game.hud.refresh(game.sim,[hq],game.camera,true,"",0)
	check(not game.hud.entry_widgets.has("rivet_hq") and not game.hud.entry_widgets.has("rivet_outpost") and not game.hud.entry_widgets.has("rivet_barracks"),"基地兵营仅提供步兵目录")
	game.sim.debug_spawn(0,"rivet_power",Vector2(26.5,42.5))
	var engineer_id:int=game.sim.debug_spawn(0,"rivet_engineer",Vector2(15.5,33.5))
	game.hud.refresh(game.sim,[hq,engineer_id],game.camera,true,"",0)
	check(game.hud.production_panel.visible and not game.hud.entry_widgets.has("rivet_outpost") and not game.hud.entry_widgets.has("rivet_barracks") and game.hud.entry_widgets.has("rivet_hq") and not game.hud.deploy_outpost_button.visible and game.hud.selected_engineer()==engineer_id,"基地兵营与工兵混选提供唯一基地兵营建造卡，移除分基地按钮")
	game.hud.refresh(game.sim,[hq],game.camera,true,"",0)
	check(game.sim.data_for("rivet_hq").name=="基地兵营" and game.hud.info_label.text.contains("基地兵营"),"初始基地使用基地兵营名称")
	for i in range(3): await process_frame
	var old_distance:float=game.distance
	var wheel:=InputEventMouseButton.new()
	wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed=true
	wheel.position=game.hud.build_scroll.get_global_rect().get_center()
	game._unhandled_input(wheel)
	check(is_equal_approx(game.distance,old_distance) and is_equal_approx(game.zoom_target_distance,old_distance),"建造栏滚轮不缩放地图或改动后台目标")
	# The compact dock can fit all current buildings. Force an overflowing
	# list so this check still exercises real GUI scrolling on tall windows.
	var scroll_spacer := Control.new()
	scroll_spacer.custom_minimum_size.x = game.hud.build_scroll.size.x + 80.0
	game.hud.list_box.add_child(scroll_spacer)
	await process_frame
	await process_frame
	wheel.position=game.hud.build_scroll.get_global_rect().get_center()
	var scroll_before:int=game.hud.build_scroll.scroll_horizontal
	var mouse:=InputEventMouseMotion.new()
	mouse.position=wheel.position
	root.push_input(mouse,true)
	await process_frame
	root.push_input(wheel,true)
	await process_frame
	await process_frame
	check(game.hud.build_scroll.scroll_horizontal>scroll_before and is_equal_approx(game.distance,old_distance) and is_equal_approx(game.zoom_target_distance,old_distance),"真实GUI滚轮滚动建筑条目且不穿透缩放目标")
	game.hud.list_box.remove_child(scroll_spacer)
	scroll_spacer.queue_free()
	wheel.position=game.battlefield_rect().get_center()
	game._unhandled_input(wheel)
	check(is_equal_approx(game.distance,old_distance) and game.zoom_target_distance>old_distance,"战场滚轮设定平滑目标，不立即跳变")
	game._advance_camera_zoom(.016);game.update_camera()
	check(game.distance>old_distance and game.distance<game.zoom_target_distance,"战场滚轮随后逐帧平滑缩放")
	game.distance=old_distance
	var power_info:Dictionary=game.sim.rules.buildings.rivet_power
	game.sim.building_orders[0]={"spec":"rivet_power","progress":0.37,"ready":false,"remaining":float(power_info.build_time)*0.63,"total":float(power_info.build_time),"cost":float(power_info.cost)}
	game.hud.tab="build"
	game.hud.refresh(game.sim,[engineer_id],game.camera,true,"",0)
	var entry:Dictionary=game.hud.entry_widgets.rivet_power
	check(entry.progress.visible and is_equal_approx(entry.progress.value,37.0),"建造进度显示在对应建筑条目内")
	game.sim.building_orders[0].ready=true
	game.hud.refresh(game.sim,[engineer_id],game.camera,true,"",0)
	check(entry.ready and entry.progress.value==100.0 and entry.price_label.text.contains("放置"),"准备完成的条目加深并显示放置提示")
	check(entry.button.get_theme_stylebox("normal").bg_color.get_luminance()<PaperHUD.CREAM.get_luminance(),"就绪条目的底色确实加深")
	game.sim.building_orders[0]={}
	game.hud.refresh(game.sim,[engineer_id],game.camera,true,"",0)
	check(not entry.ready and not entry.progress.visible,"队列清空后条目恢复颜色并隐藏进度")
	var factory_id:int=game.sim.debug_spawn(0,"rivet_factory",Vector2(14.5,42.5))
	var tank_info:Dictionary=game.sim.rules.units.rivet_tank
	game.sim.entities[factory_id].queue=[{"spec":"rivet_tank","progress":0.5,"ready":false,"remaining":float(tank_info.build_time)*0.5,"total":float(tank_info.build_time),"cost":float(tank_info.cost)}]
	game.hud.tab="vehicle"
	game.hud.refresh(game.sim,[factory_id],game.camera,true,"",0)
	var unit_entry:Dictionary=game.hud.entry_widgets.rivet_tank
	check(unit_entry.progress.visible and is_equal_approx(unit_entry.progress.value,50.0),"选中工厂的单位生产进度也显示在其条目内")
	game.sim.entities[factory_id].queue[0].ready=true
	game.hud.refresh(game.sim,[factory_id],game.camera,true,"",0)
	check(unit_entry.ready and unit_entry.price_label.text.contains("等待出口") and not unit_entry.price_label.text.contains("放置"),"堵门完成单位显示等待出口而不误提示手工放置")
	game.sim.entities[factory_id].queue=[]
	game.hud.tab="build"
	game.hud.refresh(game.sim,[hq],game.camera,true,"",0)
	game.selected.clear()
	var click:=InputEventMouseButton.new()
	click.button_index=MOUSE_BUTTON_LEFT
	click.pressed=true
	var ui_position:Vector2=game.hud.title_label.get_global_rect().get_center()
	click.position=ui_position
	root.push_input(click,true)
	await process_frame
	click=InputEventMouseButton.new()
	click.button_index=MOUSE_BUTTON_LEFT
	click.pressed=false
	click.position=ui_position
	root.push_input(click,true)
	await process_frame
	check(not game.dragging and game.selected.is_empty(),"UI鼠标操作不穿透为地面选择")
	var before:float=game.sim.time
	game.handle_action("new_game",null)
	for i in range(5):game._physics_process(1.0/30.0)
	check(game.hud.menu.visible and game.pve_paused and game.sim.time==before,"新战局配置暂停现有对局")
	game.handle_action("setup_resume",null)
	check(not game.hud.menu.visible and not game.pve_paused,"取消新战局配置恢复原运行状态")
	for i in range(5):game._physics_process(1.0/30.0)
	check(game.sim.time>before,"关闭配置后模拟继续推进")
	game.command_mode="attack_move"
	var stop:=InputEventKey.new()
	stop.keycode=KEY_X
	stop.pressed=true
	game._unhandled_input(stop)
	check(game.command_mode.is_empty(),"X取消攻击移动光标")
	game.selected=[id]
	game.sim.issue([id],"move",p+Vector2(2,0))
	var camera_keys:Array=[KEY_W,KEY_A,KEY_S,KEY_D]
	var camera_directions:Array=[Vector2.UP,Vector2.LEFT,Vector2.DOWN,Vector2.RIGHT]
	for index in range(camera_keys.size()):
		var key:=InputEventKey.new()
		key.keycode=camera_keys[index]
		key.physical_keycode=camera_keys[index]
		key.pressed=true
		Input.parse_input_event(key)
		await process_frame
		game._unhandled_input(key)
		check(game.camera_keyboard_direction()==camera_directions[index],"WASD物理按键设置相机方向 "+str(camera_keys[index]))
		check(game.command_mode.is_empty() and game.sim.entities[id].commands[0].kind=="move","WASD不会切换命令光标或停止部队 "+str(camera_keys[index]))
		var release:InputEventKey=key.duplicate()
		release.pressed=false
		Input.parse_input_event(release)
		await process_frame
	var command_key:=InputEventKey.new()
	command_key.pressed=true
	command_key.keycode=KEY_Z
	game._unhandled_input(command_key)
	check(game.command_mode=="attack_move","Z启用攻击移动")
	command_key.keycode=KEY_C
	game._unhandled_input(command_key)
	check(game.command_mode=="waypoint","C启用连续路径点")
	command_key.keycode=KEY_X
	game._unhandled_input(command_key)
	check(game.command_mode.is_empty() and game.sim.entities[id].commands.is_empty(),"X停止单位并退出命令光标")
	game.hud.help_panel.show()
	for frame in range(3):await process_frame
	var help_scroll:ScrollContainer=game.hud.help_panel.get_node("HelpColumn/HelpScroll")
	var help_body:Label=help_scroll.get_node("HelpBody")
	check(game.hud.help_panel.get_global_rect().encloses(help_scroll.get_global_rect()) and help_body.size.x<=help_scroll.size.x,"操作手册正文自动换行且滚动区位于纸板框内")
	check(help_scroll.get_v_scroll_bar().max_value>help_scroll.get_v_scroll_bar().page and help_scroll.get_h_scroll_bar().max_value<=help_scroll.get_h_scroll_bar().page,"新增规则与按键说明通过纵向滚动完整阅读")
	game.hud.help_panel.hide()
	game.dragging=true
	game.middle_drag=true
	game.overlay.active=true
	game._process(0.0)
	check(not game.dragging and not game.middle_drag and not game.overlay.active,"UI消费松键后不残留框选或平移状态")
	var current_rules:Dictionary=RulesLoader.load_rules()
	var old_snapshot:Dictionary=current_rules.duplicate(true)
	old_snapshot.economy.initial_money=float(current_rules.economy.initial_money)+321.0
	old_snapshot.units.rivet_rifle.cost=float(current_rules.units.rivet_rifle.cost)+23.0
	# handle_action("load") assigns the saved snapshot to these two rule owners.
	# Reproduce that state without overwriting the player's actual save file.
	game.rules=old_snapshot
	game.sim.rules=old_snapshot.duplicate(true)
	var new_match_started:bool=game.start_match("dev",73026,"rivet",true)
	check(new_match_started and game.rules==current_rules and game.sim.rules==current_rules and is_equal_approx(float(game.sim.money[0]),float(current_rules.economy.initial_money)),"读取旧规则快照后新局重读当前JSON配置与初始资金")
	game.sim.result="win"
	game.hud.show_menu(true)
	game.hud.end_panel.hide()
	game.hud.refresh(game.sim,[hq],game.camera,true,"",0)
	check(not game.hud.end_panel.visible and game.hud.menu.visible,"结算返回菜单不会被下一次UI刷新覆盖")
	print("UI / rendering checks: ",checks-failures," passed, ",failures," failed")
	game.queue_free()
	await process_frame
	quit(1 if failures>0 else 0)
