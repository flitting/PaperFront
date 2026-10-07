extends "res://tools/capture_rts_model_revision.gd"
const OUT = "res://artifacts/architecture_identity_20261007"
var masks: Dictionary = {}
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	V.configure_player_colors(["#397ac4"])
	root.size=Vector2i(1800,1050); root.content_scale_size=root.size
	for tier in range(3):
		prepare("FOUR SHIPYARDS / CANON · HAMMER · LONG NAIL · PROVIDENCE / "+["NEAR","MEDIUM","FAR"][tier],14.0,Vector3(0,1.7,0))
		camera.position=Vector3(4,9,17); camera.look_at(Vector3(0,1.7,0))
		for i in range(4): add_model({"faction":["kestrel","rivet","iron","sky"][i],"art":"shipyard","size":4},"building",Vector3(-7.5+float(i)*5,0,0),tier)
		await _save(OUT+"/shipyards_lod_"+str(tier)+".png")
	prepare("SKY COMMAND NODES / FOLDED WINGS + PHASE PORTAL",11.5,Vector3(0,1.8,0))
	camera.position=Vector3(4,7,14); camera.look_at(Vector3(0,1.8,0))
	add_model({"faction":"sky","art":"hq","size":8},"building",Vector3(-3.2,0,0),0,{"production_door":.60})
	add_model({"faction":"sky","art":"outpost","size":4},"building",Vector3(4.0,0,0),0,{"production_door":.60})
	await _save(OUT+"/sky_hq_outpost.png")
	root.size=Vector2i(512,512); root.content_scale_size=root.size
	var monochrome:=StandardMaterial3D.new(); monochrome.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; monochrome.albedo_color=Color("282828")
	for faction in ["kestrel","rivet","iron","sky"]:
		var spec: Dictionary={"faction":faction,"art":"shipyard","size":4}
		prepare("",6.2,Vector3(0,1.80,0)); labels.hide()
		camera.position=Vector3(5.2,5.0,8.5); camera.look_at(Vector3(0,1.8,0))
		var model: Dictionary=add_model(spec,"building",Vector3.ZERO)
		for piece in model.meshes: piece.material_override=monochrome; piece.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		await _save(OUT+"/silhouette_"+faction+".png")
		var rendered: Image=root.get_texture().get_image()
		var mask:=PackedByteArray(); mask.resize(rendered.get_width()*rendered.get_height())
		for y in range(rendered.get_height()):
			for x in range(rendered.get_width()):
				var pixel: Color=rendered.get_pixel(x,y)
				mask[y*rendered.get_width()+x]=1 if maxf(pixel.r,maxf(pixel.g,pixel.b)) < .30 else 0
		masks[faction]=mask
		# New production cards use exactly the same meshes, in their actual livery.
		for piece in model.meshes: piece.material_override=null
		await _save("res://assets/cards/architecture_revision/"+faction+"_shipyard.png")
	for art in ["hq","outpost"]:
		var spec: Dictionary={"faction":"sky","art":art,"size":8 if art=="hq" else 4}
		var recipe: Dictionary=V._recipe(spec,"building",0)
		prepare("",maxf(recipe.dimensions.x*1.33,recipe.dimensions.y*1.4),Vector3(0,recipe.dimensions.y*.43,0)); labels.hide()
		add_model(spec,"building",Vector3.ZERO)
		await _save("res://assets/cards/architecture_revision/sky_"+art+".png")
	var overlaps: Array=[]
	var factions: Array=masks.keys()
	var passed: bool=true
	for a in range(factions.size()):
		for b in range(a+1,factions.size()):
			var left: PackedByteArray=masks[factions[a]]
			var right: PackedByteArray=masks[factions[b]]
			var intersection: int=0; var joined: int=0
			for i in range(left.size()):
				if left[i] or right[i]: joined+=1
				if left[i] and right[i]: intersection+=1
			var overlap: float=float(intersection)/maxi(1,joined)
			overlaps.append({"a":factions[a],"b":factions[b],"silhouette_iou":overlap})
			passed=passed and overlap<.83
	var file:=FileAccess.open(OUT+"/silhouette_manifest.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":passed,"same_camera":true,"one_flat_material":true,"threshold":.83,"pairs":overlaps,"device":RenderingServer.get_video_adapter_name()},"  ")); file.close()
	print("ARCHITECTURE_IDENTITY ",JSON.stringify({"passed":passed,"pairs":overlaps}))
	scene.free(); labels.free(); await process_frame; quit(0 if passed else 1)
func _save(path: String) -> void:
	for frame in range(5): await process_frame
	RenderingServer.force_draw()
	print("IDENTITY_CAPTURE ",path," ",root.get_texture().get_image().save_png(path))
