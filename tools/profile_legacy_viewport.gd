extends SceneTree

## Diagnostic only: restore v11's declared-texture sizing mistake while retaining
## the actual game simulation, native output, camera, lighting and lens settings.
## This is intentionally excessive rendering and is not an acceptance benchmark.
var game: Node3D
var legacy_active: bool = false
var logged_size: Vector2i = Vector2i.ZERO

func _initialize() -> void:
	call_deferred("start")

func start() -> void:
	game = load("res://main.tscn").instantiate()
	root.add_child(game)
	for i in range(8):
		await process_frame
	legacy_active = true
	apply_legacy_size()

func apply_legacy_size() -> void:
	var rect: Rect2 = game.battlefield_rect()
	var logical_size: Vector2 = root.get_visible_rect().size
	var declared_pixels: Vector2i = root.get_texture().get_size()
	var dock_pixels: int = roundi((logical_size.x - rect.size.x) * float(declared_pixels.x) / maxf(1.0, logical_size.x))
	var render_size := Vector2i(maxi(2, declared_pixels.x - dock_pixels), maxi(2, declared_pixels.y))
	if game.battlefield_viewport.size != render_size:
		game.battlefield_viewport.size = render_size
	if logged_size != render_size:
		logged_size = render_size
		print("LEGACY_OVERSAMPLING_DIAGNOSTIC ", JSON.stringify({"acceptance": false, "window_pixels": root.size, "logical_viewport": logical_size, "declared_texture_pixels": declared_pixels, "legacy_battlefield_pixels": render_size}))

func _process(_delta: float) -> bool:
	if legacy_active and is_instance_valid(game):
		apply_legacy_size()
	return false
