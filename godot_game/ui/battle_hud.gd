class_name BattleHUD
extends CanvasLayer
## Everything the commander reads at a glance: the reserve both sides are
## bleeding, who holds which point, supply, the clock, the current selection and
## the build menu.

var battle: Battle
var controls: BattleControls

var _tickets_labels: Array = []
var _points_box: HBoxContainer
var _time_label: Label
var _supply_label: Label
var _cover_label: Label
var _selection_box: VBoxContainer
var _group_bar: HBoxContainer
var _selection_rect: Control
var _objective_label: Label
var _objective_bar: ProgressBar
var _sandbox_panel: PanelContainer
var _rect: Rect2 = Rect2()
var _rect_active: bool = false
var _build_panel: PanelContainer

func setup(b: Battle, c: BattleControls) -> void:
	battle = b
	controls = c
	layer = 10
	_build()
	EventBus.tickets_changed.connect(_on_tickets)
	EventBus.supply_changed.connect(_on_supply)
	EventBus.selection_changed.connect(_on_selection)
	controls.selection_box_changed.connect(_on_box)
	controls.build_menu_requested.connect(_toggle_build_menu)

func _build() -> void:
	var top := UIKit.make_panel(UIKit.PANEL)
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 54
	add_child(top)
	var row := UIKit.hbox(18)
	top.add_child(row)

	for i in range(2):
		var l := UIKit.label("", 16, battle.team_color(i))
		_tickets_labels.append(l)
		row.add_child(l)
	_points_box = UIKit.hbox(6)
	row.add_child(_points_box)
	_time_label = UIKit.label("", 15)
	row.add_child(_time_label)
	_supply_label = UIKit.label("", 15, UIKit.ACCENT)
	row.add_child(_supply_label)
	_cover_label = UIKit.label("", 13, UIKit.MUTED)
	row.add_child(_cover_label)
	var weather := UIKit.label("%s / %s" % [battle.season, battle.weather], 13, UIKit.MUTED)
	row.add_child(weather)

	var quit := UIKit.button("CHIQISH", 13)
	quit.custom_minimum_size = Vector2(100, 30)
	quit.pressed.connect(_leave)
	row.add_child(quit)

	# What this side has to do to win, and how close it is to doing it.
	var obj_panel := UIKit.make_panel(UIKit.PANEL)
	obj_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	obj_panel.offset_left = -280
	obj_panel.offset_right = 280
	obj_panel.offset_top = 58
	obj_panel.offset_bottom = 116
	add_child(obj_panel)
	var obj_col := UIKit.vbox(3)
	obj_panel.add_child(obj_col)
	_objective_label = UIKit.label(battle.director.objective_text(battle.player_team), 13, UIKit.WARN)
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	obj_col.add_child(_objective_label)
	_objective_bar = UIKit.bar(0.0, 1.0, UIKit.ACCENT)
	obj_col.add_child(_objective_bar)

	if battle.sandbox:
		_build_sandbox_panel()

	# Bottom left: what is selected and what it is doing.
	var bottom := UIKit.make_panel(UIKit.PANEL)
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bottom.offset_top = -170
	bottom.offset_right = 420
	bottom.offset_bottom = -8
	bottom.offset_left = 8
	add_child(bottom)
	_selection_box = UIKit.vbox(3)
	bottom.add_child(_selection_box)

	# Bottom right: control groups and the key reminders.
	var right := UIKit.make_panel(UIKit.PANEL)
	right.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	right.offset_left = -420
	right.offset_top = -170
	right.offset_right = -8
	right.offset_bottom = -8
	add_child(right)
	var rcol := UIKit.vbox(4)
	right.add_child(rcol)
	_group_bar = UIKit.hbox(4)
	rcol.add_child(_group_bar)
	rcol.add_child(UIKit.label(
		"%s otryad · %s tank · %s artilleriya · %s qurilish"
		% [Settings.key_name("bf_reinforce"), Settings.key_name("bf_call_tank"),
		Settings.key_name("bf_call_artillery"), Settings.key_name("bf_build_menu")], 12, UIKit.MUTED))
	rcol.add_child(UIKit.label(
		"%s xandaq · %s granata · %s RPG · %s dron · 1-5 guruh (Ctrl bilan tuzish)"
		% [Settings.key_name("bf_dig_trench"), Settings.key_name("bf_grenade"),
		Settings.key_name("bf_rocket"), Settings.key_name("bf_recon")], 12, UIKit.MUTED))

	_selection_rect = Control.new()
	_selection_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_selection_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selection_rect.draw.connect(_draw_selection_rect)
	add_child(_selection_rect)

	_build_build_menu()

func _build_build_menu() -> void:
	_build_panel = UIKit.make_panel(UIKit.PANEL)
	_build_panel.set_anchors_preset(Control.PRESET_CENTER)
	_build_panel.offset_left = -170
	_build_panel.offset_right = 170
	_build_panel.offset_top = -150
	_build_panel.offset_bottom = 150
	_build_panel.visible = false
	add_child(_build_panel)
	var col := UIKit.vbox(6)
	_build_panel.add_child(col)
	col.add_child(UIKit.label("QURILISH", 20, UIKit.ACCENT))
	for fid in DB.fortifications.keys():
		var f: Dictionary = DB.fortifications[fid]
		var cost := int(f.get("cost", f.get("cost_per_m", 1)))
		var b := UIKit.button("%s (%d)" % [DB.local_name(f.get("name", ""), str(fid)), cost], 14)
		b.pressed.connect(func():
			_build_panel.visible = false
			if str(fid) == "trench":
				controls.pending = BattleControls.Pending.TRENCH
				controls._has_trench_start = false
				GameState.notify("Xandaqning boshini belgilang.", "info")
			else:
				controls.build_fortification(str(fid)))
		col.add_child(b)
	var close := UIKit.button("Yopish", 13)
	close.pressed.connect(func(): _build_panel.visible = false)
	col.add_child(close)

## Sandbox only: a panel that drops any unit in the game onto the map so the
## player can try matchups without setting up a whole battle.
func _build_sandbox_panel() -> void:
	_sandbox_panel = UIKit.make_panel(UIKit.PANEL)
	_sandbox_panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_sandbox_panel.offset_left = 8
	_sandbox_panel.offset_right = 250
	_sandbox_panel.offset_top = -230
	_sandbox_panel.offset_bottom = 230
	add_child(_sandbox_panel)
	var col := UIKit.vbox(3)
	_sandbox_panel.add_child(col)
	col.add_child(UIKit.label("SANDBOX", 16, UIKit.ACCENT))
	col.add_child(UIKit.label("Bosing — bo'linma qo'shiladi.", 11, UIKit.MUTED))
	for team in range(2):
		col.add_child(UIKit.label("Jamoa %d" % (team + 1), 13, battle.team_color(team)))
		var grid := GridContainer.new()
		grid.columns = 2
		col.add_child(grid)
		for uid in DB.units.keys():
			var b := UIKit.button(DB.local_name(DB.unit(str(uid)).get("name", {}), str(uid)), 11)
			b.custom_minimum_size = Vector2(0, 26)
			b.pressed.connect(_sandbox_spawn.bind(team, str(uid)))
			grid.add_child(b)

func _sandbox_spawn(team: int, unit_id: String) -> void:
	var base := battle.spawn_point_for(team)
	var offset := Vector3(randf_range(-20, 20), 0, randf_range(-20, 20))
	var u := battle.spawn_unit(team, unit_id, battle.terrain.clamp_to_map(base + offset))
	if u != null:
		GameState.notify("%s qo'shildi." % DB.local_name(DB.unit(unit_id).get("name", {}), unit_id), "good")

func _toggle_build_menu(_open: bool) -> void:
	_build_panel.visible = not _build_panel.visible

func _process(_delta: float) -> void:
	if battle == null or battle.director == null:
		return
	var d := battle.director
	for i in range(2):
		var who := "Siz" if i == battle.player_team else "Dushman"
		_tickets_labels[i].text = "%s: %d" % [who, d.tickets[i]]
	for c in _points_box.get_children():
		c.queue_free()
	for p in d.points:
		var col: Color = battle.team_color(p.owner_team) if p.owner_team >= 0 else UIKit.MUTED
		var l := UIKit.label(p.id, 18, col)
		if p.contested:
			l.add_theme_color_override("font_color", UIKit.WARN)
		_points_box.add_child(l)
	var left := d.time_left()
	_time_label.text = "∞" if is_inf(left) else "%02d:%02d" % [int(left / 60.0), int(left) % 60]
	if _objective_bar != null:
		var progress := d.objective_progress(battle.player_team)
		_objective_bar.visible = progress >= 0.0
		if progress >= 0.0:
			_objective_bar.value = progress
	_supply_label.text = "%s %d" % [Loc.t("battle.supply"), int(d.supply[battle.player_team])]
	var cd := d.reinforce_cooldown(battle.player_team)
	if cd > 0.0:
		_supply_label.text += "   (otryad %ds)" % int(cd)
	_cover_label.text = "Pana nuqtalari: %d" % battle.cover.slot_count()
	_refresh_groups()

func _refresh_groups() -> void:
	if _group_bar.get_child_count() == battle.squads.size():
		for i in range(battle.squads.size()):
			var btn: Button = _group_bar.get_child(i)
			btn.text = "%d: %s (%d)" % [i + 1, battle.squads[i].auto_label(), battle.squads[i].size()]
		return
	for c in _group_bar.get_children():
		c.queue_free()
	for i in range(battle.squads.size()):
		var b := UIKit.button("", 12)
		b.custom_minimum_size = Vector2(76, 28)
		b.pressed.connect(func():
			controls._set_selection(battle.squads[i].alive_units()))
		_group_bar.add_child(b)

func _on_tickets(_team: int, _value: int) -> void:
	pass

func _on_supply(_team: int, _value: float) -> void:
	pass

func _on_selection(units: Array) -> void:
	for c in _selection_box.get_children():
		c.queue_free()
	if units.is_empty():
		_selection_box.add_child(UIKit.label("Hech kim tanlanmagan.", 14, UIKit.MUTED))
		return
	var counts: Dictionary = {}
	var hp_sum := 0.0
	var hp_max := 0.0
	var suppressed := 0
	for u in units:
		counts[u.unit_id] = int(counts.get(u.unit_id, 0)) + 1
		hp_sum += u.hp
		hp_max += u.max_hp
		if u.suppression > 0.4:
			suppressed += 1
	_selection_box.add_child(UIKit.label("Tanlangan: %d bo'linma" % units.size(), 16, UIKit.ACCENT))
	for uid in counts.keys():
		_selection_box.add_child(UIKit.label("  %s x%d"
			% [DB.local_name(DB.unit(str(uid)).get("name", ""), str(uid)), int(counts[uid])], 13))
	_selection_box.add_child(UIKit.bar(hp_sum, maxf(hp_max, 1.0), UIKit.ACCENT))
	if suppressed > 0:
		_selection_box.add_child(UIKit.label("Bosim ostida: %d" % suppressed, 13, UIKit.WARN))

func _on_box(rect: Rect2, active: bool) -> void:
	_rect = rect
	_rect_active = active
	_selection_rect.queue_redraw()

func _draw_selection_rect() -> void:
	if not _rect_active:
		return
	_selection_rect.draw_rect(_rect, Color(0.4, 0.9, 0.6, 0.12))
	_selection_rect.draw_rect(_rect, Color(0.4, 0.9, 0.6, 0.8), false, 1.5)

func _leave() -> void:
	if GameState.mode == GameState.Mode.GLOBAL_WAR:
		GameState.go("world", {})
	else:
		GameState.go("main_menu", {})
