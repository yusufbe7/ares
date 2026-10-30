## MISSION: raqam va nom, rasm, tavsif, OBJECTIVES (haqiqiy holat), REWARDS, START MISSION.
## Missiya tanlansa kamera uning hududiga siljiydi va hudud xaritada belgilanadi.
class_name MissionPanel
extends PanelContainer

var map: Node
var mission: MissionData
var _title: Label
var _img: Control
var _img_box: PanelContainer
var _brief: Label
var _obj: VBoxContainer
var _rew: VBoxContainer
var _start: Button


static func make(p_map: Node) -> MissionPanel:
	var p := MissionPanel.new()
	p.map = p_map
	return p


func _ready() -> void:
	custom_minimum_size = Vector2(520, 0)
	var v := UiKit.vbox(8)
	add_child(v)
	_title = UiKit.label("", "HeaderLabel")
	v.add_child(_title)
	var h := UiKit.hbox(12)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(h)
	_img_box = UiKit.panel("CardPanel")
	_img_box.custom_minimum_size = Vector2(230, 150)
	h.add_child(_img_box)
	var right := UiKit.vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	_brief = UiKit.label("", "SmallLabel")
	_brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_brief.custom_minimum_size = Vector2(240, 0)
	right.add_child(_brief)
	var cols := UiKit.hbox(14)
	right.add_child(cols)
	var oc := UiKit.vbox(3)
	oc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	oc.add_child(UiKit.label(Loc.t("objectives").to_upper(), "StatLabel"))
	_obj = UiKit.vbox(2)
	oc.add_child(_obj)
	cols.add_child(oc)
	var rc := UiKit.vbox(3)
	rc.add_child(UiKit.label(Loc.t("rewards").to_upper(), "StatLabel"))
	_rew = UiKit.vbox(2)
	rc.add_child(_rew)
	cols.add_child(rc)
	_start = UiKit.button("▶  " + Loc.t("start_mission").to_upper(), "AmberButton", func():
		if mission: CampaignDialogs.start_mission(map, mission))
	right.add_child(_start)
	EventBus.mission_selected.connect(_on_select)
	for s in [EventBus.campaign_changed, EventBus.language_changed]:
		s.connect(refresh)
	EventBus.turn_ended.connect(func(_t): refresh())
	var ms: CampaignMissions = map.rules.missions
	if not ms.list.is_empty():
		mission = ms.list[0]
	refresh()


func _on_select(id: String) -> void:
	for m in map.rules.missions.list:
		if m.id == id:
			mission = m
	var t: int = map.rules.missions.targets.get(id, 0)
	map.layers.target_province = t
	if t > 0:
		map.cam.focus(map.province_world(t))
	refresh()


func refresh() -> void:
	if mission == null:
		_title.text = Loc.t("no_missions")
		return
	var ms: CampaignMissions = map.rules.missions
	var idx := ms.list.find(mission) + 1
	_title.text = "%02d.  %s" % [idx, Loc.t(mission.title).to_upper()]
	UiKit.clear(_img_box)
	_img_box.add_child(UiKit.image_slot(mission.image, Vector2(230, 150)))
	_brief.text = Loc.t(mission.briefing)
	UiKit.clear(_obj)
	if map.rules.phase == "choose":
		_obj.add_child(UiKit.label(Loc.t("choose_first"), "SmallLabel"))
	else:
		for s in ms.status(mission):
			var h := UiKit.hbox(6)
			h.add_child(UiIcon.make("check" if s.done else "star", 12, UiKit.GREEN if s.done else UiKit.AMBER))
			var l := UiKit.label(s.text + ("  " + s.progress if s.progress != "" else ""), "SmallLabel")
			if s.done: l.add_theme_color_override("font_color", UiKit.GREEN)
			h.add_child(l)
			_obj.add_child(h)
	UiKit.clear(_rew)
	for k in [["gold", "coins"], ["supply", "crate"], ["xp", "star"]]:
		if mission.rewards.has(k[0]):
			var h := UiKit.hbox(6)
			h.add_child(UiIcon.make(k[1], 14, UiKit.AMBER))
			h.add_child(UiKit.label("%s %s" % [UiKit.num(int(mission.rewards[k[0]])), Loc.t(k[0]).to_upper() if k[0] != "xp" else "XP"], "SmallLabel"))
			_rew.add_child(h)
	var done: bool = ms.done.has(mission.id)
	_start.disabled = done or not ms.available(mission)
	_start.text = ("✔  " + Loc.t("completed").to_upper()) if done else ("▶  " + Loc.t("start_mission").to_upper())
