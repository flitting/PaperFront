extends SceneTree

const HUD = preload("res://scripts/paper_hud.gd")
const Sim = preload("res://tests/rule_test_simulation.gd")
const Localization = preload("res://scripts/localization.gd")
var checks: int = 0
var failures: Array[String] = []
var hud: PaperHUD
var sim

func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func display(ids: Array) -> void:
	hud.refresh(sim, ids, null, true, "", 0.0)
	for frame in range(4): await process_frame

func run() -> void:
	Localization.initialize("en")
	var han := RegEx.new(); han.compile("[\\x{3400}-\\x{9fff}]")
	VolumeModels.configure_player_colors(["#347dd0", "#d85140"])
	sim = Sim.new()
	sim.setup(RulesLoader.load_rules(), "dev", 17, "kestrel", false, {"vision_enabled":false})
	sim.money[0] = 100000.0
	var hq: int = sim.entities.values().filter(func(entity): return entity.kind == "building" and entity.team == 0)[0].id
	var barracks: int = sim._spawn(0, "kestrel_barracks", Vector2(24,24), true)
	var engineer: int = sim._spawn(0, "kestrel_engineer", Vector2(26,24), true)
	var tank: int = sim._spawn(0, "kestrel_tank", Vector2(28,24), true)
	var enemy: int = sim._spawn(1, "rivet_tank", Vector2(29,24), true)
	var transport: int = sim._spawn(0, "iron_air_transport", Vector2(30,24), true)
	var squad: int = sim.debug_spawn_squad(0, "kestrel_rifle", Vector2(26,28), true)
	hud = HUD.new(); root.add_child(hud)
	await process_frame
	hud.is_started = true; hud.show_menu(false)
	for window: Vector2i in [Vector2i(1600,900), Vector2i(1100,700)]:
		root.size = window; root.content_scale_size = window
		await display([barracks])
		var barracks_height: float = hud.production_panel.size.y
		check(hud.production_panel.visible and not hud.construction_channels.visible and not hud.catalog_tabs.visible, "barracks exposes its single category without redundant rows: " + str(window))
		check(barracks_height < 185.0, "barracks paper shrinks to header and cards: " + str(window) + " height=" + str(barracks_height))
		var paper_bottom: float = hud.production_panel.get_global_rect().end.y
		var card_bottom: float = hud.list_box.get_global_rect().end.y
		check(paper_bottom - card_bottom <= 27.0, "no empty lower paper beneath barracks cards: " + str(window))
		check(root.get_visible_rect().encloses(hud.production_panel.get_global_rect()) and not hud.production_panel.get_global_rect().intersects(hud.minimap_panel.get_global_rect()) and not hud.production_panel.get_global_rect().intersects(hud.command_panel.get_global_rect()), "compact production stays between minimap and commands: " + str(window))
		check(hud.selection_portrait.texture != null and hud.selection_portrait.texture.resource_path == sim.data_for("kestrel_barracks").portrait, "selected building resolves its existing portrait resource")
		check(han.search(TranslationServer.translate(hud.info_label.text)) == null, "English selected-building statistics render without Chinese fragments")
		await display([hq])
		check(hud.construction_channels.visible and hud.catalog_tabs.visible and hud.category_buttons.build.visible and hud.category_buttons.defense.visible, "HQ retains both construction channels and Buildings/Defense categories")
		check(hud.production_panel.size.y >= barracks_height + 40.0, "HQ height includes its two visible context rows")
		await display(sim.squad_members(squad))
		check(hud.selection_header.visible and hud.selection_portrait_frame.visible and hud.selection_portrait_spec == "kestrel_rifle", "one complete squad displays one member-type portrait")
		check(hud.selection_portrait.texture.resource_path == sim.data_for("kestrel_rifle").portrait, "infantry prefers its dedicated portrait over idle art")
		check(hud.selection_portrait.material is ShaderMaterial and hud.selection_portrait.material.get_shader_parameter("player_color") == VolumeModels.player_color(0), "portrait cloth uses its owner's actual player color")
		check(hud.info_label.text.contains("HP") and hud.info_label.text.contains("Members") and hud.info_label.text.contains("Anti-infantry"), "squad introduction retains live membership, health, and combat role")
		check(root.get_visible_rect().encloses(hud.selection_panel.get_global_rect()) and not hud.selection_panel.get_global_rect().intersects(hud.command_panel.get_global_rect()), "portrait and introduction remain above commands at the minimum window")
		await display([engineer])
		check(hud.selection_portrait_spec == "kestrel_engineer" and hud.selection_portrait_frame.visible and hud.info_label.text.contains("HP"), "individual engineer displays its own portrait and health")
		await display([tank])
		check(hud.selection_portrait_spec == "kestrel_tank" and hud.selection_portrait.texture.resource_path == sim.data_for("kestrel_tank").animations.idle, "vehicle uses idle portrait fallback")
		await display([enemy])
		check(hud.selection_portrait_team == 1 and hud.selection_portrait.material.get_shader_parameter("player_color") == VolumeModels.player_color(1), "visible enemy portrait uses enemy owner color")
		sim.entities[transport].passengers = [engineer]; sim.entities[engineer].transport_id = transport
		await display([transport])
		check(hud.selection_portrait_spec == "iron_air_transport" and hud.return_button.visible and hud.land_button.visible and hud.unload_button.visible and hud.unload_move_button.visible, "loaded aircraft keeps its portrait and all four transport commands")
		check(root.get_visible_rect().encloses(hud.selection_panel.get_global_rect()) and hud.selection_panel.get_global_rect().position.y >= 84.0 and not hud.selection_panel.get_global_rect().intersects(hud.command_panel.get_global_rect()), "largest introduction and transport controls fit below the top HUD and above commands")
		sim.entities[transport].passengers = []; sim.entities[engineer].transport_id = -1
		await display([engineer, tank])
		check(not hud.selection_header.visible and hud.selection_portrait.texture == null and hud.info_label.text.contains("2"), "mixed selections hide the single-unit portrait and retain group summary")
		await display([])
		check(not hud.selection_panel.visible and hud.selection_portrait.texture == null, "clearing selection removes the old portrait")
	# More technology adds enough cards to overflow. The scrollbar gets only its
	# own height, and scrolling survives category changes and resizing.
	sim._spawn(0, "kestrel_factory", Vector2(32,25), true)
	sim._spawn(0, "kestrel_tech", Vector2(36,25), true)
	await display([barracks])
	check(hud.list_box.get_combined_minimum_size().x > hud.build_scroll.size.x and hud.build_scroll.get_h_scroll_bar().visible, "expanded infantry catalog scrolls horizontally")
	check(hud.production_panel.size.y < 185.0, "extra cards do not add empty vertical production space")
	hud.build_scroll.scroll_horizontal = 90
	await process_frame
	check(hud.build_scroll.scroll_horizontal > 0, "horizontal card scrolling remains usable")
	Localization.set_language("zh_CN")
	await display(sim.squad_members(squad))
	check(hud.selection_portrait_spec == "kestrel_rifle" and hud.info_label.text.contains("成员"), "Chinese UI preserves the portrait and translated squad introduction")
	hud.queue_free(); await process_frame
	if failures.is_empty(): print("HUD_COMPACT_PORTRAIT PASSED: %d checks" % checks)
	else:
		for failure: String in failures: push_error(failure)
		print("HUD_COMPACT_PORTRAIT FAILED: %d/%d" % [failures.size(), checks])
	quit(0 if failures.is_empty() else 1)
