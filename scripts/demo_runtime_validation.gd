extends RefCounted

## Opt-in source/export smoke harness. This is not an economy, campaign,
## navigation, transport, audio-device listening or performance benchmark.
## Result screens use a disclosed building-elimination fixture, never a
## direct assignment to simulation.result. Ordinary startup does not run it.
const SETTINGS_PATH := "user://settings.cfg"
const EXTENSION_PATH := "res://assets/native/paper_front_kernels.gdextension"
const CommanderVoice = preload("res://scripts/commander_voice.gd")

static func run(owner_game: Node) -> int:
	if "--verify-demo" not in OS.get_cmdline_user_args(): return 0
	if owner_game.get_meta("demo_validation_running", false): return 0
	owner_game.set_meta("demo_validation_running", true)
	var probe := RuntimeProbe.new()
	return await probe.execute(owner_game)

class RuntimeProbe extends RefCounted:
	var game
	var output := "user://demo_runtime_check.json"
	var checks: Array[Dictionary] = []
	var failures: Array[String] = []
	var details: Dictionary = {}
	var file_backups: Dictionary = {}
	var original_mix: Dictionary = {}
	var original_quality: Dictionary = {}
	var actions: Array[Dictionary] = []
	var finished := false
	var exported := false
	var started_us := 0

	func check(ok: bool, label: String, evidence: Variant = null) -> void:
		var entry: Dictionary = {"label": label, "pass": ok}
		if evidence != null: entry.evidence = evidence
		checks.append(entry)
		if not ok: failures.append(label)
		print("DEMO_CHECK ", "PASS " if ok else "FAIL ", label)

	func frames(count: int = 3) -> void:
		for _frame: int in range(count): await game.get_tree().process_frame

	func button_named(panel: Node, caption: String) -> Button:
		for candidate: Node in panel.find_children("", "Button", true, false):
			if candidate.text == caption: return candidate
		return null

	func press_named(panel: Node, caption: String) -> bool:
		if finished: return false
		var button: Button = button_named(panel, caption)
		if button == null or not button.is_visible_in_tree() or button.disabled: return false
		button.pressed.emit()
		return true

	func preserve_file(path: String) -> void:
		file_backups[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null

	func restore_files() -> bool:
		var restored := true
		for path: String in file_backups:
			if file_backups[path] == null:
				if FileAccess.file_exists(path):
					restored = DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK and restored
			else:
				var file := FileAccess.open(path, FileAccess.WRITE)
				if file == null:
					restored = false
				else:
					file.store_buffer(file_backups[path])
					file.close()
					restored = FileAccess.get_file_as_bytes(path) == file_backups[path] and restored
		return restored

	func file_identity(path: String) -> Dictionary:
		var stored := path
		for suffix: String in [".import", ".remap"]:
			if not FileAccess.file_exists(path + suffix): continue
			var mapping := ConfigFile.new()
			if mapping.load(path + suffix) == OK:
				stored = str(mapping.get_value("remap", "path", path))
				break
		var file := FileAccess.open(stored, FileAccess.READ)
		return {"requested_path": path, "stored_path": stored,
			"sha256": FileAccess.get_sha256(stored) if file != null else "",
			"bytes": file.get_length() if file != null else 0,
			"resource_exists": ResourceLoader.exists(path)}

	func pcm_identity(stream: AudioStreamWAV) -> Dictionary:
		var hashing := HashingContext.new()
		hashing.start(HashingContext.HASH_SHA256)
		hashing.update(stream.data)
		return {"format": stream.format, "mix_rate": stream.mix_rate, "stereo": stream.stereo,
			"seconds": stream.get_length(), "pcm_bytes": stream.data.size(),
			"pcm_sha256": hashing.finish().hex_encode(), "loop_mode": stream.loop_mode,
			"loop_begin": stream.loop_begin, "loop_end": stream.loop_end}

	func pcm_ok(value: Variant, looping: bool = false) -> bool:
		return value is AudioStreamWAV and value.mix_rate == 22050 and value.format == AudioStreamWAV.FORMAT_16_BITS and not value.stereo and value.data.size() > 0 and value.get_length() > 0.1 and (not looping or value.loop_mode == AudioStreamWAV.LOOP_FORWARD and value.loop_end > value.loop_begin)

	func wait_music(scene: String) -> bool:
		var began: int = Time.get_ticks_msec()
		var deadline: int = began + 6000
		var track: String = game.audio.music.track_for_map(str(game.sim.map.mode)) if scene == "battle" else "battle_calm" if scene in ["win", "lose", "draw"] else scene
		while Time.get_ticks_msec() < deadline and not finished:
			if Time.get_ticks_msec() - began >= 3000 and game.audio_scene == scene and game.audio.music.requested_scene == scene and game.audio.music.scene == scene and game.audio.music.requested_track == track and game.audio.music.active_track == track and game.audio.music.player.stream == game.audio.music.tracks.get(track) and game.audio.music.player.playing and game.audio.music.gain >= 0.99:
				if not details.has("music_playback"): details.music_playback = {}
				details.music_playback[scene] = {"requested_by_main": game.audio_scene, "map_id": str(game.sim.map.mode), "asset_track": track, "player_bus": game.audio.music.player.bus, "playing": true, "same_bundled_stream": true, "gain": game.audio.music.gain, "settled_ms": Time.get_ticks_msec() - began}
				return true
			await game.get_tree().process_frame
		return false

	func wait_match(seed_value: int) -> bool:
		var deadline: int = Time.get_ticks_msec() + 20000
		while Time.get_ticks_msec() < deadline and not finished:
			if game.started and not game.loading and game.sim.map.mode == "dev" and int(game.sim.map.seed) == seed_value and game.sim.result.is_empty(): return true
			await game.get_tree().process_frame
		return false

	func current_quality() -> Dictionary:
		return {"render_scale": game.render_scale, "viewport_scale": game.battlefield_viewport.scaling_3d_scale,
			"quality": game.graphics_quality, "dof_near": game.lens.dof_blur_near_enabled,
			"dof_far": game.lens.dof_blur_far_enabled, "dof_override": game.dof_override,
			"shadows": game.key_light.shadow_enabled, "ssao": game.environment.ssao_enabled,
			"msaa_3d": game.battlefield_viewport.msaa_3d, "screen_space_aa": game.battlefield_viewport.screen_space_aa}

	func quality_matches_startup() -> bool:
		var config := ConfigFile.new()
		var status: int = config.load(SETTINGS_PATH)
		var expected_scale: float = float(config.get_value("graphics", "render_scale", 1.0)) if status == OK else 1.0
		var expected_quality: String = str(config.get_value("graphics", "quality", "balanced")) if status == OK else "balanced"
		var expected_shadows: bool = bool(config.get_value("graphics", "shadows", true)) if status == OK else true
		var expected_ssao: bool = bool(config.get_value("graphics", "ambient_occlusion", true)) if status == OK else true
		if expected_quality not in ["native", "balanced", "performance"]: expected_quality = "balanced"
		var arguments := OS.get_cmdline_user_args()
		for index: int in range(arguments.size() - 1):
			if arguments[index] == "--render-scale": expected_scale = arguments[index + 1].to_float()
		expected_scale = clampf(expected_scale, 0.5, 1.0)
		details.preference_baseline = {"settings_existed": file_backups[SETTINGS_PATH] != null,
			"settings_load_error": status, "settings_sha256": FileAccess.get_sha256(SETTINGS_PATH) if file_backups[SETTINGS_PATH] != null else "",
			"clean_defaults": file_backups[SETTINGS_PATH] == null and "--render-scale" not in arguments,
			"declared_defaults": {"render_scale": 1.0, "quality": "balanced"},
			"expected_loaded_scale": expected_scale, "expected_loaded_quality": expected_quality, "expected_shadows": expected_shadows, "expected_ssao": expected_ssao,
			"actual": original_quality, "original_audio_mix": original_mix}
		return is_equal_approx(game.render_scale, expected_scale) and is_equal_approx(game.battlefield_viewport.scaling_3d_scale, expected_scale) and game.graphics_quality == expected_quality and game.key_light.shadow_enabled == expected_shadows and game.environment.ssao_enabled == expected_ssao

	func resource_and_native_checks() -> void:
		var identities: Dictionary = {}
		var readable := true
		for path: String in ["res://scripts/main.gd", "res://scripts/demo_runtime_validation.gd", "res://scripts/paper_audio.gd", "res://scripts/paper_music.gd", "res://scripts/paper_settings.gd", "res://data/rules.json", "res://assets/audio/music/manifest.json", PaperAudio.voice_manifest(game.audio.voice_language), PaperAudio.system_manifest(game.audio.voice_language), PaperAudio.SFX_MANIFEST, PaperMusic.REVISION_MANIFEST, PaperAudio.commander_manifest(game.audio.voice_language)]:
			identities[path] = file_identity(path)
			readable = not str(identities[path].sha256).is_empty() and readable
		details.resources = identities
		check(readable and ResourceLoader.exists("res://scripts/demo_runtime_validation.gd"), "actual main/audio/settings/validation scripts and provenance are readable in this execution", identities)
		var loaded: PackedStringArray = GDExtensionManager.get_loaded_extensions()
		var extension: GDExtension = GDExtensionManager.get_extension(EXTENSION_PATH) if GDExtensionManager.is_extension_loaded(EXTENSION_PATH) else null
		var lifetime: Dictionary = {}
		if game.sim._kernels != null and game.sim._kernels.has_method("verify_container_lifetimes"):
			lifetime = game.sim._kernels.verify_container_lifetimes()
		var native_filename: String = "paper_front_kernels.dll" if OS.has_feature("windows") else "libpaper_front_kernels.so"
		var native_path: String = OS.get_executable_path().get_base_dir().path_join(native_filename) if exported else "res://assets/native/" + native_filename
		details.native = {"loaded_extensions": loaded, "extension_open": extension != null and extension.is_library_open(),
			"kernel_class": ClassDB.class_exists("PaperFrontKernels"), "kernel_instance": game.sim._kernels != null,
			"library": file_identity(native_path), "lifetime_call": lifetime,
			"simulation_enabled": game.sim.native_kernels_enabled, "render_batches_enabled": game.world.native_batches_enabled,
			"world_sync_enabled": game.world.native_world_sync_enabled}
		check(extension != null and extension.is_library_open() and ClassDB.class_exists("PaperFrontKernels") and game.sim._kernels != null and not str(details.native.library.sha256).is_empty() and lifetime.get("after_move") == 1 and lifetime.get("after_self") == 2 and lifetime.get("after_scope") == 1, "native extension library opens and executes its compiled lifetime probe", details.native)
		check(game.sim.native_kernels_enabled and game.world.native_batches_enabled and game.world.native_world_sync_enabled, "normal native simulation and rendering policies remain enabled")
		var routing: Dictionary = {}
		var routes_ok := true
		for name: String in [PaperAudio.MASTER_BUS, PaperAudio.MUSIC_BUS, PaperAudio.BUS_NAME, PaperAudio.VOICE_BUS, CommanderVoice.BUS]:
			var index: int = AudioServer.get_bus_index(name)
			var send: String = str(AudioServer.get_bus_send(index)) if index >= 0 else "missing"
			routing[name] = send
			routes_ok = index >= 0 and send == ("Master" if name == PaperAudio.MASTER_BUS else PaperAudio.MASTER_BUS) and routes_ok
		check(routes_ok and game.audio.music.player.bus == PaperAudio.MUSIC_BUS and game.audio.speech_player.bus == PaperAudio.VOICE_BUS and game.audio.commander.player.bus == CommanderVoice.BUS, "all five audio buses route real music, response and commander players through the master", routing)
		var music_manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/music/manifest.json"))
		var revision_music_manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(PaperMusic.REVISION_MANIFEST))
		var radio_manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(PaperAudio.voice_manifest(game.audio.voice_language)))
		var licenses: Dictionary = {}
		var licenses_ok := true
		for path: String in ["res://assets/audio/licenses/ESPEAK_GPL-3.0.txt", "res://assets/audio/licenses/ESPEAK_DEBIAN_COPYRIGHT.txt", "res://assets/audio/licenses/UNICODE-LICENSE.txt"]:
			licenses[path] = file_identity(path)
			licenses_ok = not str(licenses[path].sha256).is_empty() and licenses_ok
		details.audio_provenance = {"music": music_manifest, "radio": radio_manifest, "music_revision": revision_music_manifest, "license_files": licenses}
		check(music_manifest is Dictionary and music_manifest.get("license", "") == "CC0-1.0" and music_manifest.get("tracks", []).size() == 12, "music provenance identifies twelve project-authored CC0-1.0 tracks")
		check(radio_manifest is Dictionary and not str(radio_manifest.get("license", "")).is_empty() and not radio_manifest.get("clips", []).is_empty(), "spoken class banks identify their actual provider provenance and generation terms", radio_manifest)
		var music_metadata: Dictionary = {}
		if revision_music_manifest is Dictionary:
			for entry: Dictionary in revision_music_manifest.get("tracks", []):
				music_metadata[str(entry.get("id", entry.get("scene", entry.get("name", ""))))] = entry
		var expected_music: Array = PaperMusic.APPLIED_TRACKS.duplicate()
		var manifest_music: Array = music_metadata.keys()
		expected_music.sort()
		manifest_music.sort()
		check(manifest_music == expected_music and revision_music_manifest.get("tracks", []).size() == expected_music.size() and not str(revision_music_manifest.get("license", "")).is_empty(), "all five applied compositions record their actual generation provenance", manifest_music)
		details.music = {}
		var loaded_music: Array = game.audio.music.tracks.keys()
		loaded_music.sort()
		check(loaded_music == expected_music, "exactly the five applied music sources load; historical scene tracks stay inactive", loaded_music)
		for track: String in game.audio.music.tracks:
			var stream: Variant = game.audio.music.tracks.get(track)
			var identity: Dictionary = pcm_identity(stream) if stream is AudioStreamWAV else {"missing": true}
			identity.resource = file_identity(PaperMusic.REVISION_MUSIC_DIR + track + ".wav")
			details.music[track] = identity
			check(pcm_ok(stream, true) and absf(stream.get_length() - float(music_metadata.get(track, {}).get("duration_s", 0.0))) < .001, "bundled looping 16-bit PCM music matches its manifest: " + track, identity)
		var radio_metadata: Dictionary = {}
		var radio_groups: Dictionary = {}
		if radio_manifest is Dictionary:
			for entry: Dictionary in radio_manifest.get("clips", []):
				var group: String = str(entry.get("faction", "")) + "/" + str(entry.get("category", "")) + "/" + str(entry.get("action", ""))
				var key: String = group + "/" + str(int(entry.get("variant", 0)))
				radio_metadata[key] = entry
				radio_groups[group] = int(radio_groups.get(group, 0)) + 1
		var radio_ok: bool = game.audio.radio_bank.size() == radio_metadata.size() and radio_metadata.size() == radio_manifest.get("clips", []).size() and game.audio.speech_clips.size() == 96 and radio_groups.size() == 96
		details.radio = {}
		for faction: String in ["kestrel", "rivet", "iron", "sky"]:
			for category: String in PaperAudio.RADIO_CATEGORIES:
				for action_id: String in PaperAudio.RADIO_ACTIONS:
					var key: String = faction + "/" + category + "/" + action_id
					var clips: Array = game.audio.speech_clips.get(key, [])
					radio_ok = clips.size() == int(radio_groups.get(key, 0)) and (clips.size() == 4 if action_id == "death" else clips.size() in [2, 3]) and radio_ok
					var variants: Array = []
					var distinct_texts: Dictionary = {}
					var distinct_pcm: Dictionary = {}
					for clip: Dictionary in clips:
						var stream: Variant = game.audio.radio_bank.get(str(clip.key))
						var words: String = str(clip.get("text", ""))
						var metadata: Dictionary = radio_metadata.get(str(clip.key), {})
						radio_ok = pcm_ok(stream) and not words.is_empty() and words == str(metadata.get("text", "")) and not clip.get("provenance", {}).is_empty() and clip.get("provenance", {}) == metadata.get("provenance", {}) and str(clip.get("speaker_id", "")) == str(game.audio.speech_profile_speakers.get(faction + "/" + category, "")) and radio_ok
						var identity: Dictionary = pcm_identity(stream) if stream is AudioStreamWAV else {"missing": true}
						identity.merge({"text": words, "language": clip.get("language", "cmn"), "provenance": clip.get("provenance", {}), "variant": clip.get("variant", 0)})
						variants.append(identity)
						distinct_texts[words] = true
						distinct_pcm[str(identity.get("pcm_sha256", ""))] = true
					radio_ok = distinct_texts.size() == clips.size() and distinct_pcm.size() == clips.size() and radio_ok
					details.radio[key] = variants
				game.audio.reset_field()
				var spec := ""
				for candidate: String in game.rules.units:
					var definition: Dictionary = game.rules.units[candidate]
					if definition.get("faction") == faction and game.audio.voice_category(candidate) == category: spec = candidate; break
				radio_ok = not spec.is_empty() and game.audio.play_unit_voice(spec, "select") and game.audio.speech_player.stream == game.audio.radio_bank.get(str(game.audio.last_spoken_clip.get("key", ""))) and game.audio.speech_player.playing and radio_ok
		check(radio_ok, "all faction/class/action PCM banks contain distinct authored words and exact clip captions, and every faction/class plays its selected response")
		game.audio.reset_field()
		var retired_available: Array[String] = []
		for retired_path: String in ["res://assets/audio/radio/manifest.json", "res://assets/audio/voices/manifest.json", "res://assets/audio/radio/rivet_select.wav", "res://assets/audio/voices/iron_ship_frigate_select_01.wav"]:
			if FileAccess.file_exists(retired_path) or ResourceLoader.exists(retired_path): retired_available.append(retired_path)
		details.retired_speech = {"available_paths": retired_available, "runtime_cache_empty": game.audio.speech_cache.is_empty()}
		check(retired_available.is_empty() and game.audio.speech_cache.is_empty(), "retired mechanical acknowledgements are removed and only new class banks load", details.retired_speech)

	func settings_checks() -> void:
		var opened: bool = press_named(game.hud.entry_menu, "设置 · 声音与画面")
		await frames()
		if finished: return
		check(opened and game.hud.settings.visible and game.hud.settings.sliders.size() == PaperAudio.MIX_KEYS.size(), "real entry settings control opens every audio category slider")
		for key: String in PaperAudio.MIX_KEYS:
			var slider: HSlider = game.hud.settings.sliders.get(key)
			if slider == null:
				check(false, "settings slider updates actual mix and persisted preference: " + key)
				continue
			slider.value = 31.0 if not is_equal_approx(slider.value, 31.0) else 47.0
			var config := ConfigFile.new()
			var mix: Dictionary = game.audio.get_mix()
			check(is_equal_approx(float(mix[key]), slider.value / 100.0) and config.load(SETTINGS_PATH) == OK and is_equal_approx(float(config.get_value("audio", key, -1.0)), float(mix[key])), "settings slider updates actual mix and persisted preference: " + key)
		game.hud.settings.mute_button.button_pressed = true
		check(game.audio.muted and AudioServer.is_bus_mute(AudioServer.get_bus_index(PaperAudio.MASTER_BUS)) and game.audio.music.silent, "actual total-mute control immediately silences the master and music policy")
		game.hud.settings.mute_button.button_pressed = false
		check(not game.audio.muted and not AudioServer.is_bus_mute(AudioServer.get_bus_index(PaperAudio.MASTER_BUS)), "actual mute control restores the Demo master")
		game.hud.settings.close_button.pressed.emit()
		await frames()
		check(not game.hud.settings.visible and game.hud.entry_menu.visible and not game.pve_paused, "actual settings completion returns to entry and restores pause")
		check(current_quality() == original_quality, "audio settings do not silently alter render scale, materials policy, depth, shadows or AA")

	func start_fixture(seed_value: int) -> bool:
		if finished: return false
		game.hud.action.emit("start", {"mode": "dev", "seed": seed_value, "faction": "kestrel", "match_options": {}})
		return await wait_match(seed_value)

	func settle_fixture(outcome: String, seed_value: int) -> bool:
		if not await start_fixture(seed_value): return false
		game.pve_paused = true
		game._flush_render_simulation()
		var removed: Array[int] = []
		for id: int in game.sim.entities.keys():
			var entity: Dictionary = game.sim.entities[id]
			if entity.kind != "building": continue
			if outcome == "draw" or (int(entity.team) == 0 if outcome == "lose" else int(entity.team) != 0):
				removed.append(id)
				game.sim._kill_entity(id, true)
		game.sim._check_result()
		game.hud.refresh(game.sim, [], game.camera, game.dev_mode, "", 0.0)
		var music_ok: bool = await wait_music(outcome)
		details["settlement_" + outcome] = {"fixture": "building elimination via real simulation kill/result routines", "seed": seed_value, "removed_buildings": removed, "result": game.sim.result, "music_played": music_ok}
		return game.sim.result == outcome and game.hud.scoreboard.visible and game.hud.scoreboard.displayed_result == outcome and game.hud.scoreboard.displayed_stats.teams.size() == game.sim.factions.size() and not game.hud.end_panel.visible and music_ok

	func menu_flow_checks() -> void:
		check(await start_fixture(73026) and game.sim.map.size == 100 and int(game.sim.map.get("developer_layout", 0)) == 2 and game.sim.counts(0).y == 1, "actual HUD start signal loads the current 100-cell developer fixture with its normal headquarters")
		if finished: return
		check(await wait_music("battle"), "actual match lifecycle plays the bundled battle music")
		if finished: return
		for before: bool in [false, true]:
			game.pve_paused = before
			game.hud.action.emit("settings_open", null)
			var paused_inside: bool = game.pve_paused and game.hud.settings.visible
			game.hud.settings.close_button.pressed.emit()
			check(paused_inside and not game.hud.settings.visible and game.pve_paused == before, "real in-match settings restores the previous pause state: " + str(before))
		check(await settle_fixture("win", 73027), "building-elimination win shows the real scoreboard and plays the calm result score")
		if finished: return
		var new_battle: bool = press_named(game.hud.scoreboard, "新建战局")
		check(new_battle and not game.hud.scoreboard.visible and game.hud.menu.visible and game.setup_session_active, "actual scoreboard new-battle control opens the match setup")
		check(await start_fixture(73027) and not game.hud.scoreboard.visible and await wait_music("battle"), "a new match from settlement setup starts the dev fixture and plays calm battlefield music")
		if finished: return
		check(await settle_fixture("lose", 73028), "building-elimination loss shows the real scoreboard and plays the calm result score")
		if finished: return
		var home: bool = press_named(game.hud.scoreboard, "返回主菜单")
		check(home and game.hud.entry_menu.visible and not game.hud.scoreboard.visible and not game.hud.entry_menu.resume_button.visible and await wait_music("menu"), "actual loss return opens the main menu without a finished-match resume action")
		if finished: return
		check(await settle_fixture("draw", 73029), "building-elimination draw shows the real scoreboard and plays the calm result score")
		if finished: return
		home = press_named(game.hud.scoreboard, "返回主菜单")
		check(home and game.hud.entry_menu.visible and not game.hud.scoreboard.visible and not game.hud.entry_menu.resume_button.visible and await wait_music("menu"), "actual draw return opens the main menu and restores menu PCM")

	func finish() -> int:
		if finished: return 1 if not failures.is_empty() else 0
		finished = true
		game.audio.set_mix(original_mix)
		var exit_code := 0 if failures.is_empty() else 1
		# Set main.quit_pending before restoring files. Main.save_preferences must
		# honor this guard so an already-awaited start/load cannot write later.
		game.quit_game(exit_code)
		check(restore_files(), "user preferences and save bytes are restored exactly (or removed if originally absent)")
		check(game.quit_pending and not game.started and not game.audio.music.player.playing and game.audio.music.player.stream == null, "actual controlled quit guards shutdown and releases music playback")
		exit_code = 0 if failures.is_empty() else 1
		var executable: String = OS.get_executable_path()
		details.data_paths = {"portable_feature": OS.has_feature("portable"), "user_data": OS.get_user_data_dir(),
			"globalized_user": ProjectSettings.globalize_path("user://"), "cache": OS.get_cache_dir(),
			"appdata": OS.get_environment("APPDATA"), "localappdata": OS.get_environment("LOCALAPPDATA"),
			"temp": OS.get_environment("TEMP"), "tmp": OS.get_environment("TMP")}
		var report: Dictionary = {"schema": 1, "scope": "opt-in actual main/PCK resource, audio routing, settings and settlement-menu smoke",
			"opt_in_flag": "--verify-demo", "fixture_only": true,
			"not_validated": ["economic/combat victory through normal play", "campaign completion", "pathfinding/transport regression", "performance on target integrated GPU", "physical audio output/listening quality", "pixel/visual acceptance"],
			"execution": "exported_template" if exported else "source_engine", "godot": Engine.get_version_info(),
			"display": DisplayServer.get_name(), "renderer": RenderingServer.get_current_rendering_method(),
			"debug_build": OS.is_debug_build(), "development_feature": OS.has_feature("development"),
			"executable": {"path": executable, "sha256": FileAccess.get_sha256(executable)},
			"main_script_resource": game.get_script().resource_path, "window_pixels": [game.get_window().size.x, game.get_window().size.y],
			"quality_start": original_quality, "quality_end": current_quality(), "duration_ms": (Time.get_ticks_usec() - started_us) / 1000.0,
			"checks": checks, "failures": failures, "details": details, "hud_actions": actions, "exit_code": exit_code}
		var absolute_output: String = ProjectSettings.globalize_path(output)
		DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
		var file := FileAccess.open(output, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report, "  "))
			file.close()
		else:
			exit_code = 1
			report.exit_code = 1
			report.failures.append("could not write validation report: " + error_string(FileAccess.get_open_error()))
		print("DEMO_RUNTIME ", JSON.stringify(report))
		print("DEMO_RUNTIME_FILE ", absolute_output)
		for failure: String in report.failures: push_error(failure)
		if exit_code != 0: game.get_tree().quit(1)
		return exit_code

	func execute(owner_game: Node) -> int:
		game = owner_game
		started_us = Time.get_ticks_usec()
		exported = not OS.has_feature("editor")
		var arguments := OS.get_cmdline_user_args()
		for index: int in range(arguments.size() - 1):
			if arguments[index] == "--demo-output": output = arguments[index + 1]
		preserve_file(SETTINGS_PATH)
		preserve_file(game.SAVE_PATH)
		original_mix = game.audio.get_mix().duplicate(true)
		original_quality = current_quality()
		if ProjectSettings.globalize_path(output).simplify_path() in [ProjectSettings.globalize_path(SETTINGS_PATH).simplify_path(), ProjectSettings.globalize_path(game.SAVE_PATH).simplify_path()] or output.is_empty():
			output = "user://demo_runtime_check.json"
			check(false, "report output must not overwrite protected user settings/save")
		game.hud.action.connect(func(kind: String, value: Variant): actions.append({"kind": kind, "value": value}))
		game.get_tree().create_timer(70.0).timeout.connect(func():
			if not finished:
				check(false, "runtime harness completed within its watchdog deadline")
				finish())
		await frames()
		if finished: return 1
		var dev_map_entry := false
		var actual_map_ids: Array[String] = []
		for index: int in range(game.hud.map_option.item_count):
			var map_id: String = str(game.hud.map_option.get_item_metadata(index))
			actual_map_ids.append(map_id)
			if map_id == "dev": dev_map_entry = true
		var startup_preferences := ConfigFile.new()
		var expected_debug_enabled: bool = "--debug-panel" in arguments
		if startup_preferences.load(SETTINGS_PATH) == OK:
			expected_debug_enabled = bool(startup_preferences.get_value("debug", "enabled", expected_debug_enabled))
		var expected_map_ids: Array[String] = []
		for entry: Dictionary in BattlefieldCatalog.entries():
			if str(entry.id) == "dev" and not expected_debug_enabled: continue
			expected_map_ids.append(str(entry.id))
		details.shipping_controls = {"debug_enabled_preference": expected_debug_enabled, "debug_available": game.debug_available, "debug_panel_visible": game.debug_panel.visible,
			"debug_button_visible": game.hud.dev_button.visible, "dev_map_entry_present": dev_map_entry, "actual_map_ids": actual_map_ids, "expected_map_ids": expected_map_ids, "policy": "user opt-in in every build; disabled by default"}
		var shipping_controls_ok: bool = game.debug_available == expected_debug_enabled and game.hud.debug_menu_enabled == expected_debug_enabled and dev_map_entry == expected_debug_enabled and not game.debug_panel.visible and (expected_debug_enabled or not game.hud.dev_button.visible) and actual_map_ids == expected_map_ids
		check(game.hud.entry_menu.visible and not game.started and shipping_controls_ok, "initial entry respects the saved optional Debug preference and dev-map visibility", details.shipping_controls)
		check(quality_matches_startup(), "startup respects declared or persisted render scale/quality without silent visual reductions", original_quality)
		# Unmute only this opt-in controlled audition. Original bytes/mix are saved.
		game.audio.set_mix({"master": 0.5, "music": 0.4, "sfx": 0.5, "voice": 0.5, "muted": false})
		resource_and_native_checks()
		check(await wait_music("menu"), "initial real main menu actually plays its bundled menu music")
		if finished: return 1
		await settings_checks()
		if finished: return 1
		await menu_flow_checks()
		if finished: return 1
		return finish()
