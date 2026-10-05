extends SceneTree

## Run with the real display server. Mouse warps use logical viewport positions;
## assertions use actual client pixels and the camera's resulting world focus.
var game: Node3D
var checks: int = 0
var failures: Array[String] = []
var movements: Array[Dictionary] = []
const OUTPUT_DIR := "res://artifacts/visual_iteration/g0/"

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS ",description)
	else:
		failures.append(description)
		push_error("NATIVE_VIEWPORT_PROBE_FAIL "+description)

func settle(frames: int = 4) -> void:
	for frame in range(frames):
		await process_frame

func run() -> void:
	if DisplayServer.get_name()=="headless":
		check(false,"真实窗口探查需要原生显示服务器")
		finish()
		return
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1440,900)
	root.position = Vector2i(32,32)
	root.unresizable = true
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.audio.muted = true
	game.start_match("dev",73026,"rivet",true)
	game.set_render_scale(1.0)
	game.spawn_roster()
	game.hud.show_menu(false)
	game.set_process(false)
	game.set_physics_process(false)
	await settle(6)
	root.grab_focus()
	await create_timer(0.15).timeout
	await settle()
	check(root.has_focus(),"原生1440×900窗口已获取真实焦点")
	if not root.has_focus():
		finish()
		return
	var logical: Rect2 = root.get_visible_rect()
	var transform: Transform2D = root.get_final_transform()
	check(transform.origin.is_zero_approx() and (transform*logical.end).distance_to(Vector2(root.size))<1.0,"非16:9原生画布覆盖窗口且无上下留白")
	check(game.battlefield_viewport.size==Vector2i(1217,900),"1440×900原生战场仅渲染1217×900实际像素")
	var default_focus: Vector2 = game.focus
	var default_distance: float = game.distance
	for item in [
		[Vector2(1,450),Vector2.LEFT,"左边"],
		[Vector2(720,1),Vector2.UP,"上边"],
		[Vector2(720,899),Vector2.DOWN,"下边"],
		[Vector2(1439,450),Vector2.RIGHT,"右栏最右屏幕边缘"],
		[Vector2(1439,1),Vector2(1,-1).normalized(),"右上角"]
	]:
		await warp_pointer(item[0],item[2])
		game.focus = Vector2(24,24)
		game.yaw = 0.0
		var before: Vector2 = game.focus
		game.camera_controls(0.1)
		var movement: Vector2 = game.focus-before
		movements.append({"label":item[2],"focus_delta":[movement.x,movement.y],"mouse_logical":[root.get_mouse_position().x,root.get_mouse_position().y],"window_focused":root.has_focus()})
		check(movement.length()>0.01 and movement.normalized().is_equal_approx(item[1]),"原生鼠标贴"+item[2]+"实际推动镜头")
	await warp_pointer(Vector2(1320,450),"右栏内部")
	var before: Vector2 = game.focus
	game.camera_controls(0.1)
	check(game.focus.is_equal_approx(before),"鼠标停在右栏内部不推动镜头")
	await warp_pointer(Vector2(1439,450),"菜单边缘")
	game.hud.show_menu(true)
	before = game.focus
	game.camera_controls(0.1)
	check(game.focus.is_equal_approx(before),"菜单打开时贴边不移动镜头")
	game.hud.show_menu(false)
	game.dragging = true
	game.camera_controls(0.1)
	check(game.focus.is_equal_approx(before),"框选拖拽时贴边不移动镜头")
	game.dragging = false
	game.middle_drag = true
	game.camera_controls(0.1)
	check(game.focus.is_equal_approx(before),"中键拖拽时贴边不重复移动镜头")
	game.middle_drag = false
	game.focus = default_focus
	game.distance = default_distance
	game.yaw = 0.0
	game.update_camera()
	game.world.elapsed = 0.0
	game.world.sync(0.0,game.selected,{})
	game.hud.refresh(game.sim,game.selected,game.camera,true,"原生窗口探查 · 固定帧",0.0,-1,game.debug_available)
	await warp_pointer(Vector2(720,450),"截图中央")
	check(not game.debug_panel.visible and not game.hud.fps_label.is_visible_in_tree(),"正常右栏不显示常驻性能读数")
	await capture("v12_native_1440x900_normal")
	push_f2()
	await settle()
	check(game.debug_panel.visible and game.hud.fps_label.is_visible_in_tree(),"实际GUI F2输入打开调试面板")
	await capture("v12_native_1440x900_debug")
	push_f2()
	await settle()
	check(not game.debug_panel.visible,"实际GUI第二次F2输入关闭调试面板")
	finish()

func warp_pointer(pixel: Vector2, label: String) -> void:
	var transform: Transform2D = root.get_final_transform()
	root.warp_mouse(transform.affine_inverse()*pixel)
	await create_timer(0.04).timeout
	await settle()
	var actual: Vector2 = transform*root.get_mouse_position()
	check(root.has_focus() and actual.distance_to(pixel)<2.0,"原生鼠标正确抵达"+label+"实际像素")

func push_f2() -> void:
	for pressed in [true,false]:
		var key := InputEventKey.new()
		key.keycode = KEY_F2
		key.pressed = pressed
		root.push_input(key,true)

func capture(label: String) -> void:
	await settle(8)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var screenshot: Image = root.get_texture().get_image()
	var error: Error = screenshot.save_png(OUTPUT_DIR+label+".png")
	check(error==OK and screenshot.get_size()==Vector2i(1440,900),"原生截图 "+label+" 为实际1440×900")
	print("NATIVE_VIEWPORT_CAPTURE ",ProjectSettings.globalize_path(OUTPUT_DIR+label+".png"))

func finish() -> void:
	var result := {"checks":checks,"passed":checks-failures.size(),"failures":failures,"display_server":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"window_pixels":[root.size.x,root.size.y],"movements":movements}
	if game!=null:
		result["battlefield_pixels"] = [game.battlefield_viewport.size.x,game.battlefield_viewport.size.y]
		result["render_scale"] = game.render_scale
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var file := FileAccess.open(OUTPUT_DIR+"v12_native_viewport_probe.json",FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify(result,"\t"))
	print("NATIVE_VIEWPORT_PROBE ",JSON.stringify(result))
	if game!=null:
		game.queue_free()
	quit(0 if failures.is_empty() else 1)
