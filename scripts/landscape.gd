class_name PaperLandscape
extends Node3D

# Original painted miniature tabletop scenery. Simulation is read-only here: every
# navigable surface samples MapData, while water, props and cut faces are art.
const BRIDGE_CRAFT = preload("res://scripts/bridge_craft.gd")
const SCENERY_SCALE = preload("res://scripts/scenery_scale.gd")
const CLIFF_CRAFT = preload("res://scripts/cliff_craft.gd")
const PINE = preload("res://scripts/pine_model.gd")
const MAP = preload("res://scripts/map_data.gd")
const TERRAIN_DISK_CACHE = preload("res://scripts/terrain_resource_cache.gd")
const NORTH_CONTEXT = preload("res://scripts/north_context.gd")
const FOREGROUND_GROVE = preload("res://scripts/foreground_grove.gd")
const CONTEXT_PROPS = preload("res://scripts/contextual_props.gd")
const BIOME_SCENERY = preload("res://scripts/biome_scenery.gd")
const ENVIRONMENT_MODELS = preload("res://scripts/city_environment_models.gd")
const CHUNK: int = 32
const PROP_CHUNK: int = 16
const ENVIRONMENT_CHUNK: int = 32
const TREE_LOD_BIAS: float = 0.30
const WATER_DEPTH: float = 2.65
const LOAD_YIELD_BUDGET_USEC: int = 24000
static var _terrain_cache: Dictionary = {}
var bridge_visuals: Dictionary = {}
var ruin_visuals: Dictionary = {}
var tree_visuals: Dictionary = {}
var _tree_cells: Dictionary = {}
var _tree_alive: Dictionary = {}
var _ruin_ids_by_position: Dictionary = {}
var _ruin_alive: Dictionary = {}
var _resources_initialized: bool = false
var _forest_lods: Array[Dictionary] = []
var _trunk_lods: Array[Dictionary] = []
var full_trunk_ink:bool=OS.get_environment("PAPER_FRONT_FULL_TRUNK_INK")=="1"
var quality_mode: String = "native"
var terrain_disk_cache_enabled:bool=OS.get_environment("PAPER_FRONT_DISABLE_TERRAIN_CACHE")!="1"
var mine_visuals: Array[Node3D] = []
var stats: Dictionary = {"terrain_triangles": 0, "prop_instances": 0, "prop_draws": 0, "ground_chunks": 0, "resource_full_scans": 0, "resource_updates": 0, "terrain_cache_hit": false, "shadow_cap_triangles": 0, "terrain_shadow_triangles": 0, "tree_shadow_batches": 0, "tree_far_shadow_triangles": 0}
var _map: Dictionary
var _meshes: Dictionary = {}
var _batches: Dictionary = {}
var _materials: Dictionary = {}
var _ground_colors: Dictionary = {}
var _ground_contexts: Dictionary = {}
var _ground_paint_samples: Dictionary = {}
var _terrain_features: Dictionary = {}
var _terrain_features_ready: bool = false
var _ground_marks: Dictionary = {}
var _ground_islands: Dictionary = {}
var _ground_island_centres: Array[Dictionary] = []
var _ground_run_centres: Array[Vector2] = []
var _ground_earth_marks: Dictionary = {}
var _ground_exclusions: Array[Dictionary] = []
var _surface_corners: Dictionary = {}
var _accent_cells: Dictionary = {}
var _north_prop_cells: Dictionary = {}
var _mine_buckets: Array[int] = []
var _noise: FastNoiseLite = FastNoiseLite.new()
var _water_profiles: Dictionary = {}
var _civilian_batches: Array[Dictionary] = []


static func build(sim: WarSimulation) -> Node3D:
	var landscape: Node3D = (load("res://scripts/landscape.gd") as Script).new()
	landscape.name = "PaperLandscape"
	landscape._build(sim)
	return landscape


static func build_with_progress(sim: WarSimulation, progress: Callable) -> Node3D:
	if not progress.is_valid(): return build(sim)
	var landscape: Node3D = (load("res://scripts/landscape.gd") as Script).new()
	landscape.name = "PaperLandscape"
	await landscape._build_with_progress(sim, progress)
	return landscape


func sync_resources(sim: WarSimulation, force: bool = false) -> void:
	sync_environment(sim.time)
	# A match/load does one complete reconciliation. During play, only actual
	# destruction events touch forest slots, independent of total map area.
	if force or not _resources_initialized:
		stats.resource_full_scans = int(stats.resource_full_scans) + 1
		for ruin in sim.ruins: _sync_ruin(ruin)
		_resources_initialized = true
	else:
		for event in sim.events:
			if event.get("kind") != "ruin_destroy": continue
			var id: int = int(event.get("id", _ruin_ids_by_position.get(event.get("pos"), -1)))
			if id >= 0 and id < sim.ruins.size(): _sync_ruin(sim.ruins[id])
	for bridge: Dictionary in sim.bridges:
		if bridge_visuals.has(int(bridge.id)):
			var visual: Dictionary = bridge_visuals[int(bridge.id)]
			var alive: bool = bool(bridge.alive)
			if bool(visual.alive) != alive:
				visual.deck.visible = alive
				visual.broken.visible = not alive
				visual.alive = alive
	# Infinite mine landmarks are built at full scale and have no frame work.


## Visual pedestrians are deterministic environmental characters. They own
## no collision / neutral targets and never participate in combat navigation.
func sync_environment(time: float) -> void:
	for group: Dictionary in _civilian_batches:
		for index: int in group.people.size():
			var person: Dictionary = group.people[index]
			var sample: Dictionary = civilian_sample(person, time)
			var point: Vector2 = sample.pos
			var direction: Vector2 = sample.direction
			var basis := Basis(Vector3.UP, -atan2(direction.x, -direction.y))
			var bob: float = sin(time * 7.0 + float(person.phase)) * 0.014
			group.multi.set_instance_transform(index, Transform3D(basis, Vector3(point.x, MAP.height_at(_map, point) + bob, point.y)))


static func civilian_sample(person: Dictionary, time: float) -> Dictionary:
	return preload("res://scripts/city_layout.gd").civilian_sample(person, time)

func _sync_ruin(ruin: Dictionary) -> void:
	var id: int = int(ruin.id)
	var alive: bool = float(ruin.hp) > 0.0
	if _ruin_alive.get(id, not alive) == alive: return
	_ruin_alive[id] = alive
	stats.resource_updates = int(stats.resource_updates) + 1
	if ruin.kind == "tree":
		_tree_alive[id] = alive
		for piece in tree_visuals.get(id, []):
			var transform: Transform3D = piece.transform
			if not alive: transform.basis = Basis.IDENTITY.scaled(Vector3.ZERO)
			piece.multi.set_instance_transform(int(piece.slot), transform)
			piece.current_transform = transform
	elif ruin_visuals.has(id):
		var visual: Dictionary = ruin_visuals[id]
		if visual.intact is Dictionary:
			for form: String in ["intact", "rubble"]:
				var piece: Dictionary = visual[form]
				var previous_active: bool = piece.current_transform.basis != Basis.IDENTITY.scaled(Vector3.ZERO)
				var transform: Transform3D = piece.transform
				if alive != (form == "intact"): transform.basis = Basis.IDENTITY.scaled(Vector3.ZERO)
				piece.multi.set_instance_transform(int(piece.slot), transform)
				piece.current_transform = transform
				if piece.has("node"):
					var count: int = int(piece.node.get_meta("active_neutrals", 0)) + int(alive == (form == "intact")) - int(previous_active)
					piece.node.set_meta("active_neutrals", count)
					piece.node.visible = count > 0
		else:
			visual.intact.visible = alive
			visual.rubble.visible = not alive


func configure_quality(preset: String = "native") -> void:
	quality_mode = preset if preset in ["native", "balanced", "performance"] else "native"
	var distance: float = 60.0 if quality_mode == "performance" else 75.0 if quality_mode == "balanced" else 90.0
	for lod in _forest_lods:
		lod.near.visibility_range_end = distance
		lod.mid.visible = distance < 90.0
		lod.mid.visibility_range_begin = distance
		lod.mid.visibility_range_end = 90.0
		lod.far.visibility_range_begin = 90.0
		lod.far.material_override = _material("foliage") if quality_mode == "native" else _material("foliage_far")
	# Keep full geometric bark strokes near the camera. At long distance only
	# their thin overlay quads are removed; the trunk/root silhouette is intact.
	var ink_distance:float=90.0 if quality_mode=="performance" else 110.0 if quality_mode=="balanced" else 140.0
	for lod in _trunk_lods:
		lod.far.visibility_range_end=0.0 if full_trunk_ink else ink_distance
		lod.distant.visibility_range_begin=ink_distance
		lod.distant.visible=not full_trunk_ink
	stats.trunk_ink_lod_distance=0.0 if full_trunk_ink else ink_distance
	stats.forest_visual_lod_distance = distance
	stats.forest_shader_lod_distance = 90.0
	stats.scenery_quality = quality_mode


func _build(sim: WarSimulation) -> void:
	_initialize_build(sim)
	_build_terrain()
	_build_water_banks()
	_build_props()
	_build_environment()
	_build_mines(sim)
	for ruin in sim.ruins:
		_build_ruin(ruin)
	for bridge: Dictionary in sim.bridges:
		_build_bridge(bridge)
	_flush_batches()
	sync_resources(sim)


func _build_with_progress(sim: WarSimulation, progress: Callable) -> void:
	_initialize_build(sim)
	await _build_terrain_with_progress(progress)
	await progress.call(0.65, "构建河岸")
	_build_water_banks()
	await progress.call(0.68, "布置森林与地物")
	await _build_props_with_progress(progress)
	_build_environment()
	await progress.call(0.8, "放置矿藏与遗迹")
	_build_mines(sim)
	var completed: int = 0
	var yielded_at: int = Time.get_ticks_usec()
	for ruin in sim.ruins:
		_build_ruin(ruin)
		completed += 1
		if Time.get_ticks_usec() - yielded_at >= LOAD_YIELD_BUDGET_USEC:
			await progress.call(0.8 + 0.08 * float(completed) / maxi(1, sim.ruins.size()), "放置矿藏与遗迹")
			yielded_at = Time.get_ticks_usec()
	await progress.call(0.88, "搭建桥梁")
	completed = 0
	yielded_at = Time.get_ticks_usec()
	for bridge: Dictionary in sim.bridges:
		_build_bridge(bridge)
		completed += 1
		if Time.get_ticks_usec() - yielded_at >= LOAD_YIELD_BUDGET_USEC:
			await progress.call(0.88 + 0.02 * float(completed) / maxi(1, sim.bridges.size()), "搭建桥梁")
			yielded_at = Time.get_ticks_usec()
	await progress.call(0.9, "整理场景物件")
	await _flush_batches_with_progress(progress)
	sync_resources(sim)
	await progress.call(1.0, "地图加载完成")


func _initialize_build(sim: WarSimulation) -> void:
	_map = sim.map
	for ruin in sim.ruins:
		_ruin_ids_by_position[ruin.pos] = int(ruin.id)
		if ruin.kind == "tree": _tree_cells[Vector2i(floori(ruin.pos.x), floori(ruin.pos.y))] = int(ruin.id)
	_noise.seed = int(_map.seed)
	_noise.frequency = 0.073
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.fractal_octaves = 3
	_prepare_ground_exclusions(sim)


func _build_ruin(ruin: Dictionary) -> void:
	if ruin.kind == "tree": return
	var meshes: Dictionary = ENVIRONMENT_MODELS.meshes(str(ruin.archetype), float(ruin.height), int(ruin.variant)) if ruin.has("archetype") else preload("res://scripts/battlefield_ruins.gd").meshes(ruin.kind,int(ruin.variant))
	var position:=Vector3(ruin.pos.x,MAP.height_at(_map,ruin.pos),ruin.pos.y)
	if ruin.has("archetype"):
		for form: String in ["intact", "rubble"]:
			var key: String = "environment_building_%s_%s_%d_%s:%d_%d" % [str(ruin.archetype), str(ruin.height), int(ruin.variant), form, floori(ruin.pos.x / ENVIRONMENT_CHUNK), floori(ruin.pos.y / ENVIRONMENT_CHUNK)]
			if not _batches.has(key): _batches[key] = {"mesh": meshes[form], "transforms": [], "shadow": true, "neutral_ids": [], "neutral_form": form}
			var visual_scale: float = float(ruin.get("visual_scale", 1.0))
			var scale_xz: float = float(ruin.get("visual_scale_xz", visual_scale))
			var scale_y: float = float(ruin.get("visual_scale_y", visual_scale))
			_batches[key].transforms.append(Transform3D(Basis(Vector3.UP, float(ruin.get("yaw", 0))).scaled(Vector3(scale_xz, scale_y, scale_xz)), position))
			_batches[key].neutral_ids.append(int(ruin.id))
			stats.prop_instances = int(stats.prop_instances) + 1
		stats.environment_buildings = int(stats.get("environment_buildings", 0)) + 1
		return
	var intact:=_instance(meshes.intact,self,"DestructibleRuin_%d"%ruin.id)
	intact.position=position
	intact.rotation.y=float(ruin.get("yaw",0))
	var rubble:=_instance(meshes.rubble,self,"RuinDebris_%d"%ruin.id)
	rubble.position=position
	rubble.rotation.y=float(ruin.get("yaw",0))
	ruin_visuals[int(ruin.id)]={"intact":intact,"rubble":rubble}


func _material(kind: String = "paper") -> Material:
	if _materials.has(kind):
		return _materials[kind]
	if kind == "foliage_far":
		# Fine dry-brush chips become subpixel in the far canopy. Preserve the
		# original vertex paint and ink rim with one averaged pigment sample.
		var shader := Shader.new()
		shader.code = """shader_type spatial;
render_mode diffuse_burley, cull_back;
uniform sampler2D pigment_noise : filter_linear_mipmap, repeat_enable;
varying vec3 model_position;
void vertex() { model_position = VERTEX; }
void fragment() {
    vec3 paint = COLOR.rgb;
    float grain = texture(pigment_noise, (UV*vec2(8.0,3.0)+model_position.xz*1.5+vec2(0.5))/64.0).r;
    paint *= 0.90 + grain*0.20;
    float rim = 1.0-smoothstep(0.06,0.25,abs(dot(normalize(NORMAL),normalize(VIEW))));
    paint = mix(paint,vec3(0.10,0.17,0.12),rim*0.42);
    ALBEDO = mix(paint/12.92,pow((paint+vec3(0.055))/1.055,vec3(2.4)),step(vec3(0.04045),paint));
    ROUGHNESS = 0.87;
    SPECULAR = 0.15;
}
"""
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("pigment_noise", load("res://assets/textures/pigment_noise.png"))
		_materials[kind] = material
		return material
	if kind == "foliage":
		var shader := Shader.new()
		shader.code = """shader_type spatial;
render_mode diffuse_burley, cull_back;
uniform sampler2D pigment_noise : filter_linear_mipmap, repeat_enable;
varying vec3 model_position;
void vertex() { model_position = VERTEX; }
float hash(vec2 p) {
    vec3 q = fract(vec3(p.xyx) * 0.1031); q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}
float paint_noise(vec2 p) {
    return texture(pigment_noise,(p+vec2(0.5))/64.0).r;
}
void fragment() {
    vec3 p = model_position;
    vec3 paint = COLOR.rgb;
    float patch = paint_noise(vec2(UV.x * 7.0, UV.y * 3.0) + vec2(p.x+p.z,p.y)*1.9);
    float stroke = paint_noise(vec2(UV.x * 12.0, UV.y * 3.0));
    paint *= 0.83 + patch * 0.26 + stroke * 0.12;
    float dry = smoothstep(0.48, 0.76, stroke) * smoothstep(0.32, 0.91, UV.y);
    paint = mix(paint, vec3(0.48, 0.53, 0.27), dry * 0.27);
    float chips = smoothstep(0.51,0.70,paint_noise(vec2(UV.x*8.0,UV.y*12.0)+p.xz*3.0));
    chips *= smoothstep(0.63,0.93,UV.y);
    paint = mix(paint,vec3(0.55,0.58,0.29),chips*0.56);
    // Narrow dark paint in the creases, short golden-green brush tips.
    float groove = smoothstep(0.62, 0.76, paint_noise(vec2(UV.x*19.0,UV.y*2.5)));
    paint = mix(paint, vec3(0.13,0.22,0.16), groove*0.18*(1.0-smoothstep(0.65,0.95,UV.y)));
    float rim = 1.0-smoothstep(0.06,0.25,abs(dot(normalize(NORMAL),normalize(VIEW))));
    paint = mix(paint,vec3(0.10,0.17,0.12),rim*0.42);
    ALBEDO = mix(paint/12.92,pow((paint+vec3(0.055))/1.055,vec3(2.4)),step(vec3(0.04045),paint));
    ROUGHNESS = 0.87;
    SPECULAR = 0.15;
}

"""
		var foliage := ShaderMaterial.new()
		foliage.shader = shader
		foliage.set_shader_parameter("pigment_noise",load("res://assets/textures/pigment_noise.png"))
		_materials[kind] = foliage
		return foliage
	if kind in ["ground", "paper", "water"]:
		var shader := Shader.new()
		shader.code = """shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_back;
uniform float surface_kind = 0.0;
uniform sampler2D pigment_noise : filter_linear_mipmap, repeat_enable;
varying vec3 paper_position;
varying vec3 paper_normal;
void vertex() { paper_position = VERTEX; paper_normal = NORMAL; }
float hash(vec2 p) {
    vec3 q=fract(vec3(p.xyx)*0.1031); q+=dot(q,q.yzx+33.33);
    return fract((q.x+q.y)*q.z);
}
float wash(vec2 p) {
    return texture(pigment_noise,(p+vec2(0.5))/64.0).r;
}
void fragment() {
    vec3 p = paper_position;
    float top = abs(normalize(paper_normal).y);
    vec2 uv = mix(vec2(p.x + p.z, p.y), p.xz, smoothstep(0.5, 0.9, top));
    float broad = wash(uv * 1.1 + wash(uv * 3.7) * 0.4);
    float brush = wash(uv * vec2(14.0, 3.0) + broad);
    float grain = hash(floor(uv * 105.0));
    float footprint = max(fwidth(uv.x * 105.0), fwidth(uv.y * 105.0));
    grain = mix(0.5, grain, 1.0 - smoothstep(0.4, 1.2, footprint));
    vec3 pigment = COLOR.rgb;
    if (surface_kind < 1.5) {
        // Mid-scale scumbled pigment remains visible at the gameplay distance.
        pigment *= 0.89 + broad * 0.16 + brush * 0.055 + grain * 0.025;
        float fibres = wash(uv * vec2(35.0, 2.5));
        pigment *= 0.99 + fibres * 0.02;
        // Small irregular printed earth/gravel clusters break large empty tops.
        // Jittered centres and broad support avoid a grid or even noise blanket.
        if (surface_kind < 0.5 && top > 0.95) {
            vec2 cell = floor(uv * 3.1);
            vec2 jitter = vec2(hash(cell+13.7),hash(cell+71.3))*0.68+0.16;
            vec2 d = (fract(uv*3.1)-jitter)*vec2(1.0,1.35);
            float size = mix(0.05,0.17,hash(cell+29.1));
            float aa = max(fwidth(d.x),fwidth(d.y));
            float spot = 1.0-smoothstep(size,size+aa,length(d));
            float clusters = smoothstep(0.40,0.70,wash(uv*0.70));
            vec3 earth = mix(vec3(0.31,0.28,0.18),vec3(0.61,0.53,0.37),hash(cell+46.3));
            pigment = mix(pigment,earth,spot*clusters*0.47);
        }
        // Vertical cardboard carries layered dark fibres; flat ground stays quiet.
        float strata = wash(vec2(uv.x * 2.2, p.y * 18.0 + broad));
        pigment *= 1.0 - (1.0 - top) * (0.035 + smoothstep(0.65, 0.88, strata) * 0.07);
    } else {
        // Cold painted river: broad blue washes and broken short brush strokes.
        float flow = wash(vec2(p.x * 6.0 + sin(p.z * 1.5) * 0.4, p.z * 5.5));
        pigment *= 0.91 + broad * 0.14;
        float fleck = smoothstep(0.70, 0.88, flow) * smoothstep(0.45, 0.67, broad);
        pigment = mix(pigment, vec3(0.52, 0.72, 0.86), fleck * 0.20);
    }
    ALBEDO = mix(pigment / 12.92, pow((pigment + vec3(0.055)) / 1.055, vec3(2.4)), step(vec3(0.04045), pigment));
    ROUGHNESS = 0.95;
    SPECULAR = 0.0;
}
"""
		var paper := ShaderMaterial.new()
		paper.shader = shader
		paper.set_shader_parameter("pigment_noise",load("res://assets/textures/pigment_noise.png"))
		paper.set_shader_parameter("surface_kind", 2.0 if kind == "water" else 1.0 if kind == "paper" else 0.0)
		_materials[kind] = paper
		return paper
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.94
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if kind == "water":
		# The river is painted paper: broad blue values and pale printed flow.
		material.roughness = 0.92
		material.metallic = 0.0
	elif kind == "crystal":
		material.roughness = 0.6
		material.emission_enabled = true
		material.emission = Color("2973a8")
		material.emission_energy_multiplier = 0.11
	elif kind == "contact":
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_materials[kind] = material
	return material


func _data() -> Dictionary:
	return {"vertices": [], "normals": [], "colors": []}


func _triangle(data: Dictionary, a: Vector3, b: Vector3, c: Vector3, color: Color, outward: Vector3 = Vector3.ZERO) -> void:
	var normal: Vector3 = (b - a).cross(c - a)
	if normal.length_squared() < 0.00000001:
		return
	if outward != Vector3.ZERO and normal.dot(outward) < 0.0:
		var swap: Vector3 = b
		b = c
		c = swap
		normal = -normal
	normal = normal.normalized()
	# Godot front faces use clockwise winding. Keep the geometric outward
	# lighting normal, but submit reversed vertex order so double-sided
	# materials do not treat the lit exterior as a back face and flip it.
	data.vertices.append_array([a, c, b])
	data.normals.append_array([normal, normal, normal])
	data.colors.append_array([color, color, color])


func _quad(data: Dictionary, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, outward: Vector3 = Vector3.ZERO) -> void:
	_triangle(data, a, b, c, color, outward)
	_triangle(data, a, c, d, color, outward)


func _finish(data: Dictionary, kind: String = "paper") -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if data.vertices.is_empty():
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(data.vertices)
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(data.normals)
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray(data.colors)
	if data.has("uvs"):
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(data.uvs)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material(kind))
	return mesh


func _instance(mesh: Mesh, parent: Node3D = null, label: String = "") -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.name = label if label != "" else "PaperMesh"
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var owner_node: Node3D = self if parent == null else parent
	owner_node.add_child(instance)
	return instance


func _terrain_shadow_data(data: Dictionary) -> Dictionary:
	# The visible chunk keeps every painted triangle. Its shadow copy contains
	# cut walls, steep faces and upright grass, never flat tops or printed paint.
	var shadow: Dictionary = _data()
	for index: int in range(0, data.vertices.size(), 3):
		var normal: Vector3 = data.normals[index]
		if normal.y >= 0.95:continue
		for corner: int in range(3):
			shadow.vertices.append(data.vertices[index + corner])
			shadow.normals.append(data.normals[index + corner])
			shadow.colors.append(data.colors[index + corner])
	return shadow


func _append_terrain_shadow_cap(caps: Dictionary, top: Dictionary, start: int) -> void:
	# Only the just-emitted cell surface enters this cap, before printed roads,
	# washes or details. Its hidden 6 cm drop separates caster and receiver while
	# closing the platform for external shadows; visible geometry never moves.
	for index: int in range(start, top.vertices.size()):
		caps.vertices.append(top.vertices[index] + Vector3.DOWN * 0.06)
		caps.normals.append(top.normals[index])
		caps.colors.append(top.colors[index])


func _ground_color(x: float, z: float, terrain: int) -> Color:
	var key := Vector3(x, z, terrain)
	if _ground_colors.has(key):
		return _ground_colors[key]
	if _map.has("profile"):
		var profile_color: Color = BIOME_SCENERY.ground_color(_map, Vector2(x, z), terrain, _noise.get_noise_2d(x, z))
		_ground_colors[key] = profile_color
		return profile_color
	var mottling: float = _noise.get_noise_2d(x, z) * 0.105
	var fine: float = _noise.get_noise_2d(x * 5.2 + 817.0, z * 5.2 - 313.0) * 0.016
	var color := Color("b79b73")
	if terrain == MAP.ROAD:
		color = Color("a18d70")
	elif terrain == MAP.RAMP:
		color = Color("b79b73")
	var moss: float = smoothstep(0.05, 0.34, _noise.get_noise_2d(x - 441.0, z + 275.0))
	var soil: float = smoothstep(0.10, 0.36, _noise.get_noise_2d(x + 243.0, z - 137.0))
	var strength: float = 1.0 if terrain in [MAP.LAND, MAP.BLOCKED, MAP.RAMP] else 0.3
	color = color.lerp(Color("74794f"), moss * 0.38 * strength)
	color = color.lerp(Color("857054"), soil * 0.27 * strength)
	# Soil and scrub belong to the edge of a grove or a cut bank, rather than
	# appearing as unrelated specks across every open manoeuvring surface.
	var context: Vector2 = _ground_context(x, z)
	var broken_edge: float = 0.58 + smoothstep(-0.3, 0.35, _noise.get_noise_2d(x * 3.1, z * 3.1)) * 0.42
	color = color.lerp(Color("72784b"), context.x * broken_edge * 0.48 * strength)
	color = color.lerp(Color("8e7754"), context.y * broken_edge * 0.34 * strength)
	if terrain in [MAP.LAND, MAP.BLOCKED, MAP.RAMP]:
		var paint: Vector4 = _ground_paint_weights(x, z)
		color = color.lerp(Color("a18d70"), paint.x)
		color = color.lerp(Color("857054"), paint.y)
		color = color.lerp(Color("74794f").lerp(Color("b79b73"), 0.38), paint.z)
	color = color.lightened(mottling + fine)
	_ground_colors[key] = color
	return color


func _ground_paint_weights(x: float, z: float) -> Vector4:
	# The old 2.2/3.2 m edge falloff cannot reach the broad clearings. These
	# distances organise a wider margin; warped continuous fields decide where
	# that margin opens into paper, warm earth, dark earth or dry ochre grass.
	var distances: Vector3 = _ground_paint_distances(x, z)
	var forest: float = 1.0 - smoothstep(0.8, 8.5, distances.x)
	var rim: float = 1.0 - smoothstep(0.7, 7.3, distances.y)
	var road: float = 1.0 - smoothstep(1.0, 5.4, distances.z)
	var clear_road: float = 1.0 - smoothstep(0.65, 1.40, distances.z)
	var warp := Vector2(_noise.get_noise_2d(x * 0.48 + 73.0, z * 0.48 - 351.0), _noise.get_noise_2d(x * 0.48 - 182.0, z * 0.48 + 631.0)) * 2.7
	var position := Vector2(x, z) + warp
	var field: float = _noise.get_noise_2d(position.x * 0.82 + 91.0, position.y * 0.82 + 312.0)
	var weather: float = _noise.get_noise_2d(position.x * 0.65 - 701.0, position.y * 0.65 + 503.0)
	var support: float = maxf(forest * 0.92, rim * 0.76)
	var earth: float = smoothstep(-0.16, 0.28, field + support * 0.11)
	var warm: float = smoothstep(-0.30, 0.32, weather) * (0.12 + maxf(road, rim) * 0.34) * (1.0 - earth * 0.58)
	var dark: float = earth * (0.10 + support * 0.62)
	var dry: float = rim * smoothstep(-0.24, 0.22, -field) * smoothstep(-0.20, 0.30, -weather) * (1.0 - forest * 0.72) * 0.38
	# The painted road footprint/width stays authoritative. Colour fades out
	# beside its centre; continuous low-context negative-field interiors also
	# retain their original bright paper, rather than receiving a global wash.
	var preserve: float = 1.0 - clear_road * 0.92
	return Vector4(warm * preserve, dark * preserve, dry * preserve, clear_road)


func _ground_paint_distances(x: float, z: float) -> Vector3:
	# Interpolated two-metre samples keep expensive map searches bounded while
	# every top vertex/paint intersection receives a continuous world colour.
	var here: float = MAP.height_at(_map, Vector2(x, z))
	var origin := Vector2(floorf(x * 0.5) * 2.0, floorf(z * 0.5) * 2.0)
	var fraction := Vector2((x - origin.x) * 0.5, (z - origin.y) * 0.5)
	var north: Vector3 = _ground_paint_distance_sample(origin.x, origin.y, here).lerp(_ground_paint_distance_sample(origin.x + 2.0, origin.y, here), fraction.x)
	var south: Vector3 = _ground_paint_distance_sample(origin.x, origin.y + 2.0, here).lerp(_ground_paint_distance_sample(origin.x + 2.0, origin.y + 2.0, here), fraction.x)
	return north.lerp(south, fraction.y)


func _ground_paint_distance_sample(x: float, z: float, level: float) -> Vector3:
	var key := Vector3(x, z, level)
	if _ground_paint_samples.has(key):
		return _ground_paint_samples[key]
	var result := Vector3.ONE * 11.0
	var position := Vector2(x, z)
	if _terrain_features_ready:
		result.y = minf(result.y, _local_rim_distance(position, level))
		for feature in _feature_candidates(position, 9):
			var cell: Vector2i = feature.cell
			if absi(cell.x - floori(x)) > 9 or absi(cell.y - floori(z)) > 9: continue
			var distance: float = position.distance_to(Vector2(cell) + Vector2.ONE * .5)
			if feature.forest and is_equal_approx(float(feature.height), level): result.x = minf(result.x, distance)
			if feature.water or (absf(float(feature.height) - level) > .95 and feature.kind != MAP.RAMP): result.y = minf(result.y, distance)
			if feature.road and is_equal_approx(float(feature.height), level): result.z = minf(result.z, distance)
		_ground_paint_samples[key] = result
		return result
	for dz: int in range(-9, 10):
		for dx: int in range(-9, 10):
			var cell := Vector2i(floori(x) + dx, floori(z) + dz)
			if not _inside(cell.x, cell.y):
				continue
			var kind: int = int(_map.terrain[cell.y][cell.x])
			var height: float = float(_map.heights[cell.y][cell.x])
			var distance: float = position.distance_to(Vector2(cell) + Vector2.ONE * 0.5)
			if kind == MAP.BLOCKED and is_equal_approx(height, level):
				result.x = minf(result.x, distance)
			if kind == MAP.WATER or (absf(height - level) > 0.95 and kind != MAP.RAMP):
				result.y = minf(result.y, distance)
			var road: bool = kind == MAP.ROAD
			for mark: Dictionary in _ground_marks.get(cell, []):
				road = road or float(mark.offset) > 0.0035
			if road and is_equal_approx(height, level):
				result.z = minf(result.z, distance)
	_ground_paint_samples[key] = result
	return result


func _ground_context(x: float, z: float) -> Vector2:
	var key := Vector2(x, z)
	if _ground_contexts.has(key):return _ground_contexts[key]
	var here: float = MAP.height_at(_map, key)
	var forest: float = 0.0
	var rim: float = 0.0
	if _terrain_features_ready:
		rim = clampf(1.0 - _local_rim_distance(key, here) / 2.2, 0.0, 1.0)
		for feature in _feature_candidates(key, 3):
			var cell: Vector2i = feature.cell
			if absi(cell.x - floori(x)) > 3 or absi(cell.y - floori(z)) > 3: continue
			var distance: float = key.distance_to(Vector2(cell) + Vector2.ONE * .5)
			if feature.forest and is_equal_approx(float(feature.height), here): forest = maxf(forest, clampf(1.0 - distance / 3.2, 0.0, 1.0))
			if feature.water or (absf(float(feature.height) - here) > .95 and feature.kind != MAP.RAMP): rim = maxf(rim, clampf(1.0 - distance / 2.2, 0.0, 1.0))
		var result := Vector2(forest, rim)
		_ground_contexts[key] = result
		return result
	for dz: int in range(-3, 4):
		for dx: int in range(-3, 4):
			var cell := Vector2i(floori(x) + dx, floori(z) + dz)
			if not _inside(cell.x, cell.y):continue
			var distance: float = key.distance_to(Vector2(cell) + Vector2.ONE * 0.5)
			var level: float = float(_map.heights[cell.y][cell.x])
			var kind: int = int(_map.terrain[cell.y][cell.x])
			if kind == MAP.BLOCKED and is_equal_approx(level, here):
				forest = maxf(forest, clampf(1.0 - distance / 3.2, 0.0, 1.0))
			if kind == MAP.WATER or (absf(level - here) > 0.95 and kind != MAP.RAMP):
				rim = maxf(rim, clampf(1.0 - distance / 2.2, 0.0, 1.0))
	var result := Vector2(forest, rim)
	_ground_contexts[key] = result
	return result


func _prepare_terrain_features() -> void:
	# Nearest unlike-height cells lie on an interface. Store those interfaces,
	# water, blockers and roads by region instead of rescanning 361 ordinary
	# cells for every paint sample. Local unlike-height samples cover origins
	# which interpolation places just inside the neighbouring plateau.
	_terrain_features.clear()
	var size: int = int(_map.size)
	var directions: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN, Vector2i(-1, -1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(1, 1)]
	for z in range(size):
		for x in range(size):
			var kind: int = int(_map.terrain[z][x])
			var height: float = float(_map.heights[z][x])
			var road: bool = kind == MAP.ROAD
			for mark in _ground_marks.get(Vector2i(x, z), []): road = road or float(mark.offset) > .0035
			var boundary: bool = false
			if kind != MAP.RAMP:
				for direction in directions:
					var next := Vector2i(x, z) + direction
					if _inside(next.x, next.y) and not is_equal_approx(float(_map.heights[next.y][next.x]), height):
						boundary = true
						break
			if not road and kind not in [MAP.WATER, MAP.BLOCKED] and not boundary: continue
			var bucket := Vector2i(x / 8, z / 8)
			if not _terrain_features.has(bucket): _terrain_features[bucket] = []
			_terrain_features[bucket].append({"cell": Vector2i(x, z), "height": height, "kind": kind, "water": kind == MAP.WATER, "forest": kind == MAP.BLOCKED, "road": road})
	_terrain_features_ready = true


func _feature_candidates(point: Vector2, radius: int) -> Array:
	var answer: Array = []
	for z in range(floori((point.y - radius) / 8.0), floori((point.y + radius) / 8.0) + 1):
		for x in range(floori((point.x - radius) / 8.0), floori((point.x + radius) / 8.0) + 1): answer.append_array(_terrain_features.get(Vector2i(x, z), []))
	return answer


func _local_rim_distance(point: Vector2, level: float) -> float:
	var nearest: float = INF
	var cell := Vector2i(floori(point.x), floori(point.y))
	for z in range(cell.y - 1, cell.y + 2):
		for x in range(cell.x - 1, cell.x + 2):
			if not _inside(x, z): continue
			var kind: int = int(_map.terrain[z][x])
			if kind == MAP.WATER or (kind != MAP.RAMP and absf(float(_map.heights[z][x]) - level) > .95): nearest = minf(nearest, point.distance_to(Vector2(x + .5, z + .5)))
	return nearest


func _paint_top(data: Dictionary, start: int, terrain: int) -> void:
	# Shared corner samples give broad moss/soil patches continuous colour
	# gradients instead of making the underlying gameplay grid visible.
	for index: int in range(start, data.vertices.size()):
		var vertex: Vector3 = data.vertices[index]
		data.colors[index] = _ground_color(vertex.x, vertex.z, terrain)


func _surface_height(x: float, z: float, water: bool) -> float:
	return MAP.water_surface_y(_map, Vector2(x, z)) if water else MAP.height_at(_map, Vector2(x, z))


func _surface_corner(point: Vector3) -> Vector3:
	if _surface_corners.has(point):
		return _surface_corners[point]
	var offset: Vector2 = _rim_corner_offset(point)
	var result: Vector3 = point + Vector3(offset.x, 0, offset.y)
	_surface_corners[point] = result
	return result


func _rim_corner_offset(point: Vector3) -> Vector2:
	var vertex := Vector2i(roundi(point.x), roundi(point.z))
	if point.y < 0.0 or absf(point.x - vertex.x) > 0.00001 or absf(point.z - vertex.y) > 0.00001:
		return Vector2.ZERO
	var cells: Array[Vector2i] = [vertex + Vector2i(-1, -1), vertex + Vector2i(0, -1), vertex + Vector2i(-1, 0), vertex]
	var high_cells: Array[Vector2i] = []
	var centre_sum := Vector2.ZERO
	# All owners of this integer corner agree before any geometry is emitted.
	# Low-layer corners beside a higher tile stay at their original wall foot.
	for cell: Vector2i in cells:
		if not _inside(cell.x, cell.y):
			return Vector2.ZERO
		var terrain: int = int(_map.terrain[cell.y][cell.x])
		var height: float = float(_map.heights[cell.y][cell.x])
		if terrain in [MAP.RAMP, MAP.ROAD] or _ground_marks.has(cell):
			return Vector2.ZERO
		if terrain != MAP.WATER and height > point.y + 0.001:
			return Vector2.ZERO
		if terrain != MAP.WATER and is_equal_approx(height, point.y):
			high_cells.append(cell)
			centre_sum += Vector2(cell) + Vector2.ONE * 0.5 - Vector2(vertex)
		elif terrain != MAP.WATER and point.y - height < 0.95:
			# Small ramp-like risers are never a silhouette experiment.
			return Vector2.ZERO
	var count: int = high_cells.size()
	if count not in [1, 2] or centre_sum.length_squared() < 0.00001:
		# Concave, interior and diagonal-touch corners remain authoritative.
		return Vector2.ZERO
	var corner_point := Vector2(point.x, point.z)
	for bridge: Dictionary in _map.bridges:
		var bounds: Array = bridge.bounds
		var protection := Rect2(Vector2(bounds[0], bounds[1]) - Vector2.ONE, Vector2(bounds[2], bounds[3]) + Vector2.ONE * 2.0)
		if protection.grow(0.0001).has_point(corner_point):
			return Vector2.ZERO
		for head: Array in bridge.heads:
			if corner_point.distance_squared_to(Vector2(head[0], head[1])) <= 4.0:
				return Vector2.ZERO
	var inward: Vector2 = centre_sum.normalized()
	# A one-cell island, shelf or neck cannot surrender its visual support.
	# Convex corners require a full 2x2 land patch inward; straight rims require
	# another row on the land side. This leaves every narrow route untouched.
	for cell: Vector2i in high_cells:
		var axis_steps: Array[Vector2i] = []
		if absf(inward.x) > 0.01:
			axis_steps.append(Vector2i(1 if inward.x > 0.0 else -1, 0))
		if absf(inward.y) > 0.01:
			axis_steps.append(Vector2i(0, 1 if inward.y > 0.0 else -1))
		if axis_steps.size() == 2:
			axis_steps.append(axis_steps[0] + axis_steps[1])
		for step: Vector2i in axis_steps:
			var support: Vector2i = cell + step
			if not _inside(support.x, support.y):
				return Vector2.ZERO
			var kind: int = int(_map.terrain[support.y][support.x])
			if kind in [MAP.WATER, MAP.RAMP, MAP.ROAD] or _ground_marks.has(support) or not is_equal_approx(float(_map.heights[support.y][support.x]), point.y):
				return Vector2.ZERO
	# Smooth world-space variation avoids a new per-cell sawtooth. The convex
	# value is total diagonal length (each axis <= 0.283 m), not per-axis inset.
	var phase: float = float(posmod(int(_map.seed), 997)) * 0.019
	var wave: float = 0.5 + 0.5 * sin(point.x * 0.19 + point.z * 0.23 + phase)
	return inward * lerpf(0.38, 0.40, wave) if count == 1 else inward * lerpf(0.08, 0.12, wave)


func _cell_rim_changed(x: int, z: int, height: float) -> bool:
	for dz: int in [0, 1]:
		for dx: int in [0, 1]:
			var corner := Vector3(x + dx, height, z + dz)
			if _surface_corner(corner) != corner:
				return true
	return false


func _build_terrain() -> void:
	var request: Dictionary = _terrain_build_request()
	if bool(request.cached):
		for item in _terrain_cache.nodes:
			_restore_terrain_node(item)
		_restore_terrain_stats()
		return
	_prepare_terrain_geometry()
	for cz: int in range(0, int(request.size), CHUNK):
		for cx: int in range(0, int(request.size), CHUNK):
			_build_terrain_chunk(cx, cz, int(request.size))
	_finish_terrain_build(request)


func _build_terrain_with_progress(progress: Callable) -> void:
	await progress.call(0.0, "读取地形缓存")
	var request: Dictionary = _terrain_build_request()
	var completed: int = 0
	var yielded_at: int = Time.get_ticks_usec()
	if bool(request.cached):
		await progress.call(0.05, "加载地形缓存")
		yielded_at = Time.get_ticks_usec()
		for item in _terrain_cache.nodes:
			_restore_terrain_node(item)
			completed += 1
			if Time.get_ticks_usec() - yielded_at >= LOAD_YIELD_BUDGET_USEC:
				await progress.call(0.05 + 0.6 * float(completed) / maxi(1, _terrain_cache.nodes.size()), "加载地形缓存")
				yielded_at = Time.get_ticks_usec()
		_restore_terrain_stats()
		return
	await progress.call(0.04, "准备地形")
	_terrain_cache.clear()
	_surface_corners.clear()
	_prepare_battle_marks()
	await progress.call(0.06, "分析地形")
	_prepare_terrain_features()
	await progress.call(0.08, "绘制地表")
	_prepare_ground_islands()
	await progress.call(0.12, "构建地形")
	var size: int = int(request.size)
	var chunk_count: int = ceili(float(size) / CHUNK)
	var total: int = chunk_count * chunk_count
	yielded_at = Time.get_ticks_usec()
	for cz: int in range(0, size, CHUNK):
		for cx: int in range(0, size, CHUNK):
			_build_terrain_chunk(cx, cz, size)
			completed += 1
			if Time.get_ticks_usec() - yielded_at >= LOAD_YIELD_BUDGET_USEC:
				await progress.call(0.12 + 0.5 * float(completed) / maxi(1, total), "构建地形")
				yielded_at = Time.get_ticks_usec()
	await progress.call(0.62, "整理地形缓存")
	_finish_terrain_build(request)


func _terrain_build_request() -> Dictionary:
	var size: int = int(_map.size)
	var inputs:Array=[_map,_ground_exclusions]
	var signature:int=hash(inputs)
	var disk_key:String=""
	stats.terrain_disk_cache_hit=false
	stats.terrain_cache_read_ms=0.0
	stats.terrain_cache_write_ms=0.0
	if terrain_disk_cache_enabled and size>=320:
		disk_key=TERRAIN_DISK_CACHE.key_for(inputs)
		if _terrain_cache.get("signature",-1)!=signature:
			var read_start:int=Time.get_ticks_usec()
			var stored:Dictionary=TERRAIN_DISK_CACHE.load_entry(disk_key)
			stats.terrain_cache_read_ms=(Time.get_ticks_usec()-read_start)/1000.0
			if not stored.is_empty():
				_terrain_cache=stored
				_terrain_cache.signature=signature
				stats.terrain_disk_cache_hit=true
				stats.terrain_cache_source=str(stored.get("cache_source","user"))
	return {"size": size, "signature": signature, "disk_key": disk_key, "cached": _terrain_cache.get("signature", -1) == signature}


func _restore_terrain_node(item: Dictionary) -> void:
	var node: MeshInstance3D = _instance(item.mesh, self, item.name)
	node.cast_shadow = item.shadow
	if item.has("navigation_top_ranges"): node.set_meta("navigation_top_ranges", item.navigation_top_ranges)


func _restore_terrain_stats() -> void:
	for key in _terrain_cache.stats: stats[key] = _terrain_cache.stats[key]
	stats.terrain_cache_hit = true


func _prepare_terrain_geometry() -> void:
	# Retain at most one complete battlefield's static terrain resources.
	# Trees, mines, bridge state and their transforms are built separately.
	_terrain_cache.clear()
	_surface_corners.clear()
	_prepare_battle_marks()
	_prepare_terrain_features()
	_prepare_ground_islands()


func _build_terrain_chunk(cx: int, cz: int, size: int) -> void:
	var land: Dictionary = _data()
	var ecology: Dictionary = _data()
	var water: Dictionary = _data()
	var shadow_caps: Dictionary = _data()
	var flat_shadow_tiles := PackedFloat32Array()
	flat_shadow_tiles.resize(CHUNK * CHUNK)
	flat_shadow_tiles.fill(INF)
	var navigation_top_ranges: Array[Vector2i] = []
	for z: int in range(cz, mini(cz + CHUNK, size)):
		for x: int in range(cx, mini(cx + CHUNK, size)):
			var terrain: int = int(_map.terrain[z][x])
			var wet: bool = terrain == MAP.WATER
			var target: Dictionary = water if wet else land
			var top_start: int = target.vertices.size()
			var flat_cap: bool = false
			var color: Color = Color("397fa3").lightened(_noise.get_noise_2d(x * 2.0, z * 2.0) * 0.08) if wet else _ground_color(x, z, terrain)
			var h_n: float = _surface_height(x + 0.5, z + 0.0001, wet)
			var h_mid: float = _surface_height(x + 0.5, z + 0.5, wet)
			var h_s: float = _surface_height(x + 0.5, z + 0.9999, wet)
			# Ramp interpolation is piecewise linear around the cell centre.
			# Two strips reproduce it rather than inventing a visual slope.
			if terrain == MAP.RAMP:
				_quad(target, Vector3(x, h_n, z), Vector3(x, h_mid, z + 0.5), Vector3(x + 1, h_mid, z + 0.5), Vector3(x + 1, h_n, z), color, Vector3.UP)
				_quad(target, Vector3(x, h_mid, z + 0.5), Vector3(x, h_s, z + 1), Vector3(x + 1, h_s, z + 1), Vector3(x + 1, h_mid, z + 0.5), color, Vector3.UP)
			else:
				# One cached world vertex owns both the flat top and cliff rim.
				# Water keeps its original full grid footprint below the banks.
				var corners: Array[Vector3] = [Vector3(x, h_mid, z), Vector3(x, h_mid, z + 1), Vector3(x + 1, h_mid, z + 1), Vector3(x + 1, h_mid, z)]
				if not wet:
					flat_cap = true
					for corner: int in corners.size():
						var resolved: Vector3 = _surface_corner(corners[corner])
						flat_cap = flat_cap and resolved == corners[corner]
						corners[corner] = resolved
				_quad(target, corners[0], corners[1], corners[2], corners[3], color, Vector3.UP)
			if not wet:
				# Preserve the real terrain subset for navigation-height QA. Printed
				# marks, cardboard litter and scree later share this draw only.
				navigation_top_ranges.append(Vector2i(top_start,target.vertices.size()))
			if wet:
				_paint_water_top(target, top_start)
			else:
				if flat_cap:
					flat_shadow_tiles[(z - cz) * CHUNK + x - cx] = h_mid
				else:
					_append_terrain_shadow_cap(shadow_caps, target, top_start)
				_paint_top(target, top_start, terrain)
			_build_cell_edges(land, x, z, h_n, h_s, wet)
			if wet and (x * 3 + z) % 4 == 0:
				_water_marks(water, x, z, h_mid)
			elif terrain == MAP.ROAD and _map.get("profile", {}).get("biome", "") == "city":
				_city_road_mark(land, x, z, h_mid)
			elif terrain == MAP.ROAD and (x + z) % 3 == 0:
				var y: float = h_mid + 0.009
				_quad(land, Vector3(x + 0.20, y, z + 0.44), Vector3(x + 0.20, y, z + 0.51), Vector3(x + 0.65, y, z + 0.57), Vector3(x + 0.65, y, z + 0.50), Color("dbceb4"), Vector3.UP)
			elif terrain == MAP.LAND and _map.has("profile"):
				_profile_ground_details(land, x, z, h_mid)
			elif terrain == MAP.LAND:
				var context: Vector2 = _ground_context(x + 0.5, z + 0.5)
				var patch: float = smoothstep(0.12, 0.4, _noise.get_noise_2d(x * 3.8 + 95.0, z * 3.8))
				var density: float = 0.085 + maxf(context.x * 0.46, context.y * 0.37) + patch * 0.22
				if _static_hash(x, z, 15.0) > 1.0 - density and not _cell_rim_changed(x, z, h_mid):
					_ground_details(land, x + 0.32 + _static_hash(x,z,12.0)*0.36, z + 0.32 + _static_hash(x,z,13.0)*0.36, h_mid)
			if terrain in [MAP.LAND, MAP.ROAD]:
				_battle_marks(land, x, z, h_mid)
			if terrain == MAP.LAND and not _map.has("profile"):
				_ground_ecology(ecology, Vector2i(x, z))
	if not land.vertices.is_empty():
		_append_coalesced_shadow_caps(shadow_caps, flat_shadow_tiles, cx, cz, mini(CHUNK, size - cx), mini(CHUNK, size - cz))
		stats.shadow_cap_triangles = int(stats.shadow_cap_triangles) + shadow_caps.vertices.size() / 3
		# Ecology shares this visible terrain draw. It remains below 22 cm and
		# uses its earth-paper contact body instead of adding fragile tiny
		# shadow casters to the separated platform-cap chain.
		var shadow_data: Dictionary = _terrain_shadow_data(land)
		land.vertices.append_array(ecology.vertices)
		land.normals.append_array(ecology.normals)
		land.colors.append_array(ecology.colors)
		var visible_ground: MeshInstance3D = _instance(_finish(land, "ground"), self, "Ground_%d_%d" % [cx, cz])
		visible_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visible_ground.set_meta("navigation_top_ranges",navigation_top_ranges)
		shadow_data.vertices.append_array(shadow_caps.vertices)
		shadow_data.normals.append_array(shadow_caps.normals)
		shadow_data.colors.append_array(shadow_caps.colors)
		stats.terrain_shadow_triangles = int(stats.terrain_shadow_triangles) + shadow_data.vertices.size() / 3
		if not shadow_data.vertices.is_empty():
			var caster: MeshInstance3D = _instance(_finish(shadow_data, "ground"), self, "TerrainCaster_%d_%d" % [cx, cz])
			caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		stats.ground_chunks = int(stats.ground_chunks) + 1
		stats.terrain_triangles = int(stats.terrain_triangles) + land.vertices.size() / 3
	if not water.vertices.is_empty():
		var visible_water: MeshInstance3D = _instance(_finish(water, "water"), self, "Water_%d_%d" % [cx, cz])
		visible_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stats.terrain_triangles = int(stats.terrain_triangles) + water.vertices.size() / 3


func _finish_terrain_build(request: Dictionary) -> void:
	var size: int = int(request.size)
	var signature: int = int(request.signature)
	var disk_key: String = str(request.disk_key)
	var board: Dictionary = _data()
	_box(board, Vector3(size * 0.5, -WATER_DEPTH - 0.55, size * 0.5), Vector3(size + 0.18, 0.6, size + 0.18), Color("796d59"))
	var visible_board: MeshInstance3D = _instance(_finish(board), self, "TabletopBase")
	visible_board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var nodes: Array = []
	for node in get_children():
		if not node is MeshInstance3D: continue
		if not str(node.name).begins_with("Ground_") and not str(node.name).begins_with("TerrainCaster_") and not str(node.name).begins_with("Water_") and str(node.name) != "TabletopBase": continue
		var record: Dictionary = {"name": str(node.name), "mesh": node.mesh, "shadow": node.cast_shadow}
		if node.has_meta("navigation_top_ranges"): record.navigation_top_ranges = node.get_meta("navigation_top_ranges")
		nodes.append(record)
	var cached_stats: Dictionary = {}
	for key in ["terrain_triangles", "ground_chunks", "shadow_cap_triangles", "terrain_shadow_triangles"]: cached_stats[key] = stats[key]
	_terrain_cache = {"signature": signature, "nodes": nodes, "stats": cached_stats}
	if not disk_key.is_empty():
		var write_start:int=Time.get_ticks_usec()
		stats.terrain_cache_write_error=TERRAIN_DISK_CACHE.store_entry(disk_key,_terrain_cache)
		stats.terrain_cache_write_ms=(Time.get_ticks_usec()-write_start)/1000.0


func _append_coalesced_shadow_caps(data: Dictionary, tiles: PackedFloat32Array, cx: int, cz: int, width: int, depth: int) -> void:
	# Flat neighbouring cell caps are one exact plane. Merge their union while
	# retaining the original six-centimetre offset; ramps and carved rims keep
	# their original triangles, so shadows cannot bridge a real cliff or water.
	for z in range(depth):
		for x in range(width):
			var height: float = float(tiles[z * CHUNK + x])
			if not is_finite(height): continue
			var run: int = 1
			while x + run < width and float(tiles[z * CHUNK + x + run]) == height: run += 1
			var rows: int = 1
			while z + rows < depth:
				var compatible: bool = true
				for offset in range(run):
					if float(tiles[(z + rows) * CHUNK + x + offset]) != height:
						compatible = false
						break
				if not compatible: break
				rows += 1
			var h: float = height - .06
			_quad(data, Vector3(cx + x, h, cz + z), Vector3(cx + x, h, cz + z + rows), Vector3(cx + x + run, h, cz + z + rows), Vector3(cx + x + run, h, cz + z), Color.WHITE, Vector3.UP)
			for row in range(rows):
				for offset in range(run): tiles[(z + row) * CHUNK + x + offset] = INF


func _build_cell_edges(data: Dictionary, x: int, z: int, h_n: float, h_s: float, wet: bool) -> void:
	var size: int = int(_map.size)
	for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var nx: int = x + direction.x
		var nz: int = z + direction.y
		var neighbor_wet: bool = _inside(nx, nz) and int(_map.terrain[nz][nx]) == MAP.WATER
		var a: Vector3
		var b: Vector3
		var low_a: float = -WATER_DEPTH - 0.25
		var low_b: float = -WATER_DEPTH - 0.25
		if direction.x != 0:
			var edge_x: float = x + (1 if direction.x > 0 else 0)
			a = Vector3(edge_x, h_n, z)
			b = Vector3(edge_x, h_s, z + 1)
			if _inside(nx, nz):
				low_a = _surface_height(nx + 0.5, nz + 0.0001, neighbor_wet)
				low_b = _surface_height(nx + 0.5, nz + 0.9999, neighbor_wet)
		else:
			var edge_z: float = z + (1 if direction.y > 0 else 0)
			var high: float = h_s if direction.y > 0 else h_n
			a = Vector3(x, high, edge_z)
			b = Vector3(x + 1, high, edge_z)
			if _inside(nx, nz):
				low_a = _surface_height(nx + 0.5, nz + (0.0001 if direction.y > 0 else 0.9999), neighbor_wet)
				low_b = low_a
		if a.y <= low_a + 0.001 and b.y <= low_b + 0.001:
			continue
		low_a = minf(low_a, a.y)
		low_b = minf(low_b, b.y)
		var color := Color("9e7854").lightened(_noise.get_noise_2d(x + 0.5, z + 0.5) * 0.055)
		var normal := Vector3(direction.x, 0, direction.y)
		# Keep every foot on the authoritative low surface. Moving the rim must
		# never pull a wall foot away from unchanged water or lower ground.
		var original_a: Vector3 = a
		var original_b: Vector3 = b
		var bottom_a := Vector3(original_a.x, low_a, original_a.z)
		var bottom_b := Vector3(original_b.x, low_b, original_b.z)
		if not wet:
			a = _surface_corner(original_a)
			b = _surface_corner(original_b)
		if maxf(a.y - low_a, b.y - low_b) < 0.95:
			# Tiny legal ramp risers remain exact and visually quiet.
			_quad(data, a, b, bottom_b, bottom_a, color, normal)
		else:
			_faceted_cliff(data, a, b, bottom_a, bottom_b, normal, color, x, z, original_a, original_b)
		# A thin warm lip makes riverbanks legible against the blue water.
		if neighbor_wet and not wet:
			var inward := Vector3(-direction.x, 0, -direction.y) * 0.11
			_quad(data, a + Vector3.UP * 0.01, b + Vector3.UP * 0.01, b + inward + Vector3.UP * 0.01, a + inward + Vector3.UP * 0.01, Color("bda07a"), Vector3.UP)


func _static_hash(x: float, z: float, salt: float) -> float:
	var value: float = sin(x * 12.9898 + z * 78.233 + salt * 47.13 + float(posmod(int(_map.seed), 997)) * 1.327) * 43758.5453
	return value - floorf(value)


func _face_normal(a: Vector3, b: Vector3, c: Vector3, outside: Vector3) -> Vector3:
	var normal: Vector3 = (b - a).cross(c - a).normalized()
	return -normal if normal.dot(outside) < 0.0 else normal


func _faceted_cliff(data: Dictionary, a: Vector3, b: Vector3, low_a: Vector3, low_b: Vector3, outside: Vector3, color: Color, x: int, z: int, original_a: Vector3, original_b: Vector3) -> void:
	# The shared rim retreats inside the upper land; the original foot stays put.
	# Fold topology still uses original grid corners, including at chunk joins.
	var middle_a: Vector3 = _cliff_fold_point(a, low_a, outside, original_a)
	var middle_b: Vector3 = _cliff_fold_point(b, low_b, outside, original_b)
	_quad(data, a, b, middle_b, middle_a, color.lightened(0.018), outside)
	_quad(data, middle_a, middle_b, low_b, low_a, color.darkened(0.065), outside)
	CLIFF_CRAFT.decorate(self, data, a, b, middle_a, middle_b, low_a, low_b, outside, color, x, z)


func _cliff_fold_point(top: Vector3, bottom: Vector3, outside: Vector3, original_top: Vector3) -> Vector3:
	if _cliff_fold_locked(original_top, bottom, outside):
		return top.lerp(bottom, 0.5)
	# Only global coordinates determine the profile. No per-cell random centre,
	# chunk phase or camera dependence is permitted in this wall geometry.
	var along: float = original_top.z if absf(outside.x) > 0.5 else original_top.x
	var plane: float = original_top.x if absf(outside.x) > 0.5 else original_top.z
	var phase: float = plane * 0.23 + float(posmod(int(_map.seed), 97)) * 0.019 + (outside.x + outside.z) * 0.43
	var down: float = 0.50 + sin(along * 0.29 + phase) * 0.10 + sin(along * 0.61 - phase) * 0.04
	var limit: float = minf(0.18, maxf(0.0, top.y - bottom.y) * 0.07)
	var inset: float = limit * (0.68 + sin(along * 0.38 + phase) * 0.23 + sin(along * 0.15 - phase) * 0.09)
	# The fold remains inside the upper cell and adds no horizontal walking ledge.
	return top.lerp(bottom, down) - outside * inset


func _cliff_fold_locked(top: Vector3, bottom: Vector3, outside: Vector3) -> bool:
	var point := Vector2(top.x, top.z)
	for bridge: Dictionary in _map.bridges:
		var bounds: Array = bridge.bounds
		var protection := Rect2(Vector2(bounds[0], bounds[1]) - Vector2.ONE, Vector2(bounds[2], bounds[3]) + Vector2.ONE * 2.0)
		if protection.has_point(point):
			return true
		for head: Array in bridge.heads:
			if point.distance_squared_to(Vector2(head[0], head[1])) <= 4.0:
				return true
	# All four cells incident on this vertex must be free of ramps. Pinning
	# the fold leaves ramp joins and their exact height interpolation untouched.
	for cell_z: int in range(floori(top.z) - 1, floori(top.z) + 1):
		for cell_x: int in range(floori(top.x) - 1, floori(top.x) + 1):
			if not _inside(cell_x, cell_z) or int(_map.terrain[cell_z][cell_x]) == MAP.RAMP:
				return true
	var tangent := Vector2(0, 1) if absf(outside.x) > 0.5 else Vector2(1, 0)
	var outward := Vector2(outside.x, outside.z)
	# Both tangent-adjacent segments must describe this same straight wall.
	# A turn, height transition or end of a drop pins the shared vertical edge;
	# differently oriented walls therefore cannot separate their corner vertex.
	for sign_along: float in [-1.0, 1.0]:
		var middle: Vector2 = point + tangent * sign_along * 0.5
		var high_cell := Vector2i(floori(middle.x - outward.x * 0.5), floori(middle.y - outward.y * 0.5))
		var low_cell := Vector2i(floori(middle.x + outward.x * 0.5), floori(middle.y + outward.y * 0.5))
		if not _inside(high_cell.x, high_cell.y) or not _inside(low_cell.x, low_cell.y):
			return true
		var high_wet: bool = int(_map.terrain[high_cell.y][high_cell.x]) == MAP.WATER
		var low_wet: bool = int(_map.terrain[low_cell.y][low_cell.x]) == MAP.WATER
		var high_y: float = _surface_height(high_cell.x + 0.5, high_cell.y + 0.5, high_wet)
		var low_y: float = _surface_height(low_cell.x + 0.5, low_cell.y + 0.5, low_wet)
		if not is_equal_approx(high_y, top.y) or not is_equal_approx(low_y, bottom.y) or high_y - low_y < 0.95:
			return true
	return false


func _cliff_quad_point(a: Vector3, b: Vector3, c: Vector3, d: Vector3, u: float, v: float) -> Vector3:
	# Exact barycentric point on _quad's a-b-c / a-c-d triangulation. Bilinear
	# interpolation would lift ink away from a folded, non-planar quad.
	if v <= u:
		return a * (1.0 - u) + b * (u - v) + c * v
	return a * (1.0 - v) + c * u + d * (v - u)


func _cliff_facet_strip(data: Dictionary, a: Vector3, b: Vector3, c: Vector3, d: Vector3, u: float, start: float, end: float, outside: Vector3, color: Color, width: float) -> void:
	var split: float = clampf(u, start, end)
	if split > start + 0.0001:
		_cliff_triangle_strip(data, _cliff_quad_point(a, b, c, d, u, start), _cliff_quad_point(a, b, c, d, u, split), a, b, c, outside, color, width)
	if end > split + 0.0001:
		_cliff_triangle_strip(data, _cliff_quad_point(a, b, c, d, u, split), _cliff_quad_point(a, b, c, d, u, end), a, c, d, outside, color, width)


func _cliff_triangle_strip(data: Dictionary, start: Vector3, end: Vector3, a: Vector3, b: Vector3, c: Vector3, outside: Vector3, color: Color, width: float) -> void:
	# Clip the complete ink ribbon, not just its centreline. Its width must not
	# hang over a wall end or bridge the empty space outside a folded triangle.
	if start.distance_squared_to(end) < 0.0000001 or (b - a).cross(c - a).length_squared() < 0.0000001:
		return
	var normal: Vector3 = _face_normal(a, b, c, outside)
	var across: Vector3 = (end - start).normalized().cross(normal).normalized() * width * 0.5
	var polygon: Array[Vector3] = [start - across, end - across, end + across, start + across]
	var triangle: Array[Vector3] = [a, b, c]
	var centre: Vector3 = (a + b + c) / 3.0
	for edge: int in range(3):
		if polygon.is_empty():
			return
		var edge_a: Vector3 = triangle[edge]
		var edge_b: Vector3 = triangle[(edge + 1) % 3]
		var inward: Vector3 = normal.cross(edge_b - edge_a).normalized()
		if inward.dot(centre - edge_a) < 0.0:
			inward = -inward
		var clipped: Array[Vector3] = []
		var previous: Vector3 = polygon.back()
		var previous_distance: float = inward.dot(previous - edge_a)
		for point: Vector3 in polygon:
			var distance: float = inward.dot(point - edge_a)
			if (distance >= 0.0) != (previous_distance >= 0.0):
				clipped.append(previous.lerp(point, previous_distance / (previous_distance - distance)))
			if distance >= 0.0:
				clipped.append(point)
			previous = point
			previous_distance = distance
		polygon = clipped
	for index: int in range(1, polygon.size() - 1):
		_triangle(data, polygon[0] + normal * 0.002, polygon[index] + normal * 0.002, polygon[index + 1] + normal * 0.002, color, normal)


func _water_row_bounds(row: int) -> Vector2:
	row = clampi(row, 0, int(_map.size) - 1)
	if _water_profiles.has(row):return _water_profiles[row]
	var first: int = -1
	var last: int = -1
	for x: int in range(int(_map.size)):
		if int(_map.terrain[row][x]) == MAP.WATER:
			if first < 0:first = x
			last = x + 1
	var bounds := Vector2(first, last)
	_water_profiles[row] = bounds
	return bounds


func _river_direction(point: Vector2) -> Vector2:
	var before: Vector2 = _water_row_bounds(floori(point.y) - 2)
	var after: Vector2 = _water_row_bounds(floori(point.y) + 2)
	if before.x < 0.0 or after.x < 0.0:return Vector2.DOWN
	return Vector2((after.x + after.y - before.x - before.y) * 0.5, 4.0).normalized()


func _paint_water_top(data: Dictionary, start: int) -> void:
	# Shared vertex samples replace tile colours with broad blue washes. This
	# changes paint only; the river grid, water height and cliff corners stay put.
	for index: int in range(start, data.vertices.size()):
		var point: Vector3 = data.vertices[index]
		if _map.has("profile"):
			var shade: float = _noise.get_noise_2d(point.x * 0.43, point.z * 0.43) * 0.06
			data.colors[index] = Color(str(_map.profile.water)).lightened(shade)
			continue
		var bounds: Vector2 = _water_row_bounds(floori(point.z))
		var half_width: float = maxf((bounds.y - bounds.x) * 0.5, 1.0)
		var across: float = clampf(absf(point.x - (bounds.x + bounds.y) * 0.5) / half_width, 0.0, 1.0)
		var broad: float = _noise.get_noise_2d(point.x * 0.55 + 413.0, point.z * 0.80 - 173.0)
		var wash: float = clampf(0.16 + pow(across, 1.3) * 0.43 + broad * 0.35, 0.06, 0.75)
		data.colors[index] = Color("245b88").lerp(Color("5898bf"), wash)


func _water_points_valid(points: Array[Vector2], height: float) -> bool:
	for point: Vector2 in points:
		var cell := Vector2i(floori(point.x), floori(point.y))
		if not _inside(cell.x, cell.y) or int(_map.terrain[cell.y][cell.x]) != MAP.WATER:
			return false
		if not is_equal_approx(_surface_height(point.x, point.y, true), height):return false
	return true


func _water_ribbon(data: Dictionary, points: Array[Vector2], width: float, color: Color, height: float) -> void:
	for index: int in range(points.size() - 1):
		var start: Vector2 = points[index]
		var end: Vector2 = points[index + 1]
		var direction: Vector2 = (end - start).normalized()
		var side := Vector2(-direction.y, direction.x)
		var head_width: float = width * 0.5 * maxf(0.22, sin(float(index) / float(points.size() - 1) * PI))
		var tail_width: float = width * 0.5 * maxf(0.22, sin(float(index + 1) / float(points.size() - 1) * PI))
		var corners: Array[Vector2] = [start - side * head_width, end - side * tail_width, end + side * tail_width, start + side * head_width]
		var probes: Array[Vector2] = corners.duplicate()
		probes.append(start.lerp(end, 0.5))
		if not _water_points_valid(probes, height):continue
		var y: float = height + 0.014
		_quad(data, Vector3(corners[0].x, y, corners[0].y), Vector3(corners[1].x, y, corners[1].y), Vector3(corners[2].x, y, corners[2].y), Vector3(corners[3].x, y, corners[3].y), color, Vector3.UP)


func _water_marks(data: Dictionary, x: int, z: int, height: float) -> void:
	# Curves follow the existing river bend, with static irregular placement.
	# No TIME or wall clock: both frozen captures and normal play are stable.
	var ripple_patch: float = _noise.get_noise_2d(x * 2.8 + 173.0, z * 2.8 - 84.0)
	if _static_hash(x, z, 51.0) < 0.38 or ripple_patch < -0.10:return
	var centre := Vector2(x + 0.25 + _static_hash(x, z, 52.0) * 0.5, z + 0.15 + _static_hash(x, z, 53.0) * 0.65)
	var direction: Vector2 = _river_direction(centre)
	var side := Vector2(-direction.y, direction.x)
	var length: float = 0.65 + _static_hash(x, z, 54.0) * 0.8
	var bend: float = (_static_hash(x, z, 55.0) - 0.5) * 0.55
	var points: Array[Vector2] = []
	for index: int in range(7):
		var fraction: float = float(index) / 6.0
		points.append(centre + side * ((fraction - 0.5) * length) + direction * sin(fraction * PI) * (0.12 + absf(bend)))
	var width: float = 0.040 + _static_hash(x, z, 56.0) * 0.030
	var color: Color = Color("90bdc5").lerp(Color("c5dce0"), _static_hash(x, z, 57.0))
	_water_ribbon(data, points, width, color, height)
	# Smaller broken companions form a patch of wave fronts. Clear pools
	# alternate with ripples; long downstream wisps are reserved for rock wakes.
	if _static_hash(x, z, 58.0) > 0.46:
		var echo: Array[Vector2] = []
		for index: int in range(5):
			var fraction: float = float(index) / 4.0
			echo.append(centre + direction * 0.27 + side * ((fraction - 0.5) * length * 0.60) + direction * sin(fraction * PI) * 0.13)
		_water_ribbon(data, echo, width * 0.65, Color("8bb8c4"), height)


func _water_bridge_clear(point: Vector2) -> bool:
	for bridge: Dictionary in _map.bridges:
		var bounds: Array = bridge.bounds
		var protection := Rect2(Vector2(bounds[0], bounds[1]) - Vector2.ONE * 2.0, Vector2(bounds[2], bounds[3]) + Vector2.ONE * 4.0)
		if protection.has_point(point):return false
	return true


func _append_water_rock(data: Dictionary, position: Vector3, dimensions: Vector3, angle: float, variant: int) -> void:
	var rock: Dictionary = _data()
	_rock(rock, variant)
	var basis: Basis = Basis(Vector3.UP, angle).scaled(dimensions)
	var normal_basis: Basis = basis.inverse().transposed()
	for index: int in range(rock.vertices.size()):
		data.vertices.append(position + basis * rock.vertices[index])
		data.normals.append((normal_basis * rock.normals[index]).normalized())
		var tint: Color = rock.colors[index]
		data.colors.append(tint.lerp(Color("998970"), 0.28))


func _build_water_banks() -> void:
	if _map.has("ruins"):return
	# Small partly submerged groups live strictly inside impassable water cells.
	# Their independent node survives G0's authoritative PropBatch restoration.
	var stones: Dictionary = _data()
	var foam: Dictionary = _data()
	var anchors: Array[Vector2] = []
	for z: int in range(1, int(_map.size) - 1):
		for x: int in range(1, int(_map.size) - 1):
			if int(_map.terrain[z][x]) != MAP.WATER or _static_hash(x, z, 61.0) > 0.18:continue
			var edge: bool = false
			for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if int(_map.terrain[z + direction.y][x + direction.x]) != MAP.WATER:edge = true
			if not edge:continue
			var point := Vector2(x + 0.5, z + 0.5)
			if not _water_bridge_clear(point):continue
			var separated: bool = true
			for previous: Vector2 in anchors:
				if previous.distance_to(point) < 4.3:separated = false
			if not separated:continue
			anchors.append(point)
			var height: float = _surface_height(point.x, point.y, true)
			var angle: float = _static_hash(x, z, 62.0) * TAU
			_append_water_rock(stones, Vector3(point.x - 0.07, height - 0.07, point.y), Vector3(0.85, 0.68, 0.85), angle, 0)
			_append_water_rock(stones, Vector3(point.x + 0.19, height - 0.035, point.y + 0.16), Vector3(0.48, 0.43, 0.48), angle + 1.3, 1)
			var flow: Vector2 = _river_direction(point)
			var side := Vector2(-flow.y, flow.x)
			for sign_side: float in [-1.0, 1.0]:
				var wake: Array[Vector2] = []
				for step: int in range(6):
					var fraction: float = float(step) / 5.0
					wake.append(point + flow * (0.08 + fraction * 1.65) + side * sign_side * (0.36 + sin(fraction * PI) * 0.15 - fraction * 0.25))
				_water_ribbon(foam, wake, 0.060, Color("cbdedc"), height)
	CLIFF_CRAFT.append_bank_rocks(self, stones)
	if stones.vertices.is_empty():return
	var root := Node3D.new()
	root.name = "WaterBank"
	add_child(root)
	_instance(_finish(stones), root, "SubmergedReefs")
	if not foam.vertices.is_empty():
		var foam_mesh: MeshInstance3D = _instance(_finish(foam, "water"), root, "ReefFlow")
		foam_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _ground_details(data: Dictionary, x: float, z: float, height: float) -> void:
	# Printed gravel lies on the true top. The few tiny paper blades have no
	# collision and never change the map's navigation or placement footprint.
	var y: float = height + 0.008
	for blade: int in range(3):
		var angle: float = float(blade) * 2.1 + x * 0.43
		var base := Vector3(x + cos(angle) * 0.14, y, z + sin(angle) * 0.14)
		var across := Vector3(cos(angle + 1.57), 0, sin(angle + 1.57)) * 0.075
		_triangle(data, base - across, base + Vector3(cos(angle) * 0.23, 0.18 + blade * 0.035, sin(angle) * 0.23), base + across, Color("667449"), Vector3(cos(angle), 0, sin(angle)))
	for fleck: int in range(2):
		var px: float = x - 0.22 + fleck * 0.20
		_quad(data, Vector3(px, y, z + 0.13), Vector3(px - 0.07, y, z + 0.30), Vector3(px + 0.19, y, z + 0.34), Vector3(px + 0.23, y, z + 0.18), Color("827357"), Vector3.UP)
	for leaf: int in range(3):
		var angle: float = _static_hash(x, z, 21.0 + leaf) * TAU
		var centre := Vector3(x, y, z) + Vector3(cos(angle), 0, sin(angle)) * (0.13 + leaf * 0.055)
		var along := Vector3(cos(angle + 0.7), 0, sin(angle + 0.7)) * 0.10
		var across := Vector3(-along.z, 0, along.x) * 0.42
		var color: Color = Color("8a6945") if leaf % 2 == 0 else Color("74724d")
		_quad(data, centre - along, centre + across, centre + along, centre - across, color, Vector3.UP)


func _prepare_ground_exclusions(sim: WarSimulation) -> void:
	_ground_exclusions.clear()
	# The low scraps never create a new blocker. Keep the occupied area and its
	# immediate apron legible in the scene that is actually being built.
	for entity: Dictionary in sim.entities.values():
		if not bool(entity.get("alive", true)):
			continue
		var definition: Dictionary = sim.data_for(str(entity.spec))
		if str(entity.kind) == "building":
			var half: float = float(definition.get("size", 1.0)) * 0.5 + 0.8
			_ground_exclusions.append({"pos": entity.pos, "half": half})
		else:
			_ground_exclusions.append({"pos": entity.pos, "radius": float(definition.get("radius", 0.35)) + 0.45})
	for mine: Dictionary in sim.mines:
		_ground_exclusions.append({"pos": mine.pos, "radius": 1.8})
	for bridge: Dictionary in _map.bridges:
		var bounds: Array = bridge.bounds
		_ground_exclusions.append({"rect": Rect2(Vector2(bounds[0], bounds[1]), Vector2(bounds[2], bounds[3])).grow(1.5)})
		for head: Array in bridge.heads:
			_ground_exclusions.append({"pos": Vector2(head[0], head[1]), "radius": 2.6})


func _prepare_ground_islands() -> void:
	_ground_islands.clear()
	_ground_island_centres.clear()
	_ground_run_centres.clear()
	_ground_earth_marks.clear()
	if _map.has("profile"): return
	# These are short, broken margins attached to scenery, not identical plants
	# stationed beside the route. Each run changes from earth to litter, gravel
	# or sparse grass and can narrow to nothing as the true support runs out.
	if int(_map.size) == 160:
		var margins: Array = [
			{"points": [Vector2(65.6, 111.8), Vector2(65.8, 113.3), Vector2(66.1, 115.8)], "width": 0.92, "profile": 2, "salt": 112.0},
			{"points": [Vector2(81.8, 109.6), Vector2(80.6, 110.9), Vector2(79.3, 111.9), Vector2(77.8, 113.0)], "width": 1.14, "profile": 1, "salt": 117.0},
			{"points": [Vector2(62.6, 116.5), Vector2(62.5, 117.8), Vector2(61.6, 119.1), Vector2(60.5, 120.4)], "width": 1.24, "profile": 3, "salt": 122.0},
			{"points": [Vector2(75.8, 103.6), Vector2(75.9, 105.0), Vector2(76.7, 106.1), Vector2(77.9, 106.8)], "width": 1.12, "profile": 0, "salt": 127.0},
			{"points": [Vector2(80.9, 116.8), Vector2(80.0, 118.4), Vector2(79.0, 120.3)], "width": 1.20, "profile": 2, "salt": 132.0},
			{"points": [Vector2(64.9, 119.2), Vector2(63.8, 120.4), Vector2(62.1, 121.7)], "width": 0.86, "profile": 0, "salt": 137.0}
		]
		for mirror: bool in [false, true]:
			for margin: Dictionary in margins:
				var points: Array[Vector2] = []
				for point: Vector2 in margin.points:
					points.append(Vector2(160.0 - point.x, point.y) if mirror else point)
				_ground_margin(points, float(margin.width), int(margin.profile), float(margin.salt))
	# Less frequent edge runs extend the same vocabulary to fresh maps. Their
	# tangent is derived from the nearest forest, road or real height/water edge.
	# Open interiors do not receive an extra blanket of evenly scattered dots.
	for gz: int in range(1, ceili(float(_map.size) / 5.2)):
		for gx: int in range(1, ceili(float(_map.size) / 5.2)):
			var centre := Vector2(float(gx) * 5.2, float(gz) * 5.2)
			centre += Vector2(_static_hash(gx, gz, 93.0) - 0.5, _static_hash(gx, gz, 94.0) - 0.5) * 2.8
			if not _inside(floori(centre.x), floori(centre.y)) or not _ground_island_safe(centre, 0.55):
				continue
			var near: bool = false
			for previous: Vector2 in _ground_run_centres:
				if centre.distance_squared_to(previous) < 26.0:
					near = true
					break
			if near:
				continue
			var context: Vector2 = _ground_context(centre.x, centre.y)
			var shoulder: float = _ground_road_shoulder(centre)
			var weight: float = maxf(context.x * 1.7, maxf(context.y * 1.65, shoulder * 0.65))
			if weight < 0.18 or _static_hash(gx, gz, 95.0) > minf(0.70, weight):
				continue
			var tangent: Vector2 = _ground_edge_tangent(centre)
			var length: float = 2.5 + _static_hash(gx, gz, 96.0) * 1.2
			var profile: int = 0 if context.x > context.y else 1
			if shoulder > maxf(context.x, context.y):
				profile = 3
			var points: Array[Vector2] = [centre - tangent * length * 0.45, centre, centre + tangent * length * 0.55]
			_ground_margin(points, 0.75 + _static_hash(gx, gz, 97.0) * 0.5, profile, 130.0)


func _ground_edge_tangent(centre: Vector2) -> Vector2:
	var nearest: Vector2 = centre + Vector2.RIGHT
	var best: float = INF
	var cell := Vector2i(floori(centre.x), floori(centre.y))
	var level: float = MAP.height_at(_map, centre)
	for dz: int in range(-4, 5):
		for dx: int in range(-4, 5):
			var point := cell + Vector2i(dx, dz)
			if not _inside(point.x, point.y):
				continue
			var kind: int = int(_map.terrain[point.y][point.x])
			var edge: bool = kind in [MAP.BLOCKED, MAP.WATER, MAP.ROAD] or not is_equal_approx(float(_map.heights[point.y][point.x]), level)
			for mark: Dictionary in _ground_marks.get(point, []):
				edge = edge or float(mark.offset) > 0.0035
			var spot: Vector2 = Vector2(point) + Vector2.ONE * 0.5
			var distance: float = spot.distance_squared_to(centre)
			if edge and distance < best and distance > 0.0001:
				best = distance
				nearest = spot
	var normal: Vector2 = (centre - nearest).normalized()
	return Vector2(-normal.y, normal.x)


func _ground_margin(points: Array[Vector2], width: float, profile: int, salt: float) -> void:
	var length: float = 0.0
	for index: int in range(points.size() - 1):
		length += points[index].distance_to(points[index + 1])
	if length < 0.1:
		return
	_ground_run_centres.append(points[points.size() / 2])
	var offset: float = 0.0
	for index: int in range(points.size() - 1):
		var segment: float = points[index].distance_to(points[index + 1])
		var tangent: Vector2 = (points[index + 1] - points[index]).normalized()
		var side := Vector2(-tangent.y, tangent.x)
		var steps: int = maxi(1, ceili(segment / 0.38))
		for step: int in steps:
			var fraction: float = float(step) / float(steps)
			var centre: Vector2 = points[index].lerp(points[index + 1], fraction)
			var progress: float = (offset + segment * fraction) / length
			var pulse: float = 0.38 + _static_hash(centre.x, centre.y, salt) * 0.62
			var spread: float = width * pulse * (0.35 + sin(progress * PI) * 0.65)
			# Torn printed earth connects some pieces, then gives way to bare
			# ground. It has a faded edge, no complete raised paper-pad outline.
			if (step + index) % 2 == 0:
				_ground_earth_fringe(centre, tangent, spread, profile, salt + 1.0)
			for lane: int in 3:
				var across: float = float(lane - 1) * 0.45 + (_static_hash(centre.x + lane, centre.y, salt + 2.0) - 0.5) * 0.38
				var position: Vector2 = centre + side * spread * across
				position += tangent * (_static_hash(centre.x, centre.y + lane, salt + 3.0) - 0.5) * 0.27
				var chance: float = _static_hash(position.x, position.y, salt + 4.0)
				if chance > 0.76 - absf(across) * 0.25:
					continue
				var grass: float = 0.44 * (1.0 - progress) + 0.05 if profile == 0 else 0.27 if profile == 2 else 0.055
				var gravel: float = 0.66 if profile == 1 else 0.28 if profile == 3 else 0.18
				var kind: String = "grass" if chance < grass else "scree" if chance < grass + gravel else "litter"
				var radius: float = 0.21 + _static_hash(position.x, position.y, salt + 5.0) * 0.13 if kind == "grass" else 0.10 + _static_hash(position.x, position.y, salt + 6.0) * 0.13
				_add_ground_piece(position, radius, kind, atan2(tangent.y, tangent.x) + (_static_hash(position.x, position.y, salt + 7.0) - 0.5) * 1.9, salt + 8.0)
		offset += segment


func _add_ground_piece(centre: Vector2, radius: float, kind: String, angle: float, salt: float) -> void:
	if not _ground_island_safe(centre, radius + 0.30):
		return
	for previous: Dictionary in _ground_island_centres:
		if centre.distance_squared_to(previous.centre) < pow((radius + float(previous.radius)) * 0.70, 2.0):
			return
	var piece: Dictionary = {"centre": centre, "radius": radius, "level": MAP.height_at(_map, centre), "kind": kind, "angle": angle, "salt": salt}
	var cell := Vector2i(floori(centre.x), floori(centre.y))
	if not _ground_islands.has(cell):
		_ground_islands[cell] = []
	_ground_islands[cell].append(piece)
	_ground_island_centres.append(piece)


func _ground_earth_fringe(centre: Vector2, tangent: Vector2, width: float, profile: int, salt: float) -> void:
	if not _inside(floori(centre.x), floori(centre.y)):
		return
	var side := Vector2(-tangent.y, tangent.x)
	var level: float = MAP.height_at(_map, centre)
	var length: float = 0.44 + _static_hash(centre.x, centre.y, salt) * 0.50
	var offset: float = (_static_hash(centre.x, centre.y, salt + 1.0) - 0.5) * width * 0.6
	var root: Vector2 = centre + side * offset
	var dark: float = 0.36 + _static_hash(centre.x, centre.y, salt + 2.0) * 0.25
	var tint: Color = Color("827357").lerp(Color("74724d"), 0.13 if profile == 0 else 0.0)
	# Two unequal tapered tears overlap at one end, with bare paper between
	# their tips. The shape never closes into the nine-sided mat used by A.
	for tear: int in 2:
		var spine: Vector2 = root + side * width * (float(tear) - 0.5) * 0.32
		var a: Vector2 = spine - tangent * length * 0.48
		var b: Vector2 = spine - tangent * length * 0.08 + side * width * (0.24 if tear == 0 else -0.22)
		var c: Vector2 = spine + tangent * length * (0.67 if tear == 0 else 0.43)
		var d: Vector2 = spine + tangent * length * 0.10 - side * width * (0.13 if tear == 0 else -0.17)
		var core := Vector3(spine.x, spine.y, dark)
		var ring: Array[Vector3] = [Vector3(a.x, a.y, 0.0), Vector3(b.x, b.y, dark * 0.13), Vector3(c.x, c.y, 0.0), Vector3(d.x, d.y, dark * 0.22)]
		for corner: int in 4:
			_store_ground_earth([core, ring[corner], ring[(corner + 1) % 4]], tint, level)


func _store_ground_earth(polygon: Array[Vector3], tint: Color, level: float) -> void:
	var bounds := Rect2(Vector2(polygon[0].x, polygon[0].y), Vector2.ZERO)
	for point: Vector3 in polygon:
		bounds = bounds.expand(Vector2(point.x, point.y))
	for z: int in range(maxi(floori(bounds.position.y), 0), mini(ceili(bounds.end.y), int(_map.size))):
		for x: int in range(maxi(floori(bounds.position.x), 0), mini(ceili(bounds.end.x), int(_map.size))):
			if int(_map.terrain[z][x]) != MAP.LAND or not is_equal_approx(float(_map.heights[z][x]), level) or _cell_rim_changed(x, z, level):
				continue
			if not _ground_island_safe(Vector2(x + 0.5, z + 0.5), 0.71):
				continue
			var clipped: Array[Vector3] = polygon.duplicate()
			for boundary: int in 4:
				var coordinate: int = 0 if boundary < 2 else 1
				var limit: float = float(x if coordinate == 0 else z) + float(boundary % 2)
				clipped = _clip_ground_mark(clipped, coordinate, limit, boundary % 2 == 0)
				if clipped.size() < 3:
					break
			if clipped.size() >= 3:
				var cell := Vector2i(x, z)
				if not _ground_earth_marks.has(cell):
					_ground_earth_marks[cell] = []
				_ground_earth_marks[cell].append({"polygon": clipped, "tint": tint, "level": level})


func _ground_road_shoulder(centre: Vector2) -> float:
	var result: float = 0.0
	var cell := Vector2i(floori(centre.x), floori(centre.y))
	for dz: int in range(-4, 5):
		for dx: int in range(-4, 5):
			var point := cell + Vector2i(dx, dz)
			if not _inside(point.x, point.y):
				continue
			var road: bool = int(_map.terrain[point.y][point.x]) == MAP.ROAD
			for mark: Dictionary in _ground_marks.get(point, []):
				road = road or float(mark.offset) > 0.0035
			if road and is_equal_approx(float(_map.heights[point.y][point.x]), MAP.height_at(_map, centre)):
				result = maxf(result, clampf(1.0 - centre.distance_to(Vector2(point) + Vector2.ONE * 0.5) / 4.5, 0.0, 1.0))
	return result


func _ground_island_safe(centre: Vector2, radius: float) -> bool:
	if not _inside(floori(centre.x), floori(centre.y)):
		return false
	var level: float = MAP.height_at(_map, centre)
	# The piece envelope, plus 30 cm, must rest on real flat LAND. Taking
	# every cell touched by the disc prevents a cut corner or thin ledge from
	# acquiring an unsupported floating paper fringe.
	for z: int in range(floori(centre.y - radius), ceili(centre.y + radius)):
		for x: int in range(floori(centre.x - radius), ceili(centre.x + radius)):
			var nearest := Vector2(clampf(centre.x, float(x), float(x + 1)), clampf(centre.y, float(z), float(z + 1)))
			if nearest.distance_squared_to(centre) > radius * radius:
				continue
			if not _inside(x, z) or int(_map.terrain[z][x]) != MAP.LAND or not is_equal_approx(float(_map.heights[z][x]), level):
				return false
			for mark: Dictionary in _ground_marks.get(Vector2i(x, z), []):
				if float(mark.offset) > 0.0035:
					return false
	for exclusion: Dictionary in _ground_exclusions:
		if exclusion.has("rect"):
			if (exclusion.rect as Rect2).grow(radius).has_point(centre):
				return false
		elif exclusion.has("half"):
			var half: float = float(exclusion.half) + radius
			if absf(centre.x - exclusion.pos.x) < half and absf(centre.y - exclusion.pos.y) < half:
				return false
		elif centre.distance_squared_to(exclusion.pos) < pow(float(exclusion.radius) + radius, 2.0):
			return false
	return true


func _ground_ecology(data: Dictionary, cell: Vector2i) -> void:
	for mark: Dictionary in _ground_earth_marks.get(cell, []):
		var polygon: Array[Vector3] = mark.polygon
		for index: int in range(1, polygon.size() - 1):
			var points: Array[Vector3] = [polygon[0], polygon[index], polygon[index + 1]]
			var start: int = data.vertices.size()
			_triangle(data, Vector3(points[0].x, float(mark.level) + 0.006, points[0].y), Vector3(points[1].x, float(mark.level) + 0.006, points[1].y), Vector3(points[2].x, float(mark.level) + 0.006, points[2].y), Color.WHITE, Vector3.UP)
			for vertex: int in range(start, data.vertices.size()):
				var position: Vector3 = data.vertices[vertex]
				for point: Vector3 in points:
					if position.x == point.x and position.z == point.y:
						data.colors[vertex] = _ground_color(position.x, position.z, MAP.LAND).lerp(mark.tint, point.z)
	for piece: Dictionary in _ground_islands.get(cell, []):
		var centre: Vector2 = piece.centre
		var base := Vector3(centre.x, float(piece.level) + 0.012, centre.y)
		if str(piece.kind) == "grass":
			_ground_folded_grass(data, base, float(piece.radius), float(piece.angle), centre, float(piece.salt))
		elif str(piece.kind) == "scree":
			_ground_paper_scree(data, base, float(piece.radius), float(piece.angle), floori(_static_hash(centre.x, centre.y, float(piece.salt)) * 4.0))
		else:
			_ground_litter(data, base, float(piece.radius), float(piece.angle), floori(_static_hash(centre.x, centre.y, float(piece.salt)) * 4.0))


func _ground_folded_grass(data: Dictionary, base: Vector3, radius: float, angle: float, centre: Vector2, salt: float) -> void:
	# Narrow low folded strips replace A's radial succulent-like flower. The
	# three unequal leaves lean together, with an occasional small raised tip.
	for blade: int in 3:
		var phase: float = angle + float(blade - 1) * 0.40 + _static_hash(centre.x + blade, centre.y, salt) * 0.25
		var length: float = radius * (0.73 + _static_hash(centre.x, centre.y + blade, salt + 1.0) * 0.25)
		var height: float = 0.08 + float(blade) * 0.045 + _static_hash(centre.x + blade, centre.y, salt + 2.0) * 0.03
		var along := Vector3(cos(phase), 0, sin(phase))
		var across := Vector3(-along.z, 0, along.x) * radius * (0.11 + float(blade % 2) * 0.045)
		var crease: Vector3 = base + along * length * 0.42 + Vector3.UP * height
		var tip: Vector3 = base + along * length + Vector3.UP * height * (0.34 + float(blade) * 0.10)
		var green: Color = Color("667449").darkened(float(blade % 3) * 0.055)
		_triangle(data, base - across, crease, tip, green, Vector3.UP)
		_triangle(data, base + across, tip, crease, green.lightened(0.075), Vector3.UP)
		_triangle(data, base - across, base + across, crease, green.darkened(0.15), -along)


func _ground_litter(data: Dictionary, base: Vector3, radius: float, angle: float, variant: int) -> void:
	var along := Vector3(cos(angle), 0, sin(angle)) * radius
	var across := Vector3(-sin(angle), 0, cos(angle)) * radius * 0.34
	var ridge: Vector3 = base + along * 0.12 + Vector3.UP * 0.025
	var tint: Color = Color("8a6945") if variant % 2 == 0 else Color("74724d")
	_triangle(data, base - along * 0.86 - across, ridge, base + along, tint, Vector3.UP)
	_triangle(data, base - along * 0.70 + across, base + along, ridge, tint.lightened(0.055), Vector3.UP)


func _ground_paper_scree(data: Dictionary, centre: Vector3, radius: float, angle: float, variant: int) -> void:
	# Broken masonry chips replace the remaining loose ground stones.
	var height: float = .045 + float(variant % 3) * .027
	_box(data,centre+Vector3.UP*height*.5,Vector3(radius*1.6,height,radius*.8),Color("a89473"),Basis(Vector3.UP,angle))


func _battle_marks(data: Dictionary, x: int, z: int, height: float) -> void:
	# Paint belongs to the existing ground batch. Each piece is already clipped
	# to one legal, flat cell, so neither river decks nor cliff edges get a road.
	var cell := Vector2i(x, z)
	if not _ground_marks.has(cell):
		return
	var terrain: int = int(_map.terrain[z][x])
	for mark: Dictionary in _ground_marks[cell]:
		if not is_equal_approx(height, float(mark.level)):
			continue
		var polygon: Array[Vector3] = mark.polygon
		var y: float = height + float(mark.offset)
		for index: int in range(1, polygon.size() - 1):
			var points: Array[Vector3] = [polygon[0], polygon[index], polygon[index + 1]]
			var start: int = data.vertices.size()
			_triangle(data, Vector3(points[0].x, y, points[0].y), Vector3(points[1].x, y, points[1].y), Vector3(points[2].x, y, points[2].y), Color.WHITE, Vector3.UP)
			for vertex_index: int in range(start, data.vertices.size()):
				var vertex: Vector3 = data.vertices[vertex_index]
				for point: Vector3 in points:
					if vertex.x == point.x and vertex.z == point.y:
						data.colors[vertex_index] = _ground_color(vertex.x, vertex.z, terrain).lerp(mark.tint, point.z)
						break


func _prepare_battle_marks() -> void:
	_ground_marks.clear()
	if int(_map.size) != 160:
		return
	# A narrow neck clears the south-facing factory door. The worn track opens
	# up only beyond its footprint, then ends on the land at the real bridgehead.
	var blue: Array[Vector2] = [Vector2(64, 99.4), Vector2(66.8, 99.4), Vector2(68.5, 98.2), Vector2(70.8, 96.65), Vector2(75.5, 96.5)]
	var red: Array[Vector2] = [Vector2(96, 99.4), Vector2(93.2, 99.4), Vector2(91.5, 98.2), Vector2(89.2, 96.65), Vector2(84.5, 96.5)]
	var widths: Array[float] = [0.76, 1.10, 1.95, 2.40, 1.90]
	_worn_road(blue, widths)
	_worn_road(red, widths)
	# A worn, bending approach continues past the bridge bases towards the
	# southern bypass. These are paint on existing flat land, not new paths.
	for mirror: bool in [false, true]:
		var route: Array[Vector2] = [Vector2(68.0, 109.5), Vector2(70.0, 113.0), Vector2(72.0, 117.0), Vector2(72.0, 120.0), Vector2(69.0, 124.0), Vector2(64.0, 130.0)]
		if mirror:
			for index: int in route.size():route[index].x = 160.0 - route[index].x
		_worn_road(route, [1.1, 1.6, 1.9, 1.8, 1.6, 1.1])
	# Elongated earth beside the route gives the pale wear a darker shoulder;
	# its soft fringe overlaps the road edge while the road itself stays intact.
	_soil_wash(Vector2(70.5, 95.30), Vector2(4.20, 1.75), 0.0, 18.0, 0.55, 0.42)
	_soil_wash(Vector2(89.5, 95.25), Vector2(4.20, 1.90), 0.0, 23.0, 0.55, 0.42)
	_soil_wash(Vector2(72.0, 114.5), Vector2(4.00, 2.30), 0.0, 28.0)


func _worn_road(anchors: Array[Vector2], widths: Array[float]) -> void:
	var centres: Array[Vector2] = []
	var half_widths: Array[float] = []
	for index: int in range(anchors.size() - 1):
		var steps: int = ceili(anchors[index].distance_to(anchors[index + 1]) / 0.8)
		for step: int in steps:
			var fraction: float = float(step) / float(steps)
			var point: Vector2 = anchors[index].lerp(anchors[index + 1], fraction)
			centres.append(point)
			half_widths.append(lerpf(widths[index], widths[index + 1], fraction) * 0.5 * (0.91 + _static_hash(point.x, point.y, 16.0) * 0.16))
	centres.append(anchors.back())
	half_widths.append(widths.back() * 0.5)
	var cross_sections: Array = []
	for index: int in centres.size():
		var previous: Vector2 = centres[maxi(index - 1, 0)]
		var following: Vector2 = centres[mini(index + 1, centres.size() - 1)]
		var tangent: Vector2 = (following - previous).normalized()
		var side := Vector2(-tangent.y, tangent.x)
		var strength: float = 0.78 + _static_hash(centres[index].x, centres[index].y, 17.0) * 0.12
		if index == 0 or index == centres.size() - 1:
			strength *= 0.6
		var section: Array[Vector3] = []
		for lane: int in 4:
			var across: float = [-1.0, -0.56, 0.56, 1.0][lane]
			var point: Vector2 = centres[index] + side * half_widths[index] * across
			section.append(Vector3(point.x, point.y, 0.0 if lane in [0, 3] else strength))
		cross_sections.append(section)
	var tint: Color = Color("dcccad").lerp(Color("a18d70"), 0.12)
	for index: int in range(cross_sections.size() - 1):
		for lane: int in 3:
			var polygon: Array[Vector3] = [cross_sections[index][lane], cross_sections[index + 1][lane], cross_sections[index + 1][lane + 1], cross_sections[index][lane + 1]]
			_store_ground_mark(polygon, tint, 0.0, 0.004)


func _soil_wash(centre: Vector2, extent: Vector2, level: float, salt: float, core_strength: float = 0.45, inner_strength: float = 0.35) -> void:
	var edge: Array[Vector2] = []
	for index: int in 10:
		var angle: float = float(index) / 10.0 * TAU
		var radius: float = 0.82 + _static_hash(centre.x + index, centre.y, salt) * 0.25
		edge.append(centre + Vector2(cos(angle) * extent.x, sin(angle) * extent.y) * radius)
	var tint := Color("857054")
	for index: int in edge.size():
		var a: Vector2 = edge[index]
		var b: Vector2 = edge[(index + 1) % edge.size()]
		var inner_a: Vector2 = centre.lerp(a, 0.54)
		var inner_b: Vector2 = centre.lerp(b, 0.54)
		var core: Array[Vector3] = [Vector3(centre.x, centre.y, core_strength), Vector3(inner_a.x, inner_a.y, inner_strength), Vector3(inner_b.x, inner_b.y, inner_strength)]
		var fringe: Array[Vector3] = [Vector3(inner_a.x, inner_a.y, inner_strength), Vector3(a.x, a.y, 0.0), Vector3(b.x, b.y, 0.0), Vector3(inner_b.x, inner_b.y, inner_strength)]
		_store_ground_mark(core, tint, level, 0.003)
		_store_ground_mark(fringe, tint, level, 0.003)


func _store_ground_mark(polygon: Array[Vector3], tint: Color, level: float, offset: float) -> void:
	# Vector3 here carries (map x, map z, paint strength). Intersections retain
	# strength, producing a soft irregular wash without a transparent draw call.
	var bounds := Rect2(Vector2(polygon[0].x, polygon[0].y), Vector2.ZERO)
	for point: Vector3 in polygon:
		bounds = bounds.expand(Vector2(point.x, point.y))
	for z: int in range(maxi(floori(bounds.position.y), 0), mini(ceili(bounds.end.y), int(_map.size))):
		for x: int in range(maxi(floori(bounds.position.x), 0), mini(ceili(bounds.end.x), int(_map.size))):
			if int(_map.terrain[z][x]) not in [MAP.LAND, MAP.ROAD] or not is_equal_approx(MAP.height_at(_map, Vector2(x + 0.5, z + 0.5)), level):
				continue
			var clipped: Array[Vector3] = polygon.duplicate()
			for boundary: int in 4:
				var coordinate: int = 0 if boundary < 2 else 1
				var limit: float = float(x if coordinate == 0 else z) + float(boundary % 2)
				clipped = _clip_ground_mark(clipped, coordinate, limit, boundary % 2 == 0)
				if clipped.size() < 3:
					break
			if clipped.size() >= 3:
				var cell := Vector2i(x, z)
				if not _ground_marks.has(cell):
					_ground_marks[cell] = []
				_ground_marks[cell].append({"polygon": clipped, "tint": tint, "level": level, "offset": offset})


func _clip_ground_mark(polygon: Array[Vector3], coordinate: int, limit: float, keep_above: bool) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if polygon.is_empty():
		return result
	var previous: Vector3 = polygon.back()
	var previous_inside: bool = previous[coordinate] >= limit if keep_above else previous[coordinate] <= limit
	for point: Vector3 in polygon:
		var inside: bool = point[coordinate] >= limit if keep_above else point[coordinate] <= limit
		if inside != previous_inside:
			var fraction: float = (limit - previous[coordinate]) / (point[coordinate] - previous[coordinate])
			var intersection: Vector3 = previous.lerp(point, fraction)
			intersection[coordinate] = limit
			result.append(intersection)
		if inside:
			result.append(point)
		previous = point
		previous_inside = inside
	return result


func _inside(x: int, z: int) -> bool:
	return x >= 0 and z >= 0 and x < int(_map.size) and z < int(_map.size)


func _build_props() -> void:
	var rng: RandomNumberGenerator = _prepare_prop_build()
	for decoration: Dictionary in _map.decorations:
		_build_decoration(decoration, rng)
	_finish_prop_build()


func _build_props_with_progress(progress: Callable) -> void:
	var rng: RandomNumberGenerator = _prepare_prop_build()
	var completed: int = 0
	var yielded_at: int = Time.get_ticks_usec()
	for decoration: Dictionary in _map.decorations:
		_build_decoration(decoration, rng)
		completed += 1
		if Time.get_ticks_usec() - yielded_at >= LOAD_YIELD_BUDGET_USEC:
			await progress.call(0.68 + 0.1 * float(completed) / maxi(1, _map.decorations.size()), "布置森林与地物")
			yielded_at = Time.get_ticks_usec()
	await progress.call(0.78, "整理地物")
	_finish_prop_build()


func _prepare_prop_build() -> RandomNumberGenerator:
	# Original trees retain their original LAND neighbours for edge scaling.
	# The appended north wing joins them without rerolling old transforms.
	_north_prop_cells.clear()
	for addition: Dictionary in _map.get("north_context", []):
		_north_prop_cells[Vector2i(floori(float(addition.pos[0])), floori(float(addition.pos[1])))] = true
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_map.seed) + 61841
	_choose_forest_accents()
	return rng


func _build_decoration(decoration: Dictionary, rng: RandomNumberGenerator) -> void:
	var point := Vector2(float(decoration.pos[0]), float(decoration.pos[1]))
	var position := Vector3(point.x, MAP.height_at(_map, point), point.y)
	var transform := Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)), position)
	var cell := Vector2i(floori(point.x), floori(point.y))
	var kind: String = str(decoration.kind) if _map.has("ruins") else str(_accent_cells.get(cell, decoration.kind))
	var size: float = rng.randf_range(0.82, 1.22)
	if int(_map.get("profile", {}).get("design_version", 0)) >= 6 and kind == "tree":
		size *= 2.15 if str(_map.profile.get("biome", "")) == "forest" else 1.55
	if kind == "tree":
		var horizontal: float = size if int(_map.get("profile", {}).get("design_version", 0)) >= 6 else 1.0
		var vertical: float = size
		if int(_map.get("profile", {}).get("design_version", 0)) < 6 and _forest_edge(cell):
			horizontal = 0.52 + _static_hash(point.x, point.y, 31.0) * 0.24
			vertical *= 0.45 + _static_hash(point.x, point.y, 32.0) * 0.45
			var margin: float = (0.47 - horizontal * 0.47) * 0.8
			position.x += (_static_hash(point.x, point.y, 33.0) * 2.0 - 1.0) * margin
			position.z += (_static_hash(point.x, point.y, 34.0) * 2.0 - 1.0) * margin
			transform.origin = position
		transform.basis = transform.basis.scaled(Vector3(horizontal, vertical, horizontal))
		_batch("tree_%d" % rng.randi_range(0, 2), transform)
		_batch("trunk", Transform3D(Basis.IDENTITY.scaled(Vector3(horizontal, vertical, horizontal)), position))
	elif kind == "rock":
		var horizontal: float = minf(size, 1.07)
		var vertical: float = size * (1.8 if _accent_cells.has(cell) else 1.2)
		transform.basis = transform.basis.scaled(Vector3(horizontal, vertical, horizontal))
		_batch("rock_%d" % rng.randi_range(0, 2), transform)
	elif kind == "fence":
		_batch("fence", transform)
	else:
		transform.basis = transform.basis.scaled(Vector3(0.93, 1.0, 0.93))
		_batch("ruin", transform)
	_batch("contact", Transform3D(Basis.IDENTITY, position + Vector3.UP * 0.015))


func _finish_prop_build() -> void:
	if not _map.has("ruins"): _compose_contextual_props()
	_append_foreground_props()


func _append_foreground_props() -> void:
	# Append after all legacy placement/RNG and contextual remapping. Separate
	# groups let explicit G0 fixtures retain their authoritative old transforms.
	var groups: Array = FOREGROUND_GROVE.append_prop_batches(_map, [])
	groups = NORTH_CONTEXT.append_prop_batches(_map, groups)
	for group: Dictionary in groups:
		var key: String = str(group.mesh_key)
		var region: String = str(group.name).trim_prefix("PropBatch_" + key + "_")
		var transforms: Array = []
		for values: Array in group.transforms:
			transforms.append(SCENERY_SCALE.corrected(key, Transform3D(Basis(Vector3(values[0], values[1], values[2]), Vector3(values[3], values[4], values[5]), Vector3(values[6], values[7], values[8])), Vector3(values[9], values[10], values[11]))))
		_batches[key + ":" + region] = {"mesh": _prop_mesh(key), "transforms": transforms, "shadow": int(group.shadow) != 0}
		stats.prop_instances = int(stats.prop_instances) + transforms.size()


func _compose_contextual_props() -> void:
	if int(_map.size) != 160:
		return
	var resolved: Array = []
	for key: String in _batches:
		var group: Dictionary = _batches[key]
		var transforms: Array = []
		for transform: Transform3D in group.transforms:
			transforms.append([transform.basis.x.x, transform.basis.x.y, transform.basis.x.z, transform.basis.y.x, transform.basis.y.y, transform.basis.y.z, transform.basis.z.x, transform.basis.z.y, transform.basis.z.z, transform.origin.x, transform.origin.y, transform.origin.z])
		resolved.append({"name": "PropBatch_" + key.replace(":", "_"), "mesh_key": key.get_slice(":", 0), "shadow": 1 if bool(group.shadow) else 0, "transforms": transforms})
	var composed: Array = CONTEXT_PROPS.remap_prop_batches(_map, resolved)
	_batches.clear()
	stats.prop_instances = 0
	for group: Dictionary in composed:
		var key: String = str(group.mesh_key)
		var region: String = str(group.name).trim_prefix("PropBatch_" + key + "_")
		var transforms: Array = []
		for values: Array in group.transforms:
			transforms.append(SCENERY_SCALE.corrected(key, Transform3D(Basis(Vector3(values[0], values[1], values[2]), Vector3(values[3], values[4], values[5]), Vector3(values[6], values[7], values[8])), Vector3(values[9], values[10], values[11]))))
		_batches[key + ":" + region] = {"mesh": _prop_mesh(key), "transforms": transforms, "shadow": int(group.shadow) != 0}
		stats.prop_instances = int(stats.prop_instances) + transforms.size()


func _forest_edge(cell: Vector2i) -> bool:
	for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var next: Vector2i = cell + direction
		if _inside(next.x, next.y) and (_north_prop_cells.has(next) or (int(_map.terrain[next.y][next.x]) != MAP.BLOCKED and not _tree_cells.has(next))):
			return true
	return false


func _choose_forest_accents() -> void:
	if int(_map.size) != 160:
		return
	var anchors: Array[Vector2] = []
	for decoration: Dictionary in _map.decorations:
		if decoration.kind != "tree":
			continue
		var point := Vector2(float(decoration.pos[0]), float(decoration.pos[1]))
		if point.y < 92.0 or point.y > 127.0 or absf(point.x - 80.0) < 12.0 or absf(point.x - 80.0) > 39.0:
			continue
		var separated: bool = true
		for previous: Vector2 in anchors:
			separated = separated and previous.distance_to(point) >= 13.0
		if not separated:
			continue
		var cell := Vector2i(floori(point.x), floori(point.y))
		var edge: bool = false
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + direction
			if _inside(next.x, next.y) and int(_map.terrain[next.y][next.x]) != MAP.BLOCKED:
				edge = true
		if not edge:
			continue
		anchors.append(point)
		for neighbor: Dictionary in _map.decorations:
			var candidate := Vector2(float(neighbor.pos[0]), float(neighbor.pos[1]))
			if neighbor.kind == "tree" and candidate.distance_to(point) <= 1.45:
				_accent_cells[Vector2i(floori(candidate.x), floori(candidate.y))] = "ruin" if anchors.size() == 2 else "rock"
		if anchors.size() == 3:
			break


func _batch(key: String, transform: Transform3D) -> void:
	transform = SCENERY_SCALE.corrected(key, transform)
	var region: String = "%d_%d" % [floori(transform.origin.x / PROP_CHUNK), floori(transform.origin.z / PROP_CHUNK)]
	var batch_key: String = key + ":" + region
	if not _batches.has(batch_key):
		_batches[batch_key] = {"mesh": _prop_mesh(key), "transforms": [], "shadow": key != "contact"}
	_batches[batch_key].transforms.append(transform)
	stats.prop_instances = int(stats.prop_instances) + 1


func _flush_batches() -> void:
	for key: String in _batches:
		_flush_prop_batch(key, _batches[key])
	_finish_prop_batches()


func _flush_batches_with_progress(progress: Callable) -> void:
	var completed: int = 0
	var yielded_at: int = Time.get_ticks_usec()
	for key: String in _batches:
		_flush_prop_batch(key, _batches[key])
		completed += 1
		if Time.get_ticks_usec() - yielded_at >= LOAD_YIELD_BUDGET_USEC:
			await progress.call(0.9 + 0.09 * float(completed) / maxi(1, _batches.size()), "整理场景物件")
			yielded_at = Time.get_ticks_usec()
	_finish_prop_batches()


func _finish_prop_batches() -> void:
	_batches.clear()
	configure_quality(quality_mode)


func _flush_prop_batch(key: String, group: Dictionary) -> void:
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.mesh = group.mesh
	mesh.instance_count = group.transforms.size()
	for index: int in mesh.instance_count:
		var displayed: Transform3D = group.transforms[index]
		if group.get("neutral_form", "") == "rubble": displayed.basis = Basis.IDENTITY.scaled(Vector3.ZERO)
		mesh.set_instance_transform(index, displayed)
		if key.get_slice(":", 0).begins_with("tree_") or key.get_slice(":", 0).begins_with("environment_") or key.get_slice(":", 0) in ["trunk", "contact"]:
			var transform: Transform3D = group.transforms[index]
			var cell := Vector2i(floori(transform.origin.x), floori(transform.origin.z))
			if _tree_cells.has(cell):
				var tree_id: int = int(_tree_cells[cell])
				if not tree_visuals.has(tree_id): tree_visuals[tree_id] = []
				tree_visuals[tree_id].append({"multi": mesh, "slot": index, "transform": transform, "current_transform": transform})
		if group.has("neutral_ids"):
			var id: int = int(group.neutral_ids[index])
			if not ruin_visuals.has(id): ruin_visuals[id] = {}
			ruin_visuals[id][str(group.neutral_form)] = {"multi": mesh, "slot": index, "transform": group.transforms[index], "current_transform": displayed}
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = mesh
	instance.name = "PropBatch_" + key.replace(":", "_")
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if group.shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if group.has("neutral_ids"):
		instance.set_meta("active_neutrals", 0 if group.neutral_form == "rubble" else group.neutral_ids.size())
		instance.visible = group.neutral_form != "rubble"
		for id: int in group.neutral_ids: ruin_visuals[id][str(group.neutral_form)].node = instance
	if key.get_slice(":", 0) == "trunk":
		var far_mesh := MultiMesh.new()
		far_mesh.transform_format = MultiMesh.TRANSFORM_3D
		far_mesh.mesh = _prop_mesh("trunk_far")
		far_mesh.instance_count = group.transforms.size()
		for index in range(far_mesh.instance_count):
			var transform: Transform3D = group.transforms[index]
			far_mesh.set_instance_transform(index, transform)
			var cell := Vector2i(floori(transform.origin.x), floori(transform.origin.z))
			if _tree_cells.has(cell):
				var id: int = int(_tree_cells[cell])
				tree_visuals[id].append({"multi": far_mesh, "slot": index, "transform": transform, "current_transform": transform})
		var distant := MultiMeshInstance3D.new()
		distant.name = "TrunkFar_" + key.replace(":", "_")
		distant.multimesh = far_mesh
		instance.visibility_range_end = 45.0
		distant.visibility_range_begin = 45.0
		add_child(distant)
		var outline_mesh:=MultiMesh.new()
		outline_mesh.transform_format=MultiMesh.TRANSFORM_3D
		outline_mesh.mesh=_prop_mesh("trunk_distant")
		outline_mesh.instance_count=group.transforms.size()
		for index in range(outline_mesh.instance_count):
			var transform:Transform3D=group.transforms[index]
			outline_mesh.set_instance_transform(index,transform)
			var cell:=Vector2i(floori(transform.origin.x),floori(transform.origin.z))
			if _tree_cells.has(cell):
				tree_visuals[int(_tree_cells[cell])].append({"multi":outline_mesh,"slot":index,"transform":transform,"current_transform":transform})
		var outline:=MultiMeshInstance3D.new()
		outline.name="TrunkDistant_"+key.replace(":","_")
		outline.multimesh=outline_mesh
		add_child(outline)
		_trunk_lods.append({"near":instance,"far":distant,"distant":outline})
	if key.get_slice(":", 0).begins_with("tree_") and not _tree_cells.is_empty():
		instance.lod_bias = TREE_LOD_BIAS
		var distant: ArrayMesh = _prop_shadow_mesh(key.get_slice(":", 0))
		if distant != null:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var near_shadow := MultiMeshInstance3D.new()
			near_shadow.name = "TreeNearCaster_" + key.replace(":", "_")
			near_shadow.multimesh = mesh
			near_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			near_shadow.visibility_range_end = 45.0
			add_child(near_shadow)
			var far_mesh := MultiMesh.new()
			far_mesh.transform_format = MultiMesh.TRANSFORM_3D
			far_mesh.mesh = distant
			far_mesh.instance_count = group.transforms.size()
			for index in range(far_mesh.instance_count):
				var transform: Transform3D = group.transforms[index]
				far_mesh.set_instance_transform(index, transform)
				var cell := Vector2i(floori(transform.origin.x), floori(transform.origin.z))
				if _tree_cells.has(cell):
					var id: int = int(_tree_cells[cell])
					tree_visuals[id].append({"multi": far_mesh, "slot": index, "transform": transform, "current_transform": transform, "shadow": true})
			var far_shadow := MultiMeshInstance3D.new()
			far_shadow.name = "TreeFarCaster_" + key.replace(":", "_")
			far_shadow.multimesh = far_mesh
			far_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			far_shadow.visibility_range_begin = 45.0
			add_child(far_shadow)
			# The same compact geometry and transforms provide the far visual
			# crown; destruction updates the visible and shadow passes together.
			var mid_visual := MultiMeshInstance3D.new()
			mid_visual.name = "TreeMidVisual_" + key.replace(":", "_")
			mid_visual.multimesh = far_mesh
			mid_visual.material_override = _material("foliage")
			mid_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mid_visual)
			var far_visual := MultiMeshInstance3D.new()
			far_visual.name = "TreeFarVisual_" + key.replace(":", "_")
			far_visual.multimesh = far_mesh
			far_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(far_visual)
			_forest_lods.append({"near": instance, "mid": mid_visual, "far": far_visual})
			stats.tree_shadow_batches = int(stats.tree_shadow_batches) + 2
			stats.tree_far_shadow_triangles = int(stats.tree_far_shadow_triangles) + int(distant.get_meta("pine_shadow_triangles", 0)) * far_mesh.instance_count
	add_child(instance)
	stats.prop_draws = int(stats.prop_draws) + 1


func _prop_shadow_mesh(key: String) -> ArrayMesh:
	var cache_key: String = key + ":shadow"
	if _meshes.has(cache_key): return _meshes[cache_key]
	var variant: String = key.get_slice("_", 1)
	var source_path: String = "res://assets/models/pine_%s.res" % variant
	var path: String = "res://assets/models/pine_shadow_%s.res" % variant
	if not ResourceLoader.exists(path) or not FileAccess.file_exists(source_path): return null
	var mesh: ArrayMesh = load(path)
	if str(mesh.get_meta("pine_shadow_source_sha256", "")) != FileAccess.get_sha256(source_path): return null
	_meshes[cache_key] = mesh
	return mesh


func _prop_mesh(key: String) -> ArrayMesh:
	if _meshes.has(key):
		return _meshes[key]
	# LODs are baked offline; exported games need no editor-only ImporterMesh.
	# In the source project a stale bake falls back to the procedural authoring mesh.
	if key.begins_with("tree_"):
		var path: String = "res://assets/models/pine_%s.res" % key.get_slice("_", 1)
		if ResourceLoader.exists(path):
			var baked: ArrayMesh = load(path)
			var hashes: Dictionary = baked.get_meta("pine_source_hashes", {})
			var fresh: bool = true
			for source: String in ["res://scripts/pine_model.gd", "res://scripts/landscape.gd"]:
				if FileAccess.file_exists(source) and FileAccess.get_sha256(source) != str(hashes.get(source, "")):
					fresh = false
			if fresh:
				var mesh: ArrayMesh = baked.duplicate()
				mesh.surface_set_material(0, _material("foliage"))
				_meshes[key] = mesh
				return mesh
	var data: Dictionary = _data()
	var material_kind: String = "paper"
	if key.begins_with("tree"):
		var variant: int = int(key.get_slice("_", 1))
		material_kind = "foliage"
		_tree_miniature_crown(data, variant)
	elif key in ["trunk", "trunk_far", "trunk_distant"]:
		PINE.trunk(self, data, key == "trunk", key != "trunk_distant")
	elif key.begins_with("rock"):
		_rock(data, int(key.get_slice("_", 1)))
	elif key == "fence":
		for x: float in [-0.34, 0.34]:
			_box(data, Vector3(x, 0.52, 0), Vector3(0.075, 1.04, 0.075), Color("756b55"))
		for y: float in [0.36, 0.79]:
			_box(data, Vector3(0, y, 0), Vector3(0.88, 0.065, 0.065), Color("98866a"))
	elif key == "ruin":
		for row: int in range(4):
			for column: int in range(3 - int(row == 3)):
				_box(data, Vector3((column - 1) * 0.27 + (row % 2) * 0.09, 0.14 + row * 0.26, 0), Vector3(0.25, 0.23, 0.34), Color("a89d87").darkened((column + row) % 3 * 0.035))
	elif key in CONTEXT_PROPS.MESH_KEYS:
		_contextual_wall(data, key)
	else:
		material_kind = "contact"
		_contact_disc(data, 0.48)
	var mesh: ArrayMesh = _finish(data, material_kind)
	if key=="trunk_distant":
		# Ink planes protrude by fractions of a millimetre at the upper edge.
		# Retain their conservative culling bounds across the LOD transition.
		mesh.custom_aabb=_prop_mesh("trunk_far").get_aabb()
	_meshes[key] = mesh
	return mesh

func _contextual_wall(data: Dictionary, key: String) -> void:
	var stone := Color("b6a17c")
	var corner: bool = key in ["context_wall_corner_r", "context_wall_corner_l"]
	# The whole paper foundation, including ink, stays inside a 0.85m square.
	_contextual_brick(data, Vector3(0, 0.10, 0), Vector3(0.81, 0.16, 0.81 if corner else 0.41), stone.darkened(0.12))
	var courses: int = 2 if key == "context_wall_stub" else 3
	for row: int in courses:
		for side: int in [-1, 1]:
			var centre := Vector3(side * 0.207, 0.29 + row * 0.23, 0.20 if corner else 0.0)
			_contextual_brick(data, centre, Vector3(0.394, 0.22, 0.32), stone.darkened(float((row + side + 3) % 3) * 0.035))
	if corner:
		var handedness: float = 1.0 if key.ends_with("_r") else -1.0
		for row: int in range(3):
			for depth: int in range(2):
				var centre := Vector3(handedness * 0.21, 0.29 + row * 0.23, -0.075 - depth * 0.22)
				_contextual_brick(data, centre, Vector3(0.32, 0.22, 0.22), stone.darkened(0.045 + depth * 0.025))
		# One surviving high head, supported by the broad low wall below it.
		_contextual_brick(data, Vector3(handedness * 0.21, 0.965, 0.20), Vector3(0.35, 0.19, 0.31), stone)
		_contextual_brick(data, Vector3(handedness * 0.23, 1.14, 0.20), Vector3(0.29, 0.15, 0.29), stone.lightened(0.035))
	elif key == "context_wall_broken":
		_contextual_brick(data, Vector3(-0.20, 0.965, 0.0), Vector3(0.37, 0.19, 0.31), stone.lightened(0.025))
	else:
		# A single broad fallen piece keeps the low end visibly impassable.
		_contextual_brick(data, Vector3(0.17, 0.615, 0.025), Vector3(0.40, 0.15, 0.33), stone.darkened(0.07))


func _contextual_brick(data: Dictionary, centre: Vector3, size: Vector3, tint: Color) -> void:
	var points: Array[Vector3] = []
	for corner: Vector3 in [Vector3(-1,-1,-1), Vector3(1,-1,-1), Vector3(1,1,-1), Vector3(-1,1,-1), Vector3(-1,-1,1), Vector3(1,-1,1), Vector3(1,1,1), Vector3(-1,1,1)]:
		var point: Vector3 = centre + corner * size * 0.5
		if corner.y > 0.0:
			point.x -= 0.009 * corner.x
			point.y += 0.006 if corner.x < 0.0 else -0.009
			point.z -= 0.005 * corner.z
		points.append(point)
	for face: Array in [[0,3,2,1,Vector3.FORWARD], [4,5,6,7,Vector3.BACK], [0,4,7,3,Vector3.LEFT], [1,2,6,5,Vector3.RIGHT], [3,7,6,2,Vector3.UP], [0,1,5,4,Vector3.DOWN]]:
		var normal: Vector3 = face[4]
		var color: Color = tint.lightened(0.065) if normal == Vector3.UP else tint
		_quad(data, points[face[0]], points[face[1]], points[face[2]], points[face[3]], color, normal)
		if normal == Vector3.DOWN:
			continue
		# Printed joints and cut-paper outer edges belong to real volume faces.
		for index: int in range(4):
			_ink_strip(data, points[face[index]], points[face[(index + 1) % 4]], normal, Color("493b2b"), 0.020)


func _tree_miniature_crown(data: Dictionary, variant: int) -> void:
	PINE.crown(self, data, variant)


func _cone(data: Dictionary, bottom: float, height: float, radius: float, color: Color) -> void:
	for side: int in range(10):
		var angle: float = float(side) * TAU / 10.0
		var next: float = float(side + 1) * TAU / 10.0
		var a_radius: float = radius * (1.0 if side % 2 == 0 else 0.70)
		var b_radius: float = radius * (0.70 if side % 2 == 0 else 1.0)
		var a := Vector3(cos(angle) * a_radius, bottom + (0.0 if side % 2 == 0 else height * 0.13), sin(angle) * a_radius)
		var b := Vector3(cos(next) * b_radius, bottom + (height * 0.13 if side % 2 == 0 else 0.0), sin(next) * b_radius)
		var tip := Vector3(0, bottom + height, 0)
		var outside := Vector3(a.x + b.x, 0, a.z + b.z)
		_triangle(data, a, tip, b, color.lightened(0.045 if side % 2 == 0 else 0.0), outside)
		_triangle(data, Vector3(0, bottom, 0), a, b, color.darkened(0.18), Vector3.DOWN)
		var normal: Vector3 = (tip - a).cross(b - a).normalized()
		if normal.dot(outside) < 0.0:
			normal = -normal
		_ink_strip(data, a, b, normal, Color("a8996b"), 0.010)
		if side % 2 == 0:
			_ink_strip(data, a, tip, normal, Color("142f29"), 0.012)


func _ink_strip(data: Dictionary, start: Vector3, end: Vector3, normal: Vector3, color: Color, width: float) -> void:
	var edge: Vector3 = normal.cross((end - start).normalized()).normalized() * width * 0.5
	var offset: Vector3 = normal * 0.002
	_quad(data, start - edge + offset, end - edge + offset, end + edge + offset, start + edge + offset, color, normal)


func _rock(data: Dictionary, variant: int) -> void:
	# Retain placement/footprints while replacing every legacy boulder mesh.
	_contextual_wall(data, ["context_wall_broken", "context_wall_corner_r", "context_wall_stub"][variant % 3])


func _contact_disc(data: Dictionary, radius: float) -> void:
	# One batch of soft vertex-alpha footprints provides contact AO even when
	# screen-space AO is disabled; it has no collision or simulation footprint.
	for side: int in range(12):
		var angle: float = float(side) * TAU / 12.0
		var next: float = float(side + 1) * TAU / 12.0
		data.vertices.append_array([Vector3.ZERO, Vector3(cos(angle) * radius, 0, sin(angle) * radius), Vector3(cos(next) * radius, 0, sin(next) * radius)])
		data.normals.append_array([Vector3.UP, Vector3.UP, Vector3.UP])
		data.colors.append_array([Color(0.22, 0.20, 0.16, 0.36), Color(0.22, 0.20, 0.16, 0.0), Color(0.22, 0.20, 0.16, 0.0)])


func _box(data: Dictionary, centre: Vector3, size: Vector3, color: Color, rotation: Basis = Basis.IDENTITY) -> void:
	var p: Array[Vector3] = []
	for corner: Vector3 in [Vector3(-1,-1,-1), Vector3(1,-1,-1), Vector3(1,1,-1), Vector3(-1,1,-1), Vector3(-1,-1,1), Vector3(1,-1,1), Vector3(1,1,1), Vector3(-1,1,1)]:
		p.append(centre + rotation * (corner * size * 0.5))
	for face: Array in [[0,3,2,1,Vector3.FORWARD], [4,5,6,7,Vector3.BACK], [0,4,7,3,Vector3.LEFT], [1,2,6,5,Vector3.RIGHT], [3,7,6,2,Vector3.UP], [0,1,5,4,Vector3.DOWN]]:
		_quad(data, p[face[0]], p[face[1]], p[face[2]], p[face[3]], color, rotation * face[4])


func _build_mines(sim: WarSimulation) -> void:
	for index: int in sim.mines.size():
		var mine: Dictionary = sim.mines[index]
		var root := Node3D.new()
		root.name = "BlueCrystalDeposit_%d" % index
		root.position = Vector3(mine.pos.x, MAP.height_at(_map, mine.pos), mine.pos.y)
		add_child(root)
		_instance(_crystal_cluster(index % 3), root, "CutPaperCrystals")
		mine_visuals.append(root)
		_mine_buckets.append(-1)
		var transform := Transform3D(Basis.IDENTITY.scaled(Vector3(2.8, 1, 2.8)), root.position + Vector3.UP * 0.012)
		_batch("contact", transform)


func _crystal_cluster(variant: int) -> ArrayMesh:
	var key: String = "crystal_%d" % variant
	if _meshes.has(key):
		return _meshes[key]
	var data: Dictionary = _data()
	for piece: int in range(7):
		var angle: float = piece * 2.399 + variant * 0.42
		var radius: float = 0.65 if piece > 0 else 0.0
		var centre := Vector3(cos(angle) * radius, 0.03, sin(angle) * radius)
		var height: float = 1.65 if piece == 0 else 0.62 + float(piece % 3) * 0.31
		_crystal(data, centre, height, 0.28 if piece == 0 else 0.23, angle)
	var mesh: ArrayMesh = _finish(data, "crystal")
	_meshes[key] = mesh
	return mesh


func _crystal(data: Dictionary, centre: Vector3, height: float, radius: float, yaw: float) -> void:
	for side: int in range(5):
		var a: float = side * TAU / 5.0 + yaw
		var b: float = (side + 1) * TAU / 5.0 + yaw
		var low_a: Vector3 = centre + Vector3(cos(a) * radius, 0, sin(a) * radius)
		var low_b: Vector3 = centre + Vector3(cos(b) * radius, 0, sin(b) * radius)
		var top_a: Vector3 = low_a + Vector3(0.035, height * 0.72, -0.025)
		var top_b: Vector3 = low_b + Vector3(0.035, height * 0.72, -0.025)
		var tip: Vector3 = centre + Vector3(0.05, height, -0.025)
		var color: Color = [Color("3194d2"), Color("64c9ee"), Color("a1e3f6"), Color("3482be"), Color("297ab0")][side]
		var outward := Vector3(cos((a+b)*0.5), 0, sin((a+b)*0.5))
		_quad(data, low_a, top_a, top_b, low_b, color, outward)
		_triangle(data, top_a, tip, top_b, color.lightened(0.13), Vector3.UP)


func _build_bridge(bridge: Dictionary) -> void:
	var bounds: Array = bridge.bounds
	var style: String = str(bridge.get("style", ""))
	if style.is_empty():
		for authored: Dictionary in _map.get("bridges", []):
			if int(authored.get("id", -1)) == int(bridge.id): style = str(authored.get("style", "")); break
	var stone_deck: bool = style == "stone_arch"
	var w: float = float(bounds[2])
	var d: float = float(bounds[3])
	var middle := Vector2(float(bounds[0]) + w * 0.5, float(bounds[1]) + d * 0.5)
	var root := Node3D.new()
	root.name = "NeutralBridge_%d" % int(bridge.id)
	root.position = Vector3(middle.x, MAP.height_at(_map, middle), middle.y)
	add_child(root)
	var along_x: bool = w >= d
	var length: float = maxf(w, d)
	var breadth: float = minf(w, d)
	var turn: Basis = Basis.IDENTITY if along_x else Basis(Vector3.UP, PI * 0.5)
	var foundation: Dictionary = _data()
	for side: float in [-1.0, 1.0]:
		_box(foundation, turn * Vector3(side * (length * 0.5 - 0.55), -WATER_DEPTH * 0.5, 0), Vector3(0.85, WATER_DEPTH + 0.08, breadth), Color("a99a82"), turn)
	BRIDGE_CRAFT.abutments(self, foundation, length, breadth, turn, WATER_DEPTH)
	_instance(_finish(foundation), root, "StoneAbutments")
	var deck: Dictionary = _data()
	_bridge_arch(deck, length, breadth, turn)
	BRIDGE_CRAFT.arch(self, deck, length, breadth, turn, WATER_DEPTH)
	for index: int in ceili(length / 0.62):
		var position: Vector3 = turn * Vector3(-length * 0.5 + 0.30 + index * 0.62, -0.07, 0)
		_box(deck, position, Vector3(minf(0.58, length), 0.14, breadth), (Color("aeb0aa") if stone_deck else Color("a39171")).lightened((index % 3) * 0.025), turn)
	if not stone_deck: BRIDGE_CRAFT.planks(self, deck, length, breadth, turn)
	for side: float in [-1.0, 1.0]:
		_box(deck, turn * Vector3(0, 0.64, side * breadth * 0.47), Vector3(length, 0.1, 0.09), Color("75634a"), turn)
		for index: int in ceili(length / 1.45):
			_box(deck, turn * Vector3(-length * 0.5 + 0.23 + index * 1.45, 0.36, side * breadth * 0.47), Vector3(0.105, 0.85, 0.105), Color("897455"), turn)
	var intact: MeshInstance3D = _instance(_finish(deck), root, "IntactDeck")
	var ruin: Dictionary = _data()
	for side: float in [-1.0, 1.0]:
		for piece: int in range(3):
			var angle: float = side * piece * 0.26
			var rotation: Basis = turn * Basis(Vector3.FORWARD, angle)
			_box(ruin, turn * Vector3(side * (length * 0.5 - 0.2 - piece * 0.43), -0.13 - piece * 0.13, 0), Vector3(0.42, 0.12, breadth * 0.87), Color("8b785b"), rotation)
	var broken: MeshInstance3D = _instance(_finish(ruin), root, "BrokenDeck")
	intact.visible = bool(bridge.alive)
	broken.visible = not bool(bridge.alive)
	bridge_visuals[int(bridge.id)] = {"root": root, "deck": intact, "broken": broken, "alive": bool(bridge.alive)}


func _bridge_arch(data: Dictionary, length: float, breadth: float, turn: Basis) -> void:
	var radius: float = maxf(1.0, length * 0.5 - 0.67)
	var inner: float = maxf(0.5, radius - 0.42)
	var centre_y: float = minf(-radius - 0.14, -WATER_DEPTH)
	var half: float = breadth * 0.43
	for stone: int in range(13):
		var a: float = float(stone) * PI / 13.0
		var b: float = float(stone + 1) * PI / 13.0
		var outer_a := Vector2(cos(a) * radius, centre_y + sin(a) * radius)
		var outer_b := Vector2(cos(b) * radius, centre_y + sin(b) * radius)
		var inner_a := Vector2(cos(a) * inner, centre_y + sin(a) * inner)
		var inner_b := Vector2(cos(b) * inner, centre_y + sin(b) * inner)
		var color := Color("b1a083").darkened(float(stone % 3) * 0.027)
		for side: float in [-1.0, 1.0]:
			var normal: Vector3 = turn * Vector3(0, 0, side)
			var aa: Vector3 = turn * Vector3(outer_a.x, outer_a.y, side * half)
			var bb: Vector3 = turn * Vector3(outer_b.x, outer_b.y, side * half)
			var cc: Vector3 = turn * Vector3(inner_b.x, inner_b.y, side * half)
			var dd: Vector3 = turn * Vector3(inner_a.x, inner_a.y, side * half)
			_quad(data, aa, bb, cc, dd, color, normal)
			_ink_strip(data, aa, dd, normal, Color("72644e"), 0.015)
			_quad(data, aa, turn * Vector3(outer_a.x, -0.11, side * half), turn * Vector3(outer_b.x, -0.11, side * half), bb, color.darkened(0.04), normal)
		_quad(data, turn * Vector3(inner_a.x, inner_a.y, -half), turn * Vector3(inner_b.x, inner_b.y, -half), turn * Vector3(inner_b.x, inner_b.y, half), turn * Vector3(inner_a.x, inner_a.y, half), color.darkened(0.13), turn * Vector3(-cos((a+b)*0.5), -sin((a+b)*0.5), 0))


func _build_environment() -> void:
	for prop: Dictionary in _map.get("environment_props", []):
		var point: Vector2 = prop.pos
		var kind: String = str(prop.kind)
		var variant: int = int(prop.get("variant", 0))
		var key: String = "environment_%s_%d:%d_%d" % [kind, variant, floori(point.x / ENVIRONMENT_CHUNK), floori(point.y / ENVIRONMENT_CHUNK)]
		if not _batches.has(key): _batches[key] = {"mesh": ENVIRONMENT_MODELS.prop_mesh(kind, variant), "transforms": [], "shadow": true}
		var scale: float = float(prop.get("scale", 1.0))
		var domain: String = str(prop.get("surface_domain", "ground"))
		var base_y: float = MAP.entity_surface_y(_map, point, "naval") if domain == "naval" else MAP.height_at(_map, point)
		var transform := Transform3D(Basis(Vector3.UP, float(prop.get("yaw", 0.0))).scaled(Vector3.ONE * scale), Vector3(point.x, base_y + float(prop.get("height_offset", 0.0)), point.y))
		_batches[key].transforms.append(transform)
		stats.prop_instances = int(stats.prop_instances) + 1
	var people_by_variant: Dictionary = {}
	for person: Dictionary in _map.get("civilians", []):
		var variant: int = int(person.get("variant", 0))
		if not people_by_variant.has(variant): people_by_variant[variant] = []
		people_by_variant[variant].append(person)
	for variant: int in people_by_variant:
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = ENVIRONMENT_MODELS.prop_mesh("pedestrian", variant)
		multi.instance_count = people_by_variant[variant].size()
		var instance := MultiMeshInstance3D.new()
		instance.name = "NeutralPedestrians_%d" % variant
		instance.multimesh = multi
		add_child(instance)
		_civilian_batches.append({"multi": multi, "people": people_by_variant[variant]})
	stats.environment_props = _map.get("environment_props", []).size()
	stats.environment_people = _map.get("civilians", []).size()
	sync_environment(0.0)


func _city_road_mark(data: Dictionary, x: int, z: int, height: float) -> void:
	if int(_map.profile.get("design_version", 0)) >= 6:
		# V6 streets follow authored district routes rather than a modulo grid.
		# Only the authored centre cells receive a dashed line.
		var direction: String = str(_map.get("road_mark_cells", {}).get(Vector2i(x, z), ""))
		var y: float = height + .014
		var paint: Color = Color("e0d8b7")
		if direction == "h":
			_quad(data, Vector3(x, y, z + .46), Vector3(x, y, z + .54), Vector3(x + .94, y, z + .54), Vector3(x + .94, y, z + .46), paint, Vector3.UP)
		elif direction == "v":
			_quad(data, Vector3(x + .46, y, z), Vector3(x + .54, y, z), Vector3(x + .54, y, z + .94), Vector3(x + .46, y, z + .94), paint, Vector3.UP)
		return
	var spacing: int = int(_map.profile.street_spacing)
	var origin: int = int(_map.profile.street_origin)
	var px: int = posmod(x - origin, spacing)
	var pz: int = posmod(z - origin, spacing)
	var y: float = height + .014
	var color := Color("e0d8b7")
	if px == 2 and pz > 5 and z % 5 < 3:
		_quad(data, Vector3(x + .43, y, z), Vector3(x + .43, y, z + .94), Vector3(x + .57, y, z + .94), Vector3(x + .57, y, z), color, Vector3.UP)
	if pz == 2 and px > 5 and x % 5 < 3:
		_quad(data, Vector3(x, y, z + .43), Vector3(x, y, z + .57), Vector3(x + .94, y, z + .57), Vector3(x + .94, y, z + .43), color, Vector3.UP)
	# Pavement crosswalk stripes are visible on real road planes.
	if px < 5 and pz == 6 and x % 2 == 0:
		_quad(data, Vector3(x + .12, y, z + .15), Vector3(x + .12, y, z + .72), Vector3(x + .88, y, z + .72), Vector3(x + .88, y, z + .15), color, Vector3.UP)


func _profile_ground_details(data: Dictionary, x: int, z: int, height: float) -> void:
	var biome: String = str(_map.profile.biome)
	if biome == "city" or _static_hash(x, z, 349.0) > .045: return
	var y: float = height + .009
	var color: Color = Color("c0c8c4") if biome == "snow" else Color("b39768") if biome == "desert" else Color("9a9b70")
	var width: float = .05 if biome == "snow" else .035
	_quad(data, Vector3(x + .13, y, z + .31), Vector3(x + .21, y, z + .31 + width), Vector3(x + .79, y, z + .53 + width), Vector3(x + .77, y, z + .53), color, Vector3.UP)
