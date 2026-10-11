extends SceneTree

# Black-box bus output test. AudioEffectRecord records the engine's own Master
# mix; it never opens an input device or changes operating-system audio settings.
# No main scene, 3D world, simulation or external audio assets are loaded.
const REPORT_DEFAULT := "res://artifacts/demo_20261004/audio_mix/headless_mix.json"
const CAPTURE_SECONDS := 0.18
const FLUSH_SECONDS := 0.12
var failures: Array[String] = []
var checks := 0
var captures: Array[Dictionary] = []
var recorder: AudioEffectRecord
var recorder_index := -1
var sound: PaperAudio
var started_ms := 0
var report: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func capture(label: String, event := "") -> Dictionary:
	# Let already queued mix blocks drain before starting a fresh recording.
	# AudioEffectRecord starts a new buffer on each inactive -> active transition.
	recorder.set_recording_active(false)
	await create_timer(FLUSH_SECONDS).timeout
	recorder.set_recording_active(true)
	if not event.is_empty(): sound.play(event)
	await create_timer(CAPTURE_SECONDS).timeout
	recorder.set_recording_active(false)
	var stream := recorder.get_recording()
	var measurement := {"label": label, "mix": sound.get_mix(), "scene": sound.music.scene,
		"bytes": 0, "samples": 0, "peak_pcm16": 0, "rms_pcm16": 0.0,
		"duration_s": 0.0, "format": -1, "stereo": false, "mix_rate": 0}
	if stream != null:
		var pcm := stream.data
		measurement.bytes = pcm.size()
		measurement.samples = pcm.size() / 2
		measurement.duration_s = stream.get_length()
		measurement.format = stream.format
		measurement.stereo = stream.stereo
		measurement.mix_rate = stream.mix_rate
		var energy := 0.0
		var peak := 0
		if stream.format == AudioStreamWAV.FORMAT_16_BITS:
			for offset in range(0, pcm.size() - 1, 2):
				var value := pcm.decode_s16(offset)
				peak = maxi(peak, absi(value))
				energy += float(value) * float(value)
		measurement.peak_pcm16 = peak
		measurement.rms_pcm16 = sqrt(energy / maxf(1.0, float(measurement.samples)))
	captures.append(measurement)
	return measurement

func has_samples(measurement: Dictionary) -> bool:
	return int(measurement.samples) > 0 and int(measurement.format) == AudioStreamWAV.FORMAT_16_BITS

func audible(measurement: Dictionary) -> bool:
	return has_samples(measurement) and int(measurement.peak_pcm16) > 0

func silent(measurement: Dictionary) -> bool:
	return has_samples(measurement) and int(measurement.peak_pcm16) == 0

func run() -> void:
	started_ms = Time.get_ticks_msec()
	report = {"scope": "Engine output-only Master bus PCM capture; no microphone, no 3D, no human listening audit",
		"godot": Engine.get_version_info(), "audio_driver": AudioServer.get_driver_name(),
		"mix_rate": AudioServer.get_mix_rate(), "output_latency_s": AudioServer.get_output_latency(),
		"source_sha256": {}, "capture_seconds": CAPTURE_SECONDS, "flush_seconds": FLUSH_SECONDS}
	for path in ["res://scripts/paper_audio.gd", "res://scripts/paper_music.gd", "res://tests/demo_audio_mix_tests.gd"]:
		report.source_sha256[path] = FileAccess.get_sha256(path)
	recorder = AudioEffectRecord.new()
	recorder.format = AudioStreamWAV.FORMAT_16_BITS
	recorder_index = AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, recorder, recorder_index)
	sound = PaperAudio.new(); sound.voice_language = "zh_CN"
	root.add_child(sound)
	await process_frame
	sound.set_mix({"master": 0.85, "music": 0.45, "sfx": 0.9, "voice": 0.85, "muted": false})
	sound.set_scene("menu")
	await create_timer(0.55).timeout
	var music := await capture("menu_music")
	if not has_samples(music):
		report["support_boundary"] = "AudioEffectRecord returned no 16-bit PCM samples with this audio driver. Output mixing cannot be assessed in this environment."
		await complete("UNSUPPORTED")
		return
	check(audible(music), "Menu music produces nonzero real Master PCM")
	sound.set_mix({"music": 0.0})
	check(silent(await capture("music_zero")), "Music zero produces exactly silent PCM with no field sounds")
	sound.set_mix({"music": 0.45, "master": 0.0})
	check(silent(await capture("master_zero")), "Master zero produces exactly silent PCM")
	sound.set_mix({"master": 0.85, "muted": true})
	check(silent(await capture("muted")), "Global mute produces exactly silent PCM")
	sound.set_mix({"muted": false})
	check(audible(await capture("unmuted")), "Unmuting restores nonzero music PCM")
	sound.set_mix({"sfx": 0.0})
	check(audible(await capture("sfx_zero_music")), "SFX zero preserves real music output")
	sound.set_mix({"voice": 0.0})
	check(audible(await capture("voice_zero_music")), "Voice zero preserves real music output")
	sound.set_mix({"music": 0.0, "sfx": 0.9})
	sound.reset_field()
	check(audible(await capture("voice_zero_sfx", "result")), "Voice zero preserves real SFX output while music is muted")
	sound.reset_field()
	sound.set_mix({"sfx": 0.0})
	check(silent(await capture("sfx_zero_sfx", "result")), "SFX zero suppresses real SFX output while music is muted")
	sound.reset_field()
	sound.set_mix({"music": 0.45, "sfx": 0.9, "voice": 0.85})
	sound.set_scene("battle")
	sound.set_scene("win")
	sound.set_scene("lose")
	# A full scene replacement fades out then fades in (1.2s each).
	await create_timer(2.6).timeout
	var transition := await capture("rapid_scene_switch")
	check(audible(transition) and sound.music.scene == "lose" and sound.music.get_child_count() == 1 and sound.music.player.playing,
		"Rapid scene switches settle on one playing music player with real PCM")
	await complete("PASS" if failures.is_empty() else "FAIL")

func complete(status: String) -> void:
	recorder.set_recording_active(false)
	AudioServer.remove_bus_effect(0, recorder_index)
	recorder = null
	sound.stop_all()
	# AudioStreamPlayer stop commands are consumed by the audio thread. Match
	# the existing audio regression's drain before freeing its playback owner.
	await create_timer(0.15).timeout
	sound.queue_free()
	await process_frame
	sound = null
	report.merge({"status": status, "checks": checks, "failures": failures,
		"captures": captures, "wall_seconds": (Time.get_ticks_msec() - started_ms) / 1000.0})
	var output_path := REPORT_DEFAULT
	var args := OS.get_cmdline_user_args()
	var index := args.find("--mix-report")
	if index >= 0 and index + 1 < args.size(): output_path = args[index + 1]
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var output := FileAccess.open(output_path, FileAccess.WRITE)
	if output: output.store_string(JSON.stringify(report, "  "))
	else:
		failures.append("Could not write mix report: " + output_path)
		status = "FAIL"
	# Release coroutine temporaries before engine teardown.
	call_deferred("finish", status)

func finish(status: String) -> void:
	print("DEMO_AUDIO_MIX ", JSON.stringify({"status": status, "checks": checks,
		"audio_driver": report.audio_driver, "wall_seconds": report.wall_seconds, "failures": failures}))
	for failure in failures: push_error(failure)
	quit(0 if status == "PASS" else (2 if status == "UNSUPPORTED" else 1))
