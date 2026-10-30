## 1) CAMPAIGN: chapda missiyalar ro'yxati (ochiq / qulflangan / bajarilgan), o'ngda dunyo xaritasi (sun'iy
## yo'ldosh rasmi) va missiya nuqtalari, ular orasida yo'nalish chizig'i. Missiya ma'lumoti: briefing, vazifalar,
## qiyinlik, mukofotlar. CONTINUE / NEW CAMPAIGN / saqlangan slotlar -> dunyo xaritasi sahnasi.
extends Control

var _list: VBoxContainer
var _info: VBoxContainer
var _map: Control
var _sel: MissionData
var _missions: Array[MissionData] = []
var _save := {}
var _centers := {}
var _names := {}


func _ready() -> void:
	var body := ScreenFrame.build(self, "menu.campaign", "campaign", Color("#E8C23A"))
	_save = SaveManager.load_campaign(0)
	var d := DirAccess.open("res://data/missions/")
	if d:
		for f in d.get_files():
			var path := "res://data/missions/" + f.trim_suffix(".remap")
			if path.ends_with(".tres"):
				_missions.append(load(path))
	_missions.sort_custom(func(a, b): return a.order < b.order)
	for e in CampaignData._json("res://data/provinces.json", []):
		_centers[int(e.id)] = Vector2(e.center_px[0], e.center_px[1])
		_names[int(e.id)] = str(e.name)
	var h := UiKit.hbox(16)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.add_child(h)
	var left := UiKit.vbox(10)
	left.custom_minimum_size = Vector2(360, 0)
	h.add_child(left)
	var lp := UiKit.titled(Loc.t("campaign.title"), UiKit.vbox(4))
	left.add_child(lp)
	_list = lp.get_child(0).get_child(1)
	left.add_child(_slots())
	var right := UiKit.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	var mp := UiKit.panel("CardPanel")
	mp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(mp)
	var tr := TextureRect.new()
	tr.texture = load("res://map/satellite.jpg") if ResourceLoader.exists("res://map/satellite.jpg") else null
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.custom_minimum_size = Vector2(600, 300)
	mp.add_child(tr)
	_map = Control.new()
	_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map.draw.connect(_draw_map)
	# xaritani bosish: dunyo xaritasi o'sha joyda ochiladi (saqlangan o'yin bo'lsa davom etadi)
	_map.mouse_filter = Control.MOUSE_FILTER_STOP
	_map.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_map.gui_input.connect(_on_map_click)
	tr.add_child(_map)
	_info = UiKit.vbox(6)
	var ip := UiKit.panel()
	ip.add_child(_info)
	right.add_child(ip)
	_sel = _missions[0] if not _missions.is_empty() else null
	_refresh()


func _done(m: MissionData) -> bool:
	return (_save.get("missions", {}).get("done", {}) as Dictionary).has(m.id)


func _open(m: MissionData) -> bool:
	return m.requires == "" or (_save.get("missions", {}).get("done", {}) as Dictionary).has(m.requires)


func _refresh() -> void:
	UiKit.clear(_list)
	for k in _missions.size():
		var m := _missions[k]
		var b := UiKit.button("      %s %02d   %s" % [Loc.t("mission").to_upper(), k + 1, Loc.t(m.title)], "TabButtonActive" if m == _sel else "TabButton")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var ic := UiIcon.make("check" if _done(m) else ("target" if _open(m) else "lock"), 16, UiKit.GREEN if _done(m) else (UiKit.AMBER if _open(m) else UiKit.DIM))
		ic.position = Vector2(10, 9)
		b.add_child(ic)
		b.disabled = not _open(m) and not _done(m)
		var mm := m
		b.pressed.connect(func(): _sel = mm; _refresh())
		_list.add_child(b)
	UiKit.clear(_info)
	if _sel:
		_info.add_child(UiKit.label(Loc.t(_sel.title).to_upper(), "HeaderLabel"))
		var br := UiKit.label(Loc.t(_sel.briefing), "SmallLabel")
		br.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_info.add_child(br)
		_info.add_child(UiKit.label("%s: %s" % [Loc.t("difficulty"), Loc.t("diff.%d" % _sel.difficulty)], "AmberLabel"))
		var tgt: int = int(_save.get("missions", {}).get("targets", {}).get(_sel.id, 0))
		var tname: String = _names.get(tgt, Loc.t("target"))
		for o in _sel.objectives:
			_info.add_child(UiKit.label("•  " + Loc.t(str(o.get("text", ""))).replace("%s", tname).replace("%d", str(o.get("count", 1))), "SmallLabel"))
		var rw := []
		for k in ["gold", "supply", "xp"]:
			if _sel.rewards.has(k):
				rw.append("%s %s" % [UiKit.num(int(_sel.rewards[k])), Loc.t(k).to_upper() if k != "xp" else "XP"])
		_info.add_child(UiKit.label("%s: %s" % [Loc.t("rewards"), ",  ".join(rw)], "SmallLabel"))
	_map.queue_redraw()


## Missiya nuqtalari (saqlangan kampaniyadagi maqsad hududlar) va ular orasidagi yo'nalish chizig'i.
func _draw_map() -> void:
	var targets: Dictionary = _save.get("missions", {}).get("targets", {})
	var meta: Dictionary = CampaignData._json("res://data/map_meta.json", {"width": 4320, "height": 1704})
	var sz := _map.size
	var pts := []
	for m in _missions:
		var t := int(targets.get(m.id, 0))
		if _centers.has(t):
			var c: Vector2 = _centers[t]
			pts.append([m, Vector2(c.x / float(meta.width) * sz.x, c.y / float(meta.height) * sz.y)])
	for k in range(1, pts.size()):
		_map.draw_dashed_line(pts[k - 1][1], pts[k][1], UiKit.AMBER, 2.0, 8.0)
	for e in pts:
		var sel: bool = e[0] == _sel
		_map.draw_circle(e[1], 9.0 if sel else 6.0, UiKit.AMBER if sel else Color(0.9, 0.9, 0.85))
		_map.draw_arc(e[1], 13.0, 0, TAU, 24, UiKit.AMBER, 2.0, true)
	if pts.is_empty():
		_map.draw_string(ThemeDB.fallback_font, Vector2(16, 30), Loc.t("hub.no_campaign"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.9))


func _slots() -> Control:
	var v := UiKit.vbox(6)
	var p := UiKit.titled(Loc.t("save_slots"), v)
	var cont := UiKit.button("▶  " + Loc.t("continue").to_upper(), "AmberButton", func(): ScreenManager.open_campaign(0))
	cont.disabled = _save.is_empty()
	v.add_child(cont)
	v.add_child(UiKit.button(Loc.t("new_campaign").to_upper(), "", func(): ScreenManager.open_campaign(-1)))
	for i in [0, 1, 2, 3]:
		var info := SaveManager.slot_info(i)
		var txt := "%s %d:  %s" % [Loc.t("slot"), i, Loc.t("empty")] if info.is_empty() else \
			"%s %d:  %s  ·  %s %d  ·  %s" % [Loc.t("slot") if i > 0 else Loc.t("autosave"), i, info.country, Loc.t("turn"), int(info.turn), str(info.saved_at).replace("T", " ").substr(0, 16)]
		var b := UiKit.button(txt, "TabButton", func(): ScreenManager.open_campaign(i))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = info.is_empty()
		v.add_child(b)
	v.add_child(UiKit.soon(UiKit.button(Loc.t("cinematics"), "")))
	return p


func _on_map_click(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		var meta: Dictionary = CampaignData._json("res://data/map_meta.json", {"width": 4320, "height": 1704})
		GameSession.campaign_focus = Vector2(e.position.x / _map.size.x * float(meta.width), e.position.y / _map.size.y * float(meta.height))
		ScreenManager.open_campaign(0 if not _save.is_empty() else -1)
