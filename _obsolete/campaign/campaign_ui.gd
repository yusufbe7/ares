## Strategik xarita UI: tepada davlat va oltin, o'ng yuqorida til tanlash, pastda "Ma'lum davlatlar" ro'yxati,
## yon tomonda tanlangan hudud yoki (tanlash ekranida) davlat haqida qisqa ma'lumot, xabarlar.
## Hamma matnlar data/lang/*.json dan (Loc.t).
class_name CampaignUI
extends CanvasLayer

const PANEL := Color(0.09, 0.08, 0.07, 0.88)
const GOLD := Color(0.95, 0.78, 0.38)

var map: CampaignMap
var _top: Label
var _end: Button
var _lang: OptionButton
var _side: PanelContainer
var _info: RichTextLabel
var _choose: Button
var _recruit: Button
var _list_title: Label
var _list: HBoxContainer
var _feed: VBoxContainer
var _shown_country := 0
var _panels: Array = []         ## yozuvlar shu panellar ostiga tushmasin


static func _sb(bg: Color, border := Color(0, 0, 0, 0), w := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(w)
	s.set_corner_radius_all(4)
	s.content_margin_left = 8; s.content_margin_right = 8; s.content_margin_top = 6; s.content_margin_bottom = 6
	return s


func _label(t: String, size := 14, col := Color(0.95, 0.93, 0.88)) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func setup(p_map: CampaignMap) -> void:
	map = p_map
	# ---------------- tepa: davlat, oltin, yurish
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", _sb(PANEL, Color(0.45, 0.36, 0.22), 1))
	top.anchor_left = 0.5; top.anchor_right = 0.5
	top.offset_left = -330; top.offset_right = 330; top.offset_top = 8
	add_child(top)
	var th := HBoxContainer.new()
	top.add_child(th)
	_top = _label("", 16, GOLD)
	_top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(_top)
	_end = Button.new()
	_end.focus_mode = Control.FOCUS_NONE
	_end.pressed.connect(func(): map.end_turn())
	th.add_child(_end)
	_panels.append(top)
	# ---------------- o'ng yuqori: til
	var lp := PanelContainer.new()
	lp.add_theme_stylebox_override("panel", _sb(PANEL, Color(0.45, 0.36, 0.22), 1))
	lp.anchor_left = 1.0; lp.anchor_right = 1.0
	lp.offset_left = -170; lp.offset_right = -10; lp.offset_top = 8
	add_child(lp)
	_lang = OptionButton.new()
	_lang.focus_mode = Control.FOCUS_NONE
	var i := 0
	for l in Loc.langs():
		_lang.add_item(l[1])
		_lang.set_item_metadata(i, l[0])
		if l[0] == Loc.lang:
			_lang.select(i)
		i += 1
	_lang.item_selected.connect(func(k: int):
		Loc.set_lang(_lang.get_item_metadata(k))
		map.apply_language())
	lp.add_child(_lang)
	_panels.append(lp)
	# ---------------- yon: hudud yoki davlat ma'lumoti
	_side = PanelContainer.new()
	_side.add_theme_stylebox_override("panel", _sb(PANEL, Color(0.45, 0.36, 0.22), 1))
	_side.anchor_left = 1.0; _side.anchor_right = 1.0
	_side.offset_left = -290; _side.offset_right = -10; _side.offset_top = 60
	add_child(_side)
	var sv := VBoxContainer.new()
	_side.add_child(sv)
	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.fit_content = true
	_info.custom_minimum_size = Vector2(260, 10)
	_info.add_theme_font_size_override("normal_font_size", 14)
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sv.add_child(_info)
	_choose = Button.new()
	_choose.focus_mode = Control.FOCUS_NONE
	_choose.pressed.connect(func(): map.choose_country(map.choice_id))
	sv.add_child(_choose)
	_recruit = Button.new()
	_recruit.focus_mode = Control.FOCUS_NONE
	_recruit.pressed.connect(func(): map.recruit(map.selected_id))
	sv.add_child(_recruit)
	_side.visible = false
	_panels.append(_side)
	# ---------------- past: Ma'lum davlatlar
	var bottom := PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", _sb(PANEL, Color(0.45, 0.36, 0.22), 1))
	bottom.anchor_left = 0.0; bottom.anchor_right = 1.0; bottom.anchor_top = 1.0; bottom.anchor_bottom = 1.0
	bottom.offset_left = 230; bottom.offset_right = -230; bottom.offset_top = -92; bottom.offset_bottom = -8
	add_child(bottom)
	_panels.append(bottom)
	var bv := VBoxContainer.new()
	bottom.add_child(bv)
	_list_title = _label("", 13, GOLD)
	_list_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(_list_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 48)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bv.add_child(scroll)
	_list = HBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	scroll.add_child(_list)
	# ---------------- xabarlar
	_feed = VBoxContainer.new()
	_feed.position = Vector2(12, 60)
	_feed.custom_minimum_size = Vector2(520, 0)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_feed)
	rebuild_texts()


## Til almashganda hamma matnlarni qayta yozadi.
func rebuild_texts() -> void:
	_end.text = Loc.t("end_turn")
	_recruit.text = Loc.t("recruit", [CampaignMap.RECRUIT_COST])
	_list_title.text = Loc.t("known_nations")
	refresh()


func refresh() -> void:
	var d := map.data
	if map.phase == "choose":
		_top.text = Loc.t("choose_title")
		_end.visible = false
	else:
		var c: CountryData = d.countries[map.player_id]
		_top.text = Loc.t("top_bar", [Loc.country(c), int(c.resources.get("gold", 0)), c.province_count, map.turn])
		_end.visible = map.phase == "play"
	for ch in _list.get_children():
		ch.queue_free()
	var cs: Array = d.countries.values().filter(func(c): return c.province_count > 0)
	cs.sort_custom(func(a, b): return a.province_count > b.province_count)
	for c in cs:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.flat = true
		var h := HBoxContainer.new()
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sw := ColorRect.new()
		sw.color = c.color
		sw.custom_minimum_size = Vector2(16, 16)
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(sw)
		var l := _label("%s  %d" % [Loc.country(c), c.province_count], 13, GOLD if c.id == map.player_id else Color(0.92, 0.9, 0.86))
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(l)
		b.add_child(h)
		b.custom_minimum_size = Vector2(h.get_combined_minimum_size().x + 26, 28)
		var cid: int = c.id
		b.pressed.connect(func():
			var cap: int = map.data.countries[cid].capital
			if map.owner_of(cap) != cid:
				cap = map._any_province(cid)
			map.cam.focus(map.province_world(cap))
			if map.phase == "choose":
				map.preview_country(cid)
			else:
				map.select_province(cap))
		_list.add_child(b)
	if map.phase == "choose":
		show_country(_shown_country)
	else:
		show_province(map.selected_id)


## Tanlash ekrani: davlat haqida qisqa ma'lumot (nomi, hududlar soni, kuchi).
func show_country(cid: int) -> void:
	_shown_country = cid
	var c: CountryData = map.data.countries.get(cid)
	_recruit.visible = false
	if c == null:
		_side.visible = map.choice_id > 0
		if map.choice_id > 0 and map.choice_id != cid:
			show_country(map.choice_id)
		return
	_side.visible = true
	var s := map.strength(cid)
	var t := "[font_size=22][color=#%s]■[/color] [b]%s[/b][/font_size]\n\n" % [c.color.to_html(false), Loc.country(c)]
	t += "%s: [b]%d[/b]\n" % [Loc.t("provinces"), c.province_count]
	t += "%s: [b]%s[/b]\n" % [Loc.t("strength"), Loc.t("armies_fmt", [s.x, s.y]) if s.y > 0 else Loc.t("no_army")]
	t += "%s: %d\n" % [Loc.t("gold"), int(c.resources.get("gold", 0))]
	var cap: ProvinceData = map.data.provinces.get(c.capital)
	if cap and cap.owner == cid:
		t += "%s: %s\n" % [Loc.t("capital").capitalize(), cap.name]
	_info.text = t
	var chosen: CountryData = map.data.countries.get(map.choice_id)
	_choose.visible = chosen != null
	if chosen:
		_choose.text = Loc.t("play_as", [Loc.country(chosen)])


func show_province(id: int) -> void:
	if map.phase == "choose":
		return
	var d := map.data
	var p: ProvinceData = d.provinces.get(id)
	if p == null:
		_side.visible = false
		return
	_side.visible = true
	var c: CountryData = d.countries.get(p.owner)
	var a := map.army_in(id)
	var t := "[font_size=20][b]%s[/b][/font_size]\n" % p.name
	t += "[color=#%s]■[/color] %s%s\n\n" % [c.color.to_html(false) if c else "999999", Loc.country(c), "  (%s)" % Loc.t("capital") if c and c.capital == id else ""]
	t += "%s: %s\n" % [Loc.t("population"), _num(p.population)]
	t += "%s: %s\n" % [Loc.t("resource"), Loc.resource(p.resource)]
	t += "%s: %s %s\n" % [Loc.t("area"), _num(p.area_km2), Loc.t("km2")]
	t += "%s: %d %s%s\n" % [Loc.t("elevation"), p.elevation_m, Loc.t("m"), "   (%s)" % Loc.t("coastal") if p.coastal else ""]
	t += "%s: %d\n" % [Loc.t("neighbors"), p.neighbors.size()]
	if a:
		var ac: CountryData = d.countries.get(a.owner)
		t += "\n" + Loc.t("army_line", [a.size, Loc.country(ac)])
		if a.moved and a.owner == map.player_id:
			t += "  - " + Loc.t("moved")
		if a.owner == map.player_id and not a.moved:
			t += "\n[color=#f2c862]%s[/color]" % Loc.t("right_click_hint")
	_info.text = t
	_choose.visible = false
	_recruit.visible = map.phase == "play" and p.owner == map.player_id and a == null


static func _num(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = " " + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


## Ekranda ko'rinib turgan panellar (yozuvlar ularning ostiga tushmasligi uchun).
func blocked_rects() -> Array:
	var out := []
	for p in _panels:
		if p.visible:
			out.append(p.get_global_rect())
	return out


func clear_messages() -> void:
	for ch in _feed.get_children():
		ch.free()


func message(t: String) -> void:
	var l := _label(t, 14)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(520, 0)
	_feed.add_child(l)
	while _feed.get_child_count() > 6:
		_feed.get_child(0).free()
	var tm := Timer.new()
	tm.wait_time = 9.0
	tm.one_shot = true
	tm.autostart = true
	tm.timeout.connect(l.queue_free)
	l.add_child(tm)
