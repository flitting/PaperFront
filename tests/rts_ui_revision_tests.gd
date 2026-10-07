extends SceneTree

const Catalog = preload("res://scripts/wiki_catalog.gd")
const Tiers = preload("res://scripts/tier_availability.gd")
const OUTPUT := "res://artifacts/rts_revision_20261007/ui_revision"
var checks := 0
var failures: Array[String] = []
var images: Array[String] = []
var game

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func frames(count := 3) -> void:
	for _frame in count: await process_frame

func key(code: int, control := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	event.ctrl_pressed = control
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await frames()

func click(button: Control) -> void:
	var point: Vector2 = button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await frames()

func snapshot(name: String) -> void:
	if OS.get_environment("PAPER_FRONT_CAPTURE_OFFSCREEN") != "1": return
	game.hud.fps_label.hide()
	await frames()
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var path: String = OUTPUT.path_join(name + ".png")
	check(image != null and not image.is_empty() and image.save_png(path) == OK, "Main viewport renders " + name)
	images.append(path)

func refresh() -> void:
	game.hud.refresh(game.sim, game.selected, game.camera, false, "", 0.0)
	game.hud.refresh_groups(game.groups)
	game.world.sync(0.0, game.selected, {})

func complete_building(id: int) -> void:
	var duration: float = float(game.sim.entities[id].construct_remaining)
	for _frame in ceili((duration + .1) * 30.0): game.sim.step(1.0 / 30.0)
	refresh()
	await frames()

func tier_progression(hq: int) -> void:
	game.selected = [hq]
	game.hud.select_catalog("build")
	refresh()
	check(Tiers.current(game.sim, 0) == 0 and game.hud.entry_widgets.has("kestrel_barracks") and not game.hud.entry_widgets.has("kestrel_factory"), "T0 catalog permits initial structures and hides T1 factories")
	var funds: float = game.sim.money[0]
	check(game.sim.build(0, "kestrel_factory").contains("T1") and game.sim.money[0] == funds, "T0 cannot purchase a T1 structure or spend its price")
	var barracks: int = game.sim._spawn(0, "kestrel_barracks", Vector2(16, 35), false)
	refresh()
	check(Tiers.current(game.sim, 0) == 0 and not game.hud.entry_widgets.has("kestrel_factory"), "Unfinished barracks cannot unlock T1 cards")
	await complete_building(barracks)
	check(Tiers.current(game.sim, 0) == 1 and game.hud.entry_widgets.has("kestrel_factory") and not game.hud.entry_widgets.has("kestrel_tech"), "Actual barracks completion unlocks T1 and keeps T2 technology hidden")
	check(game.sim.build(0, "kestrel_tech").contains("T2"), "T1 cannot purchase the technology center")
	var factory: int = game.sim._spawn(0, "kestrel_factory", Vector2(29, 35), false)
	refresh()
	check(Tiers.current(game.sim, 0) == 1 and not game.hud.entry_widgets.has("kestrel_repair"), "Unfinished factory cannot unlock T2 repair depots")
	await complete_building(factory)
	check(Tiers.current(game.sim, 0) == 2 and game.hud.entry_widgets.has("kestrel_repair") and game.hud.entry_widgets.has("kestrel_tech"), "Factory completion alone unlocks T2 building cards")
	game.selected = [factory]
	refresh()
	check(game.hud.entry_widgets.has("kestrel_tank") and not game.hud.entry_widgets.has("kestrel_heavy_tank") and game.sim.produce(factory, "kestrel_heavy_tank").contains("T3"), "T2 vehicle catalog allows normal tanks and blocks T3 heavy tank purchases")
	await snapshot("tier2_vehicle_cards")
	game.sim._kill_entity(factory, true)
	game.selected = [hq]
	refresh()
	check(Tiers.current(game.sim, 0) == 1 and not game.hud.entry_widgets.has("kestrel_tech"), "Losing the sole T2 facility removes its unlock")
	var airfield: int = game.sim._spawn(0, "kestrel_airfield", Vector2(31, 44), false)
	refresh()
	check(Tiers.current(game.sim, 0) == 1, "Unfinished airport does not satisfy T2")
	await complete_building(airfield)
	check(Tiers.current(game.sim, 0) == 2 and game.hud.entry_widgets.has("kestrel_tech"), "Airport completion unlocks T2 with no factory: real OR prerequisite")
	game.hud.select_catalog("defense")
	check(game.hud.entry_widgets.has("kestrel_advanced_tower") and game.hud.entry_widgets.has("kestrel_aa_tower"), "T2 defense catalog includes advanced cannon and anti-air turret")
	await snapshot("tier2_defense_cards")
	var tech: int = game.sim._spawn(0, "kestrel_tech", Vector2(17, 43), false)
	game.selected = [barracks]
	refresh()
	check(Tiers.current(game.sim, 0) == 2 and not game.hud.entry_widgets.has("kestrel_demolition"), "Unfinished technology center cannot unlock T3 infantry")
	await complete_building(tech)
	check(Tiers.current(game.sim, 0) == 3 and game.hud.entry_widgets.has("kestrel_demolition") and game.hud.entry_widgets.kestrel_demolition.tier_label.text == "T3", "Technology center completion exposes actual T3 infantry card")
	await snapshot("tier3_infantry_cards")

func run() -> void:
	root.size = Vector2i(1440, 900)
	root.gui_embed_subwindows = true
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	await frames()
	game.audio.set_mix({"muted":true})
	check(game.start_match("dev", 177, "kestrel", true), "Starts the actual main scene")
	game.sim.ai_enabled = false
	game.sim.money[0] = 100000
	game.hud.show_entry(false)
	game.hud.show_menu(false)
	game.hud.settings.hide()
	game.selected = []
	refresh()
	check(not game.hud.group_panel.visible and game.hud.group_rows.values().all(func(row): return not row.visible), "No sidebar or placeholder rows before saving a group")
	await snapshot("groups_empty")
	var rifle: int = game.sim._spawn(0, "kestrel_rifle", Vector2(19, 19), true)
	var tank: int = game.sim._spawn(0, "kestrel_tank", Vector2(22, 19), true)
	var enemy: int = game.sim._spawn(1, "rivet_rifle", Vector2(26, 19), true)
	var hq := -1
	for entity: Dictionary in game.sim.entities.values():
		if entity.kind == "building" and entity.team == 0 and game.sim.data_for(entity.spec).role == "hq": hq = int(entity.id)
	game.selected = [rifle, tank, enemy, hq]
	await key(KEY_2, true)
	check(game.groups.get(2, []) == [rifle, tank], "Actual Ctrl2 input saves only controllable units")
	game.selected = [tank]
	await key(KEY_5, true)
	check(game.groups.get(2, []) == [rifle, tank] and game.groups.get(5, []) == [tank], "Ctrl5 preserves overlapping memberships")
	refresh()
	await frames()
	check(game.hud.group_panel.visible and game.hud.group_rows[2].visible and game.hud.group_rows[5].visible and not game.hud.group_rows[1].visible and not game.hud.group_rows[6].visible, "Only populated rows are rendered")
	check(game.hud.group_panel.size.y < 130, "Two groups shrink the sidebar to their content")
	game.selected = []
	await click(game.hud.group_rows[2])
	check(game.selected == [rifle, tank] and game.hud.selection == [rifle, tank] and not game.dragging, "Real sidebar mouse click selects the group immediately without starting world selection")
	game.selected = []
	await key(KEY_5)
	check(game.selected == [tank], "Actual 5 shortcut selects its own membership")
	game.selected = [rifle]
	await key(KEY_2, true)
	refresh()
	await click(game.hud.group_rows[5])
	check(game.selected == [tank], "Repeated sidebar rebuild keeps its paper and clickable child composition")
	game.focus = Vector2(20, 21)
	game.distance = 30
	game.update_camera()
	refresh()
	await snapshot("groups_2_5")
	game.sim._kill_entity(rifle, true)
	game.prune_control_groups()
	refresh()
	check(not game.groups.has(2) and not game.hud.group_rows[2].visible and game.hud.group_rows[5].visible, "A destroyed group's final unit removes only that row")
	game.sim.entities[tank].team = 1
	game.prune_control_groups()
	refresh()
	check(game.groups.is_empty() and not game.hud.group_panel.visible, "Loss of control clears the last row and panel")
	game.selected = [hq]
	await key(KEY_3, true)
	check(game.groups.is_empty(), "Saving a building-only selection cannot create an empty row")
	refresh()
	var power: Dictionary = game.sim.data_for("kestrel_power")
	check(game.hud.entry_widgets.has("kestrel_power") and game.hud.entry_widgets.kestrel_power.tier_label.text == Catalog.tier_label(power), "Production cards show the live rules' technology tier")
	check(game.hud.spec_tooltip(power).contains(Catalog.tier_label(power)) and game.hud.spec_tooltip(power).contains(Catalog.tier_description(power)), "Card tooltip explains the actual tier condition")
	game.focus = game.sim.entities[hq].pos
	game.update_camera()
	await snapshot("tier_building_cards")
	var sections: Array[Dictionary] = Catalog.sections(game.sim.rules, "kestrel_power")
	check(sections[0].rows.any(func(row): return row.label == "科技解锁" and str(row.value).contains(Catalog.tier_label(power))), "Wiki details expose technology tier and unlock condition")
	check(not Catalog.entries(game.sim.rules, "", "", Catalog.tier_label(power)).is_empty(), "Wiki searches by tier")
	var zeppelin_tooltip: String = game.hud.spec_tooltip(game.sim.data_for("rivet_zeppelin"))
	check(zeppelin_tooltip.contains("短程自由落体炸弹") and zeppelin_tooltip.contains("独立副武器 · 背部机枪") and zeppelin_tooltip.contains("射速 5.56发/秒"), "Actual unit-information tooltip exposes both zeppelin weapons and machine-gun firing rate")
	await tier_progression(hq)
	game.quit_pending = true
	game.audio.stop_all()
	game.queue_free()
	await frames()
	var report := {"checks":checks, "failures":failures, "images":images, "input_route":"root.push_input -> main scene GUI and unhandled key input -> main group membership and selection", "screenshot_scope":"Actual main-scene HUD in arranged fixture; screenshots only on private Xvfb when explicitly enabled by capture wrapper"}
	var file := FileAccess.open(OUTPUT.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("RTS_UI_REVISION ", JSON.stringify(report))
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
