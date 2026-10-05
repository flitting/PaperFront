extends Control
const PATHS = preload("res://scripts/selection_paths.gd")
var start := Vector2.ZERO
var finish := Vector2.ZERO
var active := false
var command: String = ""
var projector: Node3D
var selection: Array = []
var _selected_routes: Array[Dictionary] = []
var _paint_key:Array=[]
var _unit_circle:PackedVector2Array=PackedVector2Array()
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for index in range(21):_unit_circle.append(Vector2.from_angle(float(index)*TAU/20.0))

func refresh_overlay() -> void:
	var key:Array=[active,start,finish,command,collisions,size,global_position]
	var next_routes: Array[Dictionary] = []
	if sim != null and not selection.is_empty(): next_routes = PATHS.selected_routes(sim.entities, selection, sim.rules)
	_selected_routes = next_routes
	key.append(_selected_routes)
	if not _selected_routes.is_empty() and camera != null:
		key.append_array([camera.global_transform, camera.fov, camera.size, camera.projection, camera.h_offset, camera.v_offset, get_viewport().get_visible_rect()])
		# The projector owns the battlefield SubViewport-to-client transform.
		if projector != null and projector.has_method("battlefield_rect"): key.append(projector.battlefield_rect())
	if not command.is_empty():key.append(get_viewport().get_mouse_position())
	if collisions and sim!=null and camera!=null:key.append_array([sim.time,camera.global_transform])
	if key!=_paint_key:
		_paint_key=key
		queue_redraw()
func _draw() -> void:
	draw_selected_paths()
	draw_collisions()
	if active:
		var r := Rect2(start - global_position, finish-start).abs()
		draw_rect(r, Color(0.91,0.68,0.26,0.12))
		draw_rect(r, PaperHUD.PLAYER_COLORS[0], false, 2)
	if not command.is_empty():
		var mouse := get_viewport().get_mouse_position() - global_position
		if command=="force_move":
			draw_circle(mouse,12,Color("67c5d9"),false,2)
			draw_line(mouse+Vector2(-17,17),mouse+Vector2(14,-14),Color("67c5d9"),3)
			draw_line(mouse+Vector2(14,-14),mouse+Vector2(1,-14),Color("67c5d9"),3)
			draw_line(mouse+Vector2(14,-14),mouse+Vector2(14,-1),Color("67c5d9"),3)
		else:
			draw_circle(mouse,12,Color("a64d36") if command=="force_attack" else Color("f7dc97"),false,2)
			draw_line(mouse-Vector2(17,0),mouse+Vector2(17,0),Color("a64d36"),2)
			draw_line(mouse-Vector2(0,17),mouse+Vector2(0,17),Color("a64d36"),2)

var sim: WarSimulation
var camera: Camera3D
var collisions: bool = false

func draw_selected_paths() -> void:
	if sim == null or camera == null or projector == null: return
	for route in _selected_routes:
		var color: Color = VolumeModels.player_color(int(route.team)).lightened(.25)
		if str(route.kind) in ["attack", "force_attack", "attack_move"]: color = color.lerp(Color("de8760"), .50)
		elif str(route.kind) == "patrol": color = color.lerp(Color("84d9bc"), .45)
		color.a = .82 if bool(route.planned) else .44
		var points3: PackedVector3Array = PATHS.ground_points(route.points, sim.map, .09, str(route.get("domain","ground")))
		for section in projected_route_sections(points3): _draw_route_section(section, color, bool(route.planned))

func projected_route_sections(points: PackedVector3Array) -> Array[PackedVector2Array]:
	var sections: Array[PackedVector2Array] = []
	var visible := PackedVector2Array()
	for point in points:
		if camera.is_position_behind(point):
			if visible.size() > 1: sections.append(visible)
			visible = PackedVector2Array()
		else: visible.append(projector.project_world_to_screen(point) - global_position)
	if visible.size() > 1: sections.append(visible)
	return sections

func _draw_route_section(points: PackedVector2Array, color: Color, planned: bool) -> void:
	for segment in PATHS.dashed_segments(points, 8.0 if planned else 5.0, 5.0):
		draw_line(segment[0], segment[1], Color(.16, .13, .10, color.a * .7), 3.5, true)
		draw_line(segment[0], segment[1], color, 1.7, true)
	if points.size() > 1: draw_circle(points[points.size() - 1], 3.0 if planned else 2.5, color, false, 1.3, true)

func draw_collisions() -> void:
	if not collisions or sim==null or camera==null:return
	for e in sim.entities.values():
		if int(e.get("transport_id", -1)) > 0: continue
		var d:Dictionary=sim.data_for(e.spec)
		var points:=PackedVector2Array()
		var h:float=MapData.height_at(sim.map,e.pos)+0.04
		if str(d.get("domain", "ground")) == "air": h += float(e.get("flight_height", d.get("flight_height", 4.0)))
		if camera.is_position_behind(Vector3(e.pos.x,h,e.pos.y)):continue
		if e.kind=="building":
			var half:float=float(d.size)*0.5
			for v in [Vector2(-half,-half),Vector2(half,-half),Vector2(half,half),Vector2(-half,half),Vector2(-half,-half)]:
				points.append(projector.project_world_to_screen(Vector3(e.pos.x+v.x,h,e.pos.y+v.y)) - global_position)
		else:
			for point in _unit_circle:
				var v:Vector2=point*float(d.radius)
				points.append(projector.project_world_to_screen(Vector3(e.pos.x+v.x,h,e.pos.y+v.y)) - global_position)
		draw_polyline(points,VolumeModels.player_color(int(e.team)),1.5,true)
