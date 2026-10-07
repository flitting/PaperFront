extends RefCounted

## Explicit exported-application check. Ordinary play never runs this fixture.
## Settings, save and the diagnostic terrain entry are restored before exit.
const TerrainCache = preload("res://scripts/terrain_resource_cache.gd")
const SETTINGS_PATH := "user://settings.cfg"

static func run(game: Node) -> int:
	if "--verify-portable" not in OS.get_cmdline_user_args(): return 0
	if game.get_meta("portable_validation_running", false): return 0
	game.set_meta("portable_validation_running", true)
	var probe := RuntimeProbe.new()
	return await probe.execute(game)

class RuntimeProbe extends RefCounted:
	var game
	var checks: Array[Dictionary] = []
	var failures: Array[String] = []
	var backups: Dictionary = {}
	var details: Dictionary = {}
	var finished := false
	var started_us := 0
	var watchdog: SceneTreeTimer
	var watchdog_callback: Callable

	func check(ok: bool, label: String, evidence: Variant = null) -> void:
		var entry: Dictionary = {"label": label, "pass": ok}
		if evidence != null: entry.evidence = evidence
		checks.append(entry)
		if not ok: failures.append(label)

	func normalized(path: String) -> String:
		return path.replace("\\", "/").simplify_path().trim_suffix("/").to_lower()

	func preserve(path: String) -> void:
		backups[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null

	func restore() -> bool:
		var ok := true
		for path: String in backups:
			if backups[path] == null:
				if FileAccess.file_exists(path): ok = DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK and ok
			else:
				var file := FileAccess.open(path, FileAccess.WRITE)
				if file == null: ok = false
				else:
					file.store_buffer(backups[path])
					file.close()
					ok = FileAccess.get_file_as_bytes(path) == backups[path] and ok
		return ok

	func write_text(path: String, value: String) -> bool:
		if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir()) != OK: return false
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null: return false
		file.store_string(value)
		file.close()
		return FileAccess.get_file_as_string(path) == value

	func frames(count: int = 3) -> void:
		for _frame: int in range(count): await game.get_tree().process_frame

	func key(code: Key) -> void:
		for pressed: bool in [true, false]:
			var event := InputEventKey.new()
			event.keycode = code
			event.pressed = pressed
			game.get_tree().root.push_input(event, true)
		await frames()

	func environment_checks() -> void:
		var runtime_dir: String = OS.get_executable_path().get_base_dir()
		var root_dir: String = runtime_dir.get_base_dir()
		var expected: String = root_dir.path_join("user_data")
		details.paths = {"executable": OS.get_executable_path(), "portable_feature": OS.has_feature("portable"),
			"user_data": OS.get_user_data_dir(), "globalized_user": ProjectSettings.globalize_path("user://"),
			"engine_cache": OS.get_cache_dir(), "terrain_cache": ProjectSettings.globalize_path(TerrainCache.DIRECTORY),
			"appdata": OS.get_environment("APPDATA"), "localappdata": OS.get_environment("LOCALAPPDATA"),
			"temp": OS.get_environment("TEMP"), "tmp": OS.get_environment("TMP"),
			"portable_root": OS.get_environment("PAPER_FRONT_PORTABLE_ROOT"), "expected_user_data": expected,
			"working_directory": DirAccess.open(".").get_current_dir()}
		check(OS.has_feature("portable") and OS.has_feature("windows") and not OS.has_feature("editor"), "actual Windows portable export is running", details.paths)
		check(normalized(OS.get_user_data_dir()) == normalized(expected) and normalized(ProjectSettings.globalize_path("user://")) == normalized(expected), "user:// resolves to the extracted package user_data directory")
		check(normalized(OS.get_environment("APPDATA")) == normalized(root_dir) and normalized(OS.get_environment("PAPER_FRONT_PORTABLE_ROOT")) == normalized(root_dir), "launcher confines roaming data to the extracted package")
		check(normalized(OS.get_environment("LOCALAPPDATA")) == normalized(expected.path_join("cache")) and normalized(OS.get_cache_dir()).begins_with(normalized(expected) + "/"), "Windows local cache stays under user_data")
		check(normalized(OS.get_environment("TEMP")) == normalized(expected.path_join("tmp")) and normalized(OS.get_environment("TMP")) == normalized(expected.path_join("tmp")), "temporary file environment stays under user_data")
		check(normalized(ProjectSettings.globalize_path(TerrainCache.DIRECTORY)).begins_with(normalized(expected) + "/"), "derived terrain cache stays under user_data")

	func license_checks() -> void:
		var license_text: String = Engine.get_license_text()
		var copyright_info: Array = Engine.get_copyright_info()
		var license_info: Dictionary = Engine.get_license_info()
		var valid := not license_text.is_empty() and not copyright_info.is_empty() and not license_info.is_empty()
		valid = write_text("user://licenses/GODOT_LICENSE.txt", license_text) and valid
		valid = write_text("user://licenses/GODOT_COPYRIGHT.json", JSON.stringify(copyright_info, "  ")) and valid
		valid = write_text("user://licenses/GODOT_THIRD_PARTY_LICENSES.json", JSON.stringify(license_info, "  ")) and valid
		details.engine_licenses = {"directory": ProjectSettings.globalize_path("user://licenses"), "copyright_components": copyright_info.size(), "license_count": license_info.size(), "license_sha256": FileAccess.get_sha256("user://licenses/GODOT_LICENSE.txt")}
		check(valid, "running Windows engine exports its license and bundled third party notices", details.engine_licenses)

	func persistence_checks() -> void:
		preserve(SETTINGS_PATH)
		preserve(game.SAVE_PATH)
		game.audio.set_mix({"master": 0.37})
		game.save_preferences()
		var settings := ConfigFile.new()
		check(settings.load(SETTINGS_PATH) == OK and is_equal_approx(float(settings.get_value("audio", "master", -1.0)), 0.37), "actual settings save writes and reloads inside user_data", ProjectSettings.globalize_path(SETTINGS_PATH))
		if not game.start_match("dev", 73026, "kestrel", true):
			check(false, "portable save fixture starts")
			return
		game.hud.show_entry(false)
		game.hud.show_menu(false)
		game.pve_paused = true
		await frames()
		game._flush_render_simulation()
		var original_money: float = float(game.sim.money[0])
		await key(KEY_F5)
		check(FileAccess.file_exists(game.SAVE_PATH) and FileAccess.get_file_as_bytes(game.SAVE_PATH).size() > 0, "actual F5 input saves the battlefield under user_data", ProjectSettings.globalize_path(game.SAVE_PATH))
		var saved_digest: String = FileAccess.get_sha256(game.SAVE_PATH)
		game.sim.money[0] = original_money + 123.0
		await key(KEY_F9)
		var deadline: int = Time.get_ticks_msec() + 25000
		while game.loading and Time.get_ticks_msec() < deadline and not finished: await game.get_tree().process_frame
		if finished: return
		game.pve_paused = true
		game._flush_render_simulation()
		check(not game.loading and game.started and is_equal_approx(float(game.sim.money[0]), original_money) and FileAccess.get_sha256(game.SAVE_PATH) == saved_digest, "actual F9 input restores the saved battlefield after a controlled state change", {"saved_money": original_money, "loaded_money": game.sim.money[0], "save_sha256": saved_digest})
		var cache_key: String = "paper-front-portable-validation".sha256_text()
		var cache_path: String = TerrainCache.DIRECTORY.path_join(cache_key + ".res")
		preserve(cache_path)
		var store_error: int = TerrainCache.store_entry(cache_key, {"nodes": [], "stats": {"portable_probe": true}}, TerrainCache.DIRECTORY, 0)
		var loaded: Dictionary = TerrainCache.load_entry(cache_key)
		check(store_error == OK and loaded.get("cache_source", "") == "user" and bool(loaded.get("stats", {}).get("portable_probe", false)), "production terrain cache writes and reloads a derived entry inside user_data", {"path": ProjectSettings.globalize_path(cache_path), "store_error": store_error})

	func finish() -> int:
		if finished: return 1 if not failures.is_empty() else 0
		finished = true
		if watchdog != null and watchdog.timeout.is_connected(watchdog_callback):
			watchdog.timeout.disconnect(watchdog_callback)
		watchdog = null
		watchdog_callback = Callable()
		game.quit_game(0 if failures.is_empty() else 1)
		check(restore(), "original settings, save and diagnostic terrain cache bytes are restored")
		var exit_code: int = 0 if failures.is_empty() else 1
		var report: Dictionary = {"schema": 1, "scope": "actual Windows portable export paths, settings, F5/F9 save roundtrip and derived cache", "opt_in_flag": "--verify-portable", "godot": Engine.get_version_info(), "display": DisplayServer.get_name(), "renderer": RenderingServer.get_current_rendering_method(), "duration_ms": (Time.get_ticks_usec() - started_us) / 1000.0, "checks": checks, "failures": failures, "details": details, "exit_code": exit_code}
		if not write_text("user://portable_runtime_check.json", JSON.stringify(report, "  ")):
			exit_code = 1
			push_error("Could not write portable validation report")
		print("PORTABLE_RUNTIME ", JSON.stringify(report))
		print("PORTABLE_RUNTIME_FILE ", ProjectSettings.globalize_path("user://portable_runtime_check.json"))
		if exit_code != 0: game.get_tree().quit(exit_code)
		return exit_code

	func execute(owner_game: Node) -> int:
		game = owner_game
		started_us = Time.get_ticks_usec()
		watchdog = game.get_tree().create_timer(40.0)
		watchdog_callback = func():
			if not finished:
				check(false, "portable validation completes within its watchdog deadline")
				finish()
		watchdog.timeout.connect(watchdog_callback)
		await frames()
		environment_checks()
		license_checks()
		await persistence_checks()
		return finish()
