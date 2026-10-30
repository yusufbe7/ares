shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_always;

// Murky river: flowing ripples, fresnel reflection of the sky, sun glints.
uniform sampler2D ripple_noise : hint_normal, repeat_enable, filter_linear_mipmap;
uniform vec3 deep_color : source_color = vec3(0.07, 0.13, 0.12);
uniform vec3 shallow_color : source_color = vec3(0.20, 0.27, 0.20);
uniform vec2 flow = vec2(0.0, 0.45);
uniform float opacity = 0.86;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz * 0.08;
	vec3 n1 = texture(ripple_noise, uv + TIME * flow * 0.08).rgb;
	vec3 n2 = texture(ripple_noise, uv * 1.9 - TIME * flow.yx * 0.05 + vec2(0.3, 0.7)).rgb;
	NORMAL_MAP = normalize(mix(n1, n2, 0.5));
	NORMAL_MAP_DEPTH = 0.6;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(deep_color, shallow_color, 0.35 + 0.3 * n1.r);
	METALLIC = 0.0;
	ROUGHNESS = 0.06;
	SPECULAR = 0.7;
	ALPHA = clamp(opacity + fres * 0.2, 0.0, 1.0);
}
