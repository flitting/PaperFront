extends SceneTree
var checks:=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func run()->void:
	var before:int=AudioServer.bus_count
	var audio:=PaperAudio.new(); audio.voice_language = "zh_CN";root.add_child(audio);audio.set_scene("menu")
	for i in range(60):audio.music._process(.05)
	await create_timer(.6).timeout
	audio.music.set_playback_paused(true)
	var saved:float=audio.music.player.get_playback_position()
	check(saved>.05 and audio.music.player.stream_paused,"gameplay pause freezes alreadyadvanced music")
	var evidence:Dictionary={"before_browser":saved,"playing_while_paused":audio.music.player.playing,"paused_flag":audio.music.player.stream_paused}
	var browser:=AudioBrowser.new();root.add_child(browser);browser.configure(audio,RulesLoader.load_rules());browser.set_session_active(true)
	await process_frame
	check(browser.session_active and not audio.music.player.playing,"audio tab silences music whilegameplay alreadypaused")
	evidence["snapshot"]=browser._music_snapshot.duplicate();evidence.snapshot.erase("owner");evidence.snapshot.erase("stream")
	browser.set_session_active(false);await create_timer(.15).timeout
	evidence["after_close_paused"]=audio.music.player.get_playback_position();evidence["after_close_playing"]=audio.music.player.playing;evidence["after_close_flag"]=audio.music.player.stream_paused;evidence["pause_owner"]=audio.music.playback_paused;evidence["held_cursor"]=audio.music.get_playback_position()
	check(audio.music.playback_paused and not audio.music.player.playing and audio.music.preview_resume_position>=0.0 and absf(audio.music.get_playback_position()-saved)<.03,"leavingtab preserves gameplaypaused position")
	var frozen_again:float=audio.music.get_playback_position()
	browser.set_session_active(true);await process_frame;browser.set_session_active(false);await process_frame
	check(absf(audio.music.get_playback_position()-frozen_again)<.005,"reopening pausedtab cannotlose pendingresume cursor")
	audio.music.set_playback_paused(false);await create_timer(.3).timeout
	evidence["after_resume"]=audio.music.player.get_playback_position()
	check(audio.music.player.playing and audio.music.player.get_playback_position()>saved+.04,"resume aftertab continuesoriginalposition")
	audio.music.set_scene("battle");await create_timer(.35).timeout
	check(audio.music.active_track=="menu" and audio.music.requested_track=="battle_calm" and audio.music.fade_phase=="out","fixture pauses a realmenu-to-calm fade beforestreamswitch")
	audio.music.set_playback_paused(true)
	var transition_cursor:float=audio.music.get_playback_position();var transition_gain:float=audio.music.gain;var transition_elapsed:float=audio.music.fade_elapsed
	browser.set_session_active(true);await process_frame;browser.set_session_active(false);await create_timer(.1).timeout
	check(absf(audio.music.get_playback_position()-transition_cursor)<.03 and audio.music.gain==transition_gain and audio.music.fade_elapsed==transition_elapsed,"pausedtransitiontab roundtrip preservesoutgoingcursor gainandfadeclock despitependingdifferenttrack")
	audio.music.set_playback_paused(false);await create_timer(.2).timeout
	check(audio.music.active_track=="menu" and audio.music.fade_elapsed>transition_elapsed and audio.music.player.playing,"transition resumes originaloutgoingstream andfadephase")
	browser.queue_free();audio.stop_all();await create_timer(.2).timeout;audio.queue_free();await process_frame
	check(AudioServer.bus_count==before,"pausedbrowser fixture releasesallbuses")
	await process_frame;await create_timer(.3).timeout
	var report:Dictionary={"checks":checks,"failures":failures,"saved_position":saved,"evidence":evidence}
	var f:=FileAccess.open("res://artifacts/audio_revision_20261007/pause_browser_validation.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t")+"\n");f=null
	print("PAUSE_BROWSER ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
