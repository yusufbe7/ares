## O'yinchi paneli (yuqori o'ng): avatar, ism, daraja, XP chizig'i, CREDITS, SUPPLY, UNITS, xabarlar, sozlamalar.
## source: "profile" (bosh menyu: PlayerProfile) yoki "campaign" (kampaniya: davlat oltini va supply, qo'shinlar soni).
class_name PlayerPanel
extends PanelContainer

var source := "profile"
var map: Node = null
var _name: Label
var _rank: Label
var _lv: Label
var _xp: ProgressBar
var _credits: Label
var _supply: Label
var _units: Label
var _log: Array = []


static func make(src: String, p_map: Node = null) -> PlayerPanel:
	var p := PlayerPanel.new()
	p.source = src
	p.map = p_map
	return p


func _ready() -> void:
	var h := UiKit.hbox(14)
	add_child(h)
	var av := UiKit.panel("CardPanel")
	var j: Dictionary = CampaignData._json("res://data/game.json", {})
	var ap := str(j.get("avatar", ""))
	if ap != "" and ResourceLoader.exists(ap):
		av.add_child(UiKit.image_slot(load(ap), Vector2(44, 44)))
	else:
		av.add_child(UiIcon.make("soldier", 44, Color(0.75, 0.75, 0.72)))
	h.add_child(av)
	var v := UiKit.vbox(2)
	v.custom_minimum_size = Vector2(150, 0)
	h.add_child(v)
	_name = UiKit.label("", "PanelTitle")
	v.add_child(_name)
	var rh := UiKit.hbox(8)
	_rank = UiKit.label("", "AmberLabel")
	_rank.add_theme_font_size_override("font_size", 13)
	rh.add_child(_rank)
	rh.add_child(UiKit.spacer())
	_lv = UiKit.label("", "SmallLabel")
	rh.add_child(_lv)
	v.add_child(rh)
	_xp = ProgressBar.new()
	_xp.custom_minimum_size = Vector2(150, 5)
	_xp.show_percentage = false
	v.add_child(_xp)
	_credits = _stat(h, "coins", "CREDITS")
	_supply = _stat(h, "crate", "SUPPLY")
	_units = _stat(h, "units", "UNITS")
	var mail := UiKit.button("", "IconButton", _show_log)
	mail.add_child(UiIcon.make("mail", 22))
	mail.custom_minimum_size = Vector2(44, 44)
	mail.get_child(0).position = Vector2(11, 11)
	mail.tooltip_text = Loc.t("messages")
	h.add_child(mail)
	var gear := UiKit.button("", "IconButton", func(): ScreenManager.open("settings"))
	gear.add_child(UiIcon.make("gear", 22))
	gear.custom_minimum_size = Vector2(44, 44)
	gear.get_child(0).position = Vector2(11, 11)
	gear.tooltip_text = Loc.t("settings")
	h.add_child(gear)
	for s in [EventBus.credits_changed, EventBus.profile_changed, EventBus.campaign_changed, EventBus.turn_ended, EventBus.language_changed]:
		s.connect(func(_a = null, _b = null): refresh())
	EventBus.campaign_message.connect(func(t: String): _log.append(t))
	EventBus.toast.connect(func(t: String): _log.append(t))
	refresh()


func _stat(h: HBoxContainer, icon: String, title: String) -> Label:
	var row := UiKit.hbox(6)
	row.add_child(UiIcon.make(icon, 26, UiKit.AMBER))
	var v := UiKit.vbox(-4)
	var val := UiKit.label("0", "BigNumber")
	v.add_child(val)
	v.add_child(UiKit.label(title, "SmallLabel"))
	row.add_child(v)
	h.add_child(row)
	return val


func refresh() -> void:
	var pr: PlayerProfile = GameSession.profile
	_name.text = pr.player_name
	if source == "campaign" and map and map.rules.player_id > 0:
		var r: CampaignRules = map.rules
		var c: CountryData = r.data.countries[r.player_id]
		var ranks: Array = r.data.ranks
		var k := r.rank_index()
		_rank.text = Loc.t(str(ranks[k].name)).to_upper() if not ranks.is_empty() else ""
		var cur := int(ranks[k].xp) if not ranks.is_empty() else 0
		var nxt := int(ranks[mini(k + 1, ranks.size() - 1)].xp) if not ranks.is_empty() else 1
		_lv.text = "XP %d" % r.xp
		_xp.value = 100.0 * (r.xp - cur) / maxf(nxt - cur, 1)
		_credits.text = UiKit.num(int(c.resources.get("gold", 0)))
		_supply.text = UiKit.num(int(c.resources.get("supply", 0)))
		_units.text = str(r.strength(r.player_id).y)
	else:
		_rank.text = Loc.t(pr.rank_key()).to_upper()
		_lv.text = "Lv %d" % pr.level()
		_xp.value = pr.level_progress() * 100.0
		_credits.text = UiKit.num(pr.credits)
		_supply.text = UiKit.num(pr.supply)
		_units.text = str(pr.selected_vehicles.size())


func _show_log() -> void:
	var t := "\n".join(_log.slice(maxi(0, _log.size() - 12))) if not _log.is_empty() else Loc.t("no_messages")
	var d := ConfirmDialog.ask(get_tree().current_scene, Loc.t("messages"), t, "OK", Loc.t("close"))
	d.answered.connect(func(_y): pass)
