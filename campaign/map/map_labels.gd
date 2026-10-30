## Xarita yozuvlari: davlat nomlari (yerga yotqizilgan), hudud nomlari (yaqinda), okean va dengiz nomlari.
## Davlat nomi davlat ichidagi eng keng joyga qo'yiladi (pole of inaccessibility: chamfer masofa), o'lchami
## maydon va shu joydagi kenglikka qarab. Ekranda bir-birini va panellarni yopmaydi (katta davlat birinchi).
class_name MapLabels
extends Node3D

const COUNTRY_NEAR := 30.0      ## bundan uzoqda davlat nomlari
const PROVINCE_FAR := 34.0      ## bundan yaqinda hudud nomlari
const LABEL_MIN_PX := 10.0      ## harf balandligi bundan kichik bo'lsa yashiriladi
const LG := 6                   ## joy hisoblash uchun qo'pol to'r (piksel)

var map: CampaignMap
var rects: Array = []           ## ko'rinib turgan yozuvlar (ekran to'rtburchaklari)
var shown_countries: Array = [] ## [[country id, Rect2]] (bayroq chizish uchun)
var _country := {}              ## cid -> Label3D
var _area := {}
var _prov := {}                 ## pid -> Label3D
var _prov_order: Array = []
var _oceans: Array = []
var _dirty := {}
var _lw := 0
var _lh := 0
var _cell := PackedInt32Array()
var _cells := {}                ## pid -> Array (katak indekslari)
var _box := {}                  ## pid -> Rect2i


func build(m: CampaignMap) -> void:
	map = m
	_build_grid()
	for c in map.data.countries.values():
		var l := _flat_label(64, 14, Color(1, 1, 1, 0.92))
		_country[c.id] = l
		_place(c.id)
	for p in map.data.provinces.values():
		var l := Label3D.new()
		l.text = p.name
		l.font_size = 30
		l.pixel_size = 0.00034          # fixed_size: ekranda doim ~15 px
		l.fixed_size = true
		l.outline_size = 9
		l.modulate = Color(1, 0.98, 0.92, 0.9)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.vertical_alignment = VERTICAL_ALIGNMENT_TOP    # nom nuqtadan pastda, qo'shin belgisi tepada
		l.no_depth_test = true
		l.position = map.province_world(p.id) + Vector3(0, 0.05, 0)
		l.visible = false
		l.set_meta("ts", ThemeDB.fallback_font.get_string_size(p.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 30) * l.pixel_size)
		add_child(l)
		_prov[p.id] = l
	_prov_order = _prov.keys()
	_prov_order.sort_custom(func(a, b): return map.data.provinces[a].pixels > map.data.provinces[b].pixels)
	var oj: Dictionary = CampaignData._json("res://data/oceans.json", {})
	for e in oj.get("labels", []):
		var l := _flat_label(64, 0, Color(0.55, 0.72, 0.9, 0.55))
		l.set_meta("key", str(e.key))
		l.set_meta("size", float(e.get("size", 1.0)))
		var px := Vector2((float(e.lon) + 180.0) / 360.0 * map.data.width, (84.0 - float(e.lat)) / 142.0 * map.data.height)
		l.position = map.terrain.px_to_world(px) + Vector3(0, 0.1, 0)
		_oceans.append(l)
	apply_language()


## Davlat va okean nomlari uchun shrift: Oswald (qalin tor, Theme bilan bir xil), bo'lmasa standart shrift.
static var _map_font: Font


static func map_font() -> Font:
	if _map_font == null:
		var p := "res://ui/theme/fonts/Oswald.ttf"
		_map_font = load(p) if ResourceLoader.exists(p) else ThemeDB.fallback_font
	return _map_font


func _flat_label(fs: int, outline: int, col: Color) -> Label3D:
	var l := Label3D.new()
	l.font = map_font()
	l.font_size = fs
	l.outline_size = outline
	l.modulate = col
	l.outline_modulate = Color(0.03, 0.03, 0.03, 0.7)
	l.rotation = Vector3(-PI * 0.5, 0, 0)       # yerga yotqizilgan (Total War uslubi)
	l.no_depth_test = true
	l.render_priority = 2
	l.outline_render_priority = 1
	l.visible = false
	add_child(l)
	return l


func apply_language() -> void:
	for cid in _country:
		_dirty[cid] = true
	for l in _oceans:
		l.text = Loc.t(l.get_meta("key")).to_upper()
		var ts := map_font().get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size)
		l.pixel_size = float(l.get_meta("size")) / ts.y
		l.set_meta("ts", ts * l.pixel_size)


func mark_dirty(cid: int) -> void:
	_dirty[cid] = true


func set_province_owner(province_id: int, owner: int) -> void:
	for k in _cells.get(province_id, []):
		_cell[k] = owner


func set_player_tint(player_id: int, choosing: bool) -> void:
	for cid in _country:
		_country[cid].modulate = Color(1.0, 0.82, 0.45, 0.95) if cid == player_id and not choosing else Color(1, 1, 1, 0.92)


func _build_grid() -> void:
	var d := map.data
	_lw = d.width / LG
	_lh = d.height / LG
	_cell.resize(_lw * _lh)
	for cy in _lh:
		for cx in _lw:
			var k := cy * _lw + cx
			var id := d.id_at(Vector2i(cx * LG + LG / 2, cy * LG + LG / 2))
			if id <= 0 or not d.provinces.has(id):
				_cell[k] = 0
				continue
			_cell[k] = d.provinces[id].owner
			if not _cells.has(id):
				_cells[id] = []
				_box[id] = Rect2i(cx, cy, 1, 1)
			_cells[id].append(k)
			_box[id] = (_box[id] as Rect2i).expand(Vector2i(cx, cy)).expand(Vector2i(cx + 1, cy + 1))


## Davlat nomini joylash (chamfer masofa bilan eng keng nuqta).
func _place(cid: int) -> void:
	var l: Label3D = _country.get(cid)
	var c: CountryData = map.data.countries.get(cid)
	if l == null or c == null:
		return
	l.text = Loc.country(c).to_upper()
	var box := Rect2i()
	var have := false
	var area := 0
	var cen := Vector2.ZERO
	var wsum := 0.0
	for p in map.data.provinces.values():
		if p.owner != cid or not _box.has(p.id):
			continue
		box = _box[p.id] if not have else box.merge(_box[p.id])
		have = true
		area += (_cells[p.id] as Array).size()
		cen += Vector2(p.center_px) / LG * maxf(p.pixels, 1)
		wsum += maxf(p.pixels, 1)
	_area[cid] = area
	l.set_meta("ok", have)
	if not have:
		l.visible = false
		return
	cen /= wsum
	box = box.grow(1).intersection(Rect2i(0, 0, _lw, _lh))
	var dt := LabelPlacer.distance(_cell, _lw, box, cid)
	var w := box.size.x
	var best := LabelPlacer.best(dt, box, cen)
	var bx := best % w
	var by := best / w
	var x0 := bx
	while x0 > 0 and dt[by * w + x0 - 1] > 0.0: x0 -= 1
	var x1 := bx
	while x1 < w - 1 and dt[by * w + x1 + 1] > 0.0: x1 += 1
	var cell := LG * MapTerrain.PX
	var ts := map_font().get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size)
	var hh := clampf(sqrt(float(area)) * cell * 0.17, 0.5, 8.0)
	hh = minf(hh, dt[best] * 2.0 * cell * 0.9)
	hh = minf(hh, (x1 - x0 + 1) * cell * 1.1 * ts.y / ts.x)    # chegaradan biroz chiqishi mumkin
	hh = maxf(hh, 0.45)
	l.pixel_size = hh / ts.y
	l.set_meta("ts", ts * l.pixel_size)
	var wp := map.terrain.px_to_world(Vector2((box.position.x + (x0 + x1) * 0.5 + 0.5) * LG, (box.position.y + by + 0.5) * LG))
	var gy := 0.0
	var half: float = ts.x * l.pixel_size * 0.5
	for k in 5:
		gy = maxf(gy, map.terrain.ground_y(wp.x + lerpf(-half, half, k / 4.0), wp.z))
	l.position = Vector3(wp.x, gy + 0.15, wp.z)


func _prio(cid: int) -> float:
	return (1e9 if cid == map.rules.player_id else 0.0) + float(_area.get(cid, 0))


func country_label(cid: int) -> Label3D:
	return _country.get(cid)


## Qaysi yozuv ko'rinadi: masofa darajasi, o'qiladigan o'lcham, bir-birini va panellarni yopmaslik.
func update(blocked: Array) -> void:
	for cid in _dirty:
		_place(cid)
	_dirty.clear()
	var vp := get_viewport().get_visible_rect()
	var cam: Camera3D = map.cam.camera
	rects.clear()
	shown_countries.clear()
	var dist: float = map.cam.distance
	var choosing: bool = map.rules.phase == "choose"
	var show_c := choosing or dist > COUNTRY_NEAR
	var ids: Array = _country.keys()
	ids.sort_custom(func(a, b): return _prio(a) > _prio(b))
	for cid in ids:
		var l: Label3D = _country[cid]
		var ok: bool = show_c and l.get_meta("ok", false) and map.data.countries[cid].province_count > 0
		if ok:
			var r := LabelPlacer.flat_rect(l, cam)
			ok = r.size.y >= LABEL_MIN_PX * 1.35 and vp.intersects(r) and not _hits(r, blocked)
			if ok:
				var inner := r.grow_individual(-r.size.x * 0.04, -r.size.y * 0.2, -r.size.x * 0.04, -r.size.y * 0.2)
				ok = not _hits(inner, rects)
			if ok:
				rects.append(r.grow_individual(0, -r.size.y * 0.15, 0, -r.size.y * 0.15))
				shown_countries.append([cid, r])
		l.visible = ok
	for l in _oceans:
		var r := LabelPlacer.flat_rect(l, cam)
		l.visible = r.size.y >= LABEL_MIN_PX * 1.2 and r.size.y < 160.0 and vp.intersects(r) and not _hits(r, rects) and not _hits(r, blocked)
	var show_p := not choosing and dist < PROVINCE_FAR
	for pid in _prov_order:
		var l: Label3D = _prov[pid]
		var ok := show_p and not cam.is_position_behind(l.position)
		if ok:
			var r := LabelPlacer.bill_rect(l, cam, vp.size.y)
			ok = vp.intersects(r) and not _hits(r, blocked) and not _hits(r, rects)
			if ok:
				rects.append(r)
		l.visible = ok


static func _hits(r: Rect2, list: Array) -> bool:
	for o in list:
		if r.intersects(o):
			return true
	return false
