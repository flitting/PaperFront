extends SceneTree

## Production portraits render the actual cached faction model on transparency.
## Camera framing includes every articulated part, gun barrel and visible cargo.
var viewport: SubViewport
var stage: Node3D
var camera: Camera3D
var portraits: Array[Dictionary]=[]
var failures: Array[String]=[]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	viewport=SubViewport.new()
	viewport.size=Vector2i(512,384)
	viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	stage=Node3D.new()
	viewport.add_child(stage)
	var environment:=WorldEnvironment.new()
	stage.add_child(environment)
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color(0,0,0,0)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color("f0e2c4")
	environment.environment.ambient_light_energy=.72
	var light:=DirectionalLight3D.new()
	stage.add_child(light)
	light.rotation_degrees=Vector3(-51,-33,0)
	light.light_energy=1.0
	camera=Camera3D.new()
	stage.add_child(camera)
	camera.current=true
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect=Camera3D.KEEP_HEIGHT
	var rules: Dictionary=RulesLoader.load_rules()
	for faction in ["kestrel","rivet"]:
		for kind in ["building","unit"]:
			var source: Dictionary=rules.buildings if kind=="building" else rules.units
			for id in source:
				var spec: Dictionary=source[id]
				if spec.faction!=faction or not VolumeModels.supports(spec,kind):continue
				await portrait(id,spec,kind)
	await contact_sheet()
	var file:=FileAccess.open("res://artifacts/factions/portrait_index.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"size":[512,384],"transparent":true,"team":0,"portraits":portraits,"failures":failures},"\t"))
	file.close()
	print("FACTION_PORTRAITS ",JSON.stringify({"count":portraits.size(),"failures":failures}))
	stage.free()
	viewport.queue_free()
	VolumeModels.recipes.clear()
	VolumeModels.painted_material=null
	for frame in range(3):await process_frame
	quit(0 if failures.is_empty() else 1)

func portrait(id: String, spec: Dictionary, kind: String) -> void:
	var model: Dictionary=VolumeModels.create_model(spec,kind,0)
	stage.add_child(model.root)
	if spec.art=="harvester":
		for piece in model.cargo:piece.visible=true
	var bounds:=AABB()
	var first: bool=true
	for graphic in model.root.find_children("*","MeshInstance3D",true,false):
		if not graphic.visible:continue
		var part_bounds: AABB=graphic.global_transform*graphic.mesh.get_aabb()
		bounds=part_bounds if first else bounds.merge(part_bounds)
		first=false
	if first:
		failures.append(id+": model has no rendered bounds")
		model.root.free()
		return
	var center: Vector3=bounds.get_center()
	camera.position=center+Vector3(6,5.8,8).normalized()*24
	camera.look_at(center)
	var extent:=Vector2.ZERO
	var inverse: Basis=camera.global_basis.inverse()
	for corner in range(8):
		var point: Vector3=bounds.position+Vector3(bounds.size.x if corner&1 else 0.0,bounds.size.y if corner&2 else 0.0,bounds.size.z if corner&4 else 0.0)
		var projection: Vector3=inverse*(point-center)
		extent.x=maxf(extent.x,absf(projection.x))
		extent.y=maxf(extent.y,absf(projection.y))
	var aspect: float=float(viewport.size.x)/float(viewport.size.y)
	camera.size=maxf(extent.y*2.0,extent.x*2.0/aspect)*1.14
	for frame in range(3):await process_frame
	await RenderingServer.frame_post_draw
	var image: Image=viewport.get_texture().get_image()
	var opaque: int=0
	var border: int=0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x,y).a>.08:
				opaque+=1
				if x<3 or y<3 or x>=image.get_width()-3 or y>=image.get_height()-3:border+=1
	if opaque<100:failures.append(id+": blank portrait")
	if border>0:failures.append(id+": framing clips visible model")
	if image.get_pixel(0,0).a>.001:failures.append(id+": portrait background is opaque")
	var path: String="res://assets/cards/"+str(spec.faction)+"_"+str(spec.art)+"_portrait.png"
	if image.save_png(path)!=OK:failures.append(id+": portrait failed to save")
	portraits.append({"id":id,"name":spec.name,"kind":kind,"faction":spec.faction,"art":spec.art,"path":path,"opaque_pixels":opaque,"border_pixels":border,"camera_size":camera.size})
	model.root.free()

func contact_sheet() -> void:
	var sheet:=SubViewport.new()
	sheet.size=Vector2i(2048,2304)
	sheet.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(sheet)
	var canvas:=Control.new()
	canvas.size=Vector2(sheet.size)
	sheet.add_child(canvas)
	var background:=ColorRect.new()
	background.color=Color("dbcaa8")
	background.size=canvas.size
	canvas.add_child(background)
	for i in range(portraits.size()):
		var entry: Dictionary=portraits[i]
		var cell:=Vector2((i%6)*336+16,(i/6)*316+25)
		var pane:=ColorRect.new()
		pane.color=Color("f0dfbd") if entry.faction=="kestrel" else Color("e5d0aa")
		pane.position=cell
		pane.size=Vector2(320,302)
		canvas.add_child(pane)
		var picture:=TextureRect.new()
		picture.position=cell+Vector2(4,0)
		picture.size=Vector2(312,258)
		var png:=Image.new()
		png.load(ProjectSettings.globalize_path(str(entry.path)))
		picture.texture=ImageTexture.create_from_image(png)
		picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		canvas.add_child(picture)
		var label:=Label.new()
		label.text=("正典 · " if entry.faction=="kestrel" else "重锤 · ")+str(entry.name)
		label.position=cell+Vector2(2,263)
		label.size=Vector2(316,37)
		label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size",21)
		label.add_theme_color_override("font_color",Color("382a22"))
		canvas.add_child(label)
	for frame in range(3):await process_frame
	await RenderingServer.frame_post_draw
	sheet.get_texture().get_image().save_png("res://artifacts/factions/portrait_contact_sheet.png")
	sheet.queue_free()
