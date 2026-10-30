## SOZLAMALAR: chapda bo'limlar ro'yxati, o'ngda tafsilot. Har o'zgarish darhol qo'llanadi va
## user://settings.cfg ga saqlanadi (Settings). "Standartga qaytarish" hammasini tiklaydi.
## Bo'limlar: GRAPHICS, AUDIO, CONTROLS (tugmalarni qayta belgilash, ziddiyat tekshiruvi), GAMEPLAY,
## LANGUAGE, INTERFACE, CREDITS.
extends Control

const SECTIONS := [["graphics", "set.graphics", "target"], ["audio", "set.audio", "units"], ["controls", "set.controls", "gear"],
	["gameplay", "set.gameplay", "soldier"], ["language", "set.language", "globe"], ["interface", "set.interface", "base"],
	["credits", "set.credits", "check"]]
const COLOR := Color("#3EC1C9")

var _s: Dictionary
var _sec := "graphics"
var _menu: SideMenu
var _body: VBoxContainer
var _title: Label
var _wait_action := ""          ## qaysi amal uchun yangi tugma kutilmoqda
var _wait_btn: Button
var _msg: Label


func _ready() -> void:
	_s = Settings.load_all()
	var body := ScreenFrame.build(self, "menu.settings", "gear", COLOR)
	var h := UiKit.hbox(16)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.add_child(h)
	var left := UiKit.vbox(10)
	h.add_child(left)
	_menu = SideMenu.make(SECTIONS.map(func(x): return [x[0], x[1], x[2], true]), _sec)
	_menu.chosen.connect(func(id: String): _sec = id; _rebuild())
	left.add_child(_menu)
	left.add_child(UiKit.spacer(false))
	left.add_child(UiKit.button(Loc.t("set.defaults"), "", _defaults))
	var right := UiKit.panel()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	var rv := UiKit.vbox(14)
	right.add_child(rv)
	_title = UiKit.label("", "PanelTitle")
	_title.add_theme_font_size_override("font_size", 26)
	rv.add_child(_title)
	_msg = UiKit.label("", "AmberLabel")
	rv.add_child(_msg)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(sc)
	_body = UiKit.vbox(12)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_body)
	_rebuild()


func _rebuild() -> void:
	for id in _menu._buttons:
		_menu._buttons[id].theme_type_variation = "NavButtonActive" if id == _sec else "NavButton"
	UiKit.clear(_body)
	_msg.text = ""
	_wait_action = ""
	for x in SECTIONS:
		if x[0] == _sec:
			_title.text = Loc.t(x[1]).to_upper()
	match _sec:
		"graphics": _graphics()
		"audio": _audio()
		"controls": _controls()
		"gameplay": _gameplay()
		"language": _language()
		"interface": _interface()
		"credits": _credits()


# ------------------------------------------------------------------ qatorlar
func _row(title_key: String, ctl: Control) -> void:
	var h := UiKit.hbox(16)
	var l := UiKit.label(Loc.t(title_key), "")
	l.custom_minimum_size = Vector2(300, 0)
	h.add_child(l)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ctl)
	_body.add_child(h)


func _check(sec: String, key: String, title_key: String) -> void:
	var c := CheckButton.new()
	c.button_pressed = bool(_s[sec].get(key, false))
	c.focus_mode = Control.FOCUS_ALL
	c.toggled.connect(func(on: bool): _put(sec, key, on))
	_row(title_key, c)


func _slider(sec: String, key: String, title_key: String, lo: float, hi: float, step := 0.05) -> void:
	var h := UiKit.hbox(10)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(_s[sec].get(key, lo))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(260, 24)
	var v := UiKit.label("", "SmallLabel")
	v.custom_minimum_size = Vector2(56, 0)
	var show := func(x: float): v.text = ("%d%%" % int(round(x * 100.0))) if hi <= 1.0 else ("x%.2f" % x)
	show.call(s.value)
	s.value_changed.connect(func(x: float): show.call(x); _put(sec, key, x))
	h.add_child(s)
	h.add_child(v)
	_row(title_key, h)


func _option(sec: String, key: String, title_key: String, items: Array, values: Array) -> void:
	var o := OptionButton.new()
	for k in items.size():
		o.add_item(str(items[k]))
		if str(values[k]) == str(_s[sec].get(key, values[0])):
			o.select(k)
	o.item_selected.connect(func(k: int): _put(sec, key, values[k]))
	_row(title_key, o)


func _soon_row(title_key: String) -> void:
	var b := UiKit.button(Loc.t("set.off"), "")
	UiKit.soon(b)
	_row(title_key, b)


## Qiymatni o'zgartiradi, darhol qo'llaydi va saqlaydi.
func _put(sec: String, key: String, v: Variant) -> void:
	_s[sec][key] = v
	Settings.save_all(_s)
	Settings.apply(_s, get_tree().root)
	EventBus.settings_changed.emit()
	_msg.text = Loc.t("set.saved")


# ------------------------------------------------------------------ bo'limlar
func _graphics() -> void:
	_option("graphics", "resolution", "set.resolution", Settings.RESOLUTIONS, Settings.RESOLUTIONS)
	_check("graphics", "fullscreen", "set.fullscreen")
	_check("graphics", "vsync", "set.vsync")
	_option("graphics", "quality", "set.quality", [Loc.t("set.low"), Loc.t("set.medium"), Loc.t("set.high")], [0, 1, 2])
	_check("graphics", "shadows", "set.shadows")
	_option("graphics", "msaa", "set.aa", [Loc.t("set.off"), "MSAA 2x", "MSAA 4x", "MSAA 8x"], [0, 2, 4, 8])


func _audio() -> void:
	for b in [["Master", "set.master"], ["Music", "set.music"], ["SFX", "set.sfx"], ["UI", "set.ui"], ["Voice", "set.voice"]]:
		_slider("audio", b[0], b[1], 0.0, 1.0)


func _controls() -> void:
	_body.add_child(UiKit.label(Loc.t("set.rebind"), "SmallLabel"))
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 16)
	g.add_theme_constant_override("v_separation", 6)
	_body.add_child(g)
	var c: Dictionary = _s["controls"]
	for a in Keys.ACTIONS:
		var l := UiKit.label(Loc.t("act." + a[0]), "")
		l.custom_minimum_size = Vector2(300, 0)
		g.add_child(l)
		var key := int(c.get(a[0], a[1]))
		var b := UiKit.button(OS.get_keycode_string(key), "")
		b.custom_minimum_size = Vector2(160, 34)
		var act: String = a[0]
		b.pressed.connect(func(): _wait_action = act; _wait_btn = b; b.text = Loc.t("set.press_key"))
		g.add_child(b)


func _input(e: InputEvent) -> void:
	if _wait_action == "" or not (e is InputEventKey) or not e.pressed or e.echo:
		return
	get_viewport().set_input_as_handled()
	var k := (e as InputEventKey).keycode
	var act := _wait_action
	_wait_action = ""
	if k == KEY_ESCAPE:
		_rebuild()
		return
	var other := Keys.conflict(act, k)
	if other != "":
		_wait_btn.text = OS.get_keycode_string(Keys.key_of(act))
		_msg.text = Loc.t("set.conflict", [Loc.t("act." + other)])
		_msg.add_theme_color_override("font_color", UiKit.RED)
		return
	_msg.remove_theme_color_override("font_color")
	_put("controls", act, k)
	_wait_btn.text = OS.get_keycode_string(k)


func _gameplay() -> void:
	_slider("gameplay", "camera_speed", "camera_speed", 0.4, 2.5)
	_soon_row("auto_pause")
	_soon_row("order_hints")


func _language() -> void:
	for l in Loc.langs():
		var code: String = l[0]
		var b := UiKit.button(str(l[1]), "TabButtonActive" if code == Loc.lang else "TabButton", func():
			_put("game", "language", code)
			EventBus.language_changed.emit()
			ScreenManager.open("settings", false))     # ekran yangi tilda qayta chiziladi
		b.custom_minimum_size = Vector2(260, 44)
		_body.add_child(b)


func _interface() -> void:
	_slider("interface", "ui_scale", "ui_scale", 0.75, 1.5)
	_slider("interface", "panel_opacity", "panel_opacity", 0.4, 1.0)
	_check("interface", "show_fps", "show_fps")


func _credits() -> void:
	var clip := Control.new()
	clip.clip_contents = true
	clip.custom_minimum_size = Vector2(0, 520)
	clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(clip)
	var l := UiKit.label(Loc.t("credits_text"), "", HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 18)
	clip.add_child(l)
	l.size = Vector2(900, 0)
	# aylanuvchi matn: pastdan yuqoriga, takrorlanadi
	l.position = Vector2(0, 520)
	var tw := l.create_tween().set_loops()
	tw.tween_property(l, "position:y", -420.0, 22.0).from(520.0)


func _defaults() -> void:
	_s = Settings.defaults()
	_s["game"]["language"] = Loc.lang
	for a in Keys.ACTIONS:                    # tugmalar ham standartga qaytadi
		_s["controls"][a[0]] = a[1]
	Settings.save_all(_s)
	Settings.apply(_s, get_tree().root)
	EventBus.settings_changed.emit()
	_rebuild()
	_msg.text = Loc.t("set.saved")
