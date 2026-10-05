shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_back;
uniform sampler2D paper_grain : filter_linear_mipmap, repeat_enable;
varying vec3 local_position;
varying vec3 face_normal;
void vertex() { local_position=VERTEX; face_normal=NORMAL; }
void fragment() {
    vec3 n=abs(face_normal);
    vec2 uv=n.z>n.x && n.z>n.y ? local_position.xy : (n.x>n.y ? local_position.zy : local_position.xz);
    float wash=texture(paper_grain,uv*0.42).r;
    float brush=texture(paper_grain,uv*vec2(1.8,0.55)+vec2(.37,.19)).r;
    vec3 pigment=COLOR.rgb;
    // Flat painted faces and ochre cut edges, with broad dry pigment and
    // restrained fibre. No stone gloss, bump mapping, or metallic response.
    float paper=smoothstep(.20,.65,dot(pigment,vec3(.3,.5,.2)));
    pigment=mix(pigment,vec3(.85,.73,.54),paper*(.035+wash*.045));
    pigment*=.91+wash*.12+brush*.045;
    ALBEDO=mix(pigment/12.92,pow((pigment+vec3(.055))/1.055,vec3(2.4)),step(vec3(.04045),pigment));
    ROUGHNESS=1.0;
    METALLIC=0.0;
    SPECULAR=0.0;
}
