## Kampaniya / dunyo xaritasi ekrani (3D xarita ustidagi UI qatlami). Joylashuv rasmdagidek:
##   yuqori chap: logotip; chap: vertikal menyu; yuqori markaz: tablar; yuqori o'ng: o'yinchi paneli;
##   o'ng: GLOBAL TENSION va hudud ma'lumoti; pastda 4 panel (CURRENT CAMPAIGN, MISSION, SELECT FACTION,
##   MAP OPTIONS), yig'iladi. Hamma uslub ui/theme/main_theme.tres da. Qismlar EventBus orqali gaplashadi.
class_name CampaignScreen
extends CanvasLayer

const MENU := [["campaign", "menu.campaign", "campaign", true], ["world_map", "menu.world_map", "globe", true],
	["operations", "menu.operations", "target", true], ["armory", "menu.armory", "rifle", true],
	["garage", "menu.garage", "tank", true], ["customization", "menu.customization", "soldier", true],
	["base", "menu.base", "base", false], ["research", "menu.research", "research", false],
	["settings", "menu.settings", "gear", true], ["exit", "menu.exit", "exit", true]]

var map: Node
var root: Control
var bottom: HBoxContainer
var _right: VBoxContainer
var _menu: SideMenu
var _collapse: Button
var _end: Button
var _window: Control
var _collapsed := false
var _bottom_y := 0.0
var _goals: Label
var _due: Array = []                ## navbatdagi bot hujumlari (o'yinchi bittadan tanlaydi)


func setup(p_map: Node) -> void:
	map = p_map
	layer = 2
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.theme()
	add_child(root)
	var logo := GameLogo.make("subtitle", 40)
	logo.position = Vector2(22, 10)
	root.add_child(logo)
	_menu = SideMenu.make(MENU, "campaign")
	_menu.position = Vector2(20, 100)
	_menu.add_theme_constant_override("separation", 4)
	for b in _menu.get_children():
		b.custom_minimum_size = Vector2(250, 37)
		b.add_theme_font_size_override("font_size", 17)
	_menu.chosen.connect(_on_menu)
	root.add_child(_menu)
	var top_right := PlayerPanel.make("campaign", map)
	UiKit.pin_top_right(top_right, Vector2(16, 10))
	root.add_child(top_right)
	var tabs := TabsBar.new()
	UiKit.pin_top_center(tabs, 84, 10)
	root.add_child(tabs)
	_right = UiKit.vbox(10)
	UiKit.pin_top_right(_right, Vector2(16, 92))
	_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_right)
	_right.add_child(TensionPanel.make(map))
	_right.add_child(ProvincePanel.make(map))
	_build_bottom()
	var toasts := Toasts.new()
	UiKit.pin_top_center(toasts, 128, 10)
	root.add_child(toasts)
	EventBus.campaign_message.connect(toasts.show_text)
	EventBus.tab_changed.connect(_on_tab)
	EventBus.country_chosen.connect(func(_c): _end.visible = true)
	# urush maqsadlari (g'alaba sharti) tablar ostida
	_goals = UiKit.label("", "SmallLabel")
	_goals.add_theme_color_override("font_outline_color", Color.BLACK)
	_goals.add_theme_constant_override("outline_size", 4)
	UiKit.pin_top_center(_goals, 52)
	root.add_child(_goals)
	EventBus.campaign_changed.connect(_update_goals)
	map.rules.attack_due.connect(_on_attack_due)
	for c in root.get_children():
		UiKit.slide_in(c, 0.05 * c.get_index())
	_load_slot.call_deferred()


func _build_bottom() -> void:
	bottom = UiKit.hbox(10)
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 16
	bottom.offset_right = -16
	bottom.offset_top = -292
	bottom.offset_bottom = -12
	root.add_child(bottom)
	var panels: Array = [CampaignListPanel.make(map), MissionPanel.make(map), FactionPanel.make(map), MapOptionsPanel.new()]
	var ratios := [3.0, 5.2, 4.0, 2.2]
	for k in panels.size():
		panels[k].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panels[k].size_flags_stretch_ratio = ratios[k]
		bottom.add_child(panels[k])
	_collapse = UiKit.button("▼  " + Loc.t("hide_panels"), "TabButton", toggle_panels)
	_collapse.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_collapse.position = Vector2(-16 - 170, -292 - 34)
	_collapse.custom_minimum_size = Vector2(170, 30)
	root.add_child(_collapse)
	_end = UiKit.button(Loc.t("end_turn").to_upper(), "AmberButton", func(): map.end_turn())
	_end.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_end.position = Vector2(-16 - 170 - 190, -292 - 46)
	_end.custom_minimum_size = Vector2(180, 42)
	_end.visible = false
	root.add_child(_end)


## Pastki panellarni yig'ish / ochish (silliq).
func toggle_panels() -> void:
	_collapsed = not _collapsed
	var dy := 292.0 if _collapsed else 0.0
	var tw := root.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(bottom, "offset_top", -292 + dy, 0.35)
	tw.tween_property(bottom, "offset_bottom", -12 + dy, 0.35)
	tw.tween_property(_collapse, "position:y", root.size.y - 292 - 34 + dy, 0.35)
	tw.tween_property(_end, "position:y", root.size.y - 292 - 46 + dy, 0.35)
	_collapse.text = ("▲  " + Loc.t("show_panels")) if _collapsed else ("▼  " + Loc.t("hide_panels"))
	EventBus.panels_toggled.emit(_collapsed)


func _on_menu(id: String) -> void:
	match id:
		"campaign":
			if _collapsed: toggle_panels()
		"world_map":
			if not _collapsed: toggle_panels()
		"exit":
			_autosave()
			var d := ConfirmDialog.ask(root, Loc.t("menu.exit"), Loc.t("leave_campaign"), Loc.t("main_menu"), Loc.t("cancel"))
			d.answered.connect(func(yes: bool): if yes: ScreenManager.open("main"))
		_:
			_autosave()
			ScreenManager.open(id)


func _on_tab(id: String) -> void:
	if _window:
		_window.queue_free()
		_window = null
	match id:
		"economy": _window = EconomyWindow.make(map)
		"diplomacy": _window = DiplomacyWindow.make(map)
		"tactical", "factions":
			_window = UiKit.titled(Loc.t("tab." + id), UiKit.label(Loc.t("coming_soon_long"), "SmallLabel"))
			_window.custom_minimum_size = Vector2(460, 0)
	if _window:
		var c := CenterContainer.new()
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(c)
		c.add_child(_window)
		_window.tree_exited.connect(c.queue_free)
		UiKit.slide_in(_window)


## Yozuvlar shu panellar ostiga tushmasin (xarita yozuvlari va belgilar uchun).
## Ekranda UI egallagan joylar: xarita yozuvlari va qo'shin belgilari shu joylarga chizilmaydi
## (yarim shaffof panel orqasidan ko'rinib, chalkashlik qilmasin).
func blocked_rects() -> Array:
	var out := []
	for c in root.get_children():
		if not (c is Control) or not c.is_visible_in_tree() or c is Toasts:
			continue
		if c in [bottom, _right, _menu]:
			for ch in c.get_children():
				if ch is Control and ch.visible:
					out.append(ch.get_global_rect())
		else:
			var r: Rect2 = c.get_global_rect()
			if r.size.x > 1.0 and r.size.y > 1.0:
				out.append(r)
	return out


## Kampaniya ekranidagi kichik xaritada bosilgan joyga uchish.
func _fly_focus() -> void:
	var f: Vector2 = GameSession.campaign_focus
	if f.x < 0.0:
		return
	GameSession.campaign_focus = Vector2(-1, -1)
	map.cam.fly_to(map.px_to_world(f), 14.0)


func _update_goals() -> void:
	var r: CampaignRules = map.rules
	_goals.visible = r.phase == "play"
	if _goals.visible:
		var p := r.occupation.progress()
		_goals.text = Loc.t("victory.progress", [int(p.share * 100), int(p.need_share * 100), p.caps, p.need_caps])


## Bot hujumi yetib keldi: 3D himoya yoki avto-jang. Bir nechta bo'lsa navbat bilan.
func _on_attack_due(op: Dictionary) -> void:
	_due.append(op)
	if _due.size() == 1:
		_next_due.call_deferred()


func _next_due() -> void:
	if _due.is_empty():
		return
	var op: Dictionary = _due[0]
	var d: CampaignData = map.data
	var t := Loc.t("op.incoming", [d.provinces[op.to].name, Loc.country(d.countries.get(op.attacker)), int(op.count)])
	map.cam.focus(map.province_world(op.to))
	var dlg := ConfirmDialog.ask(root, Loc.t("op.title"), t, Loc.t("op.defend"), Loc.t("op.auto"))
	dlg.answered.connect(func(yes: bool):
		_due.pop_front()
		if yes:
			for o in _due:                      # qolganlari avto (3D jangga o'tilyapti)
				map.ops.resolve_auto(o)
			_due.clear()
		map.runner.run(op, not yes, yes)
		if not yes:
			_wait_runner())


func _wait_runner() -> void:
	while map.runner.busy():
		await get_tree().process_frame
	_next_due()


func _autosave() -> void:
	if map.rules.phase == "play":
		SaveManager.save_campaign(0, CampaignSave.to_dict(map.rules))


func _load_slot() -> void:
	var slot := GameSession.campaign_slot
	GameSession.campaign_slot = -1
	_fly_focus.call_deferred()
	if slot < 0:
		# yangi kampaniya: davlat tanlash ekranidagi davlat va sozlamalar bilan
		var st: Dictionary = GameSession.campaign_setup
		var cid := int(map.data.by_code.get(str(st.get("country", "")), 0))
		if cid > 0:
			map.rules.player_id = cid
			map.rules.apply_setup(st, true)
			map.choose_country(cid)
		return
	var d := SaveManager.load_campaign(slot)
	if not d.is_empty() and CampaignSave.from_dict(map.rules, d):
		map._apply_phase_look()
		map.cam.focus(map.province_world(map.data.countries[map.rules.player_id].capital))
		_end.visible = true
		EventBus.country_chosen.emit(map.rules.player_id)
		for p in map.data.provinces.values():
			map.labels.set_province_owner(p.id, p.owner)
		for c in map.data.countries:
			map.labels.mark_dirty(c)
		EventBus.campaign_changed.emit()
		BattleBridge.apply_pending(map)


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		root.get_viewport().set_input_as_handled()
		if _window:
			EventBus.tab_changed.emit("world_map")
		else:
			_on_menu("exit")
	elif e is InputEventKey and e.pressed and e.keycode == KEY_ENTER and map.rules.phase == "play":
		map.end_turn()
