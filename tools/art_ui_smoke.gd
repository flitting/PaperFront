extends SceneTree

# One short opt-in real-render check for the paper HUD iteration, not a regression suite.
var game: Node3D
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void:
	call_deferred("run")

func verify(condition: bool, detail: String) -> void:
	checks += 1
	if not condition: failures.append(detail)

func refresh_selection(ids: Array) -> void:
	game.selected.assign(ids)
	game.hud.cache_key = ""
	game.hud.refresh(game.sim, game.selected, game.camera, false, "", 0.0, -1, true)

func find_role(role: String) -> int:
	var nearest: int = -1
	var distance: float = INF
	for entity: Dictionary in game.sim.entities.values():
		if entity.team == 0 and entity.kind == "building" and game.sim.data_for(entity.spec).role == role:
			var next: float = entity.pos.distance_squared_to(Vector2(73,102))
			if next < distance: distance = next; nearest = int(entity.id)
	return nearest

func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.golden_view = "gameplay"
	game.start_golden_visual()
	game.golden_mode = false
	game.started = true
	game.hud.is_started = true
	game.set_physics_process(false)
	game.set_process(false)
	for frame in range(4): await process_frame
	verify(game.battlefield_viewport.size == Vector2i(1920,1080), "full client battlefield")
	verify(game.battlefield_rect().size == Vector2(1600,900), "full logical battlefield")
	refresh_selection([])
	verify(game.hud.entry_widgets.is_empty(), "empty selection has no construction cards")
	refresh_selection(game.golden_state.selection)
	verify(game.hud.entry_widgets.is_empty(), "unit selection has no construction cards")
	var hq: int = find_role("hq")
	refresh_selection([hq])
	verify(not game.hud.entry_widgets.is_empty(), "HQ exposes construction cards")
	for spec: String in game.hud.entry_widgets:
		verify(game.sim.rules.buildings.has(spec), "HQ card is a building: " + spec)
	game.hud.cancel_build_button.pressed.emit()
	verify(game.sim.building_orders[0].is_empty(), "HQ cancellation uses normal order refund")
	var build_money: float = game.sim.money[0]
	game.hud.entry_widgets["rivet_power"].button.pressed.emit()
	verify(game.sim.building_orders[0].get("spec", "") == "rivet_power", "HQ card creates normal building order")
	verify(game.sim.money[0] < build_money, "HQ card charges normal building cost")
	var factory: int = find_role("factory")
	refresh_selection([factory])
	verify(not game.hud.entry_widgets.is_empty(), "factory exposes production cards")
	for spec: String in game.hud.entry_widgets:
		verify(game.sim.data_for(spec).get("producer", "") == "factory", "factory card producer")
	var before_money: float = game.sim.money[0]
	if not game.hud.entry_widgets.is_empty(): game.hud.entry_widgets.values()[0].button.pressed.emit()
	verify(game.sim.money[0] < before_money, "production card charges normal money")
	verify(not game.sim.entities[factory].queue.is_empty(), "production card queues on selected factory")
	refresh_selection([find_role("barracks")])
	for spec: String in game.hud.entry_widgets:
		verify(game.sim.data_for(spec).get("producer", "") == "barracks", "barracks card producer")
	refresh_selection([find_role("power")])
	verify(game.hud.entry_widgets.is_empty(), "non-producing building has no construction cards")
	game.handle_action("debug_panel", null)
	verify(game.debug_panel.visible, "Debug button action opens diagnostics")
	game.handle_action("debug_panel", null)
	verify(not game.debug_panel.visible, "Debug button action closes diagnostics")
	game.dragging = false
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	mouse.position = Vector2(35,30)
	game._unhandled_input(mouse)
	verify(not game.dragging, "resource paper does not start world box selection")
	var zoom: float = game.distance
	mouse.button_index = MOUSE_BUTTON_WHEEL_UP
	game._unhandled_input(mouse)
	verify(is_equal_approx(game.distance, zoom), "paper panel blocks world zoom")
	game.hud.show_menu(true)
	verify(game.hud.menu.visible, "settings menu still opens")
	game.hud.show_menu(false)
	game.sim.result = "win"
	refresh_selection([])
	verify(game.hud.end_panel.visible, "result paper still opens")
	verify(game.hud.end_panel.get_child(1).has_node("Outcome"), "result message survives paper background child")
	var result := {"scope":"paper HUD minimum interactions", "renderer":RenderingServer.get_current_rendering_method(), "checks":checks, "failures":failures}
	print("ART_UI_SMOKE ", JSON.stringify(result))
	var output: String = "res://artifacts/visual_iteration/v15_ui/ui_smoke.json"
	var args := OS.get_cmdline_user_args()
	if args.size() == 1: output = args[0]
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(result,"\t"));file.close()
	game.quit_game(0 if failures.is_empty() else 2)
