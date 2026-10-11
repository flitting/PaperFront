extends SceneTree
const OUT = "res://artifacts/squad_readability_20261009/"
var game
func _initialize() -> void: call_deferred("run")
func save(name: String) -> void:
	for i in range(6): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT+name+".png")
	print("VOICE_SETTINGS_CAPTURE ",name)
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size=Vector2i(1100,700); root.content_scale_size=root.size
	game=load("res://main.tscn").instantiate(); root.add_child(game)
	await process_frame
	game.set_process(false); game.set_physics_process(false); game.audio.muted=true
	game._open_settings()
	await save("settings_english_english")
	game.hud.settings.voice_language_option.item_selected.emit(0)
	await save("settings_english_chinese_voice")
	game.hud.settings.language_option.item_selected.emit(1)
	game.hud.settings.voice_language_option.item_selected.emit(1)
	await save("settings_chinese_english_voice")
	game.quit_game()
