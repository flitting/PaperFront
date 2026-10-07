extends SceneTree

var failures: Array[String]=[]
var checks:=0

func expect(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node3D=load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.audio.muted=true
	game.set_process(false)
	game.set_physics_process(false)
	expect(game.hud.entry_menu.visible and not game.hud.menu.visible,"Fresh launch has a dedicated entry menu")
	expect(not game.started and not game.hud.wiki.visible,"Opening screen does not begin a match")
	game.handle_action("wiki",null)
	var wiki: PaperWiki=game.hud.wiki
	await process_frame
	expect(wiki.visible and not game.hud.entry_menu.visible,"Entry menu opens the army Wiki")
	var configured_entries:int=game.rules.units.values().filter(func(info):return not bool(info.get("roster_hidden",false))).size()+game.rules.buildings.size()
	expect(wiki.current_entries.size()==configured_entries and wiki.entry_buttons.size()==configured_entries,"Every current-roster unit and building is browsable")
	for id:String in game.rules.units:
		if bool(game.rules.units[id].get("roster_hidden",false)):
			expect(not wiki.current_entries.any(func(entry):return entry.id==id),"Retired ship is absent from the actual Wiki: "+id)
	expect(wiki.selected_id=="kestrel_hq" and wiki.preview.model_node!=null,"First Wiki page displays the canon HQ model")
	var original_rules: Dictionary=game.rules.duplicate(true)
	for entry in wiki.current_entries:
		wiki.select_entry(entry.id)
		expect(wiki.selected_id==entry.id and wiki.preview.model_node!=null,"Selectable live model: "+entry.id)
		expect(wiki.description_label.text==entry.spec.description,"Correct introduction: "+entry.id)
		var shown: Dictionary={}
		for row in wiki.displayed_rows:
			if not str(row.get("source_path","")).is_empty():shown[row.source_path]=true
		var category: String="units" if entry.kind=="unit" else "buildings"
		for key in entry.spec:
			if key in preload("res://scripts/wiki_catalog.gd").TECHNICAL_FIELDS:continue
			if entry.spec[key] is bool or entry.spec[key] is int or entry.spec[key] is float:
				expect(shown.has(category+"."+entry.id+"."+str(key)),"Numeric row in actual UI: "+entry.id+"/"+str(key))
		if not str(entry.spec.weapon).is_empty():
			for key in ["damage","interval","range","blast","speed"]:
				expect(shown.has("weapons."+str(entry.spec.weapon)+"."+key),"Weapon value in actual UI: "+entry.id+"/"+key)
	expect(game.rules==original_rules,"Browsing every Wiki entry never mutates game rules")
	wiki.faction_filter.select(2);wiki.kind_filter.select(2);wiki._rebuild_entries()
	var rivet_buildings:int=game.rules.buildings.values().filter(func(spec):return spec.faction=="rivet").size()
	expect(wiki.current_entries.size()==rivet_buildings and wiki.current_entries.all(func(e):return e.kind=="building" and e.spec.faction=="rivet"),"Faction and building filters combine and retain the entire configured group")
	wiki.search.text="绝无此条目";wiki._rebuild_entries()
	expect(wiki.current_entries.is_empty() and wiki.selected_id.is_empty() and wiki.preview.model_node==null and wiki.displayed_rows.is_empty(),"Empty search releases the previous model and table")
	wiki.search.text="";wiki.faction_filter.select(0);wiki.kind_filter.select(0);wiki._rebuild_entries("kestrel_fighter")
	expect(wiki.selected_id=="kestrel_fighter" and wiki.displayed_rows.any(func(r):return str(r.value).contains("空中")),"Aircraft page has its combat domain")
	for dimensions in [Vector2i(1600,900),Vector2i(1100,700),Vector2i(1920,1080)]:
		root.size=dimensions
		for frame in range(3):await process_frame
		var logical:=root.get_visible_rect()
		expect(logical.encloses(wiki.preview.get_global_rect()),"Model preview remains inside window: "+str(dimensions))
		expect(wiki.detail_scroll.size.y>170,"Introduction/table stays readable at window: "+str(dimensions))
		expect(wiki.preview.get_global_rect().end.y<=wiki.detail_scroll.get_global_rect().position.y,"Model stays above its introduction/table")
		wiki.select_entry("rivet_bomber")
		for frame in range(2):await process_frame
		expect(wiki.detail_scroll.get_v_scroll_bar().max_value>wiki.detail_scroll.size.y,"Full numerical table can be scrolled")
	wiki.close_catalog()
	expect(game.hud.entry_menu.visible and not wiki.visible,"Closing entry Wiki returns to entry menu")
	expect(wiki.preview.model_node==null and wiki.preview.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,"Closing Wiki releases the model and disables rendering")
	game.handle_action("entry_play",null)
	expect(game.hud.menu.visible and not game.hud.entry_menu.visible and not game.started,"Start entry opens match configuration")
	var escape:=InputEventKey.new();escape.pressed=true;escape.keycode=KEY_ESCAPE
	game._unhandled_input(escape)
	expect(game.hud.entry_menu.visible,"Escape from pregame settings returns to entry")
	game.start_match("dev",24,"kestrel",true);game.hud.show_menu(true)
	game.sim.rules.units.kestrel_tank.cost+=123
	game.pve_paused=false
	var before_time: float=game.sim.time
	game.handle_action("wiki",null)
	expect(game.pve_paused and wiki.visible,"In-game Wiki temporarily pauses the battle")
	expect(wiki.rules.units.kestrel_tank.cost==original_rules.units.kestrel_tank.cost,"Wiki reads current catalog rather than a historical battle snapshot")
	game._physics_process(.3)
	expect(game.sim.time==before_time,"Reading the Wiki does not advance battle time")
	var distance: float=game.distance
	var wheel:=InputEventMouseButton.new();wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;wheel.pressed=true;wheel.position=wiki.preview.get_global_rect().get_center()
	game._unhandled_input(wheel)
	expect(game.distance==distance and not game.dragging,"Wiki mouse input never reaches battlefield controls")
	wiki.close_catalog()
	expect(not game.pve_paused and game.hud.menu.visible,"Closing Wiki restores an unpaused battle and its previous menu")
	game.pve_paused=true;game.handle_action("wiki",null);wiki.close_catalog()
	expect(game.pve_paused,"A battle already paused before Wiki remains paused")
	game.handle_action("entry_home",null);game.handle_action("entry_resume",null)
	expect(not game.hud.entry_menu.visible and game.pve_paused,"Entry resume preserves the user's pause state")
	game.queue_free()
	await process_frame
	print("WIKI_UI ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
