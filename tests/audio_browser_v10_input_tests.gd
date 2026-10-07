extends SceneTree
const Browser=preload("res://scripts/audio_browser.gd")
const Settings=preload("res://scripts/paper_settings.gd")
var checks:=0
var failures:Array[String]=[]
var input_evidence:Dictionary={}
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func mouse(button:int,pressed:bool,point:Vector2)->void:
	var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point
	root.push_input(motion,true)
	var event:=InputEventMouseButton.new();event.button_index=button;event.pressed=pressed;event.position=point;event.global_position=point
	if button==MOUSE_BUTTON_LEFT:event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(event,true)
func click(point:Vector2)->void:
	var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion,true)
	await process_frame
	mouse(MOUSE_BUTTON_LEFT,true,point);await process_frame
	mouse(MOUSE_BUTTON_LEFT,false,point);await process_frame
func run()->void:
	root.size=Vector2i(1400,900)
	var before:int=AudioServer.bus_count
	var audio:=PaperAudio.new();root.add_child(audio);await process_frame
	audio.set_mix({"master":2.0,"music":1.75,"voice":2.0,"sfx":1.5,"muted":false})
	check(audio.get_mix().master==2.0 and audio.get_mix().voice==2.0,"runtime preserves200% preferences")
	var browser:=Browser.new();root.add_child(browser);browser.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);browser.configure(audio,RulesLoader.load_rules())
	await process_frame;await process_frame
	check(browser.current_entries.size()==381 and browser.entry_buttons.size()==381,"every variant remains a separate playable row")
	check(browser.volume_slider.max_value==200.0,"preview slider reaches200%")
	browser.set_preview_volume(200);check(browser.preview_volume==200.0,"preview200% does notclamp to100%")
	var row:Button=browser.entry_buttons[str(browser.current_entries[0].id)]
	var point:Vector2=row.get_global_rect().position+Vector2(20,row.size.y*.5)
	var initial:int=browser.list_scroll.scroll_vertical
	mouse(MOUSE_BUTTON_WHEEL_DOWN,true,point);mouse(MOUSE_BUTTON_WHEEL_DOWN,false,point);await process_frame
	check(browser.list_scroll.scroll_vertical>initial,"real wheel input over the row text scrolls the list")
	var selected:String=browser.selected_id
	for index in range(3):
		mouse(MOUSE_BUTTON_WHEEL_DOWN,true,point);mouse(MOUSE_BUTTON_WHEEL_DOWN,false,point)
	await process_frame
	check(browser.list_scroll.scroll_vertical>initial and browser.selected_id==selected,"scrolling over buttons never activates/reselects a row")
	input_evidence["wheel_before"]=initial;input_evidence["wheel_after"]=browser.list_scroll.scroll_vertical
	var music:Dictionary=browser.catalog.filter(func(entry):return entry.type=="music" and entry.action=="menu")[0]
	browser.select_entry(str(music.id));browser.play_selected();await process_frame
	var volume_rect:Rect2=browser.volume_slider.get_global_rect()
	var volume_point:Vector2=volume_rect.position+Vector2(volume_rect.size.x*.72,volume_rect.size.y*.5)
	await click(volume_point)
	check(browser.volume_slider.value>100.0 and browser.volume_slider.value<190.0,"actual mouse input still operates the200% volume slider")
	input_evidence["mouse_set_preview_percent"]=browser.volume_slider.value
	var progress_rect:Rect2=browser.progress_slider.get_global_rect()
	var progress_point:Vector2=progress_rect.position+Vector2(progress_rect.size.x*.25,progress_rect.size.y*.5)
	await click(progress_point)
	check(browser.playback_position()>5.0 and browser.playback_position()<30.0,"actual mouse input still seeks on the progress slider")
	input_evidence["mouse_seek_seconds"]=browser.playback_position()
	check(audio.get_mix().master==2.0 and audio.get_mix().voice==2.0,"preview controls never alter persisted category preferences")
	var settings=Settings.new();root.add_child(settings);settings.open({"master":2.0,"music":1.75,"sfx":1.5,"voice":2.0});settings.hide()
	for id:String in settings.sliders:check(settings.sliders[id].max_value==200.0,"every settings audio control supports200%")
	check(settings.sliders.master.value==200.0 and settings.sliders.music.value==175.0,"settings restores amplified values exactly")
	browser.set_session_active(false);browser.queue_free();settings.queue_free();audio.stop_all();await create_timer(.2).timeout;audio.queue_free();await process_frame
	browser=null;settings=null;audio=null
	check(AudioServer.bus_count==before,"input fixture releasesaudio buses")
	call_deferred("finish")
func finish()->void:
	await process_frame;await create_timer(.3).timeout
	var report:Dictionary={"checks":checks,"failures":failures,"input_evidence":input_evidence,"scope":"native viewport wheel/slider dispatch, separate variant rows,200%preferences, no GPUcapture"}
	var file:=FileAccess.open("res://artifacts/audio_revision_20261007/audio_browser_input_validation.json",FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"\t")+"\n")
	print("AUDIO_BROWSER_V10_INPUT ",JSON.stringify(report))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
