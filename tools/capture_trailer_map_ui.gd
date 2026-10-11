extends SceneTree
## Controlled capture of the production main scene and English HUD on the
## unmodified 320-cell Forest map. All camera movement happens between shots.
const Main = preload("res://scripts/main.gd")
const Localize = preload("res://scripts/localization.gd")
const OUT = "res://artifacts/trailer_revision_20261011/map_ui/"
const FPS: int = 30
const SIZE = Vector2i(1600,900)
var app
var hq: int = -1
var barracks: int = -1
var squad: int = -1
var base: Vector2
var motion: bool = false
var actions: Array = []
var shots: Array = []
var failures: Array[String] = []
var map_identity: String = ""

func _initialize() -> void:
	if OS.get_environment("PAPER_FRONT_CAPTURE_OFFSCREEN") != "1":
		printerr("Use the private offscreen capture launcher with the shared capture.lock.")
		quit(2)
		return
	call_deferred("run")

func progress(stage: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	FileAccess.open(OUT+"progress.json",FileAccess.WRITE).store_string(JSON.stringify({"stage":stage,"ticks_usec":Time.get_ticks_usec()}))
	print("MAP_UI_CAPTURE ",stage)

func require(ok: bool, label: String) -> bool:
	if not ok:
		failures.append(label)
		push_error(label)
	return ok

func own(spec: String) -> int:
	for e: Dictionary in app.sim.entities.values():
		if int(e.team) == 0 and str(e.spec) == spec: return int(e.id)
	return -1

func select(ids: Array) -> void:
	app.selected = app.selectable_squad(ids)
	app.inspected_bridge = -1
	app.inspected_ruin = -1
	app.hud.cache_key = ""
	refresh()

func refresh() -> void:
	app.hud.refresh(app.sim,app.selected,app.camera,false,"",0.0,-1,false)
	app.overlay.sim = app.sim
	app.overlay.camera = app.camera
	app.overlay.selection = app.selected
	app.overlay.command = app.command_mode
	app.overlay.refresh_overlay()

func advance(seconds: float) -> void:
	for tick: int in ceili(seconds*30.0): app.sim.step(1.0/30.0)

func construct(spec: String, desired: Vector2) -> int:
	select([hq])
	var before: float = app.sim.money[0]
	app.handle_action("build",{"spec":spec,"channel":"normal"})
	if not require(not app.sim.order_for_team(0,"normal").is_empty(),"normal paid construction order exists: "+spec): return -1
	actions.append({"phase":"preroll","action":"build","spec":spec,"funds_before":before,"funds_after":app.sim.money[0],"sim_time":app.sim.time})
	for tick: int in 2400:
		app.sim.step(1.0/30.0)
		if bool(app.sim.order_for_team(0,"normal").get("ready",false)): break
	var candidates: Array[Vector2] = []
	for z: int in range(-20,21,2):
		for x: int in range(-20,21,2): candidates.append(base+Vector2(x,z))
	candidates.sort_custom(func(a,b):return a.distance_squared_to(desired)<b.distance_squared_to(desired))
	for point: Vector2 in candidates:
		var site: Vector2 = app.sim.snap_build_position(0,point,"normal")
		if app.sim.placement_error(0,site,"normal").is_empty():
			if not require(app.sim.place_building(0,site,"normal").is_empty(),"normal placement succeeds: "+spec): return -1
			advance(2.0)
			return own(spec)
	require(false,"a legal normal construction site exists: "+spec)
	return -1

func camera_at(point: Vector2, zoom: float, pitch: float, orbit: float) -> void:
	app.focus = point
	app.distance = zoom
	app.yaw = orbit
	app.camera_pitch_mode = "fixed"
	app.camera_pitch = pitch
	app._camera_pitch_blending = false
	app.update_camera()
	app.hud.mini.update_camera_outline(app.camera,app.sim,MapData.height_at(app.sim.map,point))

func transform_data() -> Dictionary:
	var t: Transform3D = app.camera.global_transform
	return {"position":[t.origin.x,t.origin.y,t.origin.z],"basis":[t.basis.x.x,t.basis.x.y,t.basis.x.z,t.basis.y.x,t.basis.y.y,t.basis.y.z,t.basis.z.x,t.basis.z.y,t.basis.z.z],"fov":app.camera.fov,"h_offset":app.camera.h_offset,"focus":[app.focus.x,app.focus.y],"distance":app.distance,"pitch":app.camera_pitch,"yaw":app.yaw}

func render_frame(delta: float) -> void:
	app.world.sync(delta,app.selected,{})
	app.sim.events.clear()
	refresh()
	await process_frame
	await RenderingServer.frame_post_draw

func save_pixels(path: String) -> void:
	var image: Image = root.get_texture().get_image()
	require(image.get_size() == SIZE,"capture preserves full 1600x900 viewport")
	require(image.save_png(path)==OK,"save capture "+path)

func capture(name: String, frames: int, interaction: bool=false) -> void:
	progress("Preparing fixed shot "+name)
	var folder: String = OUT+name+"/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for warmup: int in 8: await render_frame(0.0)
	var camera_before: Dictionary = transform_data()
	var origin: Transform3D = app.camera.global_transform
	var maximum_position_drift: float = 0.0
	var maximum_basis_drift: float = 0.0
	var began: float = app.sim.time
	var capture_frames: int = frames if motion else 1
	for frame: int in capture_frames:
		if interaction: apply_interaction(frame)
		if motion: app.sim.step(1.0/FPS)
		await render_frame(1.0/FPS if motion else 0.0)
		var current: Transform3D = app.camera.global_transform
		maximum_position_drift=maxf(maximum_position_drift,current.origin.distance_to(origin.origin))
		maximum_basis_drift=maxf(maximum_basis_drift,maxf(current.basis.x.distance_to(origin.basis.x),maxf(current.basis.y.distance_to(origin.basis.y),current.basis.z.distance_to(origin.basis.z))))
		save_pixels(folder+"%04d.png"%frame if motion else OUT+name+"_qa.png")
		if frame%30==0: progress("Captured "+name+" frame "+str(frame)+"/"+str(capture_frames))
	require(maximum_position_drift==0.0 and maximum_basis_drift==0.0,"camera is exactly fixed throughout "+name)
	shots.append({"name":name,"path":ProjectSettings.globalize_path(folder if motion else OUT+name+"_qa.png"),"frames":capture_frames,"fps":FPS,"duration":float(capture_frames)/FPS,"map_mode":app.sim.map.mode,"map_size":app.sim.map.size,"sim_time_start":began,"sim_time_end":app.sim.time,"camera_start":camera_before,"camera_end":transform_data(),"max_camera_position_drift":maximum_position_drift,"max_camera_basis_drift":maximum_basis_drift,"selected":app.selected.duplicate(),"full_hud":true,"ui_language":Localize.language(),"production_cards":app.hud.entry_widgets.keys()})

func apply_interaction(frame: int) -> void:
	if frame == 0:
		select([hq])
		actions.append({"shot":"interface","frame":frame,"seconds":float(frame)/FPS,"action":"select_headquarters","id":hq,"sim_time":app.sim.time})
	elif frame == 18:
		var funds: float = app.sim.money[0]
		app.handle_action("build",{"spec":"kestrel_power","channel":"normal"})
		require(not app.sim.order_for_team(0,"normal").is_empty(),"recorded HUD interaction starts a normal power order")
		actions.append({"shot":"interface","frame":frame,"seconds":float(frame)/FPS,"action":"normal_build_handler","spec":"kestrel_power","funds_before":funds,"funds_after":app.sim.money[0],"sim_time":app.sim.time})
	elif frame == 45:
		select([barracks])
		actions.append({"shot":"interface","frame":frame,"seconds":float(frame)/FPS,"action":"select_barracks","id":barracks,"sim_time":app.sim.time})
	elif frame == 54:
		var funds: float = app.sim.money[0]
		app.handle_action("produce","kestrel_rifle")
		require(not app.sim.entities[barracks].queue.is_empty(),"recorded HUD interaction pays for a real infantry squad")
		actions.append({"shot":"interface","frame":frame,"seconds":float(frame)/FPS,"action":"normal_produce_handler","spec":"kestrel_rifle","members":app.sim.squad_size("kestrel_rifle"),"funds_before":funds,"funds_after":app.sim.money[0],"order_time":app.sim.production_time("kestrel_rifle"),"sim_time":app.sim.time})
	elif frame == 81:
		select([squad])
		var destination: Vector2 = app.sim._near_stand(base+Vector2(7,17),.5,-1,8.0)
		require(app.command_units("move",destination),"production main issues the selected squad's ordinary move command")
		actions.append({"shot":"interface","frame":frame,"seconds":float(frame)/FPS,"action":"normal_squad_move","ids":app.selected.duplicate(),"destination":[destination.x,destination.y],"sim_time":app.sim.time})

func run() -> void:
	motion=OS.get_environment("PAPER_FRONT_TRAILER_MAP_UI_MOTION")=="1"
	progress("Loading production main scene")
	root.size=SIZE
	root.content_scale_size=SIZE
	app=Main.new()
	app.render_overlap_enabled=false
	root.add_child(app)
	app.set_process(false)
	app.set_physics_process(false)
	app.set_process_input(false)
	app.set_process_unhandled_input(false)
	Localize.set_language("en")
	app.audio.muted=true
	app.hud.show_entry(false)
	app.hud.show_menu(false)
	for warmup: int in 4: await process_frame
	progress("Building unmodified Forest 320 map")
	if not require(await app.start_match_with_loading("forest",73026,"kestrel",{"vision_enabled":false}),"production main starts Forest match"): await app.quit_game(1);return
	app.sim.synchronous_path_tests=true
	app.sim.ai_enabled=false
	app.hud.show_menu(false)
	app.hud.show_entry(false)
	# Offline PNG throughput is not a gameplay performance measurement.
	app.performance_overlay.screen.hide()
	app.hud.fps_label.hide()
	app.debug_panel.hide()
	app.lens.dof_blur_near_enabled=false
	app.lens.dof_blur_far_enabled=false
	base=app.sim._team_start(0)
	hq=own("kestrel_hq")
	map_identity=JSON.stringify({"size":app.sim.map.size,"terrain":app.sim.map.terrain,"heights":app.sim.map.heights,"bridges":app.sim.map.bridges,"roads":app.sim.map.get("road_mark_cells",{})}).sha256_text()
	progress("Preparing an ordinary paid mid-match base")
	construct("kestrel_power",base+Vector2(-9,-4))
	barracks=construct("kestrel_barracks",base+Vector2(9,0))
	construct("kestrel_refinery",base+Vector2(-8,11))
	select([barracks])
	app.handle_action("produce","kestrel_rifle")
	for tick: int in 2100:
		app.sim.step(1.0/30.0)
		squad=own("kestrel_rifle")
		if squad>0 and app.sim.entities[barracks].queue.is_empty() and app.sim.squad_members(squad).all(func(id):return not bool(app.sim.entities[id].get("emerging",false))):break
	require(squad>0 and app.sim.squad_members(squad).size()==app.sim.squad_size("kestrel_rifle"),"paid pre-roll physically recruits the complete squad")
	app.sim.notices.clear()
	app.feedback.clear()
	select([hq])
	camera_at(Vector2(139,166),180,45,.20)
	await capture("river_structure",75)
	camera_at(Vector2(66,42),108,38,-.40)
	await capture("ridge_structure",75)
	camera_at(base+Vector2(2,7),53,36,-.18)
	select([hq])
	if motion:
		await capture("interface",135,true)
	else:
		await capture("interface_headquarters",1)
		apply_interaction(18)
		apply_interaction(45)
		apply_interaction(54)
		await capture("interface_production",1)
		apply_interaction(81)
		advance(.5)
		await capture("interface_squad",1)
	var unchanged: String = JSON.stringify({"size":app.sim.map.size,"terrain":app.sim.map.terrain,"heights":app.sim.map.heights,"bridges":app.sim.map.bridges,"roads":app.sim.map.get("road_mark_cells",{})}).sha256_text()
	require(unchanged==map_identity,"formal terrain, height, river, bridge and road data remain unchanged")
	var anchors: Dictionary={"river_structure":[[955,353,100,20],[1190,300,80,100],[1030,120,120,30]],"ridge_structure":[[880,360,130,70],[740,440,60,50],[290,445,90,100]],"interface":[[640,340,130,70],[170,400,140,100],[1030,360,150,100]]}
	var manifest: Dictionary={"scope":"Controlled demonstration of current production main/PaperWorld and real English HUD. Formal 320 Forest map, ordinary paid pre-roll construction and infantry production, AI disabled and full visibility for readable terrain. No map flattening, fake UI, camera shake, panning or zooming. Normal handlers/selection interfaces drive recorded interactions.","godot":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"device":RenderingServer.get_video_adapter_name(),"resolution":[SIZE.x,SIZE.y],"fps":FPS,"offline_fps_diagnostic_hidden":true,"static_background_anchor_rects_xywh":anchors,"map_mode":"forest","map_size":app.sim.map.size,"map_seed":73026,"map_geometry_sha256":map_identity,"geometry_unchanged":unchanged==map_identity,"mode":"motion" if motion else "stills","shots":shots,"actions":actions,"failures":failures}
	FileAccess.open(OUT+("capture_manifest.json" if motion else "stills_manifest.json"),FileAccess.WRITE).store_string(JSON.stringify(manifest,"\t"))
	progress("Completed "+("motion" if motion else "stills")+" capture")
	await app.quit_game(0 if failures.is_empty() else 1)
