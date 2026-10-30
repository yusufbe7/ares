extends Node
## After-action report: who won and why, what each side lost, and which unit
## type actually earned its place in the battle.

var _result: Dictionary = {}

const REASON_TEXT := {
	"annihilation": "Raqibning na maydonda, na zaxirada kuchi qoldi.",
	"elimination": "Dushman kuchlari butunlay yo'q qilindi.",
	"all_points": "Barcha nazorat nuqtalari ushlab turildi.",
	"zone_taken": "Mudofaa hududi egallandi.",
	"target_destroyed": "Shtab yo'q qilindi.",
	"time": "Vaqt tugadi.",
}

func open(payload: Dictionary) -> void:
	_result = payload

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
	scroll.custom_minimum_size = Vector2(760, 820)
	center.add_child(scroll)
	var panel := UIKit.make_panel()
	panel.custom_minimum_size = Vector2(740, 0)
	scroll.add_child(panel)
	var col := UIKit.vbox(8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(col)

	var won := bool(payload.get("player_won", false))
	col.add_child(UIKit.label(Loc.t("battle.victory") if won else Loc.t("battle.defeat"),
		34, UIKit.ACCENT if won else UIKit.BAD))
	col.add_child(UIKit.label(str(REASON_TEXT.get(str(payload.get("reason", "")), "")), 14, UIKit.MUTED))
	col.add_child(UIKit.label(_context_line(), 13, UIKit.MUTED))

	var stats: Dictionary = payload.get("stats", {})
	if stats.is_empty():
		_simple_summary(col)
	else:
		_stats_table(col, stats)
		_best_units(col, stats)

	col.add_child(UIKit.spacer(14))
	var cont := UIKit.button("DAVOM ETISH", 18)
	cont.pressed.connect(_continue)
	col.add_child(cont)
	var again := UIKit.button("YANA BIR BOR", 14)
	again.pressed.connect(func(): GameState.go("setup", {}))
	col.add_child(again)

func _context_line() -> String:
	var parts: Array = []
	var map_id := str(_result.get("map", ""))
	if map_id != "":
		parts.append(DB.local_name(DB.battle_map(map_id).get("name", {}), map_id))
	var season_id := str(_result.get("season", ""))
	if season_id != "":
		parts.append(DB.local_name(DB.season(season_id).get("title", {}), season_id))
	var weather_id := str(_result.get("weather", ""))
	if weather_id != "":
		parts.append(DB.local_name(DB.weather(weather_id).get("name", {}), weather_id))
	var mode_id := str(_result.get("victory_mode", ""))
	if mode_id != "":
		parts.append(DB.local_name(DB.victory_mode(mode_id).get("name", {}), mode_id))
	var elapsed := float(_result.get("stats", {}).get("elapsed", 0.0))
	if elapsed > 0.0:
		parts.append("%d:%02d" % [int(elapsed / 60.0), int(elapsed) % 60])
	return " · ".join(parts)

func _simple_summary(col: VBoxContainer) -> void:
	col.add_child(UIKit.label("G'olib: %s" % str(_result.get("winner", "?")), 16))
	col.add_child(UIKit.label("Hujumchi yo'qotishlari: %d%%"
		% int(float(_result.get("attacker_losses", 0.0)) * 100.0), 14))
	col.add_child(UIKit.label("Mudofaachi yo'qotishlari: %d%%"
		% int(float(_result.get("defender_losses", 0.0)) * 100.0), 14))

## The numbers players actually ask for after a fight.
func _stats_table(col: VBoxContainer, stats: Dictionary) -> void:
	var names: Array = stats.get("team_names", ["TEAM A", "TEAM B"])
	var player_team := int(_result.get("player_team", 0))
	var winner_team := int(_result.get("winner_team", 0))

	col.add_child(UIKit.spacer(10))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 4)
	col.add_child(grid)

	grid.add_child(UIKit.label("", 13))
	for team in range(2):
		var suffix := "  (siz)" if team == player_team else ""
		var crown := "  ★" if team == winner_team else ""
		grid.add_child(UIKit.label(str(names[team]) + suffix + crown, 15,
			UIKit.ACCENT if team == winner_team else UIKit.TEXT))

	var rows := [
		{"label": "Yo'q qilingan dushman", "key": "kills"},
		{"label": "Yo'qotilgan bo'linmalar", "key": "losses"},
		{"label": "Yo'qotilgan jonli kuch", "key": "men_lost"},
		{"label": "Yo'qotilgan texnika", "key": "vehicles_lost"},
		{"label": "Yo'qotilgan aviatsiya", "key": "aircraft_lost"},
		{"label": "Egallangan nuqtalar", "key": "points"},
	]
	for row in rows:
		grid.add_child(UIKit.label(str(row["label"]), 13, UIKit.MUTED))
		var values: Array = stats.get(str(row["key"]), [0, 0])
		for team in range(2):
			grid.add_child(UIKit.label(str(int(values[team])), 14))

	grid.add_child(UIKit.label("Yetkazilgan zarar", 13, UIKit.MUTED))
	var damage: Array = stats.get("damage", [0.0, 0.0])
	for team in range(2):
		grid.add_child(UIKit.label(str(int(float(damage[team]))), 14))

	grid.add_child(UIKit.label("Qolgan zaxira", 13, UIKit.MUTED))
	var tickets: Array = _result.get("tickets", [0, 0])
	for team in range(2):
		grid.add_child(UIKit.label(str(int(tickets[team])), 14))

func _best_units(col: VBoxContainer, stats: Dictionary) -> void:
	col.add_child(UIKit.spacer(12))
	col.add_child(UIKit.label("Eng samarali texnika", 18, UIKit.ACCENT))
	var names: Array = stats.get("team_names", ["TEAM A", "TEAM B"])
	var best: Array = stats.get("best_unit", ["", ""])
	var records: Array = stats.get("records", [])
	for team in range(2):
		var best_id: String = str(best[team]) if best.size() > team else ""
		if best_id == "":
			col.add_child(UIKit.label("%s — hisobga olinadigan natija yo'q." % str(names[team]), 13, UIKit.MUTED))
			continue
		var row := _find_record(records, team, best_id)
		col.add_child(UIKit.label("%s — %s" % [str(names[team]),
			DB.local_name(DB.unit(best_id).get("name", {}), best_id)], 15))
		col.add_child(UIKit.label("    %d yo'q qilish · %d zarar · %d yo'qotish"
			% [int(row.get("kills", 0)), int(float(row.get("damage", 0.0))), int(row.get("lost", 0))],
			12, UIKit.MUTED))

	col.add_child(UIKit.spacer(8))
	col.add_child(UIKit.label("Bo'linmalar bo'yicha", 16))
	var sorted_rows: Array = records.duplicate()
	sorted_rows.sort_custom(func(a, b): return int(a.get("kills", 0)) > int(b.get("kills", 0)))
	for row in sorted_rows:
		if int(row.get("kills", 0)) == 0 and int(row.get("lost", 0)) == 0:
			continue
		var uid := str(row.get("unit", ""))
		var team := int(row.get("team", 0))
		col.add_child(UIKit.label("%s · %s — chiqdi %d, yo'q qildi %d, yo'qotildi %d"
			% [str(names[team]), DB.local_name(DB.unit(uid).get("name", {}), uid),
			int(row.get("spawned", 0)), int(row.get("kills", 0)), int(row.get("lost", 0))],
			12, UIKit.MUTED))

func _find_record(records: Array, team: int, unit_id: String) -> Dictionary:
	for r in records:
		if int(r.get("team", -1)) == team and str(r.get("unit", "")) == unit_id:
			return r
	return {}

func _continue() -> void:
	GameState.go("setup", {})
