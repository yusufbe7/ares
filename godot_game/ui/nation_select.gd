extends Node
## Pick a nation off the world map itself, exactly as it will look in play.

var map: WorldMapView
var info_box: VBoxContainer
var chosen: String = ""
var role_option: OptionButton

func open(_payload: Dictionary) -> void:
	if GameState.world == null:
		GameState.start_new_world(0)
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := HBoxContainer.new()
	UIKit.fullscreen(root)
	layer.add_child(root)

	map = WorldMapView.new()
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map.set_world(GameState.world)
	map.province_clicked.connect(_on_province_clicked)
	root.add_child(map)

	var side := UIKit.make_panel()
	side.custom_minimum_size = Vector2(380, 0)
	root.add_child(side)
	var col := UIKit.vbox(8)
	side.add_child(col)

	col.add_child(UIKit.title(Loc.t("world.select_nation")))
	col.add_child(UIKit.label("Xaritadan hudud bosing yoki ro'yxatdan tanlang.", 13, UIKit.MUTED))

	var role_row := UIKit.hbox()
	role_row.add_child(UIKit.label("Lavozim:", 14))
	role_option = OptionButton.new()
	role_option.add_item("Davlat rahbari", GameState.Role.HEAD_OF_STATE)
	role_option.add_item("Qo'mondon", GameState.Role.COMMANDER)
	role_option.add_item("Ofitser", GameState.Role.OFFICER)
	role_option.selected = 0
	role_row.add_child(role_option)
	col.add_child(role_row)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	var list := UIKit.vbox(4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var ids: Array = GameState.world.nation_ids()
	ids.sort_custom(func(a, b):
		var na: Nation = GameState.world.nation(str(a))
		var nb: Nation = GameState.world.nation(str(b))
		return na.tier > nb.tier)
	for nid in ids:
		var n: Nation = GameState.world.nation(str(nid))
		var b := UIKit.button("%s  —  %d hudud, %d daraja" % [n.display_name, n.provinces.size(), n.tier], 14)
		b.add_theme_color_override("font_color", n.color)
		b.pressed.connect(_select_nation.bind(str(nid)))
		list.add_child(b)

	info_box = UIKit.vbox(4)
	col.add_child(info_box)

	var start := UIKit.button(Loc.t("battle.deploy"), 18)
	start.pressed.connect(_confirm)
	col.add_child(start)

	var back := UIKit.button(Loc.t("common.back"), 14)
	back.pressed.connect(func(): GameState.go("main_menu", {}))
	col.add_child(back)

	_select_nation("UZB")

func _on_province_clicked(pid: int, _button: int) -> void:
	var p: Province = GameState.world.province(pid)
	if p != null and p.owner_id != "":
		_select_nation(p.owner_id)

func _select_nation(nid: String) -> void:
	chosen = nid
	var n: Nation = GameState.world.nation(nid)
	if n == null:
		return
	map.highlight = n.provinces.duplicate()
	map.center_on(n.capital_province)
	map.queue_redraw()
	for c in info_box.get_children():
		c.queue_free()
	info_box.add_child(UIKit.label(n.display_name, 22, n.color))
	info_box.add_child(UIKit.label("Poytaxt: %s" % n.capital_name, 13, UIKit.MUTED))
	info_box.add_child(UIKit.label("Doktrina: %s" % n.doctrine, 13, UIKit.MUTED))
	info_box.add_child(UIKit.label("Hududlar: %d   Armiyalar: %d" % [n.provinces.size(), n.armies.size()], 13))
	info_box.add_child(UIKit.label("Byudjet: %d   Jonli kuch: %d"
		% [int(n.resources.get("money", 0)), int(n.resources.get("manpower", 0))], 13))
	var neighbours: Array = []
	for other in GameState.world.nation_ids():
		if str(other) != nid and GameState.world._shares_border(nid, str(other)):
			neighbours.append(GameState.world.nation(str(other)).display_name)
	info_box.add_child(UIKit.label("Qo'shnilar: %s" % ", ".join(neighbours), 12, UIKit.MUTED))

func _confirm() -> void:
	if chosen == "":
		GameState.notify("Avval davlat tanlang.", "warn")
		return
	var role: int = role_option.get_item_id(role_option.selected)
	Net.pick_nation(chosen, role)
	GameState.local_nation = chosen
	GameState.mode = GameState.Mode.GLOBAL_WAR
	Net.clock_running = true
	GameState.go("world", {})
