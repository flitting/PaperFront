extends SceneTree

const Mini = preload("res://scripts/minimap.gd")
var checks := 0
var failures: Array[String] = []
var terrain_draws := 0
var outline_draws := 0
var click_payloads: Array[Dictionary] = []

class CameraGame:
	extends "res://scripts/main.gd"
	var terrain_raycasts := 0
	func ground_at(screen: Vector2) -> Vector2:
		terrain_raycasts += 1
		return super.ground_at(screen)

class VisibleSimulation:
	extends "res://scripts/simulation.gd"
	func entity_visible_to(team: int, id: int) -> bool:
		return entities.has(id) and (int(entities[id].get("visible_to",0)) & (1<<team)) != 0
	func last_known_enemy(team: int, id: int) -> Dictionary:
		return team_vision.last_known[team].get(id,{})

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label)

func flat_map(size: int) -> Dictionary:
	var map := {"size":size,"seed":73026,"mode":"dev","terrain":[],"heights":[],"starts":[[20.5,30.5],[299.5,30.5]]}
	for z: int in size:
		var heights: Array[float] = []
		var terrain: Array[int] = []
		heights.resize(size); heights.fill(0.0)
		terrain.resize(size); terrain.fill(MapData.LAND)
		map.heights.append(heights); map.terrain.append(terrain)
	return map

func nearest_polygon_distance(point: Vector2, polygon: PackedVector2Array) -> float:
	var nearest := INF
	for index: int in polygon.size():
		nearest = minf(nearest,point.distance_to(Geometry2D.get_closest_point_to_segment(point,polygon[index],polygon[(index+1)%polygon.size()])))
	return nearest

func run() -> void:
	root.size = Vector2i(1920,1080)
	var game := CameraGame.new()
	root.add_child(game)
	game.set_process(false); game.set_physics_process(false)
	game.audio.muted = true
	game.started = true
	game.hud.show_menu(false); game.hud.show_entry(false)
	var sim := VisibleSimulation.new()
	sim.setup(RulesLoader.load_rules(),"dev",7,"rivet",false)
	sim.ai_enabled = false
	sim.map = flat_map(320)
	sim.entities.clear(); sim._building_entities.clear(); sim.bridges.clear(); sim.mines.clear()
	game.sim = sim
	game.focus = Vector2(160,160); game.distance = 40; game.camera_pitch = 40; game.yaw = 0
	game._refresh_camera_reference(); game.update_camera()
	var mini = game.hud.mini
	mini.update_camera_outline(game.camera,sim,game.camera_reference_height)
	mini.draw.connect(func():terrain_draws+=1)
	mini._camera_outline.draw.connect(func():outline_draws+=1)
	game.hud.action.connect(func(kind: String,value: Variant):if kind=="minimap":click_payloads.append(value.duplicate()))
	await process_frame; await process_frame
	check(mini._outline_world.size()==4,"ordinary fixed-plane view has four camera corners")
	# Independently intersect each actual viewport corner ray with the plane.
	var viewport_size: Vector2 = game.camera.get_viewport().get_visible_rect().size
	var plane := Plane(Vector3.UP,game.camera_reference_height)
	for pixel: Vector2 in [Vector2.ZERO,Vector2(viewport_size.x,0),viewport_size,Vector2(0,viewport_size.y)]:
		var hit: Variant = plane.intersects_ray(game.camera.project_ray_origin(pixel),game.camera.project_ray_normal(pixel))
		check(hit is Vector3 and nearest_polygon_distance(Vector2(hit.x,hit.z),mini._outline_world)<.002,"minimap footprint matches the actual viewport corner ray")
	var original_world: PackedVector2Array = mini._outline_world.duplicate()
	for z: int in 320: sim.map.heights[z][160] = 14.8
	mini._outline_key.clear()
	mini.update_camera_outline(game.camera,sim,game.camera_reference_height)
	check(mini._outline_world==original_world,"terrain cliffs never change a fixed-camera footprint")
	var baseline_draws: int = terrain_draws
	var baseline_outline_draws: int = outline_draws
	var original_texture: ImageTexture = mini.texture
	var previous: PackedVector2Array = mini._outline_world.duplicate()
	var previous_height: float = MapData.height_at(sim.map,game.focus)
	var previous_distance: float = game.camera_actual_distance
	for frame: int in 24:
		game.focus.x += .30
		game.update_camera()
		var focus_height: float = MapData.height_at(sim.map,game.focus)
		mini.update_camera_outline(game.camera,sim,focus_height)
		var actual: PackedVector2Array = mini._outline_world
		var maximum_error := 0.0
		var focus_plane := Plane(Vector3.UP,focus_height)
		for pixel: Vector2 in [Vector2.ZERO,Vector2(viewport_size.x,0),viewport_size,Vector2(0,viewport_size.y)]:
			var hit: Variant = focus_plane.intersects_ray(game.camera.project_ray_origin(pixel),game.camera.project_ray_normal(pixel))
			maximum_error = maxf(maximum_error,nearest_polygon_distance(Vector2(hit.x,hit.z),actual) if hit is Vector3 else INF)
		check(maximum_error<.003,"each panning frame matches the actual viewport at local focus height")
		if is_equal_approx(focus_height,previous_height) and is_equal_approx(game.camera_actual_distance,previous_distance):
			maximum_error=0.0
			for point: Vector2 in previous: maximum_error=maxf(maximum_error,nearest_polygon_distance(point+Vector2(.30,0),actual))
			check(maximum_error<.003,"unobstructed flat-terrain panning translates the footprint smoothly")
		previous=actual.duplicate()
		previous_height=focus_height
		previous_distance=game.camera_actual_distance
		await process_frame
	var pan_terrain_draws:int=terrain_draws-baseline_draws
	var pan_outline_draws:int=outline_draws-baseline_outline_draws
	check(terrain_draws==baseline_draws,"camera motion redraws no terrain or entity-marker CanvasItem")
	check(outline_draws>=baseline_outline_draws+23,"outline updates every frame without the 150ms HUD refresh")
	check(mini.texture==original_texture,"panning reuses the cached terrain image")
	check(game.terrain_raycasts==0,"minimap camera updates never call terrain ground_at rays")
	var before_zoom: PackedVector2Array = mini._outline.duplicate()
	game.distance=110; game.camera_pitch=20; game.update_camera()
	mini.update_camera_outline(game.camera,sim,game.camera_reference_height)
	check(mini._outline!=before_zoom,"zoom updates the footprint immediately")
	check(mini._outline_world.size()>=3,"near-horizon overview produces a valid bounded footprint")
	for point: Vector2 in mini._outline_world:
		check(point.is_finite() and point.x>=0 and point.y>=0 and point.x<=320 and point.y<=320,"horizon/far-plane footprint remains finite and inside map")
	# Outline cache tracks the complete projection, including orthographic size
	# and lens offsets, even when the camera transform remains unchanged.
	game.camera.projection=Camera3D.PROJECTION_ORTHOGONAL; game.camera.size=30
	mini.update_camera_outline(game.camera,sim,0)
	var before_size: PackedVector2Array=mini._outline.duplicate()
	game.camera.size=60; mini.update_camera_outline(game.camera,sim,0)
	check(mini._outline!=before_size,"orthographic size invalidates the outline projection cache")
	var before_offset: PackedVector2Array=mini._outline.duplicate()
	game.camera.h_offset=4; mini.update_camera_outline(game.camera,sim,0)
	check(mini._outline!=before_offset,"lens offsets invalidate the outline transform cache")
	game.camera.h_offset=0; game.camera.projection=Camera3D.PROJECTION_PERSPECTIVE
	for window_size: Vector2i in [Vector2i(1920,1080),Vector2i(1280,800)]:
		root.size=window_size
		await process_frame; await process_frame
		game.resize_battlefield(); game.update_camera()
		mini.update_camera_outline(game.camera,sim,0)
		check(mini.map_rect.size.is_equal_approx(Vector2(mini.size.x-10,mini.size.y-25)),"resized minimap bounds reflect current layout without waiting for terrain draw")
		var fraction := Vector2(.36,.61)
		var local: Vector2=mini.map_rect.position+mini.map_rect.size*fraction
		var screen: Vector2=mini.get_global_transform()*local
		var event:=InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;event.position=screen
		root.push_input(event,true)
		event=event.duplicate();event.pressed=false;root.push_input(event,true)
		await process_frame
		check(game.focus.distance_to(fraction*320)<.05,"real GUI click respects minimap offsets at each window size")
		var right:=InputEventMouseButton.new()
		right.button_index=MOUSE_BUTTON_RIGHT;right.pressed=true;right.position=local
		mini._gui_input(right)
		check(not click_payloads.is_empty() and click_payloads.back().move and (click_payloads.back().pos as Vector2).distance_to(fraction*320)<.001,"right click preserves the exact movement destination payload")
	# Existing marker visibility/domain behavior is independent of the overlay.
	var friend: int=sim._spawn(0,"rivet_rifle",Vector2(100,100),true)
	var naval: int=sim._spawn(0,"rivet_ship_frigate",Vector2(110,100),true)
	var air: int=sim._spawn(0,"rivet_fighter",Vector2(120,100),true)
	var hidden: int=sim._spawn(1,"kestrel_tank",Vector2(130,100),true)
	sim.entities[hidden].visible_to=2
	sim.team_vision={"last_known":[{999:{"pos":Vector2(140,100),"kind":"building","domain":"ground"}},{}]}
	var markers: Array[Dictionary]=mini.marker_records(0)
	check(markers.any(func(item):return item.id==friend and item.domain=="ground"),"friendly ground markers remain visible")
	check(markers.any(func(item):return item.id==naval and item.domain=="naval"),"naval minimap markers preserve their domain")
	check(markers.any(func(item):return item.id==air and item.domain=="air"),"air minimap markers preserve their domain")
	check(not markers.any(func(item):return item.id==hidden),"hidden enemies do not leak their live marker")
	check(markers.any(func(item):return item.id==999 and item.remembered),"remembered building markers remain last-known records")
	# Headless CPU timing of the actual outline update, with changed camera pose
	# on every call. This measures neither rendering FPS nor GPU performance.
	var samples: Array[int]=[]
	for index: int in 2200:
		game.camera.position.x+=.01
		var begin:=Time.get_ticks_usec()
		mini.update_camera_outline(game.camera,sim,0)
		var elapsed:int=Time.get_ticks_usec()-begin
		if index>=200:samples.append(elapsed)
	samples.sort()
	var timing := {"samples":samples.size(),"outline_update_p50_us":samples[1000],"outline_update_p95_us":samples[1900],"outline_update_p99_us":samples[1980],"terrain_draws_during_24_pan_frames":pan_terrain_draws,"outline_draws_during_24_pan_frames":pan_outline_draws,"scope":"headless changed-camera CPU outline update; no FPS/GPU claim"}
	print("MINIMAP_CAMERA_TIMING ",JSON.stringify(timing))
	print("MINIMAP_CAMERA_TESTS ",JSON.stringify({"checks":checks,"failures":failures}))
	game.queue_free();await process_frame
	for failure: String in failures:push_error(failure)
	quit(0 if failures.is_empty() else 1)
