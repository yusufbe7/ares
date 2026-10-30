shader_type spatial;
render_mode cull_back;

// Grass / dirt / mud ground that blends by noise, slope and height (river banks).
uniform sampler2D macro_noise : hint_default_white, repeat_enable, filter_linear_mipmap;
uniform sampler2D detail_noise : hint_default_white, repeat_enable, filter_linear_mipmap;
uniform vec3 grass_a : source_color = vec3(0.24, 0.31, 0.12);
uniform vec3 grass_b : source_color = vec3(0.33, 0.37, 0.16);
uniform vec3 dry : source_color = vec3(0.44, 0.40, 0.24);
uniform vec3 dirt : source_color = vec3(0.36, 0.29, 0.20);
uniform vec3 mud : source_color = vec3(0.22, 0.18, 0.13);

varying vec3 wpos;
varying vec3 wnorm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = wpos.xz;
	float m = texture(macro_noise, uv * 0.004).r;
	float m2 = texture(macro_noise, uv * 0.017 + vec2(0.37, 0.11)).r;
	float d = texture(detail_noise, uv * 0.35).r;
	float d2 = texture(detail_noise, uv * 1.7).r;
	vec3 g = mix(grass_a, grass_b, smoothstep(0.35, 0.7, m2));
	g = mix(g, dry, smoothstep(0.62, 0.8, m) * 0.7);
	g = mix(g, dirt, smoothstep(0.72, 0.9, m2 * d) * 0.8);
	// river banks: mud below ~-0.4 m
	float bank = smoothstep(-0.3, -1.4, wpos.y);
	g = mix(g, mud, bank);
	// steep = dirt
	float slope = 1.0 - wnorm.y;
	g = mix(g, dirt, smoothstep(0.15, 0.35, slope));
	g *= 0.82 + 0.3 * d * (0.7 + 0.6 * d2);
	ALBEDO = g;
	ROUGHNESS = mix(0.95, 0.6, bank);
	SPECULAR = 0.25;
}
