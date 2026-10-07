extends SceneTree
const Browser=preload("res://scripts/audio_browser.gd")
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func run()->void:
	var before:int=AudioServer.bus_count
	var audio:=PaperAudio.new();root.add_child(audio)
	await process_frame
	audio.configure_units(RulesLoader.load_rules());audio.set_mix({"muted":false,"master":.8,"music":.4,"sfx":.8,"voice":.8})
	audio.set_scene("menu");await create_timer(2.2).timeout
	var browser:=Browser.new();browser.hide();root.add_child(browser)
	browser.configure(audio,RulesLoader.load_rules());browser.show();await process_frame
	check(browser.session_active and not audio.music.player.playing and not audio.music.is_processing(),"entering the player pauses all normal background music before play")
	check(browser.demo!=null,"the animation panel is actually present")
	browser.select_entry("sfx/fire_cannon/1");browser.play_selected()
	check(browser.preview_player.playing and browser.demo.demo_playing,"play starts selected audio and its firing scene")
	await create_timer(.12).timeout
	check(browser.demo.demo_age>.05 and browser.demo.is_processing(),"the demonstration actually animates from normal engine frames")
	browser.demo.set_process(false);browser.demo._process(.12)
	var age:float=browser.demo.demo_age
	browser.seek_to(.7)
	check(absf(browser.playback_position()-.7)<.05 and browser.demo.demo_age==age,"audio seek changes only audio cursor, not animation")
	browser.set_playback_speed(1.5);check(browser.preview_player.pitch_scale==1.5,"speed control reaches the sole playback player")
	browser.set_preview_volume(35);check(absf(browser.preview_player.volume_linear-db_to_linear(browser._preview_gain(browser.selected_entry))*.35)<.0001,"preview volume is independent of saved category preferences")
	browser.pause_preview(true)
	check(browser.preview_player.stream_paused and browser.demo.demo_paused,"explicit pause freezes audio and the independent scene")
	browser.pause_preview(false);browser.restart_preview()
	check(browser.demo.demo_age==0.0 and not browser.preview_player.stream_paused and browser.preview_player.playing,"replay restarts both audio and animation")
	browser.demo._process(.12);age=browser.demo.demo_age
	browser._preview_finished()
	check(browser.demo.demo_age==age and browser.demo.demo_playing,"audio ending after a seek cannot stop the independently running scene")
	browser.stop_preview()
	check(not browser.preview_player.playing and not browser.demo.demo_playing and not audio.music.player.playing,"stop ends selected audio/scene while normal music remains paused")
	var id:String=browser.selected_id
	browser.next_clip()
	check(browser.selected_id!=id and browser.preview_player.playing,"next selects and starts the next item in the current filtered playlist")
	browser.select_entry("music/menu");browser.play_selected()
	check(browser.demo.scene_kind=="blank" and browser.demo.model_node==null,"background music has no animation")
	check(browser.find_children("*","AudioStreamPlayer",true,false).size()==1 and audio.players.all(func(p):return not p.playing),"only the selected clip is audible; demonstration has no extra players")
	browser.hide();await process_frame
	check(audio.music.player.playing and audio.music.is_processing() and not audio.preview_active,"leaving the player restores normal background playback")
	browser.queue_free();audio.stop_all();await create_timer(.25).timeout
	audio.queue_free();await process_frame
	check(AudioServer.bus_count==before,"transport and demonstration teardown releases audio graph")
	print("AUDIO_BROWSER_TRANSPORT ",JSON.stringify({"checks":checks,"failures":failures}))
	call_deferred("finish")
func finish()->void:
	await process_frame;await create_timer(.3).timeout
	for failure:String in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
