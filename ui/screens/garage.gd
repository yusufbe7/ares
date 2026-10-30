## 4) GARAGE: tablar (TANKS, APC, TRUCKS, JEEPS, HELICOPTERS). Tanlangan texnika: o'yindagi 3D model
## (sichqoncha bilan aylantirish), nom, tur, FIREPOWER / ARMOR / MOBILITY, narx. BUY (credits yetsa) va
## UPGRADE (dvigatel, zirh, qurol: daraja va narx, ko'rsatkich oshadi). Pastda egalik qilingan texnikalar.
## O'yinda modeli yo'q texnika (BTR-80, Ural) "Tez orada".
extends Control

const TABS := [["tank", "vtab.tanks"], ["apc", "vtab.apc"], ["truck", "vtab.trucks"], ["jeep", "vtab.jeeps"], ["heli", "vtab.heli"]]
const PARTS := [["engine", "mobility"], ["armor", "armor"], ["weapon", "firepower"]]

var _tab := "tank"
var _v: VehicleData
var _tabs: HBoxContainer
var _list: VBoxContainer
var _view: PanelContainer
var _thumb: Control
var _info: VBoxContainer
var _owned: HBoxContainer
var _drag := false


func _ready() -> void:
	var body := ScreenFrame.build(self, "menu.garage", "tank", Color("#5DBE5A"), 0.8)
	var v := UiKit.vbox(12)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.add_child(v)
	var avail := func(t: String) -> bool: return GameSession.items("vehicles").any(func(x): return x.type == t and x.available)
	_tabs = ScreenFrame.tabs(TABS.map(func(t): return [t[0], Loc.t(t[1]), avail.call(t[0])]), _tab, func(id: String): _tab = id; _v = null; _refresh())
	v.add_child(_tabs)
	var h := UiKit.hbox(14)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(h)
	_list = UiKit.vbox(6)
	var lp := UiKit.titled(Loc.t("vehicles"), _list)
	lp.custom_minimum_size = Vector2(280, 0)
	h.add_child(lp)
	_view = UiKit.panel("CardPanel")
	_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view.gui_input.connect(_on_view_input)
	h.add_child(_view)
	_info = UiKit.vbox(8)
	var ip := UiKit.panel()
	ip.custom_minimum_size = Vector2(360, 0)
	ip.add_child(_info)
	h.add_child(ip)
	_owned = UiKit.hbox(8)
	v.add_child(UiKit.titled(Loc.t("my_vehicles"), _owned))
	for s in [EventBus.vehicle_bought, EventBus.vehicle_selected]:
		s.connect(func(_id): _refresh())
	EventBus.credits_changed.connect(func(_a, _b): _refresh())
	_refresh()


func _on_view_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_drag = e.pressed
	elif e is InputEventMouseMotion and _drag and _thumb is ModelThumb:
		(_thumb as ModelThumb).rotate_by((e as InputEventMouseMotion).relative.x * 0.01)


func _refresh() -> void:
	var p: PlayerProfile = GameSession.profile
	var vs: Array = GameSession.items("vehicles").filter(func(x): return x.type == _tab)
	var keep := _v
	if keep == null or not (keep in vs):
		keep = vs[0] if not vs.is_empty() else null
	var changed := keep != _v or _thumb == null
	_v = keep
	UiKit.clear(_list)
	for x in vs:
		var b := UiKit.button("%s%s" % [x.name, "   ✔" if x.id in p.owned_vehicles else ""], "TabButtonActive" if x == _v else "TabButton", func(): _v = x; _thumb = null; _refresh())
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if not x.available:
			b.text += "  ·  " + Loc.t("soon_short")
		_list.add_child(b)
	if changed:
		UiKit.clear(_view)
		_thumb = ModelThumb.make(_v.model if _v else "", Vector2(480, 320), true, _v.model_scale if _v else 1.0)
		_view.add_child(_thumb)
	UiKit.clear(_info)
	if _v == null:
		return
	_info.add_child(UiKit.label(_v.name, "HeaderLabel"))
	_info.add_child(UiKit.label(Loc.t("vtype." + _v.type).to_upper(), "AmberLabel"))
	var d := UiKit.label(Loc.t(_v.description), "SmallLabel")
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_child(d)
	var st := Shop.vehicle_stats(_v)
	for k in ["firepower", "armor", "mobility"]:
		_info.add_child(StatBar.make(Loc.t("stat." + k), st[k]))
	var owned := _v.id in p.owned_vehicles
	var row := UiKit.hbox(8)
	_info.add_child(row)
	row.add_child(UiIcon.make("coins", 18, UiKit.AMBER))
	var pr := UiKit.label(UiKit.num(_v.price), "PanelTitle")
	pr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not owned and p.credits < _v.price:
		pr.add_theme_color_override("font_color", UiKit.RED)
	row.add_child(pr)
	var buy := UiKit.button(Loc.t("owned") if owned else Loc.t("buy"), "AmberButton", func(): Shop.buy_vehicle(_v.id))
	buy.disabled = owned or not _v.available or p.credits < _v.price or p.level() < _v.required_level
	if not _v.available:
		buy.text = Loc.t("soon_short")
		buy.tooltip_text = Loc.t("no_model")
	row.add_child(buy)
	var sel := UiKit.button(Loc.t("selected") if _v.id in p.selected_vehicles else Loc.t("select"), "", func(): Shop.select_vehicle(_v.id))
	sel.disabled = not owned
	row.add_child(sel)
	_info.add_child(HSeparator.new())
	_info.add_child(UiKit.label(Loc.t("upgrades").to_upper(), "PanelTitle"))
	for part in PARTS:
		var lv := Shop.upgrade_level(_v.id, part[0])
		var costs: Array = _v.upgrade_costs.get(part[0], [])
		var uh := UiKit.hbox(8)
		var n := UiKit.label("%s  %s" % [Loc.t("up." + part[0]), "■".repeat(lv) + "□".repeat(costs.size() - lv)], "SmallLabel")
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		uh.add_child(n)
		var maxed := lv >= costs.size()
		var pp: String = part[0]
		var ub := UiKit.button(Loc.t("max") if maxed else "+%d %s  ·  %s" % [_v.upgrade_bonus, Loc.t("stat." + part[1]), UiKit.num(int(costs[lv]))], "", func(): Shop.upgrade(_v.id, pp))
		ub.disabled = maxed or not owned or p.credits < (int(costs[lv]) if not maxed else 0)
		uh.add_child(ub)
		_info.add_child(uh)
	_info.add_child(UiKit.soon(UiKit.button(Loc.t("skins_camo"), "")))
	UiKit.clear(_owned)
	for id in p.owned_vehicles:
		var x: VehicleData = GameSession.item("vehicles", id)
		if x == null:
			continue
		var c := UiKit.button(x.name + ("  ✔" if id in p.selected_vehicles else ""), "TabButtonActive" if x == _v else "TabButton", func(): _tab = x.type; _v = x; _thumb = null; _refresh())
		c.custom_minimum_size = Vector2(150, 40)
		_owned.add_child(c)
