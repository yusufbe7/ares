## Ko'rsatkich chizig'i: nom, chiziq (0..100), qiymat. preview() bilan oldin/keyin farqi ko'rsatiladi
## (yashil oshsa, qizil kamaysa).
class_name StatBar
extends HBoxContainer

var _name: Label
var _bar: Control
var _val: Label
var value := 0.0
var preview_value := -1.0


static func make(title: String, v: float) -> StatBar:
	var s := StatBar.new()
	s.setup(title, v)
	return s


func setup(title: String, v: float) -> void:
	add_theme_constant_override("separation", 8)
	_name = UiKit.label(title.to_upper(), "StatLabel")
	_name.custom_minimum_size = Vector2(92, 0)
	add_child(_name)
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(90, 8)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.draw.connect(_draw_bar)
	add_child(_bar)
	_val = UiKit.label("", "StatLabel")
	_val.custom_minimum_size = Vector2(52, 0)
	_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_val)
	set_value(v)


func set_value(v: float) -> void:
	value = v
	preview_value = -1.0
	_refresh()


func preview(v: float) -> void:
	preview_value = v
	_refresh()


func _refresh() -> void:
	if preview_value >= 0.0 and int(preview_value) != int(value):
		var d := int(preview_value - value)
		_val.text = "%d %s%d" % [int(value), "+" if d > 0 else "", d]
		_val.add_theme_color_override("font_color", UiKit.GREEN if d > 0 else UiKit.RED)
	else:
		_val.text = str(int(value))
		_val.remove_theme_color_override("font_color")
	_bar.queue_redraw()


func _draw_bar() -> void:
	var r := Rect2(Vector2.ZERO, _bar.size)
	_bar.draw_rect(r, Color(0.06, 0.06, 0.07))
	var segs := 20
	var gap := 2.0
	var sw := (r.size.x - gap * (segs - 1)) / segs
	var f := clampf(value / 100.0, 0.0, 1.0)
	var pf := clampf(preview_value / 100.0, 0.0, 1.0) if preview_value >= 0.0 else f
	for k in segs:
		var t := (k + 0.5) / segs
		var col := Color(0.2, 0.21, 0.23)
		if t <= minf(f, pf): col = UiKit.AMBER
		elif t <= pf: col = UiKit.GREEN
		elif t <= f: col = UiKit.RED
		_bar.draw_rect(Rect2(k * (sw + gap), 0, sw, r.size.y), col)
