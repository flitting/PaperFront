extends RefCounted

# Only camera-near geometry and the outer screen margin fade. The normally
# viewed centre is always opaque. Per-fragment masks preserve shared batches,
# terrain chunks and authored material colours outside the affected regions.
static var _registered := false
static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}
const DECLARATIONS := """
global uniform vec3 paper_camera_eye;
global uniform vec4 paper_camera_focus;
global uniform vec3 paper_camera_right;
global uniform vec3 paper_camera_up;
global uniform vec4 paper_camera_fade_limits;
float paper_camera_occlusion(vec3 world) {
    vec3 relative = world - paper_camera_eye;
    vec3 axis = paper_camera_focus.xyz - paper_camera_eye;
    float reach = length(axis);
    float along = dot(relative, axis / max(reach, 0.001));
    vec2 projected = vec2(dot(relative, paper_camera_right), dot(relative, paper_camera_up));
    projected /= max(along, 0.001) * paper_camera_fade_limits.xy;
    float edge = smoothstep(0.78, 0.98, max(abs(projected.x), abs(projected.y)));
    float near_eye = 1.0 - smoothstep(paper_camera_fade_limits.z, paper_camera_fade_limits.w, length(relative));
    // Edge fading applies only to foreground geometry, never the focused
    // object or scenery farther away. There is deliberately no central mask.
    float foreground = 1.0 - smoothstep(reach * 0.84, reach * 0.97, along);
    float in_front = smoothstep(-0.2, 0.05, along);
    float above_floor = smoothstep(paper_camera_focus.y + 0.08, paper_camera_focus.y + 0.5, world.y);
    return max(near_eye * 0.96, edge * foreground * 0.72) * in_front * above_floor * paper_camera_focus.w;
}
"""
const FRAGMENT := """
    vec3 paper_occlusion_world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
    // Keep shadow-map passes intact: fading a roof at the screen edge must
    // not change the lighting/colour of a normal central object.
    float paper_occlusion_fade = distance(INV_VIEW_MATRIX[3].xyz, paper_camera_eye) < 0.01 ? paper_camera_occlusion(paper_occlusion_world) : 0.0;
    // Stable screen-space stipple keeps opaque lighting/depth and avoids
    // sorting seams across overlapping roofs and cliff layers.
    float paper_occlusion_noise = fract(52.9829189 * fract(dot(floor(FRAGCOORD.xy), vec2(0.06711056, 0.00583715))));
    if (paper_occlusion_noise < paper_occlusion_fade) { discard; }
"""

static func ensure_globals() -> void:
	if _registered: return
	_registered = true
	RenderingServer.global_shader_parameter_add("paper_camera_eye", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.ZERO)
	RenderingServer.global_shader_parameter_add("paper_camera_focus", RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4.ZERO)
	RenderingServer.global_shader_parameter_add("paper_camera_right", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.RIGHT)
	RenderingServer.global_shader_parameter_add("paper_camera_up", RenderingServer.GLOBAL_VAR_TYPE_VEC3, Vector3.UP)
	RenderingServer.global_shader_parameter_add("paper_camera_fade_limits", RenderingServer.GLOBAL_VAR_TYPE_VEC4, Vector4(.5,.4,1.0,2.0))

static func parameters(distance: float, fov: float, aspect: float) -> Dictionary:
	var strength: float = 1.0 - smoothstep(8.0, 60.0, distance)
	var near_end: float = lerpf(1.4, minf(distance * .34, 7.0), strength)
	var vertical: float = tan(deg_to_rad(fov) * .5)
	return {"strength":strength,"limits":Vector4(vertical*aspect,vertical,near_end*.45,near_end)}

static func update(view: Camera3D, target: Vector3, enabled: bool = true) -> void:
	ensure_globals()
	var viewport: Vector2 = view.get_viewport().get_visible_rect().size
	var aspect: float = viewport.x / maxf(1.0,viewport.y)
	var distance: float = view.global_position.distance_to(target)
	var settings: Dictionary = parameters(distance, view.fov, aspect)
	# Camera3D's default KEEP_HEIGHT means its FOV is measured vertically.
	if view.keep_aspect == Camera3D.KEEP_WIDTH:
		settings.limits.x /= aspect
		settings.limits.y /= aspect
	RenderingServer.global_shader_parameter_set("paper_camera_eye", view.global_position)
	RenderingServer.global_shader_parameter_set("paper_camera_focus", Vector4(target.x,target.y,target.z,float(settings.strength) if enabled else 0.0))
	RenderingServer.global_shader_parameter_set("paper_camera_right", view.global_basis.x)
	RenderingServer.global_shader_parameter_set("paper_camera_up", view.global_basis.y)
	RenderingServer.global_shader_parameter_set("paper_camera_fade_limits", settings.limits)

static func material(source: Material) -> Material:
	if source == null: return null
	var id: int = source.get_instance_id()
	if _materials.has(id): return _materials[id]
	ensure_globals()
	var code := ""
	if source is ShaderMaterial:
		if source.shader == null: return source
		code = source.shader.code
	elif source is StandardMaterial3D:
		# The opaque scenery accents use untextured StandardMaterial3D. Keep
		# translucent overlays (rings, health bars, particles) in their own pass.
		if source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or source.albedo_texture != null or source.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED: return source
		code = "shader_type spatial;\nrender_mode " + ("cull_disabled" if source.cull_mode == BaseMaterial3D.CULL_DISABLED else "cull_front" if source.cull_mode == BaseMaterial3D.CULL_FRONT else "cull_back") + ";\n"
		code += "uniform vec4 camera_original_albedo : source_color;\nuniform vec3 camera_original_emission : source_color;\nuniform float camera_original_roughness;\nuniform float camera_original_metallic;\nuniform float camera_original_specular;\nvoid fragment() {\n ALBEDO = camera_original_albedo.rgb;\n"
		if source.vertex_color_use_as_albedo:
			code += "ALBEDO *= mix(COLOR.rgb / 12.92, pow((COLOR.rgb + vec3(0.055)) / 1.055, vec3(2.4)), step(vec3(0.04045), COLOR.rgb));\n" if source.vertex_color_is_srgb else "ALBEDO *= COLOR.rgb;\n"
		code += "EMISSION = camera_original_emission; ROUGHNESS = camera_original_roughness; METALLIC = camera_original_metallic; SPECULAR = camera_original_specular; }\n"
	if code.is_empty() or not code.contains("void fragment()") or code.contains("paper_camera_occlusion"): return source
	var shader := Shader.new()
	code = code.replace("shader_type spatial;", "shader_type spatial;\n" + DECLARATIONS)
	var fragment := RegEx.new()
	fragment.compile("void fragment\\(\\)\\s*\\{")
	code = fragment.sub(code, "void fragment() {\n" + FRAGMENT)
	shader.code = code
	var result := ShaderMaterial.new()
	result.shader = shader
	if source is ShaderMaterial:
		for uniform: Dictionary in source.shader.get_shader_uniform_list():
			var value: Variant = source.get_shader_parameter(uniform.name)
			if value != null: result.set_shader_parameter(uniform.name, value)
	else:
		result.set_shader_parameter("camera_original_albedo", source.albedo_color)
		result.set_shader_parameter("camera_original_emission", source.emission * source.emission_energy_multiplier if source.emission_enabled else Color.BLACK)
		result.set_shader_parameter("camera_original_roughness", source.roughness)
		result.set_shader_parameter("camera_original_metallic", source.metallic)
		result.set_shader_parameter("camera_original_specular", source.metallic_specular)
	result.render_priority = source.render_priority
	result.next_pass = source.next_pass
	_materials[id] = result
	return result

static func mesh(source: Mesh) -> Mesh:
	if source == null: return null
	var id: int = source.get_instance_id()
	if _meshes.has(id): return _meshes[id]
	var result: Mesh = source.duplicate()
	for surface: int in result.get_surface_count():
		result.surface_set_material(surface, material(source.surface_get_material(surface)))
	_meshes[id] = result
	return result

# Direct Skeleton3D meshes keep their shared Mesh/Skin and private animation.
# Overrides persist across LOD swaps and pooling; only their rendered material
# gains the same peripheral/nearby fade as a MultiMesh instance.
static func wrap_instance(node: MeshInstance3D) -> void:
	if node.material_override != null:
		node.material_override = material(node.material_override)
	elif node.mesh != null:
		for surface: int in node.mesh.get_surface_count():
			node.set_surface_override_material(surface, material(node.get_active_material(surface)))

# CPU counterpart for geometry regression tests; no physics/collision changes.
static func strength(point: Vector3, eye: Vector3, target: Vector3, fov: float = 42.0, aspect: float = 1.6) -> float:
	var axis: Vector3 = target-eye
	var reach: float = axis.length()
	var direction: Vector3 = axis/maxf(reach,.001)
	var right: Vector3 = direction.cross(Vector3.UP).normalized()
	var up: Vector3 = right.cross(direction).normalized()
	var relative: Vector3 = point-eye
	var along: float = relative.dot(direction)
	var settings: Dictionary = parameters(reach,fov,aspect)
	var limits: Vector4 = settings.limits
	var projected := Vector2(relative.dot(right)/limits.x,relative.dot(up)/limits.y)/maxf(along,.001)
	var edge: float = smoothstep(.78,.98,maxf(absf(projected.x),absf(projected.y)))
	var near_eye: float = 1.0-smoothstep(limits.z,limits.w,relative.length())
	var foreground: float = 1.0-smoothstep(reach*.84,reach*.97,along)
	return maxf(near_eye*.96,edge*foreground*.72)*smoothstep(-.2,.05,along)*smoothstep(target.y+.08,target.y+.5,point.y)*float(settings.strength)
