## 3) ARMORY: tablar (ASSAULT, SNIPER, LMG, SHOTGUN, PISTOL, LAUNCHER). Chapda qurollar ro'yxati, o'ngda
## tanlangan qurol: 3D model, DAMAGE / ACCURACY / RANGE / FIRE RATE / MOBILITY. Modifikatsiya slotlari:
## slotni bossangiz variantlar chiqadi; variant ustiga borilsa ko'rsatkichlar oldin/keyin farqi bilan
## ko'rinadi, bosilsa sotib olinadi / o'rnatiladi (jangda ham ishlaydi). BUY / UNLOCK, EQUIP.
## O'yinda modeli yo'q sinflar (snayper, pulemyot, drobovik, to'pponcha) "Tez orada".
extends Control

const TABS := ["assault", "sniper", "lmg", "shotgun", "pistol", "launcher"]
const STATS := ["damage", "accuracy", "range", "fire_rate", "mobility"]

var _tab := "assault"
var _w: WeaponData
var _slot := ""
var _tabs: HBoxContainer
var _list: VBoxContainer
var _view: PanelContainer
var _bars := {}
var _slots: HBoxContainer
var _opts: VBoxContainer
var _act: HBoxContainer
var _title: Label


func _ready() -> void:
	var body := ScreenFrame.build(self, "menu.armory", "rifle", Color("#E05A4E"), 0.8)
	var v := UiKit.vbox(12)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.add_child(v)
	var list := TABS.map(func(t): return [t, Loc.t("wclass." + t), _has(t)])
	_tabs = ScreenFrame.tabs(list, _tab, func(id: String): _tab = id; _w = null; _refresh())
	v.add_child(_tabs)
	var h := UiKit.hbox(14)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(h)
	_list = UiKit.vbox(6)
	var lp := UiKit.titled(Loc.t("weapons"), _list)
	lp.custom_minimum_size = Vector2(300, 0)
	h.add_child(lp)
	var right := UiKit.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	var top := UiKit.hbox(14)
	right.add_child(top)
	_view = UiKit.panel("CardPanel")
	_view.custom_minimum_size = Vector2(460, 240)
	top.add_child(_view)
	var sv := UiKit.vbox(6)
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sv)
	_title = UiKit.label("", "HeaderLabel")
	sv.add_child(_title)
	for s in STATS:
		_bars[s] = StatBar.make(Loc.t("stat." + s), 0)
		sv.add_child(_bars[s])
	_act = UiKit.hbox(8)
	sv.add_child(_act)
	_slots = UiKit.hbox(8)
	right.add_child(UiKit.titled(Loc.t("modifications"), _slots))
	_opts = UiKit.vbox(4)
	right.add_child(_opts)
	right.add_child(UiKit.soon(UiKit.button(Loc.t("weapon_skins"), "")))
	EventBus.weapon_equipped.connect(func(_id): _refresh())
	EventBus.credits_changed.connect(func(_a, _b): _refresh())
	_refresh()


func _has(cls: String) -> bool:
	return GameSession.items("weapons").any(func(w): return w.weapon_class == cls)


func _refresh() -> void:
	ScreenFrame.mark_tabs(_tabs, TABS.map(func(t): return [t, "", true]), _tab)
	var ws: Array = GameSession.items("weapons").filter(func(w): return w.weapon_class == _tab)
	if _w == null or not (_w in ws):
		_w = ws[0] if not ws.is_empty() else null
	UiKit.clear(_list)
	var p: PlayerProfile = GameSession.profile
	for w in ws:
		var b := UiKit.button("%s%s" % [w.name, "   ✔" if w.id == p.equipped_weapon else ""], "TabButtonActive" if w == _w else "TabButton", func(): _w = w; _slot = ""; _refresh())
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_list.add_child(b)
	UiKit.clear(_view)
	UiKit.clear(_act)
	UiKit.clear(_slots)
	UiKit.clear(_opts)
	if _w == null:
		_title.text = Loc.t("coming_soon")
		return
	_view.add_child(ModelThumb.make(_w.model, Vector2(460, 240), true, _w.model_scale))
	_title.text = _w.name
	var st := Shop.weapon_stats(_w)
	for s in STATS:
		_bars[s].set_value(st[s])
	var owned := _w.id in p.owned_weapons
	if not owned:
		var lock := p.level() < _w.required_level
		var b := UiKit.button((Loc.t("unlock_lv", [_w.required_level]) if lock else Loc.t("buy")) + "  " + UiKit.num(_w.price), "AmberButton", func(): Shop.buy_weapon(_w.id); _refresh())
		b.disabled = lock or p.credits < _w.price
		_act.add_child(b)
	else:
		var e := UiKit.button(Loc.t("equipped") if p.equipped_weapon == _w.id else Loc.t("equip"), "AmberButton", func(): Shop.equip_weapon(_w.id))
		e.disabled = p.equipped_weapon == _w.id
		_act.add_child(e)
	if _w.slots.is_empty():
		_slots.add_child(UiKit.label(Loc.t("no_mod_slots"), "SmallLabel"))
	var mods: Dictionary = p.weapon_mods.get(_w.id, {})
	for slot in _w.slots:
		var a: AttachmentData = GameSession.item("attachments", str(mods.get(slot, "")))
		var b := UiKit.button("%s\n%s" % [Loc.t("slot." + slot).to_upper(), a.name if a else Loc.t("empty")], "TabButtonActive" if slot == _slot else "TabButton", func(): _slot = slot; _refresh())
		b.custom_minimum_size = Vector2(140, 54)
		b.disabled = not owned
		_slots.add_child(b)
	if _slot != "" and owned:
		_show_options(mods)


## Slot variantlari: ustiga borilsa ko'rsatkichlar oldin/keyin, bosilsa o'rnatiladi (kerak bo'lsa sotib olinadi).
func _show_options(mods: Dictionary) -> void:
	var h := UiKit.hbox(8)
	_opts.add_child(h)
	var none := UiKit.button(Loc.t("remove"), "", func(): Shop.uninstall(_w.id, _slot))
	none.disabled = not mods.has(_slot)
	h.add_child(none)
	for a in GameSession.items("attachments"):
		if a.slot != _slot:
			continue
		var own: bool = a.id in GameSession.profile.owned_attachments
		var parts := []
		for k in a.stats:
			parts.append("%s %s%d" % [Loc.t("stat." + k), "+" if int(a.stats[k]) > 0 else "", int(a.stats[k])])
		var b := UiKit.button("%s\n%s" % [a.name, Loc.t("owned") if own else UiKit.num(a.price)], "TabButtonActive" if mods.get(_slot, "") == a.id else "TabButton", func(): Shop.install(_w.id, a))
		b.custom_minimum_size = Vector2(130, 54)
		b.tooltip_text = ", ".join(parts)
		b.disabled = not own and (GameSession.profile.level() < a.required_level or GameSession.profile.credits < a.price)
		b.mouse_entered.connect(func():
			var after := Shop.weapon_stats(_w, a)
			for s in STATS: _bars[s].preview(after[s]))
		b.mouse_exited.connect(func():
			var now := Shop.weapon_stats(_w)
			for s in STATS: _bars[s].set_value(now[s]))
		h.add_child(b)
