## Xarita ma'lumotlarini yuklaydi: rasmlar (res://map) va JSON (res://data) -> Resource lar.
## Hech narsa kodga yozilmagan: hudud / davlat / qo'shin qo'shish uchun JSON ni o'zgartirish kifoya.
## Katta rasmlar (dunyo, 4320x1704) piksel-piksel tsiklda o'qilmaydi: bayt massivi saqlanadi va
## kerakli piksel kerak bo'lganda o'qiladi (tez yuklanadi).
## Fayl yo'q yoki buzilgan bo'lsa o'yin qulamaydi: push_warning va bo'sh qiymat.
class_name CampaignData
extends RefCounted

const MAP_DIR := "res://map/"
const DATA_DIR := "res://data/"

var width := 0
var extra_allies := {}                      ## "a:b" -> true: o'yin davomida tuzilgan ittifoqlar
var height := 0
var meta := {}
var rules := {}
var provinces := {}                        ## id -> ProvinceData
var countries := {}                        ## id -> CountryData
var by_code := {}                          ## "UZB" -> id
var armies: Array = []                     ## ArmyData
var bases: Array = []                      ## [{province, type}]
var blocs: Array = []                      ## [{id, name, color, members}]
var others := {}
var factions := {}
var ranks: Array = []
var id_image: Image
var _ids := PackedByteArray()              ## province_ids.png RGB8 baytlari
var _hs := PackedByteArray()               ## height.png RGB8 baytlari


func load_all() -> void:
	meta = _json(DATA_DIR + "map_meta.json", {})
	rules = _json(DATA_DIR + "rules.json", {})
	_read_images()
	_read_provinces()
	_read_countries()
	_read_armies()
	for e in _json(DATA_DIR + "bases.json", []):
		if e is Dictionary and provinces.has(int(e.get("province", 0))):
			bases.append({"province": int(e.province), "type": str(e.get("type", "army"))})
	var bj: Dictionary = _json(DATA_DIR + "blocs.json", {})
	blocs = bj.get("blocs", [])
	others = bj.get("others", {"id": "others", "name": "OTHERS", "color": "#8a8f98"})
	for b in blocs:
		for code in b.get("members", []):
			if by_code.has(code):
				countries[by_code[code]].bloc = b.id
	factions = _json(DATA_DIR + "factions.json", {})
	ranks = _json(DATA_DIR + "ranks.json", [])
	recount()


func rule(key: String, def: Variant) -> Variant:
	return rules.get(key, def)


static func _json(path: String, def: Variant) -> Variant:
	if not FileAccess.file_exists(path):
		push_warning("Topilmadi: " + path)
		return def
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if j == null or typeof(j) != typeof(def):
		push_warning("Buzilgan JSON: " + path)
		return def
	return j


static func _image(path: String) -> Image:
	if not ResourceLoader.exists(path):
		push_warning("Rasm topilmadi: " + path)
		return null
	# rasm "lossless", mipmapsiz import qilingan (.import faylida); siqilgan bo'lsa ham ochib olamiz
	var img: Image = (load(path) as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGB8)
	return img


func _read_images() -> void:
	id_image = _image(MAP_DIR + "province_ids.png")
	var hi := _image(MAP_DIR + "height.png")
	if id_image == null:
		id_image = Image.create(2, 2, false, Image.FORMAT_RGB8)
	width = id_image.get_width()
	height = id_image.get_height()
	_ids = id_image.get_data()
	if hi and hi.get_width() == width and hi.get_height() == height:
		_hs = hi.get_data()


## province_ids.png: id = R + G * 256.
func id_at(px: Vector2i) -> int:
	if px.x < 0 or px.y < 0 or px.x >= width or px.y >= height:
		return 0
	var k := (px.y * width + px.x) * 3
	return _ids[k] + _ids[k + 1] * 256


## height.png: metr = (R * 256 + G) / 2 - 12000   (8-bit rasmda 16-bit aniqlik)
func height_at(px: Vector2i) -> float:
	if _hs.is_empty():
		return 0.0
	px = px.clamp(Vector2i.ZERO, Vector2i(width - 1, height - 1))
	var k := (px.y * width + px.x) * 3
	return (_hs[k] * 256 + _hs[k + 1]) * 0.5 - 12000.0


func _read_provinces() -> void:
	var nb: Dictionary = _json(DATA_DIR + "neighbors.json", {})
	for e in _json(DATA_DIR + "provinces.json", []):
		if not (e is Dictionary) or not e.has("id"):
			continue
		var p := ProvinceData.new()
		p.id = int(e.id)
		p.name = str(e.get("name", "Province %d" % p.id))
		p.owner = int(e.get("owner", 0))
		p.population = int(e.get("population", 0))
		p.gdp_musd = float(e.get("gdp_musd", 0))
		p.resource = str(e.get("resource", ""))
		p.resource_amount = int(e.get("resource_amount", 1))
		p.coastal = bool(e.get("coastal", false))
		p.area_km2 = int(e.get("area_km2", 0))
		p.elevation_m = int(e.get("elevation_m", 0))
		p.pixels = int(e.get("pixels", 0))
		var c: Variant = e.get("center_px", null)
		if c is Array and c.size() == 2:
			p.center_px = Vector2i(int(c[0]), int(c[1]))
		var n: Variant = nb.get(str(p.id), [])
		if n is Array:                               # eski shakl: faqat quruqlik ro'yxati
			p.neighbors = PackedInt32Array(n)
		elif n is Dictionary:
			p.neighbors = PackedInt32Array(n.get("land", []))
			for s in n.get("sea", []):
				p.sea[int(s[0])] = int(s[1])
		provinces[p.id] = p
	# JSON siz (rasmga yangi chizilgan) hududlar: map_meta da soni ko'p bo'lsa, rasmni qo'pol ko'rib chiqamiz
	if int(meta.get("province_count", provinces.size())) > provinces.size() or provinces.is_empty():
		_scan_new()


## Rasmdagi, lekin provinces.json da yo'q hududlarni topadi (3 pikselda bir tekshiradi).
func _scan_new() -> void:
	var found := {}
	for y in range(0, height, 3):
		for x in range(0, width, 3):
			var i := id_at(Vector2i(x, y))
			if i > 0 and not provinces.has(i):
				if not found.has(i):
					found[i] = [0, 0, 0]
				found[i][0] += x; found[i][1] += y; found[i][2] += 1
	for i in found:
		var p := ProvinceData.new()
		p.id = i
		p.name = "Province %d" % i
		var f: Array = found[i]
		p.center_px = Vector2i(f[0] / f[2], f[1] / f[2])
		p.pixels = f[2] * 9
		provinces[i] = p


func _read_countries() -> void:
	for e in _json(DATA_DIR + "countries.json", []):
		if not (e is Dictionary) or not e.has("id"):
			continue
		var c := CountryData.new()
		c.id = int(e.id)
		c.code = str(e.get("code", ""))
		c.iso2 = str(e.get("iso2", c.code.substr(0, 2)))
		c.name = str(e.get("name", c.code))
		c.color = Color.html(e.get("color", "#888888")) if Color.html_is_valid(e.get("color", "")) else Color.GRAY
		c.controller = str(e.get("controller", "bot"))
		c.capital = int(e.get("capital", 0))
		c.population = int(e.get("population", 0))
		c.gdp_musd = int(e.get("gdp_musd", 0))
		c.resources = (e.get("resources", {}) as Dictionary).duplicate()
		countries[c.id] = c
		by_code[c.code] = c.id


func _read_armies() -> void:
	var n := 0
	for e in _json(DATA_DIR + "armies.json", []):
		if not (e is Dictionary) or not provinces.has(int(e.get("province", 0))):
			continue
		var a := ArmyData.new()
		n += 1
		a.id = n
		a.owner = int(e.get("owner", 0))
		a.province = int(e.province)
		a.size = int(e.get("size", 1))
		armies.append(a)


func recount() -> void:
	for c in countries.values():
		(c as CountryData).province_count = 0
	for p in provinces.values():
		var c: CountryData = countries.get((p as ProvinceData).owner)
		if c:
			c.province_count += 1


func bloc_of(cid: int) -> String:
	var c: CountryData = countries.get(cid)
	return c.bloc if c else ""


## Ittifoqchi: o'zi, bir blokdagi davlat yoki o'yin davomida tuzilgan ittifoq (extra_allies).
func allied(a: int, b: int) -> bool:
	if a == b or extra_allies.has(CampaignDiplomacy._key(a, b)):
		return true
	var ba := bloc_of(a)
	return ba != "" and ba == bloc_of(b)
