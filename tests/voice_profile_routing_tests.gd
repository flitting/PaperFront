extends SceneTree

var checks := 0
var failures: Array[String] = []
var routes: Dictionary = {}

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func run() -> void:
	var sound := PaperAudio.new()
	root.add_child(sound)
	await process_frame
	sound.set_process(false)
	var rules: Dictionary = RulesLoader.load_rules()
	sound.configure_units(rules)
	check(sound.speech_profile_speakers.size() == 12, "Every faction/class has one declared fixed speaker profile")
	var representatives: Dictionary = {}
	for spec: String in rules.units:
		var profile: String = sound.speech_profile_key(spec)
		var speaker: String = str(sound.speech_profile_speakers.get(profile, ""))
		check(not speaker.is_empty(), "Unit resolves a fixed speaker: " + spec)
		if not representatives.has(profile): representatives[profile] = spec
		var action_routes: Dictionary = {}
		for action: String in PaperAudio.RADIO_ACTIONS:
			var key: String = sound.speech_key(spec, action)
			check(key == profile + "/" + action, "Unit/faction/class remain independent of action: " + spec + "/" + action)
			var clips: Array = sound.speech_clips.get(key, [])
			check(clips.size() == 4 if action == "death" else clips.size() in [2,3], "Fixed identity retains distinct original variants after old faction-name recordings retire: " + key)
			check(clips.all(func(clip):return not str(clip.text).contains("铁钉") and not str(clip.text).contains("天翼")), "Active recordings never speak former faction names: " + key)
			check(clips.all(func(clip): return str(clip.get("speaker_id", "")) == speaker), "All variants/actions use exactly the unit's fixed speaker: " + key)
			action_routes[action] = {"group":key,"speaker_id":speaker,"variants":clips.size()}
		routes[spec] = {"profile":profile,"speaker_id":speaker,"actions":action_routes}
	for profile: String in representatives:
		for action: String in PaperAudio.RADIO_ACTIONS:
			sound.reset_field()
			check(sound.play_unit_voice(str(representatives[profile]), action), "Actual profile/action plays: " + profile + "/" + action)
			check(str(sound.last_spoken_clip.speaker_id) == str(sound.speech_profile_speakers[profile]), "Playback chooses the declared speaker across actions")
			check(sound.speech_players.any(func(player): return player.playing and is_equal_approx(player.pitch_scale, 1.0)), "Runtime never changes dialogue pitch by action")
	sound.stop_all()
	await create_timer(.25).timeout
	sound.queue_free()
	await process_frame
	call_deferred("finish")

func finish() -> void:
	await process_frame
	await create_timer(.3).timeout
	var report := {"status":"PASS" if failures.is_empty() else "FAIL","checks":checks,"failures":failures,"scope":"Definition-based faction/class routing and declared fixed speaker consistency across every action/variant; actual runtime playback remains pitch1; acoustic identity reviewed separately.","units":routes}
	var path := "res://artifacts/av_revision_20261006/voice_profile_routing_validation.json"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report,"  "))
	print("VOICE_PROFILE_ROUTING ",JSON.stringify({"checks":checks,"failures":failures,"units":routes.size()}))
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
