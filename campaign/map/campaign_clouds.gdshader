// Sekin suzuvchi siyrak bulutlar va yengil tuman. Kamera uzoqda ko'rinadi (fade), yaqinda yo'qoladi.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float fade = 1.0;
uniform float coverage = 0.66;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) { float s = 0.0; float a = 0.5; for (int k = 0; k < 5; k++) { s += a * vnoise(p); p *= 2.03; a *= 0.5; } return s; }

void fragment() {
	vec2 p = UV * vec2(36.0, 15.0) + vec2(TIME * 0.012, TIME * 0.004);
	float n = fbm(p + fbm(p * 0.5 + TIME * 0.003) * 1.5);
	float c = smoothstep(coverage, coverage + 0.22, n);
	float edge = smoothstep(0.0, 0.08, UV.x) * smoothstep(1.0, 0.92, UV.x) * smoothstep(0.0, 0.08, UV.y) * smoothstep(1.0, 0.92, UV.y);
	ALBEDO = vec3(0.86, 0.88, 0.92);
	ALPHA = c * 0.16 * fade * edge;
}
