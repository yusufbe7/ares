class_name UIKit
extends RefCounted
## Small builders so every screen looks like the same game without a .tscn per
## panel. Colours live here once.

const BG := Color(0.07, 0.08, 0.10)
const PANEL := Color(0.11, 0.13, 0.16)
const PANEL_SOFT := Color(0.15, 0.17, 0.21)
const ACCENT := Color(0.44, 0.83, 0.63)
const WARN := Color(0.95, 0.73, 0.33)
const BAD := Color(0.91, 0.39, 0.36)
const TEXT := Color(0.88, 0.90, 0.92)
const MUTED := Color(0.58, 0.62, 0.67)

static func panel(color: Color = PANEL, radius: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.bg_color.a = Settings.ui_opacity
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb

static func make_panel(color: Color = PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel(color))
	return p

static func label(text: String, size: int = 16, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", int(float(size) * Settings.ui_scale))
	l.add_theme_color_override("font_color", color)
	return l

static func title(text: String) -> Label:
	var l := label(text, 30, ACCENT)
	return l

static func button(text: String, size: int = 18) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", int(float(size) * Settings.ui_scale))
	b.custom_minimum_size = Vector2(0, 42)
	var normal := panel(PANEL_SOFT, 6)
	var hover := panel(PANEL_SOFT.lightened(0.12), 6)
	var pressed := panel(ACCENT.darkened(0.55), 6)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", hover)
	return b

static func vbox(separation: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	return v

static func hbox(separation: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	return h

static func spacer(height: int = 8) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c

static func bar(value: float, max_value: float, color: Color) -> ProgressBar:
	var p := ProgressBar.new()
	p.max_value = maxf(max_value, 0.001)
	p.value = value
	p.show_percentage = false
	p.custom_minimum_size = Vector2(0, 14)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.corner_radius_top_left = 3
	fill.corner_radius_top_right = 3
	fill.corner_radius_bottom_left = 3
	fill.corner_radius_bottom_right = 3
	p.add_theme_stylebox_override("fill", fill)
	p.add_theme_stylebox_override("background", panel(Color(0.2, 0.22, 0.25), 3))
	return p

static func color_for_kind(kind: String) -> Color:
	match kind:
		"good": return ACCENT
		"warn": return WARN
		"bad": return BAD
	return TEXT

static func fullscreen(c: Control) -> Control:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	return c
