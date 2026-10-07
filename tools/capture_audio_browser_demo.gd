extends SceneTree

## Real main/Wiki GPU captures; no match starts and preferences are restored.
var game
var backup: Variant
var preserved: bool=false
var rows: Array=[]
const OUTPUT: String="res://artifacts/feedback_v10_20261006/audio_browser/"
func _initialize() -> void: call_deferred("run")
func frames(count: int=5) -> void:
	for frame: int in count: await process_frame
func restore() -> void:
	if not preserved: return
	if backup==null: DirAccess.remove_absolute(ProjectSettings.globalize_path("user://settings.cfg"))
	else:
		var file:=FileAccess.open("user://settings.cfg",FileAccess.WRITE)
		if file!=null:file.store_buffer(backup);file.close()
	preserved=false
func _finalize() -> void: restore()
func capture(name: String) -> void:
	await frames(3)
	if game.hud.wiki.audio_browser.entry_buttons.has(game.hud.wiki.audio_browser.selected_id):
		game.hud.wiki.audio_browser.list_scroll.ensure_control_visible(game.hud.wiki.audio_browser.entry_buttons[game.hud.wiki.audio_browser.selected_id])
	await frames(5)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT+name+".png")
	var wiki: PaperWiki=game.hud.wiki
	var browser: Control=wiki.audio_browser
	var logical: Rect2=root.get_visible_rect()
	var controls_inside: bool=true
	for control: Control in [wiki.audio_button,browser.search,browser.type_filter,browser.faction_filter,browser.category_filter,browser.action_filter,browser.play_button,browser.stop_button]:
		controls_inside=controls_inside and logical.encloses(control.get_global_rect())
	rows.append({"capture":name,"physical_window":[root.size.x,root.size.y],"logical_canvas":[logical.size.x,logical.size.y],"all_primary_controls_inside":controls_inside,"catalog_entries":browser.catalog.size(),"shown_entries":browser.current_entries.size(),"selected_id":browser.selected_id,"browser_rect":str(browser.get_global_rect()),"search_rect":str(browser.search.get_global_rect()),"demo_scene":str(browser.demo.scene_plan.get("scene","none")) if browser.demo!=null else "missing","demo_time":float(browser.demo.animation_time) if browser.demo!=null else 0.0,"demo_visible":browser.demo.visible if browser.demo!=null else false,"demo_rect":str(browser.demo.get_global_rect()) if browser.demo!=null else ""})
func run() -> void:
	if DisplayServer.get_name()=="headless":push_error("Audio browser capture requires a real GPU/display.");quit(1);return
	backup=FileAccess.get_file_as_bytes("user://settings.cfg") if FileAccess.file_exists("user://settings.cfg") else null
	preserved=true
	game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_physics_process(false)
	game.performance_overlay.set_loading(true)
	game.audio.muted=true
	game.set_debug_enabled(false);game.set_audio_browser_enabled(true)
	await frames()
	game.handle_action("wiki",null)
	var wiki: PaperWiki=game.hud.wiki
	wiki.set_audio_tab(true)
	var browser: Control=wiki.audio_browser
	for size: Vector2i in [Vector2i(1440,810),Vector2i(1100,700)]:
		root.size=size;await frames()
		for entry: String in ["sfx/fire_cannon/1","sfx/deploy_building/1","voice/rivet/infantry/under_attack/1","sfx/aircraft_loop/1","music/menu"]:
			browser.select_entry(entry);browser.play_selected()
			if browser.demo!=null:
				browser.demo.set_process(false)
				browser.demo._process(.35 if entry=="sfx/fire_cannon/1" else .70)
				browser.demo.set_process(false)
			await capture(entry.replace("/","_")+"_"+str(size.x)+"x"+str(size.y))
			browser.stop_preview()
	wiki.close_catalog();game.audio.stop_all();game.queue_free();await frames()
	restore()
	var report: Dictionary={"scope":"Real main scene Wiki audio browser, no running match; only selected muted preview clip plus silent independent animation demo, independent global debug disabled; preferences restored; stale frozen FPSbadge hidden.","gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"display":DisplayServer.get_name(),"rows":rows}
	var file:=FileAccess.open(OUTPUT+"capture_report.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("AUDIO_BROWSER_DEMO_GPU ",JSON.stringify(report))
	quit(0 if rows.all(func(row):return row.all_primary_controls_inside) else 1)
