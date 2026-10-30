## DAVLAT TANLASH (o'yin ochilganda birinchi ekran). Chapda qidiruv va ro'yxat (bayroq, nom, kuch), o'rtada
## dunyo xaritasi (bosib tanlash), pastda o'yin sozlamalari (rejim, qiyinlik, Ironman, bloklarsiz), o'ngda
## tanlangan davlat: kuch, tablar (Umumiy / Statistika / Blok / Boshqaruv), g'alaba shartlari.
## START -> GameSession.campaign_setup to'ldiriladi va bosh menyu ochiladi.
extends Control

const TABS := [["overview", "tab.overview", true], ["stats", "tab.stats", true], ["bloc", "tab.bloc", true],
	["system", "tab.system", false]]

var _list: VBoxContainer
var _search: LineEdit
var _map: WorldPickMap
var _info: VBoxContainer
var _tabs: HBoxContainer
var _tab := "overview"
var _sel: Dictionary = {}
var _mode: OptionButton
var _diff: OptionButton
var _iron: CheckButton
var _noblocs: CheckButton
var _victory: Label
var _rows := {}                      ## davlat id -> Button


func _ready() -> void:
	var body := ScreenFrame.build(self, "cs.title", "globe", UiKit.AMBER, 0.7)
	var h := UiKit.hbox(14)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.add_child(h)
	h.add_child(_left())
	var mid := UiKit.vbox(10)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(mid)
	var mp := UiKit.panel("CardPanel")
	mp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(mp)
	var mv := UiKit.vbox(4)
	mp.add_child(mv)
	# xarita o'z nisbatida (4320 x 1704), cho'zilmaydi
	var ar := AspectRatioContainer.new()
	ar.ratio = 4320.0 / 1704.0
	ar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mv.add_child(ar)
	_map = WorldPickMap.new()
	_map.custom_minimum_size = Vector2(500, 197)
	_map.picked.connect(func(cid): _select(CountryInfo.get_info(cid), true))
	ar.add_child(_map)
	mv.add_child(UiKit.label(Loc.t("cs.pick_map"), "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER))
	mid.add_child(_options())
	h.add_child(_right())
	var setup: Dictionary = GameSession.campaign_setup
	var first: Dictionary = CountryInfo.by_code(str(setup.get("country", "USA")))
	if first.is_empty():
		first = CountryInfo.by_code("USA")
	_select(first, true)
	_search.grab_focus.call_deferred()


func _left() -> Control:
	var v := UiKit.vbox(6)
	v.custom_minimum_size = Vector2(330, 0)
	_search = LineEdit.new()
	_search.placeholder_text = Loc.t("search")
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): _fill())
	v.add_child(_search)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var p := UiKit.panel()
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.add_child(sc)
	v.add_child(p)
	_list = UiKit.vbox(2)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list)
	_fill()
	return v


## Ro'yxat (qidiruv bo'yicha filtr): bayroq, nom, kuch.
func _fill() -> void:
	UiKit.clear(_list)
	_rows.clear()
	var q := _search.text.strip_edges().to_lower()
	for e in CountryInfo.all():
		var c: CountryData = e.country
		var nm := Loc.country(c)
		if q != "" and not nm.to_lower().contains(q) and not c.code.to_lower().contains(q):
			continue
		var b := UiKit.button("            " + nm, "TabButtonActive" if e == _sel else "TabButton")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 34)
		b.clip_text = true
		var f := FlagRect.make(c, Vector2(33, 22))
		f.position = Vector2(8, 6)
		b.add_child(f)
		var s := UiKit.label(str(e.strength), "AmberLabel", HORIZONTAL_ALIGNMENT_RIGHT)
		s.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		s.offset_left = -52; s.offset_right = -10
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(s)
		var ee: Dictionary = e
		b.pressed.connect(func(): _select(ee, false))
		_list.add_child(b)
		_rows[c.id] = b


func _options() -> Control:
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 14)
	var p := UiKit.titled(Loc.t("game_mode"), g)
	_mode = OptionButton.new()
	for k in ["mode.standard", "mode.domination"]:
		_mode.add_item(Loc.t(k))
	_diff = OptionButton.new()
	for k in [1, 2, 3]:
		_diff.add_item(Loc.t("diff.%d" % k))
	var st: Dictionary = GameSession.campaign_setup
	_mode.selected = 1 if st.get("mode", "standard") == "domination" else 0
	_diff.selected = clampi(int(st.get("difficulty", 2)) - 1, 0, 2)
	g.add_child(UiKit.label(Loc.t("game_mode"), "StatLabel"))
	g.add_child(_mode)
	g.add_child(UiKit.label(Loc.t("difficulty"), "StatLabel"))
	g.add_child(_diff)
	_iron = CheckButton.new()
	_iron.text = Loc.t("ironman")
	_iron.button_pressed = bool(st.get("ironman", false))
	_noblocs = CheckButton.new()
	_noblocs.text = Loc.t("no_blocs")
	_noblocs.button_pressed = bool(st.get("no_blocs", false))
	g.add_child(_iron)
	g.add_child(UiKit.spacer())
	g.add_child(_noblocs)
	for o in [_mode, _noblocs]:
		if o is OptionButton:
			o.item_selected.connect(func(_i): _show())
		else:
			o.toggled.connect(func(_b): _show())
	return p


func _right() -> Control:
	var v := UiKit.vbox(8)
	v.custom_minimum_size = Vector2(420, 0)
	var p := UiKit.panel()
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(p)
	_info = UiKit.vbox(8)
	p.add_child(_info)
	_tabs = ScreenFrame.tabs(TABS.map(func(t): return [t[0], Loc.t(t[1]), t[2]]), _tab, func(id): _tab = id; _show())
	for b in _tabs.get_children():
		b.custom_minimum_size = Vector2(100, 34)
	v.add_child(_tabs)
	_victory = UiKit.label("", "SmallLabel")
	_victory.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_victory)
	var row := UiKit.hbox(8)
	row.add_child(UiKit.button(Loc.t("exit_game").to_upper(), "", func(): ExitDialog.ask(get_tree().current_scene)))
	row.add_child(UiKit.button(Loc.t("random").to_upper(), "", _random))
	row.add_child(UiKit.spacer())
	var go := UiKit.button("▶  " + Loc.t("start").to_upper(), "AmberButton", _start)
	go.custom_minimum_size = Vector2(170, 52)
	go.add_theme_font_size_override("font_size", 22)
	row.add_child(go)
	v.add_child(row)
	return v


func _select(e: Dictionary, scroll: bool) -> void:
	if e.is_empty():
		return
	_sel = e
	for id in _rows:
		_rows[id].theme_type_variation = "TabButtonActive" if id == e.country.id else "TabButton"
	if scroll and _rows.has(e.country.id):
		var b: Button = _rows[e.country.id]
		_scroll_to(b)
	_show()


## O'ng panel: bayroq, nom, kuch va tanlangan tab.
func _show() -> void:
	if _sel.is_empty():
		return
	var c: CountryData = _sel.country
	var blocs := not _noblocs.button_pressed
	_map.highlight(c.id, CountryInfo.bloc_members(c.bloc).map(func(x): return x.country.id) if blocs else [])
	ScreenFrame.mark_tabs(_tabs, TABS, _tab)
	UiKit.clear(_info)
	var top := UiKit.hbox(12)
	top.add_child(FlagRect.make(c, Vector2(84, 56)))
	var tv := UiKit.vbox(2)
	tv.add_child(UiKit.label(Loc.country(c).to_upper(), "HeaderLabel"))
	tv.add_child(UiKit.label("%s: %s" % [Loc.t("capital").capitalize(), _sel.capital_name], "SmallLabel"))
	top.add_child(tv)
	_info.add_child(top)
	_info.add_child(StatBar.make(Loc.t("strength"), float(_sel.strength)))
	var t := UiKit.label("", "SmallLabel")
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	match _tab:
		"overview":
			t.text = CountryInfo.describe(_sel)
		"stats":
			var res: Dictionary = c.resources
			var lines := [[Loc.t("population"), UiKit.num(c.population)], [Loc.t("gdp"), "$" + UiKit.num(c.gdp_musd) + " M"],
				[Loc.t("provinces"), str(_sel.provinces)], [Loc.t("regiments"), str(_sel.regiments)],
				[Loc.t("bases"), str(_sel.bases)], [Loc.t("gold"), UiKit.num(int(res.get("gold", 0)))],
				[Loc.t("supply"), UiKit.num(int(res.get("supply", 0)))], [Loc.t("manpower"), UiKit.num(int(res.get("manpower", 0)))]]
			t.text = "\n".join(lines.map(func(l): return "%s:  %s" % [l[0], l[1]]))
		"bloc":
			if not blocs:
				t.text = Loc.t("cs.blocs_off")
			elif c.bloc == "":
				t.text = Loc.t("cs.bloc_none")
			else:
				var m := CountryInfo.bloc_members(c.bloc).map(func(x): return Loc.country(x.country))
				t.text = Loc.t("cs.bloc_in", [c.bloc]) + "\n\n" + Loc.t("cs.members", [", ".join(m)])
	_info.add_child(t)
	_victory.text = Loc.t("victory.domination" if _mode.selected == 1 else "victory.standard")


func _scroll_to(b: Control) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(b):
		var sc := _list.get_parent() as ScrollContainer
		sc.scroll_vertical = int(b.position.y - sc.size.y * 0.4)


func _random() -> void:
	var l := CountryInfo.all().filter(func(e): return e.provinces > 0)
	_select(l[randi() % l.size()], true)


## Tanlov saqlanadi va bosh menyuga o'tiladi. Kampaniya (NEW CAMPAIGN / urush) shu sozlamalar bilan boshlanadi.
func _start() -> void:
	GameSession.campaign_setup = {"country": _sel.country.code, "mode": "domination" if _mode.selected == 1 else "standard",
		"difficulty": _diff.selected + 1, "ironman": _iron.button_pressed, "no_blocs": _noblocs.button_pressed}
	GameSession.save_setup()
	ScreenManager.open("main")
