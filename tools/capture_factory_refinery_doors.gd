extends SceneTree
const V = preload("res://scripts/volume_models.gd")
const OUTPUT := "res://artifacts/rts_revision"
func _initialize() -> void: call_deferred("run")
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	root.size=Vector2i(1500,950); root.content_scale_size=root.size
	V.configure_player_colors(["#4893e6"])
	var env_node:=WorldEnvironment.new(); var env:=Environment.new()
	env.background_mode=Environment.BG_COLOR; env.background_color=Color("e6dac7")
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color=Color("fff2dc"); env.ambient_light_energy=.75
	env_node.environment=env; root.add_child(env_node)
	var light:=DirectionalLight3D.new(); light.rotation_degrees=Vector3(-55,-30,0); light.light_energy=1.05; light.shadow_enabled=true; root.add_child(light)
	var camera:=Camera3D.new(); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.current=true; camera.size=15.0; root.add_child(camera)
	camera.position=Vector3(1.5,9,16); camera.look_at(Vector3(0,1.6,0))
	var floor_node:=MeshInstance3D.new(); var floor_mesh:=PlaneMesh.new(); floor_mesh.size=Vector2(22,16); floor_node.mesh=floor_mesh
	var material:=StandardMaterial3D.new(); material.albedo_color=Color("d8cbb2"); material.roughness=1.0; floor_node.material_override=material; root.add_child(floor_node)
	var canvas:=CanvasLayer.new(); root.add_child(canvas); var label:=Label.new(); label.position=Vector2(24,20); label.add_theme_font_size_override("font_size",26); label.add_theme_color_override("font_color",Color("302b25")); canvas.add_child(label)
	var manifest: Dictionary={"renderer":RenderingServer.get_current_rendering_method(),"device":RenderingServer.get_video_adapter_name(),"models":[]}
	for faction in ["kestrel","rivet","iron","sky"]:
		var nodes: Array=[]
		for art in ["factory","refinery"]:
			var spec: Dictionary={"faction":faction,"art":art,"size":6 if art=="factory" else 5}
			var model: Dictionary=V.create_model(spec,"building",0); root.add_child(model.root)
			model.root.position.x=-3.8 if art=="factory" else 3.5
			V.update_model(model,{"kind":"building","state":"emerging","production_door":1.0},.1)
			var unit: Dictionary=V.create_model({"faction":faction,"art":"tank" if art=="factory" else "harvester"},"unit",0); root.add_child(unit.root)
			unit.root.position=Vector3(model.root.position.x,0,model.dimensions.z*.43); unit.root.rotation.y=-PI*.5
			nodes.append(model.root); nodes.append(unit.root)
			manifest.models.append({"faction":faction,"art":art,"dimensions":str(model.dimensions)})
		label.text=faction.to_upper()+" / FACTORY 6 x 6 / REFINERY 5 x 5 / CLEAR TWO-CELL FRONT GATES"
		for frame in range(10): await process_frame
		RenderingServer.force_draw()
		root.get_texture().get_image().save_png(OUTPUT+"/"+faction+"_factory_refinery_gates.png")
		for node in nodes: node.free()
	var file:=FileAccess.open(OUTPUT+"/factory_refinery_gates_manifest.json",FileAccess.WRITE); file.store_string(JSON.stringify(manifest,"  "))
	print("FACTORY_REFINERY_GPU ",JSON.stringify(manifest)); quit()
