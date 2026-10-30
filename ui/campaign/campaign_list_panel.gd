## CURRENT CAMPAIGN: kampaniya nomi, missiyalar ro'yxati (bajarilgan belgisi, hozirgi, qulflanganlar).
class_name CampaignListPanel
extends PanelContainer

var map: Node
var selected := ""
var _list: VBoxContainer


static func make(p_map: Node) -> CampaignListPanel:
	var p := CampaignListPanel.new()
	p.map = p_map
	return p


func _ready() -> void:
	theme_type_variation = "PanelContainer"
	custom_minimum_size = Vector2(300, 0)
	var v := UiKit.vbox(6)
	add_child(v)
	v.add_child(UiKit.label(Loc.t("current_campaign").to_upper(), "SmallLabel"))
	v.add_child(UiKit.label(Loc.t("campaign.title").to_upper(), "HeaderLabel"))
	_list = UiKit.vbox(3)
	v.add_child(_list)
	for s in [EventBus.campaign_changed, EventBus.language_changed]:
		s.connect(refresh)
	EventBus.turn_ended.connect(func(_t): refresh())
	EventBus.country_chosen.connect(func(_c):
		var m: MissionData = map.rules.missions.current()
		if m: select(m.id))
	refresh()


func select(id: String) -> void:
	selected = id
	EventBus.mission_selected.emit(id)
	refresh()


func refresh() -> void:
	UiKit.clear(_list)
	var ms: CampaignMissions = map.rules.missions
	if selected == "" and not ms.list.is_empty():
		selected = ms.list[0].id
	var k := 0
	for m in ms.list:
		k += 1
		var done: bool = ms.done.has(m.id)
		var open: bool = ms.available(m)
		var b := Button.new()
		b.theme_type_variation = "TabButtonActive" if m.id == selected else "TabButton"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 30)
		b.text = "      %02d   %s" % [k, Loc.t(m.title)]
		var ic := UiIcon.make("check" if done else ("lock" if not open else "target"), 16, UiKit.GREEN if done else (UiKit.DIM if not open else UiKit.AMBER))
		ic.position = Vector2(8, 7)
		b.add_child(ic)
		b.disabled = not open and not done
		var id: String = m.id
		b.pressed.connect(func(): select(id))
		_list.add_child(b)
