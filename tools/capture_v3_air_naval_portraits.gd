extends "res://tools/capture_rts_v3_visuals.gd"
func run()->void:
	var output:String="res://assets/cards/air_naval_revision/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size=Vector2i(512,512);root.content_scale_size=root.size
	V.configure_player_colors(["#369f95","#ba5065"])
	var rules:Dictionary=RulesLoader.load_rules()
	for faction in ["kestrel","rivet","iron","sky"]:
		for role in ["helicopter","submarine","amphibious","hovercraft","support_ship","carrier"]:
			prepare("",2.85,Vector3(0,.36,0))
			add_model(rules.units[faction+"_"+role],"unit",Vector3.ZERO)
			for i in range(3):await process_frame
			RenderingServer.force_draw()
			var error:Error=root.get_texture().get_image().save_png(output+faction+"_"+role+".png")
			print("AIRNAVAL_PORTRAIT ",faction,"_",role," ",error)
	quit()
