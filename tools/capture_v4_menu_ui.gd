extends "res://tests/tabbed_menu_unit_brief_v4_tests.gd"

func capture(name:String)->void:
	if name=="unit_brief":
		# Earlier smoke fixtures reused this point. Let the selected live tank be
		# visible without the deliberately destroyed test plants' collapse ghosts.
		game.world.ghosts.clear()
		game.world.sync(.01,game.selected)
	await super.capture(name)
