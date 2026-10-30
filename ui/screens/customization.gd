## 5) SOLDIER CUSTOMIZATION: chapda kategoriyalar (UNIFORM, HELMET, VEST, BACKPACK, GLOVES, BOOTS, FACE, PATCH),
## o'rtada o'yindagi askar (to'liq 3D, sichqoncha bilan aylantirish, g'ildirak bilan yaqinlashtirish),
## o'ngda kategoriya variantlari (nom, qulf, narx) va kamuflyaj ranglari. Yuqorida jamoa a'zolari (3 loadout slot).
## SAVE LOADOUT / CANCEL. Hamma o'zgarish LoadoutApplier.apply orqali (jangda ham shunday ko'rinadi).
extends Control

const CATS := ["uniform", "helmet", "vest", "backpack", "gloves", "boots", "face", "patch"]

var _cat := "helmet"
var _slot := 0
var _work: SoldierLoadout
var _cats: VBoxContainer
var _grid: GridContainer
var _camos: HBoxContainer
var _members: HBoxContainer


func _ready() -> void:
	var body := ScreenFrame.build(self, "menu.customization", "soldier", Color("#A66BE0"), 0.0)
	_slot = GameSession.profile.active_loadout
	_work = SoldierLoadout.from_dict(GameSession.profile.loadout().to_dict())
	_cats = UiKit.vbox(6)
	_cats.custom_minimum_size = Vector2(250, 0)
	_cats.position = Vector2(0, 50)
	body.add_child(_cats)
	_members = UiKit.hbox(6)
	UiKit.pin_top_center(_members, 0)
	body.add_child(_members)
	var right := UiKit.vbox(10)
	right.anchor_left = 1.0; right.anchor_right = 1.0
	right.offset_left = -420; right.offset_right = 0; right.offset_top = 50
	body.add_child(right)
	var filt := OptionButton.new()
	filt.add_item(Loc.t("style.standard"))
	filt.tooltip_text = Loc.t("style_hint")
	right.add_child(filt)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	right.add_child(UiKit.titled(Loc.t("variants"), _grid))
	_camos = UiKit.hbox(6)
	right.add_child(UiKit.titled(Loc.t("camo_color"), _camos))
	var bt := UiKit.hbox(10)
	bt.anchor_left = 0.5; bt.anchor_right = 0.5; bt.anchor_top = 1.0; bt.anchor_bottom = 1.0
	bt.offset_left = -170; bt.offset_top = -56
	body.add_child(bt)
	bt.add_child(UiKit.button(Loc.t("cancel").to_upper(), "", _cancel))
	bt.add_child(UiKit.button(Loc.t("save_loadout").to_upper(), "AmberButton", _save))
	var hint := UiKit.label(Loc.t("rotate_hint"), "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
	hint.anchor_left = 0.5; hint.anchor_right = 0.5; hint.anchor_top = 1.0; hint.anchor_bottom = 1.0
	hint.offset_left = -200; hint.offset_right = 200; hint.offset_top = -86
	body.add_child(hint)
	_refresh()


func _preview() -> void:
	var root := get_tree().current_scene
	var pv: SoldierPreview = root.get("preview") if root else null
	if pv and pv.soldiers.size() > 1 and pv.soldiers[1].get_child_count() > 0:
		LoadoutApplier.apply(pv.soldiers[1].get_child(0), _work)


func _refresh() -> void:
	UiKit.clear(_members)
	var p: PlayerProfile = GameSession.profile
	p.loadout()
	for k in 3:
		var nm := Loc.t("member.player") if k == 0 else Loc.t("member.squad", [k + 1])
		var b := UiKit.button("%s  ·  %s" % [nm, p.loadouts[k].slot_name], "TabButtonActive" if k == _slot else "TabButton", func(): _select_slot(k))
		_members.add_child(b)
	UiKit.clear(_cats)
	for c in CATS:
		var it: CosmeticItem = GameSession.item("cosmetics", str(_work.items.get(c, "")))
		var b := UiKit.button("%s\n%s" % [Loc.t("cat." + c).to_upper(), it.name if it else "-"], "NavButtonActive" if c == _cat else "NavButton", func(): _cat = c; _refresh())
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(250, 52)
		b.add_theme_font_size_override("font_size", 15)
		_cats.add_child(b)
	UiKit.clear(_grid)
	var items: Array = GameSession.items("cosmetics").filter(func(it): return it.category == _cat)
	for it in items:
		_grid.add_child(_item_button(it, str(_work.items.get(_cat, "")) == it.id))
	if items.size() <= 1:
		var more := UiKit.soon(UiKit.button(Loc.t("more_items"), ""))
		_grid.add_child(more)
	UiKit.clear(_camos)
	for cm in GameSession.items("camos"):
		var b := Button.new()
		b.theme_type_variation = "TabButtonActive" if _work.camo == cm.id else "TabButton"
		b.custom_minimum_size = Vector2(62, 74)
		var sw := ColorRect.new()
		sw.color = Color(0.36, 0.38, 0.27) * cm.tint
		sw.custom_minimum_size = Vector2(46, 38)
		sw.position = Vector2(8, 6)
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(sw)
		var l := UiKit.label(cm.name if Shop.owns_cosmetic(cm) else "🔒 " + UiKit.num(cm.price), "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
		l.position = Vector2(0, 50)
		l.size = Vector2(62, 18)
		l.add_theme_font_size_override("font_size", 11)
		b.add_child(l)
		b.pressed.connect(func(): _pick(cm))
		_camos.add_child(b)
	_preview()


func _item_button(it: CosmeticItem, active: bool) -> Button:
	var own := Shop.owns_cosmetic(it)
	var b := UiKit.button("", "TabButtonActive" if active else "TabButton", func(): _pick(it))
	b.custom_minimum_size = Vector2(124, 96)
	var v := UiKit.vbox(2)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := UiIcon.make("lock" if not own else ({"helmet": "soldier", "vest": "crate", "gloves": "units", "boots": "units", "face": "soldier"}.get(it.category, "soldier")), 30, UiKit.DIM if not own else Color(0.85, 0.85, 0.83) * it.tint)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var n := UiKit.label(it.name, "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.custom_minimum_size = Vector2(116, 0)
	v.add_child(n)
	if not own:
		v.add_child(UiKit.label("%s  ·  Lv %d" % [UiKit.num(it.price), it.required_level], "AmberLabel", HORIZONTAL_ALIGNMENT_CENTER))
	b.add_child(v)
	return b


## Tanlash: egalik qilinmagan bo'lsa sotib olish so'raladi.
func _pick(it: Resource) -> void:
	if not Shop.owns_cosmetic(it):
		var d := ConfirmDialog.ask(get_tree().current_scene, str(it.name), Loc.t("buy_confirm", [it.name, UiKit.num(int(it.price))]))
		d.answered.connect(func(yes: bool):
			if yes and Shop.buy_cosmetic(it): _pick(it))
		return
	if it is CamouflageData:
		_work.camo = it.id
	else:
		_work.items[it.category] = it.id
	_refresh()


func _select_slot(k: int) -> void:
	_slot = k
	GameSession.profile.active_loadout = k
	_work = SoldierLoadout.from_dict(GameSession.profile.loadout().to_dict())
	EventBus.loadout_changed.emit()
	_refresh()


func _save() -> void:
	var p: PlayerProfile = GameSession.profile
	p.loadouts[_slot] = SoldierLoadout.from_dict(_work.to_dict())
	p.active_loadout = _slot
	Shop.track("loadouts_saved")
	GameSession.save()
	EventBus.loadout_changed.emit()
	EventBus.toast.emit(Loc.t("loadout_saved"))


func _cancel() -> void:
	_work = SoldierLoadout.from_dict(GameSession.profile.loadout().to_dict())
	_refresh()
