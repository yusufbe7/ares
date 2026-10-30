## Oddiy vektor ikonkalar (rasm fayllarisiz). name: campaign, globe, target, rifle, tank, soldier, base, research,
## gear, exit, mail, coins, crate, units, infantry, apc, aircraft, helicopter, truck, jeep, ship, lock, check, cross, star.
## Agar res://ui/icons/<name>.png bo'lsa, o'sha rasm chiziladi (almashtiriladigan).
class_name UiIcon
extends Control

@export var icon := "star"
@export var color := Color(0.88, 0.88, 0.86)
var _tex: Texture2D


static func make(name: String, sz := 22.0, col := Color(0.88, 0.88, 0.86)) -> UiIcon:
	var i := UiIcon.new()
	i.icon = name
	i.color = col
	i.custom_minimum_size = Vector2(sz, sz)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i


func _ready() -> void:
	var p := "res://ui/icons/%s.png" % icon
	if ResourceLoader.exists(p):
		_tex = load(p)


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	if _tex:
		draw_texture_rect(_tex, Rect2(o, Vector2(s, s)), false, color)
		return
	var c := o + Vector2(s, s) * 0.5
	var r := s * 0.42
	var w := maxf(1.5, s * 0.08)
	match icon:
		"campaign":
			draw_rect(Rect2(c - Vector2(r, r * 0.8), Vector2(r * 0.95, r * 1.6)), color, false, w)
			draw_rect(Rect2(c + Vector2(0.05 * r, -r * 0.8), Vector2(r * 0.95, r * 1.6)), color, false, w)
		"globe":
			draw_arc(c, r, 0, TAU, 32, color, w, true)
			draw_line(c - Vector2(r, 0), c + Vector2(r, 0), color, w * 0.7)
			draw_arc(c, r * 0.45, 0, TAU, 32, color, w * 0.7, true)
			draw_line(c - Vector2(0, r), c + Vector2(0, r), color, w * 0.7)
		"target":
			draw_arc(c, r * 0.75, 0, TAU, 32, color, w, true)
			for a in 4:
				var d := Vector2.RIGHT.rotated(a * PI * 0.5)
				draw_line(c + d * r * 0.35, c + d * r, color, w)
			draw_circle(c, w * 0.8, color)
		"rifle":
			draw_line(c + Vector2(-r, r * 0.1), c + Vector2(r, -r * 0.1), color, w * 1.6)
			draw_line(c + Vector2(-r * 0.2, 0), c + Vector2(-r * 0.35, r * 0.6), color, w * 1.4)
			draw_line(c + Vector2(-r, r * 0.1), c + Vector2(-r * 1.0, r * 0.45), color, w * 1.6)
		"tank":
			draw_rect(Rect2(c + Vector2(-r, 0), Vector2(r * 2, r * 0.55)), color, false, w)
			draw_rect(Rect2(c + Vector2(-r * 0.45, -r * 0.4), Vector2(r * 0.9, r * 0.4)), color)
			draw_line(c + Vector2(r * 0.4, -r * 0.22), c + Vector2(r * 1.1, -r * 0.22), color, w)
		"soldier", "infantry":
			draw_arc(c + Vector2(0, -r * 0.1), r * 0.55, PI, TAU, 16, color, w * 1.4, true)
			draw_line(c + Vector2(-r * 0.75, -r * 0.1), c + Vector2(r * 0.75, -r * 0.1), color, w)
			draw_rect(Rect2(c + Vector2(-r * 0.4, r * 0.15), Vector2(r * 0.8, r * 0.7)), color)
		"base":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r, -r * 0.1), c + Vector2(0, -r * 0.8), c + Vector2(r, -r * 0.1)]), color)
			for k in 3:
				draw_rect(Rect2(c + Vector2(-r * 0.75 + k * r * 0.6, 0), Vector2(r * 0.3, r * 0.8)), color)
		"research":
			draw_line(c + Vector2(-r * 0.25, -r), c + Vector2(-r * 0.25, -r * 0.1), color, w)
			draw_line(c + Vector2(r * 0.25, -r), c + Vector2(r * 0.25, -r * 0.1), color, w)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.25, -r * 0.1), c + Vector2(r * 0.25, -r * 0.1), c + Vector2(r * 0.8, r * 0.85), c + Vector2(-r * 0.8, r * 0.85)]), color)
		"gear":
			for a in 8:
				var d := Vector2.RIGHT.rotated(a * PI / 4)
				draw_line(c + d * r * 0.55, c + d * r, color, w * 1.8)
			draw_arc(c, r * 0.55, 0, TAU, 24, color, w * 1.6, true)
		"exit":
			draw_rect(Rect2(c + Vector2(-r * 0.8, -r), Vector2(r * 1.0, r * 2)), color, false, w)
			draw_line(c, c + Vector2(r, 0), color, w)
			draw_line(c + Vector2(r * 0.6, -r * 0.35), c + Vector2(r, 0), color, w)
			draw_line(c + Vector2(r * 0.6, r * 0.35), c + Vector2(r, 0), color, w)
		"mail":
			draw_rect(Rect2(c - Vector2(r, r * 0.65), Vector2(r * 2, r * 1.3)), color, false, w)
			draw_polyline(PackedVector2Array([c - Vector2(r, r * 0.65), c + Vector2(0, r * 0.1), c + Vector2(r, -r * 0.65)]), color, w)
		"coins":
			for k in 3:
				draw_arc(c + Vector2(0, r * 0.45 - k * r * 0.4), r * 0.75, 0, PI, 16, color, w * 1.3, true)
			draw_arc(c + Vector2(0, -r * 0.35), r * 0.75, PI, TAU, 16, color, w * 1.3, true)
		"crate":
			draw_rect(Rect2(c - Vector2(r, r * 0.8), Vector2(r * 2, r * 1.6)), color, false, w)
			draw_line(c - Vector2(r, r * 0.8), c + Vector2(r, r * 0.8), color, w * 0.8)
			draw_line(c + Vector2(-r, r * 0.8), c + Vector2(r, -r * 0.8), color, w * 0.8)
		"units":
			draw_circle(c + Vector2(-r * 0.4, -r * 0.35), r * 0.3, color)
			draw_circle(c + Vector2(r * 0.4, -r * 0.35), r * 0.3, color)
			draw_rect(Rect2(c + Vector2(-r, r * 0.05), Vector2(r * 2, r * 0.7)), color)
		"apc", "truck", "jeep":
			draw_rect(Rect2(c + Vector2(-r, -r * 0.35), Vector2(r * 2, r * 0.8)), color, false, w)
			draw_circle(c + Vector2(-r * 0.55, r * 0.55), r * 0.22, color)
			draw_circle(c + Vector2(r * 0.55, r * 0.55), r * 0.22, color)
		"aircraft":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.15, r), c + Vector2(-r * 0.15, r)]), color)
			draw_line(c + Vector2(-r, r * 0.1), c + Vector2(r, r * 0.1), color, w * 1.4)
			draw_line(c + Vector2(-r * 0.4, r * 0.8), c + Vector2(r * 0.4, r * 0.8), color, w)
		"helicopter":
			draw_line(c + Vector2(-r, -r * 0.6), c + Vector2(r, -r * 0.6), color, w)
			draw_circle(c + Vector2(-r * 0.2, 0), r * 0.42, color)
			draw_line(c + Vector2(0, 0), c + Vector2(r, -r * 0.1), color, w * 1.2)
		"ship":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r, r * 0.05), c + Vector2(r, r * 0.05), c + Vector2(r * 0.65, r * 0.6), c + Vector2(-r * 0.75, r * 0.6)]), color)
			draw_rect(Rect2(c + Vector2(-r * 0.35, -r * 0.4), Vector2(r * 0.7, r * 0.42)), color)
			draw_line(c + Vector2(0, -r * 0.4), c + Vector2(0, -r * 0.95), color, w)
		"cross":
			draw_line(c + Vector2(-r * 0.6, -r * 0.6), c + Vector2(r * 0.6, r * 0.6), color, w * 1.4)
			draw_line(c + Vector2(r * 0.6, -r * 0.6), c + Vector2(-r * 0.6, r * 0.6), color, w * 1.4)
		"lock":
			draw_rect(Rect2(c + Vector2(-r * 0.6, -r * 0.1), Vector2(r * 1.2, r)), color)
			draw_arc(c + Vector2(0, -r * 0.1), r * 0.42, PI, TAU, 12, color, w, true)
		"check":
			draw_polyline(PackedVector2Array([c + Vector2(-r * 0.7, 0), c + Vector2(-r * 0.15, r * 0.55), c + Vector2(r * 0.75, -r * 0.6)]), color, w * 1.4)
		_:
			var pts := PackedVector2Array()
			for k in 10:
				pts.append(c + Vector2.UP.rotated(k * PI / 5) * (r if k % 2 == 0 else r * 0.45))
			draw_colored_polygon(pts, color)
