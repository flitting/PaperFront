extends SceneTree

var checks := 0
var failures: Array[String] = []
var game
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func key(code: int, control := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code; event.pressed = true; event.ctrl_pressed = control
	game._unhandled_input(event)
func run() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false); game.set_physics_process(false)
	await process_frame
	game.audio.set_mix({"master":1.0,"voice":1.0,"commander":.6,"muted":false})
	var setup = game.hud.match_setup
	setup.players_option.select(0)
	setup.player_color_option.select(3)
	setup.opponent_rows[0].color.select(3)
	setup.opponent_rows[0].faction.select(1)
	var options: Dictionary = setup.options("kestrel")
	check(options.slots[0].color == options.slots[1].color and options.slots[0].faction != options.slots[1].faction, "different factions can use the exact same menu color")
	setup.opponent_rows[0].faction.select(0); setup.opponent_rows[0].color.select(5)
	var same: Dictionary = setup.options("kestrel")
	check(same.slots[0].faction == same.slots[1].faction and same.slots[0].color != same.slots[1].color, "same faction can use different owner colors")
	setup.restore(options)
	check(setup.options("kestrel").slots[0].color == options.slots[0].color and setup.options("kestrel").slots[1].color == options.slots[1].color, "menu color choices round-trip with match preferences")
	var faction_ids: Array[String] = []
	var starts: Array[Vector2] = []
	check(game.start_match("dev", 177, "kestrel", true, {}, faction_ids, starts, options), "actual match starts with selected colors")
	game.sim.ai_enabled = false
	game.hud.show_entry(false); game.hud.show_menu(false)
	check(VolumeModels.player_color(0) == VolumeModels.player_color(1) and VolumeModels.player_color(0) == PaperHUD.PLAYER_COLORS[3], "render palette follows owners and retains duplicate player colors")
	var infantry: int = game.sim._spawn(0, "kestrel_rifle", Vector2(19, 19), true)
	var tank: int = game.sim._spawn(0, "kestrel_tank", Vector2(22, 19), true)
	var enemy: int = game.sim._spawn(1, "rivet_rifle", Vector2(26, 19), true)
	game.selected = [infantry, tank, enemy]
	for number in range(1, 7): key(KEY_0 + number, true)
	check(game.groups.size() == 6 and game.groups[1] == [infantry, tank] and game.groups[6] == [infantry, tank], "Ctrl1–6 creates six controllable groups with overlapping members")
	key(KEY_7, true); key(KEY_0, true)
	check(game.groups.size() == 6, "unsupported number keys cannot create extra groups")
	game.selected = [infantry]; key(KEY_2, true)
	check(game.groups[1] == [infantry,tank] and game.groups[2] == [infantry], "overwriting one group preserves overlapping membership in another")
	game.selected = []; game.hud.group_rows[2].pressed.emit()
	check(game.selected == [infantry], "sidebar group button selects its own distinct real membership")
	game.selected = []; key(KEY_5)
	check(game.selected == [infantry, tank], "number key selects the real overlapping group")
	game.hud.sim = game.sim; game.hud.refresh_groups(game.groups)
	check(game.hud.group_rows[5].tooltip_text.contains(game.sim.data_for("kestrel_rifle").name) and game.hud.group_rows[5].tooltip_text.contains(game.sim.data_for("kestrel_tank").name) and str(game.hud.group_rows[5].get_meta("composition")).contains("×1"), "sidebar shows each type portrait and live quantities")
	game.sim._kill_entity(infantry, true)
	game.prune_control_groups(); game.hud.refresh_groups(game.groups)
	check(game.groups[1] == [tank] and game.groups[6] == [tank] and not game.hud.group_rows[1].tooltip_text.contains(game.sim.data_for("kestrel_rifle").name), "real unit death updates every group and sidebar")
	game.sim.entities[tank].team = 1; game.prune_control_groups()
	check(not game.groups.has(1) and not game.groups.has(6), "loss of control deletes empty groups immediately")
	var identity: String = game.hud.entity_identity(enemy)
	check(identity.contains("玩家 2 · 敌对") and identity.contains("重锤军团") and identity.contains(game.sim.data_for("rivet_rifle").name), "visible enemy identity separates prominent owner and relation from faction")
	game.sim.vision_enabled = true
	for e: Dictionary in game.sim.entities.values():
		if int(e.team) == 0: e.pos = Vector2(3, 3)
	game.sim.entities[enemy].pos = Vector2(46, 46)
	game.sim.TeamVision.refresh(game.sim, true)
	check(not game.sim.entity_visible_to(0, enemy) and game.hud.entity_identity(enemy).is_empty(), "hidden enemy tooltip reveals no owner, faction, name or live state")
	game.sim.vision_enabled = false
	var base_ids: Array[int] = []
	for e: Dictionary in game.sim.entities.values():
		if e.kind == "building" and game.sim.data_for(e.spec).role == "hq": base_ids.append(e.id)
	var outpost: int = game.sim._spawn(0, "kestrel_outpost", Vector2(13, 13), true)
	var markers: Array = game.hud.mini.marker_records(0)
	check(markers.any(func(marker):return marker.id == base_ids[0] and marker.role == "hq") and markers.any(func(marker):return marker.id == outpost and marker.role == "outpost"), "minimap records distinguish live main bases from outposts")
	var voice = game.audio.commander
	voice.enabled = true; voice.reset(game.sim)
	game.sim.events.clear()
	var victim: int = game.sim._spawn(0, "kestrel_tank", Vector2(22, 22), true)
	game.sim._add_damage(victim, 10); game.sim._apply_damage(); game.sim._damage.clear()
	for event: Dictionary in game.sim.events: voice.observe_event(event, game.sim)
	key(KEY_SPACE)
	check(game.focus == Vector2(22,22), "Space uses latest actual visible damage hotspot")
	game.sim.time += 46; key(KEY_SPACE)
	var own_hq: Dictionary = {}
	for e: Dictionary in game.sim.entities.values():
		if int(e.team) == 0 and game.sim.data_for(e.spec).get("role", "") == "hq": own_hq = e; break
	check(game.focus == own_hq.pos, "expired hotspots fall back to main base")
	voice.set_process(false)
	voice._process(.1)
	check(voice.player.playing and voice.player.stream is AudioStreamWAV and voice.player.stream.data.size() > 10000 and voice.active_action == "vehicle_attacked", "actual damage starts a recorded commander report, not a caption placeholder")
	check(game.audio.get_mix().commander == .6 and voice.player.volume_db <= -15.0, "commander default is restrained and independently configurable")
	game.audio.set_mix({"commander":0.0})
	check(not voice.player.playing and game.audio.get_mix().voice == 1.0 and AudioServer.is_bus_mute(AudioServer.get_bus_index("Paper Commander")), "commander slider mutes only commander playback")
	game.audio.set_mix({"commander":.6})
	voice.reset(game.sim); voice.enabled = true
	for index in 40: voice.request("unit_lost", {"id":index})
	check(voice.pending.size() == 1 and voice.pending.unit_lost.count == 40, "mass deaths merge into one pending report")
	voice.request("base_attacked"); voice._process(.1)
	check(voice.active_action == "base_attacked" and voice.pending.has("unit_lost"), "urgent base attack wins over mass death reporting")
	voice.player.stop(); voice.pending.clear()
	check(not voice.request("base_attacked"), "same class cooldown suppresses rapid repeat base reports")
	voice.report_clock += 13
	check(voice.request("base_attacked"), "report becomes eligible again after configured cooldown")
	game.quit_pending = true; game.audio.stop_all(); game.queue_free()
	await process_frame
	await create_timer(.25).timeout
	print("RTS_COMMAND_INFORMATION ", JSON.stringify({"checks":checks,"failures":failures}))
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
