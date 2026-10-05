shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_test_disabled, depth_draw_never;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D sight_mask : filter_linear, repeat_disable;
uniform float map_size = 320.0;
uniform bool fog_enabled = true;

void vertex() {
    POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
    vec3 scene = texture(screen_texture, SCREEN_UV).rgb;
    float depth = texture(depth_texture, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth * 2.0 - 1.0);
    bool has_surface = depth < .999999;
#else
    vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
    bool has_surface = depth > .000001;
#endif
    vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    view /= view.w;
    vec3 world = (INV_VIEW_MATRIX * view).xyz;
    vec2 uv = world.xz / map_size;
    if (fog_enabled && has_surface && all(greaterThanEqual(uv, vec2(0.0))) && all(lessThanEqual(uv, vec2(1.0)))) {
        vec2 sight = texture(sight_mask, uv).rg;
        float visible = smoothstep(.05, .82, sight.r);
        float explored = smoothstep(.05, .82, sight.g);
        float grey = dot(scene, vec3(.2126, .7152, .0722));
        // The familiar paper terrain stays readable in remembered territory.
        // Cold, desaturated pigment distinguishes it from the warm live view.
        vec3 remembered = mix(vec3(grey) * vec3(.34, .46, .64), scene * .32, .20);
        // Unexplored paper has a deeper blue ink wash and a quiet fixed hatch.
        float hatch = step(.78, fract((world.x + world.z) * .18));
        vec3 unknown = mix(scene * .12, vec3(.025, .038, .065) * max(grey, .15), .56);
        unknown *= .94 + hatch * .06;
        ALBEDO = mix(unknown, remembered, explored);
        // Screen reads contain the opaque pass. Transparent blending preserves
        // existing infantry borders, particles and guides in the clear view.
        ALPHA = (1.0 - visible) * mix(.90, .66, explored);
    } else {
        ALBEDO = scene;
        ALPHA = 0.0;
    }
}
