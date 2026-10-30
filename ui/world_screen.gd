extends Node
## The global map screen: who holds what, how much of the world that is, and
## where to attack next. Winning a battle here moves the country on the map.

var model: WorldModel
var map: WorldMapView
var _share_rows: VBoxContainer
var _share_bar: HBoxContainer
var _info: VBoxContainer
var _player_faction: String = "atlantic"

func open(payload: Dictionary) -> void:
	_player_faction = str(payload.get("faction", GameState.player_faction))
	model = WorldModel.new()
	model.load_from_data()
	_apply_pending_result()
	_build()
	_refresh_shares()
	_show_country(GameState.last_conquest if GameState.last_conquest != "" else "")

## A battle launched from here reports back through GameState.
func _apply_pending_result() -> void:
	var res: Dictionary = GameState.last_battle_result
	var target := str(res.get("world_country", ""))
	if target == "":
		return
	GameState.last_battle_result = {}
	if bool(res.get("player_won", false)):
		model.transfer(target, _player_faction)
		GameState.record_conquest(target, _player_faction)
		GameState.notify("%s nazoratga olindi." % model.country(target).name, "good")
	else:
		GameState.notify("Hujum qaytarildi.", "bad")
	for id in GameState.conquests.keys():
		model.transfer(str(id), str(GameState.conquests[id]))

func _build() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	map = WorldMapView.new()
	map.set_anchors_preset(Control.PRESET_FULL_RECT)
	map.setup(model)
	map.country_clicked.connect(_show_country)
	layer.add_child(map)

	# Territory control, top right, the way a strategic screen reports it.
	var share_panel := UIKit.make_panel(UIKit.PANEL)
	share_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	share_panel.offset_left = -300
	share_panel.offset_right = -12
	share_panel.offset_top = 12
	share_panel.offset_bottom = 190
	layer.add_child(share_panel)
	var col := UIKit.vbox(5)
	share_panel.add_child(col)
	col.add_child(UIKit.label("GLOBAL TERRITORY", 13, UIKit.MUTED))
	_share_bar = UIKit.hbox(0)
	_share_bar.custom_minimum_size = Vector2(0, 10)
	col.add_child(_share_bar)
	_share_rows = UIKit.vbox(2)
	col.add_child(_share_rows)

	# The selected country, bottom left.
	var info_panel := UIKit.make_panel(UIKit.PANEL)
	info_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	info_panel.offset_left = 12
	info_panel.offset_right = 360
	info_panel.offset_top = -250
	info_panel.offset_bottom = -12
	layer.add_child(info_panel)
	_info = UIKit.vbox(4)
	info_panel.add_child(_info)

	var top_left := UIKit.make_panel(UIKit.PANEL)
	top_left.set_anchors_preset(Control.PRESET_TOP_LEFT)
	top_left.offset_left = 12
	top_left.offset_right = 300
	top_left.offset_top = 12
	top_left.offset_bottom = 86
	layer.add_child(top_left)
	var tl := UIKit.vbox(2)
	top_left.add_child(tl)
	tl.add_child(UIKit.label("GLOBAL FRONT — 2041", 17, UIKit.ACCENT))
	tl.add_child(UIKit.label("Sizning blokingiz: %s" % model.faction_name(_player_faction),
		13, model.faction_color(_player_faction)))
	var back := UIKit.button(Loc.t("common.back"), 12)
	back.custom_minimum_size = Vector2(0, 26)
	back.pressed.connect(func(): GameState.go("setup", {}))
	tl.add_child(back)

func _refresh_shares() -> void:
	for c in _share_rows.get_children():
		c.queue_free()
	for c in _share_bar.get_children():
		c.queue_free()
	var shares := model.control_share()
	var ranked: Array = model.faction_order.duplicate()
	ranked.sort_custom(func(a, b): return float(shares[a]) > float(shares[b]))
	for fid in ranked:
		var pct := float(shares[fid])
		if pct <= 0.0005:
			continue
		var seg := ColorRect.new()
		seg.color = model.faction_color(str(fid))
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.size_flags_stretch_ratio = maxf(pct, 0.001)
		_share_bar.add_child(seg)

		var row := UIKit.hbox(6)
		var swatch := ColorRect.new()
		swatch.color = model.faction_color(str(fid))
		swatch.custom_minimum_size = Vector2(12, 12)
		row.add_child(swatch)
		var name_label := UIKit.label(model.faction_name(str(fid)), 12)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		row.add_child(UIKit.label("%d%%" % int(round(pct * 100.0)), 13,
			model.faction_accent(str(fid))))
		_share_rows.add_child(row)

func _show_country(id: String) -> void:
	for c in _info.get_children():
		c.queue_free()
	if id == "" or model.country(id) == null:
		_info.add_child(UIKit.label("Xaritadan davlat tanlang.", 13, UIKit.MUTED))
		_info.add_child(UIKit.label("O'ng tugma bilan sudrang, g'ildirak bilan yaqinlashing.",
			11, UIKit.MUTED))
		return
	var c = model.country(id)
	_info.add_child(UIKit.label(c.name, 20, model.faction_accent(c.owner)))
	_info.add_child(UIKit.label("Blok: %s" % model.faction_name(c.owner), 13,
		model.faction_color(c.owner)))
	_info.add_child(UIKit.label("Qit'a: %s   Aholi: %s" % [c.continent, _thousands(c.population)],
		12, UIKit.MUTED))
	_info.add_child(UIKit.label("Dunyo quruqligining %.1f%%" % (c.area / model.total_area * 100.0),
		12, UIKit.MUTED))
	if c.contested:
		_info.add_child(UIKit.label("NIZOLI HUDUD", 13, UIKit.WARN))

	var map_id := model.battle_map_for(id)
	var season := model.season_for(id)
	_info.add_child(UIKit.label("Jang: %s, %s" % [
		DB.local_name(DB.battle_map(map_id).get("name", {}), map_id),
		DB.local_name(DB.season(season).get("title", {}), season).split(" — ")[0]], 12))

	if c.owner == _player_faction:
		_info.add_child(UIKit.label("Bu hudud sizda.", 12, UIKit.ACCENT))
		return
	var attack := UIKit.button("HUJUM QILISH", 15)
	attack.pressed.connect(_attack.bind(id))
	_info.add_child(attack)

func _attack(id: String) -> void:
	var c = model.country(id)
	if c == null:
		return
	var defenders := maxi(18, mini(44, int(c.area * 0.6) + 18))
	var options := {
		"title": c.name,
		"map": model.battle_map_for(id),
		"season": model.season_for(id),
		"weather": "clear",
		"victory_mode": "capture",
		"difficulty": "normal",
		"minutes": 15.0,
		"seed": hash(id),
		"player_force": {"infantry": 28, "tanks": 4, "transports": 3, "artillery": 2, "aircraft": 1},
		"enemy_force": {"infantry": defenders, "tanks": 4, "transports": 2, "artillery": 2, "aircraft": 1},
		"player_faction": "army", "enemy_faction": "insurgent" if c.contested else "army",
		"player_name": model.faction_name(_player_faction),
		"enemy_name": model.faction_name(c.owner),
		"player_color": model.faction_color(_player_faction).to_html(false),
		"enemy_color": model.faction_color(c.owner).to_html(false),
	}
	var cfg := BattleSetup.build(options)
	cfg["world_country"] = id
	GameState.remember_setup(options)
	GameState.go("battle", cfg)

static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = " " + out
	return out
