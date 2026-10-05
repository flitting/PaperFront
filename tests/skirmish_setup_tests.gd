extends SceneTree
const HUD = preload("res://scripts/paper_hud.gd")
const CATALOG = preload("res://scripts/battlefield_catalog.gd")
var checks: int = 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func run() -> void:
	var hud = HUD.new()
	root.add_child(hud)
	await process_frame
	var setup = hud.match_setup
	check(hud.selected_map() == "forest", "default skirmish uses the new forest battlefield")
	for mode: String in CATALOG.MODES:
		hud.select_map(mode)
		check(not setup.players_option.disabled, mode + " permits2-4 real participants")
		for players: int in [2, 3, 4]:
			setup.players_option.select(players - 2)
			setup.players_option.item_selected.emit(players - 2)
			for i: int in 3:
				setup.opponent_rows[i].faction.select(i + 1)
				setup.opponent_rows[i].difficulty.select(i)
			var options: Dictionary = setup.options("kestrel")
			check(options.players == players and options.slots.size() == players, "player count creates exactly matching slots")
			check(options.slots[0] == {"faction": "kestrel", "control": "human", "difficulty": "normal"}, "human slot preserves selected faction")
			for index: int in 3:
				check(setup.opponent_rows[index].row.visible == (index < players - 1), "only participating opponent rows are shown")
			for index: int in range(1, players):
				check(options.slots[index].control == "ai" and options.slots[index].faction == ["rivet", "iron", "sky"][index - 1] and options.slots[index].difficulty == ["easy", "normal", "hard"][index - 1], "per-opponent faction and difficulty remain independent")
	for mode: String in ["handmade", "random", "mountains", "mountains640", "dev"]:
		hud.select_map(mode)
		check(hud.selected_map() == "forest" and not setup.players_option.disabled and setup.player_count() == 4, "unavailable menu map falls back to forest and preserves participant preference: " + mode)
	hud.set_debug_available(true)
	hud.select_map("dev")
	check(hud.selected_map() == "dev" and setup.players_option.disabled and setup.player_count() == 2 and setup.options("iron").slots.size() == 2, "opted-in dev battlefield enforces its actual two starts")
	hud.set_debug_available(false)
	check(hud.selected_map() == "forest" and not setup.players_option.disabled and setup.player_count() == 4, "disabling debug returns to forest and restores the public participant preference")
	hud.select_map("islands")
	check(setup.player_count() == 4, "public participant preference survives a temporary dev selection")
	var saved: Dictionary = {"players": 3, "slots": [{"faction": "sky", "control": "human", "difficulty": "normal"}, {"faction": "iron", "control": "ai", "difficulty": "hard"}, {"faction": "kestrel", "control": "ai", "difficulty": "easy"}]}
	setup.restore(saved)
	check(setup.options("sky") == saved, "saved participant factions and difficulties restore exactly")
	var requested: Array = []
	hud.action.connect(func(kind, value):
		if kind == "start": requested.append(value))
	hud.select_faction("sky")
	for node: Node in hud.menu.find_children("", "Button", true, false):
		if (node as Button).text == "开始遭遇战": (node as Button).pressed.emit()
	check(requested.size() == 1 and requested[0].match_options == saved and requested[0].mode == "islands", "real start button emits the complete reviewed match configuration")
	print("Skirmish setup checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	for failure: String in failures: push_error(failure)
	hud.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
