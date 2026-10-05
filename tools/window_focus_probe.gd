extends SceneTree

## Native popup lifecycle regression; root.push_input uses logical UI coordinates.
func _initialize() -> void:
	call_deferred("run")

func click(control: Control) -> void:
	var position: Vector2 = control.get_global_rect().get_center()
	for pressed: bool in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = position
		root.push_input(event,true)

func run() -> void:
	var game: Node3D = load("res://main.tscn").instantiate()
	root.add_child(game)
	for frame in range(4):await process_frame
	for round_index in range(8):
		for option: OptionButton in [game.hud.faction_option,game.hud.map_option]:
			game.hud.show_menu(true)
			click(option)
			for frame in range(3):await process_frame
			print("POPUP_PROBE ",round_index," ",option.get_popup().visible)
			option.get_popup().hide()
			for frame in range(2):await process_frame
	game.confirm.popup_centered(Vector2i(440,180))
	for frame in range(3):await process_frame
	game.confirm.hide()
	for frame in range(3):await process_frame
	game.quit_game()
