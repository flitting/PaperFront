extends SceneTree

const V = preload("res://scripts/volume_models.gd")
const OUTPUT := "res://artifacts/rts_revision"
var scene: Node3D
var camera: Camera3D
var models: Array[Dictionary] = []
var labels: CanvasLayer
var manifest: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func floor_grid(width: int, depth: int, step: float = 1.0) -> void:
	var floor_node := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(width*step,depth*step)
	floor_node.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("d8cbb2")
	mat.roughness = 1
	floor_node.material_override = mat
	scene.add_child(floor_node)
	var craft = V.CraftMesh.new()
	for x in range(-width/2,width/2+1): craft.line(Vector3(x*step,.005,-depth*step*.5),Vector3(x*step,.005,depth*step*.5),.004,Color("aaa08b"))
	for z in range(-depth/2,depth/2+1): craft.line(Vector3(-width*step*.5,.005,z*step),Vector3(width*step*.5,.005,z*step),.004,Color("aaa08b"))
	var grid := MeshInstance3D.new()
	grid.mesh = craft.mesh()
	scene.add_child(grid)

func text_label(text: String, pos: Vector2, size: int = 26) -> void:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_color_override("font_color",Color("332d25"))
	label.add_theme_font_size_override("font_size",size)
	labels.add_child(label)

func prepare(title: String, width: float, target: Vector3) -> void:
	if is_instance_valid(scene): scene.free()
	if is_instance_valid(labels): labels.free()
	models.clear()
	scene = Node3D.new()
	root.add_child(scene)
	labels = CanvasLayer.new()
	root.add_child(labels)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("e6dac7")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("fff2dc")
	env.ambient_light_energy = .78
	environment.environment = env
	scene.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-58,-28,0)
	light.light_energy = 1.15
	light.shadow_enabled = true
	scene.add_child(light)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = width
	camera.position = target+Vector3(4,6,9)
	scene.add_child(camera)
	camera.look_at(target)
	camera.current = true
	text_label(title,Vector2(38,22),32)

func add_model(spec: Dictionary, kind: String, pos: Vector3, tier: int = 0, state: Dictionary = {}) -> Dictionary:
	var model: Dictionary = V.create_model(spec,kind,0)
	scene.add_child(model.root)
	model.root.position = pos
	for node in model.meshes:
		if tier > 0: node.mesh = V.quality_mesh(node.mesh,0,"far" if tier == 1 else "extreme")
	if not state.is_empty(): V.update_model(model,state,.36)
	models.append(model)
	var vertices: int = 0
	for node in model.meshes:
		if node.mesh.get_surface_count()>0: vertices += node.mesh.surface_get_array_len(0)
	manifest.append({"art":spec.art,"faction":spec.faction,"tier":tier,"vertices":vertices,"dimensions":str(model.dimensions)})
	return model

func capture(file: String) -> void:
	for i in range(10): await process_frame
	RenderingServer.force_draw()
	var image := root.get_texture().get_image()
	var error: Error = image.save_png(OUTPUT+"/"+file+".png")
	print("RTS_CAPTURE ",file," ",error)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Real renderer required; no headless image substitutes")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/cards/rts_revision"))
	root.size = Vector2i(1600,1000)
	root.content_scale_size = root.size
	V.configure_player_colors(["#26aaa7"])
	for tier in range(3):
		prepare("HUMAN 2D PAPER INFANTRY / SAME COLOR / 1 GRID / "+["NEAR","MEDIUM","FAR"][tier],6.8,Vector3(0,.65,0))
		floor_grid(10,8,1.0)
		for i in range(4):
			var faction: String = ["kestrel","rivet","iron","sky"][i]
			for row in range(4): add_model({"faction":faction,"art":["rifle","anti","engineer","demolition"][row]},"unit",Vector3(-2.4+i*1.6,0,-2.1+row*1.4),tier)
			text_label(["CANON / EXOSUIT","HAMMER / HEAVY","LONG NAIL / STEAM","PROVIDENCE / FOLD"][i],Vector2(80+i*375,930),22)
		await capture("infantry_2d_same_color_grid" if tier == 0 else "infantry_2d_lod_"+["near","medium","far"][tier])
	for faction in ["kestrel","rivet","iron","sky"]:
		prepare("HUMAN PAPER ACTIONS / "+faction.to_upper()+" / IDLE-MOVE-COMBAT-HIT-DEATH",7.2,Vector3(0,.60,0))
		floor_grid(12,8,1)
		for tier in range(3):
			for column in range(5):
				add_model({"faction":faction,"art":"rifle","paper_pose":["idle","move","combat","hit","death"][column]},"unit",Vector3(-3.0+column*1.5,0,-1.5+tier*1.5),tier)
		await capture("human_paper_actions_"+faction)
	prepare("FOUR ARMIES / SAME PLAYER COLOR / 2 X 2 GRID VEHICLES",10.5,Vector3(0,.24,0))
	floor_grid(14,12)
	for i in range(4):
		var faction: String = ["kestrel","rivet","iron","sky"][i]
		for row in range(3): add_model({"faction":faction,"art":["tank","fighter","naval_frigate"][row]},"unit",Vector3(-4.2+i*2.8,0,-3.0+row*3.0))
	await capture("vehicles_same_color_grid")
	prepare("NEW MODELS / 2 GRID VEHICLES / THREE INDEPENDENT LODS",14.0,Vector3(0,1.10,0))
	floor_grid(18,16)
	for row in range(5):
		var art: String = ["drill","zeppelin","armored_train","rail","rail_junction"][row]
		for tier in range(3): add_model({"faction":"rivet" if row<2 else "iron","art":art,"rail_mask":3,"rail_ports":7},"building" if art in ["drill","rail","rail_junction"] else "unit",Vector3(-3.4+tier*3.4,0,-4.6+row*2.3),tier)
	text_label("NEAR",Vector2(390,930),24)
	text_label("MEDIUM",Vector2(780,930),24)
	text_label("FAR",Vector2(1180,930),24)
	await capture("new_models_three_lods")
	prepare("HQ 8 GRID / FACTORY 7 / AIRFIELD 7 / REFINERY 6",33,Vector3(0,1.5,0))
	floor_grid(42,30)
	for i in range(4):
		var art: String = ["hq","factory","airfield","refinery"][i]
		add_model({"faction":"sky","art":art,"size":8 if i==0 else 6 if i==3 else 7},"building",Vector3(-12+i*8,0,0))
	await capture("building_scale_grid")
	prepare("PRODUCTION / REAL OPEN CORRIDOR / SLIDING DOOR",10,Vector3(0,1.5,0))
	floor_grid(14,14)
	var factory := add_model({"faction":"iron","art":"factory","size":7},"building",Vector3.ZERO,0,{"production_door":1.0,"id":1})
	add_model({"faction":"iron","art":"armored_train"},"unit",Vector3(0,0,2.2))
	await capture("factory_open_train_exit")
	V.update_model(factory,{"production_door":0.0,"id":1},.1)
	await capture("factory_closed")
	# Cards are images of the actual new recipe, never old unit pictures.
	root.size=Vector2i(512,512)
	root.content_scale_size=root.size
	for art in ["drill","zeppelin","armored_train","rail","rail_junction"]:
		prepare("",4.6 if art=="drill" else 3.0,Vector3(0,1.8 if art=="drill" else .56,0))
		labels.hide()
		floor_grid(4,4)
		add_model({"faction":"rivet" if art in ["drill","zeppelin"] else "iron","art":art,"rail_mask":3,"rail_ports":7},"building" if art in ["drill","rail","rail_junction"] else "unit",Vector3.ZERO)
		for i in range(8): await process_frame
		RenderingServer.force_draw()
		var card: Image = root.get_texture().get_image()
		card.save_png("res://assets/cards/rts_revision/"+art+".png")
	var report := FileAccess.open(OUTPUT+"/model_manifest.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"renderer":RenderingServer.get_current_rendering_method(),"display":DisplayServer.get_name(),"device":RenderingServer.get_video_adapter_name(),"entries":manifest},"  "))
	V.configure_player_colors()
	scene.free()
	labels.free()
	await process_frame
	quit()
