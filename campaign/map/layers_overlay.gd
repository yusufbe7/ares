## Xarita ustidagi qatlamlar (ekranda 2D chiziladi), har biri MAP OPTIONS katakchasi bilan yoqiladi:
##  - supply:    o'yinchi qo'shinlarining ta'minot yo'llari (punktir). Quruqlikda yuk mashinasi, dengizda kema
##               harakatlanadi. Yo'l uzilgan bo'lsa qizil va ustida samolyot (havo orqali urinish) ko'rinadi.
##  - sea:       dengiz yo'llari (orollarga o'tish) ingichka punktir
##  - conflicts: so'nggi yurishlarda jang bo'lgan hududlarda qizil pulsatsiyalanuvchi belgi (jang log'idan)
##  - bases:     harbiy bazalar (data/bases.json)
##  - resources: hudud resursi ikonkasi (rangli doira, harf, miqdor nuqtalari)
##  - flags:     ko'rinib turgan davlat nomlari yonida bayroq (data/flags/<id>.png yoki <KOD>.png; bo'lmasa
##               davlat rangidagi kvadrat va ikki harfli kod)
##  - target:    tanlangan missiya hududi
class_name LayersOverlay
extends Control

const RED := Color(0.95, 0.22, 0.18)
const AMBER := Color(0.91, 0.64, 0.23)

var map: CampaignMap
var show := {"supply": true, "sea": true, "conflicts": true, "bases": true, "flags": true, "resources": false}
var target_province := 0
var _font: Font
var _flags := {}                ## cid -> Texture2D yoki null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func _process(_d: float) -> void:
	queue_redraw()


func _sp(province_id: int) -> Variant:
	var w := map.province_world(province_id)
	if map.cam.camera.is_position_behind(w):
		return null
	return map.cam.camera.unproject_position(w)


func flag_texture(c: CountryData) -> Texture2D:
	if not _flags.has(c.id):
		var t: Texture2D = null
		for p in ["res://data/flags/%d.png" % c.id, "res://data/flags/%s.png" % c.code]:
			if ResourceLoader.exists(p):
				t = load(p)
				break
		_flags[c.id] = t
	return _flags[c.id]


## Bayroq: rasm bo'lsa rasm, bo'lmasa rang + ikki harfli kod.
func draw_flag(c: CountryData, r: Rect2) -> void:
	var t := flag_texture(c)
	draw_rect(r.grow(1.5), Color(0, 0, 0, 0.75))
	if t:
		draw_texture_rect(t, r, false)
		return
	draw_rect(r, c.color.darkened(0.15))
	var fs := int(clampf(r.size.y * 0.55, 8, 22))
	var tw := _font.get_string_size(c.iso2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(_font, r.get_center() + Vector2(-tw * 0.5, fs * 0.36), c.iso2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))


var _blk: Array = []       ## UI panellari egallagan joylar (u yerga chizilmaydi)


## Nuqta UI paneli ostida emasmi.
func _free(p: Vector2) -> bool:
	for b in _blk:
		if b.has_point(p):
			return false
	return true


func _draw() -> void:
	if map == null:
		return
	_blk = map.blocked_rects() if map.has_method("blocked_rects") else []
	var d := map.data
	var vp := get_viewport_rect().grow(40)
	var t := Time.get_ticks_msec() / 1000.0
	var far: bool = map.cam.distance > 150.0
	if show.sea and not far:
		_draw_sea(vp)
	if map.rules.phase != "choose":
		if show.supply:
			_draw_supply(vp, t)
		if show.conflicts:
			for pid in map.rules.conflicts():
				var s: Variant = _sp(pid)
				if s != null and vp.has_point(s) and _free(s):
					var k := fmod(t * 1.4, 1.0)
					draw_arc(s, 8.0 + k * 22.0, 0, TAU, 32, Color(RED, 1.0 - k), 2.5, true)
					draw_circle(s, 5.0, RED)
					draw_line(s + Vector2(-3, -3), s + Vector2(3, 3), Color.WHITE, 1.5)
					draw_line(s + Vector2(-3, 3), s + Vector2(3, -3), Color.WHITE, 1.5)
	if show.resources and map.cam.distance < 110.0:
		_draw_resources(vp)
	if show.bases and map.cam.distance < 80.0:
		for b in d.bases:
			var s: Variant = _sp(b.province)
			if s == null or not vp.has_point(s) or not _free(s):
				continue
			var c: CountryData = d.countries.get(d.provinces[b.province].owner)
			_base_icon(s + Vector2(16, 6), b.type, c.color if c else Color.GRAY)
	if show.flags:
		for e in map.labels.shown_countries:
			var c: CountryData = d.countries.get(e[0])
			var r: Rect2 = e[1]
			if c and r.size.y > 16.0 and _free(r.get_center()):
				var h := clampf(r.size.y * 0.7, 12.0, 34.0)
				draw_flag(c, Rect2(Vector2(r.get_center().x - h * 0.75, r.position.y - h - 4.0), Vector2(h * 1.5, h)))
	if target_province > 0:
		var s: Variant = _sp(target_province)
		if s != null and _free(s):
			var k := 0.5 + 0.5 * sin(t * 3.0)
			draw_arc(s, 18.0 + k * 4.0, 0, TAU, 40, AMBER, 2.5, true)
			for a in 4:
				var dir := Vector2.RIGHT.rotated(a * PI * 0.5)
				draw_line(s + dir * 12.0, s + dir * 26.0, AMBER, 2.0)


func _draw_resources(vp: Rect2) -> void:
	for p in map.data.provinces.values():
		var s: Variant = _sp(p.id)
		if s == null or not vp.has_point(s) or not _free(s):
			continue
		var c: Color = MapTerrain.RES_COLORS.get(p.resource, Color.GRAY)
		var at: Vector2 = s + Vector2(-18, 8)
		draw_circle(at, 8.0, Color(0.05, 0.05, 0.05, 0.9))
		draw_circle(at, 6.5, c)
		var ch := Loc.resource(p.resource).substr(0, 1).to_upper()
		draw_string(_font, at + Vector2(-3.5, 4.5), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.BLACK if c.get_luminance() > 0.5 else Color.WHITE)
		for k in p.resource_amount:
			draw_circle(at + Vector2(-5 + k * 5, 11), 1.6, c)


func _draw_sea(vp: Rect2) -> void:
	var seen := {}
	for p in map.data.provinces.values():
		for o in p.sea:
			var key := mini(p.id, o) * 100000 + maxi(p.id, o)
			if seen.has(key):
				continue
			seen[key] = true
			var a: Variant = _sp(p.id)
			var b: Variant = _sp(o)
			if a == null or b == null or not (vp.has_point(a) or vp.has_point(b)) or a.distance_to(b) > 1400.0:
				continue
			_dashed(a, b, Color(0.55, 0.75, 0.95, 0.35), 1.2, 6.0, 0.0)


func _draw_supply(vp: Rect2, t: float) -> void:
	for a in map.data.armies:
		if a.owner != map.rules.player_id and a != map.selected_army:
			continue
		var r: Dictionary = map.rules.supply.routes.get(a.id, {})
		var path: Array = r.get("path", [])
		if path.size() < 2:
			continue
		var ok: bool = r.ok
		var col := Color(0.95, 0.85, 0.55, 0.85) if ok else Color(RED, 0.9)
		var pts := []
		for pid in path:
			pts.append(_sp(pid))
		for k in range(1, pts.size()):
			if pts[k - 1] == null or pts[k] == null:
				continue
			var sea: bool = r.sea[k - 1]
			_dashed(pts[k - 1], pts[k], col if not sea else Color(0.6, 0.85, 1.0, 0.9), 2.0, 7.0, t * 14.0)
			# harakatlanuvchi ikonka har segmentda
			var f := fmod(t * 0.35 + k * 0.37, 1.0)
			var at: Vector2 = pts[k - 1].lerp(pts[k], f)
			if not _free(at):
				continue
			var ang: float = (pts[k] - pts[k - 1]).angle()
			if not ok:
				_plane(at, ang, RED)
			elif sea:
				_ship(at, ang)
			else:
				_truck(at, ang)


func _dashed(a: Vector2, b: Vector2, col: Color, w: float, dash: float, offset: float) -> void:
	var L := a.distance_to(b)
	if L < 1.0:
		return
	var dir := (b - a) / L
	var s := fmod(offset, dash * 2.0) - dash * 2.0
	while s < L:
		var s0 := maxf(s, 0.0)
		var s1 := minf(s + dash, L)
		if s1 > s0 and _free(a + dir * (s0 + s1) * 0.5):
			draw_line(a + dir * s0, a + dir * s1, col, w, true)
		s += dash * 2.0


func _truck(p: Vector2, ang: float) -> void:
	draw_set_transform(p, ang, Vector2.ONE)
	draw_rect(Rect2(-7, -3.5, 9, 7), Color(0.2, 0.22, 0.18))
	draw_rect(Rect2(2, -3, 5, 6), Color(0.35, 0.38, 0.3))
	draw_rect(Rect2(-7, -3.5, 14, 7), Color(0.95, 0.85, 0.55), false, 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _ship(p: Vector2, ang: float) -> void:
	draw_set_transform(p, ang, Vector2.ONE)
	draw_colored_polygon(PackedVector2Array([Vector2(-8, -3), Vector2(6, -3), Vector2(10, 0), Vector2(6, 3), Vector2(-8, 3)]), Color(0.75, 0.85, 0.95))
	draw_rect(Rect2(-4, -2, 5, 4), Color(0.2, 0.25, 0.32))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _plane(p: Vector2, ang: float, col: Color) -> void:
	draw_set_transform(p, ang, Vector2.ONE)
	draw_colored_polygon(PackedVector2Array([Vector2(9, 0), Vector2(-6, -2), Vector2(-3, 0), Vector2(-6, 2)]), col)
	draw_line(Vector2(1, -7), Vector2(1, 7), col, 2.0)
	draw_line(Vector2(-6, -3), Vector2(-6, 3), col, 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _base_icon(p: Vector2, type: String, col: Color) -> void:
	draw_rect(Rect2(p - Vector2(7, 7), Vector2(14, 14)), Color(0.06, 0.06, 0.06, 0.9))
	draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), col.darkened(0.3))
	match type:
		"naval":
			draw_line(p + Vector2(0, -4), p + Vector2(0, 4), Color.WHITE, 1.5)
			draw_arc(p + Vector2(0, 1), 3.5, 0.2, PI - 0.2, 8, Color.WHITE, 1.5)
		"air":
			_plane(p, -PI * 0.5, Color.WHITE)
		_:
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -5), p + Vector2(4, 4), p + Vector2(-4, 4)]), Color.WHITE)
