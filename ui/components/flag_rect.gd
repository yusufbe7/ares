## Bayroq: res://data/flags/<id>.png yoki <KOD>.png; bo'lmasa davlat rangidagi kvadrat va ikki harfli kod.
class_name FlagRect
extends Control

var country: CountryData
var _tex: Texture2D


static func make(c: CountryData, sz := Vector2(36, 24)) -> FlagRect:
	var f := FlagRect.new()
	f.country = c
	f.custom_minimum_size = sz
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return f


func set_country(c: CountryData) -> void:
	country = c
	_tex = null
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r.grow(1), Color(0, 0, 0, 0.8))
	if country == null:
		draw_rect(r, Color(0.25, 0.26, 0.28))
		return
	if _tex == null:
		for p in ["res://data/flags/%d.png" % country.id, "res://data/flags/%s.png" % country.code]:
			if ResourceLoader.exists(p):
				_tex = load(p)
				break
	if _tex:
		draw_texture_rect(_tex, r, false)
		return
	draw_rect(r, country.color.darkened(0.12))
	var f := ThemeDB.fallback_font
	var fs := int(size.y * 0.55)
	var tw := f.get_string_size(country.iso2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f, r.get_center() + Vector2(-tw * 0.5, fs * 0.36), country.iso2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
