extends SceneTree

const Brief=preload("res://scripts/unit_brief.gd")
var game
var checks:int=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message)
func frames(count:int=3)->void:
	for _frame:int in range(count):await process_frame
func click(control:Control)->void:
	for pressed:bool in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=control.get_global_rect().get_center();root.push_input(event,true)
	await frames()
func tab(tabs:TabContainer,index:int)->void:
	var bar:TabBar=tabs.get_tab_bar()
	for pressed:bool in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=bar.global_position+bar.get_tab_rect(index).get_center();root.push_input(event,true)
	await frames()
	check(tabs.current_tab==index,"actual tab click opens "+tabs.get_tab_title(index))
func capture(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	var folder:String="res://artifacts/rts_revision_v4_20261007/ui"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	check(root.get_texture().get_image().save_png(folder.path_join(name+".png"))==OK,"actual viewport screenshot "+name)
func run()->void:
	root.size=Vector2i(1440,900)
	game=load("res://main.tscn").instantiate();root.add_child(game)
	game.set_process(false);game.set_physics_process(false);await frames(5)
	var hud=game.hud
	await click(hud.entry_menu.play_button)
	check(hud.menu.visible and hud.setup_tabs.get_tab_count()==3,"new-match menu has three navigation pages")
	var original_faction:String=hud.selected_faction()
	await tab(hud.setup_tabs,0)
	await click(hud.faction_buttons.sky)
	check(hud.selected_faction()=="sky","actual faction button still selects Sky from its tab")
	await tab(hud.setup_tabs,1)
	check(hud.map_option.is_visible_in_tree() and not hud.faction_buttons.sky.is_visible_in_tree(),"battlefield tab displays map controls and hides faction controls")
	await capture("match_battlefield")
	await tab(hud.setup_tabs,2)
	check(hud.match_setup.is_visible_in_tree(),"deployment page exposes real player and opponent settings")
	var color_choice:OptionButton=hud.match_setup.player_color_option
	color_choice.select(3);color_choice.item_selected.emit(3)
	var selected_color:String=hud.match_setup.options("sky").slots[0].color
	await capture("match_deployment")
	await tab(hud.setup_tabs,0)
	check(hud.selected_faction()=="sky" and hud.match_setup.options("sky").slots[0].color==selected_color,"tab navigation preserves faction and deployment values")
	check(game.start_match("dev",17,"kestrel",true),"real gameplay starts for selected-unit brief")
	hud.show_menu(false)
	game.handle_action("settings_open",null);await frames()
	var sheet:PaperSettings=hud.settings
	check(sheet.tabs.get_tab_count()==5 and game.pve_paused,"settings has five pages and keeps the match paused")
	var initial_time:float=game.sim.time
	await tab(sheet.tabs,1)
	var original:float=sheet.sliders.sfx.value
	sheet.sliders.sfx.value=83
	await tab(sheet.tabs,2)
	check(sheet.quality.is_visible_in_tree() and not sheet.sliders.sfx.is_visible_in_tree(),"graphics tab displays only its controls")
	await capture("settings_graphics")
	await tab(sheet.tabs,3)
	check(sheet.pitch_mode.is_visible_in_tree() and sheet.pitch.is_visible_in_tree(),"camera controls have a dedicated page")
	await capture("settings_camera")
	await tab(sheet.tabs,4)
	check(sheet.debug_enabled.is_visible_in_tree(),"debug controls have a dedicated page")
	await tab(sheet.tabs,1)
	check(is_equal_approx(sheet.sliders.sfx.value,83),"audio edits survive switching pages")
	sheet.sliders.sfx.value=original
	game._physics_process(.3)
	check(game.sim.time==initial_time,"switching settings tabs cannot advance the paused simulation")
	await tab(sheet.tabs,0);await click(sheet.close_button)
	check(not sheet.visible and not game.pve_paused,"completion closes every page and restores running state")
	game.camera.position=Vector3(25,20,45)
	game.camera.look_at(Vector3(25,0,25))
	for faction:String in ["sky","kestrel"]:
		var power:int=game.sim._spawn(0,faction+"_power",Vector2(25,25),true)
		game.world.sync(.01,[])
		var model:Dictionary=game.world.models[power]
		var before_smoke:int=0
		for batch:Dictionary in game.world.steam_batches:before_smoke+=game.world._batch_count(batch)
		game.world._industrial_smoke(model,game.sim.entities[power])
		var after_smoke:int=0
		for batch:Dictionary in game.world.steam_batches:after_smoke+=game.world._batch_count(batch)
		check((after_smoke==before_smoke) if faction=="sky" else (after_smoke>before_smoke),faction+" actual industrial smoke matches chimney presence")
		check(model.smoke_ports.is_empty() if faction=="sky" else not model.smoke_ports.is_empty(),faction+" chimney emitter contract")
		game.sim._kill_entity(power,false)
	for spec:String in ["kestrel_rifle","kestrel_anti","kestrel_aa","kestrel_harvester","sky_heavy_tank","rivet_zeppelin","kestrel_carrier"]:
		var id:int=game.sim._spawn(0,spec,Vector2(25,25),true)
		var e:Dictionary=game.sim.entities[id]
		hud.selection=[id]
		var text:String=hud.selection_text()
		check(text.contains("定位：") and text.contains("护甲") and text.contains("穿甲"),spec+" concise role and numeric defense/offense are in the visible selection text")
		check(text.contains("护甲 %.0f"%game.sim.armor_for(e)),spec+" armor is the actual dynamic value")
		if spec=="kestrel_anti":
			var old_armor:float=game.sim.armor_for(e)
			e.veteran=true;e.max_hp=game.sim.max_hp(e)
			check(Brief.summary(game.sim,e).contains("护甲 %.0f"%game.sim.armor_for(e)) and game.sim.armor_for(e)>old_armor,"veteran panel uses live upgraded armor")
		if spec=="sky_heavy_tank":
			game.world.sync(.01,[id]);game.selected=[id];hud.refresh(game.sim,[id],game.camera,true,"",0.0);await frames();await capture("unit_brief")
		game.sim._kill_entity(id,false)
	game.audio.stop_all();game.queue_free();await frames()
	print("TABBED_MENU_UNIT_BRIEF_V4 ",JSON.stringify({"checks":checks,"failures":failures,"input":"actual root.push_input tab/button clicks"}))
	for message:String in failures:push_error(message)
	quit(0 if failures.is_empty() else 1)
