extends "res://tools/capture_faction_roster.gd"

func run() -> void:
	capture_viewport=SubViewport.new()
	capture_viewport.size=Vector2i(2600,2200)
	capture_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(capture_viewport)
	rules=RulesLoader.load_rules()
	output="res://artifacts/faction_revision"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	for kind: String in ["building", "unit"]:
		var source: Dictionary=rules.buildings if kind=="building" else rules.units
		var specs: Array[Dictionary]=[]
		for spec: Dictionary in source.values():
			if spec.faction=="sky" and VolumeModels.supports(spec,kind): specs.append(spec)
		prepare("天翼教团 / 厚盒、纸筒与折板 · " + kind,5,3)
		camera.size=29.0
		camera.position=Vector3(13,33,37)
		camera.look_at(Vector3(0,.55,0))
		for i: int in range(specs.size()):
			var pos:=Vector3((i%5-2)*5.7,0,(i/5-1)*7.0)
			catalog_model(specs[i],kind,0,pos,str(specs[i].name))
		for record: Dictionary in labels: record.pos.z-=.5
		await finish(output+"/sky_"+kind+"_revision.png")
	await cleanup_capture()
	quit()
