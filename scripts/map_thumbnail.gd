extends TextureRect
class_name MapThumbnail

# Actual generated terrain, births, minerals and bridges. The background task
# returns only bytes; Image/texture resources are created on the main thread.
const Catalog = preload("res://scripts/battlefield_catalog.gd")
const RESOLUTION := 192
const CACHE_LIMIT := 16
static var _pixel_cache: Dictionary = {}
static var _cache_order: Array[String] = []
var source_key := ""
var source_metadata: Dictionary = {}
var pending_key := ""
var _thread: Thread
var _latest: Dictionary = {}
var _running_key := ""
var _delay := 0.0
var player_colors: Array[Color] = []
signal updated(metadata: Dictionary)

func _ready() -> void:
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func request(mode: String, seed: int, players: int = 2) -> void:
	var key: String = "%s/%d/%d" % [mode, seed, players]
	if key == source_key or key == pending_key: return
	pending_key = key
	_latest = {"mode":mode,"seed":seed,"players":players,"key":key}
	_delay = .12
	if _pixel_cache.has(key):
		_apply(_pixel_cache[key]); _latest.clear(); pending_key = ""

func set_player_colors(values: Array) -> void:
	player_colors.clear()
	for value in values: player_colors.append(value if value is Color else Color(str(value)))
	queue_redraw()

func _draw() -> void:
	if player_colors.is_empty() or source_metadata.is_empty(): return
	var side: float = minf(size.x, size.y)
	var origin: Vector2 = (size - Vector2.ONE * side) * .5
	for index in source_metadata.get("starts", []).size():
		var coordinates: Array = source_metadata.starts[index]
		var point: Vector2 = origin + Vector2(float(coordinates[0]),float(coordinates[1])) / float(source_metadata.size) * side
		draw_circle(point, 5.0 * side / RESOLUTION, Color("392c21"))
		draw_circle(point, 3.0 * side / RESOLUTION, player_colors[posmod(index, player_colors.size())])

func _process(delta: float) -> void:
	if _thread != null and not _thread.is_alive():
		var result: Dictionary = _thread.wait_to_finish()
		_thread = null
		_pixel_cache[str(result.key)] = result
		_cache_order.erase(str(result.key)); _cache_order.append(str(result.key))
		while _cache_order.size() > CACHE_LIMIT: _pixel_cache.erase(_cache_order.pop_front())
		if str(result.key) == pending_key:
			_apply(result); pending_key = ""; _latest.clear()
	if _thread != null or _latest.is_empty(): return
	_delay -= delta
	if _delay > 0.0: return
	_thread = Thread.new()
	_running_key = str(_latest.key)
	_thread.start(_generate.bind(_latest.duplicate()))

func _apply(result: Dictionary) -> void:
	var image := Image.create_from_data(RESOLUTION, RESOLUTION, false, Image.FORMAT_RGB8, result.pixels)
	texture = ImageTexture.create_from_image(image)
	source_key = str(result.key)
	source_metadata = {"mode":result.mode,"seed":result.seed,"players":result.players,"size":result.map_size,"starts":result.starts,"terrain_sha256":result.terrain_sha256,"source":"MapData.generate actual terrain"}
	queue_redraw()
	updated.emit(source_metadata)

static func _generate(request_value: Dictionary) -> Dictionary:
	var mode: String = str(request_value.mode)
	var map: Dictionary = MapData.generate(mode, int(request_value.seed), {"players":int(request_value.players)})
	var n: int = int(map.size)
	var profile: Dictionary = map.get("profile", {})
	var ground := Color(str(profile.get("ground", "879865")))
	var water := Color(str(profile.get("water", "437f8f")))
	var road := Color(str(profile.get("road", "b29d7b")))
	var pixels := PackedByteArray()
	pixels.resize(RESOLUTION * RESOLUTION * 3)
	var terrain_digest := PackedByteArray()
	terrain_digest.resize(n * n)
	for z in range(n):
		for x in range(n): terrain_digest[z*n+x] = int(map.terrain[z][x])
	for py in range(RESOLUTION):
		var z: int = mini(n - 1, int(float(py) / RESOLUTION * n))
		for px in range(RESOLUTION):
			var x: int = mini(n - 1, int(float(px) / RESOLUTION * n))
			var terrain: int = int(map.terrain[z][x])
			var color: Color = water if terrain == MapData.WATER else road if terrain == MapData.ROAD else ground.lightened(clampf(float(map.heights[z][x]) * .032, -.15, .22))
			if terrain == MapData.BLOCKED: color = ground.darkened(.35)
			if terrain == MapData.RAMP: color = ground.lightened(.2)
			_set_pixel(pixels, px, py, color)
	for mine: Variant in map.get("mines", []):
		var p: Variant = mine.get("pos", Vector2.ZERO) if mine is Dictionary else mine
		_dot(pixels, _map_pixel(p, n), 2, Color("536f89"))
	# The balance map has only four houses and small paired tree stands. Show
	# their actual footprints so the preview also explains its open lanes.
	if mode == "symmetric":
		for ruin: Dictionary in map.get("ruins", []):
			_dot(pixels, _map_pixel(ruin.pos, n), 1 if ruin.kind == "tree" else 2, Color("68865c") if ruin.kind == "tree" else Color("aa8054"))
	for bridge: Dictionary in map.get("bridges", []):
		var bounds: Array = bridge.get("bounds", [])
		if bounds.size() < 4: continue
		var a := Vector2i(int(float(bounds[0]) / n * RESOLUTION), int(float(bounds[1]) / n * RESOLUTION))
		var b := Vector2i(int(float(bounds[0] + bounds[2]) / n * RESOLUTION), int(float(bounds[1] + bounds[3]) / n * RESOLUTION))
		for y in range(a.y, b.y + 1):
			for x in range(a.x, b.x + 1): _set_pixel(pixels, x, y, Color("d8b577"))
	var colors: Array[Color] = [Color("e7ad42"), Color("41c7c6"), Color("af80d1"), Color("9bb85a")]
	for index in range(map.starts.size()):
		var start: Vector2i = _map_pixel(map.starts[index], n)
		_dot(pixels, start, 5, Color("392c21")); _dot(pixels, start, 3, colors[index % colors.size()])
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256); hash.update(terrain_digest)
	return {"key":request_value.key,"mode":mode,"seed":request_value.seed,"players":request_value.players,"map_size":n,"starts":map.starts,"terrain_sha256":hash.finish().hex_encode(),"pixels":pixels}

static func _map_pixel(p: Variant, map_size: int) -> Vector2i:
	var point: Vector2 = p if p is Vector2 else Vector2(float(p[0]), float(p[1]))
	return Vector2i(int(point.x / map_size * RESOLUTION), int(point.y / map_size * RESOLUTION))

static func _dot(pixels: PackedByteArray, center: Vector2i, radius: int, color: Color) -> void:
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			if Vector2i(x,y).distance_squared_to(center) <= radius*radius: _set_pixel(pixels,x,y,color)

static func _set_pixel(pixels: PackedByteArray, x: int, y: int, color: Color) -> void:
	if x < 0 or y < 0 or x >= RESOLUTION or y >= RESOLUTION: return
	var offset: int = (y * RESOLUTION + x) * 3
	pixels[offset] = color.r8; pixels[offset+1] = color.g8; pixels[offset+2] = color.b8

func _exit_tree() -> void:
	if _thread != null:
		_thread.wait_to_finish(); _thread = null
