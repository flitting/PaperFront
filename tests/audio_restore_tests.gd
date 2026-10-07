extends SceneTree

## Headless, isolated preferences and the actual game audio graph. Captures the
## engine's output bus only, never a microphone or operating-system settings.
var checks := 0
var failures: Array[String] = []
var settings_path := ""
var settings_existed := false
var settings_backup := PackedByteArray()
var settings_preserved := false
var game: Node
var recorder: AudioEffectRecord
var recorder_index := -1
var pcm: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func run() -> void:
	# This fixture deliberately exercises preference writes. A hard-killed test
	# must still be confined to its launcher's explicitly isolated data folder.
	if OS.get_environment("XDG_DATA_HOME").is_empty():
		push_error("audio_restore_tests requires an isolated XDG_DATA_HOME")
		quit(2)
		return
	settings_path=ProjectSettings.globalize_path("user://settings.cfg")
	settings_existed=FileAccess.file_exists(settings_path)
	if settings_existed:settings_backup=FileAccess.get_file_as_bytes(settings_path)
	settings_preserved=true
	var preferences:=ConfigFile.new()
	var expected:Dictionary={"master":.61,"music":.23,"sfx":.77,"voice":.44,"muted":false}
	for key:String in expected:preferences.set_value("audio",key,expected[key])
	preferences.set_value("camera","pitch",30.0)
	preferences.set_value("graphics","quality","balanced")
	preferences.set_value("fixture","unrelated_value","must remain byte exact")
	check(preferences.save(settings_path)==OK,"isolated preferences fixture saves")
	var baseline:PackedByteArray=FileAccess.get_file_as_bytes(settings_path)
	# Reproduce the actual former regression: the visual test temporarily mutes
	# audio and calls the normal whole-preferences save path several times.
	var child_output:Array=[]
	var args:=PackedStringArray(["--headless","--audio-driver","Dummy","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/depth_of_field_tests.gd"])
	var child_status:int=OS.execute(OS.get_executable_path(),args,child_output,true)
	var child_log:String="\n".join(child_output)
	check(child_status==0 and not child_log.contains("SCRIPT ERROR:") and not child_log.contains("\nERROR:"),"actual depth-of-field fixture completes without runtime errors")
	check(FileAccess.get_file_as_bytes(settings_path)==baseline,"visual test restores all original preference bytes, including non-audio fields")
	preferences.load(settings_path)
	check(not bool(preferences.get_value("audio","muted",true)),"visual diagnostics cannot leave global mute persisted")
	game=load("res://main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false);game.set_physics_process(false)
	var sound:PaperAudio=game.audio
	check(sound.get_mix()==expected,"actual main-scene startup restores custom positive levels and unmuted state")
	for pair:Array in [[PaperAudio.MASTER_BUS,"master"],[PaperAudio.MUSIC_BUS,"music"],[PaperAudio.BUS_NAME,"sfx"],[PaperAudio.VOICE_BUS,"voice"]]:
		var index:int=AudioServer.get_bus_index(pair[0])
		check(index>=0 and not AudioServer.is_bus_mute(index),"restored category bus is unmuted: "+pair[0])
		check(absf(AudioServer.get_bus_volume_db(index)-linear_to_db(float(expected[pair[1]])))<.001,"restored slider gain reaches its bus: "+pair[1])
	for name:String in [PaperAudio.MUSIC_BUS,PaperAudio.BUS_NAME,PaperAudio.VOICE_BUS]:
		check(AudioServer.get_bus_send(AudioServer.get_bus_index(name))==PaperAudio.MASTER_BUS,"category routes through game master: "+name)
	check(AudioServer.get_bus_send(AudioServer.get_bus_index(PaperAudio.MASTER_BUS))=="Master","game master routes to output")
	for key:String in sound.bank:
		var streams:Array=sound.bank[key] if sound.bank[key] is Array else [sound.bank[key]]
		for stream:AudioStream in streams:check(stream is AudioStreamWAV and stream.data.size()>0 and stream.get_length()>0,"effect imports nonempty original PCM: "+key)
	for key:String in sound.radio_bank:check(sound.radio_bank[key] is AudioStreamWAV and sound.radio_bank[key].data.size()>0,"radio imports original PCM: "+key)
	for key:String in sound.music.tracks:check(sound.music.tracks[key] is AudioStreamWAV and sound.music.tracks[key].data.size()>0,"music imports original PCM: "+key)
	recorder=AudioEffectRecord.new();recorder.format=AudioStreamWAV.FORMAT_16_BITS
	recorder_index=AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0,recorder,recorder_index)
	sound.set_mix({"music":0.0});sound.reset_field()
	await capture("ui_effect",func():sound.play("select"))
	check(sound.ui_players.any(func(player):return player.stream!=null and player.bus==PaperAudio.BUS_NAME),"UI effect uses its dedicated loaded SFX player")
	sound.reset_field();sound.camera_focus=Vector2(10,10)
	await capture("field_effect",func():sound.play_event({"kind":"fire","weapon":"rivet_tank","pos":Vector2(10,10)}))
	check(sound.field_players.any(func(player):return player.stream!=null and player.bus==PaperAudio.BUS_NAME),"combat event reaches the original variant bank and field pool")
	sound.reset_field();sound.set_mix({"sfx":0.0})
	await capture("unit_voice",func():sound.play_unit_voice("rivet_tank","select"))
	check(sound.speech_player.stream==sound.radio_bank[str(sound.last_spoken_clip.key)] and sound.speech_player.bus==PaperAudio.VOICE_BUS,"authored unit radio still plays on the voice route")
	sound.reset_field();sound.set_mix({"music":.23,"sfx":.77,"voice":0.0});sound.set_scene("battle")
	await create_timer(2.6).timeout
	await capture("music",func():pass)
	check(sound.music.player.playing and sound.music.player.stream!=null,"scene music resumes on its single music player")
	sound.set_mix({"muted":true})
	await capture("manual_mute",func():sound.play("select"))
	for name:String in [PaperAudio.MASTER_BUS,PaperAudio.MUSIC_BUS,PaperAudio.BUS_NAME,PaperAudio.VOICE_BUS]:check(AudioServer.is_bus_mute(AudioServer.get_bus_index(name)),"manual total mute remains authoritative: "+name)
	sound.set_mix(expected)
	await capture("manual_unmute",func():sound.play("command"))
	check(not sound.muted,"manual unmute restores playback without resetting the chosen slider levels")
	var available:bool=not pcm.is_empty() and int(pcm[0].samples)>0
	if available:
		for row:Dictionary in pcm:
			check(int(row.peak)==0 if row.label=="manual_mute" else int(row.peak)>0,"actual engine output follows its intended mute/mix state: "+str(row.label))
	# Manual settings must keep working; only diagnostic muting is temporary.
	game.handle_action("audio_mix",{"muted":true})
	preferences.load(settings_path)
	check(bool(preferences.get_value("audio","muted",false)),"intentional mute saves its preference")
	game.handle_action("audio_mix",{"muted":false})
	preferences.load(settings_path)
	check(not bool(preferences.get_value("audio","muted",true)),"intentional unmute saves its preference")
	for key:String in ["master","music","sfx","voice"]:check(is_equal_approx(float(preferences.get_value("audio",key,-1)),float(expected[key])),"mute toggles retain custom category level: "+key)
	game.quit_pending=true
	recorder.set_recording_active(false)
	AudioServer.remove_bus_effect(0,recorder_index);recorder_index=-1
	sound.stop_all()
	await create_timer(.15).timeout
	game.queue_free();await process_frame
	game=null;recorder=null
	check(restore_settings(),"audio restore suite leaves its original settings bytes untouched")
	var report:Dictionary={"checks":checks,"failures":failures,"audio_driver":AudioServer.get_driver_name(),"pcm_supported":available,"pcm":pcm,"scope":"isolated headless original PCM/player routing and optional engine-output samples; no microphone or human listening claim"}
	call_deferred("finish",report)

func finish(report:Dictionary) -> void:
	# Completed async locals can retain loaded WAVs until their coroutine exits.
	# Release them before asking the engine/audio thread to shut down.
	await process_frame
	await create_timer(.2).timeout
	print("AUDIO_RESTORE_TESTS ",JSON.stringify(report))
	for failure:String in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)

func capture(label:String,trigger:Callable) -> void:
	recorder.set_recording_active(false)
	await create_timer(.10).timeout
	recorder.set_recording_active(true)
	trigger.call()
	await create_timer(.18).timeout
	recorder.set_recording_active(false)
	var stream:AudioStreamWAV=recorder.get_recording()
	var samples:=0
	var peak:=0
	if stream!=null and stream.format==AudioStreamWAV.FORMAT_16_BITS:
		samples=stream.data.size()/2
		for offset:int in range(0,stream.data.size()-1,2):peak=maxi(peak,absi(stream.data.decode_s16(offset)))
	pcm.append({"label":label,"samples":samples,"peak":peak})

func restore_settings() -> bool:
	if not settings_preserved:return true
	if settings_existed:
		var file:=FileAccess.open(settings_path,FileAccess.WRITE)
		if file==null:return false
		file.store_buffer(settings_backup);file.close()
		return FileAccess.get_file_as_bytes(settings_path)==settings_backup
	return not FileAccess.file_exists(settings_path) or DirAccess.remove_absolute(settings_path)==OK

func _finalize() -> void:
	restore_settings()
