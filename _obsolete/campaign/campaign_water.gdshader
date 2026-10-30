// Dengiz: chuqurlikka qarab rang (qirg'oq yonida ochiq), sekin harakatlanuvchi to'lqinlar.
shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

uniform sampler2D depth_tex : filter_linear, repeat_disable;   // r = chuqurlik (0 qirg'oq .. 1 chuqur)
uniform vec3 deep = vec3(0.04, 0.12, 0.22);
uniform vec3 shallow = vec3(0.16, 0.38, 0.45);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	float d = texture(depth_tex, UV).r;
	vec2 wp = UV * vec2(1290.0, 540.0);
	float w1 = vnoise(wp * 0.35 + vec2(TIME * 0.12, TIME * 0.05));
	float w2 = vnoise(wp * 0.9 - vec2(TIME * 0.08, -TIME * 0.11));
	vec3 col = mix(shallow, deep, smoothstep(0.0, 0.55, d));
	col += vec3(0.5, 0.55, 0.55) * smoothstep(0.06, 0.0, d) * (0.4 + 0.6 * w2);   // qirg'oq ko'pigi
	ALBEDO = col * (0.92 + 0.12 * w1);
	NORMAL_MAP = normalize(vec3((w1 - 0.5) * 0.5, (w2 - 0.5) * 0.5, 1.0)) * 0.5 + 0.5;
	ROUGHNESS = 0.18;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
