## UI yasash uchun kichik yordamchilar (hamma uslub main_theme.tres da, bu yerda faqat tuzilma).
class_name UiKit
extends RefCounted

const AMBER := Color("#E8A33A")
const DIM := Color(0.58, 0.6, 0.62)
const RED := Color(0.9, 0.3, 0.25)
const GREEN := Color(0.45, 0.8, 0.4)
const THEME := "res://ui/theme/main_theme.tres"


static func theme() -> Theme:
	return load(THEME) if ResourceLoader.exists(THEME) else null


static func label(text: String, variation := "", align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	l.horizontal_alignment = align
	return l


static func button(text: String, variation := "", cb: Callable = Callable()) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = variation
	b.focus_mode = Control.FOCUS_ALL
	if cb.is_valid():
		b.pressed.connect(cb)
	_hover_fx(b)
	return b


## "Tez orada" tugmasi: o'chirilgan, ishlayotgandek ko'rinmaydi.
static func soon(b: BaseButton) -> BaseButton:
	b.disabled = true
	b.tooltip_text = Loc.t("coming_soon")
	if b is Button and not (b as Button).text.is_empty():
		(b as Button).text += "  ·  " + Loc.t("coming_soon").to_upper()
	return b


static func panel(variation := "") -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = variation
	return p


static func vbox(sep := 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 6) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func spacer(h := true) -> Control:
	var c := Control.new()
	if h: c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else: c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func titled(title: String, content: Control, variation := "") -> PanelContainer:
	var p := panel(variation)
	var v := vbox(6)
	p.add_child(v)
	v.add_child(label(title.to_upper(), "PanelTitle"))
	v.add_child(content)
	return p


## Rasm joyi: tekstura bo'lsa uni, bo'lmasa kulrang "NO IMAGE".
static func image_slot(tex: Texture2D, min_size: Vector2) -> Control:
	if tex:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.custom_minimum_size = min_size
		return tr
	var c := ColorRect.new()
	c.color = Color(0.22, 0.23, 0.25)
	c.custom_minimum_size = min_size
	var l := label("NO IMAGE", "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	c.add_child(l)
	return c


## Hover'da yorishish va bosilganda kichik "silkinish" (Tween).
static func _hover_fx(c: Control) -> void:
	c.mouse_entered.connect(func():
		if not c.is_inside_tree(): return
		c.create_tween().tween_property(c, "modulate", Color(1.12, 1.1, 1.05), 0.12))
	c.mouse_exited.connect(func():
		if not c.is_inside_tree(): return
		c.create_tween().tween_property(c, "modulate", Color.WHITE, 0.18))


## Element silliq kirsin (0.35 s): pastdan sirpanib, shaffoflikdan.
static func slide_in(c: Control, delay := 0.0, from := Vector2(0, 18)) -> void:
	if not c.is_inside_tree():
		return
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(c, "modulate:a", 1.0, 0.35)
	# mahkamlangan (pin) yoki konteyner ichidagi panel joyi o'zi hisoblanadi: faqat shaffoflik animatsiyasi
	if c.get_parent() is Container or c.has_meta("pin"):
		return
	var p0 := c.position
	c.position = p0 + from
	tw.parallel().tween_property(c, "position", p0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Yuqori o'ng burchakka mahkamlash (o'lcham chapga qarab o'sadi).
static func pin_top_right(c: Control, margin: Vector2) -> void:
	c.anchor_left = 1.0; c.anchor_right = 1.0; c.anchor_top = 0.0; c.anchor_bottom = 0.0
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	c.set_meta("pin", ["tr", margin.x, margin.y])
	_repin(c)
	if not c.minimum_size_changed.is_connected(_repin.bind(c)):
		c.minimum_size_changed.connect(_repin.bind(c))


## Yuqori markazga mahkamlash (ikki tomonga teng o'sadi).
static func pin_top_center(c: Control, y: float, dx := 0.0) -> void:
	c.anchor_left = 0.5; c.anchor_right = 0.5; c.anchor_top = 0.0; c.anchor_bottom = 0.0
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.set_meta("pin", ["tc", dx, y])
	_repin(c)
	if not c.minimum_size_changed.is_connected(_repin.bind(c)):
		c.minimum_size_changed.connect(_repin.bind(c))


## Ichidagi narsalar o'zgarganda (tarjima, yangi qator) panel o'lchamiga qarab joyini qayta hisoblaydi:
## o'ngga mahkamlangan panel chapga, markazdagisi ikki tomonga kengayadi va ekrandan chiqmaydi.
static func _repin(c: Control) -> void:
	var m: Array = c.get_meta("pin", [])
	if m.is_empty():
		return
	var w := c.get_combined_minimum_size().x
	if m[0] == "tr":
		c.offset_right = -float(m[1])
		c.offset_left = -float(m[1]) - w
	else:
		c.offset_left = float(m[1]) - w * 0.5
		c.offset_right = float(m[1]) + w * 0.5
	c.offset_top = float(m[2])
	c.offset_bottom = float(m[2])


static func num(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


static func clear(c: Node) -> void:
	for ch in c.get_children():
		ch.queue_free()
