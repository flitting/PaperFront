extends SceneTree

# Main-scene integration: every score observation comes through the production
# game._process event loop, from genuine simulation fire/impact/death events.
# No score, active-track, or combat-source state is assigned by this fixture.
const STEP := .05
const MAX_COMBAT_STEPS := 360
const REPORT := "res://artifacts/audio_revision_20261007/adaptive_music_game_validation.json"

var checks := 0
var failures: Array[String] = []
var phases: Array[Dictionary] = []
var game: Node3D
var before_buses := 0
var settings_path := ""
var original_settings := PackedByteArray()
var settings_existed := false

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func tick(delta: float = STEP) -> Dictionary:
	game.sim.step(delta)
	var observed := {"fire": 0, "impact": 0, "death": 0}
	for event: Dictionary in game.sim.events:
		var kind: String = str(event.get("kind", ""))
		if observed.has(kind): observed[kind] = int(observed[kind]) + 1
	# Both automatic entry points are disabled; exercise the real main route
	# exactly once, then advance its regular audio children by the same time.
	game._process(delta)
	game.audio._process(delta)
	game.audio.music._process(delta)
	return observed

func run_for(seconds: float) -> void:
	for index in range(ceili(seconds / STEP)):
		tick()
		if index % 4 == 0: await process_frame

func prepare_match(scripted: bool) -> bool:
	var started: bool = game.start_match("dev", 91804 if scripted else 91803, "kestrel", true)
	check(started, ("script" if scripted else "native") + ": real main scene starts its match")
	if not started: return false
	game.sim.native_unit_dispatch_enabled = not scripted
	check(scripted or (game.sim.native_kernels_enabled and game.sim._kernels != null), "native scenario uses the available dispatch extension")
	game.sim.synchronous_path_tests = true
	game.sim.vision_enabled = false
	game.sim.ai_enabled = false
	game.hud.show_menu(false)
	game.hud.show_entry(false)
	game.pve_paused = false
	game.audio.set_mix({"master": .8, "music": .3, "sfx": 0.0, "voice": 0.0, "muted": false})
	await process_frame
	await run_for(3.0)
	check(game.audio.music.requested_scene == "battle" and game.audio.music.active_track == "battle_calm", "main scene selects quiet dev battle music")
	return true

func target_at(position: Vector2) -> int:
	var id: int = game.sim.debug_spawn(1, "rivet_harvester", position, true)
	check(id > 0, "unarmed opposing target is spawned through the real simulation")
	if id > 0:
		game.sim.entities[id].hp = 100000.0
		game.sim.issue([id], "hold", position)
	return id

func squad(spec: String, target: int, idle: bool, count: int = 3) -> Array[int]:
	var ids: Array[int] = []
	var goal: Vector2 = game.sim.entities[target].pos
	for index in range(count):
		var pos := Vector2(20.0, 18.0 + float(index) * .8)
		var id: int = game.sim.debug_spawn(0, spec, pos, true)
		check(id > 0, "real combatant spawns: " + spec)
		if id <= 0: continue
		ids.append(id)
		if count > 6:
			pos = Vector2(17.0 + float(index % 4) * 1.6, 17.0 + float(index / 4) * 1.6)
			game.sim.entities[id].pos = pos
		var heading: float = rad_to_deg((goal - pos).angle())
		game.sim.entities[id].alpha = heading
		game.sim.entities[id].turret_alpha = heading
		if not idle: game.sim.issue([id], "attack", goal, target)
	return ids

func enter_through_real_fire(label: String, ids: Array[int], expected_track: String = "battle_engaged") -> Dictionary:
	var music: PaperMusic = game.audio.music
	var ledger := {"label": label, "native_dispatch_enabled": game.sim.native_kernels_enabled and game.sim.native_unit_dispatch_enabled, "steps": 0, "real_fire_events": 0, "real_impact_events": 0, "entered_at_sim_s": -1.0, "reload_frames": 0}
	var start: float = game.sim.time
	for index in range(MAX_COMBAT_STEPS):
		var events: Dictionary = tick()
		ledger.steps = index + 1
		ledger.real_fire_events += int(events.fire)
		ledger.real_impact_events += int(events.impact)
		if music.combat_active and float(ledger.entered_at_sim_s) < 0.0:
			ledger.entered_at_sim_s = game.sim.time - start
		# A reload gap contains no artificial events or direct score injection.
		if music.active_track == expected_track and music.player.playing and int(events.fire) == 0:
			var reloading := true
			for id in ids:
				if not game.sim.entities.has(id) or float(game.sim.entities[id].cooldown) <= 0.0: reloading = false
			if reloading:
				ledger.reload_frames += 1
				check(music.combat_active and music.requested_track == expected_track, label + ": real reload gap retains the intense cue")
		if index % 4 == 0: await process_frame
		if int(ledger.real_fire_events) >= 18 and int(ledger.reload_frames) >= 3 and music.player.stream == music.tracks.get(expected_track) and music.player.playing:
			break
	check(int(ledger.real_fire_events) >= 18 and int(ledger.real_impact_events) >= 6, label + ": multiple real volleys and impacts passed through main dispatch")
	check(float(ledger.entered_at_sim_s) >= 0.0 and float(ledger.entered_at_sim_s) <= STEP * 2.0, label + ": isolated actual combat immediately enters the ordinary stage")
	check(music.combat_active and music.active_track == expected_track and music.player.stream == music.tracks.get(expected_track) and music.player.playing, label + ": actual combat-layer WAV reaches the single music player")
	check(game.sim.events.is_empty() and not music.combat_sources.is_empty(), label + ": production main loop drains events and records their real shooter IDs")
	phases.append(ledger)
	return ledger

func assert_silent_cut(label: String) -> void:
	var music: PaperMusic = game.audio.music
	var outgoing: AudioStream = music.player.stream
	# Flying projectiles can still hit after the firing command stops. Wait for
	# the production interaction timer, not a fixed delay from issuing move.
	var stopped_at: float = game.sim.time
	for index in range(200):
		if not music.combat_active: break
		tick()
		if index % 4 == 0: await process_frame
	check(game.sim.time - stopped_at > 4.9, label + ": thirdtier orordinarybed retainsatleastfiveactualquietseconds")
	var starting_gain: float = music.gain
	check(not music.combat_active and music.player.playing and music.gain > 0.0, label + ": ceasefire retains the cue for gradual fade")
	await run_for(1.0)
	check(music.player.playing and music.player.stream == outgoing and music.gain > starting_gain * .15 and music.gain < starting_gain * .85, label + ": outgoing cue fades halfway through from its current gain")
	await run_for(1.1)
	check(music.active_track == "battle_calm" and music.gain < .1, label + ": combat cue fades to zero at about two seconds")
	await run_for(2.1)
	check(music.player.stream == music.tracks.get("battle_calm") and music.player.playing and music.gain > .99, label + ": calm theme fades back in")

func exercise(scripted: bool) -> void:
	var mode: String = "script" if scripted else "native"
	if not await prepare_match(scripted): return
	var first: int = target_at(Vector2(24, 20))
	if first <= 0: return
	var tanks: Array[int] = squad("kestrel_tank", first, false)
	await enter_through_real_fire(mode + " tank", tanks)
	check(game.audio.music.combat_level == 1, mode + ": ordinary fight cannot enter the dense tier")
	check(game.sim._can_move_fire(game.sim.data_for("kestrel_tank")), mode + ": fixture includes a vehicle capable of combat movement")
	game.sim.issue(tanks, "move", Vector2(7, 35))
	game._process(0.0)
	check(game.sim.entities.has(first) and float(game.sim.entities[first].hp) > 0.0, mode + ": ceasefire target remains alive")
	check((game.sim.entities[tanks[0]].pos as Vector2).distance_to(game.sim.entities[first].pos) < float(game.sim.rules.weapons.kestrel_tank.range), mode + ": old target remains in range when ordinary move suppresses firing")
	check(not game.audio.music.recent_shots.is_empty(), mode + ": ordinarymovement preserves10secondactualfirehistory untilquietexit")
	await assert_silent_cut(mode + " normal move")
	for id in tanks: game.sim._kill_entity(id, false)
	game.sim._kill_entity(first, false)
	game._process(0.0)
	game.audio.reset_field()
	await process_frame
	var dense_target: int = target_at(Vector2(24, 20))
	var dense_army: Array[int] = squad("kestrel_tank", dense_target, false, 6)
	await enter_through_real_fire(mode + " dense tank battle", dense_army, "battle_intense")
	check(game.audio.music.combat_level == 2 and game.audio.music.dense_sources == 6, mode + ":sixactual friendlyshooters reachthe intense threshold")
	game.sim.issue(dense_army, "move", Vector2(12, 27))
	game._process(0.0)
	await assert_silent_cut(mode + " dense ceasefire")
	for id in dense_army: game.sim._kill_entity(id, false)
	game.sim._kill_entity(dense_target, false)
	game._process(0.0);game.audio.reset_field()
	await process_frame
	var old_target: int = target_at(Vector2(24, 20))
	var replacement: int = target_at(Vector2(38, 37))
	if old_target <= 0 or replacement <= 0: return
	var infantry: Array[int] = squad("kestrel_rifle", old_target, true)
	await enter_through_real_fire(mode + " idle infantry", infantry)
	var ready_to_retarget := false
	for index in range(20):
		ready_to_retarget = true
		for id in infantry:
			if float(game.sim.entities[id].cooldown) <= .20: ready_to_retarget = false
		if ready_to_retarget: break
		tick()
	check(ready_to_retarget, mode + ": foot squad reaches an actual reload gap before target replacement")
	for id in infantry:
		check(game.sim.entities[id].commands.is_empty() and int(game.sim.entities[id].auto_target) == -1 and int(game.sim.entities[id].turret_target) == -1, mode + ": idle non-turret acquisition has no stored auto/turret target")
	game.sim.entities[replacement].pos = game.sim.entities[old_target].pos
	game.sim._kill_entity(old_target, true)
	var retarget_events: Dictionary = tick()
	check(int(retarget_events.fire) == 0, mode + ": target replacement happens before the next real volley")
	check(game.audio.music.combat_active and game.audio.music.player.playing and game.audio.music.active_track == "battle_engaged", mode + ": idle foot retargeting through main dispatch preserves intensity during reload")
	game.sim._kill_entity(replacement, true)
	game._process(0.0)
	check(game.sim.result.is_empty(), mode + ": last local engagement ends without ending the match")
	await assert_silent_cut(mode + " last target destroyed")
	for id in infantry: game.sim._kill_entity(id, false)
	game._process(0.0)
	await process_frame

func run() -> void:
	if OS.get_environment("XDG_DATA_HOME").is_empty():
		push_error("adaptive_music_game_tests requires isolated XDG_DATA_HOME")
		quit(2)
		return
	settings_path = ProjectSettings.globalize_path("user://settings.cfg")
	settings_existed = FileAccess.file_exists(settings_path)
	if settings_existed: original_settings = FileAccess.get_file_as_bytes(settings_path)
	before_buses = AudioServer.bus_count
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.audio.set_process(false)
	game.audio.music.set_process(false)
	await process_frame
	check(ClassDB.class_exists("PaperFrontKernels"), "native dispatch extension is present for the native scenario")
	for scripted in [false, true]: await exercise(scripted)
	game.quit_pending = true
	game.audio.stop_all()
	await create_timer(.30).timeout
	game.queue_free()
	await process_frame
	game = null
	await process_frame
	check(AudioServer.bus_count == before_buses, "main scene teardown releases all owned audio buses")
	check(FileAccess.file_exists(settings_path) == settings_existed and (not settings_existed or FileAccess.get_file_as_bytes(settings_path) == original_settings), "fixture does not change isolated preferences")
	call_deferred("finish")

func finish() -> void:
	# Let async locals return and the audio mixer release their resources before
	# engine shutdown; headless time acceleration is not an audio-thread drain.
	await process_frame
	await create_timer(.30).timeout
	var report := {"checks": checks, "failures": failures, "phases": phases,
		"scope": "actual main.tscn, production event dispatch, real simulation shots; native and GDScript unit modes; player-state verification, no human listening claim"}
	var path: String = ProjectSettings.globalize_path(REPORT)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t") + "\n")
	print("ADAPTIVE_MUSIC_GAME ", JSON.stringify(report))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
