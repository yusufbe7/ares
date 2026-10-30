## Jang maydoni joylashuvi: zonalar (A / B / C), kirish nuqtalari, yo'llar, uylar va o'simliklar.
## Tuzilishi asl operatsiya kabi: biz janubi-g'arbdan, dushman shimoli-sharqdan; A - chorraha, B - shaharcha
## (uylar), C - dushman tayanch nuqtasi. Hammasi tasodifiy (seed), lekin bir hudud uchun doim bir xil.
class_name BattleLayout
extends RefCounted

const HALF := 300.0
const HOUSES := "res://europe/village.json"
const VEG := "res://europe/vegetation.json"

static var _house_info: Array = []
static var _scales := {}          ## o'simlik turi -> [min, max] masshtab (asl xaritadan)


## Rejani tuzadi: {zones, entry, enemy_entry, roads: [[Vector2...]], houses: [...], coast: float|null}
static func plan(b: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var j := func(v: Vector2, r: float) -> Vector2: return v + Vector2(rng.randf_range(-r, r), rng.randf_range(-r, r))
	var L := {"entry": [Vector2(-200, 150), Vector2(-150, 205)], "enemy_entry": [Vector2(225, -235), Vector2(150, -258)]}
	var city: bool = b.get("grid", false)
	var a: Vector2 = j.call(Vector2(-60, -60), 22.0)
	var bb: Vector2 = j.call(Vector2(20, -130), 18.0) if not city else Vector2(10, -60)
	var c: Vector2 = j.call(Vector2(195, -140), 20.0)
	L.zones = [{"name": "A", "pos": a, "r": 30.0}, {"name": "B", "pos": bb, "r": 55.0 if not city else 75.0},
		{"name": "C", "pos": c, "r": 35.0}]
	L.coast = -232.0 if b.get("water", false) else null
	# yo'llar: bizning kirishdan A -> B -> C -> dushman kirishi, ikkinchi kirishlardan B ga
	L.roads = [_curvy([L.entry[0], a, bb, c, L.enemy_entry[0]], rng), _curvy([L.entry[1], bb], rng), _curvy([L.enemy_entry[1], bb], rng)]
	if city:
		var R: float = b.town_r
		for k in range(-2, 3):
			L.roads.append([bb + Vector2(-R, k * 62.0), bb + Vector2(R, k * 62.0)])
			L.roads.append([bb + Vector2(k * 62.0, -R), bb + Vector2(k * 62.0, R)])
	L.houses = _houses(b, rng, L)
	return L


## Yo'l: nuqtalar orasiga biroz egrilik qo'shiladi.
static func _curvy(pts: Array, rng: RandomNumberGenerator) -> Array:
	var out := [pts[0]]
	for k in range(1, pts.size()):
		var p0: Vector2 = pts[k - 1]
		var p1: Vector2 = pts[k]
		var n := (p1 - p0).orthogonal().normalized()
		out.append((p0 + p1) * 0.5 + n * rng.randf_range(-18.0, 18.0))
		out.append(p1)
	return out


static func road_dist(L: Dictionary, p: Vector2) -> float:
	var best := 1e9
	for r in L.roads:
		for k in range(1, r.size()):
			best = minf(best, Geometry2D.get_closest_point_to_segment(p, r[k - 1], r[k]).distance_to(p))
	return best


static func _info() -> Array:
	if _house_info.is_empty():
		_house_info = JSON.parse_string(FileAccess.get_file_as_string(HOUSES)) if FileAccess.file_exists(HOUSES) else []
	return _house_info


## Uylar: B atrofida yo'l bo'ylab (yo'lga qarab), C da 2 ta (ferma), A da 1 ta. Shahar - ko'cha to'ri bloklarida.
static func _houses(b: Dictionary, rng: RandomNumberGenerator, L: Dictionary) -> Array:
	var types := _info()
	var out: Array = []
	if types.is_empty():
		return out
	var want: int = int(b.get("houses", 10))
	var center: Vector2 = L.zones[1].pos
	var R: float = float(b.get("town_r", 60))
	var tries := 0
	var spots: Array = []
	for z in [[L.zones[2].pos, 30.0, 2], [L.zones[0].pos, 26.0, 1]]:
		for k in z[2]:
			spots.append([(z[0] as Vector2) + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(12.0, z[1]), true])
	while out.size() < want + spots.size() and tries < 4000:
		tries += 1
		var p: Vector2
		var forced := false
		if not spots.is_empty():
			var s: Array = spots.pop_back()
			p = s[0]
			forced = true
		else:
			p = center + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * R
		var rd := road_dist(L, p)
		if rd < 9.0 or (not forced and rd > 34.0):
			continue
		if L.coast != null and p.x < float(L.coast) + 40.0:
			continue
		if absf(p.x) > HALF - 30.0 or absf(p.y) > HALF - 30.0:
			continue
		var ok := true
		for h in out:
			if Vector2(h.place.x, h.place.z).distance_to(p) < 19.0:
				ok = false
				break
		if not ok:
			continue
		var info: Dictionary = (types[rng.randi() % types.size()] as Dictionary).duplicate(true)
		info.place = {"x": p.x, "z": p.y, "rot": _face_road(L, p) + (PI if rng.randf() < 0.5 else 0.0)}
		out.append(info)
	return out


## Uy yo'lga qaragan bo'lsin: eng yaqin yo'l bo'lagining yo'nalishi.
static func _face_road(L: Dictionary, p: Vector2) -> float:
	var best := 1e9
	var dir := Vector2.RIGHT
	for r in L.roads:
		for k in range(1, r.size()):
			var q := Geometry2D.get_closest_point_to_segment(p, r[k - 1], r[k])
			if q.distance_to(p) < best:
				best = q.distance_to(p)
				dir = (r[k] as Vector2) - (r[k - 1] as Vector2)
	return -dir.angle()


static func _scale_range(type: String) -> Vector2:
	if _scales.is_empty() and FileAccess.file_exists(VEG):
		var v: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(VEG))
		for cat in v:
			for t in v[cat]:
				var lo := 1e9
				var hi := 0.0
				for e in v[cat][t]:
					lo = minf(lo, float(e[4]))
					hi = maxf(hi, float(e[4]))
				_scales[t] = Vector2(lo, hi)
	return _scales.get(type, Vector2(0.8, 1.2))


## O'simliklar (vegetation.json formati): {cat: {type: [[x, 0, z, rot, scale], ...]}}.
## Daraxtlar o'rmon dog'larida to'planadi; yo'l, uy, zona markazi, kirish va suvdan uzoqda.
static func vegetation(b: Dictionary, rng: RandomNumberGenerator, L: Dictionary, slope: Callable) -> Dictionary:
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.012
	var out := {}
	for cat in [["trees", "tree_types", 9.0, 0.15], ["bushes", "bush_types", 4.0, -0.1], ["rocks", "rock_types", 4.0, -1.0],
			["debris", "debris_types", 5.0, -0.3]]:
		var types: Array = b.get(cat[1], [])
		var n: int = int(b.get(cat[0], 0))
		if types.is_empty() or n <= 0:
			continue
		var d := {}
		var placed := 0
		var tries := 0
		while placed < n and tries < n * 6:
			tries += 1
			var p := Vector2(rng.randf_range(-HALF + 4, HALF - 4), rng.randf_range(-HALF + 4, HALF - 4))
			if noise.get_noise_2dv(p) < float(cat[3]):
				continue
			if not _free(L, p, float(cat[2])) or slope.call(p) > 0.75:
				continue
			var t: String = types[rng.randi() % types.size()]
			var sr := _scale_range(t)
			d.get_or_add(t, []).append([p.x, 0.0, p.y, rng.randf() * TAU, rng.randf_range(sr.x, sr.y)])
			placed += 1
		out[cat[0]] = d
	return out


static func _free(L: Dictionary, p: Vector2, road_clear: float) -> bool:
	if L.coast != null and p.x < float(L.coast) + 8.0:
		return false
	if road_dist(L, p) < road_clear:
		return false
	for h in L.houses:
		if Vector2(h.place.x, h.place.z).distance_to(p) < 11.0:
			return false
	for z in L.zones:
		if (z.pos as Vector2).distance_to(p) < float(z.r) * 0.45:
			return false
	for e in L.entry + L.enemy_entry:
		if (e as Vector2).distance_to(p) < 28.0:
			return false
	return true
