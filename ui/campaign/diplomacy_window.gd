## DIPLOMACY (poydevor): urush / tinchlik jadvali. Qoida: urushda bo'lmagan davlat hududiga hujum qilib bo'lmaydi.
## To'liq diplomatiya (ittifoq, savdo, tinchlik shartnomasi) - "Tez orada".
class_name DiplomacyWindow
extends PanelContainer

var map: Node
var _list: VBoxContainer


static func make(p_map: Node) -> DiplomacyWindow:
	var w := DiplomacyWindow.new()
	w.map = p_map
	return w


func _ready() -> void:
	custom_minimum_size = Vector2(520, 0)
	var v := UiKit.vbox(8)
	add_child(v)
	var h := UiKit.hbox()
	h.add_child(UiKit.label(Loc.t("tab.diplomacy").to_upper(), "HeaderLabel"))
	h.add_child(UiKit.spacer())
	h.add_child(UiKit.button("✕", "IconButton", func(): EventBus.tab_changed.emit("world_map")))
	v.add_child(h)
	v.add_child(UiKit.label(Loc.t("dip.rule"), "SmallLabel"))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(500, 300)
	v.add_child(sc)
	_list = UiKit.vbox(4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list)
	v.add_child(UiKit.soon(UiKit.button(Loc.t("dip.full"), "")))
	EventBus.campaign_changed.connect(refresh)
	refresh()


## O'yinchi bilan chegaradosh davlatlar va urushdagi davlatlar.
func refresh() -> void:
	UiKit.clear(_list)
	var r: CampaignRules = map.rules
	if r.player_id == 0:
		_list.add_child(UiKit.label(Loc.t("choose_first"), "SmallLabel"))
		return
	var near := {}
	for p in r.data.provinces.values():
		if p.owner != r.player_id:
			continue
		for n in p.all_neighbors():
			var o: int = r.data.provinces[n].owner
			if o != r.player_id and o > 0:
				near[o] = true
	for e in r.diplomacy.enemies_of(r.player_id):
		near[e] = true
	for cid in near:
		var c: CountryData = r.data.countries.get(cid)
		if c == null or c.province_count == 0:
			continue
		var h := UiKit.hbox(8)
		h.add_child(FlagRect.make(c, Vector2(30, 20)))
		var n := UiKit.label(Loc.country(c))
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(n)
		var war := r.diplomacy.at_war(r.player_id, cid)
		var st := UiKit.label(Loc.t("rel.war") if war else (Loc.t("rel.ally") if r.data.allied(r.player_id, cid) else Loc.t("rel.peace")), "PanelTitle")
		st.add_theme_color_override("font_color", UiKit.RED if war else UiKit.GREEN)
		h.add_child(st)
		if r.diplomacy.can_declare(r.player_id, cid):
			var id: int = cid
			h.add_child(UiKit.button(Loc.t("declare_war"), "", func(): CampaignDialogs.declare_war(map, id)))
		_list.add_child(h)
