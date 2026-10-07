extends SceneTree

const V = preload("res://scripts/volume_models.gd")
const OUTPUT := "res://artifacts/rts_v3_palette_review"
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

func add_model(spec: Dictionary, kind: String, pos: Vector3, tier: int = 0, state: Dictionary = {}, team: int = 0) -> Dictionary:
	var model: Dictionary = V.create_model(spec,kind,team)
	scene.add_child(model.root)
	model.root.position = pos
	for node in model.meshes:
		if tier > 0: node.mesh = V.quality_mesh(node.mesh,team,"far" if tier == 1 else "extreme")
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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/cards/faction_covers_current"))
	var rules: Dictionary = RulesLoader.load_rules()
	root.size = Vector2i(640,640);root.content_scale_size=root.size
	var color_pairs: Array[Color] = [Color("c14e6c"),Color("429ac9")]
	var sky_differences: Array = []
	var sky_ids: Array = []
	for id in rules.buildings:
		if rules.buildings[id].faction == "sky":sky_ids.append(id)
	for id in sky_ids:
		var spec: Dictionary = rules.buildings[id].duplicate(true)
		var first: PackedByteArray
		for color_index in range(2):
			spec.owner_color_override = color_pairs[color_index]
			var recipe: Dictionary = V._recipe(spec,"building",0)
			var width: float = maxf(recipe.dimensions.x,recipe.dimensions.z)*1.36+recipe.dimensions.y*.2
			prepare("",maxf(3.2,width),Vector3(0,recipe.dimensions.y*.36,0))
			labels.hide();floor_grid(16,16)
			add_model(spec,"building",Vector3.ZERO)
			for frame in range(5):await process_frame
			RenderingServer.force_draw()
			var img: Image = root.get_texture().get_image()
			img.save_png(OUTPUT+"/"+id+"_"+str(color_index)+".png")
			var data: PackedByteArray = img.get_data()
			if color_index == 0:first = data
			else:
				var changed: int = 0
				for pixel in range(0,data.size(),4):
					if abs(int(data[pixel])-int(first[pixel]))+abs(int(data[pixel+1])-int(first[pixel+1]))+abs(int(data[pixel+2])-int(first[pixel+2]))>20:changed+=1
				sky_differences.append({"id":id,"changed_pixels":changed,"same_angle":true})
	root.size=Vector2i(1600,1050);root.content_scale_size=root.size
	prepare("IRON / FIXED TEAL HERITAGE + TWO PLAYER LIVERIES",15.5,Vector3(0,.7,0))
	floor_grid(24,20)
	var iron_ids: Array = ["iron_tank","iron_heavy_tank","iron_train","iron_helicopter","iron_submarine","iron_carrier"]
	for row in range(iron_ids.size()):
		var id: String = iron_ids[row]
		if not rules.units.has(id):continue
		for color_index in range(2):
			var spec: Dictionary = rules.units[id].duplicate(true)
			spec.owner_color_override = color_pairs[color_index]
			add_model(spec,"unit",Vector3(-4.5+color_index*9.0,0,-6.3+row*2.7))
	await capture("iron_fixed_teal_and_owner")
	root.size=Vector2i(800,700);root.content_scale_size=root.size
	for index in range(4):
		var faction: String = ["kestrel","rivet","iron","sky"][index]
		var owner: Color = [Color("4b91c6"),Color("bd6654"),Color("499184"),Color("a18aba")][index]
		prepare("",10.8,Vector3(0,1.25,0))
		labels.hide();floor_grid(16,15)
		var hq: Dictionary = rules.buildings[faction+"_hq"].duplicate(true)
		hq.owner_color_override=owner;hq.size=6
		add_model(hq,"building",Vector3(-.9,0,-2.0))
		var tank: Dictionary = rules.units[faction+"_heavy_tank"].duplicate(true)
		tank.owner_color_override=owner
		add_model(tank,"unit",Vector3(1.5,0,3.1))
		var air: Dictionary = rules.units[faction+"_fighter"].duplicate(true)
		air.owner_color_override=owner
		add_model(air,"unit",Vector3(-2.4,2.6,1.6))
		if faction == "iron":
			var train: Dictionary = rules.units.iron_train.duplicate(true);train.owner_color_override=owner
			add_model(train,"unit",Vector3(2.5,0,.35))
		for frame in range(7):await process_frame
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png("res://assets/cards/faction_covers_current/"+faction+".png")
	var report := FileAccess.open(OUTPUT+"/sky_owner_differences.json",FileAccess.WRITE)
	report.store_string(JSON.stringify(sky_differences,"  "))
	print("SKY_OWNER_DIFFERENCES ",JSON.stringify(sky_differences))
	scene.free();labels.free();await process_frame;quit()
