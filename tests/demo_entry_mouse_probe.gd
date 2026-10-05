extends SceneTree

var game: Node
var audit: Array = []
var gui_audit: Array = []

func _initialize() -> void:
	call_deferred("run")

func frame() -> void:
	await process_frame

func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.hud.action.connect(func(kind, value): audit.append({"kind": kind, "value": str(value)}))
	for count in range(6): await frame()
	var args := OS.get_cmdline_user_args()
	if "--focus" in args:
		root.grab_focus()
		for count in range(3): await frame()
	var button: Button = game.hud.entry_menu.wiki_button
	button.gui_input.connect(func(event): gui_audit.append({"class": event.get_class(), "value": str(event)}))
	var point := button.get_global_rect().get_center()
	var pixel := game.get_viewport().get_final_transform() * point
	if "--warp" in args:
		root.warp_mouse(point)
		for count in range(3): await frame()
	var report := {"button_rect": str(button.get_global_rect()), "point": str(point), "pixel": str(pixel), "final_transform": str(game.get_viewport().get_final_transform()), "viewport_rect": str(game.get_viewport().get_visible_rect()), "window_size": str(root.size), "loading": game.loading, "benchmark": game.benchmark, "quit_pending": game.quit_pending, "settings_visible": game.hud.settings.visible, "button_visible": button.is_visible_in_tree(), "button_disabled": button.disabled}
	report.focused = root.has_focus()
	report.viewport_mouse_position = str(root.get_mouse_position())
	report.focus_requested = "--focus" in args
	report.warp_requested = "--warp" in args
	var motion := InputEventMouseMotion.new()
	motion.position = pixel; motion.global_position = pixel
	Input.parse_input_event(motion)
	await frame()
	var hovered := root.gui_get_hovered_control()
	report.hovered = str(hovered.get_path()) if hovered != null else "null"
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = pixel; event.global_position = pixel
		event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		Input.parse_input_event(event)
		await frame()
	for count in range(3): await frame()
	report.actions = audit; report.gui_input = gui_audit
	report.wiki_visible = game.hud.wiki.visible
	report.entry_visible = game.hud.entry_menu.visible
	var hit_controls: Array = []
	for control in game.hud.find_children("*", "Control", true, false):
		if control.is_visible_in_tree() and control.get_global_rect().has_point(point) and control.mouse_filter != Control.MOUSE_FILTER_IGNORE:
			hit_controls.append({"path": str(control.get_path()), "class": control.get_class(), "mouse_filter": control.mouse_filter, "rect": str(control.get_global_rect())})
	report.hit_controls = hit_controls
	var output := "user://entry_mouse_probe.json"
	var index := args.find("--probe-output")
	if index >= 0 and index + 1 < args.size(): output = args[index + 1]
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("ENTRY_MOUSE_PROBE ", JSON.stringify(report))
	game.quit_game(0)
