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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size=Vector2i(1600,1000);root.content_scale_size=root.size
	var rules: Dictionary=RulesLoader.load_rules()
	V.configure_player_colors(["#c06176"])
	prepare("CHASSIS SCALE / 2-CELL BODY / LONG EQUIPMENT EXTENDS NATURALLY",12,Vector3(0,.4,0))
	floor_grid(18,14)
	var ids: Array=["kestrel_tank","kestrel_artillery","kestrel_advanced","iron_harvester"]
	for i in range(ids.size()):
		var spec: Dictionary=rules.units[ids[i]]
		add_model(spec,"unit",Vector3(-4.7+i*3.2,0,0))
		text_label(spec.name,Vector2(70+i*390,890),25)
	await capture("corrected_chassis_scale")
	prepare("REFINERIES / STEAM DISTILLATION + ORIGAMI MINERAL SEPARATOR",15,Vector3(0,1.45,0))
	floor_grid(20,17)
	for i in range(2):
		var spec: Dictionary=rules.buildings[["iron_refinery","sky_refinery"][i]]
		add_model(spec,"building",Vector3(-4.3+i*8.6,0,0),0,{"production_door":1.0,"id":i+1})
		text_label(spec.name,Vector2(380+i*760,910),27)
	await capture("independent_refinery_process_layouts")
	prepare("THREE-SECTION ARMOURED TRAIN / LOCOMOTIVE + GUN + AA COACHES",13.8,Vector3(0,.65,0))
	floor_grid(18,16)
	for tier in range(3):add_model(rules.units.iron_train,"unit",Vector3(0,0,-3.3+tier*3.3),tier)
	await capture("armoured_train_three_lods")
	prepare("WHITE BASE ARMOUR / SKY HEAVY TANK / OWNER LIVERY",6.4,Vector3(0,.4,0))
	floor_grid(10,8)
	for i in range(2):add_model(rules.units[["kestrel_heavy_tank","sky_heavy_tank"][i]],"unit",Vector3(-1.8+i*3.6,0,0))
	await capture("sky_heavy_white_base")
	prepare("NAVAL MODELS AT DOUBLE VISUAL SIZE / COLLISION STAYS 2 X 2",17,Vector3(0,.65,0))
	floor_grid(24,18)
	var navy: Array=["kestrel_ship_frigate","iron_submarine","rivet_amphibious","sky_hovercraft","kestrel_carrier"]
	for i in range(navy.size()):
		if rules.units.has(navy[i]):add_model(rules.units[navy[i]],"unit",Vector3(-6.5+(i%3)*6.5,0,-3.0+(i/3)*6.0))
	add_model({"faction":"sky","art":"naval_aa","logical_size":2,"domain":"naval"},"unit",Vector3(6.5,0,3))
	await capture("naval_double_visual_scale")
	root.size=Vector2i(512,512);root.content_scale_size=root.size
	for faction in ["kestrel","rivet","iron","sky"]:
		var spec: Dictionary={"faction":faction,"art":"naval_aa","logical_size":2,"domain":"naval","owner_color_override":Color.MAGENTA}
		prepare("",5.8,Vector3(0,.65,0));labels.hide();floor_grid(10,10)
		add_model(spec,"unit",Vector3.ZERO)
		for frame in range(6):await process_frame
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png("res://assets/cards/air_naval_revision/"+faction+"_ship_aa.png")
	scene.free();labels.free();await process_frame;quit()
