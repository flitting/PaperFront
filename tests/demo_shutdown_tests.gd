extends SceneTree

# Uses the actual main, loading coroutine, dev world and audio players. The
# sole main override injects a real quit at the selected loading callback.
# Each mode runs in its own isolated-XDG process and lets quit_game terminate
# it after writing observations and restoring any pre-existing user files.
const Rules = preload("res://scripts/rules_loader.gd")
const Sim = preload("res://tests/rule_test_simulation.gd")

class ShutdownGame:
	extends "res://scripts/main.gd"
	signal shutdown_injected(fraction: float, stage: String)
	var injection_fraction: float = 0.98
	var injection_done: bool = false
	func _loading_progress(fraction: float, stage: String) -> void:
		if not injection_done and fraction >= injection_fraction:
			injection_done = true
			quit_game()
			shutdown_injected.emit(fraction, stage)
		await super._loading_progress(fraction, stage)

var game
var mode: String = "start"
var baseline: bool = false
var output: String = ""
var checks: int = 0
var failures: Array[String] = []
var samples: Array[Dictionary] = []
var backups: Dictionary = {}
var sentinel: PackedByteArray
var injection: Dictionary = {}
var injected_at_ms: int = -1
var action_completed: bool = false
var report_written: bool = false
var started_again: bool = false
var audio_again: bool = false
var settings_rewritten: bool = false
var viewport_reenabled: bool = false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shutdown-mode="): mode = arg.trim_prefix("--shutdown-mode=")
		if arg.begins_with("--shutdown-evidence="): output = arg.trim_prefix("--shutdown-evidence=")
		if arg == "--shutdown-baseline": baseline = true
	if output.is_empty(): output = "res://artifacts/demo_20261004/shutdown/" + mode + ".json"
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func preserve(path: String) -> void:
	backups[path] = FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null

func restore() -> void:
	for path: String in backups:
		if backups[path] == null:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		else:
			var file = FileAccess.open(path, FileAccess.WRITE)
			if file != null:
				file.store_buffer(backups[path])
				file.close()

func observe() -> Dictionary:
	var active_players: int = 0
	var assigned_streams: int = 0
	var players: Array = game.audio.players.duplicate()
	players.append(game.audio.music.player)
	for player in players:
		if not is_instance_valid(player): continue
		if player.playing: active_players += 1
		if player.stream != null: assigned_streams += 1
	var settings: PackedByteArray = FileAccess.get_file_as_bytes("user://settings.cfg")
	var sample: Dictionary = {"elapsed_ms": Time.get_ticks_msec() - injected_at_ms, "started": game.started, "hud_started": game.hud.is_started, "loading": game.loading, "quit_pending": game.quit_pending, "audio_scene": game.audio_scene, "requested_music_scene": game.audio.music.requested_scene, "music_scene": game.audio.music.scene, "music_playing": game.audio.music.player.playing, "music_stream_assigned": game.audio.music.player.stream != null, "active_players": active_players, "assigned_streams": assigned_streams, "muted": game.audio.muted, "settings_sha256": FileAccess.get_sha256("user://settings.cfg"), "sentinel_unchanged": settings == sentinel, "viewport_update_mode": game.battlefield_viewport.render_target_update_mode, "action_completed": action_completed}
	started_again = started_again or bool(sample.started)
	audio_again = audio_again or active_players > 0 or assigned_streams > 0 or game.audio.music.requested_scene != "silent"
	settings_rewritten = settings_rewritten or settings != sentinel
	viewport_reenabled = viewport_reenabled or game.battlefield_viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED
	if samples.size() < 128: samples.append(sample)
	return sample

func on_injected(fraction: float, stage: String) -> void:
	injected_at_ms = Time.get_ticks_msec()
	injection = {"fraction": fraction, "stage": stage}
	observe()

func drive_action() -> void:
	if mode == "start": await game.handle_action("start", {"mode": "dev", "seed": 41, "faction": "rivet", "match_options": {}})
	else: await game.handle_action("load", null)
	action_completed = true

func write_report() -> void:
	if report_written: return
	report_written = true
	check(not injection.is_empty() and is_equal_approx(float(injection.get("fraction", -1)), 0.98), "real loading reaches the exact late quit injection")
	check(game.quit_pending, "real quit_game owns the pending shutdown")
	check(samples.size() >= 3, "multiple actual process frames were observed after quit")
	check(action_completed, "pending start/load action resumed before the report")
	check(not started_again, "no resumed coroutine starts the match after quit")
	check(not audio_again, "audio scene, PCM streams and players remain stopped after quit")
	check(not settings_rewritten, "quit-time coroutine preserves settings sentinel bytes")
	check(not viewport_reenabled, "quit-time coroutine keeps battlefield rendering disabled")
	var report: Dictionary = {"mode": mode, "baseline_source": baseline, "main_sha256": FileAccess.get_sha256("res://artifacts/demo_20261004/shutdown/before_main.gd" if baseline else "res://scripts/main.gd"), "test_sha256": FileAccess.get_sha256("res://tests/demo_shutdown_tests.gd"), "user_directory": OS.get_user_data_dir(), "checks": checks, "failures": failures, "injection": injection, "samples": samples, "started_again": started_again, "audio_again": audio_again, "settings_rewritten": settings_rewritten, "viewport_reenabled": viewport_reenabled, "action_completed": action_completed, "real_game_exit_requested": game.quit_pending, "scope": "headless real main/loading/audio-player state; no GPU or listening claim"}
	var file = FileAccess.open(output, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	else: push_error("Cannot write shutdown evidence: " + output)
	restore()
	print("DEMO_SHUTDOWN ", JSON.stringify({"mode": mode, "checks": checks, "failures": failures, "samples": samples.size(), "real_game_exit_requested": game.quit_pending, "evidence": output}))
	for failure in failures: push_error(failure)

func run() -> void:
	# This guard prevents a mistaken direct invocation from touching a user's
	# real desktop preferences outside the test's documented writable area.
	if not OS.get_user_data_dir().begins_with("/tmp/"):
		push_error("Use isolated XDG_DATA_HOME and XDG_CONFIG_HOME under /tmp for shutdown tests")
		quit(1)
		return
	if mode not in ["start", "load"]:
		push_error("shutdown mode must be start or load")
		quit(1)
		return
	preserve("user://settings.cfg")
	preserve("user://skirmish_v1.pfront")
	sentinel = ("; shutdown sentinel bytes must survive\n[audio]\nmaster=0.77\nmusic=0.44\nsfx=0.66\nvoice=0.55\nmuted=false\n\n[shutdown_probe]\nsentinel=\"late-quit-" + mode + "\"\n").to_utf8_buffer()
	var settings = FileAccess.open("user://settings.cfg", FileAccess.WRITE)
	settings.store_buffer(sentinel)
	settings.close()
	root.size = Vector2i(1440, 810)
	game = load("res://artifacts/demo_20261004/shutdown/baseline_game.gd").new() if baseline else ShutdownGame.new()
	game.shutdown_injected.connect(on_injected)
	root.add_child(game)
	await process_frame
	if mode == "load":
		var saved = Sim.new()
		saved.setup(Rules.load_rules(), "dev", 43, "rivet", false)
		check(saved.save_game(game.SAVE_PATH).is_empty(), "isolated real dev save fixture writes")
	drive_action()
	var timeout: int = Time.get_ticks_msec() + 4500
	while injected_at_ms < 0 and Time.get_ticks_msec() < timeout: await process_frame
	if injected_at_ms < 0:
		check(false, "late loading callback was reached within the small-fixture deadline")
		write_report()
		quit(1)
		return
	while Time.get_ticks_msec() - injected_at_ms < 55 or samples.size() < 3:
		await process_frame
		observe()
	write_report()
	# A passing or failing observed run exits through the real 0.12-second
	# quit_game timer. ERROR lines remain authoritative to tools/test.sh.
	# Return this verification coroutine before teardown, releasing its local
	# FileAccess/fixture references. The signal watchdog does not hold its stack.
	create_timer(0.6).timeout.connect(on_exit_timeout)

func on_exit_timeout() -> void:
	push_error("Real quit_game timer did not terminate the test")
	quit(1)
