## BOSH MENYU (o'yin ochilganda). Rasmdagidek:
##   chap: logotip va 1-7 menyu (CAMPAIGN, OPERATIONS, ARMORY, GARAGE, SOLDIER CUSTOMIZATION, SETTINGS, EXIT);
##   o'rta: o'yindagi 3 askar (SoldierPreview, main_root da); o'ng tepada: o'yinchi paneli;
##   o'ng: VEHICLE MARKET (3 karta + VIEW ALL); pastda o'rtada: tezkor loadout; chap pastda: LAST MISSION;
##   o'ng pastda: DEPLOY TO BATTLEFIELD.
extends Control

## [id, tarjima kaliti, ikonka, yoqilgan, bo'lim rangi]
const MENU := [["campaign", "menu.campaign", "campaign", true, Color("#E8C23A")],
	["operations", "menu.operations", "target", true, Color("#4E8FE0")],
	["armory", "menu.armory", "rifle", true, Color("#E05A4E")],
	["garage", "menu.garage", "tank", true, Color("#5DBE5A")],
	["customization", "menu.customization", "soldier", true, Color("#A66BE0")],
	["settings", "menu.settings", "gear", true, Color("#3EC1C9")],
	["exit", "menu.exit", "exit", true, Color("#9AA0A6")]]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var logo := GameLogo.make("menu_subtitle", 58)
	logo.position = Vector2(26, 18)
	add_child(logo)
	var items := MENU.map(func(m): return [m[0], m[1], m[2], m[3]])
	var menu := SideMenu.make(items, "")
	menu.position = Vector2(24, 150)
	for k in MENU.size():
		var b: Button = menu.get_child(k)
		b.custom_minimum_size = Vector2(300, 48)
		(b.get_child(0) as UiIcon).color = MENU[k][4]
		if MENU[k][0] == "exit" and GameSession.in_battle:
			b.text = "       " + Loc.t("back_to_menu").to_upper()
	menu.chosen.connect(_on_menu)
	add_child(menu)
	menu.get_child(0).grab_focus.call_deferred()
	var pp := PlayerPanel.make("profile")
	UiKit.pin_top_right(pp, Vector2(16, 12))
	add_child(pp)
	add_child(_market())
	# pastki qator: oxirgi missiya | tezkor loadout | DEPLOY (bitta konteynerda, bir-birini yopmaydi)
	var bottom := UiKit.hbox(16)
	bottom.anchor_left = 0.0; bottom.anchor_right = 1.0; bottom.anchor_top = 1.0; bottom.anchor_bottom = 1.0
	bottom.offset_left = 24; bottom.offset_right = -24; bottom.offset_top = -152; bottom.offset_bottom = -20
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(bottom)
	bottom.add_child(_last_mission())
	var ql := QuickLoadout.new()
	ql.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER
	bottom.add_child(ql)
	var dep := UiKit.button("▶  " + Loc.t("deploy"), "AmberButton", _deploy)
	dep.add_theme_font_size_override("font_size", 28)
	dep.custom_minimum_size = Vector2(340, 88)
	dep.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(dep)
	var k := 0
	for c in get_children():
		UiKit.slide_in(c, 0.04 * k)
		k += 1


func _market() -> Control:
	var p := UiKit.panel()
	UiKit.pin_top_right(p, Vector2(16, 96))
	p.custom_minimum_size = Vector2(430, 0)
	var v := UiKit.vbox(8)
	p.add_child(v)
	var h := UiKit.hbox()
	h.add_child(UiIcon.make("tank", 22, UiKit.AMBER))
	h.add_child(UiKit.label(Loc.t("vehicle_market").to_upper(), "PanelTitle"))
	h.add_child(UiKit.spacer())
	h.add_child(UiKit.button(Loc.t("view_all") + "  >", "", func(): ScreenManager.open("vehicles")))
	v.add_child(h)
	var list: Array = GameSession.items("vehicles").filter(func(x): return x.available)
	list.sort_custom(func(a, b): return a.price > b.price)
	for veh in list.slice(0, 3):
		v.add_child(VehicleCard.make(veh))
	return p


func _last_mission() -> Control:
	var p := UiKit.panel()
	var h := UiKit.hbox(12)
	p.add_child(h)
	var last := GameSession.profile.last_mission
	var op: OperationData = GameSession.item("operations", last)
	var img_box := UiKit.vbox(2)
	img_box.add_child(UiKit.label(Loc.t("last_mission").to_upper(), "SmallLabel"))
	img_box.add_child(UiKit.image_slot(op.image if op else null, Vector2(170, 76)))
	img_box.add_child(UiKit.label((Loc.t(op.name) if op else Loc.t("none")).to_upper(), "PanelTitle"))
	h.add_child(img_box)
	var b := UiKit.vbox(4)
	b.custom_minimum_size = Vector2(190, 0)
	b.add_child(UiKit.label(Loc.t("briefing").to_upper(), "StatLabel"))
	var t := UiKit.label(Loc.t(op.description) if op else Loc.t("no_last_mission"), "SmallLabel")
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_child(t)
	h.add_child(b)
	return p


func _on_menu(id: String) -> void:
	if id == "exit":
		ExitDialog.ask(get_tree().current_scene)
	else:
		ScreenManager.open(id)


## DEPLOY: tanlangan operatsiya (yoki oxirgi), loadout, qurol va texnika GameSession ga yoziladi va jang yuklanadi.
func _deploy() -> void:
	var id: String = GameSession.deploy.get("id", GameSession.profile.last_mission)
	var op: OperationData = GameSession.item("operations", id)
	if op == null or not op.available or op.battle_mode == "":
		EventBus.toast.emit(Loc.t("deploy_none"))
		ScreenManager.open("operations")
		return
	Deploy.start(op)
