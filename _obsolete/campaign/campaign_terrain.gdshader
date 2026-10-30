// Strategik xarita yeri: relyef ranglari (pasttekislik, cho'l, tog', qor) + davlat ranglari qoplamasi.
// Hudud rangi rasmni qayta yasamasdan almashadi: id_tex (province_ids.png) dan hudud id si o'qiladi,
// owner_tex jadvalidan (kenglik = hududlar soni + 1, balandlik 1) shu hudud egasining rangi olinadi.
// conquer() faqat owner_tex dagi bitta pikselni o'zgartiradi.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D id_tex : filter_nearest, repeat_disable;      // province_ids.png
uniform sampler2D owner_tex : filter_nearest, repeat_disable;   // rgb = egasi rangi, a = egasi id / 255
uniform vec2 map_px = vec2(2580.0, 1080.0);
uniform vec4 lonlat = vec4(-12.0, 74.0, 22.0, 58.0);             // lon_min, lon_max, lat_min, lat_max
uniform float overlay_alpha = 0.5;                              // davlat rangi qanchalik qoplaydi (relyef ko'rinib tursin)
uniform int selected_id = -1;
uniform int hover_id = -1;
uniform int hover_owner = -1;          // tanlash ekrani: sichqoncha ostidagi davlat butunlay yorishadi
uniform int selected_owner = -1;       // tanlash ekrani: bosilgan davlat
uniform int player_owner = -1;         // o'yinchi davlati: chegarasi oltin rangda
uniform float province_lines = 1.0;    // hudud chegaralari qanchalik ko'rinadi (tanlash ekranida xira)
uniform float time_scale = 1.0;
uniform bool show_owners = true;

varying float elev;      // metr
varying vec3 wnrm;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) { float s = 0.0; float a = 0.5; for (int k = 0; k < 4; k++) { s += a * vnoise(p); p *= 2.07; a *= 0.5; } return s; }

int pid(ivec2 p) {
	p = clamp(p, ivec2(0), ivec2(map_px) - 1);
	vec3 c = texelFetch(id_tex, p, 0).rgb;
	return int(round(c.r * 255.0)) + int(round(c.g * 255.0)) * 256;
}
vec4 owner_of(int id) {
	return texelFetch(owner_tex, ivec2(id, 0), 0);
}

void vertex() {
	elev = UV2.x * 1000.0;
	wnrm = NORMAL;
}

void fragment() {
	vec2 px = UV * map_px;
	ivec2 ip = ivec2(floor(px));
	float lat = mix(lonlat.w, lonlat.z, UV.y);
	float lon = mix(lonlat.x, lonlat.y, UV.x);
	// ---- relyef rangi
	float n = fbm(px * 0.08);
	float n2 = fbm(px * 0.6);
	float arid = clamp(smoothstep(37.0, 29.0, lat) + smoothstep(44.0, 52.0, lon) * smoothstep(47.0, 40.0, lat) * 0.9 + (n - 0.5) * 0.4, 0.0, 1.0);
	vec3 green = mix(vec3(0.27, 0.36, 0.17), vec3(0.36, 0.42, 0.2), n2);
	vec3 steppe = vec3(0.55, 0.5, 0.32);
	vec3 desert = mix(vec3(0.78, 0.66, 0.45), vec3(0.86, 0.75, 0.55), n2);
	vec3 col = mix(green, steppe, smoothstep(0.2, 0.55, arid));
	col = mix(col, desert, smoothstep(0.55, 0.9, arid));
	col = mix(col, col * 0.8 + vec3(0.06, 0.08, 0.02), smoothstep(52.0, 57.0, lat) * 0.6);      // shimol: o'rmon
	float slope = 1.0 - clamp(wnrm.y, 0.0, 1.0);
	float rock = clamp(smoothstep(1400.0, 2800.0, elev) + slope * 1.6, 0.0, 1.0);
	col = mix(col, mix(vec3(0.42, 0.38, 0.33), vec3(0.52, 0.48, 0.43), n2), rock * 0.85);
	float snow = smoothstep(3500.0, 4300.0, elev + (n - 0.5) * 600.0 - (lat - 40.0) * 60.0);
	col = mix(col, vec3(0.92, 0.93, 0.96), snow);
	col = mix(col, vec3(0.78, 0.74, 0.6), smoothstep(30.0, 0.0, elev) * 0.5);                     // qirg'oq qumi
	col *= 0.9 + 0.2 * n;
	// ---- davlat ranglari, chegaralar, tanlangan hudud
	int id = pid(ip);
	if (show_owners && id > 0) {
		vec4 o = owner_of(id);
		float a = overlay_alpha;
		int own = int(round(o.a * 255.0));
		if (id == hover_id) a += 0.12;
		if (own == hover_owner) a += 0.2;
		if (own == selected_owner) a += 0.16 + 0.08 * sin(TIME * 4.0);
		if (id == selected_id) a += 0.18 + 0.1 * sin(TIME * 4.0);
		col = mix(col, o.rgb, a);
		// chegara: qo'shni piksel boshqa hudud bo'lsa - ingichka chiziq; boshqa davlat bo'lsa - qalinroq
		int r = pid(ip + ivec2(1, 0)); int l = pid(ip - ivec2(1, 0));
		int u = pid(ip + ivec2(0, 1)); int d = pid(ip - ivec2(0, 1));
		bool prov_edge = r != id || l != id || u != id || d != id;
		float my_owner = o.a;
		bool country_edge = false;
		for (int k = 1; k <= 2; k++) {
			for (int s = 0; s < 4; s++) {
				ivec2 off = (s == 0 ? ivec2(k, 0) : (s == 1 ? ivec2(-k, 0) : (s == 2 ? ivec2(0, k) : ivec2(0, -k))));
				int j = pid(ip + off);
				if (j > 0 && abs(owner_of(j).a - my_owner) > 0.001) country_edge = true;
			}
		}
		if (prov_edge) col = mix(col, vec3(0.08, 0.07, 0.06), 0.45 * province_lines);
		if (country_edge) {
			vec3 ec = o.rgb * 0.35;
			if (own == player_owner) ec = vec3(1.0, 0.82, 0.35);
			if (own == hover_owner || own == selected_owner) ec = vec3(1.0, 0.96, 0.8);
			col = mix(col, ec, 0.85);
		}
		if (id == selected_id && prov_edge) col = vec3(1.0, 0.95, 0.7);
	}
	ALBEDO = col;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
}
