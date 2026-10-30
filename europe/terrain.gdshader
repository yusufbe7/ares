// Europe battlefield ground: 8 Poly Haven layers painted by the Blender splat maps
// (splat1 = sparse grass / withered / dry / mud, splat2 = tracks / craters / road / wet),
// winter snow on top (global snow_amount), trenches (dug_tex) show raw dirt.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

global uniform float snow_amount;

uniform sampler2DArray albedo_array : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray normal_array : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D splat1 : filter_linear, repeat_disable;
uniform sampler2D splat2 : filter_linear, repeat_disable;
uniform sampler2D dug_tex : filter_linear, repeat_disable;
uniform float map_size = 600.0;
// jang maydoni generatori (battle_gen.gd): biom rangi, qum (cho'l), tik joyda tosh (tog'), qor chizig'i (m)
uniform vec3 biome_tint = vec3(1.0);
uniform float sand = 0.0;
uniform float rockiness = 0.0;
uniform float snow_line = 9999.0;
// tile size in metres for each layer
const float tile[8] = {2.6, 3.1, 2.8, 2.4, 2.2, 3.2, 2.5, 3.0};

varying vec3 wpos;
varying vec3 wnrm;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float a = 0.5; float s = 0.0;
	for (int k = 0; k < 4; k++) { s += a * vnoise(p); p *= 2.03; a *= 0.5; }
	return s;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec2 luv(int k, vec2 xz) {
	float a = float(k) * 0.7;
	mat2 r = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a)));
	return r * (xz / (tile[k] * 1.6)) + vec2(float(k) * 0.37, float(k) * 0.61);
}

void fragment() {
	vec2 xz = wpos.xz;
	vec2 suv = (xz + vec2(map_size * 0.5)) / map_size;
	vec4 s1 = texture(splat1, suv);
	vec4 s2 = texture(splat2, suv);
	float dug = texture(dug_tex, suv).r;
	float n1 = fbm(xz * 0.45) - 0.5;
	float n2 = fbm(xz * 0.06);
	vec3 col = texture(albedo_array, vec3(luv(0, xz), 0.0)).rgb;
	vec3 nt = texture(normal_array, vec3(luv(0, xz), 0.0)).rgb;
	float rough = 0.95;
	float masks[8] = {0.0, s1.r, s1.g, s1.b, s1.a, s2.r, s2.g, s2.b};
	for (int k = 1; k < 8; k++) {
		float m = masks[k];
		float f = clamp(m * 1.15 - 0.1 + n1 * (k >= 5 ? 0.4 : 0.65), 0.0, 1.0);
		if (f > 0.001) {
			vec2 uv = luv(k, xz);
			col = mix(col, texture(albedo_array, vec3(uv, float(k))).rgb, f);
			nt = mix(nt, texture(normal_array, vec3(uv, float(k))).rgb, f);
		}
	}
	// trench floor and spoil: raw earth
	vec3 dirt = texture(albedo_array, vec3(luv(4, xz), 4.0)).rgb * 0.8;
	col = mix(col, dirt, clamp(dug * 1.4, 0.0, 1.0));
	// wet channel: darker
	col *= mix(1.0, 0.75, s2.a * 0.3);
	// macro variation
	col *= 0.82 + 0.36 * n2;
	// biom: cho'lda qum (yo'l va izlardan tashqari), tog'da tik joylarda yalang'och tosh, umumiy rang
	vec3 sand_col = vec3(0.78, 0.66, 0.47) * (0.86 + 0.24 * fbm(xz * 0.9)) * (0.93 + 0.1 * n2);
	col = mix(col, sand_col, sand * clamp(1.0 - s2.b * 0.8, 0.0, 1.0) * clamp(0.75 + n1, 0.0, 1.0));
	float steep = smoothstep(0.12, 0.4, 1.0 - clamp(wnrm.y, 0.0, 1.0));
	vec3 rock_col = vec3(0.44, 0.42, 0.4) * (0.75 + 0.45 * fbm(xz * 0.6 + 3.0));
	col = mix(col, rock_col, rockiness * steep);
	col *= biome_tint;

	// ---- snow
	float slope = 1.0 - clamp((wnrm.y - 0.75) / 0.2, 0.0, 1.0);
	float clear = clamp(s2.b * 0.85 + s2.r * 0.7 + s2.g * 0.9 + dug * 1.2 + slope * 0.6, 0.0, 1.0);
	// tog'da qor chizig'idan yuqorida qish bo'lmasa ham qor
	float peak = snow_line < 9000.0 ? smoothstep(snow_line - 3.0, snow_line + 5.0, wpos.y + n1 * 4.0) : 0.0;
	float sn = max(snow_amount, peak) * clamp(1.0 - clear + (n1 + 0.15) * 0.6, 0.0, 1.0);
	float slush = snow_amount * clamp(clear - 0.25, 0.0, 1.0);
	vec3 snow_col = vec3(0.86, 0.89, 0.93) * (0.93 + 0.1 * fbm(xz * 1.7));
	col = mix(col, col * vec3(0.55, 0.55, 0.58) + vec3(0.07), slush * 0.7);   // trodden slush on roads / tracks
	col = mix(col, snow_col, smoothstep(0.25, 0.6, sn));
	float snowf = smoothstep(0.25, 0.6, sn);

	vec3 n = nt * 2.0 - 1.0;
	n.xy *= mix(1.1, 0.25, snowf);
	vec3 N = normalize(wnrm);
	vec3 T = normalize(vec3(1.0, 0.0, 0.0) - N * N.x);
	vec3 B = normalize(vec3(0.0, 0.0, 1.0) - N * N.z);
	vec3 wn = normalize(T * n.x + B * n.y + N * max(n.z, 0.1));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ALBEDO = col;
	ROUGHNESS = mix(rough, 0.72, snowf);
	SPECULAR = mix(0.25, 0.4, snowf);
}
