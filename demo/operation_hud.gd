## HUD of the OPERATION (styled after the dev-log footage): AI COVER SYSTEM read-out top-left,
## A / B / C points, men reserves of both sides (who is bleeding), timer, supply;
## action bar at the bottom (R squad, Y tank, U artillery, B build), radar, message feed,
## and the radial build menu (TRENCH / WIRE / CAMO NET / MINES).
class_name OperationHud
extends CanvasLayer

const BLUE := Color(0.35, 0.62, 1.0)
const RED := Color(1.0, 0.33, 0.27)
const GREY := Color(0.78, 0.78, 0.8)
const PANEL := Color(0.06, 0.065, 0.075, 0.72)
const TXT := Color(0.94, 0.95, 0.97)
const DIM := Color(0.62, 0.64, 0.68)

var mode: Node
var demo: Node3D
var _cover: Label
var _blue: Label
var _red: Label
var _time: Label
var _supply: Label
var _zone_box: HBoxContainer
var _zone_chips := {}
var _buttons := {}
var _feed: VBoxContainer
var _big: Label
var _radar
var _radial: RadialMenu
var _pause: Control


class RadialMenu extends Control:
	var items: Array = []           # [key, title, cost text, enabled]
	var center := Vector2.ZERO
	var hover := -1
	var on_pick: Callable
	const R_OUT := 130.0
	const R_IN := 48.0

	func open(at: Vector2, p_items: Array) -> void:
		items = p_items
		center = at
		visible = true
		hover = -1
		queue_redraw()

	func _sector(p: Vector2) -> int:
		var d := p - center
		if d.length() < R_IN or d.length() > R_OUT + 20.0 or items.is_empty():
			return -1
		var a := fposmod(d.angle() + PI * 0.75, TAU)
		return int(a / (TAU / items.size())) % items.size()

	func _gui_input(e: InputEvent) -> void:
		if not visible:
			return
		if e is InputEventMouseMotion:
			var h := _sector(e.position)
			if h != hover:
				hover = h
				queue_redraw()
		elif e is InputEventMouseButton and e.pressed:
			if e.button_index == MOUSE_BUTTON_LEFT and hover >= 0 and items[hover][3]:
				visible = false
				on_pick.call(items[hover][0])
			elif e.button_index == MOUSE_BUTTON_RIGHT or hover < 0:
				visible = false
			accept_event()

	func _draw() -> void:
		if items.is_empty():
			return
		var n := items.size()
		var step := TAU / n
		var font := ThemeDB.fallback_font
		for i in n:
			var a0 := -PI * 0.75 + i * step + 0.02
			var a1 := a0 + step - 0.04
			var pts := PackedVector2Array()
			for k in 17:
				var a := lerpf(a0, a1, k / 16.0)
				pts.append(center + Vector2(cos(a), sin(a)) * R_OUT)
			for k in 17:
				var a := lerpf(a1, a0, k / 16.0)
				pts.append(center + Vector2(cos(a), sin(a)) * R_IN)
			var en: bool = items[i][3]
			var col := Color(0.2, 0.45, 0.75, 0.92) if i == hover and en else Color(0.13, 0.14, 0.16, 0.9)
			if not en: col = Color(0.1, 0.1, 0.11, 0.8)
			draw_colored_polygon(pts, col)
			var mid := (a0 + a1) * 0.5
			var c := center + Vector2(cos(mid), sin(mid)) * (R_IN + R_OUT) * 0.5
			draw_string(font, c + Vector2(-60, -2), items[i][1], HORIZONTAL_ALIGNMENT_CENTER, 120, 14, Color(0.95, 0.96, 0.98) if en else Color(0.5, 0.5, 0.52))
			draw_string(font, c + Vector2(-60, 16), items[i][2], HORIZONTAL_ALIGNMENT_CENTER, 120, 12, Color(0.98, 0.78, 0.3) if en else Color(0.5, 0.45, 0.35))
		draw_circle(center, R_IN - 4.0, Color(0.1, 0.11, 0.13, 0.95))
		var t := "BUILD" if hover < 0 else String(items[hover][1])
		var sub := "" if hover < 0 else String(items[hover][2])
		draw_string(font, center + Vector2(-44, -2), t, HORIZONTAL_ALIGNMENT_CENTER, 88, 13, Color.WHITE)
		draw_string(font, center + Vector2(-44, 14), sub, HORIZONTAL_ALIGNMENT_CENTER, 88, 11, Color(0.98, 0.78, 0.3))


func setup(p_mode: Node, p_demo: Node3D) -> void:
	mode = p_mode
	demo = p_demo
	layer = 2
	_build()


static func _sb(bg: Color, border := Color(0, 0, 0, 0), w := 0, radius := 3) -> StyleBoxFlat:
	return RtsHud._sb(bg, border, w, radius)


func _label(text: String, size := 14, col := TXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 3)
	return l


func _build() -> void:
	# ---------------- top-left read-out
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _sb(PANEL, Color(0.25, 0.27, 0.3), 1))
	panel.position = Vector2(10, 10)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	panel.add_child(v)
	var head := HBoxContainer.new()
	head.add_child(_label("AI COVER SYSTEM", 13, Color(0.98, 0.78, 0.3)))
	head.add_child(_label("   OPERATION  EUROPE FRONT", 11, DIM))
	v.add_child(head)
	_cover = _label("", 12, DIM)
	v.add_child(_cover)
	_blue = _label("", 13, BLUE)
	v.add_child(_blue)
	_red = _label("", 13, RED)
	v.add_child(_red)
	_zone_box = HBoxContainer.new()
	_zone_box.add_theme_constant_override("separation", 6)
	v.add_child(_zone_box)
	var row := HBoxContainer.new()
	_time = _label("", 13, TXT)
	_supply = _label("", 13, Color(0.98, 0.78, 0.3))
	row.add_child(_time)
	row.add_child(_label("     ", 13))
	row.add_child(_supply)
	v.add_child(row)
	# ---------------- action bar
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	bar.anchor_left = 0.5; bar.anchor_right = 0.5; bar.anchor_top = 1.0; bar.anchor_bottom = 1.0
	bar.offset_left = -330; bar.offset_right = 330; bar.offset_top = -74; bar.offset_bottom = -12
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(bar)
	for b in [["squad", "R", "CALL SQUAD"], ["tank", "Y", "CALL TANK"], ["artillery", "U", "ARTILLERY"], ["build", "B", "BUILD"]]:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(150, 58)
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_stylebox_override("normal", _sb(Color(0.1, 0.11, 0.13, 0.88), Color(0.3, 0.32, 0.36), 1))
		btn.add_theme_stylebox_override("hover", _sb(Color(0.16, 0.24, 0.36, 0.95), BLUE, 2))
		btn.add_theme_stylebox_override("pressed", _sb(Color(0.2, 0.32, 0.5, 0.95), BLUE, 2))
		btn.add_theme_stylebox_override("disabled", _sb(Color(0.07, 0.07, 0.08, 0.8), Color(0.2, 0.2, 0.22), 1))
		var key: String = b[0]
		btn.pressed.connect(func(): mode.action(key))
		bar.add_child(btn)
		_buttons[key] = {"btn": btn, "title": "[%s]  %s" % [b[1], b[2]]}
		btn.text = _buttons[key].title
	# ---------------- feed + big text
	_feed = VBoxContainer.new()
	_feed.anchor_top = 1.0; _feed.anchor_bottom = 1.0
	_feed.offset_left = 12; _feed.offset_top = -260; _feed.offset_right = 620; _feed.offset_bottom = -90
	_feed.alignment = BoxContainer.ALIGNMENT_END
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_feed)
	_big = _label("", 44, Color(1, 0.95, 0.85))
	_big.set_anchors_preset(Control.PRESET_CENTER)
	_big.offset_left = -500; _big.offset_right = 500; _big.offset_top = -140
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big.add_theme_constant_override("outline_size", 10)
	add_child(_big)
	# ---------------- radar
	_radar = RtsHud.Radar.new()
	_radar.demo = demo
	_radar.anchor_left = 1.0; _radar.anchor_right = 1.0; _radar.anchor_top = 1.0; _radar.anchor_bottom = 1.0
	_radar.offset_left = -222; _radar.offset_top = -222; _radar.offset_right = -12; _radar.offset_bottom = -12
	add_child(_radar)
	# ---------------- radial menu
	_radial = RadialMenu.new()
	_radial.set_anchors_preset(Control.PRESET_FULL_RECT)
	_radial.visible = false
	_radial.mouse_filter = Control.MOUSE_FILTER_STOP
	_radial.on_pick = func(k): mode.build_pick(k)
	add_child(_radial)
	# ---------------- pause
	_pause = ColorRect.new()
	(_pause as ColorRect).color = Color(0, 0, 0, 0.45)
	_pause.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause.visible = false
	_pause.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pl := _label("PAUSED\nEsc - continue      F9 - restart the operation", 30)
	pl.set_anchors_preset(Control.PRESET_CENTER)
	pl.offset_left = -400; pl.offset_right = 400; pl.offset_top = -50
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause.add_child(pl)
	add_child(_pause)


func open_radial(items: Array) -> void:
	_radial.open(get_viewport().get_mouse_position(), items)


func radial_open() -> bool:
	return _radial.visible


func set_paused(on: bool) -> void:
	_pause.visible = on


## data: {slots, used, reserve: [b, r], field: [b, r], bleeding, zones: [{name, owner, cap}], time, supply, income, buttons: {key: [enabled, text]}}
func update(d: Dictionary) -> void:
	_cover.text = "COVER SLOTS %d   |   IN USE %d" % [d.slots, d.used]
	var bl: int = d.bleeding
	_blue.text = "BLUE  GROUND FORCES   men %d  (+%d in the field)%s" % [d.reserve[0], d.field[0], "   ▼ BLEEDING" if bl == 0 else ""]
	_red.text = "RED   INSURGENTS        men %d  (+%d in the field)%s" % [d.reserve[1], d.field[1], "   ▼ BLEEDING" if bl == 1 else ""]
	var t: float = maxf(0.0, d.time)
	_time.text = "TIME  %02d:%02d" % [int(t) / 60, int(t) % 60]
	_supply.text = "SUPPLY  %d   (+%.1f/s)" % [int(d.supply), d.income]
	for z in d.zones:
		if not _zone_chips.has(z.name):
			var chip := PanelContainer.new()
			chip.custom_minimum_size = Vector2(70, 24)
			var l := _label(z.name, 14)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			chip.add_child(l)
			_zone_box.add_child(chip)
			_zone_chips[z.name] = {"chip": chip, "label": l}
		var c: Dictionary = _zone_chips[z.name]
		var col: Color = BLUE if z.owner == 0 else (RED if z.owner == 1 else GREY)
		(c.chip as PanelContainer).add_theme_stylebox_override("panel", _sb(Color(col.r * 0.35, col.g * 0.35, col.b * 0.35, 0.9), col, 2))
		var pct := int(absf(z.cap) * 100.0)
		(c.label as Label).text = "%s %s" % [z.name, ("%d%%" % pct) if pct < 100 else ""]
	for k in d.buttons:
		if _buttons.has(k):
			var b: Button = _buttons[k].btn
			b.disabled = not d.buttons[k][0]
			b.text = "%s\n%s" % [_buttons[k].title, d.buttons[k][1]]


func set_marks(m: Array) -> void:
	_radar.marks = m
	_radar.queue_redraw()


func notify(t: String, col := Color(0.95, 0.95, 0.97)) -> void:
	var l := _label(t, 14, col)
	_feed.add_child(l)
	while _feed.get_child_count() > 7:
		_feed.get_child(0).free()
	var tm := Timer.new()
	tm.wait_time = 8.0
	tm.one_shot = true
	tm.autostart = true
	tm.timeout.connect(l.queue_free)
	l.add_child(tm)


func big(t: String) -> void:
	_big.text = t
