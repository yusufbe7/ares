## Ekran ramkasi: chapda "< ORQAGA" va sarlavha (bo'lim rangida ikonka), o'ngda o'yinchi paneli,
## pastda kontent maydoni (to'q fon). Esc bilan orqaga qaytiladi (ScreenManager).
class_name ScreenFrame
extends RefCounted


static func build(screen: Control, title_key: String, icon: String, color: Color, dim := 0.55) -> Control:
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if dim > 0.0:
		var bg := ColorRect.new()
		bg.color = Color(0.02, 0.025, 0.03, dim)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		screen.add_child(bg)
	var top := UiKit.hbox(14)
	top.position = Vector2(24, 20)
	screen.add_child(top)
	top.add_child(UiKit.button("<  " + Loc.t("back").to_upper(), "", func(): ScreenManager.back()))
	top.add_child(UiIcon.make(icon, 34, color))
	var t := UiKit.label(Loc.t(title_key).to_upper(), "TitleLabel")
	t.add_theme_font_size_override("font_size", 36)
	top.add_child(t)
	var pp := PlayerPanel.make("profile")
	UiKit.pin_top_right(pp, Vector2(16, 12))
	screen.add_child(pp)
	var body := Control.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.offset_left = 24; body.offset_right = -24; body.offset_top = 96; body.offset_bottom = -20
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(body)
	for c in [top, pp]:
		UiKit.slide_in(c)
	return body


## Tablar qatori: [[id, matn, yoqilgan]] -> tugmalar; tanlangani TabButtonActive.
static func tabs(list: Array, active: String, cb: Callable) -> HBoxContainer:
	var h := UiKit.hbox(0)
	for t in list:
		var b := UiKit.button(str(t[1]).to_upper(), "TabButtonActive" if t[0] == active else "TabButton")
		b.custom_minimum_size = Vector2(130, 36)
		if not t[2]:
			UiKit.soon(b)
		var id: String = t[0]
		b.pressed.connect(func(): cb.call(id))
		h.add_child(b)
	return h


static func mark_tabs(h: HBoxContainer, list: Array, active: String) -> void:
	for k in list.size():
		var b: Button = h.get_child(k)
		if not b.disabled:
			b.theme_type_variation = "TabButtonActive" if list[k][0] == active else "TabButton"
