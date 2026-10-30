// Okean: "Free Ocean simulation - Tiled" (the9thearl, CC-BY-4.0) animatsiyasi tools/bake_ocean.py bilan
// teksturaga pishirilgan (124+1 kadr, 144x144, 12 ustunli atlas). Bu fayl xarita shaderi va yaqin kadrdagi
// 3D to'lqin qatlami (ocean_near.gdshader) uchun umumiy.
//   ocean_disp   RGB = to'lqin siljishi (dx, dy, dz), [disp_min, disp_max] oralig'ida
//   ocean_nrm    RG = normal (x, z), B = ko'pik (to'lqin cho'qqisi)
//   ocean_col    GLB dagi suv / ko'pik rangi
// Ikki qatlam: asosiy (ocean_tile) va kattaroq, burilgan, boshqa vaqtdan boshlangan qatlam -
// bir xil naqsh takrorlanib ko'rinmasin.
uniform sampler2D ocean_disp : filter_linear, repeat_disable;
uniform sampler2D ocean_nrm : filter_linear, repeat_disable;
uniform sampler2D ocean_col : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D height_tex : filter_nearest, repeat_disable;     // map/height.png (dengiz chuqurligi)
uniform float ocean_tile = 0.55;          // bitta 50 m li simulyatsiya bo'lagi necha dunyo birligi
uniform float ocean_fps = 12.0;
uniform int ocean_frames = 125;
uniform int ocean_cols = 12;
uniform int ocean_grid = 144;
uniform vec3 disp_min = vec3(-0.424, -0.878, -0.447);
uniform vec3 disp_max = vec3(0.529, 1.045, 0.469);
uniform vec2 height_px = vec2(4320.0, 1704.0);

vec2 _cell_uv(vec2 t, int f) {
	int c = ocean_grid + 2;
	vec2 atlas = vec2(float(ocean_cols * c), float(((ocean_frames + ocean_cols - 1) / ocean_cols) * c));
	vec2 o = vec2(float((f % ocean_cols) * c), float((f / ocean_cols) * c)) + 1.0;
	return (o + fract(t) * float(ocean_grid)) / atlas;
}

// bitta qatlam: t - bo'lak koordinatasi (1 = bitta bo'lak), time - soniya
vec4 _layer_nrm(vec2 t, float time) {
	float ft = time * ocean_fps;
	int f0 = int(floor(ft)) % ocean_frames;
	int f1 = (f0 + 1) % ocean_frames;
	return mix(texture(ocean_nrm, _cell_uv(t, f0)), texture(ocean_nrm, _cell_uv(t, f1)), fract(ft));
}

vec3 _layer_disp(vec2 t, float time) {
	float ft = time * ocean_fps;
	int f0 = int(floor(ft)) % ocean_frames;
	int f1 = (f0 + 1) % ocean_frames;
	vec3 e = mix(texture(ocean_disp, _cell_uv(t, f0)).rgb, texture(ocean_disp, _cell_uv(t, f1)).rgb, fract(ft));
	return mix(disp_min, disp_max, e);
}

const mat2 OCEAN_ROT = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));

// dunyo (x, z) -> to'lqin siljishi dunyo birligida (balandlik bo'rttirilgan: amp)
vec3 ocean_displace(vec2 w, float time, float vamp) {
	float s = ocean_tile / 50.0;                       // metr -> dunyo birligi
	vec3 a = _layer_disp(w / ocean_tile, time);
	vec3 b = _layer_disp(OCEAN_ROT * w / (ocean_tile * 2.7), time * 0.8 + 3.1);
	return vec3(a.x + b.x * 1.6, (a.y + b.y * 1.8) * vamp, a.z + b.z * 1.6) * s;
}

// dunyo (x, z) -> (normal xyz, ko'pik)
vec4 ocean_normal_foam(vec2 w, float time, float strength) {
	vec4 a = _layer_nrm(w / ocean_tile, time);
	vec4 b = _layer_nrm(OCEAN_ROT * w / (ocean_tile * 2.7), time * 0.8 + 3.1);
	vec2 na = a.rg * 2.0 - 1.0;
	vec2 nb = OCEAN_ROT * (b.rg * 2.0 - 1.0);        // burilgan qatlam normali ham buriladi
	vec2 n = (na + nb * 0.8) * strength;
	return vec4(normalize(vec3(n.x, 1.0, n.y)), clamp(a.b + b.b * 0.6, 0.0, 1.0));
}

float _hm(ivec2 p) {
	p = clamp(p, ivec2(0), ivec2(height_px) - 1);
	vec3 c = texelFetch(height_tex, p, 0).rgb;
	return (round(c.r * 255.0) * 256.0 + round(c.g * 255.0)) * 0.5 - 12000.0;
}

// dengiz chuqurligi, metr (musbat), bilinear: piksel pog'onalari ko'rinmasin
float ocean_depth(vec2 uv) {
	vec2 p = uv * height_px - 0.5;
	ivec2 i = ivec2(floor(p));
	vec2 f = fract(p);
	float h = mix(mix(_hm(i), _hm(i + ivec2(1, 0)), f.x), mix(_hm(i + ivec2(0, 1)), _hm(i + ivec2(1, 1)), f.x), f.y);
	return max(-h, 0.0);
}

// Okean rangi. near: 0 = uzoq (xarita, tungi), 1 = yaqin (real suv). view_up: kamera qanchalik tepadan
vec3 ocean_color(vec2 w, vec2 uv, float depth, float foam, float near, float time, vec3 sat) {
	// chuqur suv to'q ko'k, sayozlik (shelf) yashil-feruza, sohil yonida och
	vec3 deep = vec3(0.008, 0.045, 0.1);
	vec3 mid = vec3(0.012, 0.1, 0.17);
	vec3 shallow = vec3(0.04, 0.28, 0.32);
	vec3 c = mix(shallow, mid, smoothstep(5.0, 160.0, depth));
	c = mix(c, deep, smoothstep(160.0, 2600.0, depth));
	// GLB suv rangi teksturasi (mayda tafsilot, juda xira)
	vec3 tex = texture(ocean_col, w / (ocean_tile * 1.7) + vec2(time * 0.004, 0.0)).rgb;
	c *= mix(1.0, 0.85 + 0.3 * dot(tex, vec3(0.33)), near * 0.5);
	// ko'pik: to'lqin cho'qqisi va sohil
	// ko'pik faqat to'lqin cho'qqisida (kuchli siqilish) va sohil yonida, me'yorida
	float shore = 1.0 - smoothstep(0.0, 12.0, depth);
	float crest = smoothstep(0.45, 0.95, foam);
	float f = clamp(crest * 0.45 + shore * (0.2 + 0.5 * crest), 0.0, 1.0) * near;
	c = mix(c, vec3(0.82, 0.87, 0.9) * (0.7 + 0.3 * dot(tex, vec3(0.33))), f * 0.7);
	// uzoqda: xarita uslubidagi tungi okean (Blue Marble okeani bilan aralash)
	vec3 night = mix(sat * 0.42, vec3(0.012, 0.03, 0.06), 0.45);
	night = mix(night, night * 1.6 + vec3(0.0, 0.03, 0.035), (1.0 - smoothstep(30.0, 400.0, depth)) * 0.6);
	return mix(night, c, near);
}
