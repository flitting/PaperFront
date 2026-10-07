extends RefCounted

## Same material roles as the battlefield paper cards: coloured cloth belongs
## to the player, while the small faction seal stays orange-yellow.
static var shader: Shader
static func make(texture_path: String, team: int) -> ShaderMaterial:
	if shader == null:
		shader = Shader.new()
		shader.code = """shader_type canvas_item;
uniform sampler2D identity_mask : filter_linear_mipmap, repeat_disable;
uniform float identity_enabled = 0.0;
uniform float model_portrait = 0.0;
uniform vec4 faction_accent : source_color = vec4(0.23,0.52,0.48,1.0);
uniform vec4 player_color : source_color = vec4(1.0);
void fragment() {
    vec4 original = texture(TEXTURE,UV);
    vec4 identity = texture(identity_mask,UV);
    float insignia = identity.r * identity.a * identity_enabled;
    float saturation = max(original.r,max(original.g,original.b))-min(original.r,min(original.g,original.b));
    // Authored infantry use a dedicated magenta cloth pigment. Warm skin and
    // leather must never be inferred as player paint from red saturation.
    float fabric = smoothstep(0.12,0.22,min(original.r,original.b)-original.g);
    fabric = clamp(fabric,0.0,1.0) * (1.0-insignia);
    float model_paint = step(original.g+0.20,min(original.r,original.b));
    fabric = mix(fabric,model_paint,model_portrait);
    vec3 cloth = player_color.rgb * clamp(max(original.r,max(original.g,original.b))*1.3,0.55,1.05);
    vec3 pigment = mix(original.rgb,cloth,fabric);
    float heritage = step(0.76,fract(UV.y*3.0+UV.x*0.35)) * fabric * (1.0-model_portrait);
    pigment = mix(pigment,faction_accent.rgb,heritage);
    COLOR = vec4(mix(pigment,vec3(0.94,0.71,0.22),insignia),original.a);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("faction_accent",VolumeModels.faction_color(texture_path.get_file().get_slice("_",0)))
	material.set_shader_parameter("model_portrait",1.0 if texture_path.get_extension().to_lower() == "png" else 0.0)
	material.set_shader_parameter("player_color",VolumeModels.player_color(team))
	var identity_path: String = texture_path.get_basename()+"_identity.svg"
	if ResourceLoader.exists(identity_path):
		material.set_shader_parameter("identity_mask",load(identity_path))
		material.set_shader_parameter("identity_enabled",1.0)
	return material
