extends Node
## CUSTOM BATTLE — the screen where the player builds the fight before it runs:
## map, season, weather, both orders of battle, victory condition, bot skill
## and length. Sandbox reuses the same screen with the clock switched off.

var sandbox_mode: bool = false

var map_id: String = "village"
var season_id: String = "summer"
var weather_id: String = "clear"
var victory_mode: String = "capture"
var difficulty: String = "normal"
var minutes: float = 15.0
var player_force: Dictionary = BattleSetup.default_force()
var enemy_force: Dictionary = BattleSetup.default_force()

var _map_buttons: Dictionary = {}
var _summary_a: Label
var _summary_b: Label
var _summary_line: Label
var _mode_hint: Label
var _slider_labels: Dictionary = {}

const FORCE_ROWS := [
	{"key": "infantry", "label": "Piyoda askarlar", "max": 80},
	{"key": "tanks", "label": "Tanklar", "max": 16},
	{"key": "transports", "label": "Transportlar", "max": 12},
	{"key": "artillery", "label": "Artilleriya", "max": 8},
	{"key": "aircraft", "label": "Aviatsiya", "max": 6},
]

func open(payload: Dictionary) -> void:
	sandbox_mode = bool(payload.get("sandbox", false))
	if sandbox_mode:
		minutes = 0.0
		difficulty = "easy"
	_build()
	_refresh_summary()

func _build() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	UIKit.fullscreen(bg)
	bg.color = UIKit.BG
	layer.add_child(bg)

	var center := CenterContainer.new()
	UIKit.fullscreen(center)
	layer.add_child(center)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(620, 860)
	center.add_child(scroll)

	var panel := UIKit.make_panel()
	panel.custom_minimum_size = Vector2(600, 0)
	scroll.add_child(panel)
	var col := UIKit.vbox(10)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(col)

	col.add_child(UIKit.label("SANDBOX" if sandbox_mode else "CUSTOM BATTLE", 26, UIKit.ACCENT))
	col.add_child(UIKit.label(
		"Erkin tajriba — vaqt chegarasiz, ta'minot cheksiz." if sandbox_mode
		else "Jang sozlamalari — o'zing xohlagan ikkita armiyani tuz.", 13, UIKit.MUTED))

	_section(col, "Xarita")
	col.add_child(_map_grid())

	_section(col, "Fasl")
	col.add_child(_season_row())

	_section(col, "Ob-havo")
	col.add_child(_weather_list())

	if not sandbox_mode:
		_section(col, "G'alaba sharti")
		col.add_child(_victory_list())
		_mode_hint = UIKit.label("", 12, UIKit.MUTED)
		_mode_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(_mode_hint)

	_section(col, "TEAM A — SENING JAMOANG")
	col.add_child(_force_block(player_force, "a"))

	var enemy_head := UIKit.hbox(8)
	enemy_head.add_child(UIKit.label("TEAM B — DUSHMAN", 16, UIKit.ACCENT))
	var badge := UIKit.label("Enemy AI", 12, UIKit.BAD)
	enemy_head.add_child(badge)
	col.add_child(UIKit.spacer(6))
	col.add_child(enemy_head)
	col.add_child(_force_block(enemy_force, "b"))

	_section(col, "Bot qiyinligi")
	col.add_child(_difficulty_row())

	if not sandbox_mode:
		_section(col, "Jang davomiyligi")
		col.add_child(_duration_row())

	_section(col, "Jang statistikasi")
	var stats_row := UIKit.hbox(30)
	var a_col := UIKit.vbox(2)
	_summary_a = UIKit.label("0", 24, UIKit.ACCENT)
	a_col.add_child(_summary_a)
	a_col.add_child(UIKit.label("TEAM A birliklari", 12, UIKit.MUTED))
	stats_row.add_child(a_col)
	var b_col := UIKit.vbox(2)
	_summary_b = UIKit.label("0", 24, UIKit.BAD)
	b_col.add_child(_summary_b)
	b_col.add_child(UIKit.label("TEAM B birliklari", 12, UIKit.MUTED))
	stats_row.add_child(b_col)
	col.add_child(stats_row)
	_summary_line = UIKit.label("", 12, UIKit.MUTED)
	col.add_child(_summary_line)

	col.add_child(UIKit.spacer(10))
	var start := UIKit.button("BATTLE BOSHLASH", 18)
	start.pressed.connect(_start)
	col.add_child(start)
	var back := UIKit.button(Loc.t("common.back"), 13)
	back.pressed.connect(func(): GameState.go("main_menu", {}))
	col.add_child(back)

func _section(parent: VBoxContainer, title: String) -> void:
	parent.add_child(UIKit.spacer(8))
	parent.add_child(UIKit.label(title, 15, UIKit.TEXT))

# ---------------------------------------------------------------------------
# Pickers
# ---------------------------------------------------------------------------

func _map_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	for mid in DB.battle_maps.keys():
		var cfg: Dictionary = DB.battle_map(str(mid))
		var b := UIKit.button(DB.local_name(cfg.get("name", {}), str(mid)), 14)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = DB.local_name(cfg.get("desc", {}), "")
		b.pressed.connect(_pick_map.bind(str(mid)))
		_map_buttons[str(mid)] = b
		grid.add_child(b)
	_pick_map(map_id)
	return grid

func _pick_map(id: String) -> void:
	map_id = id
	for mid in _map_buttons.keys():
		var b: Button = _map_buttons[mid]
		var selected: bool = str(mid) == id
		b.text = ("%s  " % DB.local_name(DB.battle_map(str(mid)).get("name", {}), str(mid))) \
			+ ("✓" if selected else "")
		b.add_theme_color_override("font_color", UIKit.ACCENT if selected else UIKit.TEXT)
	_refresh_summary()

func _season_row() -> HBoxContainer:
	var row := UIKit.hbox(6)
	var group := ButtonGroup.new()
	for sid in DB.season_ids():
		var cfg: Dictionary = DB.season(str(sid))
		var b := CheckBox.new()
		b.text = DB.local_name(cfg.get("title", {}), str(sid)).split(" — ")[0]
		b.button_group = group
		b.button_pressed = str(sid) == season_id
		b.toggled.connect(_on_season.bind(str(sid)))
		row.add_child(b)
	return row

func _on_season(pressed: bool, sid: String) -> void:
	if not pressed:
		return
	season_id = sid
	_refresh_summary()

func _weather_list() -> VBoxContainer:
	var box := UIKit.vbox(2)
	var group := ButtonGroup.new()
	for wid in DB.weather_table.keys():
		var cfg: Dictionary = DB.weather(str(wid))
		var b := CheckBox.new()
		b.text = "%s   (ko'rish %d%%, tezlik %d%%, aniqlik %d%%)" % [
			DB.local_name(cfg.get("name", {}), str(wid)),
			int(float(cfg.get("vision", 1.0)) * 100.0),
			int(float(cfg.get("speed", 1.0)) * 100.0),
			int(float(cfg.get("accuracy", 1.0)) * 100.0)]
		b.button_group = group
		b.button_pressed = str(wid) == weather_id
		b.toggled.connect(_on_weather.bind(str(wid)))
		box.add_child(b)
	return box

func _on_weather(pressed: bool, wid: String) -> void:
	if not pressed:
		return
	weather_id = wid
	_refresh_summary()

func _victory_list() -> VBoxContainer:
	var box := UIKit.vbox(2)
	var group := ButtonGroup.new()
	for vid in DB.victory_modes.keys():
		var cfg: Dictionary = DB.victory_mode(str(vid))
		var b := CheckBox.new()
		b.text = DB.local_name(cfg.get("name", {}), str(vid))
		b.button_group = group
		b.button_pressed = str(vid) == victory_mode
		b.toggled.connect(_on_victory.bind(str(vid)))
		box.add_child(b)
	return box

func _on_victory(pressed: bool, vid: String) -> void:
	if not pressed:
		return
	victory_mode = vid
	_refresh_summary()

func _difficulty_row() -> HBoxContainer:
	var row := UIKit.hbox(6)
	var group := ButtonGroup.new()
	for did in DB.difficulties.keys():
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = group
		b.text = DB.local_name(DB.difficulty(str(did)).get("name", {}), str(did))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 36)
		b.button_pressed = str(did) == difficulty
		b.toggled.connect(_on_difficulty.bind(str(did)))
		row.add_child(b)
	return row

func _on_difficulty(pressed: bool, did: String) -> void:
	if not pressed:
		return
	difficulty = did
	_refresh_summary()

func _duration_row() -> HBoxContainer:
	var row := UIKit.hbox(8)
	var group := ButtonGroup.new()
	for d in DB.durations:
		var mins := float(d.get("minutes", 15))
		var b := CheckBox.new()
		b.text = "Cheksiz" if mins <= 0.0 else "%d min" % int(mins)
		b.button_group = group
		b.button_pressed = is_equal_approx(mins, minutes)
		b.toggled.connect(_on_duration.bind(mins))
		row.add_child(b)
	return row

func _on_duration(pressed: bool, mins: float) -> void:
	if not pressed:
		return
	minutes = mins
	_refresh_summary()

# ---------------------------------------------------------------------------
# Order of battle
# ---------------------------------------------------------------------------

func _force_block(force: Dictionary, tag: String) -> VBoxContainer:
	var box := UIKit.vbox(4)
	for row_cfg in FORCE_ROWS:
		var key := str(row_cfg["key"])
		var row := UIKit.vbox(1)
		var head := UIKit.hbox(8)
		head.add_child(UIKit.label(str(row_cfg["label"]), 13))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(spacer)
		var value_label := UIKit.label(str(int(force.get(key, 0))), 13, UIKit.ACCENT)
		head.add_child(value_label)
		_slider_labels["%s_%s" % [tag, key]] = value_label
		row.add_child(head)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = int(row_cfg["max"])
		slider.step = 1
		slider.value = int(force.get(key, 0))
		slider.value_changed.connect(_on_force_changed.bind(force, key, value_label))
		row.add_child(slider)
		box.add_child(row)
	return box

func _on_force_changed(value: float, force: Dictionary, key: String, value_label: Label) -> void:
	force[key] = int(value)
	value_label.text = str(int(value))
	_refresh_summary()

func _refresh_summary() -> void:
	if _summary_a == null:
		return
	_summary_a.text = str(BattleSetup.unit_total(player_force))
	_summary_b.text = str(BattleSetup.unit_total(enemy_force))
	var season_title: String = DB.local_name(DB.season(season_id).get("title", {}), season_id)
	var parts: Array = [
		DB.local_name(DB.battle_map(map_id).get("name", {}), map_id),
		season_title,
		DB.local_name(DB.weather(weather_id).get("name", {}), weather_id),
		DB.local_name(DB.difficulty(difficulty).get("name", {}), difficulty),
	]
	if not sandbox_mode:
		parts.append("Cheksiz" if minutes <= 0.0 else "%d min" % int(minutes))
	_summary_line.text = " · ".join(parts)
	if _mode_hint != null:
		_mode_hint.text = DB.local_name(DB.victory_mode(victory_mode).get("desc", {}), "")

# ---------------------------------------------------------------------------

func _start() -> void:
	if BattleSetup.unit_total(player_force) <= 0 or BattleSetup.unit_total(enemy_force) <= 0:
		GameState.notify("Har ikkala jamoada kamida bitta bo'linma bo'lishi kerak.", "warn")
		return
	var options := {
		"title": "Sandbox" if sandbox_mode else "Custom Battle",
		"map": map_id, "season": season_id, "weather": weather_id,
		"victory_mode": victory_mode, "difficulty": difficulty,
		"minutes": minutes, "seed": randi(),
		"player_force": player_force, "enemy_force": enemy_force,
		"player_name": "TEAM A", "enemy_name": "TEAM B",
	}
	var cfg: Dictionary = BattleSetup.sandbox(options) if sandbox_mode else BattleSetup.build(options)
	GameState.mode = GameState.Mode.BATTLE_ARENA
	Net.start_offline()
	GameState.go("battle", cfg)
