class_name BattleHUD
extends CanvasLayer
## The HUD is deliberately thin: how many men are left, what support is ready,
## and what this battle is being won on. Everything else is on the ground.

var battle: Battle
var controls: BattleControls

var _men_label: Label
var _wounded_label: Label
var _wounded_pill: PanelContainer
var _air_label: Label
var _nuke_label: Label
var _air_pill: PanelContainer
var _nuke_pill: PanelContainer
var _air_icon: HudIcon
var _nuke_icon: HudIcon
var _top_label: Label
var _objective_label: Label
var _objective_bar: ProgressBar
var _selection_box: VBoxContainer
var _feed_box: VBoxContainer
var _group_bar: HBoxContainer
var _selection_rect: Control
var _sandbox_panel: PanelContainer
var _rect: Rect2 = Rect2()
var _rect_active: bool = false

func setup(b: Battle, c: BattleControls) -> void:
	battle = b
	controls = c
	layer = 10
	_build()
	EventBus.selection_changed.connect(_on_selection)
	EventBus.combat_log.connect(_on_combat_log)
	controls.selection_box_changed.connect(_on_box)

func _build() -> void:
	_build_top()
	_build_objective()
	_build_bottom_bar()
	_build_feed()
	_build_selection_panel()
	_build_group_bar()

	_selection_rect = Control.new()
	_selection_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_selection_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selection_rect.draw.connect(_draw_selection_rect)
	add_child(_selection_rect)

	if battle.sandbox:
		_build_sandbox_panel()

## One compact strip at the top: the score, the clock and the conditions.
func _build_top() -> void:
	var panel := UIKit.make_panel(UIKit.PANEL)
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -520
	panel.offset_right = -10
	panel.offset_top = 10
	panel.offset_bottom = 46
	add_child(panel)
	var row := UIKit.hbox(14)
	panel.add_child(row)
	_top_label = UIKit.label("", 14)
	row.add_child(_top_label)
	var quit := UIKit.button("MENYU", 12)
	quit.custom_minimum_size = Vector2(80, 26)
	quit.pressed.connect(_leave)
	row.add_child(quit)

func _build_objective() -> void:
	var panel := UIKit.make_panel(UIKit.PANEL)
	panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	panel.offset_left = -250
	panel.offset_right = 250
	panel.offset_top = 10
	panel.offset_bottom = 66
	add_child(panel)
	var col := UIKit.vbox(3)
	panel.add_child(col)
	_objective_label = UIKit.label(battle.director.objective_text(battle.player_team), 13, UIKit.WARN)
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_objective_label)
	_objective_bar = UIKit.bar(0.0, 1.0, UIKit.ACCENT)
	col.add_child(_objective_bar)

## The bar from the reference footage: men left, air strike, nuke. Nothing else
## sits across the bottom of the screen.
func _build_bottom_bar() -> void:
	var bar := UIKit.hbox(8)
	bar.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bar.offset_left = 12
	bar.offset_top = -46
	bar.offset_right = 520
	bar.offset_bottom = -10
	add_child(bar)

	_wounded_pill = UIKit.make_panel(UIKit.PANEL)
	var wounded_row := UIKit.hbox(6)
	_wounded_pill.add_child(wounded_row)
	wounded_row.add_child(UIKit.label("YARADOR", 13, UIKit.MUTED))
	_wounded_label = UIKit.label("0", 17, UIKit.WARN)
	wounded_row.add_child(_wounded_label)

	var men_pill := UIKit.make_panel(UIKit.PANEL)
	var men_row := UIKit.hbox(6)
	men_pill.add_child(men_row)
	men_row.add_child(HudIcon.make(HudIcon.Kind.MEN, UIKit.TEXT))
	men_row.add_child(UIKit.label("MEN", 13, UIKit.MUTED))
	_men_label = UIKit.label("0", 17, UIKit.TEXT)
	men_row.add_child(_men_label)
	bar.add_child(men_pill)
	bar.add_child(_wounded_pill)

	_air_pill = UIKit.make_panel(UIKit.PANEL)
	var air_row := UIKit.hbox(6)
	_air_pill.add_child(air_row)
	_air_icon = HudIcon.make(HudIcon.Kind.PLANE, UIKit.ACCENT)
	air_row.add_child(_air_icon)
	air_row.add_child(UIKit.label("AIR STRIKE", 13, UIKit.MUTED))
	_air_label = UIKit.label(Settings.key_name("bf_air_strike"), 13, UIKit.ACCENT)
	air_row.add_child(_air_label)
	bar.add_child(_air_pill)

	_nuke_pill = UIKit.make_panel(UIKit.PANEL)
	var nuke_row := UIKit.hbox(6)
	_nuke_pill.add_child(nuke_row)
	_nuke_icon = HudIcon.make(HudIcon.Kind.NUKE, UIKit.BAD)
	nuke_row.add_child(_nuke_icon)
	nuke_row.add_child(UIKit.label("NUKE", 13, UIKit.MUTED))
	_nuke_label = UIKit.label(Settings.key_name("bf_nuke"), 13, UIKit.BAD)
	nuke_row.add_child(_nuke_label)
	bar.add_child(_nuke_pill)

## A short feed of what is happening to the player's own soldiers, by name.
func _build_feed() -> void:
	var panel := UIKit.make_panel(UIKit.PANEL)
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 12
	panel.offset_top = -270
	panel.offset_right = 400
	panel.offset_bottom = -176
	add_child(panel)
	_feed_box = UIKit.vbox(1)
	panel.add_child(_feed_box)

func _on_combat_log(text: String, kind: String) -> void:
	if _feed_box == null:
		return
	var l := UIKit.label(text, 11, UIKit.color_for_kind(kind))
	_feed_box.add_child(l)
	while _feed_box.get_child_count() > 5:
		var oldest := _feed_box.get_child(0)
		_feed_box.remove_child(oldest)
		oldest.queue_free()
	var t := get_tree().create_timer(9.0)
	t.timeout.connect(func():
		if is_instance_valid(l):
			l.queue_free())

func _build_selection_panel() -> void:
	var panel := UIKit.make_panel(UIKit.PANEL)
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 12
	panel.offset_top = -170
	panel.offset_right = 360
	panel.offset_bottom = -54
	add_child(panel)
	_selection_box = UIKit.vbox(3)
	panel.add_child(_selection_box)
	_on_selection([])

func _build_group_bar() -> void:
	var panel := UIKit.make_panel(UIKit.PANEL)
	panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.offset_left = -430
	panel.offset_top = -80
	panel.offset_right = -10
	panel.offset_bottom = -10
	add_child(panel)
	var col := UIKit.vbox(4)
	panel.add_child(col)
	_group_bar = UIKit.hbox(4)
	col.add_child(_group_bar)
	col.add_child(UIKit.label(
		"1-5 guruh (Ctrl bilan tuzish) · %s otryad · %s tank · %s artilleriya · %s xandaq"
		% [Settings.key_name("bf_reinforce"), Settings.key_name("bf_call_tank"),
		Settings.key_name("bf_call_artillery"), Settings.key_name("bf_dig_trench")],
		11, UIKit.MUTED))

## Sandbox only: drop any unit on either side without building a whole battle.
func _build_sandbox_panel() -> void:
	_sandbox_panel = UIKit.make_panel(UIKit.PANEL)
	_sandbox_panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_sandbox_panel.offset_left = 12
	_sandbox_panel.offset_right = 262
	_sandbox_panel.offset_top = -240
	_sandbox_panel.offset_bottom = 200
	add_child(_sandbox_panel)
	var col := UIKit.vbox(3)
	_sandbox_panel.add_child(col)
	col.add_child(UIKit.label("SANDBOX", 15, UIKit.ACCENT))
	for team in range(2):
		col.add_child(UIKit.label(battle.team_name(team), 12, battle.team_color(team)))
		var grid := GridContainer.new()
		grid.columns = 2
		col.add_child(grid)
		for uid in DB.units.keys():
			var b := UIKit.button(DB.local_name(DB.unit(str(uid)).get("name", {}), str(uid)), 10)
			b.custom_minimum_size = Vector2(0, 24)
			b.pressed.connect(_sandbox_spawn.bind(team, str(uid)))
			grid.add_child(b)

func _sandbox_spawn(team: int, unit_id: String) -> void:
	var base := battle.spawn_point_for(team)
	var offset := Vector3(randf_range(-20, 20), 0, randf_range(-20, 20))
	battle.spawn_unit(team, unit_id, battle.terrain.clamp_to_map(base + offset))

# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if battle == null or battle.director == null:
		return
	var d := battle.director
	_men_label.text = str(d.men_alive(battle.player_team, battle.units))
	var down := 0
	for w in battle.wounded_units:
		if is_instance_valid(w) and w.wounded and w.team == battle.player_team:
			down += 1
	_wounded_label.text = str(down)
	_wounded_pill.visible = down > 0

	var air_ready := d.air_strike_ready(battle.player_team)
	_air_label.text = Settings.key_name("bf_air_strike") if air_ready \
		else "%ds" % int(d.air_strike_cd[battle.player_team])
	_air_label.add_theme_color_override("font_color", UIKit.ACCENT if air_ready else UIKit.MUTED)
	_air_icon.color = UIKit.ACCENT if air_ready else UIKit.MUTED
	_air_icon.queue_redraw()
	var nuke_ready := d.nuke_ready(battle.player_team)
	_nuke_label.text = Settings.key_name("bf_nuke") if nuke_ready else "—"
	_nuke_label.add_theme_color_override("font_color", UIKit.BAD if nuke_ready else UIKit.MUTED)
	_nuke_icon.color = UIKit.BAD if nuke_ready else UIKit.MUTED
	_nuke_icon.queue_redraw()

	var left := d.time_left()
	var clock := "∞" if is_inf(left) else "%02d:%02d" % [int(left / 60.0), int(left) % 60]
	var points := ""
	for p in d.points:
		points += p.id + " "
	_top_label.text = "%s %d  ·  %s %d  ·  %s  ·  %s %d" % [
		battle.team_name(0), d.tickets[0],
		battle.team_name(1), d.tickets[1],
		clock, Loc.t("battle.supply"), int(d.supply[battle.player_team])]

	var progress := d.objective_progress(battle.player_team)
	_objective_bar.visible = progress >= 0.0
	if progress >= 0.0:
		_objective_bar.value = progress
	_refresh_groups()

func _refresh_groups() -> void:
	if _group_bar.get_child_count() != battle.squads.size():
		for c in _group_bar.get_children():
			c.queue_free()
		for i in range(battle.squads.size()):
			var b := UIKit.button("", 11)
			b.custom_minimum_size = Vector2(78, 26)
			b.pressed.connect(func(): controls.select_squad(i))
			_group_bar.add_child(b)
		return
	for i in range(battle.squads.size()):
		var btn: Button = _group_bar.get_child(i)
		btn.text = "%d  %d" % [i + 1, battle.squads[i].size()]
		btn.tooltip_text = battle.squads[i].auto_label()

func _on_selection(units: Array) -> void:
	for c in _selection_box.get_children():
		c.queue_free()
	if units.is_empty():
		_selection_box.add_child(UIKit.label(
			"Sudrab tanlang · o'ng tugma: yurish yoki hujum", 12, UIKit.MUTED))
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
	if units.size() == 1:
		_selection_box.add_child(UIKit.label(units[0].soldier_name, 15, UIKit.ACCENT))
	else:
		_selection_box.add_child(UIKit.label("Tanlangan: %d" % units.size(), 15, UIKit.ACCENT))
	var line := ""
	for uid in counts.keys():
		line += "%s x%d   " % [DB.local_name(DB.unit(str(uid)).get("name", {}), str(uid)), int(counts[uid])]
	var l := UIKit.label(line, 12)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_selection_box.add_child(l)
	_selection_box.add_child(UIKit.bar(hp_sum, maxf(hp_max, 1.0), UIKit.ACCENT))
	if suppressed > 0:
		_selection_box.add_child(UIKit.label("Bosim ostida: %d" % suppressed, 12, UIKit.WARN))

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
	GameState.go("setup", {})
