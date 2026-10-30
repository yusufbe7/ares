// Jang maydonidagi dengiz (qirg'oq biomi): kampaniya xaritasidagi o'sha GLB okean animatsiyasi,
// lekin haqiqiy masshtabda (bitta simulyatsiya bo'lagi = 50 m). Chuqurlik jang relyefidan olinadi.
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

#include "res://campaign/map/ocean.gdshaderinc"

uniform sampler2D ground : filter_linear, repeat_disable;   // jang relyefi balandligi (RF, metr)
uniform float half_size = 300.0;
uniform float level = -0.4;                                  // suv sathi, metr
uniform float wave_amp = 1.0;

varying vec3 wpos;
varying float depth;

float ground_h(vec2 xz) {
	return texture(ground, xz / (half_size * 2.0) + 0.5).r;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = level - ground_h(w.xz);
	// sohilda to'lqin pasayadi: qumga chiqib ketmasin
	float k = smoothstep(0.0, 3.0, d);
	VERTEX += ocean_displace(w.xz, TIME, wave_amp) * k;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	depth = d;
}

void fragment() {
	float d = level - ground_h(wpos.xz);
	vec4 nf = ocean_normal_foam(wpos.xz, TIME, 1.0);
	vec3 deep = vec3(0.012, 0.075, 0.12);
	vec3 shallow = vec3(0.06, 0.3, 0.31);
	vec3 c = mix(shallow, deep, smoothstep(0.5, 7.0, d));
	vec3 tex = texture(ocean_col, wpos.xz / 85.0 + vec2(TIME * 0.004, 0.0)).rgb;
	c *= 0.85 + 0.3 * dot(tex, vec3(0.33));
	float shore = 1.0 - smoothstep(0.0, 0.9, d);
	float crest = smoothstep(0.45, 0.95, nf.w);
	c = mix(c, vec3(0.85, 0.89, 0.9), clamp(crest * 0.5 + shore * 0.75, 0.0, 1.0) * 0.8);
	NORMAL = normalize((VIEW_MATRIX * vec4(nf.xyz, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
	ALBEDO = mix(c, vec3(0.45, 0.58, 0.7), fres * 0.5);
	ROUGHNESS = 0.06;
	SPECULAR = 0.7;
	// qirg'oqda yumshoq chiziq
	ALPHA = mix(0.55, 0.96, smoothstep(0.0, 1.5, d));
}
