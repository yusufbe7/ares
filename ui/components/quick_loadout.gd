## Tezkor loadout paneli (bosh menyu pastida): UNIFORM, HELMET, VEST, GLOVES (strelkalar bilan variant
## almashtirish, faqat egalik qilinganlari) va CAMOUFLAGE COLOR. O'zgarsa o'rtadagi askar darhol yangilanadi.
class_name QuickLoadout
extends PanelContainer

const CATS := ["uniform", "helmet", "vest", "gloves"]
const CAMOS := ["olive", "desert", "woodland", "arctic"]

var _names := {}
var _camo_btn := {}


func _ready() -> void:
	var h := UiKit.hbox(12)
	add_child(h)
	for cat in CATS:
		var v := UiKit.vbox(2)
		v.add_child(UiKit.label(Loc.t("cat." + cat).to_upper(), "StatLabel", HORIZONTAL_ALIGNMENT_CENTER))
		var box := UiKit.panel("CardPanel")
		box.custom_minimum_size = Vector2(84, 58)
		var ic := UiIcon.make({"uniform": "soldier", "helmet": "soldier", "vest": "crate", "gloves": "units"}[cat], 34)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(ic)
		v.add_child(box)
		var row := UiKit.hbox(2)
		var c: String = cat
		row.add_child(UiKit.button("<", "IconButton", func(): _cycle(c, -1)))
		var n := UiKit.label("", "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
		n.custom_minimum_size = Vector2(64, 0)
		n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(n)
		row.add_child(UiKit.button(">", "IconButton", func(): _cycle(c, 1)))
		v.add_child(row)
		_names[cat] = n
		h.add_child(v)
	h.add_child(VSeparator.new())
	var cv := UiKit.vbox(4)
	cv.add_child(UiKit.label(Loc.t("camo_color").to_upper(), "StatLabel"))
	var ch := UiKit.hbox(6)
	cv.add_child(ch)
	for id in CAMOS:
		var cm: CamouflageData = GameSession.item("camos", id)
		if cm == null:
			continue
		var b := Button.new()
		b.theme_type_variation = "TabButton"
		b.custom_minimum_size = Vector2(58, 74)
		var sw := ColorRect.new()
		sw.color = Color(0.36, 0.38, 0.27) * cm.tint
		sw.custom_minimum_size = Vector2(46, 40)
		sw.position = Vector2(8, 6)
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(sw)
		var l := UiKit.label(cm.name, "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
		l.position = Vector2(0, 50)
		l.size = Vector2(58, 18)
		b.add_child(l)
		var cid: String = id
		b.pressed.connect(func(): _camo(cid))
		ch.add_child(b)
		_camo_btn[id] = b
	h.add_child(cv)
	EventBus.loadout_changed.connect(refresh)
	refresh()


func _owned(cat: String) -> Array:
	return GameSession.items("cosmetics").filter(func(it): return it.category == cat and Shop.owns_cosmetic(it))


func _cycle(cat: String, d: int) -> void:
	var l := GameSession.profile.loadout()
	var list := _owned(cat)
	if list.is_empty():
		return
	var i := 0
	for k in list.size():
		if list[k].id == l.items.get(cat, ""):
			i = k
	l.items[cat] = list[(i + d + list.size()) % list.size()].id
	GameSession.save()
	EventBus.loadout_changed.emit()


func _camo(id: String) -> void:
	var cm: CamouflageData = GameSession.item("camos", id)
	if not Shop.owns_cosmetic(cm):
		var d := ConfirmDialog.ask(get_tree().current_scene, cm.name, Loc.t("buy_confirm", [cm.name, UiKit.num(cm.price)]))
		d.answered.connect(func(yes: bool):
			if yes and Shop.buy_cosmetic(cm): _camo(id))
		return
	GameSession.profile.loadout().camo = id
	GameSession.save()
	EventBus.loadout_changed.emit()


func refresh() -> void:
	var l := GameSession.profile.loadout()
	for cat in _names:
		var it: CosmeticItem = GameSession.item("cosmetics", str(l.items.get(cat, "")))
		_names[cat].text = it.name if it else "-"
	for id in _camo_btn:
		var cm: CamouflageData = GameSession.item("camos", id)
		_camo_btn[id].theme_type_variation = "TabButtonActive" if l.camo == id else "TabButton"
		_camo_btn[id].tooltip_text = cm.name if Shop.owns_cosmetic(cm) else "%s - %s" % [cm.name, UiKit.num(cm.price)]
