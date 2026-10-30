// Davlat tanlash xaritasi: sun'iy yo'ldosh rasmi, tanlangan davlat hududlari yoritiladi (sel teksturasi:
// hudud id -> 1 tanlangan, 0.5 ittifoqchi), hudud chegaralari ingichka chiziq.
shader_type canvas_item;

uniform sampler2D ids : filter_nearest, repeat_disable;
uniform sampler2D sel : filter_nearest, repeat_disable;
uniform vec2 ids_px = vec2(4320.0, 1704.0);
uniform vec4 sel_color : source_color = vec4(0.91, 0.64, 0.23, 1.0);
uniform vec4 ally_color : source_color = vec4(0.35, 0.6, 0.95, 1.0);

int pid(ivec2 p) {
	vec3 c = texelFetch(ids, clamp(p, ivec2(0), ivec2(ids_px) - 1), 0).rgb;
	return int(round(c.r * 255.0)) + int(round(c.g * 255.0)) * 256;
}

void fragment() {
	vec3 c = texture(TEXTURE, UV).rgb;
	ivec2 p = ivec2(UV * ids_px);
	int id = pid(p);
	float s = id > 0 ? texelFetch(sel, ivec2(id, 0), 0).r : 0.0;
	vec3 gray = vec3(dot(c, vec3(0.3, 0.59, 0.11)));
	vec3 base = mix(gray, c, 0.75) * 0.8;
	vec3 o = base;
	if (s > 0.9) {
		o = mix(c * 1.15, sel_color.rgb, 0.4);
	} else if (s > 0.4) {
		o = mix(base, ally_color.rgb, 0.3);
	}
	// chegara: qo'shni piksel boshqa hudud
	int r = pid(p + ivec2(1, 0));
	int d = pid(p + ivec2(0, 1));
	if (id > 0 && (r != id || d != id)) {
		o = mix(o, vec3(0.0), 0.35);
	}
	COLOR = vec4(o, 1.0);
}
