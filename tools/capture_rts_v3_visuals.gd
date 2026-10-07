extends SceneTree

const V = preload("res://scripts/volume_models.gd")
const OUTPUT := "res://artifacts/rts_v3_visuals"
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
	root.size = Vector2i(1600,1100)
	root.content_scale_size = root.size
	V.configure_player_colors(["#369f95","#ba5065"])
	prepare("FOUR FACTIONS / SAME PLAYER TEAL / PAPER + OWNER LIVERY",31,Vector3(0,1.0,0))
	floor_grid(42,25)
	for i in range(4):
		var faction: String = ["kestrel","rivet","iron","sky"][i]
		add_model({"faction":faction,"art":"hq","size":7},"building",Vector3(-12+i*8,0,-4))
		add_model({"faction":faction,"art":"tank","logical_size":2},"unit",Vector3(-12+i*8,0,4))
		text_label(faction.to_upper(),Vector2(100+i*390,1020),23)
	await capture("four_factions_same_player")
	prepare("PLAYER SETUP COLOR / TEAL AND ROSE / IDENTICAL MODELS",23,Vector3(0,1.0,0))
	floor_grid(32,24)
	for i in range(4):
		var faction: String = ["kestrel","rivet","iron","sky"][i]
		for team in range(2):add_model({"faction":faction,"art":"tank","logical_size":2},"unit",Vector3(-8+i*5.3,0,-2.5+team*5),0,{},team)
	await capture("player_color_variants")
	prepare("FOUR AIRFIELD ARCHITECTURES / FOUR REAL SERVICE STANDS",25,Vector3(0,1.0,0))
	floor_grid(32,28)
	for i in range(4):
		var faction: String = ["kestrel","rivet","iron","sky"][i]
		add_model({"faction":faction,"art":"airfield","size":7},"building",Vector3(-5.8+(i%2)*11.6,0,-5.4+(i/2)*10.8))
	await capture("airfields_distinct")
	prepare("LOCOMOTIVE / DIRIGIBLE / DRILL / NEAR - MEDIUM - FAR",20,Vector3(0,1.1,0))
	floor_grid(26,20)
	for row in range(3):
		var art: String = ["armored_train","zeppelin","drill"][row]
		for tier in range(3):add_model({"faction":"iron" if row==0 else "rivet","art":art,"logical_size":2},"building" if row==2 else "unit",Vector3(-6.5+tier*6.5,0,-5+row*5),tier)
	await capture("special_models_three_lods")
	prepare("SKY FACTORY / ENCLOSED REAR + PERFORATED SIDE WALLS",9,Vector3(0,1.6,0))
	floor_grid(12,12)
	var factory: Dictionary = add_model({"faction":"sky","art":"factory","size":6},"building",Vector3.ZERO)
	factory.root.rotation.y = PI
	await capture("sky_factory_rear")
	prepare("VETERAN VEHICLE / DARK OWNER LIVERY + GOLD SERVICE BANDS",7,Vector3(0,.3,0))
	floor_grid(10,8)
	for i in range(2):
		var model: Dictionary = add_model({"faction":"iron","art":"tank","logical_size":2},"unit",Vector3(-1.7+i*3.4,0,0))
		if i==1:
			for node in model.meshes:node.material_override = V.veteran_paint(0)
	await capture("veteran_vehicle")
	prepare("INFANTRY CARDS / PLAYER TEAL AND ROSE / FIXED GOLD EMBLEMS",10,Vector3.ZERO)
	var samples: Array = ["rivet_gunner","kestrel_marksman","iron_mortar","sky_storm"]
	for i in range(samples.size()):
		for team in range(2):
			var picture := TextureRect.new()
			var path: String = "res://assets/cards/paper_infantry_revision/"+samples[i]+"_idle_0.svg"
			picture.texture = load(path)
			picture.material = load("res://scripts/owner_portrait_material.gd").make(path,team)
			picture.position = Vector2(95+i*380,110+team*460)
			picture.size = Vector2(270,400)
			picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			labels.add_child(picture)
	await capture("infantry_card_owner_colors")
	root.size=Vector2i(512,512);root.content_scale_size=root.size
	for art in ["armored_train","zeppelin","drill"]:
		prepare("",5.8 if art != "drill" else 4.8,Vector3(0,.7 if art != "drill" else 1.8,0))
		labels.hide();floor_grid(8,8)
		add_model({"faction":"iron" if art=="armored_train" else "rivet","art":art,"logical_size":2},"building" if art=="drill" else "unit",Vector3.ZERO)
		for frame in range(10):await process_frame
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png("res://assets/cards/rts_revision/"+art+".png")
	for faction in ["kestrel","rivet","iron","sky"]:
		prepare("",8.6,Vector3(0,1.0,0))
		labels.hide();floor_grid(10,10)
		add_model({"faction":faction,"art":"airfield","size":7},"building",Vector3.ZERO)
		for frame in range(10):await process_frame
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png("res://assets/cards/"+faction+"_airfield_portrait.png")
	var report := FileAccess.open(OUTPUT+"/manifest.json",FileAccess.WRITE)
	report.store_string(JSON.stringify(manifest,"  "))
	scene.free();labels.free()
	await process_frame
	quit()
