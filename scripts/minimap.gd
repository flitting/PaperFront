extends Control

var hud: PaperHUD
var sim: WarSimulation
var camera: Camera3D
var texture: ImageTexture
var map_key: String = ""
var map_rect := Rect2()
const TERRAIN_COLORS:Array[Color]=[Color("bb9e6c"),Color("79959c"),Color("ddc18c"),Color("e6ce99"),Color("818260")]
const CLIFF_DROP := 0.75
const CLIFF_INK := Color("684c35")
const CLIFF_PAPER := Color("f1d9a6")
const BIOME = preload("res://scripts/biome_scenery.gd")
const MAP = preload("res://scripts/map_data.gd")
const MEMORY_COLOR := Color("8e8980")
var _domain_cache:Dictionary={}
var _outline_key:Array=[]
var _outline:PackedVector2Array=PackedVector2Array()
var _outline_world:PackedVector2Array=PackedVector2Array()
var _camera_reference_height:float=0.0
class CameraOutline:
	extends Control
	var points := PackedVector2Array()
	func set_points(value: PackedVector2Array) -> void:
		if points == value: return
		# Packed arrays are shared references; retain a private snapshot so the
		# parent rebuilding its outline cannot mutate our redraw comparison.
		points = value.duplicate()
		queue_redraw()
	func _draw() -> void:
		if points.size()>1: draw_polyline(points,Color("eee4b8"),1.5,true)
var _camera_outline:CameraOutline
var _cliff_edges := PackedVector2Array()
var _cliff_lines := PackedVector2Array()
var _cliff_rect := Rect2()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "地形、矿柱与港湾为公共地理。敌军仅显示当前视野内目标；灰色建筑标记是上次侦察位置。"
	_camera_outline=CameraOutline.new()
	_camera_outline.name="CameraFootprint"
	_camera_outline.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(_camera_outline)
	_camera_outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_on_minimap_resized)
	_refresh_map_rect()

func _refresh_map_rect() -> void:
	map_rect=Rect2(Vector2(5,20),Vector2(maxf(1.0,size.x-10),maxf(1.0,size.y-25)))

func _on_minimap_resized() -> void:
	_refresh_map_rect()
	_outline_key.clear()
	_refresh_camera_outline()
	queue_redraw()

## Called after the gameplay camera changes, independently of HUD refresh.
## Only the small outline CanvasItem redraws while the camera moves.
func update_camera_outline(view:Camera3D,simulation:WarSimulation,reference_height:float) -> void:
	if sim!=simulation: invalidate_map()
	sim=simulation
	camera=view
	_camera_reference_height=reference_height
	_refresh_map_rect()
	_refresh_camera_outline()

func _refresh_camera_outline() -> void:
	if sim==null or camera==null or not is_instance_valid(_camera_outline):return
	var key:Array=[camera.get_camera_transform(),camera.get_camera_projection(),map_rect,int(sim.map.size),_camera_reference_height]
	if key==_outline_key:return
	_outline_key=key
	_outline_world=camera_footprint(camera,float(sim.map.size),_camera_reference_height)
	_outline.clear()
	var scale_factor:Vector2=map_rect.size/float(sim.map.size)
	for point:Vector2 in _outline_world:_outline.append(map_rect.position+point*scale_factor)
	if _outline.size()>1:_outline.append(_outline[0])
	_camera_outline.set_points(_outline)

## Intersect the fixed map plane with the actual view frustum. Clipping a
## bounded polygon also handles corners above the horizon and the far plane,
## without unstable terrain hits or unbounded projected rays.
static func camera_footprint(view:Camera3D,map_size:float,reference_height:float) -> PackedVector2Array:
	var polygon:=PackedVector2Array([Vector2.ZERO,Vector2(map_size,0),Vector2(map_size,map_size),Vector2(0,map_size)])
	var transform:Transform3D=view.get_camera_transform()
	var inside:Vector3=transform.origin-transform.basis.z*maxf(view.near*2.0,1.0)
	for plane:Plane in view.get_frustum():
		if polygon.is_empty():break
		var side:float=1.0 if plane.distance_to(inside)>=0.0 else -1.0
		var clipped:=PackedVector2Array()
		var previous:Vector2=polygon[polygon.size()-1]
		var previous_distance:float=plane.distance_to(Vector3(previous.x,reference_height,previous.y))*side
		for point:Vector2 in polygon:
			var distance:float=plane.distance_to(Vector3(point.x,reference_height,point.y))*side
			var previous_inside:bool=previous_distance>=0.0
			var point_inside:bool=distance>=0.0
			if previous_inside!=point_inside:
				clipped.append(previous.lerp(point,previous_distance/(previous_distance-distance)))
			if point_inside:clipped.append(point)
			previous=point
			previous_distance=distance
		polygon=clipped
	for index:int in polygon.size():polygon[index]=polygon[index].clamp(Vector2.ZERO,Vector2.ONE*map_size)
	return polygon

func invalidate_map() -> void:
	# A loaded snapshot can contain an earlier terrain revision with the same
	# seed. Rebuild on explicit world replacement, not on every drawing frame.
	texture = null
	map_key = ""
	_domain_cache.clear()
	_outline_key.clear()
	_outline.clear()
	_outline_world.clear()
	if is_instance_valid(_camera_outline):_camera_outline.set_points(_outline)
	_cliff_edges.clear()
	_cliff_lines.clear()
	_cliff_rect = Rect2()
	queue_redraw()

func _draw() -> void:
	if sim == null: return
	_refresh_map_rect()
	var font: Font = hud.theme_paper.default_font
	draw_string(font, Vector2(1, 14), tr("战场"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, PaperHUD.INK)
	var key := str(sim.map.seed) + str(sim.map.mode) + str(sim.map.get("profile", {}).get("players", 2))
	if texture == null or key != map_key:
		map_key = key
		make_texture()
	draw_texture_rect(texture, map_rect, false)
	var scale_factor: Vector2 = map_rect.size / float(sim.map.size)
	if not _cliff_edges.is_empty():
		if _cliff_rect != map_rect:
			_cliff_rect = map_rect
			_cliff_lines.resize(_cliff_edges.size())
			for index in _cliff_edges.size():
				_cliff_lines[index] = map_rect.position + _cliff_edges[index] * scale_factor
		# Screen-space strokes remain legible even when a 640-cell map shrinks
		# to a small paper. Terrain is cached; markers stay on top of the rim.
		draw_multiline(_cliff_lines, CLIFF_PAPER, 2.6, true)
		draw_multiline(_cliff_lines, CLIFF_INK, 1.0, true)
	draw_rect(map_rect, PaperHUD.INK, false, 2)
	var selected_ids:Dictionary={}
	for id in hud.selection:selected_ids[id]=true
	for b in sim.bridges:
		var bounds: Array = b.bounds
		var r := Rect2(map_rect.position + Vector2(bounds[0], bounds[1])*scale_factor, Vector2(bounds[2], bounds[3])*scale_factor)
		draw_rect(r, Color("d1b478") if b.alive else Color("6b4e3e"))
	for m in sim.mines:
		var p: Vector2 = map_rect.position + m.pos*scale_factor
		draw_circle(p, 2.5, Color("567a86"))
	for harbor: Dictionary in sim.map.get("harbors", []):
		var p: Vector2 = map_rect.position + (harbor.water_pos as Vector2) * scale_factor
		draw_circle(p, 3.0, Color("3f6976"), false, 1.0)
		draw_line(p + Vector2(-2, 0), p + Vector2(2, 0), Color("dce0cf"), 1.0)
		draw_line(p + Vector2(0, -2), p + Vector2(0, 2), Color("dce0cf"), 1.0)
	for marker: Dictionary in marker_records(0):
		var p: Vector2 = map_rect.position + (marker.pos as Vector2) * scale_factor
		var col: Color = MEMORY_COLOR if marker.remembered else VolumeModels.player_color(int(marker.team))
		if marker.kind == "building":
			var base: bool = str(marker.get("role", "")) in ["hq", "outpost"]
			if base:
				var radius: float = 6.0 if str(marker.role) == "hq" else 3.8
				draw_circle(p,radius,Color("161512"))
				draw_circle(p,radius-1.1,col)
				draw_circle(p,radius*.48,Color("161512"))
				draw_circle(p,maxf(.8,radius*.48-1.0),col)
			else:
				var bounds := Rect2(p-Vector2.ONE*2.5,Vector2.ONE*5.0)
				if marker.remembered: draw_rect(bounds,col,false,1.0)
				else: draw_rect(bounds,col)
		elif marker.domain == "air":
			draw_colored_polygon(PackedVector2Array([p + Vector2(0,-3.2), p + Vector2(2.8,2.2), p + Vector2(0,1.2), p + Vector2(-2.8,2.2)]), col)
		elif marker.domain == "naval": draw_colored_polygon(PackedVector2Array([p + Vector2(0,-2.5), p + Vector2(1.8,0), p + Vector2(0,2.5), p + Vector2(-1.8,0)]), col)
		else: draw_circle(p, 1.7, col)
		if not marker.remembered and selected_ids.has(marker.id): draw_circle(p, 4.2, Color("f5e9af"), false, 1.1)

func _air_unit(spec:String) -> bool:
	if not _domain_cache.has(spec):_domain_cache[spec]=sim.data_for(spec).get("domain","ground")=="air"
	return bool(_domain_cache[spec])


## Visibility is checked before reading live position, health or spec. Memory
## markers read only the last observed record, including destroyed unseen sites.
func marker_records(team: int = 0) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	if sim == null: return records
	for id: int in sim.entities:
		if not sim.entity_visible_to(team, id): continue
		var e: Dictionary = sim.entities[id]
		if int(e.get("transport_id", -1)) > 0 or int(e.get("garrison_id",-1)) >= 0 or float(e.get("hp", 0)) <= 0: continue
		records.append({"id": id, "pos": e.pos, "kind": e.kind, "team": int(e.team), "domain": str(sim.data_for(e.spec).get("domain", "ground")), "role":str(sim.data_for(e.spec).get("role", "")), "remembered": false})
	var memories: Array = sim.team_vision.get("last_known", [])
	if team < 0 or team >= memories.size(): return records
	for id: int in memories[team]:
		if sim.entity_visible_to(team, id): continue
		var memory: Dictionary = sim.last_known_enemy(team, id)
		if memory.get("kind") != "building" or not memory.get("pos") is Vector2: continue
		records.append({"id": id, "pos": memory.pos, "kind": "building", "team": -1, "domain": str(memory.get("domain", "ground")), "role":str(sim.data_for(str(memory.get("spec", ""))).get("role", "")), "remembered": true})
	return records

func make_texture() -> void:
	var s: int = sim.map.size
	var img := Image.create(s,s,false,Image.FORMAT_RGBA8)
	var land_colors:Dictionary={0.0:TERRAIN_COLORS[0]}
	for z in range(s):
		for x in range(s):
			var h: float = sim.map.heights[z][x]
			var t: int = sim.map.terrain[z][x]
			var color:Color
			if sim.map.has("profile"):
				color = Color(str(sim.map.profile.water)) if t == 1 else BIOME.ground_color(sim.map, Vector2(x + .5, z + .5), t, 0.0)
			elif t==0:
				if not land_colors.has(h):land_colors[h]=TERRAIN_COLORS[0].lightened(h*.025)
				color=land_colors[h]
			else:color=TERRAIN_COLORS[clampi(t,0,TERRAIN_COLORS.size()-1)]
			img.set_pixel(x,z,color)
	texture = ImageTexture.create_from_image(img)
	_cache_cliff_edges(s)

func _cache_cliff_edges(s: int) -> void:
	_cliff_edges.clear()
	_cliff_lines.clear()
	_cliff_rect = Rect2()
	# Merge collinear boundaries once per map. Small ramp steps stay open,
	# while the steep walls beside ramps use the same rule as other cliffs.
	for z in range(s - 1):
		var start := -1
		for x in range(s):
			var cliff := absf(_cliff_height(x, z) - _cliff_height(x, z + 1)) > CLIFF_DROP
			if cliff and start < 0:
				start = x
			elif not cliff and start >= 0:
				_cliff_edges.append(Vector2(start, z + 1))
				_cliff_edges.append(Vector2(x, z + 1))
				start = -1
		if start >= 0:
			_cliff_edges.append(Vector2(start, z + 1))
			_cliff_edges.append(Vector2(s, z + 1))
	for x in range(s - 1):
		var start := -1
		for z in range(s):
			var cliff := absf(_cliff_height(x, z) - _cliff_height(x + 1, z)) > CLIFF_DROP
			if cliff and start < 0:
				start = z
			elif not cliff and start >= 0:
				_cliff_edges.append(Vector2(x + 1, start))
				_cliff_edges.append(Vector2(x + 1, z))
				start = -1
		if start >= 0:
			_cliff_edges.append(Vector2(x + 1, start))
			_cliff_edges.append(Vector2(x + 1, s))


func _cliff_height(x: int, z: int) -> float:
	if sim.map.has("profile") and int(sim.map.terrain[z][x]) == MAP.WATER:
		return MAP.water_surface_y(sim.map, Vector2(x + .5, z + .5))
	return float(sim.map.heights[z][x])

func _gui_input(event: InputEvent) -> void:
	if sim == null: return
	_refresh_map_rect()
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
		if map_rect.has_point(event.position):
			var p: Vector2 = (event.position-map_rect.position)/map_rect.size * float(sim.map.size)
			hud.action.emit("minimap",{"pos":p,"move":event.button_index==MOUSE_BUTTON_RIGHT})
		accept_event()
