extends SceneTree

## Optional PCK smoke check; ordinary game startup does not run this script.
const Browser = preload("res://scripts/audio_browser.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func run() -> void:
	var sound := PaperAudio.new()
	root.add_child(sound)
	var browser := Browser.new()
	root.add_child(browser)
	await process_frame
	browser.configure(sound, RulesLoader.load_rules())
	check(browser.catalog.size() == 381, "PCK includes all applied unit/system audio and interface metadata")
	check(browser.demo != null, "animation helper is included in the exported game")
	for prefix: String in ["voice/rivet/vehicle/select/1", "voice/iron/air/death/4", "voice/sky/air/select/1", "voice/system/low_power/1", "voice/system/power_restored/1", "sfx/fire_cannon/1", "sfx/fire_energy/1", "sfx/impact_energy/1", "sfx/creator_hand_attack/1", "sfx/creator_hand_impact/1", "sfx/select_power/1", "sfx/ui_key/1", "sfx/ui_click/1", "music/menu", "music/battle_calm", "music/battle_engaged", "music/battle_intense", "music/battle_danger"]:
		browser.select_entry(prefix)
		check(not browser.selected_entry.is_empty() and bool(browser.selected_entry.get("preview_valid", false)), "packed imported audio can be validated: " + prefix)
		check(str(browser.inspect_entry(browser.selected_entry).get("mode", "")) == "imported", "preview validates the exported import without raw WAV fallback: " + prefix)
		browser.play_selected()
		check(browser.preview_player.playing and browser.preview_player.stream is AudioStreamWAV, "packed preview plays: " + prefix)
		check(browser.demo.scene_kind == "blank" if prefix.begins_with("music/") else browser.demo.demo_playing, "packed preview includes the right demonstration or blank background scene")
		browser.stop_preview()
	for path: String in ["res://assets/audio/radio/manifest.json", "res://assets/audio/voices/manifest.json"]:
		check(not FileAccess.file_exists(path), "retired voice manifest absent from PCK")
	browser.stop_preview()
	sound.stop_all()
	await create_timer(.25).timeout
	browser.queue_free(); sound.queue_free()
	await process_frame
	call_deferred("finish")

func finish() -> void:
	await create_timer(.3).timeout
	print("PACKED_AUDIO_BROWSER ", JSON.stringify({"checks": checks, "failures": failures}))
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
