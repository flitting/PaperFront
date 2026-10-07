extends SceneTree
const OUTPUT = "res://artifacts/rts_v3_palette_review"
var failures: Array[String] = []
var checks: int = 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:failures.append(message)
func click(control: Control) -> void:
	var point: Vector2 = control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new();motion.position=point;motion.global_position=point
	root.push_input(motion)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
		root.push_input(event)
	await process_frame
func capture(name: String) -> void:
	for frame in range(10):await process_frame
	RenderingServer.force_draw()
	root.get_texture().get_image().save_png(OUTPUT+"/"+name+".png")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size=Vector2i(1600,1050);root.content_scale_size=root.size
	var game: Node3D = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false);game.set_physics_process(false);game.audio.muted=true
	game.hud.fps_label.hide()
	var entry: PaperEntryMenu = game.hud.entry_menu
	var wiki: PaperWiki = game.hud.wiki
	entry.action.connect(func(kind,_value):
		if kind == "wiki":wiki.select_entry("iron_heavy_tank"))
	await capture("entry_current_model_covers")
	var saved_palette: Array = VolumeModels.owner_palette.duplicate()
	var gameplay_color: Color = VolumeModels.player_color(0)
	await click(entry.wiki_button)
	check(wiki.visible and not entry.visible,"entry Wiki button actually opens catalog")
	check(wiki.comparison_previews.size()==2,"two default comparison displays")
	await click(wiki.color_buttons[2]);await click(wiki.color_buttons[3])
	check(wiki.comparison_previews.size()==4,"two swatch clicks add independent third and fourth colours")
	await click(wiki.rotation_button)
	await capture("wiki_four_colors_actual_clicks")
	for display in wiki.comparison_previews:
		check(display.preview_color==display.model_data.player_color,"model retains its independent selected owner")
		check(not display.rotation_active,"shared rotation pause covers every display")
	for frame in range(30):await process_frame
	check(VolumeModels.owner_palette==saved_palette and VolumeModels.player_color(0)==gameplay_color,"preview never changes gameplay palette")
	wiki.select_entry("sky_power")
	await capture("wiki_sky_power_four_colors")
	for display in wiki.comparison_previews:check(display.preview_color==display.model_data.player_color,"Sky building colours remain independent after entry switch")
	wiki.select_entry("iron_marksman")
	await capture("wiki_infantry_four_colors")
	for display in wiki.comparison_previews:
		var mesh: Mesh = display.model_data.meshes[0].mesh
		check(mesh.surface_get_material(0).get_shader_parameter("player_color")==display.preview_color,"each paper soldier owns its shader tint")
	await click(wiki.color_buttons[4]);await click(wiki.color_buttons[5])
	check(wiki.comparison_previews.size()==6,"six simultaneous choices are supported")
	wiki.select_entry("iron_carrier")
	await capture("wiki_six_colors_actual_clicks")
	check(VolumeModels.owner_palette==saved_palette,"six-colour comparison leaves gameplay palette intact")
	await click(wiki.color_buttons[4]);await click(wiki.color_buttons[5])
	root.size=Vector2i(1100,760);root.content_scale_size=root.size
	wiki.select_entry("iron_heavy_tank")
	await capture("wiki_four_colors_narrow_window")
	for display in wiki.comparison_previews:check(root.get_visible_rect().encloses(display.get_global_rect()),"four-color display stays within narrow window")
	check(wiki.detail_scroll.size.y>90,"narrow comparison retains scrollable information")
	print("WIKI_MULTICOLOR ",JSON.stringify({"checks":checks,"failures":failures}))
	FileAccess.open(OUTPUT+"/wiki_multicolor_checks.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	game.free();await process_frame;quit(0 if failures.is_empty() else 1)
