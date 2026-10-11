extends SceneTree

const L = preload("res://scripts/localization.gd")
const Paths = preload("res://scripts/selection_paths.gd")
class VisibilityProbe:
	extends WarSimulation
	var visible_ids: Dictionary = {}
	func entity_visible_to(_team: int, id: int) -> bool:
		return visible_ids.has(id)

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures.append(description)

func run() -> void:
	var preferences: PackedByteArray = FileAccess.get_file_as_bytes("user://settings.cfg") if FileAccess.file_exists("user://settings.cfg") else PackedByteArray()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game.audio.muted = true
	check(L.language() == "en" and root.title == "Paper Front" and game.audio.voice_language == "en", "fresh installation defaults to English interface, voices and title")
	var factions: Array[String] = []
	var positions: Array[Vector2] = []
	game.start_match("dev", 73026, "kestrel", true, {}, factions, positions, {"vision_enabled":false})
	game.hud.show_entry(false)
	game.hud.show_menu(false)
	game.sim.ai_enabled = false
	game.sim.synchronous_path_tests = true
	var sim = game.sim
	var leader: int = sim.debug_spawn_squad(0,"kestrel_rifle",Vector2(29,28),true)
	check(leader > 0, "spawn squad for real screen selection")
	var members: Array = sim.squad_members(leader)
	check(members.size() == 5, "fixture has five distinct people")
	game.focus = sim.entities[leader].pos
	game.distance = 22.0
	game.update_camera()
	game.world.sync(0.0, [], {})
	await process_frame
	var screen: Vector2 = game.project_world_to_screen(game.entity_visual_center(sim.entities[members[2]]))
	game.click_select(screen,false)
	check(game.selected.size() == 5 and sim.selection_ids(game.selected).size() == 1, "clicking a member selects exactly one complete squad")
	game.click_select(screen,true)
	check(game.selected.is_empty(), "shift-click toggles the entire selected squad")
	game.box_select(Rect2(screen-Vector2(3,3),Vector2(6,6)),false)
	check(game.selected.size() == 5, "box selecting one member includes the complete squad")
	check(game.command_units("move",Vector2(35,32)), "normal right-click command accepts squad")
	check(members.all(func(id): return not sim.entities[id].commands.is_empty()), "command reaches every squad member")
	check(Paths.selected_routes(sim.entities,game.selected,sim.rules).size() == 1, "selected squad draws one intent route")
	game.save_control_group(1)
	sim._kill_entity(leader,false)
	game.select_control_group(1)
	check(game.selected.size() == 4 and sim.selection_ids(game.selected).size() == 1, "control group recalls surviving members after leader death")
	game.hud.refresh(sim,game.selected,game.camera,true,"",0)
	check(game.hud.selection_text().contains("4/5"), "selection panel shows squad losses")
	check(game.hud.selection_details().contains("HP"), "squad detail exposes individual member health")
	game.overlay.sim = sim
	game.overlay.camera = game.camera
	game.overlay.selection = game.selected
	game.overlay.refresh_overlay()
	check(game.overlay._selected_squads.size() == 1, "selected squad shares one visual bracket")
	check(game.overlay._selected_squads[0].color == VolumeModels.player_color(0), "squad boundary uses the exact owning force color")
	var engineer: int = sim.debug_spawn_squad(0,"kestrel_engineer",Vector2(32,24),true)
	check(game.selectable_squad([engineer]) == [engineer], "engineer remains one independently selectable soldier")
	check(game.hud.purchase_cost(sim.data_for("kestrel_rifle")) == 550, "production card prices the entire five-person squad")
	check(game.hud.purchase_cost(sim.data_for("kestrel_engineer")) == 136, "engineer production retains single-person cost")
	game.handle_action("language","zh_CN")
	check(L.language() == "zh_CN" and root.title.contains("纸境"), "live language action changes to Simplified Chinese")
	var cfg := ConfigFile.new()
	check(cfg.load("user://settings.cfg") == OK and cfg.get_value("interface","language","") == "zh_CN", "chosen language persists in user preferences")
	L.set_language("en")
	game.load_preferences()
	check(L.language() == "zh_CN", "saved language restores without restarting the match")
	game.handle_action("language","en")
	check(L.language() == "en" and game.selected.size() == 4, "returning to English preserves the active squad selection")
	game._open_settings()
	check(game.hud.settings.voice_language_option.selected == 1, "settings opens with the English voice option selected")
	game.hud.settings.voice_language_option.item_selected.emit(0)
	check(game.audio.voice_language == "zh_CN" and L.language() == "en", "voice selector changes spoken language without changing the English interface")
	cfg.load("user://settings.cfg")
	check(cfg.get_value("audio","voice_language","") == "zh_CN" and cfg.get_value("interface","language","") == "en", "voice and interface preferences persist independently")
	game.handle_action("language","zh_CN")
	game.hud.settings.voice_language_option.item_selected.emit(1)
	check(game.audio.voice_language == "en" and L.language() == "zh_CN", "English voices can be used with the Chinese interface")
	game.handle_action("language","en")
	game._close_settings()
	var visibility_probe := VisibilityProbe.new()
	visibility_probe.rules = sim.rules
	for slot in range(5):
		visibility_probe.entities[900+slot] = {"id":900+slot,"kind":"unit","team":1,"spec":"kestrel_rifle","hp":17.0 if slot==1 else 99.0,"squad_id":900,"squad_slot":slot,"squad_capacity":5}
	visibility_probe.visible_ids[901] = true
	game.hud.sim = visibility_probe
	game.hud.selection = [901]
	var known_text: String = game.hud.selection_text()
	check(known_text.contains("1/5") and known_text.contains("HP 17/"), "enemy squad summary counts only visible members and their health")
	check(not game.hud.selection_details().contains("99/"), "enemy squad details do not reveal hidden member health")
	game.hud.sim = sim
	game.hud.selection = game.selected
	var invalid: Dictionary = sim.rules.duplicate(true)
	invalid.units.kestrel_engineer.squad_size = 4
	check(not RulesLoader.validate(invalid,false).is_empty(), "rules reject grouped engineers")
	game.queue_free()
	await process_frame
	if preferences.is_empty(): DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	else:
		var file := FileAccess.open("user://settings.cfg",FileAccess.WRITE)
		file.store_buffer(preferences)
	print("INFANTRY_SQUAD_INPUT ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
