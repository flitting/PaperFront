extends SceneTree

## Produces model-derived card art and review frames. No simulation or map.
const MODELS=preload("res://scripts/volume_models.gd")
const OUT="res://artifacts/creator_hand"
var viewport:SubViewport
var stage:Node3D
var camera:Camera3D
var model:Dictionary

func _initialize()->void:call_deferred("run")

func run()->void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	viewport=SubViewport.new()
	viewport.size=Vector2i(1024,1024)
	viewport.transparent_bg=true
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	stage=Node3D.new()
	viewport.add_child(stage)
	var environment:=WorldEnvironment.new()
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color(0,0,0,0)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color("efe4d8")
	environment.environment.ambient_light_energy=.8
	stage.add_child(environment)
	var key:=DirectionalLight3D.new()
	key.rotation_degrees=Vector3(-47,-37,0)
	key.light_energy=1.4
	stage.add_child(key)
	var fill:=DirectionalLight3D.new()
	fill.rotation_degrees=Vector3(-30,128,0)
	fill.light_energy=.42
	stage.add_child(fill)
	camera=Camera3D.new()
	camera.current=true
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=7.5
	stage.add_child(camera)
	model=MODELS.create_model({"art":"creator_hand","faction":"sky","domain":"ground"},"unit",0)
	stage.add_child(model.root)
	await snapshot("res://assets/cards/sky_creator_hand_portrait.png",Vector3(11,8,-9),Vector3(0,2.9,0),{"state":"idle"})
	await snapshot("res://assets/cards/sky_creator_hand_idle.png",Vector3(10,6.8,8),Vector3(0,2.8,0),{"state":"idle"})
	camera.size=9.2
	await snapshot(OUT+"/front.png",Vector3(15,5.9,0),Vector3(0,2.7,0),{"state":"idle"})
	await snapshot(OUT+"/side.png",Vector3(-2.0,6.2,15),Vector3(-2.0,2.6,0),{"state":"idle"})
	await snapshot(OUT+"/top.png",Vector3(-1.9,17,0),Vector3(-2.0,2.5,0),{"state":"idle"})
	await snapshot(OUT+"/stride.png",Vector3(12,6,7),Vector3(0,2.9,0),{"state":"move"},.245)
	await snapshot(OUT+"/stride_opposite.png",Vector3(12,6,7),Vector3(0,2.9,0),{"state":"move"},.515)
	var attack:Dictionary={"state":"attack","hand_strike":.05,"pos":Vector2.ZERO,"alpha":0.0,"hand_landing":Vector2(4.5,0),"hand_contact_height":.6}
	camera.size=9.0
	await snapshot(OUT+"/strike.png",Vector3(14,6,8),Vector3(2.0,2.4,0),attack)
	await snapshot(OUT+"/strike_front.png",Vector3(17,5.9,0),Vector3(2.0,2.6,0),attack)
	await snapshot(OUT+"/strike_side.png",Vector3(2.0,6.2,17),Vector3(2.0,2.6,0),attack)
	await snapshot(OUT+"/strike_top.png",Vector3(2.1,17,0),Vector3(2.0,2.4,0),attack)
	camera.size=7.5
	model.root.rotation_degrees=Vector3(0,0,-74)
	model.root.position=Vector3(-1.55,.95,0)
	await snapshot("res://assets/cards/sky_creator_hand_death.png",Vector3(12,10,-8),Vector3(0,1.9,0),{"state":"idle"})
	model.root.rotation_degrees=Vector3.ZERO
	model.root.position=Vector3.ZERO
	var tank:Dictionary=MODELS.create_model({"art":"tank","faction":"sky","domain":"ground"},"unit",0)
	stage.add_child(tank.root)
	tank.root.position=Vector3(0,0,3.5)
	camera.size=9.5
	await snapshot(OUT+"/scale.png",Vector3(15,7,13),Vector3(0,2.8,1),{"state":"idle"})
	var ground:=MeshInstance3D.new()
	var plane:=PlaneMesh.new()
	plane.size=Vector2(16,14)
	ground.mesh=plane
	ground.position.y=-.045
	var paper:=StandardMaterial3D.new()
	paper.albedo_color=Color("d7c29c")
	paper.roughness=1.0
	ground.material_override=paper
	stage.add_child(ground)
	camera.size=11.0
	await snapshot(OUT+"/rts.png",Vector3(11,17,15),Vector3(0,2.25,1),{"state":"move"},.18)
	ground.free()
	tank.root.free()
	model.root.free()
	viewport.free()
	await process_frame
	print("CREATOR_HAND_CAPTURE ",OUT)
	quit()

func snapshot(path:String,eye:Vector3,center:Vector3,e:Dictionary,delta:float=.01)->void:
	MODELS.update_model(model,e,delta)
	camera.position=eye
	camera.look_at(center)
	for i in range(4):await process_frame
	await RenderingServer.frame_post_draw
	var image:Image=viewport.get_texture().get_image()
	image.save_png(path)
