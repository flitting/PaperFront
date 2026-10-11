extends SceneTree
## Isolated presentation prototype. Does not modify production simulation rules.
const Squads = preload("res://scripts/infantry_squads.gd")
const V = preload("res://scripts/volume_models.gd")
const OUT = "res://artifacts/squad_comparison_20261009/"
const FONT = preload("res://assets/fonts/NotoSansCJK-Regular.ttc")
const BLUE = Color("397fc2")
const TITLES = ["开阔地 · 同人数展开", "街巷 · 窄路行进", "交火 · 成员独立受伤", "密集集结 · 远景辨识"]
var card_factory = preload("res://scripts/paper_world.gd").new()
var views: Array[SubViewport] = []
var cameras: Array[Camera3D] = []
var scenes: Array[Node3D] = []
var members: Array = [[], []]
var marks: Array[Node3D] = []
var header: Label
var counters: Array[Label] = []
var footer: Label
var scenario = 0
var angle = 0
var squad_size = 5
var selected = 0
var selected_unit = 0
var clock_time = 0.0
var capturing = false
var manifest: Array = []
var targets: Dictionary = {}

func _initialize() -> void:
	call_deferred("start")

func ui_label(text: String, pos: Vector2, size: int, color = Color("e9e2d2")) -> Label:
	var l = Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	root.add_child(l)
	return l

func start() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("GPU display required for screenshots")
		quit(2)
		return
	root.size = Vector2i(1920,1080)
	root.content_scale_size = root.size
	V.configure_player_colors(["#397fc2", "#d96143"])
	card_factory.contours = JSON.parse_string(FileAccess.get_file_as_string("res://assets/cards/contours.json"))
	var bg = ColorRect.new()
	bg.color = Color("19252c")
	bg.size = Vector2(1920,1080)
	root.add_child(bg)
	header = ui_label("", Vector2(32,15), 31)
	ui_label("A / 单兵操控", Vector2(32,74), 28)
	ui_label("B / 小队操控 · 每人独立生命", Vector2(992,74), 28,Color("8dc7f1"))
	for side in range(2):
		var vp = SubViewport.new()
		vp.size = Vector2i(950,780)
		vp.own_world_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		vp.msaa_3d = Viewport.MSAA_2X
		root.add_child(vp)
		views.append(vp)
		var display = TextureRect.new()
		display.texture = vp.get_texture()
		display.position = Vector2(5+side*960,160)
		display.size = Vector2(950,780)
		root.add_child(display)
		counters.append(ui_label("",Vector2(32+side*960,120),21))
	footer = ui_label("",Vector2(32,954),22)
	ui_label("N 场景   V 视角   4 / 5 / 6 人编制   左键选择   右键移动   空格局部爆炸   R 重置   Esc 退出",Vector2(32,1025),19,Color("a9bac3"))
	rebuild()
	if "--capture" in OS.get_cmdline_user_args():
		capturing = true
		await capture_all()
		for scene in scenes: scene.free()
		scenes.clear(); members = [[],[]]; marks.clear(); cameras.clear()
		card_factory.free()
		await process_frame
		quit()

func material(color: Color, unshaded = false) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	if unshaded: mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat

func box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> void:
	var m = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.material_override = material(color)
	m.position = pos
	parent.add_child(m)

func line(parent: Node3D, a: Vector3, b: Vector3, color: Color, width = .018) -> void:
	var craft = V.CraftMesh.new()
	craft.line(a,b,width,color)
	var m = MeshInstance3D.new()
	m.mesh = craft.mesh()
	m.material_override = material(color,true)
	parent.add_child(m)

func ring(parent: Node3D, center: Vector3, radius: float, color: Color, segments = 40) -> void:
	for k in range(segments):
		var a = TAU*k/segments
		var b = TAU*(k+1)/segments
		line(parent,center+Vector3(cos(a)*radius,.018,sin(a)*radius),center+Vector3(cos(b)*radius,.018,sin(b)*radius),color,.018)

func label3(parent: Node3D, text: String, pos: Vector3, color: Color) -> void:
	var l = Label3D.new()
	l.text = text
	l.font = FONT
	l.font_size = 48
	l.pixel_size = .006
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.modulate = color
	l.position = pos
	parent.add_child(l)

func rebuild() -> void:
	for s in scenes: s.free()
	scenes.clear(); cameras.clear(); marks.clear()
	members = [[], []]
	targets.clear()
	selected = 0
	var total = 120 if scenario == 3 else 60
	for side in range(2):
		var scene = Node3D.new()
		views[side].add_child(scene)
		scenes.append(scene)
		var env_node = WorldEnvironment.new()
		var env = Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color("e5dac4")
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color("f8e9cb")
		env.ambient_light_energy = .65
		env_node.environment = env
		scene.add_child(env_node)
		var sun = DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-52,-32,0)
		sun.light_energy = .85
		sun.shadow_enabled = true
		scene.add_child(sun)
		box(scene,Vector3(0,-.16,0),Vector3(44,.3,44),Color("c9c4a0") if scenario != 1 else Color("cabda5"))
		for x in range(-20,21):
			line(scene,Vector3(x,.002,-20),Vector3(x,.002,20),Color("b6ad91"),.006)
		for z in range(-20,21):
			line(scene,Vector3(-20,.002,z),Vector3(20,.002,z),Color("b6ad91"),.006)
		if scenario == 1:
			box(scene,Vector3(0,.012,0),Vector3(4.8,.015,30),Color("9b9689"))
			for z in [-8,0,8]:
				for x in [-6,6]:
					var model: Dictionary = V.create_model({"faction":"kestrel","art":"barracks","size":3},"building",0)
					scene.add_child(model.root)
					model.root.position = Vector3(x,0,z)
					model.root.scale = Vector3.ONE*.75
		elif scenario == 2:
			for x in [-7,-3,3,7]:
				box(scene,Vector3(x,.23,-5.2),Vector3(2.3,.46,.48),Color("857966"))
			for x in [-7,0,7]:
				ring(scene,Vector3(x,.01,2),.7,Color("7c6951"))
		else:
			for z in [-8,0,8]:
				box(scene,Vector3(-11,.08,z),Vector3(1,.16,2),Color("a4a379"))
		var groups = total/squad_size
		for i in range(total):
			var g = i/squad_size
			var slot = i%squad_size
			var pos: Vector3
			if side == 0:
				if scenario == 1:
					pos = Vector3((i%3-1)*1.05,0,-10.5+(i/3)*1.05)
				else:
					pos = Vector3((i%10-4.5)*1.55,0,(i/10-(total/10-1)*.5)*1.65)
			else:
				var center: Vector3
				if scenario == 1:
					center = Vector3(0,0,-11.0+g*(22.0/maxf(1,groups-1)))
				else:
					center = Vector3((g%4-1.5)*4.08,0,(g/4-(groups/4-1)*.5)*5.16)
				var offset: Vector2 = Squads.slot_offset(slot,squad_size,.5,Vector2.UP,Vector2.RIGHT)
				pos = center + Vector3(offset.x,0,offset.y)
				if scenario == 1: pos = center+Vector3((slot%2-.5)*.8,0,(slot/2)*.48-.48)
			var pose = "move" if scenario == 1 else "attack" if scenario == 2 else "idle"
			var model: Dictionary = make_infantry(pose)
			scene.add_child(model.root)
			model.root.position = pos
			members[side].append({"model":model,"hp":100.0,"max_hp":100.0,"group":g,"slot":slot,"base":pos})
		var mark = Node3D.new()
		scene.add_child(mark)
		marks.append(mark)
		var camera = Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		scene.add_child(camera)
		camera.current = true
		cameras.append(camera)
	update_camera()
	if scenario == 2:
		# Same indexed 100-damage event for both arrangements, member HP remains independent.
		for side in range(2):
			for i in range(squad_size):
				apply_damage(side,i,[110.0,65.0,35.0,0.0,85.0,20.0][i])
			for i in range(8):
				var e: Dictionary = members[side][12+i*3]
				line(scenes[side],e.model.root.position+Vector3(.15,.25,0),e.model.root.position+Vector3(.8,.2,-1.6),Color("f5c555"),.018)
	update_marks()

func make_infantry(pose: String) -> Dictionary:
	var node = Node3D.new()
	var graphic = MeshInstance3D.new()
	node.add_child(graphic)
	var model = {"root":node,"graphic":graphic}
	set_pose(model,pose)
	return model

func set_pose(model: Dictionary, pose: String) -> void:
	model.graphic.mesh = card_factory._card("kestrel_rifle_"+pose,.99,1.08,"",0)

func apply_damage(side: int, index: int, damage: float) -> void:
	var e: Dictionary = members[side][index]
	e.hp = maxf(0,e.hp-damage)
	if e.hp <= 0:
		set_pose(e.model,"death")
	else:
		set_pose(e.model,"hit" if damage>0 else "attack")

func update_camera() -> void:
	for c in cameras:
		var target = Vector3(0,.2,0)
		var offset: Vector3 = [Vector3(0,22,13),Vector3(16,15,22),Vector3(3,5,11)][angle]
		c.size = [28.0,27.0,10.0][angle] if scenario != 3 else [36.0,35.0,12.0][angle]
		if angle == 2: target = Vector3(-5.2,.4,-3.8) if scenario != 1 else Vector3(0,.4,-7)
		c.position = target+offset
		c.look_at(target)

func update_marks() -> void:
	var total = members[0].size()
	header.text = "步兵组织方式对比 / "+TITLES[scenario]+" / "+["战术俯视","侧向斜视","局部近景"][angle]
	for side in range(2):
		for child in marks[side].get_children(): child.free()
		var alive = 0
		for e in members[side]:
			if e.hp>0: alive += 1
		var group_count = total/squad_size
		counters[side].text = ("%d 人 / %d 个操控对象"%[total,total] if side==0 else "%d 人 / %d 个 %d 人小队"%[total,group_count,squad_size])+"   当前存活 %d"%alive
		if side == 0:
			for i in range(total):
				var e: Dictionary = members[side][i]
				if e.hp <= 0: continue
				var p: Vector3 = e.model.root.position
				if i==selected_unit or e.hp<100:
					line(marks[side],p+Vector3(-.22,1.25,0),p+Vector3(-.22+.44*e.hp/100,1.25,0),Color("4e9c69"),.033)
		else:
			for g in range(group_count):
				var center = Vector3.ZERO
				var count = 0
				var hp = 0.0
				for e in members[side]:
					if e.group != g or e.hp<=0: continue
					center += e.model.root.position
					count += 1; hp += e.hp
				if count == 0: continue
				center /= count
				var color = BLUE
				# Four corner brackets keep the silhouette light and avoid a solid blob.
				for x in [-1,1]:
					for z in [-1,1]:
						var p = center+Vector3(x*1.22,.03,z*(1.3 if squad_size<=4 else 1.85))
						line(marks[side],p,p+Vector3(-x*.4,0,0),color,.07 if g == selected else .055)
						line(marks[side],p,p+Vector3(0,0,-z*.4),color,.07 if g == selected else .055)
				label3(marks[side],"%02d · %d/%d"%[g+1,count,squad_size],center+Vector3(0,1.65,0),color)
				for e in members[side]:
					if e.group == g and e.hp>0 and (g == selected or e.hp<100):
						var p: Vector3 = e.model.root.position
						line(marks[side],p+Vector3(-.21,1.25,0),p+Vector3(.21,1.25,0),Color("704b40"),.035)
						line(marks[side],p+Vector3(-.21,1.255,.006),p+Vector3(-.21+.42*e.hp/100,1.255,.006),Color("55ac73") if e.hp>40 else Color("df8543"),.037)
	footer.text = "同兵种 / 同模型尺寸 / 同势力色 / 同镜头与场地。小队只改变编组、站位和标识。\n"+("伤亡演示：第1组分别受到 110 / 65 / 35 / 0 / 85 点伤害，成员独立倒地、留存和显示血条。" if scenario==2 else "队伍边界使用势力色，选中时加粗；所有单位均不显示脚下选择圆环；未选小队显示编号与存活人数，选中时展开成员血条。")

func _process(delta: float) -> bool:
	if capturing or scenes.is_empty(): return false
	clock_time += delta
	if not targets.is_empty():
		for side in range(2):
			for i in range(members[side].size()):
				var e: Dictionary = members[side][i]
				var key = str(side)+":"+str(i)
				if targets.has(key) and e.hp>0:
					e.model.root.position = e.model.root.position.move_toward(targets[key],delta*2.0)
		update_marks()
	return false

func _input(event: InputEvent) -> void:
	if capturing: return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE: quit()
			KEY_N: scenario = (scenario+1)%4; rebuild()
			KEY_V: angle = (angle+1)%3; update_camera(); update_marks()
			KEY_4,KEY_5,KEY_6: squad_size = event.keycode-KEY_0; rebuild()
			KEY_R: rebuild()
			KEY_SPACE:
				for side in range(2):
					var center: Vector3 = members[side][selected*squad_size].model.root.position
					ring(scenes[side],center,1.4,Color("d5683d"))
					for i in range(members[side].size()):
						var dist: float = members[side][i].model.root.position.distance_to(center)
						if dist<1.4: apply_damage(side,i,130*(1-dist/1.4))
				update_marks()
	if event is InputEventMouseButton and event.pressed and event.position.y>=160 and event.position.y<940:
		var side = 0 if event.position.x<960 else 1
		var mouse = event.position-Vector2(5+960*side,160)
		var c = cameras[side]
		var origin = c.project_ray_origin(mouse)
		var direction = c.project_ray_normal(mouse)
		var point = origin+direction*(-origin.y/direction.y)
		var nearest = 0
		var best = INF
		for i in range(members[side].size()):
			var d: float = members[side][i].model.root.position.distance_to(point)
			if d<best: best=d; nearest=i
		if event.button_index == MOUSE_BUTTON_LEFT:
			selected = int(members[side][nearest].group)
			selected_unit = nearest
			update_marks()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			for i in range(members[side].size()):
				var e: Dictionary = members[side][i]
				if (side==0 and i==selected_unit) or (side==1 and e.group==selected):
					var leader: Vector3 = members[side][selected*squad_size].base
					targets[str(side)+":"+str(i)] = point+(e.base-leader if side==1 else Vector3.ZERO)
					set_pose(e.model,"move")

func save_capture(name: String) -> void:
	for i in range(8): await process_frame
	await RenderingServer.frame_post_draw
	var result = root.get_texture().get_image().save_png(OUT+name+".png")
	manifest.append({"file":name+".png","scene":scenario,"angle":angle,"squad_size":squad_size,"initial_people_per_side":members[0].size(),"alive_per_side":[members[0].filter(func(e):return e.hp>0).size(),members[1].filter(func(e):return e.hp>0).size()],"save_error":result})
	print("SQUAD_CAPTURE ",name," ",result)

func verify_interactions() -> void:
	for n in [4,5,6]:
		scenario = 0; squad_size = n; angle = 1; rebuild()
		apply_damage(1,2,35)
		assert(members[1][2].hp == 65)
		assert(members[1][1].hp == 100)
		assert(members[1][n].hp == 100)
		apply_damage(1,0,110)
		assert(members[1][0].hp == 0)
		assert(members[1].filter(func(e):return e.hp>0).size() == 59)
		var original: Vector3 = members[1][1].model.root.position
		var click = InputEventMouseButton.new()
		click.pressed = true
		click.button_index = MOUSE_BUTTON_RIGHT
		click.position = cameras[1].unproject_position(original+Vector3(2,0,2))+Vector2(965,160)
		capturing = false
		_input(click)
		assert(targets.size() == n)
		_process(.1)
		assert(members[1][1].model.root.position.distance_to(original)>0)
		assert(members[1][0].model.root.position == members[1][0].base)
		capturing = true
	print("SQUAD_VERIFY PASS: 4/5/6 member health independence, individual death, squad order, movement, dead member exclusion")

func capture_all() -> void:
	verify_interactions()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for s in range(4):
		scenario = s; squad_size = 5; angle = 0; rebuild()
		for a in range(3):
			angle = a; update_camera(); update_marks()
			await save_capture("%02d_%s_%s"%[s+1,["field","street","casualties","muster"][s],["top","oblique","close"][a]])
	for n in [4,6]:
		scenario=0; squad_size=n; angle=1; rebuild()
		await save_capture("05_field_%d_members"%n)
	var f = FileAccess.open(OUT+"manifest.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"renderer":RenderingServer.get_current_rendering_method(),"device":RenderingServer.get_video_adapter_name(),"prototype":"production PaperWorld._card geometry and textures, 0.99 x 1.08; isolated from production simulation","captures":manifest},"  "))
