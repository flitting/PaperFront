extends SceneTree

## Real main/settings/Wiki integration. Run with isolated XDG directories; the
## original settings bytes are also restored for safe standalone execution.
var game
var checks: int=0
var failures: Array[String]=[]
var backup: Variant
var preserved: bool=false
var changed_events: Array=[]

func _initialize() -> void: call_deferred("run")
func check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures.append(label)
func frames(count: int=3) -> void:
	for frame: int in count: await process_frame
func preserve() -> void:
	backup=FileAccess.get_file_as_bytes("user://settings.cfg") if FileAccess.file_exists("user://settings.cfg") else null
	preserved=true
func restore() -> void:
	if not preserved: return
	if backup==null: DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	else:
		var file:=FileAccess.open("user://settings.cfg",FileAccess.WRITE)
		if file!=null: file.store_buffer(backup);file.close()
	preserved=false
func _finalize() -> void: restore()
func config_values(ignore_browser: bool=false) -> Dictionary:
	var config:=ConfigFile.new()
	if config.load("user://settings.cfg")!=OK: return {}
	var result: Dictionary={}
	for section: String in config.get_sections():
		for key: String in config.get_section_keys(section):
			if ignore_browser and section=="debug" and key=="audio_browser_enabled": continue
			result[section+"/"+key]=config.get_value(section,key)
	return result
func click(control: Control) -> void:
	var parent: Node=control.get_parent()
	while parent!=null:
		if parent is ScrollContainer: parent.ensure_control_visible(control)
		parent=parent.get_parent()
	await frames()
	for pressed: bool in [true,false]:
		var event:=InputEventMouseButton.new()
		event.position=control.get_global_rect().get_center()
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
		root.push_input(event,true)
	await frames()

func run() -> void:
	root.size=Vector2i(1600,900)
	preserve()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_physics_process(false)
	await frames()
	var sheet: PaperSettings=game.hud.settings
	var wiki: PaperWiki=game.hud.wiki
	check(game.audio_browser_enabled and wiki.audio_browser_enabled and wiki.audio_button.visible,"fresh launch without preferences defaults the Wiki audio browser on")
	check(not game.debug_available,"audio browser does not require the global debug flag")
	check(sheet.find_child("AudioBrowserEnabled",true,false)==sheet.audio_browser_enabled,"actual canonical settings sheet owns the named AudioBrowserEnabled CheckButton")
	game.audio.set_mix({"master":.73,"music":.31,"sfx":.54,"voice":.81,"muted":false})
	game.save_preferences()
	var mix: Dictionary=game.audio.get_mix().duplicate(true)
	var original: Dictionary=config_values(true)
	sheet.changed.connect(func(kind: String,value: Variant): changed_events.append({"kind":kind,"value":value}))
	game.handle_action("settings_open",null);await frames()
	check(sheet.audio_browser_enabled.button_pressed and not sheet.debug_enabled.button_pressed,"settings presents independent audio-browser and debug switches")
	await click(sheet.audio_browser_enabled)
	check(changed_events.any(func(event): return event.kind=="audio_browser_enabled" and event.value==false),"actual GUI toggle emits the canonical settings changed signal")
	check(not game.audio_browser_enabled and not wiki.audio_button.visible and not wiki.audio_browser_enabled,"GUI toggle updates main preference and Wiki entry visibility")
	check(config_values().get("debug/audio_browser_enabled",true)==false,"GUI toggle persists debug.audio_browser_enabled=false")
	check(config_values(true)==original and game.audio.get_mix()==mix,"browser setting preserves every other saved preference and audio mix")
	game.set_audio_browser_enabled(true)
	game.load_preferences()
	check(not game.audio_browser_enabled and not wiki.audio_button.visible,"load_preferences restores the persisted disabled state")
	game.handle_action("settings_open",null);await frames()
	await click(sheet.audio_browser_enabled)
	check(game.audio_browser_enabled and wiki.audio_button.visible and config_values().get("debug/audio_browser_enabled",false),"GUI re-enable persists and restores the Wiki entry")
	check(not game.debug_available and not sheet.debug_enabled.button_pressed,"audio-browser re-enable leaves global debug disabled")
	await click(sheet.close_button)
	game.handle_action("wiki",null);await frames()
	await click(wiki.audio_button)
	var browser: Control=wiki.audio_browser
	check(wiki.audio_tab_active and browser.visible and not wiki.equipment_body.visible,"actual Wiki audio entry opens the browser tab")
	check(browser.catalog.size()==378 and browser.current_entries.size()==378,"Wiki audio tab contains exactly the 378 applied runtime-bank entries")
	check(browser.catalog.all(func(row):return not str(row.file).begins_with("res://assets/audio/voices/") and not str(row.file).begins_with("res://assets/audio/radio/") and str(row.file)!="res://assets/audio/music/menu.wav"),"Wiki inventory excludes retired voice banks and replaced menu music")
	browser.select_entry("voice/rivet/vehicle/select/1")
	browser.play_selected();await frames(2)
	check(browser.preview_player.playing and browser.preview_player.stream!=null,"actual applied clip plays in the dedicated preview player")
	check(game.audio.get_mix()==mix,"preview playback does not alter user mix preferences")
	# Change the same real CheckButton while its sheet is behind the Wiki. This
	# exercises the signal route without closing the audio tab first.
	sheet.audio_browser_enabled.button_pressed=false
	await frames()
	check(not wiki.audio_tab_active and not browser.visible and wiki.equipment_body.visible,"disabling the setting from an active audio tab returns to model archives")
	check(not browser.preview_player.playing and browser.preview_player.stream==null,"disabling an active browser stops and releases the preview stream")
	check(not wiki.audio_button.visible and config_values().get("debug/audio_browser_enabled",true)==false,"active-tab disable hides its entry and persists")
	check(game.audio.get_mix()==mix and config_values(true)==original,"active-tab disable preserves other preferences and all mix levels")
	wiki.set_audio_tab(true)
	check(not wiki.audio_tab_active and not browser.preview_player.playing,"disabled browser cannot reopen via its tab API")
	wiki.close_catalog()
	game.set_audio_browser_enabled(true)
	game.handle_action("settings_open",null);await frames()
	await click(sheet.debug_enabled)
	check(game.debug_available and config_values().get("debug/enabled",false),"existing real global-debug GUI toggle still enables and persists debug")
	check(game.audio_browser_enabled and wiki.audio_button.visible,"enabling global debug does not change the independent browser setting")
	await click(sheet.debug_enabled)
	check(not game.debug_available and config_values().get("debug/enabled",true)==false,"existing real global-debug GUI toggle still disables and persists debug")
	check(game.audio_browser_enabled and wiki.audio_button.visible,"disabling global debug leaves the browser available")
	check(game.audio.get_mix()==mix,"global-debug toggles leave the audio mix unchanged")
	await click(sheet.close_button)
	var legacy:=ConfigFile.new()
	legacy.set_value("debug","enabled",false)
	check(legacy.save("user://settings.cfg")==OK,"historical debug-only preference fixture writes")
	game.set_audio_browser_enabled(false);game.load_preferences()
	check(game.audio_browser_enabled and wiki.audio_button.visible and not game.debug_available,"historical preferences without the new key default the browser on independently")
	game.audio.stop_all();game.queue_free();await frames()
	restore()
	print("AUDIO_BROWSER_SETTINGS ",JSON.stringify({"checks":checks,"failures":failures,"input":"real viewport GUI toggle and canonical settings signal","catalog":378,"preferences_restored":not preserved}))
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
