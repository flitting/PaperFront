extends SceneTree
const Output="res://artifacts/infantry_distinction_20261007"
var rules:Dictionary
var manifest:Dictionary
var scene:Node3D
var overlay:CanvasLayer
var camera:Camera3D
var viewport:SubViewport
var reader:PaperWorld
var skin_samples:Array[Dictionary]=[]
var pixel_checks:Array[Dictionary]=[]
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(2240,1440)
	viewport=SubViewport.new();viewport.size=root.size;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	rules=RulesLoader.load_rules()
	manifest=JSON.parse_string(FileAccess.get_file_as_string("res://assets/cards/paper_infantry_revision/distinct_roles_manifest.json"))
	VolumeModels.configure_player_colors([Color("608f9e"),Color("b27060")])
	preload("res://scripts/camera_occlusion.gd").ensure_globals()
	reader=PaperWorld.new();reader.contours=JSON.parse_string(FileAccess.get_file_as_string("res://assets/cards/contours.json"))
	await board("idle",0,false,"22_roles_actual_cards.png")
	await board("combat",0,false,"22_roles_combat.png")
	await board("idle",2,true,"22_roles_far_actual_cards.png")
	await portraits()
	FileAccess.open(Output+"/actual_skin_checks.json",FileAccess.WRITE).store_string(JSON.stringify(pixel_checks,"\t"))
	for check in pixel_checks:
		if not check.passed:push_error("Rendered skin classification failed: "+str(check))
	reader.free();viewport.queue_free();await process_frame
	print("INFANTRY_DISTINCTION_CAPTURE ",Output)
	quit()
func label(text:String,pos:Vector2,size:int=26)->void:
	var node:=Label.new();node.text=text;node.position=pos
	node.add_theme_font_size_override("font_size",size)
	node.add_theme_color_override("font_color",Color("302d28"));overlay.add_child(node)
func prepare(title:String,far:bool)->void:
	if is_instance_valid(scene):scene.queue_free()
	if is_instance_valid(overlay):overlay.queue_free()
	scene=Node3D.new();viewport.add_child(scene)
	overlay=CanvasLayer.new();viewport.add_child(overlay)
	var environment:=WorldEnvironment.new();scene.add_child(environment);environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("ded5be")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.9
	var sun:=DirectionalLight3D.new();scene.add_child(sun);sun.rotation_degrees=Vector3(-15,-20,0);sun.light_energy=.55
	camera=Camera3D.new();scene.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=25.9 if far else 6.3;camera.position=Vector3(0,0,10);camera.look_at(Vector3.ZERO);camera.current=true
	label(title,Vector2(60,28),40)
	label("同一玩家涂色 · 固定橙黄徽章 · 原有方向与0.6视觉比例 · 角色主要靠剪影、背具、武器与站姿识别",Vector2(62,82),23)
func board(pose:String,lod:int,far:bool,file:String)->void:
	skin_samples.clear()
	prepare("22种步兵 / "+("远景剪影（每兵约60像素）" if far else "战斗姿势" if pose=="combat" else "实际战场纸片模型"),far)
	var row:int=0
	for faction:String in ["rivet","kestrel","iron","sky"]:
		var col:int=0
		for role:Dictionary in manifest.roles[faction]:
			var spec:Dictionary=rules.units[role.id]
			var point:Vector3=Vector3(-15.3+col*4.65,7.3-row*4.7,0) if far else Vector3(-4.08+col*1.3,1.55-row*1.4,0)
			var path:String=spec.animations["attack" if pose=="combat" else pose] if lod==0 else "res://assets/cards/paper_infantry_revision/%s_%s_%d.svg"%[role.id,pose,lod]
			var mesh:=MeshInstance3D.new();mesh.mesh=reader._card(str(role.id)+"_"+("attack" if pose=="combat" else pose),.99,1.08,path,0)
			mesh.position=point;scene.add_child(mesh)
			if pose=="idle" and not far:
				var skin:Vector2=face_pixel(str(role.id))
				var outline:Dictionary=reader.contours[path.get_file().get_basename() if reader.contours.has(path.get_file().get_basename()) else str(role.id)+"_idle"]
				var bottom:float=0
				for edge in outline.outline:bottom=maxf(bottom,float(edge[1]))
				var position:Vector3=point+Vector3((skin.x/256.0-.5)*.99,(bottom-skin.y)/320.0*1.08,.0225)
				skin_samples.append({"id":role.id,"pos":camera.unproject_position(position),"view":"battlefield"})
			var screen:Vector2=camera.unproject_position(point+Vector3(0,-.08 if not far else -.27,0))
			label(str(spec.name),screen-Vector2(52,0),23)
			col+=1
		label(str(rules.factions[faction].name).substr(0,2)+"\n"+str(rules.factions[faction].name).substr(2),Vector2(24,215+row*320) if not far else Vector2(24,250+row*260),25)
		row+=1
	await save(file)
func portraits()->void:
	viewport.size=Vector2i(2240,1640)
	skin_samples.clear()
	prepare("22种步兵 / 同步生产头像",false)
	var row:int=0
	for faction:String in ["rivet","kestrel","iron","sky"]:
		var col:int=0
		for role:Dictionary in manifest.roles[faction]:
			var info:Dictionary=rules.units[role.id]
			var picture:=TextureRect.new();picture.texture=load(info.portrait)
			picture.material=preload("res://scripts/owner_portrait_material.gd").make(str(info.portrait),0)
			picture.position=Vector2(85+col*300,140+row*350);picture.size=Vector2(256,320)
			picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;picture.size=Vector2(256,320)
			overlay.add_child(picture);label(str(info.name),picture.position+Vector2(30,325),23);col+=1
			skin_samples.append({"id":role.id,"pos":picture.position+face_pixel(str(role.id)),"view":"portrait","node":picture})
		row+=1
	await save("22_roles_production_portraits.png")
func save(file:String)->void:
	for i in range(6):await process_frame
	await RenderingServer.frame_post_draw
	var image:Image=viewport.get_texture().get_image()
	image.save_png(Output+"/"+file)
	for sample:Dictionary in skin_samples:
		var color:Color=image.get_pixelv(Vector2i(sample.pos))
		pixel_checks.append({"id":sample.id,"view":sample.view,"pixel":[sample.pos.x,sample.pos.y],"color":color.to_html(),"passed":color.r>color.g+.035 and color.g>color.b+.035})
func face_pixel(id:String)->Vector2:
	var crouch:float=24 if id.ends_with("grenadier") or id.ends_with("mortar") or id.ends_with("demolition") else 18 if id.ends_with("marksman") else 0
	if id=="rivet_gunner":return Vector2(111,92)
	if id=="kestrel_demolition":return Vector2(108,55+crouch)
	return Vector2(112,75+crouch)

