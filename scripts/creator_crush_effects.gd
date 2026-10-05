extends RefCounted

## A creator strike leaves broken plates instead of an intact death ghost.
## This is presentation only; destruction and collision stay in Simulation.
const VOLUME = preload("res://scripts/volume_models.gd")
static var fragments: Dictionary = {}

static func mark_deaths(world) -> void:
	for event: Dictionary in world.sim.events:
		if event.get("kind", "") != "death" or event.get("death_style", "") != "creator_crush" or not bool(event.get("destroyed", false)): continue
		var id: int = int(event.get("id", -1))
		if world.models.has(id): world.models[id].creator_crushed = true

static func spawn(world, model: Dictionary) -> void:
	var volume: Dictionary = model.get("volume", {})
	var dimensions: Vector3 = volume.get("dimensions", Vector3(.7, 1.4, .5))
	var width: float = clampf(dimensions.x, .7, 8.0)
	var depth: float = clampf(dimensions.z, .5, 8.0)
	var paint: Color = _paint(volume)
	var origin: Vector3 = model.root.global_position
	var heading: float = float(model.root.rotation.y)
	var count: int = 16 if model.kind == "building" else 12 if model.volumetric else 8
	for index: int in count:
		var angle: float = float(index) * 2.399963
		var spread: float = .18 + float(index % 4) * .12
		var offset := Vector3(cos(angle) * width * spread, .23 + float(index % 3) * .065, sin(angle) * depth * spread)
		_piece(world, origin + offset.rotated(Vector3.UP, heading), heading + angle,
			_fragment(paint, index % 4), Vector3(width * .16, 1.0, depth * .15), true)
	if model.kind == "unit" and model.spec.get("domain", "ground") == "ground" and model.spec.get("armor_class", "") == "armored":
		for side: float in [-1.0, 1.0]:
			var track := BoxMesh.new()
			track.size = Vector3(width * .18, .15, depth * .66)
			_piece(world, origin + Vector3(side * width * .33, .10, .10).rotated(Vector3.UP, heading), heading + side * .16, track, Vector3.ONE, false)

static func _piece(world, position: Vector3, heading: float, mesh: Mesh, scale: Vector3, vertex_paint: bool) -> void:
	var root := Node3D.new()
	world.add_child(root)
	root.position = position
	root.rotation.y = heading
	var graphic := MeshInstance3D.new()
	graphic.mesh = mesh
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = vertex_paint
	material.albedo_color = Color.WHITE if vertex_paint else Color("554e45")
	material.roughness = 1.0
	graphic.material_override = material
	graphic.scale = scale
	root.add_child(graphic)
	world._add_effect({"root":root, "graphic":graphic, "kind":"creator_rubble", "age":0.0, "base":scale, "life":6.0})

static func _paint(volume: Dictionary) -> Color:
	for instance in volume.get("meshes", []):
		if instance.mesh == null or instance.mesh.get_surface_count() == 0: continue
		var raw_colors: Variant = instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		if not raw_colors is PackedColorArray: continue
		var colors: PackedColorArray = raw_colors
		if colors.is_empty(): continue
		var average := Color(0, 0, 0, 1)
		var count: int = mini(96, colors.size())
		for index: int in count:
			var sample: Color = colors[index * colors.size() / count]
			average.r += sample.r / count
			average.g += sample.g / count
			average.b += sample.b / count
		return average.darkened(.12)
	return Color("a68b6b")

static func _fragment(paint: Color, variant: int) -> ArrayMesh:
	var key: String = paint.to_html() + ":" + str(variant)
	if fragments.has(key): return fragments[key]
	var craft = VOLUME.CraftMesh.new()
	var edge: Array[Vector2] = [Vector2(-.48, -.11), Vector2(-.29, -.19), Vector2(.11, -.16), Vector2(.46, -.04), Vector2(.30, .09), Vector2(.03, .15), Vector2(-.34, .10)]
	craft.prism(edge, .76 + .06 * variant, Vector3.ZERO, paint.lightened(.025 * variant))
	craft.box(Vector3(.09, .13, .06), Vector3(.41, .065, .39), paint.darkened(.20))
	fragments[key] = craft.mesh()
	return fragments[key]
