extends SceneTree
var game
const OUT := "res://artifacts/demo_20261004/ui"
func _initialize() -> void:
	call_deferred("run")
func capture(name: String) -> void:
	for frame in range(6): await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png(OUT + "/" + name + ".png")
	print("DEMO_UI_CAPTURE ", name)
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(2);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.mode=Window.MODE_WINDOWED
	root.unresizable=true
	root.size=Vector2i(1920,1080)
	game=load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false);game.set_physics_process(false)
	game.audio.set_mix({"muted":true})
	await capture("entry_1080")
	game.handle_action("settings_open",null)
	await capture("settings_1080")
	game.hud.settings.close()
	game.handle_action("entry_play",null)
	await capture("skirmish_1080")
	game.handle_action("entry_home",null)
	root.size=Vector2i(1100,700)
	await capture("entry_minimum")
	game.handle_action("settings_open",null)
	await capture("settings_minimum")
	game.hud.settings.close()
	game.handle_action("entry_play",null)
	await capture("skirmish_minimum")
	game.handle_action("entry_home",null)
	game.start_match("dev",7,"kestrel",true)
	game.hud.show_menu(false)
	game.set_process(true)
	game.pve_paused=true
	game.sim.result="win"
	game.hud.refresh(game.sim,[],game.camera,false,"",0)
	await capture("victory_minimum")
	game.sim.result="lose"
	game.hud.refresh(game.sim,[],game.camera,false,"",0)
	await capture("defeat_minimum")
	root.size=Vector2i(1920,1080)
	game.handle_action("settings_open",null)
	game.hud.settings.fullscreen.button_pressed=true
	await capture("settings_fullscreen")
	var full_mode: int=root.mode
	var full_size: Vector2i=root.size
	game.hud.settings.fullscreen.button_pressed=false
	game.hud.settings.close()
	for frame in range(6): await process_frame
	root.size=Vector2i(1920,1080)
	var factions: Array[String] = ["sky","sky","sky","sky"]
	game.start_match("dev",7,"sky",true,{},factions)
	game.sim.ai_enabled=false
	game.pve_paused=true
	game.hud.show_menu(false)
	game.hud.show_entry(false)
	for team in range(4):game.sim._spawn(team,"sky_creator_hand",Vector2(17+team*6,25),true)
	game.focus=Vector2(26,25);game.distance=48;game.camera_pitch=30;game.yaw=0
	game.update_camera()
	game.world.sync(0.0,[],{})
	await capture("hand_owner_four")
	root.size=Vector2i(1100,700)
	await capture("hand_owner_four_minimum")
	var report: Dictionary={"godot":Engine.get_version_info().string,"display":DisplayServer.get_name(),"renderer":RenderingServer.get_current_rendering_method(),"render_scale":game.render_scale,"quality":game.graphics_quality,"sources":{},"captures":{},"fullscreen_mode":full_mode,"fullscreen_size":[full_size.x,full_size.y]}
	for path:String in ["res://scripts/main.gd","res://scripts/paper_hud.gd","res://scripts/paper_entry_menu.gd","res://scripts/paper_settings.gd","res://scripts/paper_world.gd"]:report.sources[path]=FileAccess.get_sha256(path)
	var d=DirAccess.open(OUT)
	for file:String in d.get_files():
		if file.ends_with(".png"):report.captures[file]=FileAccess.get_sha256(OUT+"/"+file)
	var out=FileAccess.open(OUT+"/capture_identity.json",FileAccess.WRITE);out.store_string(JSON.stringify(report,"  "));out.close()
	await game.quit_game()
