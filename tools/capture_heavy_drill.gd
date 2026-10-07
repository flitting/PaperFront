extends SceneTree

const Fixture = preload("res://tests/rts_regression_fixture.gd")
const OUTPUT := "res://artifacts/rts_revision"
var rig
var world: PaperWorld
var camera: Camera3D
var label: Label
var canvas: CanvasLayer
var drill: int
var captures: Array = []

func _initialize() -> void: call_deferred("run")

func capture(name: String, selected: bool = true) -> void:
	for frame in range(12):
		world.sync(.016,[drill] if selected else [])
		await process_frame
	RenderingServer.force_draw()
	var error: Error = root.get_texture().get_image().save_png(OUTPUT+"/"+name+".png")
	captures.append({"file":name+".png","error":error,"lod":world.lod_override})
	print("HEAVY_DRILL_CAPTURE ",name," ",error)

func aim(size: float, target_y: float = 1.9) -> void:
	var pos: Vector2 = rig.sim.mines[1].pos
	camera.size=size
	camera.position=Vector3(pos.x,target_y,pos.y)+Vector3(6,6,12)
	camera.look_at(Vector3(pos.x,target_y,pos.y))

func run() -> void:
	if DisplayServer.get_name()=="headless":quit(2);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size=Vector2i(1600,1200);root.content_scale_size=root.size
	VolumeModels.configure_player_colors(["#26aaa7","#26aaa7","#26aaa7","#26aaa7"])
	rig=Fixture.new();rig.setup();rig.produce_phase()
	var env_node:=WorldEnvironment.new()
	var env:=Environment.new()
	env.background_mode=Environment.BG_COLOR;env.background_color=Color("e6dac7")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.ambient_light_color=Color("fff2dc");env.ambient_light_energy=.75
	env_node.environment=env;root.add_child(env_node)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-30,0);light.light_energy=1.05;light.shadow_enabled=true;root.add_child(light)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.current=true;root.add_child(camera)
	world=PaperWorld.new();root.add_child(world);aim(5.8);world.setup(rig.sim,camera)
	canvas=CanvasLayer.new();root.add_child(canvas)
	var caption:=ColorRect.new();caption.color=Color("e6dac7");caption.size=Vector2(1600,72);canvas.add_child(caption)
	label=Label.new();label.position=Vector2(26,20);label.add_theme_font_size_override("font_size",28);label.add_theme_color_override("font_color",Color("302b25"));canvas.add_child(label)
	var engineer: int=rig.ids.rivet_engineer
	rig.sim.build(1,"rivet_drill",engineer);rig.sim.place_building(1,rig.sim.mines[1].pos)
	rig.wait_for(func():return int(rig.sim.mines[1].get("drill",-1))>0,20)
	drill=int(rig.sim.mines[1].get("drill",-1))
	world.lod_override=0
	label.text="HEAVY AUGER / LIVE CONSTRUCTION / ORIGINAL CRYSTAL AT ROOT"
	await capture("heavy_drill_construction")
	rig.advance(22)
	for tier in range(3):
		world.lod_override=tier
		label.text="HEAVY AUGER / "+["NEAR","MEDIUM","FAR"][tier]+" GEOMETRY / LIVE WORKING RIG + ORIGINAL ORE"
		await capture("heavy_drill_"+["near","medium","far"][tier])
	world.lod_override=0
	label.text="HEAVY AUGER / ROTATION SECOND FRAME / LIVE WORKING SPINDLE + FLYWHEEL"
	for i in range(20):world.sync(.03,[]);await process_frame
	await capture("heavy_drill_rotation_b")
	rig.sim._add_damage(drill,float(rig.sim.entities[drill].hp)*.66);rig.sim._apply_damage();rig.sim._damage.clear()
	label.text="HEAVY AUGER / DAMAGED GEARBOX / 34% HEALTH / ORIGINAL ORE STILL INDEPENDENT"
	await capture("heavy_drill_damaged")
	var report:=FileAccess.open(OUTPUT+"/heavy_drill_manifest.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"renderer":RenderingServer.get_current_rendering_method(),"device":RenderingServer.get_video_adapter_name(),"captures":captures,"fixture_failures":rig.failures},"  "))
	world.queue_free();canvas.hide()
	await process_frame
	# Production mesh rendered directly for its actual portrait/idle card.
	root.size=Vector2i(512,512);root.content_scale_size=root.size
	var model: Dictionary=VolumeModels.create_model({"faction":"rivet","art":"drill"},"building",0)
	root.add_child(model.root)
	camera.size=4.6;camera.position=Vector3(5,5.5,9)+Vector3(0,1.8,0);camera.look_at(Vector3(0,1.8,0))
	for i in range(12):await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png("res://assets/cards/rts_revision/drill.png")
	model.root.queue_free();camera.queue_free();canvas.queue_free();env_node.queue_free();light.queue_free()
	await process_frame
	VolumeModels.configure_player_colors()
	print("HEAVY_DRILL_RESULT ",JSON.stringify({"captures":captures.size(),"failures":rig.failures}))
	quit(0 if rig.failures.is_empty() else 1)
