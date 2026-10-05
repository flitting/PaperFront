extends SceneTree

var checks: int = 0
var failures: int = 0
var game: Node3D
var preferences_backup: Variant

func _init() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS ", description)
	else:
		failures += 1
		push_error("FAIL " + description)

func mouse_button(position: Vector2, button: MouseButton, pressed: bool = true) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = button
	event.pressed = pressed
	return event

func run() -> void:
	preferences_backup = FileAccess.get_file_as_bytes("user://settings.cfg") if FileAccess.file_exists("user://settings.cfg") else null
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	check(not game.debug_available and not game.hud.debug_menu_enabled,"无设置文件时用户调试选项默认关闭")
	game.audio.muted = true
	game.start_match("dev", 73026, "rivet", true)
	game.hud.show_menu(false)
	# Freeze simulation and camera controls while probing positions and GUI routing.
	game.set_process(false)
	game.set_physics_process(false)
	for window_size in [Vector2i(1920,1080), Vector2i(1440,900), Vector2i(2560,1080), Vector2i(1100,700)]:
		root.size = window_size
		await process_frame
		await process_frame
		await check_layout_and_selection(str(window_size))
	await check_edge_directions()
	await check_render_scale()
	await check_debug_panel()
	print("Right dock / viewport checks: ", checks-failures, " passed, ", failures, " failed")
	game.queue_free()
	await process_frame
	if preferences_backup == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	else:
		var preferences := FileAccess.open("user://settings.cfg",FileAccess.WRITE)
		if preferences != null:
			preferences.store_buffer(preferences_backup)
			preferences.close()
	quit(1 if failures > 0 else 0)

func check_layout_and_selection(label: String) -> void:
	var logical: Rect2 = root.get_visible_rect()
	var battlefield: Rect2 = game.battlefield_rect()
	var dock: Rect2 = game.hud.dock.get_global_rect()
	var pixels: Vector2i = root.size
	var transform: Transform2D = root.get_final_transform()
	print("LAYOUT ",label," logical=",logical.size," window=",pixels," transform=",transform," 3D=",game.battlefield_viewport.size)
	# The current reference HUD floats over the full battlefield. The retained
	# dock property points at the bottom production panel, not a fixed sidebar.
	check(logical.encloses(dock) and dock.position.y>logical.size.y*.5, label+" 生产栏位于窗口内下半区")
	check(battlefield.is_equal_approx(logical), label+" 全屏战场覆盖根画布，无额外侧栏留白")
	check((transform * logical.position).is_zero_approx() and (transform * logical.end).distance_to(Vector2(pixels)) < 1.0, label+" 根画布覆盖实际窗口且无上下黑边")
	check(game.battlefield_viewport.size == pixels, label+" 3D使用整个窗口实际像素")
	check(game.battlefield_display.get_global_rect().is_equal_approx(battlefield) and game.overlay.get_global_rect().is_equal_approx(battlefield), label+" 渲染纹理与选择覆盖层精确铺满战场")
	check(game.camera.get_viewport() == game.battlefield_viewport and game.battlefield_viewport.world_3d == root.world_3d and root.disable_3d, label+" 子视口独立渲染并共享场景与灯光")
	var mini_rect: Rect2 = game.hud.mini.get_global_rect()
	check(logical.encloses(mini_rect) and mini_rect.position.x < logical.size.x*.25 and mini_rect.position.y > logical.size.y*.5, label+" 小地图位于窗口左下且完整可见")
	for node in game.hud.dock.find_children("","Label",true,false):
		var text: Label = node as Label
		if not text.is_visible_in_tree() or text.text.is_empty():continue
		var font: Font = text.get_theme_font("font")
		var font_size: int = text.get_theme_font_size("font_size")
		check(text.size.y+0.01>=font.get_height(font_size), label+" 右栏文字保留完整字高："+text.text.get_slice("\n",0))
	for fraction in [Vector2.ZERO,Vector2(0.25,0.4),Vector2(0.75,0.7),Vector2.ONE]:
		var screen: Vector2 = battlefield.position+battlefield.size*fraction
		var round_trip: Vector2 = game.battlefield_to_screen(game.screen_to_battlefield(screen))
		check(round_trip.distance_to(screen) < 0.01, label+" 屏幕与相机坐标往返 "+str(fraction))
	game.focus = Vector2(24,32)
	game.distance = 25.0
	game.camera_pitch = 36.0
	game.yaw = 0.0
	game.update_camera()
	var ids: Array[int] = []
	for x_fraction in [0.25,0.75]:
		# Use the southern flat test range. An arbitrary screen ray may hit a
		# vertical cliff face, whose hit cannot be reconstructed at terrain-top Y.
		var ground_point:=Vector2(12.5 if x_fraction<.5 else 35.5,32.5)
		var sample: Vector2 = game.project_world_to_screen(Vector3(ground_point.x,MapData.height_at(game.sim.map,ground_point)+.003,ground_point.y))
		var position: Vector2 = game.ground_at(sample)
		var height: float = MapData.height_at(game.sim.map,position)
		var ground_screen: Vector2 = game.project_world_to_screen(Vector3(position.x,height+0.003,position.y))
		check(ground_screen.distance_to(sample)<0.15, label+" 左右半区地面射线与投影一致 "+str(x_fraction))
		var id: int = game.sim.debug_spawn(0,"rivet_rifle",position)
		ids.append(id)
		# Spawning can move a unit to the nearest free, standable cell.
		position = game.sim.entities[id].pos
		height = MapData.height_at(game.sim.map,position)
		var unit_screen: Vector2 = game.project_world_to_screen(Vector3(position.x,height+0.7,position.y))
		check(game.pick_entity(unit_screen)==id, label+" 左右半区单位点击准确 "+str(x_fraction))
		game.click_select(unit_screen,false)
		check(game.selected == [id], label+" 点击选择通过根坐标选中单位 "+str(x_fraction))
		var box_screen: Vector2 = game.project_world_to_screen(Vector3(position.x,height+0.6,position.y))
		game.box_select(Rect2(box_screen-Vector2(12,12),Vector2(24,24)),false)
		check(game.selected == [id], label+" 小范围框选与点击命中一致 "+str(x_fraction))
	game.box_select(Rect2(Vector2.ZERO,logical.size),false)
	check(ids[0] in game.selected and ids[1] in game.selected, label+" 跨越右栏的框选仍包含左右可见单位")
	var selected_before: Array = game.selected.duplicate()
	var dock_center: Vector2 = game.hud.ui_panels[0].get_global_rect().get_center()
	game._unhandled_input(mouse_button(dock_center,MOUSE_BUTTON_LEFT))
	game._unhandled_input(mouse_button(dock_center,MOUSE_BUTTON_LEFT,false))
	check(game.hud.blocks_world_scroll(dock_center) and game.selected==selected_before and not game.dragging, label+" 可见面板点击不穿透或清空战场选择")
	game._unhandled_input(mouse_button(dock_center,MOUSE_BUTTON_MIDDLE))
	check(not game.middle_drag, label+" 可见面板中键不触发战场平移")
	var old_distance: float = game.distance
	game._unhandled_input(mouse_button(dock_center,MOUSE_BUTTON_WHEEL_DOWN))
	check(is_equal_approx(game.distance,old_distance), label+" 右栏滚轮不穿透缩放")
	game._unhandled_input(mouse_button(battlefield.get_center(),MOUSE_BUTTON_WHEEL_DOWN))
	check(game.distance>old_distance, label+" 战场滚轮正常缩放")
	game.distance = old_distance
	# A real GUI event must pass through the minimap's local coordinates.
	game.hud.refresh(game.sim,[],game.camera,true,"",0)
	await process_frame
	var fraction := Vector2(0.36,0.61)
	var map_local: Vector2 = game.hud.mini.map_rect.position+game.hud.mini.map_rect.size*fraction
	var click_screen: Vector2 = game.hud.mini.get_global_transform()*map_local
	root.push_input(mouse_button(click_screen,MOUSE_BUTTON_LEFT),true)
	root.push_input(mouse_button(click_screen,MOUSE_BUTTON_LEFT,false),true)
	await process_frame
	check(game.focus.distance_to(fraction*float(game.sim.map.size))<0.05 and not game.dragging, label+" 小地图GUI点击准确对焦且不触发地面框选")
	for id in ids:
		game.sim.entities.erase(id)

func check_edge_directions() -> void:
	root.size = Vector2i(1920,1080)
	await process_frame
	await process_frame
	var window_size := Vector2(root.size)
	var dock_edge: Vector2 = root.get_final_transform()*game.hud.dock.get_global_rect().position
	for item in [
		[Vector2(1,540),Vector2.LEFT,"左边"],
		[Vector2(960,1),Vector2.UP,"上边"],
		[Vector2(1919,540),Vector2.RIGHT,"右栏最右屏幕边缘"],
		[Vector2(960,1079),Vector2.DOWN,"下边"],
		[Vector2(1,1),Vector2(-1,-1).normalized(),"左上角"],
		[Vector2(1919,1079),Vector2(1,1).normalized(),"右下角"],
		[Vector2(1800,540),Vector2.ZERO,"右栏内部"],
		[Vector2(dock_edge.x,540),Vector2.ZERO,"战场与右栏接缝"],
		[Vector2(960,540),Vector2.ZERO,"中央"],
		[Vector2(-1,540),Vector2.ZERO,"窗口外"],
		[Vector2(1920,540),Vector2.ZERO,"窗口右边界外"]
	]:
		var direction: Vector2 = game.edge_pan_direction(item[0],window_size)
		check(direction.is_equal_approx(item[1]),"物理鼠标边缘方向："+item[2])
	check(game.edge_pan_direction(Vector2(23,540),window_size)==Vector2.LEFT and game.edge_pan_direction(Vector2(24,540),window_size)==Vector2.ZERO,"边缘阈值为24实际像素")

func check_render_scale() -> void:
	game.set_render_scale(1.0)
	game.focus = Vector2(24,24)
	game.distance = 25.0
	game.camera_pitch = 36.0
	game.yaw = 0.0
	game.update_camera()
	var id: int = game.sim.debug_spawn(0,"rivet_rifle",Vector2(19,28))
	var position: Vector2 = game.sim.entities[id].pos
	var center := Vector3(position.x,MapData.height_at(game.sim.map,position)+0.7,position.y)
	var native_screen: Vector2 = game.project_world_to_screen(center)
	var viewport_size: Vector2i = game.battlefield_viewport.size
	var texture_size: Vector2 = game.battlefield_viewport.get_texture().get_size()
	var battlefield_display: Rect2 = game.battlefield_display.get_global_rect()
	var dock: Rect2 = game.hud.dock.get_global_rect()
	var mini: Rect2 = game.hud.mini.get_global_rect()
	check(game.pick_entity(native_screen)==id,"原生渲染比例下单位点击准确")
	game.set_render_scale(0.75)
	game.update_camera()
	await process_frame
	check(is_equal_approx(game.battlefield_viewport.scaling_3d_scale,0.75),"75%缩放只设置3D内部渲染比例")
	check(game.battlefield_viewport.size==viewport_size and game.battlefield_viewport.get_texture().get_size()==texture_size,"75%缩放保持战场输出视口与纹理尺寸")
	check(game.battlefield_display.get_global_rect().is_equal_approx(battlefield_display) and game.hud.dock.get_global_rect().is_equal_approx(dock) and game.hud.mini.get_global_rect().is_equal_approx(mini),"75%缩放保持战场区域与UI、小地图尺寸")
	var reduced_screen: Vector2 = game.project_world_to_screen(center)
	check(reduced_screen.distance_to(native_screen)<0.01 and game.pick_entity(reduced_screen)==id,"75%缩放保持单位投影和点击位置准确")
	game.set_render_scale(1.0)
	check(is_equal_approx(game.battlefield_viewport.scaling_3d_scale,1.0) and game.battlefield_viewport.size==viewport_size,"恢复100%渲染保持输出布局")
	game.sim.entities.erase(id)

func check_debug_panel() -> void:
	# Direct historical generators remain valid fixtures even though their
	# modes are no longer offered for a new menu-launched match.
	game.start_match("handmade",73026,"rivet",true)
	game.hud.show_menu(false)
	game.set_debug_enabled(false)
	await process_frame
	var f2 := InputEventKey.new()
	f2.keycode = KEY_F2
	f2.pressed = true
	game._unhandled_input(f2)
	game.handle_action("debug",null)
	game.handle_action("debug_panel",null)
	game.hud.refresh(game.sim,[],game.camera,false,"",0,-1,false)
	check(not game.debug_panel.visible and not game.hud.dev_button.visible,"关闭用户调试选项隐藏入口且F2/按钮动作无法打开")
	game.set_debug_visible(true)
	check(not game.debug_panel.visible,"关闭用户调试选项也禁止直接显示调试面板")
	check(game.performance_overlay.layer==7 and game.performance_overlay.is_ancestor_of(game.hud.fps_label) and game.hud.fps_label.is_visible_in_tree(),"调试关闭时独立CanvasLayer7仍显示唯一FPS")
	check(not game.debug_panel.is_ancestor_of(game.hud.fps_label) and game.find_children("FPS","Label",true,false).size()==1,"FPS不属于调试面板且没有重复标签")
	game.set_debug_enabled(true)
	game.hud.refresh(game.sim,[],game.camera,false,"",0,-1,true)
	check(not game.dev_mode and game.hud.dev_button.visible,"主动启用后普通对局提供调试入口")
	game._unhandled_input(f2)
	check(game.debug_panel.visible and game.hud.fps_label.is_visible_in_tree(),"F2在普通对局打开指标面板且FPS保持可见")
	check(not game.debug_tools.visible and game.debug_metrics.text.contains("1920×1080") and game.battlefield_viewport.size==Vector2i(1920,1080),"普通对局显示真实窗口与全屏3D尺寸且隐藏规则工具")
	var before_tools := {"money":game.sim.money.duplicate(),"entities":game.sim.entities.size(),"mode":game.sim.map.mode,"seed":game.sim.map.seed,"collisions":game.overlay.collisions,"angle":game.angle_test_id,"selected":game.selected.duplicate()}
	for tool: Button in game.debug_tools.find_children("","Button",true,false):
		tool.pressed.emit()
	var after_tools := {"money":game.sim.money.duplicate(),"entities":game.sim.entities.size(),"mode":game.sim.map.mode,"seed":game.sim.map.seed,"collisions":game.overlay.collisions,"angle":game.angle_test_id,"selected":game.selected.duplicate()}
	check(before_tools==after_tools and not game.dev_mode,"普通对局直接触发隐藏规则按钮也不能加钱、生成单位或重置地图")
	check(game.debug_panel.find_children("","CheckButton",true,false).is_empty() and game.debug_panel.find_children("","OptionButton",true,false).is_empty(),"调试面板不再包含图形设置控件")
	game._unhandled_input(f2)
	check(not game.debug_panel.visible and game.hud.fps_label.is_visible_in_tree(),"第二次F2关闭指标面板，常驻FPS仍可见")
	game.handle_action("settings_open",null)
	check(game.hud.settings is PaperSettings and game.hud.settings.visible,"图形设置统一放在真实PaperSettings")
	for control in [game.hud.settings.ambient_occlusion,game.hud.settings.dof,game.hud.settings.shadows]:
		var toggle: CheckButton = control as CheckButton
		var original: bool = toggle.button_pressed
		toggle.button_pressed = false
		if toggle==game.hud.settings.ambient_occlusion:
			check(not game.environment.ssao_enabled,"AO开关直接关闭场景遮蔽")
		elif toggle==game.hud.settings.dof:
			game.update_camera()
			check(not game.lens.dof_blur_near_enabled and not game.lens.dof_blur_far_enabled,"景深开关关闭前后虚化且镜头更新保持关闭")
		elif toggle==game.hud.settings.shadows:
			check(not game.key_light.shadow_enabled,"阴影开关直接关闭主光阴影")
		toggle.button_pressed = original
	game.hud.settings.close()
	game.start_match("dev",73026,"rivet",true)
	game.set_debug_visible(true)
	check(game.debug_tools.visible,"规则试验场打开调试面板时才显示规则工具")
	game.set_debug_enabled(false)
	check(not game.debug_panel.visible and not game.debug_tools.visible and game.hud.fps_label.is_visible_in_tree(),"关闭调试同时撤下规则工具并保持FPS可见")
