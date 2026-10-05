extends "res://tools/capture_faction_roster.gd"

## Equal-angle comparisons remove paint as a possible faction identifier.
func run() -> void:
	capture_viewport=SubViewport.new()
	capture_viewport.size=Vector2i(2400,1600)
	capture_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(capture_viewport)
	rules=RulesLoader.load_rules()
	output="res://artifacts/factions/pairs"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var unit_pairs: Array=[ ["tank","tank"],["harvester","harvester"],["scout","scout"],["aa","aa"],["advanced","advanced"],["fighter","fighter"],["artillery","assault"],["attacker","bomber"] ]
	var building_pairs: Array=[]
	for art in ["hq","power","refinery","barracks","factory","tower","tech","outpost","repair","command","airfield"]:building_pairs.append([art,art])
	for kind in ["unit","building"]:
		if "--units-only" in OS.get_cmdline_user_args() and kind!="unit":continue
		if "--buildings-only" in OS.get_cmdline_user_args() and kind!="building":continue
		var pairs: Array=unit_pairs if kind=="unit" else building_pairs
		for pair in pairs:
			for paint in ["color","neutral"]:
				var a: Dictionary=rules.units["kestrel_"+pair[0]] if kind=="unit" else rules.buildings["kestrel_"+pair[0]]
				var b: Dictionary=rules.units["rivet_"+pair[1]] if kind=="unit" else rules.buildings["rivet_"+pair[1]]
				prepare("正典 / 重锤 · "+str(a.name)+" / "+str(b.name)+( " · 中性同色" if paint=="neutral" else ""),2,1)
				camera.size=14.0
				camera.position=Vector3(4,9,13)
				camera.look_at(Vector3(0,.7,0))
				catalog_model(a,kind,0,Vector3(-3.15,0,0),"正典 · "+str(a.name))
				catalog_model(b,kind,0,Vector3(3.15,0,0),"重锤 · "+str(b.name))
				for record in labels:record.pos.z=3.0
				if paint=="neutral":
					var neutral:=StandardMaterial3D.new()
					neutral.albedo_color=Color("8f9690")
					neutral.roughness=1.0
					for node in scene.get_children():
						if str(node.name).begins_with("Tabletop_"):
							for graphic in node.find_children("*","MeshInstance3D",true,false):graphic.material_override=neutral
				await finish(output+"/"+kind+"_"+str(pair[0])+"_"+paint+".png")
	print("FACTION_PAIRS_CAPTURE ",ProjectSettings.globalize_path(output))
	await cleanup_capture()
	quit()
