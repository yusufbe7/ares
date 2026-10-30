## Jang maydoni generatori: hudud turiga qarab (data/battle_biomes.json) 600x600 m maydon yaratadi va
## EuropeMap qabul qiladigan "spec" ni qaytaradi (relyef, tuproq qatlamlari, nav to'ri, o'simliklar, uylar,
## zonalar, kirish nuqtalari, suv, minixarita). Fayllar yozilmaydi - hammasi xotirada, bir necha soniyada.
## Bir hudud uchun seed bir xil -> maydon ham bir xil.
class_name BattleGen
extends RefCounted

const RES := 1025
const SIZE := 600.0
const HALF := 300.0
const GRID := SIZE / 1024.0
const COARSE := 257
const SPLAT := 512
const BIOMES := "res://data/battle_biomes.json"


static func biomes() -> Dictionary:
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(BIOMES)) if FileAccess.file_exists(BIOMES) else null
	return j if j is Dictionary else {}


static func generate(biome_name: String, seed_value: int) -> Dictionary:
	var all := biomes()
	var b: Dictionary = all.get(biome_name, all.get("temperate", {}))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var L := BattleLayout.plan(b, rng)
	var h := _heights(b, rng, L)
	_flatten(h, L)
	var slope := func(p: Vector2) -> float: return _slope(h, p)
	var veg := BattleLayout.vegetation(b, rng, L, slope)
	var spl := _splats(b, h, L, rng)
	var village: Array = []
	for info in L.houses:
		village.append(info)
	return {"biome": biome_name, "heights": h, "splat1": spl[0], "splat2": spl[1], "nav": _nav(h, L),
		"vegetation": veg, "village": village, "winter": bool(b.get("winter", false)),
		"shader": {"biome_tint": _v3(b.get("tint", [1, 1, 1])), "sand": float(b.get("sand", 0.0)),
			"rockiness": float(b.get("rock", 0.0)), "snow_line": float(b.get("snow_line", 9999))},
		"water": L.coast != null, "coast": L.coast if L.coast != null else -9999.0, "minimap": _minimap(h, L, b, spl[1]),
		"layout": {"zones": L.zones, "entry": L.entry, "enemy_entry": L.enemy_entry}}


static func _v3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func at(h: PackedFloat32Array, x: float, z: float) -> float:
	var i := clampi(int(round((x + HALF) / GRID)), 0, RES - 1)
	var j := clampi(int(round((z + HALF) / GRID)), 0, RES - 1)
	return h[j * RES + i]


static func _slope(h: PackedFloat32Array, p: Vector2) -> float:
	var dx := at(h, p.x + 2.0, p.y) - at(h, p.x - 2.0, p.y)
	var dz := at(h, p.x, p.y + 2.0) - at(h, p.x, p.y - 2.0)
	return Vector2(dx, dz).length() / 4.0          # tangens: 1.0 = 45 daraja


## Relyef: yumshoq tepaliklar + (tog'da) tizmalar; qirg'oqda g'arb tomoni dengiz tubiga tushadi.
## Avval 257x257 shovqin, keyin kubik interpolyatsiya bilan 1025x1025 (tez va silliq).
static func _heights(b: Dictionary, rng: RandomNumberGenerator, L: Dictionary) -> PackedFloat32Array:
	var n1 := FastNoiseLite.new()
	n1.seed = rng.randi()
	n1.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n1.fractal_octaves = 5
	n1.frequency = float(b.get("freq", 0.006))
	var n2 := FastNoiseLite.new()
	n2.seed = rng.randi()
	n2.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	n2.fractal_octaves = 4
	n2.frequency = float(b.get("freq", 0.006)) * 0.8
	var amp := float(b.get("amp", 6.0))
	var ridge := float(b.get("ridge", 0.0))
	var img := Image.create(COARSE, COARSE, false, Image.FORMAT_RF)
	for j in COARSE:
		for i in COARSE:
			var x := -HALF + i * SIZE / (COARSE - 1)
			var z := -HALF + j * SIZE / (COARSE - 1)
			var v := n1.get_noise_2d(x, z) * (1.0 - ridge) + (n2.get_noise_2d(x, z) * 0.5 + 0.35) * ridge
			var hv := v * amp
			if L.coast != null:
				var cx: float = float(L.coast) + sin(z * 0.021) * 14.0 + n1.get_noise_2d(z, 77.0) * 10.0
				var t := clampf((cx + 38.0 - x) / 60.0, 0.0, 1.0)
				hv = lerpf(hv * 0.35 + 1.0, -7.5, smoothstep(0.0, 1.0, t)) if x < cx + 38.0 else hv
			img.set_pixel(i, j, Color(hv, 0, 0))
	img.resize(RES, RES, Image.INTERPOLATE_CUBIC)
	return img.get_data().to_float32_array()


## Uy ostini, yo'llarni va zonalarni tekislaymiz (askar va tank o'ta olsin, uy havoda qolmasin).
static func _flatten(h: PackedFloat32Array, L: Dictionary) -> void:
	for info in L.houses:
		var p := Vector2(info.place.x, info.place.z)
		var r := maxf(float(info.W), float(info.D)) * 0.8 + 3.0
		_flat_disc(h, p, r, 5.0, _avg(h, p, r))
	for z in L.zones:
		_flat_disc(h, z.pos, float(z.r) * 0.5, float(z.r) * 0.4, _avg(h, z.pos, float(z.r) * 0.5), 0.6)
	for road in L.roads:
		for k in range(1, road.size()):
			var a: Vector2 = road[k - 1]
			var c: Vector2 = road[k]
			var steps := int(a.distance_to(c) / 2.0) + 1
			for s in steps:
				var p := a.lerp(c, float(s) / steps)
				_flat_disc(h, p, 3.0, 3.0, _avg(h, p, 6.0), 0.5)


static func _avg(h: PackedFloat32Array, p: Vector2, r: float) -> float:
	var s := 0.0
	for o in [Vector2.ZERO, Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
		s += at(h, p.x + o.x, p.y + o.y)
	return s / 5.0


static func _flat_disc(h: PackedFloat32Array, p: Vector2, r: float, fall: float, target: float, strength := 1.0) -> void:
	var R := r + fall
	var i0 := clampi(int((p.x - R + HALF) / GRID), 0, RES - 1)
	var i1 := clampi(int((p.x + R + HALF) / GRID) + 1, 0, RES - 1)
	var j0 := clampi(int((p.y - R + HALF) / GRID), 0, RES - 1)
	var j1 := clampi(int((p.y + R + HALF) / GRID) + 1, 0, RES - 1)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var d := Vector2(-HALF + i * GRID, -HALF + j * GRID).distance_to(p)
			if d < R:
				var k := j * RES + i
				var w := (1.0 - smoothstep(r, R, d)) * strength
				h[k] = lerpf(h[k], target, w)


## Tuproq qatlamlari (EuropeMap terrain.gdshader): splat1 = siyrak o't / qurigan / quruq / loy,
## splat2 = iz / voronka / yo'l / nam. 512 da hisoblanadi, 2048 ga kattalashtiriladi.
static func _splats(b: Dictionary, h: PackedFloat32Array, L: Dictionary, rng: RandomNumberGenerator) -> Array:
	var sp: Dictionary = b.get("splat", {})
	var n := FastNoiseLite.new()
	n.seed = rng.randi()
	n.frequency = 0.02
	var road := PackedFloat32Array()
	road.resize(SPLAT * SPLAT)
	var cell := SIZE / SPLAT
	for r in L.roads:
		for k in range(1, r.size()):
			var a: Vector2 = r[k - 1]
			var c: Vector2 = r[k]
			var steps := int(a.distance_to(c) / cell) + 1
			for s in steps:
				var p := a.lerp(c, float(s) / steps)
				var ci := int((p.x + HALF) / cell)
				var cj := int((p.y + HALF) / cell)
				for dj in range(-3, 4):
					for di in range(-3, 4):
						var ii := ci + di
						var jj := cj + dj
						if ii >= 0 and jj >= 0 and ii < SPLAT and jj < SPLAT:
							var w := 1.0 - smoothstep(1.4, 3.2, Vector2(di, dj).length())
							road[jj * SPLAT + ii] = maxf(road[jj * SPLAT + ii], w)
	var s1 := Image.create(SPLAT, SPLAT, false, Image.FORMAT_RGBA8)
	var s2 := Image.create(SPLAT, SPLAT, false, Image.FORMAT_RGBA8)
	for j in SPLAT:
		for i in SPLAT:
			var x := -HALF + (i + 0.5) * cell
			var z := -HALF + (j + 0.5) * cell
			var e := n.get_noise_2d(x, z)
			var e2 := n.get_noise_2d(z * 1.7, x * 1.7)
			var sl := _slope(h, Vector2(x, z))
			var hh := at(h, x, z)
			var rd := road[j * SPLAT + i]
			var grass := clampf(float(sp.get("grass", 0.6)) + e * 0.5 - sl * 0.8, 0.0, 1.0)
			var withered := clampf(float(sp.get("withered", 0.4)) + e2 * 0.5, 0.0, 1.0)
			var dry := clampf(float(sp.get("dry", 0.2)) - e * 0.4 + sl * 0.9, 0.0, 1.0)
			var mud := clampf(float(sp.get("mud", 0.1)) + e2 * 0.3 + rd * 0.3, 0.0, 1.0)
			var wet := clampf(smoothstep(0.6, -0.8, hh) if L.coast != null and x < float(L.coast) + 50.0 else 0.0, 0.0, 1.0)
			s1.set_pixel(i, j, Color(grass * (1.0 - rd), withered * (1.0 - rd), dry, mud))
			s2.set_pixel(i, j, Color(clampf(rd * 0.6 + maxf(e2, 0.0) * 0.15, 0.0, 1.0), 0.0, rd, wet))
	s1.resize(2048, 2048, Image.INTERPOLATE_BILINEAR)
	s2.resize(2048, 2048, Image.INTERPOLATE_BILINEAR)
	return [s1, s2]


## Suv faqat qirg'oq tomonda (quruqlikdagi pastliklar suv emas).
static func is_water(L: Dictionary, h: PackedFloat32Array, p: Vector2) -> bool:
	return L.coast != null and p.x < float(L.coast) + 45.0 and at(h, p.x, p.y) < -0.3


## Nav to'ri (300x300, 2 m): suv va juda tik qiyalik o'tib bo'lmaydi (> 127).
static func _nav(h: PackedFloat32Array, L: Dictionary) -> Image:
	var img := Image.create(300, 300, false, Image.FORMAT_L8)
	for j in 300:
		for i in 300:
			var p := Vector2(-HALF + i * 2.0 + 1.0, -HALF + j * 2.0 + 1.0)
			var solid := is_water(L, h, p) or _slope(h, p) > 0.85
			img.set_pixel(i, j, Color(1, 1, 1) if solid else Color(0, 0, 0))
	return img


## Minixarita (256): relyef soyasi, biom rangi, yo'llar, uylar, suv.
static func _minimap(h: PackedFloat32Array, L: Dictionary, b: Dictionary, s2: Image) -> Image:
	var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
	var t := _v3(b.get("tint", [1, 1, 1]))
	var base := Color(0.36, 0.42, 0.26).lerp(Color(0.72, 0.62, 0.42), float(b.get("sand", 0.0)) + float(b.get("splat", {}).get("dry", 0.2)) * 0.4)
	if b.get("winter", false):
		base = Color(0.86, 0.88, 0.9)
	var c := SIZE / 256.0
	for j in 256:
		for i in 256:
			var x := -HALF + (i + 0.5) * c
			var z := -HALF + (j + 0.5) * c
			var hh := at(h, x, z)
			var shade := clampf(1.0 + (at(h, x - 2.0, z - 2.0) - hh) * 0.12, 0.6, 1.3)
			var col := Color(base.r * t.x, base.g * t.y, base.b * t.z) * shade
			if is_water(L, h, Vector2(x, z)):
				col = Color(0.12, 0.3, 0.42)
			elif s2.get_pixel(i * 8 + 4, j * 8 + 4).b > 0.45:
				col = Color(0.32, 0.3, 0.27)
			img.set_pixel(i, j, col)
	for info in L.houses:
		var cx := int((float(info.place.x) + HALF) / c)
		var cz := int((float(info.place.z) + HALF) / c)
		img.fill_rect(Rect2i(cx - 2, cz - 2, 5, 5), Color(0.55, 0.3, 0.22))
	return img
