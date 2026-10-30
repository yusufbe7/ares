// Yaqin kadrdagi okean: kamera ostidagi zich to'r, GLB simulyatsiyasining haqiqiy 3D to'lqinlari bilan
// (vertex siljishi). Chetlari va uzoqlashganda shaffof bo'lib, xarita shaderidagi okeanga qo'shilib ketadi.
// Quruqlik ustida chizilmaydi (province_ids: id > 0).
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform sampler2D id_tex : filter_nearest, repeat_disable;
uniform sampler2D sat_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 map_px = vec2(4320.0, 1704.0);
uniform vec2 map_size = vec2(432.0, 170.4);    // dunyo birligida
uniform float cam_dist = 10.0;
uniform float amp = 2.6;                       // to'lqin balandligi bo'rttirilishi
uniform vec3 center = vec3(0.0);
uniform float radius = 10.0;
#include "res://campaign/map/ocean.gdshaderinc"

varying vec3 wpos;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float edge = 1.0 - smoothstep(radius * 0.55, radius, length(w.xz - center.xz));
	// siljish dunyo birligida, tugun masshtablangan: lokal koordinataga o'tkazamiz
	VERTEX += inverse(mat3(MODEL_MATRIX)) * (ocean_displace(w.xz, TIME, amp) * edge);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz / map_size + 0.5;
	// quruqlik: xarita shaderidagi kabi silliq qirg'oq (atrofdagi 4 piksel "dengizlik" ulushi)
	vec2 p = uv * map_px - 0.5;
	ivec2 i = ivec2(floor(p));
	vec2 fq = fract(p);
	float sea[4];
	for (int k = 0; k < 4; k++) {
		ivec2 q = clamp(i + ivec2(k % 2, k / 2), ivec2(0), ivec2(map_px) - 1);
		vec3 c = texelFetch(id_tex, q, 0).rgb;
		sea[k] = (round(c.r * 255.0) + round(c.g * 255.0) * 256.0) < 0.5 ? 1.0 : 0.0;
	}
	float sf = mix(mix(sea[0], sea[1], fq.x), mix(sea[2], sea[3], fq.x), fq.y);
	if (sf < 0.5) {
		discard;                                   // quruqlik
	}
	float near = 1.0 - smoothstep(10.0, 48.0, cam_dist);
	float depth = ocean_depth(uv);
	vec4 nf = ocean_normal_foam(wpos.xz, TIME, 1.0);
	vec3 sat = texture(sat_tex, uv).rgb * 1.35;
	vec3 col = ocean_color(wpos.xz, uv, depth, nf.w, near, TIME, sat);
	NORMAL = normalize((VIEW_MATRIX * vec4(nf.xyz, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
	ALBEDO = mix(col, vec3(0.42, 0.55, 0.68), fres * 0.45 * near);
	ROUGHNESS = 0.07;
	SPECULAR = 0.75;
	float edge = 1.0 - smoothstep(radius * 0.6, radius, length(wpos.xz - center.xz));
	ALPHA = edge * near;
}
