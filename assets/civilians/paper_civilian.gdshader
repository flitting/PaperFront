shader_type spatial;
render_mode skip_vertex_transform, cull_disabled, diffuse_burley;

// One camera-facing printed paper plane, including the shadow pass. Keeping
// camera_right explicit stops the light's camera from rotating the cutout.
uniform vec3 camera_right = vec3(1.0, 0.0, 0.0);
varying vec2 paper_position;

void vertex() {
    paper_position = VERTEX.xy;
    vec3 right = normalize(camera_right);
    vec3 up = vec3(0.0, 1.0, 0.0);
    vec3 front = cross(right, up);
    vec3 anchor = MODEL_MATRIX[3].xyz;
    vec3 world = anchor + right * VERTEX.x + up * VERTEX.y + front * VERTEX.z;
    VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
    NORMAL = normalize((VIEW_MATRIX * vec4(front, 0.0)).xyz);
}

void fragment() {
    float grain = sin(paper_position.x * 137.0 + paper_position.y * 93.0) * .016;
    vec3 pigment = COLOR.rgb * (1.0 + grain);
    ALBEDO = mix(pigment / 12.92, pow((pigment + vec3(.055)) / 1.055, vec3(2.4)), step(vec3(.04045), pigment));
    ROUGHNESS = .98;
    SPECULAR = .10;
}
