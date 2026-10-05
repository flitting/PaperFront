extends SceneTree

## Source-recipe checks and optional contact portraits for the revised workshop.
const Models = preload("res://scripts/volume_models.gd")
const Iron = preload("res://scripts/iron_models.gd")
var failures: Array[String]=[]
var rendered: int=0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var capture: bool="--capture" in OS.get_cmdline_user_args()
	var specs: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/faction_expansion.json"))
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(512,384)
	viewport.own_world_3d=true
	viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var stage:=Node3D.new()
	viewport.add_child(stage)
	var environment:=WorldEnvironment.new()
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color(0,0,0,0)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color("f0e2c4")
	environment.environment.ambient_light_energy=.72
	stage.add_child(environment)
	var light:=DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-51,-33,0)
	light.light_energy=1.05
	light.shadow_enabled=true
	stage.add_child(light)
	var camera:=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.current=true
	stage.add_child(camera)
	DirAccess.make_dir_recursive_absolute("/tmp/iron_revision")
	var records: Array[Dictionary]=[]
	for kind: String in ["building","unit"]:
		for art: String in (Iron.BUILDING_ARTS if kind=="building" else Iron.UNIT_ARTS):
			var id: String="iron_"+art
			var spec: Dictionary=specs["buildings" if kind=="building" else "units"][id]
			var source=Models.CraftMesh.new()
			var a: Dictionary=Iron.make(source,art,0,kind)
			var mirror=Models.CraftMesh.new()
			var b: Dictionary=Iron.make(mirror,art,1,kind)
			if source.vertices!=mirror.vertices:failures.append(id+" player changed geometry")
			if source.vertices.is_empty() or source.vertices.size()!=source.normals.size():failures.append(id+" empty geometry or missing normals")
			for vertex: Vector3 in source.vertices:
				if not vertex.is_finite():failures.append(id+" nonfinite vertex");break
			if not (a.dimensions as Vector3).is_equal_approx(b.dimensions):failures.append(id+" player changed dimensions")
			var owner_top:=false
			var owner_side:=false
			for i in range(source.colors.size()):
				if source.colors[i].is_equal_approx(Models.player_color(0)):
					owner_top=owner_top or source.normals[i].y>.7
					owner_side=owner_side or absf(source.normals[i].z)>.7
			if not owner_side:failures.append(id+" no side player plate")
			if not owner_top and not art in ["tank","assault"]:failures.append(id+" no upper player plate")
			var model: Dictionary=Models.create_model(spec,kind,0)
			stage.add_child(model.root)
			if model.turret!=null:
				var before: Vector3=Models.muzzle_world(model)-model.turret.global_position
				model.turret.rotation.y=-PI*.5
				var after: Vector3=Models.muzzle_world(model)-model.turret.global_position
				if not after.is_equal_approx(Basis(Vector3.UP,-PI*.5)*before):failures.append(id+" mismatched rotating muzzle")
				model.turret.rotation.y=0
			for cargo in model.get("cargo",[]):cargo.visible=true
			if capture:
				var bounds:=AABB()
				var first:=true
				for graphic: MeshInstance3D in model.root.find_children("*","MeshInstance3D",true,false):
					if not graphic.visible:continue
					var part: AABB=graphic.global_transform*graphic.mesh.get_aabb()
					bounds=part if first else bounds.merge(part)
					first=false
				var center: Vector3=bounds.get_center()
				camera.position=center+Vector3(6,5.8,8).normalized()*24
				camera.look_at(center)
				var extent:=Vector2.ZERO
				var inverse: Basis=camera.global_basis.inverse()
				for corner in range(8):
					var projection: Vector3=inverse*(bounds.get_endpoint(corner)-center)
					extent.x=maxf(extent.x,absf(projection.x))
					extent.y=maxf(extent.y,absf(projection.y))
				camera.size=maxf(extent.y*2,extent.x*2/(512.0/384.0))*1.16
				for frame in range(3):await process_frame
				await RenderingServer.frame_post_draw
				viewport.get_texture().get_image().save_png("/tmp/iron_revision/"+id+".png")
			records.append({"id":id,"name":spec.name,"dimensions":[model.dimensions.x,model.dimensions.y,model.dimensions.z],"source_triangles":source.vertices.size()/3})
			model.root.free()
			rendered+=1
	var report: FileAccess=FileAccess.open("/tmp/iron_revision/report.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"models":records,"failures":failures},"\t"))
	print("IRON_REVISION ",JSON.stringify({"models":rendered,"failures":failures}))
	stage.free()
	viewport.queue_free()
	Models.recipes.clear()
	Models.painted_material=null
	await process_frame
	quit(0 if failures.is_empty() else 1)
