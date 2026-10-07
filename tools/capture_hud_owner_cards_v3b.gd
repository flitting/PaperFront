extends SceneTree
const OUTPUT = "res://artifacts/rts_v3_palette_review"
var hud: PaperHUD
var sims: Dictionary = {}
var board: Control
var checks: int = 0
var failures: Array[String] = []
func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message)
func simulation(faction: String):
	if sims.has(faction):return sims[faction]
	var sim = load("res://tests/rule_test_simulation.gd").new()
	sim.setup(RulesLoader.load_rules(),"dev",123,faction,false)
	var index: int = 0
	for key in sim.rules.buildings:
		if sim.rules.buildings[key].faction == faction:
			sim._spawn(0,key,Vector2(10+index%8*8,10+index/8*8),true)
			index+=1
	sims[faction] = sim
	return sim
func actual_picture(id: String, owner: Color) -> TextureRect:
	var faction: String = id.get_slice("_",0)
	var sim = simulation(faction)
	var info: Dictionary = sim.data_for(id)
	var building: bool = sim.rules.buildings.has(id)
	var producer: String = "hq" if building else str(info.get("producer","factory"))
	if producer == "amphibious":producer = "factory"
	var producer_id: int = -1
	for entity in sim.entities.values():
		if entity.spec == faction+"_"+producer:producer_id=entity.id;break
	hud.sim=sim;hud.selection=[producer_id]
	hud.tab="build" if building else {"barracks":"infantry","factory":"vehicle","airfield":"air","shipyard":"naval"}[producer]
	VolumeModels.configure_player_colors([owner])
	hud.rebuild_list()
	check(hud.entry_widgets.has(id),"actual HUD production card exists "+id)
	if not hud.entry_widgets.has(id):return TextureRect.new()
	var picture: TextureRect = hud.entry_widgets[id].picture.duplicate()
	check(picture.material is ShaderMaterial,"actual HUD installs owner material "+id)
	if picture.material is ShaderMaterial:check(picture.material.get_shader_parameter("model_portrait")==1.0,"actual PNG preserves fixed pigments "+id)
	return picture
func make_board(ids: Array, name: String) -> void:
	for child in board.get_children():child.free()
	for row in range(2):
		for col in range(ids.size()):
			var pic: TextureRect = actual_picture(ids[col],Color("c14e6c") if row==0 else Color("429ac9"))
			board.add_child(pic)
			pic.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			pic.position=Vector2(25+col*255,80+row*360)
			pic.size=Vector2(230,270)
			var label:=Label.new();label.position=Vector2(25+col*255,45+row*360);label.text=("红 · " if row==0 else "蓝 · ")+str(hud.sim.data_for(ids[col]).name)
			label.add_theme_color_override("font_color",Color("392c21"));label.add_theme_font_size_override("font_size",18);board.add_child(label)
	for frame in range(8):await process_frame
	RenderingServer.force_draw()
	var img: Image = root.get_texture().get_image()
	img.save_png(OUTPUT+"/"+name+".png")
	var counts: Array = []
	for col in range(ids.size()):
		var changed: int = 0
		var unchanged_teal: int = 0
		var magenta: int = 0
		for y in range(80,350):
			for x in range(25+col*255,255+col*255):
				var a: Color = img.get_pixel(x,y)
				var b: Color = img.get_pixel(x,y+360)
				var distance: float = Vector3(a.r,a.g,a.b).distance_to(Vector3(b.r,b.g,b.b))
				if distance>.08:changed+=1
				if a.g-a.r>.08 and a.b-a.r>.02 and a.g>a.b*.85 and distance<.025:unchanged_teal+=1
				if minf(a.r,a.b)>a.g+.24 and minf(a.r,a.b)>.60:magenta+=1
		check(changed>12,"production owner actually changes pixels "+ids[col])
		if str(ids[col]).begins_with("iron_"):check(unchanged_teal>8,"Iron fixed teal remains unchanged "+ids[col])
		check(magenta==0,"no magenta source pigment leaks into production card "+ids[col])
		counts.append({"id":ids[col],"changed_pixels":changed,"fixed_teal_pixels":unchanged_teal,"magenta_leaks":magenta})
	FileAccess.open(OUTPUT+"/"+name+".json",FileAccess.WRITE).store_string(JSON.stringify(counts,"  "))
func run() -> void:
	root.size=Vector2i(1580,820);root.content_scale_size=root.size
	var background:=ColorRect.new();background.color=Color("e6dac7");background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(background)
	hud=PaperHUD.new();root.add_child(hud);hud.hide()
	board=Control.new();board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(board)
	await make_board(["iron_heavy_tank","iron_tank","iron_train","iron_fighter","iron_ship_frigate","iron_submarine"],"hud_iron_fixed_base_red_blue")
	await make_board(["sky_power","sky_advanced_power","sky_tech","sky_shipyard","kestrel_tank","rivet_tank"],"hud_sky_and_legacy_red_blue")
	print("HUD_OWNER_CARDS ",JSON.stringify({"checks":checks,"failures":failures}))
	FileAccess.open(OUTPUT+"/hud_owner_card_checks.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	hud.free();board.free();background.free();await process_frame;quit(0 if failures.is_empty() else 1)
