extends Node
## The global map screen: economy, construction, armies, diplomacy, the national
## council and the list of battles waiting to be fought in 3D.

var map: WorldMapView
var tabs: TabContainer
var top_bar: HBoxContainer
var log_label: RichTextLabel
var selected_army_id: int = -1

var _province_box: VBoxContainer
var _army_box: VBoxContainer
var _diplo_box: VBoxContainer
var _council_box: VBoxContainer
var _battle_box: VBoxContainer
var _clock_button: Button

func open(_payload: Dictionary) -> void:
	if GameState.world == null:
		GameState.start_new_world(0)
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := VBoxContainer.new()
	UIKit.fullscreen(root)
	layer.add_child(root)

	top_bar = UIKit.hbox(14)
	var top_panel := UIKit.make_panel(UIKit.PANEL)
	top_panel.add_child(top_bar)
	root.add_child(top_panel)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	map = WorldMapView.new()
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map.local_nation = GameState.local_nation
	map.set_world(GameState.world)
	map.province_clicked.connect(_on_province_clicked)
	body.add_child(map)

	var side := UIKit.make_panel()
	side.custom_minimum_size = Vector2(420, 0)
	body.add_child(side)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(tabs)
	_province_box = _make_tab("HUDUD")
	_army_box = _make_tab("ARMIYA")
	_diplo_box = _make_tab("DIPLOMATIYA")
	_council_box = _make_tab("KENGASH")
	_battle_box = _make_tab("JANGLAR")

	var log_panel := UIKit.make_panel(UIKit.PANEL_SOFT)
	log_panel.custom_minimum_size = Vector2(0, 110)
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.scroll_following = true
	log_panel.add_child(log_label)
	root.add_child(log_panel)

	EventBus.world_tick.connect(_on_tick)
	EventBus.world_loaded.connect(_on_world_loaded)
	EventBus.vote_opened.connect(func(_v): _refresh_council())
	EventBus.vote_closed.connect(func(_v, _p): _refresh_council())
	EventBus.war_declared.connect(func(_a, _b): _refresh_all())
	EventBus.peace_signed.connect(func(_a, _b): _refresh_all())

	var n: Nation = GameState.my_nation()
	if n != null:
		map.center_on(n.capital_province)
		map.selected_province = n.capital_province
	_refresh_all()

func _make_tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	var box := UIKit.vbox(6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	tabs.add_child(scroll)
	return box

# ---------------------------------------------------------------------------
# Top bar
# ---------------------------------------------------------------------------

func _refresh_top() -> void:
	for c in top_bar.get_children():
		c.queue_free()
	var w := GameState.world
	var n: Nation = GameState.my_nation()
	top_bar.add_child(UIKit.label("%d-kun" % w.day, 16, UIKit.ACCENT))
	top_bar.add_child(UIKit.label("%s / %s" % [w.season, w.weather], 14, UIKit.MUTED))
	if n != null:
		top_bar.add_child(UIKit.label(n.display_name, 16, n.color))
		top_bar.add_child(UIKit.label(GameState.role_name(GameState.local_role), 13, UIKit.MUTED))
		var balance := Economy.net_balance(w, n.id)
		for key in ["money", "manpower", "food", "fuel", "steel", "ammo"]:
			var value := float(n.resources.get(key, 0.0))
			var delta := float(balance.get(key, 0.0))
			var col: Color = UIKit.TEXT if delta >= 0.0 else UIKit.BAD
			top_bar.add_child(UIKit.label("%s %d (%+.0f)" % [_res_label(key), int(value), delta], 13, col))
		if n.war_weariness > 0.05:
			top_bar.add_child(UIKit.label("Charchoq %d%%" % int(n.war_weariness * 100.0), 13, UIKit.WARN))
	_clock_button = UIKit.button("PAUZA" if Net.clock_running else "DAVOM", 13)
	_clock_button.custom_minimum_size = Vector2(110, 30)
	_clock_button.pressed.connect(func():
		Net.command("start_clock", {"running": not Net.clock_running})
		if Net.is_authority():
			Net.clock_running = not Net.clock_running
		_refresh_top())
	top_bar.add_child(_clock_button)
	var save_btn := UIKit.button("SAQLASH", 13)
	save_btn.custom_minimum_size = Vector2(110, 30)
	save_btn.pressed.connect(func():
		if GameState.save_world():
			GameState.notify("O'yin saqlandi.", "good"))
	top_bar.add_child(save_btn)

func _res_label(key: String) -> String:
	match key:
		"money": return "Pul"
		"manpower": return "Jonli kuch"
		"food": return "Oziq"
		"fuel": return "Yoqilg'i"
		"steel": return "Po'lat"
		"ammo": return "O'q-dori"
	return key

# ---------------------------------------------------------------------------
# Tabs
# ---------------------------------------------------------------------------

func _refresh_all() -> void:
	_refresh_top()
	_refresh_province()
	_refresh_army()
	_refresh_diplomacy()
	_refresh_council()
	_refresh_battles()
	_refresh_log()
	if map != null:
		map.queue_redraw()

func _clear(box: VBoxContainer) -> void:
	for c in box.get_children():
		c.queue_free()

func _refresh_province() -> void:
	_clear(_province_box)
	var pid := map.selected_province if map != null else -1
	var p: Province = GameState.world.province(pid)
	if p == null:
		_province_box.add_child(UIKit.label("Xaritadan hudud tanlang.", 14, UIKit.MUTED))
		return
	var owner: Nation = GameState.world.nation(p.owner_id)
	_province_box.add_child(UIKit.label(p.name, 20, owner.color if owner != null else UIKit.TEXT))
	_province_box.add_child(UIKit.label("Egasi: %s" % (owner.display_name if owner != null else "yo'q"), 13, UIKit.MUTED))
	_province_box.add_child(UIKit.label("Yer turi: %s   Aholi: %s"
		% [Province.terrain_name(p.terrain), _thousands(p.population)], 13))
	_province_box.add_child(UIKit.label("Ta'minot: %s (%d%%)" % [SupplyNet.status_text(p.supply), int(p.supply * 100)], 13))
	_province_box.add_child(UIKit.bar(p.supply, 1.0, UIKit.ACCENT))
	if p.unrest > 0.01:
		_province_box.add_child(UIKit.label("Norozilik: %d%%" % int(p.unrest * 100), 13, UIKit.WARN))
	_province_box.add_child(UIKit.label("Mudofaa: x%.2f" % p.defense_bonus(), 13))
	_province_box.add_child(UIKit.label("Jang xaritasi: %s" % p.battle_map_id(), 12, UIKit.MUTED))

	if not p.construction.is_empty():
		_province_box.add_child(UIKit.label("Qurilmoqda:", 14, UIKit.WARN))
		for job in p.construction:
			_province_box.add_child(UIKit.label("  %s — %d kun"
				% [DB.local_name(DB.building(str(job["building"])).get("name", ""), str(job["building"])),
				int(job["days_left"])], 13))

	if not p.development.is_empty():
		_province_box.add_child(UIKit.label("Binolar:", 14))
		for bid in p.development.keys():
			_province_box.add_child(UIKit.label("  %s  lvl %d"
				% [DB.local_name(DB.building(str(bid)).get("name", ""), str(bid)), int(p.development[bid])], 13))

	if p.owner_id == GameState.local_nation:
		_province_box.add_child(UIKit.spacer(8))
		_province_box.add_child(UIKit.label("Qurish:", 14, UIKit.ACCENT))
		for bid in DB.buildings.keys():
			var b: Dictionary = DB.building(str(bid))
			var cost: Dictionary = b.get("cost", {})
			var btn := UIKit.button("%s  (%d pul, %d kun)"
				% [DB.local_name(b.get("name", ""), str(bid)), int(cost.get("money", 0)), int(b.get("build_days", 0))], 13)
			btn.pressed.connect(func():
				Net.command("build", {"province": pid, "building": str(bid)})
				_refresh_all())
			_province_box.add_child(btn)

func _refresh_army() -> void:
	_clear(_army_box)
	var n: Nation = GameState.my_nation()
	if n == null:
		_army_box.add_child(UIKit.label("Davlat tanlanmagan.", 14, UIKit.MUTED))
		return
	_army_box.add_child(UIKit.label("Kuchlar: %.0f" % n.total_strength(), 16, UIKit.ACCENT))
	_army_box.add_child(UIKit.label("Armiyani tanlang, so'ng xaritada o'ng tugmani bosing.", 12, UIKit.MUTED))
	for a in n.armies:
		var p: Province = GameState.world.province(a.province)
		var selected: bool = a.id == selected_army_id
		var btn := UIKit.button("%s%s — %d kishi, %s"
			% ["> " if selected else "", a.name, a.men(), p.name if p != null else "?"], 14)
		btn.pressed.connect(func():
			selected_army_id = a.id
			if p != null:
				map.center_on(a.province)
			_refresh_army())
		_army_box.add_child(btn)
		if selected:
			var detail := UIKit.vbox(3)
			detail.add_child(UIKit.label("Ruhiyat %d%%   Ta'minot %d%%   Mustahkamlanish %d%%"
				% [int(a.morale * 100), int(a.supply * 100), int(a.entrenched * 100)], 12, UIKit.MUTED))
			for uid in a.units.keys():
				detail.add_child(UIKit.label("  %s x%d"
					% [DB.local_name(DB.unit(str(uid)).get("name", ""), str(uid)), int(a.units[uid])], 12))
			detail.add_child(UIKit.label("Safarbarlik:", 13, UIKit.ACCENT))
			for uid in DB.units.keys():
				var u: Dictionary = DB.unit(str(uid))
				var rb := UIKit.button("+1 %s (%d pul)"
					% [DB.local_name(u.get("name", ""), str(uid)), int(u.get("cost", {}).get("money", 0))], 12)
				rb.custom_minimum_size = Vector2(0, 30)
				rb.pressed.connect(func():
					Net.command("recruit", {"army": a.id, "unit": str(uid), "count": 1})
					_refresh_all())
				detail.add_child(rb)
			_army_box.add_child(detail)

func _refresh_diplomacy() -> void:
	_clear(_diplo_box)
	var w := GameState.world
	var me: Nation = GameState.my_nation()
	if me == null:
		return
	if me.alliance_id != "":
		var pact: Dictionary = w.alliances.get(me.alliance_id, {})
		_diplo_box.add_child(UIKit.label("Ittifoq: %s" % str(pact.get("name", "")), 16, UIKit.ACCENT))
		_diplo_box.add_child(UIKit.label("A'zolar: %s" % ", ".join(pact.get("members", [])), 12, UIKit.MUTED))
		var leave := UIKit.button("Ittifoqdan chiqish", 13)
		leave.pressed.connect(func(): Net.command("leave_alliance", {}))
		_diplo_box.add_child(leave)
	else:
		var create := UIKit.button("Yangi ittifoq tuzish", 13)
		create.pressed.connect(func(): Net.command("propose_alliance", {"name": ""}))
		_diplo_box.add_child(create)

	_diplo_box.add_child(UIKit.spacer(6))
	var ids: Array = w.nation_ids()
	ids.sort_custom(func(a, b): return me.opinion_of(str(a)) > me.opinion_of(str(b)))
	for nid in ids:
		if str(nid) == me.id:
			continue
		var other: Nation = w.nation(str(nid))
		var row := UIKit.make_panel(UIKit.PANEL_SOFT)
		var col := UIKit.vbox(3)
		row.add_child(col)
		var status := "urushda" if me.is_at_war_with(str(nid)) else (
			"ittifoqdosh" if other.alliance_id != "" and other.alliance_id == me.alliance_id else "tinch")
		var opinion := me.opinion_of(str(nid))
		var opinion_color: Color = UIKit.ACCENT if opinion > 20 else (UIKit.BAD if opinion < -20 else UIKit.TEXT)
		col.add_child(UIKit.label("%s — %s (%+d)" % [other.display_name, status, opinion], 15, opinion_color))
		col.add_child(UIKit.label("Kuch: %.0f   Hudud: %d   Charchoq: %d%%"
			% [other.total_strength(), other.provinces.size(), int(other.war_weariness * 100)], 12, UIKit.MUTED))
		var buttons := UIKit.hbox(4)
		if me.is_at_war_with(str(nid)):
			var peace := UIKit.button("Tinchlik", 12)
			peace.custom_minimum_size = Vector2(0, 30)
			peace.pressed.connect(_propose_peace.bind(str(nid)))
			buttons.add_child(peace)
		else:
			var blocked := Diplomacy.can_declare_war(w, me.id, str(nid))
			var war := UIKit.button("Urush", 12)
			war.custom_minimum_size = Vector2(0, 30)
			war.disabled = blocked != ""
			war.tooltip_text = blocked
			war.pressed.connect(func(): Net.command("propose_war", {"target": str(nid), "reason": "Hududiy da'vo"}))
			buttons.add_child(war)
			if me.alliance_id == "" and other.alliance_id != "" and opinion > 20:
				var join := UIKit.button("Ittifoqqa kirish", 12)
				join.custom_minimum_size = Vector2(0, 30)
				join.pressed.connect(func(): Net.command("propose_alliance", {"alliance": other.alliance_id}))
				buttons.add_child(join)
		col.add_child(buttons)
		_diplo_box.add_child(row)

func _propose_peace(target: String) -> void:
	var w := GameState.world
	var me: Nation = GameState.my_nation()
	var terms := {"winner": me.id, "provinces": [], "reparations": 0.0, "trade": true}
	var chance := Diplomacy.peace_acceptance(w, me.id, target, terms)
	GameState.notify("Tinchlik taklifi yuborildi (qabul ehtimoli %d%%)." % int(chance * 100), "info")
	Net.command("propose_peace", {"target": target, "terms": terms})

func _refresh_council() -> void:
	_clear(_council_box)
	var w := GameState.world
	var me: Nation = GameState.my_nation()
	if me == null:
		return
	_council_box.add_child(UIKit.label("Milliy kengash", 18, UIKit.ACCENT))
	_council_box.add_child(UIKit.label(
		"Urush, tinchlik va katta xarajatlar kengash ovozi bilan hal qilinadi. "
		+ "Oflayn o'yinchilar ovoz bermasa, muddat tugashi bilan qaror qabul qilinadi.",
		12, UIKit.MUTED))
	_council_box.add_child(UIKit.label("O'yinchilar:", 14))
	for p in me.players:
		var online: bool = bool(p.get("online", false))
		_council_box.add_child(UIKit.label("  %s — %s %s"
			% [str(p.get("name", "?")), GameState.role_name(int(p.get("role", 0))),
			"(onlayn)" if online else "(oflayn)"], 12,
			UIKit.TEXT if online else UIKit.MUTED))
	var share := GameState.spend_share(GameState.local_role)
	_council_box.add_child(UIKit.label("Sizning mustaqil xarajat chegarangiz: %d%%" % int(share * 100), 12, UIKit.MUTED))

	var open_votes := WarCouncil.open_votes_for(w, me.id)
	if open_votes.is_empty():
		_council_box.add_child(UIKit.label("Ochiq ovoz berish yo'q.", 13, UIKit.MUTED))
	for v in open_votes:
		var panel := UIKit.make_panel(UIKit.PANEL_SOFT)
		var col := UIKit.vbox(3)
		panel.add_child(col)
		col.add_child(UIKit.label(str(v.get("title", "")), 15, UIKit.WARN))
		var t: Dictionary = WarCouncil.tally(v)
		col.add_child(UIKit.label("Ha: %d   Yo'q: %d   Jami vazn: %d   Muddat: %d-kun"
			% [int(t["yes"]), int(t["no"]), int(t["total"]), int(v.get("deadline_day", 0))], 12, UIKit.MUTED))
		var row := UIKit.hbox(4)
		var yes := UIKit.button("HA", 13)
		yes.custom_minimum_size = Vector2(0, 30)
		yes.pressed.connect(func():
			Net.command("cast_vote", {"vote": str(v["id"]), "approve": true})
			_refresh_council())
		row.add_child(yes)
		var no := UIKit.button("YO'Q", 13)
		no.custom_minimum_size = Vector2(0, 30)
		no.pressed.connect(func():
			Net.command("cast_vote", {"vote": str(v["id"]), "approve": false})
			_refresh_council())
		row.add_child(no)
		col.add_child(row)
		_council_box.add_child(panel)

func _refresh_battles() -> void:
	_clear(_battle_box)
	var w := GameState.world
	var me := GameState.local_nation
	if w.pending_battles.is_empty():
		_battle_box.add_child(UIKit.label("Hozircha jang yo'q.", 14, UIKit.MUTED))
		return
	for b in w.pending_battles:
		var mine: bool = str(b.get("attacker", "")) == me or str(b.get("defender", "")) == me
		var panel := UIKit.make_panel(UIKit.PANEL_SOFT)
		var col := UIKit.vbox(3)
		panel.add_child(col)
		col.add_child(UIKit.label(str(b.get("province_name", "?")), 15, UIKit.WARN if mine else UIKit.TEXT))
		col.add_child(UIKit.label("%s  vs  %s   —  %s, %s"
			% [str(b.get("attacker", "")), str(b.get("defender", "")),
			str(b.get("map", "")), str(b.get("weather", ""))], 12, UIKit.MUTED))
		if mine:
			var deploy := UIKit.button(Loc.t("battle.deploy"), 14)
			deploy.pressed.connect(func(): Net.command("request_battle", {"battle_id": int(b.get("id", -1))}))
			col.add_child(deploy)
			var auto := UIKit.button("Avtomatik hal qilish", 12)
			auto.custom_minimum_size = Vector2(0, 30)
			auto.pressed.connect(func():
				var res := BattleBridge.auto_resolve(w, b)
				BattleBridge.apply_result(w, res)
				_refresh_all())
			col.add_child(auto)
		_battle_box.add_child(panel)

func _refresh_log() -> void:
	if log_label == null:
		return
	var lines: Array = GameState.world.log_lines
	var text := ""
	for i in range(maxi(0, lines.size() - 12), lines.size()):
		text += "[color=#8a9099]%d-kun[/color]  %s\n" % [int(lines[i]["day"]), str(lines[i]["text"])]
	log_label.text = text

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _on_province_clicked(pid: int, button: int) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		if selected_army_id >= 0:
			Net.command("move_army", {"army": selected_army_id, "target": pid})
			GameState.notify("Armiya yo'lga chiqdi.", "info")
		return
	_refresh_province()

func _on_tick(_day: int) -> void:
	_refresh_all()

func _on_world_loaded() -> void:
	if map != null:
		map.set_world(GameState.world)
	_refresh_all()

func on_back() -> bool:
	GameState.go("main_menu", {})
	return true
