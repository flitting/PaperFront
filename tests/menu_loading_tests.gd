extends SceneTree

const Minimap = preload("res://scripts/minimap.gd")
const LoadingScreen = preload("res://scripts/paper_loading_screen.gd")
const Battlefields = preload("res://scripts/battlefield_catalog.gd")

var checks := 0
var failures: Array[String] = []
var hud: PaperHUD
var start_payload: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition: failures.append(description)

func settle() -> void:
	for frame in range(3): await process_frame

func click(control: Control) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = control.get_global_rect().get_center()
		root.push_input(event, true)
	await settle()

func run() -> void:
	var main_script: Script = load("res://scripts/main.gd")
	expect(main_script != null and main_script.can_instantiate(), "The main game script parses and can instantiate before startup")
	root.size = Vector2i(1600, 900)
	hud = PaperHUD.new()
	root.add_child(hud)
	await settle()
	hud.action.connect(func(kind: String, value: Variant):
		if kind == "start": start_payload = value
	)
	await check_faction_menu()
	await check_loading_screen()
	await check_minimap_cliffs()
	hud.queue_free()
	await settle()
	print("MENU_LOADING ", JSON.stringify({"checks": checks, "failures": failures}))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func check_faction_menu() -> void:
	hud.show_menu(true)
	await settle()
	var ids: Array[String] = ["kestrel", "rivet", "iron", "sky"]
	var names: Array[String] = ["正典军团", "重锤军团", "铁钉同盟", "天翼教团"]
	expect(hud.faction_buttons.size() == 4, "Pregame setup offers all four playable factions")
	for index in ids.size():
		var id := ids[index]
		var card: Button = hud.faction_buttons[id]
		expect(card.is_visible_in_tree() and card.text.contains(names[index]), "Faction card is visible and named: " + id)
		expect(card.text.contains("\n"), "Faction card includes its specialty: " + id)
		expect(str(hud.faction_option.get_item_metadata(index)) == id, "Saved faction IDs retain their stable backing selection: " + id)
		await click(card)
		expect(hud.selected_faction() == id, "Actual card click selects faction: " + id)
		var pressed_count := 0
		for candidate: Button in hud.faction_buttons.values():
			if candidate.button_pressed: pressed_count += 1
		expect(pressed_count == 1 and card.button_pressed, "Exactly one faction remains selected: " + id)
	await click(hud.faction_buttons.sky)
	expect(hud.selected_faction() == "sky" and hud.faction_buttons.sky.button_pressed, "Clicking the chosen faction keeps a valid selection")
	hud.select_faction("iron")
	expect(hud.selected_faction() == "iron" and hud.faction_buttons.iron.button_pressed, "Restoring a saved faction updates its visible card")
	hud.select_faction("unknown-faction")
	expect(hud.selected_faction() == "iron", "An unknown saved faction never corrupts the active selection")
	var expected_modes: Array[String] = ["forest", "desert", "snow", "city", "random_city", "islands"]
	var map_entries: Array[Dictionary] = Battlefields.entries(false)
	expect(not hud.debug_menu_enabled and hud.map_option.item_count == 6, "Pregame setup defaults to exactly six public battlefields with debug disabled")
	expect(map_entries.size() == expected_modes.size(), "The public catalogue retains all six 320 battlefields")
	for index in range(map_entries.size()):
		var entry: Dictionary = map_entries[index]
		expect(index < expected_modes.size() and str(entry.id) == expected_modes[index] and int(entry.size) == 320, "The public catalogue preserves its battlefield ID and dimensions: " + str(entry.id))
		expect(index < hud.map_option.item_count and str(hud.map_option.get_item_metadata(index)) == str(entry.id) and hud.map_option.get_item_text(index).contains(str(entry.name)) and hud.map_option.get_item_text(index).contains("320×320"), "Each public battlefield preserves its visible ID, name and dimensions: " + str(entry.id))
	for old_mode: String in ["handmade", "random", "mountains", "mountains640", "dev", "unknown-map"]:
		hud.select_map("snow")
		hud.select_map(old_mode)
		expect(hud.selected_map() == "forest", "Unavailable saved menu selections fall back to forest: " + old_mode)
	hud.set_debug_available(true)
	expect(hud.map_option.item_count == 7, "Enabling debug adds only the compact test battlefield")
	hud.select_map("dev")
	expect(hud.selected_map() == "dev" and hud.map_option.get_item_text(hud.map_option.selected).contains("48×48"), "The dev battlefield becomes selectable after enabling debug")
	hud.set_debug_available(false)
	expect(hud.selected_map() == "forest" and hud.map_option.item_count == 6, "Disabling debug removes the dev selection and returns to forest")
	hud.seed_input.text = "12345"
	var start: Button
	for candidate: Button in hud.menu.find_children("", "Button", true, false):
		if candidate.text == "开始遭遇战": start = candidate
	expect(start != null, "The setup has a start action")
	if start != null:
		var expected_options: Dictionary = hud.match_setup.options(hud.selected_faction())
		await click(start)
		expect(start_payload == {"faction": "iron", "mode": "forest", "seed": 12345, "match_options": expected_options}, "Starting a skirmish emits the chosen faction, public map, seed and participant settings")
		expect(int(expected_options.players) == 2 and expected_options.slots.size() == 2 and expected_options.slots[0].faction == "iron" and expected_options.slots[0].control == "human" and expected_options.slots[1].control == "ai", "The default public battlefield keeps one selected human faction and one AI opponent")
		for dimensions: Vector2i in [Vector2i(1100, 700), Vector2i(1920, 1080)]:
			root.size = dimensions
			await settle()
			expect(root.get_visible_rect().encloses(hud.menu.get_global_rect()), "Setup menu stays within the window: " + str(dimensions))
			expect(hud.menu.get_global_rect().encloses(start.get_global_rect()), "The start action stays visible: " + str(dimensions))
	hud.show_menu(false)

func check_loading_screen() -> void:
	var loading := LoadingScreen.new()
	root.add_child(loading)
	loading.screen.theme = hud.theme_paper
	await settle()
	expect(not loading.screen.visible, "Loading controls begin hidden")
	loading.open("正在加载战场", "铁钉同盟 · 随机战场")
	await settle()
	expect(loading.screen.visible and loading.screen.mouse_filter == Control.MOUSE_FILTER_STOP, "Opening loading covers the screen and blocks battlefield clicks")
	expect(loading.title_label.text == "正在加载战场" and loading.detail_label.text.contains("铁钉同盟"), "Loading identifies the requested battle")
	expect(loading.progress_bar.show_percentage and loading.progress_bar.value == 0.0, "Each load begins with visible zero-percent progress")
	loading.update_progress(0.375, "生成地图")
	expect(is_equal_approx(loading.progress_bar.value, 37.5) and loading.stage_label.text == "生成地图", "Loading displays fractional percentage and the current stage")
	loading.update_progress(0.1, "构建地形")
	expect(is_equal_approx(loading.progress_bar.value, 37.5) and loading.stage_label.text == "构建地形", "Later stages cannot move the bar backward")
	loading.update_progress(2.0, "完成")
	expect(loading.progress_bar.value == 100.0, "Over-range progress clamps to completion")
	loading.close()
	expect(not loading.screen.visible, "Closing loading releases its overlay")
	loading.open("读取存档", "恢复战场")
	loading.update_progress(-1.0, "读取数据")
	expect(loading.progress_bar.value == 0.0 and loading.title_label.text == "读取存档", "Reopening clears previous progress and negative values stay at zero")
	loading.close()
	loading.queue_free()
	await settle()

func fixture(size: int, seed: int) -> Dictionary:
	var heights: Array = []
	var terrain: Array = []
	for z in size:
		var row: Array = []
		row.resize(size)
		row.fill(2.0 if z < size / 2 else 0.0)
		heights.append(row)
		var terrain_row: Array = []
		terrain_row.resize(size)
		terrain_row.fill(MapData.LAND)
		terrain.append(terrain_row)
	return {"size": size, "seed": seed, "mode": "cliff-fixture", "heights": heights, "terrain": terrain}

func covers(lines: PackedVector2Array, point: Vector2) -> bool:
	for index in range(0, lines.size(), 2):
		if Geometry2D.get_closest_point_to_segment(point, lines[index], lines[index + 1]).distance_to(point) < 0.001:
			return true
	return false

func check_minimap_cliffs() -> void:
	var mini := Minimap.new()
	mini.hud = hud
	mini.sim = WarSimulation.new()
	mini.sim.map = fixture(8, 1)
	for x in [3, 4]:
		for z in range(2, 5):
			mini.sim.map.heights[z][x] = 2.0 - 0.5 * float(z - 1)
			mini.sim.map.terrain[z][x] = MapData.RAMP
	mini.sim.map.heights[6][6] = 0.75
	mini.size = Vector2(272, 192)
	root.add_child(mini)
	await settle()
	expect(covers(mini._cliff_edges, Vector2(1.5, 4)), "The minimap marks the real plateau drop")
	expect(not covers(mini._cliff_edges, Vector2(3.5, 4)) and not covers(mini._cliff_edges, Vector2(4.5, 4)), "Navigable ramp crossings leave gaps in cliff outlines")
	expect(covers(mini._cliff_edges, Vector2(3, 3.5)), "A steep wall beside a ramp remains a cliff")
	expect(not covers(mini._cliff_edges, Vector2(6, 6.5)), "A legal 0.75-height step is not drawn as a cliff")
	var cached_texture: ImageTexture = mini.texture
	var cached_edges: PackedVector2Array = mini._cliff_edges.duplicate()
	mini.sim.map.heights[4][1] = 2.0
	mini.queue_redraw()
	await settle()
	expect(mini.texture == cached_texture and mini._cliff_edges == cached_edges, "Ordinary redraws reuse the static map and cliff cache")
	mini.invalidate_map()
	await settle()
	expect(not covers(mini._cliff_edges, Vector2(1.5, 4)) and covers(mini._cliff_edges, Vector2(1.5, 5)), "Explicit invalidation restores an earlier terrain revision with the same seed")
	mini.sim.map = fixture(640, 2)
	for x in range(310, 330):
		for z in range(306, 334):
			mini.sim.map.heights[z][x] = 2.0 - 2.0 * float(z - 305) / 29.0
			mini.sim.map.terrain[z][x] = MapData.RAMP
	mini.invalidate_map()
	await settle()
	var line_point: Vector2 = mini.map_rect.position + mini.map_rect.size * Vector2(0.2, 0.5)
	var ramp_point: Vector2 = mini.map_rect.position + mini.map_rect.size * Vector2(0.5, 0.5)
	expect(covers(mini._cliff_lines, line_point) and not covers(mini._cliff_lines, ramp_point), "A 640 map retains its contour and ramp opening at minimap scale")
	expect(mini._cliff_edges.size() < 100, "Long cliffs are merged into a small static draw list")
	cached_texture = mini.texture
	var old_lines: PackedVector2Array = mini._cliff_lines.duplicate()
	mini.size = Vector2(400, 260)
	mini.queue_redraw()
	await settle()
	line_point = mini.map_rect.position + mini.map_rect.size * Vector2(0.2, 0.5)
	expect(mini.texture == cached_texture and mini._cliff_lines != old_lines and covers(mini._cliff_lines, line_point), "Resizing reprojects cliffs without rebuilding terrain")
	mini.queue_free()
	await settle()
