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
var _cliff_edges := PackedVector2Array()
var _cliff_lines := PackedVector2Array()
var _cliff_rect := Rect2()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "地形、矿柱与港湾为公共地理。敌军仅显示当前视野内目标；灰色建筑标记是上次侦察位置。"

func invalidate_map() -> void:
	# A loaded snapshot can contain an earlier terrain revision with the same
	# seed. Rebuild on explicit world replacement, not on every drawing frame.
	texture = null
	map_key = ""
	_domain_cache.clear()
	_outline_key.clear()
	_cliff_edges.clear()
	_cliff_lines.clear()
	_cliff_rect = Rect2()
	queue_redraw()

func _draw() -> void:
	if sim == null: return
	map_rect = Rect2(Vector2(5, 20), Vector2(maxf(1.0,size.x-10), maxf(1.0,size.y-25)))
	var font: Font = hud.theme_paper.default_font
	draw_string(font, Vector2(1, 14), "战场", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, PaperHUD.INK)
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
			var bounds := Rect2(p-Vector2(2.5,2.5), Vector2(5,5))
			if marker.remembered: draw_rect(bounds, col, false, 1.0)
			else: draw_rect(bounds, col)
		elif marker.domain == "air":
			draw_colored_polygon(PackedVector2Array([p + Vector2(0,-3.2), p + Vector2(2.8,2.2), p + Vector2(0,1.2), p + Vector2(-2.8,2.2)]), col)
		elif marker.domain == "naval": draw_colored_polygon(PackedVector2Array([p + Vector2(0,-2.5), p + Vector2(1.8,0), p + Vector2(0,2.5), p + Vector2(-1.8,0)]), col)
		else: draw_circle(p, 1.7, col)
		if not marker.remembered and selected_ids.has(marker.id): draw_circle(p, 4.2, Color("f5e9af"), false, 1.1)
	if camera != null:
		# The camera renders into a separate viewport. The HUD owns the root
		# screen coordinates used by ground_at.
		var main: Node = hud.get_parent()
		var battlefield: Rect2 = main.battlefield_rect()
		var outline_key:Array=[camera.global_transform,camera.fov,camera.h_offset,battlefield,map_rect,sim.map.size]
		if outline_key!=_outline_key:
			_outline_key=outline_key
			_outline.clear()
			for screen in [battlefield.position, Vector2(battlefield.end.x,battlefield.position.y),battlefield.end,Vector2(battlefield.position.x,battlefield.end.y)]:
				var p:Vector2=main.ground_at(screen)
				_outline.append(map_rect.position+Vector2(clampf(p.x,0,sim.map.size),clampf(p.y,0,sim.map.size))*scale_factor)
			_outline.append(_outline[0])
		if _outline.size()>1:draw_polyline(_outline,Color("eee4b8"),1.5,true)

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
		if int(e.get("transport_id", -1)) > 0 or float(e.get("hp", 0)) <= 0: continue
		records.append({"id": id, "pos": e.pos, "kind": e.kind, "team": int(e.team), "domain": str(sim.data_for(e.spec).get("domain", "ground")), "remembered": false})
	var memories: Array = sim.team_vision.get("last_known", [])
	if team < 0 or team >= memories.size(): return records
	for id: int in memories[team]:
		if sim.entity_visible_to(team, id): continue
		var memory: Dictionary = sim.last_known_enemy(team, id)
		if memory.get("kind") != "building" or not memory.get("pos") is Vector2: continue
		records.append({"id": id, "pos": memory.pos, "kind": "building", "team": -1, "domain": str(memory.get("domain", "ground")), "remembered": true})
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
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
		if map_rect.has_point(event.position):
			var p: Vector2 = (event.position-map_rect.position)/map_rect.size * float(sim.map.size)
			hud.action.emit("minimap",{"pos":p,"move":event.button_index==MOUSE_BUTTON_RIGHT})
		accept_event()
