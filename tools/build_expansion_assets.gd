extends SceneTree

## Asset production only: render portraits and save articulated model resources.
## This scene never loads the game, simulation, AI, rules validator or benchmarks.
const Models = preload("res://scripts/volume_models.gd")
const OUTPUT = "res://artifacts/expansion_models"
var viewport: SubViewport
var stage: Node3D
var camera: Camera3D
var items: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("build")

func build() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	viewport = SubViewport.new()
	viewport.size = Vector2i(512,384)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	stage = Node3D.new()
	viewport.add_child(stage)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color(0,0,0,0)
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("f0e2c4")
	world.environment.ambient_light_energy = .72
	stage.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-51,-33,0)
	light.light_energy = 1.05
	stage.add_child(light)
	camera = Camera3D.new()
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	stage.add_child(camera)
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/faction_expansion.json"))
	if OS.get_cmdline_user_args().has("--sheets-only"):
		var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUTPUT+"/index.json"))
		items.assign(saved.models)
		for faction: String in ["iron","sky"]:
			await build_sheet(faction,source.factions[faction].name)
		quit()
		return
	var infantry: Array[Dictionary] = []
	for faction: String in ["iron","sky"]:
		for kind: String in ["building","unit"]:
			var specs: Dictionary = source["buildings" if kind=="building" else "units"]
			for id: String in specs:
				var spec: Dictionary = specs[id]
				if spec.faction!=faction: continue
				if kind=="unit" and spec.art in Models.INFANTRY_ART:
					infantry.append({"id":id,"name":spec.name,"faction":faction,"animations":spec.animations,"representation":"paper_card"})
					continue
				await build_model(id,spec,kind)
		await build_sheet(faction,source.factions[faction].name)
	var file := FileAccess.open(OUTPUT+"/index.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"source":"data/faction_expansion.json","team":0,"models":items,"paper_infantry":infantry},"\t"))
	file.close()
	print("Expansion assets created: ",items.size()," models, ",infantry.size()," paper infantry.")
	stage.queue_free()
	viewport.queue_free()
	for frame in range(3): await process_frame
	quit()

func build_model(id: String, spec: Dictionary, kind: String) -> void:
	var model: Dictionary = Models.create_model(spec,kind,0)
	var node: Node3D = model.root
	node.name = id
	node.set_meta("spec_id",id)
	node.set_meta("kind",kind)
	node.set_meta("faction",spec.faction)
	node.set_meta("dimensions",model.dimensions)
	node.set_meta("emblem",model.emblem)
	node.set_meta("domain",spec.get("domain","ground"))
	set_owner(node,node)
	var packed := PackedScene.new()
	packed.pack(node)
	ResourceSaver.save(packed,OUTPUT+"/"+id+".scn",ResourceSaver.FLAG_COMPRESS)
	stage.add_child(node)
	for cargo in model.get("cargo",[]): cargo.visible=true
	var bounds := AABB()
	var first: bool = true
	for graphic in node.find_children("*","MeshInstance3D",true,false):
		if not graphic.visible: continue
		var part: AABB = graphic.global_transform*graphic.mesh.get_aabb()
		bounds = part if first else bounds.merge(part)
		first = false
	var center: Vector3 = bounds.get_center()
	camera.position = center+Vector3(6,5.8,8).normalized()*24
	camera.look_at(center)
	var extent := Vector2.ZERO
	var inverse: Basis = camera.global_basis.inverse()
	for corner in range(8):
		var projection: Vector3 = inverse*(bounds.get_endpoint(corner)-center)
		extent.x = maxf(extent.x,absf(projection.x))
		extent.y = maxf(extent.y,absf(projection.y))
	camera.size = maxf(extent.y*2,extent.x*2/(512.0/384.0))*1.16
	for frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var path: String = "res://assets/cards/"+id+"_portrait.png"
	viewport.get_texture().get_image().save_png(path)
	items.append({"id":id,"name":spec.name,"faction":spec.faction,"kind":kind,"model":OUTPUT+"/"+id+".scn","portrait":path,"dimensions":[model.dimensions.x,model.dimensions.y,model.dimensions.z],"art":spec.art,"design":model.design})
	node.free()
	print("Created ",id)

func set_owner(node: Node, owner_root: Node) -> void:
	for child in node.get_children():
		child.owner = owner_root
		set_owner(child,owner_root)

func build_sheet(faction: String, faction_name: String) -> void:
	var selected: Array[Dictionary] = []
	for item in items:
		if item.faction==faction: selected.append(item)
	var sheet := SubViewport.new()
	sheet.size = Vector2i(1600,1480)
	sheet.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sheet)
	var canvas := Control.new()
	canvas.size = Vector2(sheet.size)
	sheet.add_child(canvas)
	var background := ColorRect.new()
	background.color = Color("d8c49e")
	background.size = canvas.size
	canvas.add_child(background)
	var font = load("res://assets/fonts/NotoSansCJK-Regular.ttc")
	var heading := Label.new()
	heading.text = faction_name+"  /  建筑与载具模型"
	heading.position = Vector2(25,14)
	heading.add_theme_font_override("font",font)
	heading.add_theme_font_size_override("font_size",34)
	heading.add_theme_color_override("font_color",Color("382a22"))
	canvas.add_child(heading)
	for i in range(selected.size()):
		var item: Dictionary = selected[i]
		var origin := Vector2(16+(i%5)*316,76+(i/5)*230)
		var pane := ColorRect.new()
		pane.position = origin
		pane.size = Vector2(304,220)
		pane.color = Color("eddbba") if faction=="iron" else Color("eee5d1")
		canvas.add_child(pane)
		var png := Image.new()
		png.load(ProjectSettings.globalize_path(item.portrait))
		var picture := TextureRect.new()
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.texture = ImageTexture.create_from_image(png)
		picture.position = origin+Vector2(5,0)
		picture.size = Vector2(294,190)
		canvas.add_child(picture)
		var caption := Label.new()
		caption.text = item.name
		caption.position = origin+Vector2(4,187)
		caption.size = Vector2(296,30)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.add_theme_font_override("font",font)
		caption.add_theme_font_size_override("font_size",20)
		caption.add_theme_color_override("font_color",Color("382a22"))
		canvas.add_child(caption)
	for frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	sheet.get_texture().get_image().save_png(OUTPUT+"/"+faction+"_models.png")
	sheet.queue_free()
