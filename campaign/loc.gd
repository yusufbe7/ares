## O'yin tili. Matnlar kodda emas, res://data/lang/<kod>.json fayllarida:
##   "ui"        - tugmalar, xabarlar ("%s", "%d" o'rniga qiymat qo'yiladi)
##   "countries" - davlat nomlari (ISO kod bo'yicha: "UZB": "Uzbekistan")
## Ishga tushganda har bir JSON Godot TranslationServer ga Translation sifatida yuklanadi, shuning uchun
## hamma joyda oddiy tr("key") ishlaydi. Davlat nomi kaliti: "country.UZB".
## Yangi til qo'shish uchun en.json dan nusxa olib tarjima qiling (masalan tr.json). U ro'yxatda o'zi chiqadi.
## Tanlangan til user://settings.cfg da saqlanadi. Standart til: ingliz.
class_name Loc
extends RefCounted

const DIR := "res://data/lang/"
const SETTINGS := "user://settings.cfg"
const DEFAULT := "en"

static var lang := ""
static var _loaded := false
static var _names := {}           ## kod -> tilning o'z nomi


## Mavjud tillar: [[kod, nomi], ...] (ingliz birinchi)
static func langs() -> Array:
	_load_all()
	var out := []
	for k in _names:
		out.append([k, _names[k]])
	out.sort_custom(func(a, b): return a[0] == DEFAULT or (b[0] != DEFAULT and a[0] < b[0]))
	return out


static func _load_all() -> void:
	if _loaded:
		return
	_loaded = true
	var d := DirAccess.open(DIR)
	if d == null:
		_names[DEFAULT] = "English"
		return
	for f in d.get_files():
		if not f.ends_with(".json"):
			continue
		var code := f.get_basename()
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + f))
		if not (j is Dictionary):
			push_warning("Til fayli buzilgan: " + f)
			continue
		var t := Translation.new()
		t.locale = code
		for k in (j.get("ui", {}) as Dictionary):
			t.add_message(k, str(j.ui[k]))
		for k in (j.get("countries", {}) as Dictionary):
			t.add_message("country." + k, str(j.countries[k]))
		TranslationServer.add_translation(t)
		_names[code] = j.get("language", code)


## Saqlangan tilni yuklaydi (birinchi marta chaqirilganda).
static func ensure() -> void:
	if lang != "":
		return
	var cfg := ConfigFile.new()
	var code := DEFAULT
	if cfg.load(SETTINGS) == OK:
		code = cfg.get_value("game", "language", DEFAULT)
	set_lang(code, false)


static func set_lang(code: String, save := true) -> void:
	_load_all()
	if not _names.has(code):
		code = DEFAULT
	lang = code
	TranslationServer.set_locale(code)
	if save:
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS)
		cfg.set_value("game", "language", code)
		cfg.save(SETTINGS)


## Matn: Loc.t("no_gold", [150]) -> "Not enough gold (150 needed)." (tr() + formatlash)
## Argument turi tarjimadagi belgiga moslanadi (%d ga matn kelsa ham, %s ga son kelsa ham xato bermaydi),
## ortiqcha argumentlar tashlanadi, yetmagani bo'sh qoladi.
static func t(key: String, args: Array = []) -> String:
	ensure()
	var s := String(TranslationServer.translate(key))
	if args.is_empty() or not s.contains("%"):
		return s
	var out := ""
	var i := 0
	var k := 0
	while i < s.length():
		var ch := s[i]
		if ch != "%" or i + 1 >= s.length():
			out += ch
			i += 1
			continue
		var f := s[i + 1]
		i += 2
		if f == "%":
			out += "%"
			continue
		var v: Variant = args[k] if k < args.size() else ""
		k += 1
		match f:
			"d", "i":
				out += str(int(v) if (v is int or v is float or (v is String and v.is_valid_float())) else 0)
			"f":
				out += str(float(v) if (v is int or v is float) else 0.0)
			_:
				out += str(v)
	return out


## Davlat nomi joriy tilda (topilmasa countries.json dagi nom).
static func country(c: CountryData) -> String:
	if c == null:
		return "?"
	ensure()
	var k := "country." + c.code
	var s := String(TranslationServer.translate(k))
	return c.name if s == k else s


static func resource(r: String) -> String:
	var k := "res." + r
	var s := t(k)
	return r if s == k else s
