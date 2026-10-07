extends RefCounted

## Actual two-dimensional paper cards: one XY plane, no thickness, limbs,
## extrusion, or volumetric head. Near/middle/far use separately drawn SVGs.
static var materials: Dictionary = {}
static var sprite_shader: Shader

static func make(_mesh, faction: String, art: String, owner: Color, tier: int = 0, pose: String = "idle") -> Dictionary:
	var path: String = "res://assets/cards/paper_infantry_revision/%s_%s_%s_%d.svg" % [faction,art,pose,tier]
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-.245,0,0),Vector3(.245,.68,0),Vector3(.245,0,0),Vector3(-.245,0,0),Vector3(-.245,.68,0),Vector3(.245,.68,0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK,Vector3.BACK,Vector3.BACK,Vector3.BACK,Vector3.BACK,Vector3.BACK])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0,1),Vector2(1,0),Vector2(1,1),Vector2(0,1),Vector2(0,0),Vector2(1,0)])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE,Color.WHITE,Color.WHITE,Color.WHITE,Color.WHITE,Color.WHITE])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.surface_set_material(0,_material(path,owner))
	return {"body_mesh":mesh,"dimensions":Vector3(.49,.68,0),"muzzle_pos":Vector3(.245,.34,0),"design":"%s_%s_human_paper_%s_%d" % [faction,art,pose,tier],"paper_infantry":true,"sprite_path":path,"authored_tier":tier}

static func _material(path: String, owner: Color) -> ShaderMaterial:
	var key: String = path+":"+owner.to_html()
	if materials.has(key): return materials[key]
	if sprite_shader == null:
		sprite_shader = Shader.new()
		sprite_shader.code = """shader_type spatial;
// Printed pigment must remain legible when the billboard rotates or is backlit.
// World visibility/fog still decides whether this card is submitted.
render_mode unshaded, cull_disabled, depth_prepass_alpha;
uniform sampler2D paper_sprite : source_color, filter_linear_mipmap;
uniform vec4 player_color : source_color;
varying float paper_mirror;
void vertex() {
    paper_mirror = MODEL_MATRIX[0].x < 0.0 ? 1.0 : 0.0;
    // Fixed-Y billboard: the drawing remains a readable upright paper card.
    float sx = length(MODEL_MATRIX[0].xyz);
    float sy = length(MODEL_MATRIX[1].xyz);
    vec3 up = vec3(0.0, sy, 0.0);
    vec3 right = normalize(cross(vec3(0.0,1.0,0.0), INV_VIEW_MATRIX[2].xyz)) * sx;
    vec3 forward = normalize(cross(right,up));
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right,0.0),vec4(up,0.0),vec4(forward,0.0),MODEL_MATRIX[3]);
    MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}
void fragment() {
    vec2 uv = UV;
    uv.x = mix(uv.x,1.0-uv.x,paper_mirror);
    vec4 pigment = texture(paper_sprite, uv);
    float owner_mask = smoothstep(0.04,0.30,min(pigment.r,pigment.b)-pigment.g);
    ALBEDO = mix(pigment.rgb,player_color.rgb,owner_mask);
    ALPHA = pigment.a;
    ALPHA_SCISSOR_THRESHOLD = 0.45;
    ROUGHNESS = 1.0;
    SPECULAR = 0.0;
}
"""
	var material := ShaderMaterial.new()
	material.shader = sprite_shader
	material.set_shader_parameter("paper_sprite",load(path))
	material.set_shader_parameter("player_color",owner)
	materials[key] = material
	return material
