extends Node
## CAMPAIGN — a fixed run of missions, each one unlocked by winning the one
## before it. Every mission is just a battle config, so nothing here duplicates
## the battle code.

var _detail: VBoxContainer
var _selected: Dictionary = {}

func open(_payload: Dictionary) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	UIKit.fullscreen(bg)
	bg.color = UIKit.BG
	layer.add_child(bg)

	var margin := MarginContainer.new()
	UIKit.fullscreen(margin)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	layer.add_child(margin)

	var cols := UIKit.hbox(24)
	margin.add_child(cols)

	var left := UIKit.vbox(8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	left.add_child(UIKit.title(DB.local_name(DB.campaign_name, "CAMPAIGN")))
	var done: int = GameState.completed_missions.size()
	left.add_child(UIKit.label("Bajarilgan: %d / %d" % [done, DB.missions.size()], 13, UIKit.MUTED))
	left.add_child(UIKit.bar(float(done), maxf(float(DB.missions.size()), 1.0), UIKit.ACCENT))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(scroll)
	var list := UIKit.vbox(4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for m in DB.missions:
		var mid := str(m.get("id", ""))
		var unlocked := GameState.mission_unlocked(mid)
		var completed: bool = GameState.completed_missions.has(mid)
		var mark := "✓" if completed else ("" if unlocked else "🔒")
		var b := UIKit.button("%d. %s  %s" % [int(m.get("order", 0)),
			DB.local_name(m.get("name", {}), mid), mark], 14)
		b.disabled = not unlocked
		if completed:
			b.add_theme_color_override("font_color", UIKit.ACCENT)
		b.pressed.connect(_select.bind(m))
		list.add_child(b)

	var back := UIKit.button(Loc.t("common.back"), 13)
	back.pressed.connect(func(): GameState.go("main_menu", {}))
	left.add_child(back)

	var right := UIKit.make_panel()
	right.custom_minimum_size = Vector2(460, 0)
	cols.add_child(right)
	_detail = UIKit.vbox(6)
	right.add_child(_detail)

	if not DB.missions.is_empty():
		_select(DB.missions[0])

func _select(mission: Dictionary) -> void:
	_selected = mission
	for c in _detail.get_children():
		c.queue_free()
	var mid := str(mission.get("id", ""))
	_detail.add_child(UIKit.label(DB.local_name(mission.get("name", {}), mid), 22, UIKit.ACCENT))
	var brief := UIKit.label(DB.local_name(mission.get("brief", {}), ""), 13)
	brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(brief)
	_detail.add_child(UIKit.spacer(6))

	var map_cfg: Dictionary = DB.battle_map(str(mission.get("map", "village")))
	var season_title: String = DB.local_name(DB.season(str(mission.get("season", "summer"))).get("title", {}), "")
	_detail.add_child(UIKit.label("Xarita: %s" % DB.local_name(map_cfg.get("name", {}), ""), 13))
	_detail.add_child(UIKit.label("Fasl: %s" % season_title, 13))
	_detail.add_child(UIKit.label("Ob-havo: %s"
		% DB.local_name(DB.weather(str(mission.get("weather", "clear"))).get("name", {}), ""), 13))
	var mode: Dictionary = DB.victory_mode(str(mission.get("victory_mode", "capture")))
	_detail.add_child(UIKit.label("G'alaba sharti: %s" % DB.local_name(mode.get("name", {}), ""), 13, UIKit.WARN))
	var mode_desc := UIKit.label(DB.local_name(mode.get("desc", {}), ""), 12, UIKit.MUTED)
	mode_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(mode_desc)
	_detail.add_child(UIKit.label("Qiyinlik: %s"
		% DB.local_name(DB.difficulty(str(mission.get("difficulty", "normal"))).get("name", {}), ""), 13))
	_detail.add_child(UIKit.label("Davomiylik: %d daqiqa" % int(float(mission.get("duration", 900)) / 60.0), 13))

	_detail.add_child(UIKit.spacer(6))
	var player: Dictionary = mission.get("player", {})
	var enemy: Dictionary = mission.get("enemy", {})
	_detail.add_child(UIKit.label("Sizning kuchlaringiz: %d birlik" % BattleSetup.unit_total(player), 14, UIKit.ACCENT))
	_detail.add_child(UIKit.label(_force_line(player), 12, UIKit.MUTED))
	_detail.add_child(UIKit.label("Dushman: %d birlik" % BattleSetup.unit_total(enemy), 14, UIKit.BAD))
	_detail.add_child(UIKit.label(_force_line(enemy), 12, UIKit.MUTED))

	_detail.add_child(UIKit.spacer(10))
	var start := UIKit.button(Loc.t("battle.deploy"), 18)
	start.disabled = not GameState.mission_unlocked(mid)
	start.pressed.connect(_launch)
	_detail.add_child(start)
	if not GameState.mission_unlocked(mid):
		_detail.add_child(UIKit.label("Oldingi missiyani yakunlang.", 12, UIKit.WARN))

func _force_line(force: Dictionary) -> String:
	return "Piyoda %d · Tank %d · Transport %d · Artilleriya %d · Aviatsiya %d" % [
		int(force.get("infantry", 0)), int(force.get("tanks", 0)),
		int(force.get("transports", 0)), int(force.get("artillery", 0)),
		int(force.get("aircraft", 0))]

func _launch() -> void:
	if _selected.is_empty():
		return
	var cfg := BattleSetup.from_mission(_selected)
	GameState.mode = GameState.Mode.BATTLE_ARENA
	Net.start_offline()
	GameState.go("battle", cfg)
