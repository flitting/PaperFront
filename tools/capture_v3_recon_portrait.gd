extends "res://tools/capture_rts_v3_visuals.gd"
func run()->void:
	var output:String="res://assets/cards/air_naval_revision/kestrel_recon.png"
	root.size=Vector2i(512,512);root.content_scale_size=root.size
	V.configure_player_colors(["#369f95","#ba5065"])
	prepare("",2.85,Vector3(0,.36,0))
	var info:Dictionary=RulesLoader.load_rules().units.kestrel_recon.duplicate(true)
	info.art="recon"
	add_model(info,"unit",Vector3.ZERO)
	for i in range(5):await process_frame
	RenderingServer.force_draw()
	var error:Error=root.get_texture().get_image().save_png(output)
	print("RECON_PORTRAIT ",output," ",error)
	quit()
