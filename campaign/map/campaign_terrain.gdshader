// Strategik xarita yeri: haqiqiy sun'iy yo'ldosh rangi (NASA Blue Marble) + relyef soyasi + qorong'i okean.
// Ustida ma'lumot qatlamlari: davlat rangi (xira), chegaralar, ittifoqchilar, resurslar, tanlangan hudud.
// Hudud id si id_tex dan (id = R + G*256), qolgan hammasi info_tex dan (map_terrain.gd ga qarang).
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D id_tex : filter_nearest, repeat_disable;
uniform sampler2D info_tex : filter_nearest, repeat_disable;
uniform sampler2D sat_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_disable;
uniform vec2 map_px = vec2(4320.0, 1704.0);
uniform int view_mode = 0;              // 0 siyosiy, 1 relyef (tabiiy), 2 resurs
uniform float political_alpha = 0.15;   // davlat rangi yengil tus (asosiy rang - sun'iy yo'ldosh)
uniform float brightness = 1.35;      // Blue Marble biroz qorong'i: yorqinlik
uniform bool show_borders = true;       // hudud chegaralari
uniform bool show_allies = false;       // ittifoqchi hududlar shtrix bilan
uniform int selected_id = -1;
uniform int hover_id = -1;
uniform int hover_owner = -1;
uniform int selected_owner = -1;
uniform int player_owner = -1;
uniform float province_lines = 1.0;

uniform float cam_dist = 80.0;          // kamera masofasi: yaqinlashganda okean "real" bo'ladi
#include "res://campaign/map/ocean.gdshaderinc"

varying vec3 wpos;

int pid(ivec2 p) {
	p = clamp(p, ivec2(0), ivec2(map_px) - 1);
	vec3 c = texelFetch(id_tex, p, 0).rgb;
	return int(round(c.r * 255.0)) + int(round(c.g * 255.0)) * 256;
}
vec4 row(int id, int r) { return texelFetch(info_tex, ivec2(id, r), 0); }
int owner_of(int id) {
	if (id <= 0) return 0;
	vec4 o = row(id, 1);
	return int(round(o.r * 255.0)) + int(round(o.g * 255.0)) * 256;
}
int flags_of(int id) { return id > 0 ? int(round(row(id, 1).a * 255.0)) : 0; }
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Qirg'oq silliq bo'lsin: atrofdagi 4 pikselning "dengizlik" ulushi (bilinear). Piksel ~9 km, shuning uchun
// to'g'ridan-to'g'ri id bo'yicha ajratilsa yaqindan zinapoya ko'rinadi.
float sea_frac(vec2 px) {
	vec2 p = px - 0.5;
	ivec2 i = ivec2(floor(p));
	vec2 f = fract(p);
	float a = pid(i) == 0 ? 1.0 : 0.0;
	float b = pid(i + ivec2(1, 0)) == 0 ? 1.0 : 0.0;
	float c = pid(i + ivec2(0, 1)) == 0 ? 1.0 : 0.0;
	float d = pid(i + ivec2(1, 1)) == 0 ? 1.0 : 0.0;
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// dengiz pikseli qirg'oqqa yaqin bo'lsa - yonidagi quruqlik hududi (quruqlik rangi uchun)
int land_near(ivec2 ip) {
	int id = pid(ip);
	for (int k = 0; k < 8 && id == 0; k++) {
		ivec2 o = ivec2(k < 3 ? k - 1 : (k < 5 ? (k == 3 ? -1 : 1) : k - 6), k < 3 ? -1 : (k < 5 ? 0 : 1));
		id = pid(ip + o);
	}
	return id;
}

void fragment() {
	vec2 px = UV * map_px;
	ivec2 ip = ivec2(floor(px));
	vec3 sat = texture(sat_tex, UV).rgb * brightness;
	// relyef soyasi: normal.png (x sharq, y janub, z tepa) -> dunyo normali
	vec3 nt = texture(normal_tex, UV).rgb * 2.0 - 1.0;
	vec3 wn = normalize(vec3(nt.x, nt.z, nt.y));
	float sf = sea_frac(px);
	float aa = max(fwidth(sf), 0.03);
	float wm = smoothstep(0.5 - aa, 0.5 + aa, sf);         // 1 = suv, 0 = quruqlik (silliq qirg'oq)
	int id = wm > 0.5 ? 0 : land_near(ip);                 // tanlash, chegaralar uchun
	// ---------------- quruqlik
	vec3 col = sat;
	vec3 land_n = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(wn, 0.0)).xyz, 0.3));
	if (wm < 1.0) {
		int lid = land_near(ip);
		// yaqinlashganda mayda yer donadorligi (sun'iy yo'ldosh rasmi xira ko'rinmasin); uzoqda o'chadi
		float nearl = 1.0 - smoothstep(0.25, 1.2, fwidth(px.x));
		float dn = vnoise(px * 2.3) * 0.45 + vnoise(px * 7.1) * 0.35 + vnoise(px * 19.0) * 0.2;
		col *= mix(1.0, 0.86 + 0.28 * dn, nearl);
		if (lid > 0) {
			int own = owner_of(lid);
			int fl = flags_of(lid);
			vec3 oc0 = row(lid, 0).rgb;
			vec3 oc = mix(vec3(dot(oc0, vec3(0.3, 0.59, 0.11))), oc0, 0.7);    // davlat rangi biroz xira
			float a = view_mode == 0 ? political_alpha : (view_mode == 1 ? 0.05 : 0.0);
			if (own == hover_owner) a += 0.22;
			if (own == selected_owner) a += 0.2 + 0.08 * sin(TIME * 4.0);
			if (lid == hover_id) a += 0.14;
			if (lid == selected_id) a += 0.22 + 0.1 * sin(TIME * 4.0);
			col = mix(col, oc, clamp(a, 0.0, 0.9));
			if (view_mode == 2) {
				vec4 rc = row(lid, 2);
				float g = dot(sat, vec3(0.3, 0.59, 0.11));
				col = mix(vec3(g) * 0.6, rc.rgb, 0.35 + 0.35 * rc.a);
			}
			if (show_allies && (fl & 1) != 0 && (fl & 2) == 0) {
				float st = step(0.5, fract((px.x + px.y) * 0.18));
				col = mix(col, vec3(0.35, 0.7, 1.0), st * 0.28);
			}
			// chegaralar (faqat quruqlik hududlari orasida; dengiz bilan chegara = silliq qirg'oq)
			int r = clamp(int(ceil(fwidth(px.x) * 0.9)), 1, 4);
			int pr = pid(ip + ivec2(r, 0)); int pl = pid(ip - ivec2(r, 0));
			int pu = pid(ip + ivec2(0, r)); int pd = pid(ip - ivec2(0, r));
			bool prov_edge = (pr > 0 && pr != lid) || (pl > 0 && pl != lid) || (pu > 0 && pu != lid) || (pd > 0 && pd != lid);
			bool country_edge = (pr > 0 && owner_of(pr) != own) || (pl > 0 && owner_of(pl) != own)
				|| (pu > 0 && owner_of(pu) != own) || (pd > 0 && owner_of(pd) != own);
			if (prov_edge && show_borders) col = mix(col, vec3(0.05, 0.05, 0.05), 0.42 * province_lines);
			if (country_edge) {
				vec3 ec = mix(oc, vec3(1.0), 0.55);
				if (own == player_owner) ec = vec3(1.0, 0.72, 0.25);
				if (own == hover_owner || own == selected_owner) ec = vec3(1.0, 0.95, 0.8);
				col = mix(col, ec, 0.85);
			}
			if (lid == selected_id && prov_edge) col = vec3(1.0, 0.86, 0.45);
		}
	}
	// ---------------- okean: uzoqda tungi xarita uslubi, yaqinlashganda GLB simulyatsiyasining haqiqiy
	// to'lqinlari, ko'pik, sayoz suv rangi, quyosh yaltirashi va osmon aksi (Fresnel)
	vec3 wcol = col;
	vec3 sea_n = land_n;
	float near = 1.0 - smoothstep(10.0, 48.0, cam_dist);
	if (wm > 0.0) {
		float wav = 1.0 - smoothstep(0.08, 0.45, fwidth(wpos.x / ocean_tile));   // juda uzoqda to'lqin chizilmaydi
		float depth = ocean_depth(UV);
		vec4 nf = ocean_normal_foam(wpos.xz, TIME, 1.0);
		vec3 wn2 = normalize(mix(vec3(0.0, 1.0, 0.0), nf.xyz, max(wav * near, 0.15 * wav)));
		wcol = ocean_color(wpos.xz, UV, depth, nf.w * wav, near, TIME, sat);
		sea_n = normalize((VIEW_MATRIX * vec4(wn2, 0.0)).xyz);
		float fres = pow(1.0 - clamp(dot(sea_n, VIEW), 0.0, 1.0), 5.0);
		wcol = mix(wcol, vec3(0.42, 0.55, 0.68), fres * 0.45 * near);
	}
	ALBEDO = mix(col, wcol, wm);
	NORMAL = normalize(mix(land_n, sea_n, wm));
	ROUGHNESS = mix(0.92, mix(0.3, 0.07, near), wm);
	SPECULAR = mix(0.15, mix(0.5, 0.75, near), wm);
}
