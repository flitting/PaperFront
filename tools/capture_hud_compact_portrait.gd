extends SceneTree
const HUD = preload("res://scripts/paper_hud.gd")
const Sim = preload("res://tests/rule_test_simulation.gd")
const L = preload("res://scripts/localization.gd")
const OUT := "res://artifacts/hud_compact_portrait_20261009/"
var hud: PaperHUD
var sim
func _initialize() -> void: call_deferred("run")
func capture(name: String, ids: Array) -> void:
	hud.refresh(sim, ids, null, true, "", 0.0)
	for frame in range(8): await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + name + ".png")
	print("HUD_CAPTURE ", name)
func run() -> void:
	if DisplayServer.get_name() == "headless": quit(2); return
	L.initialize("en")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1100,700); root.content_scale_size = root.size
	var background := ColorRect.new(); background.color = Color("bcaa88"); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.add_child(background)
	VolumeModels.configure_player_colors(["#347dd0", "#d85140"])
	sim = Sim.new(); sim.setup(RulesLoader.load_rules(), "dev", 17, "kestrel", false, {"vision_enabled":false}); sim.money[0] = 100000.0
	var hq: int = sim.entities.values().filter(func(entity): return entity.kind == "building" and entity.team == 0)[0].id
	var barracks: int = sim._spawn(0, "kestrel_barracks", Vector2(24,24), true)
	var squad: int = sim.debug_spawn_squad(0, "kestrel_rifle", Vector2(26,28), true)
	var tank: int = sim._spawn(1, "rivet_tank", Vector2(29,24), true)
	hud = HUD.new(); root.add_child(hud); await process_frame
	hud.is_started = true; hud.show_menu(false)
	await capture("barracks_1100", [barracks])
	await capture("hq_1100", [hq])
	await capture("squad_1100", sim.squad_members(squad))
	await capture("enemy_tank_1100", [tank])
	sim._spawn(0, "kestrel_factory", Vector2(32,25), true); sim._spawn(0, "kestrel_tech", Vector2(36,25), true)
	await capture("expanded_barracks_1100", [barracks])
	L.set_language("zh_CN")
	await capture("squad_zh_1100", sim.squad_members(squad))
	hud.queue_free(); await process_frame; quit()
