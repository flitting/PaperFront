extends "res://tools/capture_faction_roster.gd"

## Inspect the new faction chassis and gunhouses at equal scale and ownership.
func run() -> void:
	capture_viewport=SubViewport.new()
	capture_viewport.size=Vector2i(2400,1600)
	capture_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(capture_viewport)
	rules=RulesLoader.load_rules()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	for view in ["quarter","side","top","neutral"]:
		prepare("主战坦克 / 两套全新阵营底盘与炮塔",2,1)
		camera.size=12.4
		camera.position=Vector3(7,8,12) if view in ["quarter","neutral"] else Vector3(0,4,15) if view=="side" else Vector3(.1,15,.1)
		camera.look_at(Vector3(0,.5,0))
		catalog_model(rules.units.kestrel_tank,"unit",0,Vector3(-2.8,0,0),"答案坦克 · 拱肩工程底盘 / 标准斜肩炮塔")
		catalog_model(rules.units.rivet_tank,"unit",0,Vector3(2.8,0,0),"锤头坦克 · 压梁楔形底盘 / 扁宽重炮塔")
		if view=="neutral":
			var neutral:=StandardMaterial3D.new()
			neutral.albedo_color=Color("8f9690")
			neutral.roughness=1.0
			for node in scene.get_children():
				if str(node.name).begins_with("Tabletop_"):
					for graphic in node.find_children("*","MeshInstance3D",true,false):graphic.material_override=neutral
		for record in labels:record.pos.z=2.15
		await finish(output+"/tank_comparison_"+view+".png")
	print("TANK_COMPARISON_CAPTURE ",ProjectSettings.globalize_path(output))
	await cleanup_capture()
	quit()
