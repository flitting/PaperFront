shader_type spatial;
render_mode diffuse_burley, cull_back;
uniform sampler2D paper_grain : filter_linear_mipmap, repeat_enable;
varying vec3 paper_position;
void vertex() { paper_position = VERTEX; }
void fragment() {
    float grain = texture(paper_grain, (paper_position.xz + paper_position.yy * .31) * .19).r;
    vec3 pigment = COLOR.rgb * (.93 + grain * .13);
    float rim = 1.0 - smoothstep(.06, .24, abs(dot(normalize(NORMAL), normalize(VIEW))));
    pigment = mix(pigment, vec3(.22, .19, .16), rim * .17);
    ALBEDO = mix(pigment/12.92, pow((pigment+vec3(.055))/1.055, vec3(2.4)), step(vec3(.04045),pigment));
    ROUGHNESS = .89;
    SPECULAR = .13;
}
