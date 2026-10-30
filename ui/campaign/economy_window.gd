## ECONOMY tabi: davlat daromadi va xarajati, resurslar, har yurishdagi o'zgarish (oltin, supply) jadvali va grafigi.
## Hammasi CampaignTurns.economy() va rules.history dan (haqiqiy hisob).
class_name EconomyWindow
extends PanelContainer

var map: Node
var _body: VBoxContainer
var _chart: Control


static func make(p_map: Node) -> EconomyWindow:
	var w := EconomyWindow.new()
	w.map = p_map
	return w


func _ready() -> void:
	custom_minimum_size = Vector2(640, 0)
	var v := UiKit.vbox(10)
	add_child(v)
	var h := UiKit.hbox()
	h.add_child(UiKit.label(Loc.t("tab.economy").to_upper(), "HeaderLabel"))
	h.add_child(UiKit.spacer())
	h.add_child(UiKit.button("✕", "IconButton", func(): EventBus.tab_changed.emit("world_map")))
	v.add_child(h)
	_body = UiKit.vbox(6)
	v.add_child(_body)
	_chart = Control.new()
	_chart.custom_minimum_size = Vector2(600, 150)
	_chart.draw.connect(_draw_chart)
	v.add_child(_chart)
	EventBus.turn_ended.connect(func(_t): refresh())
	EventBus.campaign_changed.connect(refresh)
	refresh()


func refresh() -> void:
	UiKit.clear(_body)
	var r: CampaignRules = map.rules
	if r.player_id == 0:
		_body.add_child(UiKit.label(Loc.t("choose_first"), "SmallLabel"))
		return
	var c: CountryData = r.data.countries[r.player_id]
	var e := CampaignTurns.economy(r, r.player_id)
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 26)
	_body.add_child(g)
	for row in [["", Loc.t("gold").to_upper(), "SUPPLY", ""],
			[Loc.t("eco.stock"), UiKit.num(int(c.resources.get("gold", 0))), UiKit.num(int(c.resources.get("supply", 0))), ""],
			[Loc.t("eco.income"), "+" + UiKit.num(e.gold_in), "+" + UiKit.num(e.supply_in), Loc.t("eco.income_src")],
			[Loc.t("eco.expense"), "-" + UiKit.num(e.gold_out), "-" + UiKit.num(e.supply_out), Loc.t("eco.expense_src")],
			[Loc.t("eco.net"), _signed(e.gold_in - e.gold_out), _signed(e.supply_in - e.supply_out), ""]]:
		for k in 4:
			g.add_child(UiKit.label(str(row[k]), "PanelTitle" if k > 0 and k < 3 else "SmallLabel"))
	var res := {}
	for p in r.data.provinces.values():
		if p.owner == r.player_id:
			res[p.resource] = int(res.get(p.resource, 0)) + p.resource_amount
	var parts := []
	for k in res:
		parts.append("%s x%d" % [Loc.resource(k), res[k]])
	_body.add_child(UiKit.label("%s: %s" % [Loc.t("resources"), ", ".join(parts)], "SmallLabel"))
	_body.add_child(UiKit.label(Loc.t("eco.history"), "StatLabel"))
	_chart.queue_redraw()


static func _signed(n: int) -> String:
	return ("+" if n >= 0 else "") + UiKit.num(n)


## Kichik grafik: oltin (amber) va supply (ko'k) yurishlar bo'yicha.
func _draw_chart() -> void:
	var hist: Array = map.rules.history
	var r := Rect2(Vector2.ZERO, _chart.size)
	_chart.draw_rect(r, Color(0.05, 0.05, 0.06, 0.8))
	if hist.size() < 2:
		_chart.draw_string(ThemeDB.fallback_font, Vector2(10, 24), Loc.t("eco.no_history"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiKit.DIM)
		return
	for key_col in [["gold", UiKit.AMBER], ["supply", Color(0.4, 0.7, 1.0)]]:
		var mx := 1.0
		for e in hist:
			mx = maxf(mx, float(e.get(key_col[0], 0)))
		var pts := PackedVector2Array()
		for i in hist.size():
			var x := r.size.x * i / (hist.size() - 1)
			pts.append(Vector2(x, r.size.y - 8 - (r.size.y - 16) * float(hist[i].get(key_col[0], 0)) / mx))
		_chart.draw_polyline(pts, key_col[1], 2.0, true)
