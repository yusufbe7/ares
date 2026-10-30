// Village house materials (painted plaster, clay / slate roofs, brick fracture faces, concrete slabs, wood).
// UVs come from Blender in metres; COLOR.r = soot ("char") burnt in by explosions; snow lies on roofs
// and other upward faces when the global snow_amount is up.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

global uniform float snow_amount;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint = vec3(1.0);
uniform float uv_scale = 0.5;
uniform float roughness = 0.85;
uniform float snow_cap = 1.0;            // roofs collect snow, walls only a dusting on top edges
uniform bool grime = true;
instance uniform float char_amount = 0.0;  // debris pieces

varying vec3 wpos;
varying vec3 wnrm;
varying float vchar;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vchar = max(COLOR.r, char_amount);
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec3 col = texture(albedo_tex, uv).rgb * tint;
	if (grime) {
		float g = vnoise(wpos.xz * 1.5 + wpos.y) * clamp(1.0 - (wpos.y - 0.0) / 400.0, 0.0, 1.0);
		col *= mix(1.0, 0.82, g * 0.5);
	}
	float soot_n = vnoise(wpos.xz * 0.9 + wpos.y * 0.7) * 0.6 + vnoise(wpos.xz * 3.1 - wpos.y * 2.3) * 0.4;
	float c = clamp(vchar * 1.6 * smoothstep(0.15, 0.75, soot_n), 0.0, 0.9);
	col = mix(col, vec3(0.03, 0.028, 0.025), c);
	float up = clamp((wnrm.y - 0.45) / 0.35, 0.0, 1.0);
	// patchy snow: thick on slabs and chimney caps, broken drifts on the tiles
	float drift = vnoise(wpos.xz * 0.55 + vec2(wpos.y)) * 0.65 + vnoise(wpos.xz * 2.7) * 0.35;
	float sn = snow_amount * up * clamp(1.0 - c * 1.5, 0.0, 1.0);
	sn *= smoothstep(1.0 - snow_cap * 0.62, 1.12 - snow_cap * 0.62, drift);
	col = mix(col, vec3(0.88, 0.9, 0.94), sn);
	ALBEDO = col;
	NORMAL_MAP = mix(texture(normal_tex, uv).rgb, vec3(0.5, 0.5, 1.0), sn * 0.8);
	ROUGHNESS = mix(roughness, 0.75, sn);
}
