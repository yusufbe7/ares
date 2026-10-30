## O'ng tomondagi ma'lumot paneli.
##  - Tanlash ekrani: sichqoncha ostidagi yoki tanlangan davlat (nomi, hududlar, kuchi, aholi, YaIM) + "PLAY AS".
##  - O'yin: tanlangan hudud (nom, egasi, aholi, resurs, mudofaa, qo'shin, ta'minot) + yollash / urush e'loni.
class_name ProvincePanel
extends PanelContainer

var map: Node
var _flag: FlagRect
var _title: Label
var _info: RichTextLabel
var _act: HBoxContainer
var _shown_country := 0


static func make(p_map: Node) -> ProvincePanel:
	var p := ProvincePanel.new()
	p.map = p_map
	return p


func _ready() -> void:
	custom_minimum_size = Vector2(290, 0)
	var v := UiKit.vbox(8)
	add_child(v)
	var h := UiKit.hbox(10)
	_flag = FlagRect.make(null, Vector2(42, 28))
	h.add_child(_flag)
	_title = UiKit.label("", "HeaderLabel")
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(_title)
	v.add_child(h)
	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.fit_content = true
	_info.custom_minimum_size = Vector2(270, 0)
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_info)
	_act = UiKit.hbox(6)
	v.add_child(_act)
	visible = false
	EventBus.country_hovered.connect(func(c: int): show_country(c if c > 0 else map.choice_id))
	EventBus.country_previewed.connect(show_country)
	EventBus.province_selected.connect(show_province)
	for s in [EventBus.campaign_changed, EventBus.language_changed]:
		s.connect(_refresh)
	EventBus.turn_ended.connect(func(_t): _refresh())


func _refresh() -> void:
	if map.rules.phase == "choose":
		show_country(_shown_country)
	else:
		show_province(map.selected_id)


func show_country(cid: int) -> void:
	_shown_country = cid
	var d: CampaignData = map.data
	var c: CountryData = d.countries.get(cid)
	visible = c != null
	if c == null:
		return
	var s: Vector2i = map.rules.strength(cid)
	_flag.set_country(c)
	_title.text = Loc.country(c)
	var t := "%s: [b]%d[/b]\n" % [Loc.t("provinces"), c.province_count]
	t += "%s: [b]%s[/b]\n" % [Loc.t("strength"), Loc.t("armies_fmt", [s.x, s.y]) if s.y > 0 else Loc.t("no_army")]
	t += "%s: %s\n" % [Loc.t("population"), UiKit.num(c.population)]
	t += "%s: $%s B\n" % [Loc.t("gdp"), UiKit.num(c.gdp_musd / 1000)]
	t += "%s: %s\n" % [Loc.t("gold"), UiKit.num(int(c.resources.get("gold", 0)))]
	if c.bloc != "":
		t += "%s: %s\n" % [Loc.t("bloc"), c.bloc.to_upper()]
	var cap: ProvinceData = d.provinces.get(c.capital)
	if cap and cap.owner == cid:
		t += "%s: %s\n" % [Loc.t("capital").capitalize(), cap.name]
	_info.text = t
	UiKit.clear(_act)
	var chosen: CountryData = d.countries.get(map.choice_id)
	if chosen:
		var b := UiKit.button(Loc.t("play_as", [Loc.country(chosen)]).to_upper(), "AmberButton", func(): map.choose_country(map.choice_id))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_act.add_child(b)


func show_province(id: int) -> void:
	if map.rules.phase == "choose":
		return
	var d: CampaignData = map.data
	var r: CampaignRules = map.rules
	var p: ProvinceData = d.provinces.get(id)
	visible = p != null
	if p == null:
		return
	var c: CountryData = d.countries.get(p.owner)
	var a: ArmyData = r.army_in(id)
	_flag.set_country(c)
	_title.text = p.name
	var own := p.owner == r.player_id
	var t := "[color=#%s]■[/color] %s%s\n" % [c.color.to_html(false) if c else "999999", Loc.country(c), "  (%s)" % Loc.t("capital") if c and c.capital == id else ""]
	if c and not own and r.player_id > 0:
		var rel := Loc.t("rel.war") if r.diplomacy.at_war(r.player_id, p.owner) else (Loc.t("rel.ally") if d.allied(r.player_id, p.owner) else Loc.t("rel.peace"))
		t += "[color=#e8a33a]%s[/color]\n" % rel
	t += "\n%s: %s\n" % [Loc.t("population"), UiKit.num(p.population)]
	t += "%s: %s x%d\n" % [Loc.t("resource"), Loc.resource(p.resource), p.resource_amount]
	t += "%s: %d\n" % [Loc.t("defence"), int(r.defence(id))]
	if r.occupation.unrest.has(id):
		t += "[color=#e5483d]%s[/color]\n" % Loc.t("occ.unrest", [int(r.occupation.unrest[id])])
	t += "%s: %s %s%s\n" % [Loc.t("area"), UiKit.num(p.area_km2), Loc.t("km2"), "   (%s)" % Loc.t("coastal") if p.coastal else ""]
	t += "%s: %d + %d %s\n" % [Loc.t("neighbors"), p.neighbors.size(), p.sea.size(), Loc.t("by_sea")]
	if a:
		var ac: CountryData = d.countries.get(a.owner)
		var size_txt := str(a.size) if a.owner == r.player_id or d.allied(r.player_id, a.owner) else "~%d-%d" % [maxi(1, a.size - 2), a.size + 3]
		t += "\n" + Loc.t("army_line", [size_txt, Loc.country(ac)])
		if a.owner == r.player_id:
			t += "\n%s: %s" % [Loc.t("supply"), Loc.t("supply_ok") if a.supplied else "[color=#e5483d]%s[/color]" % Loc.t("supply_cut")]
			if a.busy > 0:
				t += "\n" + Loc.t("at_sea")
			elif a.moved:
				t += "\n" + Loc.t("moved")
			else:
				t += "\n[color=#e8a33a]%s[/color]" % Loc.t("right_click_hint")
	_info.text = t
	UiKit.clear(_act)
	if own and a == null and r.phase == "play":
		_act.add_child(UiKit.button(Loc.t("recruit", [int(d.rule("recruit_cost", 150))]), "", func(): map.recruit(id)))
	elif c and not own and r.phase == "play" and r.diplomacy.can_declare(r.player_id, p.owner):
		var cid := p.owner
		_act.add_child(UiKit.button(Loc.t("declare_war").to_upper(), "", func(): CampaignDialogs.declare_war(map, cid)))
	if c and not own and r.phase == "play" and r.diplomacy.at_war(r.player_id, p.owner):
		_act.add_child(UiKit.button("⚔  " + Loc.t("attack").to_upper(), "AmberButton", func(): map.open_attack_plan(id, map.selected_army)))
