extends SceneTree
const Fixture = preload("res://tests/rts_regression_fixture.gd")
const OUTPUT := "res://artifacts/rts_revision"
var rig
var world: PaperWorld
var camera: Camera3D
var label: Label
var report: Dictionary = {"captures":[],"fixed_body":true}
var target: int
var root_rest: Transform3D
var body_rest: Transform3D

func _initialize() -> void: call_deferred("run")

func capture(name: String) -> void:
	for frame in range(8):
		world.sync(.016,[])
		await process_frame
	RenderingServer.force_draw()
	var model: Dictionary = world.models[target]
	report.fixed_body = report.fixed_body and model.root.transform==root_rest and model.volume.body.transform==body_rest
	var result: Error = root.get_texture().get_image().save_png(OUTPUT+"/"+name+".png")
	report.captures.append({"file":name+".png","error":result,"door":float(rig.sim.entities[target].get("production_door",0)),"state":rig.sim.entities[target].state})
	print("BUILDING_DOOR_CAPTURE ",name," ",result)

func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size=Vector2i(1400,1100); root.content_scale_size=root.size
	VolumeModels.configure_player_colors(["#4893e6","#4893e6","#4893e6","#4893e6"])
	rig=Fixture.new(); rig.setup()
	target=rig.ids.rivet_barracks
	# Isolate the live HQ's entrance from the fixture's close starting outpost.
	var hq_pos: Vector2 = rig.sim.entities[target].pos
	for id in rig.sim.entities.keys():
		if int(id)!=target and (rig.sim.entities[id].pos as Vector2).distance_to(hq_pos)<13:
			rig.sim.entities.erase(id)
	rig.sim._rebuild_spatial(); rig.sim._refresh_building_spatial(); rig.sim._nav_dirty=true

	var env_node:=WorldEnvironment.new()
	var env:=Environment.new()
	env.background_mode=Environment.BG_COLOR; env.background_color=Color("e6dac7")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color=Color("fff2dc"); env.ambient_light_energy=.75
	env_node.environment=env; root.add_child(env_node)
	var light:=DirectionalLight3D.new(); light.rotation_degrees=Vector3(-55,-30,0); light.light_energy=1.05; light.shadow_enabled=true; root.add_child(light)
	camera=Camera3D.new(); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.current=true; root.add_child(camera)
	world=PaperWorld.new(); root.add_child(world)
	target=rig.ids.rivet_barracks
	var pos: Vector2 = rig.sim.entities[target].pos
	camera.size=10.5; camera.position=Vector3(pos.x,2.3,pos.y)+Vector3(3,5,13); camera.look_at(Vector3(pos.x,2.3,pos.y))
	world.setup(rig.sim,camera); world.sync(.01,[])
	root_rest=world.models[target].root.transform; body_rest=world.models[target].volume.body.transform
	var canvas:=CanvasLayer.new(); root.add_child(canvas)
	label=Label.new(); label.position=Vector2(24,20); label.add_theme_font_size_override("font_size",26); label.add_theme_color_override("font_color",Color("302b25")); canvas.add_child(label)
	label.text="RIVET HQ / REDUCED HEIGHT / PERSONNEL GATE CLOSED"
	await capture("rivet_hq_gate_closed")
	var error: String = rig.sim.produce(target,"rivet_rifle")
	report.production_error=error
	for frame in range(800):
		rig.sim.step(.05)
		if int(rig.sim.entities[target].get("production_unit",-1))>0: break
	label.text="RIVET HQ / LIVE PRODUCTION / ONLY THE GATE MOVES"
	for frame in range(6): rig.sim.step(.05)
	await capture("rivet_hq_gate_opening")
	for frame in range(10): rig.sim.step(.05)
	label.text="RIVET HQ / LIVE SOLDIER EXIT / STATIONARY BUILDING"
	await capture("rivet_hq_soldier_exit")
	report.renderer=RenderingServer.get_current_rendering_method(); report.device=RenderingServer.get_video_adapter_name()
	var file:=FileAccess.open(OUTPUT+"/building_door_manifest.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("BUILDING_DOOR_GPU_RESULT ",JSON.stringify(report))
	quit(0 if error.is_empty() and report.fixed_body else 1)
