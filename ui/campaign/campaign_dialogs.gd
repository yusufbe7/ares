## Kampaniyadagi tasdiqlash oqimlari: urush e'loni, missiyani boshlash.
class_name CampaignDialogs
extends RefCounted


static func declare_war(map: Node, cid: int) -> void:
	var c: CountryData = map.data.countries.get(cid)
	if c == null:
		return
	var d := ConfirmDialog.ask(map.ui.root, Loc.t("declare_war"), Loc.t("declare_war_confirm", [Loc.country(c)]))
	d.answered.connect(func(yes: bool):
		if yes:
			map.rules.declare_war(map.rules.player_id, cid))


## START MISSION: missiya hududiga qo'shni o'z qo'shinimiz bilan hujum (avto-jang).
## Urush yo'q bo'lsa avval urush e'loni so'raladi. Qo'shni qo'shin bo'lmasa - yo'l-yo'riq xabari.
static func start_mission(map: Node, m: MissionData) -> void:
	var r: CampaignRules = map.rules
	if r.phase != "play":
		EventBus.campaign_message.emit(Loc.t("choose_first"))
		return
	var target: int = r.missions.targets.get(m.id, 0)
	if target <= 0:
		EventBus.campaign_message.emit(Loc.t("mission_global"))
		return
	var tp: ProvinceData = map.data.provinces[target]
	if tp.owner == r.player_id:
		map.select_province(target)
		return
	var army: ArmyData = null
	for a in map.data.armies:
		if a.owner == r.player_id and not a.moved and a.busy == 0 and target in map.data.provinces[a.province].all_neighbors():
			if army == null or a.size > army.size:
				army = a
	if army == null:
		map.cam.focus(map.province_world(target))
		EventBus.campaign_message.emit(Loc.t("mission_need_army", [tp.name]))
		return
	var go := func():
		map.cam.focus(map.province_world(target))
		map.order_move(army, target)
	if not r.diplomacy.at_war(r.player_id, tp.owner) and not map.data.allied(r.player_id, tp.owner):
		var c: CountryData = map.data.countries.get(tp.owner)
		var d := ConfirmDialog.ask(map.ui.root, Loc.t("declare_war"), Loc.t("declare_war_confirm", [Loc.country(c)]))
		d.answered.connect(func(yes: bool):
			if yes and r.declare_war(r.player_id, tp.owner):
				go.call())
	else:
		go.call()
