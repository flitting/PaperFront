extends SceneTree

## Reproducible native 3D faction catalog with player-color mirror examples.
var scene: Node3D
var camera: Camera3D
var overlay: CanvasLayer
var labels: Array[Dictionary]=[]
var rules: Dictionary
var output: String="res://artifacts/factions"
var capture_viewport: SubViewport
var paper_reader: PaperWorld

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size=Vector2i(2600,2200)
	capture_viewport=SubViewport.new()
	capture_viewport.size=Vector2i(2600,2200)
	capture_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(capture_viewport)
	rules=RulesLoader.load_rules()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	for faction in ["kestrel","rivet"]:
		await capture_roster(faction)
	await capture_identity()
	print("FACTION_ROSTER_CAPTURE ",ProjectSettings.globalize_path(output))
	await cleanup_capture()
	quit()

func prepare(title: String, columns: int, rows: int) -> void:
	if is_instance_valid(scene):scene.queue_free()
	if is_instance_valid(overlay):overlay.queue_free()
	labels.clear()
	scene=Node3D.new()
	capture_viewport.add_child(scene)
	overlay=CanvasLayer.new()
	capture_viewport.add_child(overlay)
	var environment:=WorldEnvironment.new()
	scene.add_child(environment)
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color("d8c8a8")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color("f5e9cd")
	environment.environment.ambient_light_energy=.69
	var sun:=DirectionalLight3D.new()
	scene.add_child(sun)
	sun.rotation_degrees=Vector3(-51,-33,0)
	sun.light_energy=1.08
	sun.shadow_enabled=true
	sun.directional_shadow_max_distance=90
	var floor_mesh:=BoxMesh.new()
	floor_mesh.size=Vector3(columns*6.1+3,.12,rows*8.7+3)
	var floor_instance:=MeshInstance3D.new()
	floor_instance.mesh=floor_mesh
	floor_instance.position.y=-.08
	var floor_material:=StandardMaterial3D.new()
	floor_material.albedo_color=Color("dac7a2")
	floor_material.roughness=1.0
	floor_instance.material_override=floor_material
	scene.add_child(floor_instance)
	camera=Camera3D.new()
	scene.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=maxf(columns*5.7,rows*7.2)+5.0
	camera.position=Vector3(1.8,40,37)
	camera.look_at(Vector3(0,.7,0))
	camera.current=true
	var heading:=Label.new()
	heading.text=title
	heading.position=Vector2(80,35)
	heading.add_theme_font_size_override("font_size",42)
	heading.add_theme_color_override("font_color",Color("382a22"))
	overlay.add_child(heading)
	var subtitle:=Label.new()
	subtitle.text="建筑 / 载具体积模型 + 步兵纸片 · 固定阵营涂装 + 独立玩家识别区"
	subtitle.position=Vector2(82,91)
	subtitle.add_theme_font_size_override("font_size",24)
	subtitle.add_theme_color_override("font_color",Color("6c573a"))
	overlay.add_child(subtitle)

func catalog_model(spec: Dictionary, kind: String, team: int, position: Vector3, text: String) -> void:
	if not VolumeModels.supports(spec,kind):
		if not is_instance_valid(paper_reader):
			paper_reader=PaperWorld.new()
			paper_reader.contours=JSON.parse_string(FileAccess.get_file_as_string("res://assets/cards/contours.json"))
		var dimensions: Vector2=paper_reader._dimensions(spec,"unit")
		var card:=MeshInstance3D.new()
		card.mesh=paper_reader._card(spec.faction+"_"+spec.art+"_idle",dimensions.x,dimensions.y,paper_reader._texture_path(spec,"idle"),team)
		card.position=position
		card.rotation.y=-.12
		scene.add_child(card)
		labels.append({"pos":position+Vector3(0,0,2.9),"text":text+" · 纸片"})
		return
	var model: Dictionary=VolumeModels.create_model(spec,kind,team)
	scene.add_child(model.root)
	model.root.position=position
	if kind=="unit":model.root.rotation.y=-.12
	if spec.art=="harvester":
		for cargo in model.cargo:cargo.visible=true
	labels.append({"pos":position+Vector3(0,0,2.9),"text":text})

func finish(path: String) -> void:
	for record in labels:
		var label:=Label.new()
		label.text=record.text
		label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		label.size=Vector2(390,48)
		label.position=camera.unproject_position(record.pos)-Vector2(195,0)
		label.add_theme_font_size_override("font_size",25)
		label.add_theme_color_override("font_color",Color("382a22"))
		overlay.add_child(label)
	for i in range(16):await process_frame
	await RenderingServer.frame_post_draw
	var error: int=capture_viewport.get_texture().get_image().save_png(path)
	print("ROSTER_IMAGE ",path," ",error)

func capture_roster(faction: String) -> void:
	var specs: Array[Dictionary]=[]
	for kind in ["building","unit"]:
		var source: Dictionary=rules.buildings if kind=="building" else rules.units
		for id in source:
			if source[id].faction==faction:specs.append({"spec":source[id],"kind":kind})
	prepare(("正典军团" if faction=="kestrel" else "重锤军团")+" / 全阵营模型",5,5)
	for i in range(specs.size()):
		var entry: Dictionary=specs[i]
		var pos:=Vector3((i%5-2)*6.1,0,(i/5-2)*8.7)
		catalog_model(entry.spec,entry.kind,0 if faction=="kestrel" else 1,pos,str(entry.spec.name))
	await finish(output+"/"+faction+"_roster.png")

func capture_identity() -> void:
	prepare("同阵营识别验证 / 橙黄玩家与青色玩家",4,4)
	var arts: Array[String]=["hq","repair","tank","fighter"]
	for faction in ["kestrel","rivet"]:
		for team in [0,1]:
			for i in range(arts.size()):
				var art: String=arts[i]
				var spec: Dictionary=rules.buildings[faction+"_"+art] if art in ["hq","repair"] else rules.units[faction+"_"+art]
				var z: float=(-15.0 if faction=="kestrel" else 5.0)+team*10.0
				catalog_model(spec,"building" if art in ["hq","repair"] else "unit",team,Vector3((i-1.5)*6.1,0,z),str(spec.name)+" · 玩家"+str(team+1))
	await finish(output+"/player_identification.png")


func cleanup_capture() -> void:
	if is_instance_valid(paper_reader):paper_reader.free()
	paper_reader=null
	if is_instance_valid(scene):scene.free()
	if is_instance_valid(overlay):overlay.free()
	if is_instance_valid(capture_viewport):capture_viewport.queue_free()
	VolumeModels.recipes.clear()
	VolumeModels.painted_material=null
	for i in range(3):await process_frame
