## SELECT FACTION: yirik davlatlar to'ri (data/factions.json) + CUSTOM (xaritadan istalgan davlat).
## Tanlansa kamera o'sha davlatga siljiydi, hududlari ajralib turadi, STARTING UNITS shu davlat qo'shini
## (polklar soni x tarkib ulushi x units_per_regiment, factions.json).
class_name FactionPanel
extends PanelContainer

var map: Node
var _grid: GridContainer
var _units: HBoxContainer
var _tiles := {}


static func make(p_map: Node) -> FactionPanel:
	var p := FactionPanel.new()
	p.map = p_map
	return p


func _ready() -> void:
	custom_minimum_size = Vector2(400, 0)
	var v := UiKit.vbox(6)
	add_child(v)
	v.add_child(UiKit.label(Loc.t("select_faction").to_upper(), "PanelTitle"))
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	v.add_child(_grid)
	var d: CampaignData = map.data
	for code in d.factions.get("featured", []):
		var cid := int(d.by_code.get(code, 0))
		if cid > 0:
			_tile(cid)
	_tile(0)
	v.add_child(UiKit.label(Loc.t("starting_units").to_upper(), "StatLabel"))
	_units = UiKit.hbox(6)
	v.add_child(_units)
	EventBus.country_previewed.connect(func(c: int): _mark(c); _show_units(c))
	EventBus.country_chosen.connect(func(c: int): _mark(c); _show_units(c))
	EventBus.turn_ended.connect(func(_t): _show_units(map.rules.player_id))
	_show_units(int(d.by_code.get("UZB", 0)))


func _tile(cid: int) -> void:
	var c: CountryData = map.data.countries.get(cid)
	var b := Button.new()
	b.theme_type_variation = "TabButton"
	b.custom_minimum_size = Vector2(72, 62)
	b.tooltip_text = Loc.country(c) if c else Loc.t("custom_hint")
	var v := UiKit.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	if c:
		var f := FlagRect.make(c, Vector2(44, 28))
		f.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(f)
	else:
		var ic := UiIcon.make("globe", 28)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
	var nm := (Loc.country(c) if c else Loc.t("custom")).to_upper()
	if c and nm.length() > 11:
		nm = c.code                      # uzun nom katakka sig'maydi: ISO kod (to'liq nomi tooltip'da)
	var l := UiKit.label(nm, "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_font_size_override("font_size", 11)
	l.clip_text = true
	v.add_child(l)
	b.add_child(v)
	b.pressed.connect(func(): _pick(cid))
	b.disabled = c != null and c.province_count == 0
	_grid.add_child(b)
	_tiles[cid] = b


func _pick(cid: int) -> void:
	if map.rules.phase != "choose":
		if cid > 0:
			map.cam.focus(map.province_world(map.data.countries[cid].capital))
		return
	if cid == 0:
		EventBus.campaign_message.emit(Loc.t("custom_hint"))
		_mark(0)
		return
	map.preview_country(cid)
	map.cam.focus(map.province_world(map.data.countries[cid].capital))


func _mark(cid: int) -> void:
	for k in _tiles:
		_tiles[k].theme_type_variation = "TabButtonActive" if k == cid else "TabButton"


## Boshlang'ich (yoki hozirgi) qo'shin tarkibi: ikonka + soni.
func _show_units(cid: int) -> void:
	UiKit.clear(_units)
	var c: CountryData = map.data.countries.get(cid)
	if c == null:
		return
	var f: Dictionary = map.data.factions
	var comp: Dictionary = f.get("composition", {}).get(c.code, f.get("composition", {}).get("default", {}))
	var regs: int = map.rules.strength(cid).x
	var per := int(f.get("units_per_regiment", 10))
	for ut in f.get("unit_types", []):
		var n := int(round(regs * per * float(comp.get(ut.id, 0.0))))
		var card := UiKit.panel("CardPanel")
		card.custom_minimum_size = Vector2(70, 50)
		card.tooltip_text = Loc.t("unit." + str(ut.id))
		var v := UiKit.vbox(0)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		var ic := UiIcon.make(str(ut.id), 26)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
		v.add_child(UiKit.label(UiKit.num(n), "PanelTitle", HORIZONTAL_ALIGNMENT_CENTER))
		card.add_child(v)
		_units.add_child(card)
