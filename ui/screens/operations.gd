## 2) OPERATIONS: yuqorida jang maydoni xaritasi (haqiqiy relyefdan) va operatsiya nuqtalari; rejim kartalari
## (RECON, DEFEND, ATTACK, ASSAULT, ESCORT - "Tez orada"); tezkor jang sozlamalari; kundalik / haftalik
## topshiriqlar (progress, mukofot, "Olish"). Onlayn lobbi va ochiq dunyo - "Tez orada".
extends Control

const ENTRY := Vector2(0.17, 0.75)
var _ops: Array = []
var _sel: OperationData
var _cards: HBoxContainer
var _map: Control
var _diff := 1
var _winter := true
var _tasks: VBoxContainer


func _ready() -> void:
	var body := ScreenFrame.build(self, "menu.operations", "target", Color("#4E8FE0"))
	_ops = GameSession.items("operations")
	_ops.sort_custom(func(a, b): return a.reward_credits < b.reward_credits)
	_sel = GameSession.item("operations", GameSession.profile.last_mission)
	if _sel == null and not _ops.is_empty():
		_sel = _ops[0]
	var h := UiKit.hbox(16)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.add_child(h)
	var left := UiKit.vbox(12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(left)
	var mp := UiKit.panel("CardPanel")
	mp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(mp)
	var tr := TextureRect.new()
	tr.texture = load("res://ui/operations_map.jpg") if ResourceLoader.exists("res://ui/operations_map.jpg") else null
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.custom_minimum_size = Vector2(500, 260)
	tr.clip_contents = true
	mp.add_child(tr)
	_map = Control.new()
	_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map.draw.connect(_draw_map)
	tr.add_child(_map)
	_cards = UiKit.hbox(10)
	left.add_child(_cards)
	var right := UiKit.vbox(12)
	right.custom_minimum_size = Vector2(380, 0)
	h.add_child(right)
	right.add_child(_settings())
	_tasks = UiKit.vbox(6)
	right.add_child(UiKit.titled(Loc.t("tasks"), _tasks))
	var on := UiKit.hbox(8)
	on.add_child(UiKit.soon(UiKit.button(Loc.t("online_lobby"), "")))
	on.add_child(UiKit.soon(UiKit.button(Loc.t("open_world"), "")))
	right.add_child(on)
	var go := UiKit.button("▶  " + Loc.t("deploy"), "AmberButton", _deploy)
	go.add_theme_font_size_override("font_size", 26)
	right.add_child(go)
	_refresh()


func _settings() -> Control:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 6)
	var add := func(k: String, c: Control):
		g.add_child(UiKit.label(Loc.t(k), "SmallLabel"))
		c.custom_minimum_size = Vector2(190, 0)
		g.add_child(c)
	var m := OptionButton.new()
	m.add_item(Loc.t("map.winter_village"))
	add.call("battle_map", m)
	var sides := OptionButton.new()
	sides.add_item(Loc.t("sides.default"))
	add.call("sides", sides)
	var d := OptionButton.new()
	for k in ["diff.1", "diff.2", "diff.3"]:
		d.add_item(Loc.t(k))
	d.select(_diff)
	d.item_selected.connect(func(i: int): _diff = i)
	add.call("difficulty", d)
	var s := OptionButton.new()
	s.add_item(Loc.t("season.winter"))
	s.add_item(Loc.t("season.summer"))
	s.item_selected.connect(func(i: int): _winter = i == 0)
	add.call("season", s)
	var t := UiKit.label("30:00", "PanelTitle")
	add.call("time_limit", t)
	var z := UiKit.label("3  (A / B / C)", "PanelTitle")
	add.call("points", z)
	var bot := CheckBox.new()
	bot.text = Loc.t("vs_bots")
	bot.button_pressed = true
	bot.disabled = true
	add.call("opponent", bot)
	return UiKit.titled(Loc.t("quick_battle"), g)


func _refresh() -> void:
	UiKit.clear(_cards)
	for op in _ops:
		var card := UiKit.panel("SelectedCard" if op == _sel else "CardPanel")
		card.custom_minimum_size = Vector2(170, 0)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := UiKit.vbox(4)
		card.add_child(v)
		v.add_child(UiKit.image_slot(op.image, Vector2(150, 70)))
		v.add_child(UiKit.label(Loc.t("opmode." + op.mode).to_upper(), "AmberLabel"))
		v.add_child(UiKit.label(Loc.t(op.name), "PanelTitle"))
		var dl := UiKit.label(Loc.t(op.description), "SmallLabel")
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.custom_minimum_size = Vector2(150, 0)
		v.add_child(dl)
		v.add_child(UiKit.label("+%s CR  ·  +%d XP" % [UiKit.num(op.reward_credits), op.reward_xp], "SmallLabel"))
		var b := UiKit.button(Loc.t("select"), "", func(): _sel = op; GameSession.deploy = {"id": op.id}; EventBus.operation_selected.emit(op.id); _refresh())
		if not op.available:
			UiKit.soon(b)
		v.add_child(b)
		_cards.add_child(card)
	UiKit.clear(_tasks)
	var tj: Dictionary = CampaignData._json("res://data/tasks.json", {})
	for t in tj.get("tasks", []):
		var have := int(GameSession.profile.daily.get(t.metric, 0))
		var goal := int(t.goal)
		var claimed: bool = GameSession.profile.daily.get("claimed_" + str(t.id), false)
		var row := UiKit.vbox(2)
		var hh := UiKit.hbox(8)
		hh.add_child(UiKit.label("[%s] %s" % [Loc.t("period." + str(t.period)), Loc.t(str(t.text), [goal])], "SmallLabel"))
		hh.add_child(UiKit.spacer())
		var cb := UiKit.button(Loc.t("claimed") if claimed else "%s  +%s" % [Loc.t("claim"), UiKit.num(int(t.reward))], "", func():
			GameSession.profile.daily["claimed_" + str(t.id)] = true
			GameSession.add_credits(int(t.reward))
			_refresh())
		cb.disabled = claimed or have < goal
		hh.add_child(cb)
		row.add_child(hh)
		var pb := ProgressBar.new()
		pb.custom_minimum_size = Vector2(0, 5)
		pb.show_percentage = false
		pb.value = 100.0 * mini(have, goal) / maxf(goal, 1)
		row.add_child(pb)
		_tasks.add_child(row)
	_map.queue_redraw()


## Operatsiya nuqtalari va bizning kirish nuqtamizdan yo'nalish chiziqlari.
func _draw_map() -> void:
	var sz := _map.size
	var entry := ENTRY * sz
	_map.draw_circle(entry, 7.0, Color(0.4, 0.8, 0.45))
	for op in _ops:
		var p: Vector2 = op.map_pos * sz
		var sel: bool = op == _sel
		var c := UiKit.AMBER if op.available else UiKit.DIM
		_map.draw_dashed_line(entry, p, Color(c, 0.8 if sel else 0.35), 2.0 if sel else 1.2, 9.0)
		_map.draw_circle(p, 9.0 if sel else 6.0, c)
		_map.draw_arc(p, 14.0, 0, TAU, 24, c, 2.0, true)
		_map.draw_string(ThemeDB.fallback_font, p + Vector2(16, 5), Loc.t("opmode." + op.mode).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


func _deploy() -> void:
	if _sel == null or not _sel.available:
		EventBus.toast.emit(Loc.t("deploy_none"))
		return
	Deploy.start(_sel)
	GameSession.deploy["enemy_reserve_mult"] = [0.75, 1.0, 1.35][_diff]
	GameSession.deploy["winter"] = _winter
