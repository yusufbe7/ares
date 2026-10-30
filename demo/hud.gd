## Command panel (right side): supply counter, sector radar (minimap), build / train / support tabs.
## The game mode feeds it:  mode.hud_item_state(key) -> {ok: bool, reason: String, progress: float}
##                          mode.hud_click(key)
class_name RtsHud
extends CanvasLayer

const ORANGE := Color(0.95, 0.58, 0.18)
const PANEL := Color(0.11, 0.095, 0.08, 0.95)
const DIM := Color(0.62, 0.56, 0.48)

var demo: Node3D
var mode: Object
var tabs: Dictionary = {}           # tab name -> [keys]
var current_tab := ""
var title := "COMMAND"
var subtitle := "GROUND FORCES"

var _supply: Label
var _income: Label
var _grid: GridContainer
var _tab_buttons := {}
var _tiles := {}                    # key -> {btn, name, cost, lock, bar}
var _banner: Label
var _men: Label
var _sel: Label
var _feed: VBoxContainer
var _big: Label
var _radar: Radar
var _hint: Label
var _side: PanelContainer


class Radar extends Control:
	var demo: Node3D
	var tex: Texture2D
	var map_size := 2048.0
	var marks: Array = []          # [world pos, color, size]
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		tex = demo.map.minimap_texture() if demo and "map" in demo and demo.map else load("res://europe/minimap.jpg")
		map_size = 600.0
	func w2m(p: Vector3) -> Vector2:
		return Vector2((p.x + map_size * 0.5) / map_size * size.x, (p.z + map_size * 0.5) / map_size * size.y)
	func _draw() -> void:
		if tex:
			draw_texture_rect(tex, Rect2(Vector2.ZERO, size), false, Color(0.85, 0.85, 0.85))
		for m in marks:
			var c: Vector2 = w2m(m[0])
			draw_rect(Rect2(c - Vector2.ONE * m[2] * 0.5, Vector2.ONE * m[2]), m[1])
		if demo and demo.cam:
			var c := w2m(demo.cam.position)
			var r: float = demo.cam.distance / map_size * size.x * 1.4
			draw_rect(Rect2(c - Vector2(r, r * 0.7), Vector2(r * 2, r * 1.4)), Color(1, 1, 1, 0.8), false, 1.0)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.95, 0.58, 0.18, 0.7), false, 1.5)
	func _gui_input(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventMouseMotion and e.button_mask & MOUSE_BUTTON_MASK_LEFT):
			var p: Vector2 = e.position / size * map_size - Vector2.ONE * map_size * 0.5
			demo.cam.position = Vector3(p.x, demo.ground_height(p.x, p.y), p.y)
			accept_event()


func setup(p_demo: Node3D, p_mode: Object, p_tabs: Dictionary) -> void:
	demo = p_demo
	mode = p_mode
	tabs = p_tabs
	layer = 2
	_build()
	if not tabs.is_empty():
		show_tab(tabs.keys()[0])


static func _sb(bg: Color, border := Color(0, 0, 0, 0), w := 0, radius := 3) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 6; s.content_margin_right = 6; s.content_margin_top = 4; s.content_margin_bottom = 4
	return s


func _label(text: String, size := 14, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _build() -> void:
	# ---------------- right panel
	_side = PanelContainer.new()
	_side.add_theme_stylebox_override("panel", _sb(PANEL, Color(0.3, 0.22, 0.14), 1, 4))
	_side.anchor_left = 1.0; _side.anchor_right = 1.0; _side.anchor_top = 0.0; _side.anchor_bottom = 1.0
	_side.offset_left = -300; _side.offset_right = -8; _side.offset_top = 8; _side.offset_bottom = -8
	add_child(_side)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_side.add_child(v)
	# header: operation name + supply digits
	var head := HBoxContainer.new()
	v.add_child(head)
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_theme_constant_override("separation", -2)
	head.add_child(hv)
	hv.add_child(_label("OPERATIONS / 01", 11, DIM))
	hv.add_child(_label(title, 24, Color(0.95, 0.92, 0.85)))
	hv.add_child(_label(subtitle, 10, DIM))
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 0)
	head.add_child(sv)
	sv.add_child(_label("SUPPLY", 11, DIM))
	_supply = _label("00000", 26, Color(0.95, 0.92, 0.85))
	var sp := PanelContainer.new()
	sp.add_theme_stylebox_override("panel", _sb(Color(0.05, 0.045, 0.04), Color(0.35, 0.3, 0.25), 1))
	sp.add_child(_supply)
	sv.add_child(sp)
	_income = _label("+0.0 / s", 11, Color(0.6, 0.85, 0.5))
	_income.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sv.add_child(_income)
	# radar
	v.add_child(_label("SECTOR RADAR", 11, DIM))
	_radar = Radar.new()
	_radar.demo = demo
	_radar.custom_minimum_size = Vector2(284, 284)
	v.add_child(_radar)
	# tabs
	var tb := HBoxContainer.new()
	tb.add_theme_constant_override("separation", 3)
	v.add_child(tb)
	for t in tabs:
		var b := Button.new()
		b.text = t
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 12)
		b.add_theme_stylebox_override("normal", _sb(Color(0.18, 0.15, 0.12), Color(0.35, 0.28, 0.2), 1))
		b.add_theme_stylebox_override("pressed", _sb(Color(0.55, 0.3, 0.1), ORANGE, 1))
		b.add_theme_stylebox_override("hover", _sb(Color(0.26, 0.2, 0.14), ORANGE, 1))
		b.pressed.connect(show_tab.bind(t))
		tb.add_child(b)
		_tab_buttons[t] = b
	# item grid
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	sc.add_child(_grid)
	# ---------------- top banner (towns / waves)
	_banner = _label("", 15, Color(0.95, 0.9, 0.8))
	var bp := PanelContainer.new()
	bp.add_theme_stylebox_override("panel", _sb(Color(0.08, 0.07, 0.06, 0.85), Color(0.35, 0.28, 0.2), 1))
	bp.anchor_left = 0.5; bp.anchor_right = 0.5
	bp.offset_left = -260; bp.offset_right = 110; bp.offset_top = 6; bp.offset_bottom = 34
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bp.add_child(_banner)
	bp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bp)
	# ---------------- bottom left: men + selection + hints
	var bl := VBoxContainer.new()
	bl.anchor_top = 1.0; bl.anchor_bottom = 1.0
	bl.offset_left = 12; bl.offset_top = -88; bl.offset_bottom = -8; bl.offset_right = 900
	bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bl)
	_sel = _label("", 13, Color(0.6, 1.0, 0.65))
	_men = _label("MEN 0", 16, Color(0.95, 0.92, 0.85))
	_hint = _label("Drag LMB: select   RMB: move / attack / help build   Ctrl+1-9: group   G grenade  R RPG  Z/X/C stance  H halt  N winter  Esc menu", 11, DIM)
	for l in [_sel, _men, _hint]:
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 4)
		bl.add_child(l)
	# ---------------- feed (top left) + big message
	_feed = VBoxContainer.new()
	_feed.offset_left = 12; _feed.offset_top = 46; _feed.offset_right = 600
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_feed)
	_big = _label("", 44, Color(1, 0.92, 0.75))
	_big.set_anchors_preset(Control.PRESET_CENTER)
	_big.offset_left = -500; _big.offset_right = 200; _big.offset_top = -120
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big.add_theme_color_override("font_outline_color", Color.BLACK)
	_big.add_theme_constant_override("outline_size", 10)
	add_child(_big)


func show_tab(t: String) -> void:
	current_tab = t
	for k in _tab_buttons:
		_tab_buttons[k].button_pressed = k == t
	for c in _grid.get_children():
		c.queue_free()
	_tiles.clear()
	for key in tabs[t]:
		_grid.add_child(_tile(key))
	refresh()


func _tile(key: String) -> Control:
	var d := BuildDefs.get_def(key)
	var b := Button.new()
	b.custom_minimum_size = Vector2(136, 112)
	b.focus_mode = Control.FOCUS_NONE
	b.clip_contents = true
	b.add_theme_stylebox_override("normal", _sb(Color(0.2, 0.16, 0.12), Color(0.38, 0.3, 0.2), 1))
	b.add_theme_stylebox_override("hover", _sb(Color(0.28, 0.21, 0.14), ORANGE, 2))
	b.add_theme_stylebox_override("pressed", _sb(Color(0.4, 0.25, 0.1), ORANGE, 2))
	b.add_theme_stylebox_override("disabled", _sb(Color(0.12, 0.1, 0.09), Color(0.25, 0.2, 0.16), 1))
	b.tooltip_text = "%s\n%s" % [d.get("name", key), d.get("desc", "")]
	b.pressed.connect(func(): mode.hud_click(key))
	var icon_path := "res://assets/ui/icons/%s.png" % key
	if ResourceLoader.exists(icon_path):
		var tr := TextureRect.new()
		tr.texture = load(icon_path)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.offset_bottom = -24
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(tr)
	var nm := _label(String(d.get("name", key)).to_upper(), 11, Color(0.95, 0.92, 0.85))
	nm.anchor_top = 1.0; nm.anchor_bottom = 1.0; nm.offset_top = -22; nm.offset_left = 6; nm.offset_right = 100
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(nm)
	var cost := _label(("%d/m" % d.cost) if d.get("per_meter", false) else str(d.get("cost", 0)), 12, ORANGE)
	cost.anchor_left = 1.0; cost.anchor_right = 1.0; cost.anchor_top = 1.0; cost.anchor_bottom = 1.0
	cost.offset_left = -40; cost.offset_right = -6; cost.offset_top = -22
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(cost)
	var lock := _label("", 11, ORANGE)
	lock.set_anchors_preset(Control.PRESET_FULL_RECT)
	lock.offset_bottom = -24
	lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lock.autowrap_mode = TextServer.AUTOWRAP_WORD
	lock.add_theme_color_override("font_outline_color", Color.BLACK)
	lock.add_theme_constant_override("outline_size", 5)
	lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(lock)
	var bar := ColorRect.new()
	bar.color = Color(0.4, 0.9, 0.45, 0.85)
	bar.anchor_top = 1.0; bar.anchor_bottom = 1.0; bar.offset_top = -3
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(bar)
	_tiles[key] = {"btn": b, "lock": lock, "bar": bar}
	return b


## Re-reads availability / progress for the visible tiles.
func refresh() -> void:
	for key in _tiles:
		var st: Dictionary = mode.hud_item_state(key)
		var t: Dictionary = _tiles[key]
		t.btn.disabled = not st.get("ok", true)
		t.lock.text = st.get("reason", "")
		var pr: float = st.get("progress", 0.0)
		t.bar.visible = pr > 0.0
		t.bar.offset_right = (t.btn.size.x) * pr
		t.bar.anchor_right = 0.0


func set_supply(v: float, income: float) -> void:
	_supply.text = "%05d" % int(v)
	_income.text = "+%.1f / s" % income


func set_banner(t: String) -> void:
	_banner.text = t
	_banner.get_parent().visible = t != ""


func set_men(n: int, sel_text: String) -> void:
	_men.text = "MEN %d" % n
	_sel.text = sel_text


func set_marks(m: Array) -> void:
	_radar.marks = m
	_radar.queue_redraw()


func notify(t: String, col := Color(0.95, 0.9, 0.8)) -> void:
	var l := _label(t, 14, col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	_feed.add_child(l)
	while _feed.get_child_count() > 6:
		_feed.get_child(0).free()
	var tm := Timer.new()
	tm.wait_time = 7.0
	tm.one_shot = true
	tm.autostart = true
	tm.timeout.connect(l.queue_free)
	l.add_child(tm)


func big(t: String) -> void:
	_big.text = t
