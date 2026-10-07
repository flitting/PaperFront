extends SceneTree
var checks:=0
var failures:Array[String]=[]
var settings_before: Variant = null
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label)
func frames(count:int=3)->void:
	for frame:int in count:await process_frame
func wall(seconds:float)->void:
	var until:int=Time.get_ticks_msec()+roundi(seconds*1000)
	while Time.get_ticks_msec()<until:await process_frame
func run()->void:
	if OS.get_environment("XDG_DATA_HOME").is_empty():push_error("isolated preferences required");quit(2);return
	settings_before=FileAccess.get_file_as_bytes("user://settings.cfg") if FileAccess.file_exists("user://settings.cfg") else null
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	var game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_physics_process(false);await frames()
	check(["master","music","sfx","voice"].all(func(key):return game.audio.get_mix()[key]==1.0) and game.audio.get_mix().commander==.6,"fresh application keeps four categories100% and commander60%")
	check(game.start_match("dev",51,"kestrel",true),"actual main scene starts")
	game.sim.ai_enabled=false;game.hud.show_entry(false);game.hud.show_menu(false)
	var soldiers:Array=[]
	for index:int in 3:soldiers.append(game.sim._spawn(0,"kestrel_rifle",Vector2(20+index,23),true))
	var enemy:int=game.sim._spawn(1,"rivet_tank",Vector2(30,30),true)
	game.selected=soldiers.duplicate();game.selected.append(enemy);game.speak_selection("select")
	check(game.sim._player_navigation_ids.has(soldiers[0]) and not game.sim._player_navigation_ids.has(enemy),"real selection grants navigation priority only to friendly units")
	check(game.audio.last_group_voice.copies==3 and game.audio.last_group_voice.delays_ms==[0,50,100],"real selection dispatches one staggered three-infantry phrase")
	await wall(.16)
	check(game.audio.active_speech_count()==3 and game.audio.speech_players.all(func(p):return p.stream==game.audio.speech_player.stream and p.pitch_scale==1.0),"actual delayed group shares one clip and stays inside three-voice budget")
	game.audio.reset_field();game._set_audio_scene("menu")
	var music=game.audio.music
	for frame:int in 10:music._process(.5)
	game._process(.016);await wall(.35)
	check(music.active_track=="menu" and music.requested_track=="battle_calm","paused audition fixture begins during a real scene fade transition")
	var position:float=music.get_playback_position()
	game.handle_action("pause",null)
	var fade:float=music.fade_elapsed;var combat_clock:float=music.combat_clock
	game._process(.1);await wall(.3)
	check(music.playback_paused and music.player.stream_paused,"actual player pause immediately pauses background music")
	check(absf(music.get_playback_position()-position)<.08 and music.fade_elapsed==fade and music.combat_clock==combat_clock,"actual paused main freezes cursor, fade and classifier")
	game.handle_action("wiki",null);game.hud.wiki.set_audio_tab(true);await frames()
	var browser=game.hud.wiki.audio_browser;browser.select_entry("music/menu");browser.play_selected();await frames()
	for frame:int in 4:game._process(.1);await process_frame
	check(game.audio.preview_active and not music.player.playing and not music.is_processing(),"main scene cannot unpause background music while browser is auditioning")
	browser.stop_preview();check(not music.player.playing and not music.is_processing(),"stopping audition keeps paused background isolated")
	game.hud.wiki.set_audio_tab(false);game.hud.wiki.hide();game.handle_action("wiki_closed",null);game._process(.1)
	check(music.playback_paused and absf(music.get_playback_position()-position)<.09,"paused audition roundtrip preserves actual background cursor")
	game.handle_action("pause",null);game._process(.1);await wall(.2)
	check(not music.playback_paused and music.get_playback_position()>position,"actual resume continues from saved position")
	var cfg:=ConfigFile.new()
	for entry:Array in [["master",.85],["music",.45],["sfx",.9],["voice",.85]]:cfg.set_value("audio",entry[0],entry[1])
	cfg.save("user://settings.cfg");game.load_preferences()
	check(["master","music","sfx","voice"].all(func(key):return game.audio.get_mix()[key]==1.0) and game.audio.get_mix().commander==.6,"historical defaults migrate to existing100% baseline with restrained commander60%")
	cfg.set_value("audio","music",.3);cfg.save("user://settings.cfg");game.load_preferences()
	check(game.audio.get_mix().music==.3 and game.audio.get_mix().master==.85,"custom historical player preference is preserved")
	game.quit_pending=true;game.audio.stop_all();await create_timer(.25).timeout;game.queue_free();await process_frame;await create_timer(.25).timeout
	print("MAIN_FEEDBACK_V11 ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure:String in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
func _finalize()->void:
	if settings_before==null:DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	else:
		var file:=FileAccess.open("user://settings.cfg",FileAccess.WRITE)
		if file!=null:file.store_buffer(settings_before);file.close()
