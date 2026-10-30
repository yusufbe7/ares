## HUJUM REJASI oynasi (dushman hududini o'ng tugma bilan bosganda yoki hudud panelidagi ATTACK tugmasi).
##   1) hudud ma'lumoti: egasi, aholi, mudofaa, garnizon, resurs, jang maydoni turi;
##   2) tekshiruvlar: urush, yo'l, transport (port / aviabaza), ta'minot;
##   3) usul (quruqlik / dengiz / havo), qo'shin soni, harakat tezligi, jang turi (3D / avto);
##   4) HUJUMNI BOSHLASH -> launched(op, fast, in_3d) signali (xarita animatsiyasi va jang shundan keyin).
class_name AttackPlan
extends Control

signal launched(op: Dictionary, fast: bool, in_3d: bool)

var map: Node
var target := 0
var armies: Array = []               ## hujum qila oladigan o'z qo'shinlarimiz
var _army: ArmyData
var _method := ""
var _ck := {}
var _body: VBoxContainer
var _slider: HSlider
var _troops: Label
var _cost: Label
var _go: Button
var _fast: CheckButton
var _auto: CheckButton


static func open(p_map: Node, p_target: int, prefer: ArmyData = null) -> AttackPlan:
	var w := AttackPlan.new()
	w.map = p_map
	w.target = p_target
	var ops: CampaignWarOps = p_map.ops
	for a in p_map.data.armies:
		if a.owner == p_map.rules.player_id and (ops.check(a, p_target).ok or a == prefer):
			w.armies.append(a)
	if w.armies.is_empty() and prefer:
		w.armies.append(prefer)
	w._army = prefer if prefer in w.armies else (w.armies[0] if not w.armies.is_empty() else null)
	p_map.ui.root.add_child(w)
	return w


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	var p := UiKit.panel()
	p.custom_minimum_size = Vector2(620, 0)
	c.add_child(p)
	_body = UiKit.vbox(10)
	p.add_child(_body)
	_build()
	UiKit.slide_in(p)


func _build() -> void:
	UiKit.clear(_body)
	var d: CampaignData = map.data
	var tp: ProvinceData = d.provinces[target]
	var owner: CountryData = d.countries.get(tp.owner)
	var head := UiKit.hbox(10)
	head.add_child(UiIcon.make("target", 28, UiKit.RED))
	head.add_child(UiKit.label("%s: %s" % [Loc.t("op.title").to_upper(), tp.name.to_upper()], "HeaderLabel"))
	head.add_child(UiKit.spacer())
	head.add_child(FlagRect.make(owner, Vector2(42, 28)))
	_body.add_child(head)
	var ops: CampaignWarOps = map.ops
	var dfn: ArmyData = map.rules.army_in(target)
	var info := UiKit.label("%s   ·   %s: %s   ·   %s: %d\n%s   ·   %s   ·   %s" % [Loc.country(owner), Loc.t("population"), UiKit.num(tp.population),
		Loc.t("defence"), int(map.rules.defence(target)), Loc.t("op.garrison", ["~%d" % (dfn.size + 1) if dfn else "0"]),
		"%s x%d" % [Loc.resource(tp.resource), tp.resource_amount], Loc.t("op.battlefield", [Loc.t("biome." + ops.biome_for(target))])], "SmallLabel")
	_body.add_child(info)
	if _army == null:
		_body.add_child(UiKit.label(Loc.t("op.no_army"), "AmberLabel"))
		_buttons(false)
		return
	# qo'shin tanlash
	var from := OptionButton.new()
	for a in armies:
		from.add_item(Loc.t("op.from", [d.provinces[a.province].name, a.size]))
	from.selected = armies.find(_army)
	from.item_selected.connect(func(i): _army = armies[i]; _method = ""; _build())
	_body.add_child(from)
	_ck = ops.check(_army, target)
	if _method == "" or not _ck.methods[_method].ok:
		_method = ""
		for m in CampaignWarOps.METHODS:
			if _ck.methods[m].ok and _method == "":
				_method = m
	# usullar
	_body.add_child(UiKit.label(Loc.t("op.method").to_upper(), "StatLabel"))
	var mh := UiKit.hbox(8)
	for m in [["land", "tank"], ["sea", "ship"], ["air", "aircraft"]]:
		var e: Dictionary = _ck.methods[m[0]]
		var b := UiKit.button("      " + Loc.t("m." + m[0]), "TabButtonActive" if _method == m[0] else "TabButton")
		b.custom_minimum_size = Vector2(180, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ic := UiIcon.make(m[1], 20, UiKit.AMBER if e.ok else UiKit.DIM)
		ic.position = Vector2(10, 10)
		b.add_child(ic)
		b.disabled = not e.ok
		b.tooltip_text = Loc.t(e.reason) if e.reason != "" else ""
		var id: String = m[0]
		b.pressed.connect(func(): _method = id; _build())
		mh.add_child(b)
	_body.add_child(mh)
	# tekshiruvlar
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 24)
	var me: Dictionary = _ck.methods.get(_method, _ck.methods.land)
	var route_ok: bool = me.reason not in ["op.no_border", "op.no_sea_route", "op.out_of_range"]
	var rows := [["op.check_war", _ck.reason == "" or _ck.reason == "already_moved", _ck.reason],
		["op.check_route", route_ok, me.reason if not route_ok else ""],
		["op.check_transport", me.reason not in ["op.no_port", "op.no_airbase"], me.reason],
		["op.check_supply", me.reason != "op.no_supply", "op.no_supply"]]
	if _ck.reason == "already_moved":
		rows[0][1] = true
		rows.append(["moved", false, "already_moved"])
	for r in rows:
		var h := UiKit.hbox(6)
		h.add_child(UiIcon.make("check" if r[1] else "cross", 16, UiKit.GREEN if r[1] else UiKit.RED))
		h.add_child(UiKit.label(Loc.t(r[0]) if r[1] else Loc.t(r[2]) if r[2] != "" else Loc.t(r[0]), "SmallLabel"))
		g.add_child(h)
	_body.add_child(g)
	_body.add_child(UiKit.label(Loc.t("op.distance", [int(ops.distance_km(_army.province, target))]), "SmallLabel"))
	# qo'shin soni
	_slider = HSlider.new()
	_slider.min_value = 1
	_slider.max_value = maxi(1, int(me.max))
	_slider.value = _slider.max_value
	_slider.step = 1
	_slider.editable = _method != ""
	_troops = UiKit.label("", "PanelTitle")
	_cost = UiKit.label("", "SmallLabel")
	_slider.value_changed.connect(func(_v): _upd())
	_body.add_child(_troops)
	_body.add_child(_slider)
	_body.add_child(_cost)
	var oh := UiKit.hbox(18)
	_fast = CheckButton.new()
	_fast.text = Loc.t("op.fast")
	_fast.button_pressed = bool(map.get_meta("op_fast", false))
	_auto = CheckButton.new()
	_auto.text = Loc.t("op.auto")
	_auto.button_pressed = bool(map.get_meta("op_auto", false))
	oh.add_child(UiKit.label(Loc.t("op.speed") + ":", "StatLabel"))
	oh.add_child(_fast)
	oh.add_child(UiKit.label(Loc.t("op.resolve") + ":", "StatLabel"))
	oh.add_child(_auto)
	_body.add_child(oh)
	_buttons(_method != "" and _ck.reason == "")
	_upd()


func _buttons(can: bool) -> void:
	var h := UiKit.hbox(10)
	h.alignment = BoxContainer.ALIGNMENT_END
	h.add_child(UiKit.button(Loc.t("cancel"), "", queue_free))
	_go = UiKit.button("▶  " + Loc.t("op.launch").to_upper(), "AmberButton", _launch)
	_go.disabled = not can
	h.add_child(_go)
	_body.add_child(h)


func _upd() -> void:
	if _slider == null:
		return
	var n := int(_slider.value)
	var upr := int(map.data.rule("units_per_regiment", 10))
	_troops.text = Loc.t("op.troops", [n, n * upr])
	var sup := int(map.data.countries[map.rules.player_id].resources.get("supply", 0))
	_cost.text = Loc.t("op.cost", [n * map.ops.cost(_method if _method != "" else "land"), sup])


func _launch() -> void:
	map.set_meta("op_fast", _fast.button_pressed)
	map.set_meta("op_auto", _auto.button_pressed)
	var op: Dictionary = map.ops.launch(_army, target, _method, int(_slider.value))
	if op.is_empty():
		return
	launched.emit(op, _fast.button_pressed, not _auto.button_pressed)
	queue_free()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()
