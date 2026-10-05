extends SceneTree

var failures: Array[String] = []
var checks: int = 0
var caption_text: String = ""

func _initialize() -> void:
	call_deferred("run")

func require(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func run() -> void:
	var rules: Dictionary = RulesLoader.load_rules()
	require(not rules.is_empty(), "Expanded rules must load")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PaperAudio.VOICE_MANIFEST))
	var clips: Dictionary = {}
	for clip in manifest.clips:
		clips[str(clip.faction) + "/" + str(clip.action)] = clip
		require(ResourceLoader.exists(str(clip.path)), "Missing synthesized WAV " + str(clip.path))
		var stream: AudioStreamWAV = load(str(clip.path))
		require(stream != null and stream.mix_rate == 22050 and stream.get_length() > 0.25, "Invalid PCM speech " + str(clip.path))
		require(clip.provenance.type == "offline_formant_synthesized_speech" and not clip.provenance.human_recording and not clip.provenance.online_service, "Speech provenance must identify native offline synthesis")
	for spec in rules.units:
		# All four factions use short semantic Mandarin acknowledgements.
		# The unit name remains in the caption; its spoken words come from the
		# same faction/action manifest that identifies the offline PCM asset.
		for action_id in rules.units[spec].voices:
			var key: String = str(rules.units[spec].faction) + "/" + str(action_id)
			require(clips.has(key) and not str(clips[key].text).is_empty(), "Unit action has no semantic Mandarin dialogue: " + key)
	var sound := PaperAudio.new()
	root.add_child(sound)
	await process_frame
	sound.configure_units(rules)
	sound.unit_caption.connect(func(text: String, _duration: float): caption_text = text)
	require(sound.play_unit_voice("kestrel_tank", "select"), "A selected unit must speak its own dialogue")
	require(sound.speech_player.playing and sound.speech_player.bus == PaperAudio.VOICE_BUS, "Speech requires a separate audio player and bus")
	require(caption_text.ends_with(str(clips["kestrel/select"].text)), "The audible dialogue must have a matching subtitle")
	var active_stream: AudioStream = sound.speech_player.stream
	require(not sound.play_unit_voice("rivet_tank", "move") and sound.speech_player.stream == active_stream, "Rapid orders must not overlap or replace speech during cooldown")
	require(not sound.play_unit_voice("kestrel_fighter", "return") and not sound.pending_speech.is_empty(), "A background return response must wait for the current spoken order")
	sound.muted = true
	require(sound.pending_speech.is_empty(), "Mute must discard pending speech")
	require(not sound.speech_player.playing and caption_text.is_empty(), "Mute must stop speech and clear current subtitle")
	sound.muted = false
	for pair in [["rivet_fighter", "fire_air"], ["kestrel_attacker", "bomb_release"], ["rivet_bomber", "bomb_release"], ["kestrel_artillery", "fire_artillery"]]:
		require(sound._event_family({"kind":"fire", "weapon":pair[0]}) == pair[1], "Wrong aviation weapon sound family")
	for kind in ["fire_air", "bomb_release", "rearm", "aircraft_loop"]:
		require(sound.bank.has(kind), "Missing original aviation effect " + kind)
	sound.stop_all()
	sound.queue_free()
	await process_frame
	var game: Node3D = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.set_physics_process(false)
	game.audio.muted = true
	game.start_match("dev", 73026, "kestrel", true)
	game.hud.show_menu(false)
	require(game.hud.faction_option.get_item_metadata(0) == "kestrel", "The menu must offer the canon faction first")
	require(game.hud.faction_option.get_item_text(0).contains("正典军团") and game.hud.faction_option.get_item_text(1).contains("重锤军团"), "The menu must use the latest faction names")
	require(PaperHUD.PLAYER_COLORS[0] == Color("e7ad42") and PaperHUD.PLAYER_COLORS[1] == Color("41c7c6"), "HUD player identity colors must match models")
	game.sim.debug_spawn(0, "kestrel_command", Vector2(32.5, 35.5))
	var airfield: int = game.sim.debug_spawn(0, "kestrel_airfield", Vector2(20.5, 35.5))
	game.selected = [airfield]
	game.hud.refresh(game.sim, game.selected, game.camera, true, "", 0.0)
	game.hud.select_catalog("air")
	require(game.hud.production_building() == airfield and game.hud.production_panel.visible, "Selecting an airfield must expose aircraft production")
	require(game.hud.entry_widgets.has("kestrel_fighter") and game.hud.entry_widgets.has("kestrel_attacker"), "Aircraft production cards are missing")
	var tip: String = game.hud.entry_widgets.kestrel_fighter.button.tooltip_text
	require(tip.contains("攻击空中") and tip.contains("弹药") and tip.contains("科技前置"), "Aircraft cards require domains, ammunition, and technology")
	require(tip.contains(str(rules.units.kestrel_fighter.formal_name)) and tip.contains(str(rules.units.kestrel_fighter.description)), "Cards require canonical model name and description")
	var position := Vector2(16.5, 31.5)
	var fighter: int = game.sim.debug_spawn(0, "kestrel_fighter", position)
	game.sim.entities[fighter].flight_height = 7.0
	game.focus = position
	game.update_camera()
	var sky_center: Vector3 = game.entity_visual_center(game.sim.entities[fighter])
	var sky_screen: Vector2 = game.project_world_to_screen(sky_center)
	require(game.pick_entity(sky_screen) == fighter, "Aircraft must be selectable at their visible airborne body")
	game.box_select(Rect2(sky_screen - Vector2(12,12), Vector2(24,24)), false)
	require(fighter in game.selected, "Box selection must use aircraft airborne projection")
	var ground_screen: Vector2 = game.project_world_to_screen(Vector3(position.x, MapData.height_at(game.sim.map, position) + 0.1, position.y))
	require(game.pick_entity(ground_screen) != fighter, "An aircraft's ground shadow must not steal ground clicks")
	game.sim.entities[fighter].flight_state = "returning"
	game.sim.entities[fighter].ammo = 2
	game.hud.refresh(game.sim, [fighter], game.camera, true, "", 0.0)
	require(game.hud.info_label.text.contains("弹药 2/") and game.hud.info_label.text.contains("返航"), "Selected aircraft need ammunition and flight status")
	require(game.hud.return_button.visible, "Selected aircraft need a return command")
	game.hud.show_voice("校正炮：已收到坐标。开始修正。", 2.0)
	require(game.hud.voice_label.visible and game.hud.voice_label.text.contains("开始修正"), "Spoken orders need visible subtitles")
	game.hud._process(3.0)
	require(not game.hud.voice_label.visible, "Finished subtitles must expire")
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if "--capture-dir" in args:
		var index: int = args.find("--capture-dir")
		if index + 1 < args.size(): await capture_ui(game, airfield, fighter, args[index + 1])
	game.audio.stop_all()
	game.queue_free()
	await process_frame
	# Release coroutine-local PCM references before the engine shuts down.
	call_deferred("finish")

func finish() -> void:
	await process_frame
	await create_timer(.2).timeout
	if failures.is_empty():
		print("faction_ui_audio_tests: ", checks, " checks PASS; Chinese speech coverage, PCM/provenance, separate voice pool, subtitles, aviation UI and sky selection")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)


# Optional visual evidence uses the same real game and verified entities as the
# assertions above. Default headless checks do not wait for rendered frames.
func capture_ui(game: Node3D, airfield: int, fighter: int, destination: String) -> void:
	if DisplayServer.get_name() == "headless":
		failures.append("UI screenshots require an actual display")
		return
	DirAccess.make_dir_recursive_absolute(destination)
	root.size = Vector2i(1600, 900)
	game.get_window().size = Vector2i(1600, 900)
	game.distance = 27.0
	game.camera_pitch = 30.0
	game.yaw = 0.3
	game.focus = Vector2(19.0, 34.0)
	for entry in [["kestrel_factory", Vector2(13.5, 38.5)], ["kestrel_repair", Vector2(27.5, 35.5)], ["kestrel_command", Vector2(27.5, 28.5)], ["kestrel_power", Vector2(13.5, 25.5)], ["kestrel_aa", Vector2(26.5, 31.5)], ["kestrel_tank", Vector2(13.5, 33.5)]]:
		game.sim.debug_spawn(0, entry[0], entry[1])
	game.update_camera()
	for scenario in ["airfield_production", "aircraft_return_subtitle"]:
		game.selected = [airfield] if scenario == "airfield_production" else [fighter]
		game.hud.cache_key = ""
		game.world.sync(0.0, game.selected, {})
		game.hud.refresh(game.sim, game.selected, game.camera, false, "正典军团 · 采集辉晶，建设工业，守护航空基地。", 0.0)
		if scenario == "aircraft_return_subtitle": game.hud.show_voice(str(game.sim.data_for(game.sim.entities[fighter].spec).name) + "：" + str(game.sim.data_for(game.sim.entities[fighter].spec).voices["return"][0]), 5.0)
		for frame in range(8):
			await process_frame
			game.resize_battlefield()
			game.world.sync(0.0, game.selected, {})
			await RenderingServer.frame_post_draw
		var output: String = destination.path_join(scenario + ".png")
		var result: Error = root.get_texture().get_image().save_png(output)
		require(result == OK, "Failed to save UI visual evidence " + output)
		print("FACTION_UI_CAPTURE ", output)
