extends SceneTree

const HUD = preload("res://scripts/paper_hud.gd")
const Thumbnail = preload("res://scripts/map_thumbnail.gd")
var checks := 0
var failures: Array[String] = []
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)
func run() -> void:
	root.size=Vector2i(1440,810)
	var hud=HUD.new();root.add_child(hud)
	await process_frame
	hud.show_menu(true)
	var reviewed: Dictionary={"players":3,"slots":[{"faction":"sky","control":"human","difficulty":"normal"},{"faction":"iron","control":"ai","difficulty":"hard"},{"faction":"kestrel","control":"ai","difficulty":"easy"}]}
	for index: int in reviewed.slots.size():reviewed.slots[index].color=PaperHUD.PLAYER_COLORS[index].to_html(false)
	hud.select_faction("sky");hud.select_map("islands");hud.match_setup.restore(reviewed)
	hud.seed_input.text="901";hud._request_map_preview()
	var deadline:int=Time.get_ticks_msec()+20000
	var responsive_frames:=0
	while hud.map_thumbnail.source_key!="islands/901/3" and Time.get_ticks_msec()<deadline:
		await process_frame
		responsive_frames+=1
	check(hud.map_thumbnail.texture!=null and hud.map_thumbnail.source_key=="islands/901/3","Adjacent thumbnail uses reviewed actual map/seed/player layout")
	check(responsive_frames>2,"Map generation yields to normal UI frames")
	var expected: Dictionary=Thumbnail._generate({"mode":"islands","seed":901,"players":3,"key":"islands/901/3"})
	check(hud.map_thumbnail.source_metadata.terrain_sha256==expected.terrain_sha256 and hud.map_thumbnail.source_metadata.starts==expected.starts,"Thumbnail topology and births are identical to MapData.generate")
	check(hud.match_setup.options("sky")==reviewed,"Preview rendering does not change reviewed slots/preferences")
	var calls:Array=[];hud.action.connect(func(kind,value):calls.append({"kind":kind,"value":value}))
	hud.start_button.pressed.emit()
	check(calls.back().kind=="start" and calls.back().value.mode=="islands" and calls.back().value.seed==901 and calls.back().value.match_options==reviewed,"Native start emits exact faction/map/seed/opponents contract")
	for dimensions:Vector2i in [Vector2i(1440,810),Vector2i(1100,700)]:
		root.size=dimensions
		for frame in range(3):await process_frame
		check(root.get_visible_rect().encloses(hud.menu.get_global_rect()),"New battle paper sheet fits supported window: "+str(dimensions))
		check(hud.menu.get_global_rect().encloses(hud.map_thumbnail.get_global_rect()),"Real map thumbnail stays beside settings inside sheet: "+str(dimensions))
	var snapshot:Dictionary={"duration":185.0,"map_mode":"forest","result":"win","history_complete":false,"since_time":30.0,"teams":[{"team":0,"faction":"sky","units_killed":12,"units_lost":3,"buildings_destroyed":4,"buildings_lost":1,"units_produced":17,"buildings_built":8,"funds_earned":7200,"funds_spent":5600,"money_remaining":1600,"alive_units":14,"alive_buildings":7,"damage_dealt":4210},{"team":1,"faction":"iron","units_killed":3,"units_lost":12,"buildings_destroyed":1,"buildings_lost":4,"units_produced":15,"buildings_built":4,"funds_earned":6800,"funds_spent":6200,"money_remaining":600,"alive_units":3,"alive_buildings":0,"damage_dealt":2140}]}
	var before:Dictionary=snapshot.duplicate(true)
	hud.scoreboard.show_result(snapshot,"win")
	await process_frame
	check(hud.scoreboard.visible and hud.scoreboard.displayed_result=="win","Result page opens inside the original window from authoritative statistics")
	check(hud.scoreboard.displayed_stats==before and snapshot==before,"Result display cannot mutate match statistics")
	check(hud.scoreboard.summary_label.text.contains("03:05") and hud.scoreboard.summary_label.text.contains("从读取时开始统计"),"Duration and partial save-history scope are explicit")
	var labels:Array=[]
	for node in hud.scoreboard.find_children("","Label",true,false):labels.append(node.text)
	check(labels.has("净投入") and labels.has("击杀部队") and labels.has("建成建筑") and labels.has("1600"),"Score table contains actual combat/production/economic fields")
	hud.scoreboard.new_battle_button.pressed.emit()
	check(not hud.scoreboard.visible and calls.back().kind=="entry_play","New battle closes the settlement page and invokes normal setup flow")
	hud.scoreboard.show_result(snapshot,"lose");hud.scoreboard.menu_button.pressed.emit()
	check(not hud.scoreboard.visible and calls.back().kind=="entry_home","Menu action uses normal entry navigation")
	hud.scoreboard.show_result(snapshot,"draw");hud.scoreboard.quit_button.pressed.emit()
	check(calls.back().kind=="quit","Quit closes the process through the ordinary authorized action")
	hud.queue_free();await process_frame
	call_deferred("finish")
func finish() -> void:
	await process_frame
	print("NEW_BATTLE_SCOREBOARD ",JSON.stringify({"checks":checks,"failures":failures}))
	for failure:String in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
