class_name HudIcon
extends Control
## Tiny vector glyphs drawn in code for the HUD pills, so the interface needs
## no image files at all. Each one is a handful of primitives.

enum Kind { MEN, PLANE, NUKE }

var kind: int = Kind.MEN
var color: Color = Color(0.88, 0.90, 0.92)

static func make(icon_kind: int, icon_color: Color, size: float = 16.0) -> HudIcon:
	var i := HudIcon.new()
	i.kind = icon_kind
	i.color = icon_color
	i.custom_minimum_size = Vector2(size, size)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i

func _draw() -> void:
	var s: float = minf(size.x, size.y)
	if s <= 0.0:
		s = float(custom_minimum_size.x)
	match kind:
		Kind.MEN:
			_draw_men(s)
		Kind.PLANE:
			_draw_plane(s)
		Kind.NUKE:
			_draw_nuke(s)

## Two overlapping figures: a head and a rounded torso each.
func _draw_men(s: float) -> void:
	for offset in [Vector2(s * 0.30, 0.0), Vector2(s * 0.62, s * 0.05)]:
		var c: Color = color if offset.x > s * 0.4 else color.darkened(0.25)
		draw_circle(Vector2(offset.x, s * 0.30 + offset.y), s * 0.13, c)
		var body := PackedVector2Array([
			Vector2(offset.x - s * 0.16, s * 0.86 + offset.y),
			Vector2(offset.x - s * 0.14, s * 0.56 + offset.y),
			Vector2(offset.x + s * 0.14, s * 0.56 + offset.y),
			Vector2(offset.x + s * 0.16, s * 0.86 + offset.y),
		])
		draw_colored_polygon(body, c)

## A simple swept-wing shape pointing right.
func _draw_plane(s: float) -> void:
	var body := PackedVector2Array([
		Vector2(s * 0.95, s * 0.50),
		Vector2(s * 0.35, s * 0.62),
		Vector2(s * 0.05, s * 0.60),
		Vector2(s * 0.20, s * 0.50),
		Vector2(s * 0.05, s * 0.40),
		Vector2(s * 0.35, s * 0.38),
	])
	draw_colored_polygon(body, color)
	var wing := PackedVector2Array([
		Vector2(s * 0.52, s * 0.50),
		Vector2(s * 0.34, s * 0.12),
		Vector2(s * 0.44, s * 0.12),
		Vector2(s * 0.66, s * 0.50),
		Vector2(s * 0.44, s * 0.88),
		Vector2(s * 0.34, s * 0.88),
	])
	draw_colored_polygon(wing, color)

## A blast mark: a core with three expanding arcs.
func _draw_nuke(s: float) -> void:
	var centre := Vector2(s * 0.5, s * 0.5)
	draw_circle(centre, s * 0.16, color)
	for i in range(3):
		var ang := TAU * float(i) / 3.0 - PI * 0.5
		var tip := centre + Vector2(cos(ang), sin(ang)) * s * 0.46
		var left := centre + Vector2(cos(ang - 0.45), sin(ang - 0.45)) * s * 0.28
		var right := centre + Vector2(cos(ang + 0.45), sin(ang + 0.45)) * s * 0.28
		draw_colored_polygon(PackedVector2Array([tip, left, right]), color)
