extends SceneTree

const V = preload("res://scripts/volume_models.gd")
const OUTPUT := "res://artifacts/rts_v4_visuals"
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
	var rules: Dictionary = RulesLoader.load_rules()
	root.size = Vector2i(512,512);root.content_scale_size=root.size
	var written: Dictionary = {}
	for kind in ["unit","building"]:
		for id in rules[kind+"s"]:
			var spec: Dictionary = rules[kind+"s"][id].duplicate(true)
			if id not in ["kestrel_artillery","kestrel_advanced","iron_harvester","iron_train","iron_refinery","sky_refinery","sky_heavy_tank"] and str(spec.get("domain",""))!="naval" and not str(spec.art).begins_with("naval_"):continue
			var path: String = spec.get("animations",{}).get("idle","")
			if not path.ends_with(".png") or written.has(path):continue
			if not V.supports(spec,kind):continue
			spec.owner_color_override = Color.MAGENTA
			var recipe: Dictionary = V._recipe(spec,kind,0)
			var width: float = maxf(recipe.dimensions.x,recipe.dimensions.z)*1.45+recipe.dimensions.y*.17
			prepare("",maxf(1.75,width),Vector3(0,recipe.dimensions.y*.37,0))
			labels.hide();floor_grid(16,16)
			add_model(spec,kind,Vector3.ZERO)
			for frame in range(4):await process_frame
			RenderingServer.force_draw()
			root.get_texture().get_image().save_png(path)
			written[path] = id
	print("OWNER_MODEL_CARDS ",JSON.stringify(written))
	FileAccess.open(OUTPUT+"/owner_model_cards.json",FileAccess.WRITE).store_string(JSON.stringify(written,"  "))
	scene.free();labels.free();await process_frame;quit()
