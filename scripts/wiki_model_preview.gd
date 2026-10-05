extends Control
class_name WikiModelPreview

## A self-contained display case. It reads the registered art recipes only:
## no simulation, landscape, production, AI, or unit audio is started here.
const VOLUME = preload("res://scripts/volume_models.gd")
const PAPER_WORLD = preload("res://scripts/paper_world.gd")
const PAPER := Color("efdfbe")
const INK := Color("655442")

signal rotation_active_changed(active: bool)

var viewport: SubViewport
var camera: Camera3D
var stage: Node3D
var rotation_pivot: Node3D
var model_node: Node3D
var model_data: Dictionary = {}
var model_bounds := AABB()
var rotation_bounds := AABB()
var angle: float = 0.0
var auto_rotate: bool = true
var rotation_speed: float = 0.20
var preview_team: int = 0
var current_spec: Dictionary = {}
var current_kind: String = ""
var is_volumetric: bool = false
var rotation_active: bool:
	get: return auto_rotate
	set(value): set_rotation_active(value)

var _preview_enabled: bool = true
var _picture: TextureRect
var _platform: Node3D
var _paper_factory: PaperWorld
var _dragging: bool = false
var _platform_radius: float = 1.0


func _ready() -> void:
	custom_minimum_size.y = maxf(custom_minimum_size.y, 230.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	tooltip_text = "拖动旋转 · 双击复位"
	_ensure_scene()
	resized.connect(_resize_viewport)
	visibility_changed.connect(_sync_activity)
	_resize_viewport()
	_sync_activity()


func _ensure_scene() -> void:
	if viewport != null: return
	viewport = SubViewport.new()
	viewport.name = "WikiModelViewport"
	viewport.size = Vector2i(640, 400)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.handle_input_locally = false
	viewport.gui_disable_input = true
	viewport.physics_object_picking = false
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	stage = Node3D.new()
	stage.name = "WikiDisplayCase"
	viewport.add_child(stage)
	var world_environment := WorldEnvironment.new()
	world_environment.environment = Environment.new()
	var environment: Environment = world_environment.environment
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0, 0, 0, 0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("f0e2c4")
	environment.ambient_light_energy = 0.78
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	stage.add_child(world_environment)
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-53, -34, 0)
	key_light.light_color = Color("fff4dc")
	key_light.light_energy = 1.08
	key_light.shadow_enabled = true
	key_light.directional_shadow_max_distance = 64.0
	stage.add_child(key_light)
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-24, 137, 0)
	fill_light.light_color = Color("d9e4e1")
	fill_light.light_energy = 0.24
	stage.add_child(fill_light)
	rotation_pivot = Node3D.new()
	rotation_pivot.name = "Turntable"
	stage.add_child(rotation_pivot)
	camera = Camera3D.new()
	camera.name = "WikiCamera"
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.05
	camera.far = 160.0
	stage.add_child(camera)
	_picture = TextureRect.new()
	_picture.name = "ModelPicture"
	_picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_picture.texture = viewport.get_texture()
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_SCALE
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_picture)
	_paper_factory = PAPER_WORLD.new()
	_paper_factory.contours = JSON.parse_string(FileAccess.get_file_as_string(PaperWorld.CARD_DIR + "contours.json"))


func set_entry(spec: Dictionary, kind: String, team: int = 0) -> void:
	_ensure_scene()
	_release_model()
	current_spec = spec.duplicate(true)
	current_kind = "building" if kind in ["building", "buildings"] else "unit"
	preview_team = clampi(team, 0, 1)
	angle = 0.0
	_dragging = false
	rotation_pivot.rotation.y = angle
	if current_spec.is_empty():
		_sync_activity()
		return
	model_data = VOLUME.create_model(current_spec, current_kind, preview_team)
	is_volumetric = not model_data.is_empty()
	if is_volumetric:
		model_node = model_data.root
		# The gallery shows the complete harvester, including its registered ore.
		for cargo in model_data.get("cargo", []): cargo.visible = true
		_add_volume_borders()
	else:
		model_node = Node3D.new()
		model_node.name = "PaperInfantry"
		var dimensions: Vector2 = _paper_factory._dimensions(current_spec, current_kind)
		var graphic := MeshInstance3D.new()
		graphic.name = "OriginalPaperCard"
		var texture_path: String = _paper_factory._texture_path(current_spec, "idle")
		graphic.mesh = _paper_factory._card(str(current_spec.faction) + "_" + str(current_spec.art) + "_idle", dimensions.x, dimensions.y, texture_path, preview_team)
		graphic.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		model_node.add_child(graphic)
		model_data = {"root": model_node, "meshes": [graphic], "volumetric": false, "team": preview_team, "texture_path": texture_path}
	rotation_pivot.add_child(model_node)
	# Bounds come from every mesh and transform, not the recipe's approximate
	# dimensions. Gun barrels, flags, cargo and parked airfield planes count.
	var source_bounds: AABB = _collect_bounds(model_node)
	var center: Vector3 = source_bounds.get_center()
	model_node.position = Vector3(-center.x, -source_bounds.position.y, -center.z)
	model_bounds = _collect_bounds(model_node)
	var radius: float = 0.0
	for corner in range(8):
		var point: Vector3 = model_bounds.get_endpoint(corner)
		radius = maxf(radius, Vector2(point.x, point.z).length())
	_platform_radius = maxf(radius * 1.08, 0.85)
	_build_platform()
	# A cylindrical sweep encloses the full turn, so the camera does not pump
	# or crop the long end of a gun or a wing as the display rotates.
	rotation_bounds = AABB(Vector3(-_platform_radius, -0.14, -_platform_radius), Vector3(_platform_radius * 2.0, model_bounds.end.y + 0.14, _platform_radius * 2.0))
	_frame_camera()
	_sync_activity()
	queue_redraw()


func _add_volume_borders() -> void:
	for border in model_data.get("border_meshes", []):
		if border.mesh == null or border.mesh.get_surface_count() == 0: continue
		var source: MeshInstance3D = border.source
		for paper in [false, true]:
			var shell := MeshInstance3D.new()
			shell.name = "PaperOutline" if paper else "InkOutline"
			shell.mesh = border.mesh
			shell.material_override = _paper_factory._vehicle_border_material(paper)
			shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			source.add_child(shell)


func _collect_bounds(node: Node3D) -> AABB:
	var bounds := AABB()
	var first: bool = true
	for graphic: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if graphic.mesh == null or not graphic.visible: continue
		var transform_to_pivot := graphic.transform
		var ancestor: Node = graphic.get_parent()
		while ancestor is Node3D and ancestor != rotation_pivot:
			transform_to_pivot = ancestor.transform * transform_to_pivot
			ancestor = ancestor.get_parent()
		var part_bounds: AABB = transform_to_pivot * graphic.mesh.get_aabb()
		bounds = part_bounds if first else bounds.merge(part_bounds)
		first = false
	return bounds


func _build_platform() -> void:
	_platform = Node3D.new()
	_platform.name = "PaperBlueprintPlinth"
	rotation_pivot.add_child(_platform)
	var board := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = _platform_radius
	disc.bottom_radius = _platform_radius
	disc.height = 0.12
	disc.radial_segments = 80
	board.mesh = disc
	board.position.y = -0.065
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color("e0c79b")
	paper.roughness = 1.0
	board.material_override = paper
	_platform.add_child(board)
	var diagram := ImmediateMesh.new()
	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.albedo_color = Color("a59878")
	diagram.surface_begin(Mesh.PRIMITIVE_LINES, line_material)
	var spacing: float = maxf(_platform_radius / 7.0, 0.18)
	for index in range(-7, 8):
		var coordinate: float = float(index) * spacing
		if absf(coordinate) >= _platform_radius: continue
		var length: float = sqrt(_platform_radius * _platform_radius - coordinate * coordinate) * 0.98
		diagram.surface_add_vertex(Vector3(coordinate, -0.003, -length))
		diagram.surface_add_vertex(Vector3(coordinate, -0.003, length))
		diagram.surface_add_vertex(Vector3(-length, -0.003, coordinate))
		diagram.surface_add_vertex(Vector3(length, -0.003, coordinate))
	for step in range(80):
		var a: float = TAU * float(step) / 80.0
		var b: float = TAU * float(step + 1) / 80.0
		diagram.surface_add_vertex(Vector3(cos(a), 0, sin(a)) * _platform_radius * 0.97)
		diagram.surface_add_vertex(Vector3(cos(b), 0, sin(b)) * _platform_radius * 0.97)
	diagram.surface_end()
	var grid := MeshInstance3D.new()
	grid.mesh = diagram
	grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_platform.add_child(grid)


func _frame_camera() -> void:
	if camera == null or model_node == null: return
	var target: Vector3 = rotation_bounds.get_center()
	# Original infantry begins facing the viewer, with a low elevation that
	# reveals the cardboard base without turning the figure into a billboard.
	var view_direction: Vector3 = (Vector3(6, 4.7, 8) if is_volumetric else Vector3(0, 0.24, 1)).normalized()
	camera.position = target + view_direction * maxf(12.0, rotation_bounds.size.length() * 3.0)
	camera.basis = Basis.looking_at(-view_direction, Vector3.UP)
	var extent := Vector2.ZERO
	var inverse: Basis = camera.basis.inverse()
	for corner in range(8):
		var projected: Vector3 = inverse * (rotation_bounds.get_endpoint(corner) - target)
		extent.x = maxf(extent.x, absf(projected.x))
		extent.y = maxf(extent.y, absf(projected.y))
	var aspect: float = float(viewport.size.x) / maxf(1.0, float(viewport.size.y))
	camera.size = maxf(extent.y * 2.0, extent.x * 2.0 / aspect) * 1.18
	_request_redraw()


func get_model_bounds(rotated: bool = false) -> AABB:
	return rotation_pivot.transform * model_bounds if rotated and rotation_pivot != null else model_bounds


func get_preview_bounds() -> AABB:
	return rotation_bounds


func set_preview_team(team: int) -> void:
	team = clampi(team, 0, 1)
	if team == preview_team: return
	if current_spec.is_empty():
		preview_team = team
		return
	var previous_angle: float = angle
	set_entry(current_spec, current_kind, team)
	angle = previous_angle
	rotation_pivot.rotation.y = angle
	_request_redraw()


func toggle_rotation() -> bool:
	set_rotation_active(not auto_rotate)
	return auto_rotate


func set_rotation_active(active: bool) -> void:
	if auto_rotate == active: return
	auto_rotate = active
	_sync_activity()
	rotation_active_changed.emit(auto_rotate)


func reset_rotation() -> void:
	angle = 0.0
	if rotation_pivot != null: rotation_pivot.rotation.y = angle
	_request_redraw()


func set_preview_active(active: bool) -> void:
	_preview_enabled = active
	if not active: _dragging = false
	_sync_activity()


func clear_preview() -> void:
	_release_model()
	current_spec.clear()
	current_kind = ""
	angle = 0.0
	_dragging = false
	if rotation_pivot != null: rotation_pivot.rotation.y = angle
	_sync_activity()
	queue_redraw()


func _release_model() -> void:
	if is_instance_valid(model_node): model_node.free()
	model_node = null
	model_data.clear()
	if is_instance_valid(_platform): _platform.free()
	_platform = null
	model_bounds = AABB()
	rotation_bounds = AABB()
	is_volumetric = false


func _is_preview_active() -> bool:
	return _preview_enabled and is_inside_tree() and is_visible_in_tree() and model_node != null


func _sync_activity() -> void:
	var active: bool = _is_preview_active()
	set_process(active and auto_rotate)
	if viewport == null: return
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active and auto_rotate else (SubViewport.UPDATE_ONCE if active else SubViewport.UPDATE_DISABLED)
	if not active: _dragging = false


func _request_redraw() -> void:
	if viewport != null and _is_preview_active():
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if auto_rotate else SubViewport.UPDATE_ONCE


func _resize_viewport() -> void:
	if viewport == null: return
	var desired: Vector2 = Vector2(maxf(size.x, 2.0), maxf(size.y, 2.0))
	var render_scale: float = minf(1.0, 1600.0 / maxf(desired.x, desired.y))
	viewport.size = Vector2i(maxi(2, roundi(desired.x * render_scale)), maxi(2, roundi(desired.y * render_scale)))
	_frame_camera()
	queue_redraw()


func _process(delta: float) -> void:
	if not _is_preview_active() or not auto_rotate or _dragging: return
	angle = fposmod(angle + delta * rotation_speed, TAU)
	rotation_pivot.rotation.y = angle


func _gui_input(event: InputEvent) -> void:
	if not _is_preview_active(): return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
			if event.double_click and event.pressed:
				_dragging = false
				reset_rotation()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			reset_rotation()
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		if not Rect2(Vector2.ZERO, size).has_point(event.position):
			_dragging = false
			return
		angle = fposmod(angle + event.relative.x * 0.009, TAU)
		rotation_pivot.rotation.y = angle
		_request_redraw()
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	# A quiet blueprint texture remains behind the transparent model viewport.
	for x in range(18, ceili(size.x), 36):
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.47, 0.55, 0.52, 0.08))
	for y in range(18, ceili(size.y), 36):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.47, 0.55, 0.52, 0.08))
	draw_rect(Rect2(Vector2.ONE * 9.0, size - Vector2.ONE * 18.0), Color(0.40, 0.34, 0.26, 0.16), false, 1.0)
	for corner in [Vector2(10, 10), Vector2(size.x - 10, 10), Vector2(10, size.y - 10), size - Vector2.ONE * 10.0]:
		var direction := Vector2(1 if corner.x < size.x * 0.5 else -1, 1 if corner.y < size.y * 0.5 else -1)
		draw_line(corner, corner + Vector2(direction.x * 16.0, 0), INK, 1.0)
		draw_line(corner, corner + Vector2(0, direction.y * 16.0), INK, 1.0)


func _exit_tree() -> void:
	set_process(false)
	if viewport != null: viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _enter_tree() -> void:
	call_deferred("_sync_activity")


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_paper_factory):
		_paper_factory.card_cache.clear()
		_paper_factory.material_cache.clear()
		_paper_factory.free()
		_paper_factory = null
