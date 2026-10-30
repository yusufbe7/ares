## Kampaniya o'yin mantig'i (UI va sahnaga bog'liq emas, headless testda ishlaydi).
## Harakat, jang, bosib olish, yollash, urush e'loni, tajriba (XP). Yurish oxiri: campaign_turns.gd.
## Natijalar signallar orqali chiqadi: xarita va UI ularni tinglaydi.
class_name CampaignRules
extends RefCounted

signal message(text: String)
signal owner_changed(province_id: int, old_owner: int, new_owner: int)
signal armies_changed
signal state_changed
signal battle_fought(entry: Dictionary)
## Bot hujumi o'yinchiga yetib keldi (bir yurish oldin e'lon qilingan): UI 3D himoya yoki avto-jangni so'raydi.
signal attack_due(op: Dictionary)

var data: CampaignData
var diplomacy: CampaignDiplomacy
var supply: CampaignSupply
var missions: CampaignMissions
var ops: CampaignWarOps
var occupation: CampaignOccupation
var incoming: Array = []        ## o'yinchiga e'lon qilingan bot hujumlari: [{op, due}]
var player_id := 0
var turn := 1
var phase := "choose"           ## choose (davlat tanlash) | play | over
var xp := 0
var battle_log: Array = []      ## [{turn, province, attacker, defender, won}]
var history: Array = []         ## o'yinchi iqtisodi: [{turn, gold, supply, income, expense, supply_in, supply_out}]
var setup := {}                 ## davlat tanlash ekrani sozlamalari: {country, mode, difficulty, ironman, no_blocs}


func _init(d: CampaignData) -> void:
	data = d
	diplomacy = CampaignDiplomacy.new(d)
	supply = CampaignSupply.new(d)
	missions = CampaignMissions.new(self)
	ops = CampaignWarOps.new(self)
	occupation = CampaignOccupation.new(self)
	supply.update()


func province_px(id: int) -> Vector2:
	var p: ProvinceData = data.provinces.get(id)
	return Vector2(p.center_px) if p else Vector2.ZERO


func army_in(province_id: int) -> ArmyData:
	for a in data.armies:
		if a.province == province_id:
			return a
	return null


## Davlat kuchi: [polklar soni, qo'shinlar soni]
func strength(cid: int) -> Vector2i:
	var r := Vector2i.ZERO
	for a in data.armies:
		if a.owner == cid:
			r.x += a.size
			r.y += 1
	return r


## Hudud mudofaasi: qo'shin + garnizon (aholidan), tog' va poytaxt bonusi.
func defence(province_id: int) -> float:
	var tp: ProvinceData = data.provinces[province_id]
	var other := army_in(province_id)
	var garrison := 1.0 + minf(3.0, tp.population / 2000000.0)
	var bonus := 1.0 + (0.3 if tp.elevation_m > 1200 else 0.0)
	var dc: CountryData = data.countries.get(tp.owner)
	if dc and dc.capital == tp.id:
		bonus += 0.25
	return ((other.size * supply.factor(other) if other else 0.0) + garrison) * bonus


func rank_index() -> int:
	var k := 0
	for i in data.ranks.size():
		if xp >= int(data.ranks[i].get("xp", 0)):
			k = i
	return k


func add_xp(key: String) -> void:
	xp += int((data.rule("xp", {}) as Dictionary).get(key, 0))


func grant(rewards: Dictionary) -> void:
	var c: CountryData = data.countries.get(player_id)
	if c == null:
		return
	for k in ["gold", "supply"]:
		if rewards.has(k):
			c.resources[k] = int(c.resources.get(k, 0)) + int(rewards[k])
	xp += int(rewards.get("xp", 0))
	state_changed.emit()


func choose_country(cid: int) -> void:
	if not data.countries.has(cid):
		return
	for c in data.countries.values():
		c.controller = "bot"
	player_id = cid
	data.countries[cid].controller = "player"
	phase = "play"
	missions.start(cid)
	message.emit(Loc.t("you_are", [Loc.country(data.countries[cid])]))
	state_changed.emit()


## Davlat tanlash ekrani sozlamalarini qo'llaydi: bloklarsiz boshlash, qiyinlik (rules.json -> difficulty).
## Yangi kampaniyada choose_country dan oldin, saqlangan o'yinda yuklangandan keyin chaqiriladi.
func apply_setup(s: Dictionary, fresh: bool) -> void:
	setup = s.duplicate()
	if bool(s.get("no_blocs", false)):
		for c in data.countries.values():
			c.bloc = ""
	var diff: Dictionary = (data.rule("difficulty", {}) as Dictionary).get(str(int(s.get("difficulty", 2))), {})
	for k in ["bot_attack_ratio", "bot_declare_war_chance"]:
		if diff.has(k):
			data.rules[k] = diff[k]
	if fresh and data.countries.has(player_id) and diff.has("player_gold"):
		var r: Dictionary = data.countries[player_id].resources
		r.gold = int(float(r.get("gold", 0)) * float(diff.player_gold))


## 9. Hududni bosib olish (faqat ma'lumot; xarita owner_changed signalini tinglab rangni yangilaydi).
func conquer(province_id: int, new_owner_id: int) -> void:
	var p: ProvinceData = data.provinces.get(province_id)
	if p == null or p.owner == new_owner_id:
		return
	var old := p.owner
	p.owner = new_owner_id
	data.recount()
	owner_changed.emit(province_id, old, new_owner_id)
	occupation.on_conquer(province_id, old, new_owner_id)
	var oc: CountryData = data.countries.get(old)
	if oc and oc.province_count == 0:
		message.emit(Loc.t("destroyed", [Loc.country(oc)]))
		diplomacy.forget(old)
		for a in data.armies.duplicate():
			if a.owner == old:
				data.armies.erase(a)
	if old == player_id or new_owner_id == player_id:
		supply.update()
	missions.check()
	state_changed.emit()


func declare_war(a: int, b: int) -> bool:
	if not diplomacy.declare_war(a, b, turn):
		return false
	occupation.on_war(a, b)
	if a == player_id:
		add_xp("war_declared")
	if a == player_id or b == player_id:
		message.emit(Loc.t("war_declared", [Loc.country(data.countries[a]), Loc.country(data.countries[b])]))
	missions.check()
	state_changed.emit()
	return true


func recruit(province_id: int) -> bool:
	var p: ProvinceData = data.provinces.get(province_id)
	var c: CountryData = data.countries.get(player_id)
	var cost := int(data.rule("recruit_cost", 150))
	if p == null or c == null or p.owner != player_id or army_in(province_id) != null:
		return false
	if int(c.resources.get("gold", 0)) < cost:
		message.emit(Loc.t("no_gold", [cost]))
		return false
	c.resources.gold = int(c.resources.gold) - cost
	new_army(player_id, province_id, int(data.rule("recruit_size", 3)))
	return true


func new_army(owner: int, province_id: int, size: int) -> ArmyData:
	var a := ArmyData.new()
	var mx := 0
	for o in data.armies: mx = maxi(mx, o.id)
	a.id = mx + 1
	a.owner = owner
	a.province = province_id
	a.size = size
	data.armies.append(a)
	if owner == player_id:
		supply.update()
	armies_changed.emit()
	return a


func remove_army(a: ArmyData) -> void:
	data.armies.erase(a)
	armies_changed.emit()


## Qo'shinni qo'shni hududga yuborish (quruqlik yoki dengiz yo'li).
## Dengiz orqali o'tsa qo'shin keyingi yurishda ham band (rules: sea_move_extra_turns).
## Urushda bo'lmagan davlat hududiga kirib bo'lmaydi. Dushman hududi bo'lsa - jang; yutsa bosib olinadi.
func order_move(a: ArmyData, target: int) -> bool:
	var from: ProvinceData = data.provinces.get(a.province)
	var mine := a.owner == player_id
	if from == null or target == a.province or not (target in from.all_neighbors()):
		if mine: message.emit(Loc.t("only_neighbors"))
		return false
	if a.moved or a.busy > 0:
		if mine: message.emit(Loc.t("already_moved"))
		return false
	var by_sea := from.is_sea_link(target) and not (target in from.neighbors)
	var tp: ProvinceData = data.provinces[target]
	var other := army_in(target)
	if tp.owner != a.owner and not data.allied(a.owner, tp.owner) and not diplomacy.can_attack(a.owner, tp.owner):
		if mine: message.emit(Loc.t("not_at_war", [Loc.country(data.countries.get(tp.owner))]))
		return false
	if other and other.owner != a.owner and data.allied(a.owner, other.owner):
		if mine: message.emit(Loc.t("ally_there"))
		return false
	a.moved = true
	if by_sea:
		a.busy = int(data.rule("sea_move_extra_turns", 1))
	if other and other.owner == a.owner:
		other.size += a.size                        # o'zimizniki: birlashadi
		other.moved = true
		remove_army(a)
		if mine: supply.update()
		state_changed.emit()
		return true
	if tp.owner != a.owner and not data.allied(a.owner, tp.owner) or other:
		if not _battle(a, tp, other):
			armies_changed.emit()
			return false
		a.province = target
		if mine: add_xp("province_taken")
		conquer(target, a.owner)
	else:
		a.province = target
	if mine: supply.update()             # botlar uchun yurish oxirida bir marta hisoblanadi
	armies_changed.emit()
	state_changed.emit()
	return true


## Avtomatik jang: kuch = polklar x ta'minot x tasodif; tog'da va poytaxtda himoyachiga bonus.
func _battle(a: ArmyData, tp: ProvinceData, defender: ArmyData, mult := 1.0) -> bool:
	var dfn := defence(tp.id) * randf_range(0.8, 1.2)
	var att := a.size * supply.factor(a) * randf_range(0.8, 1.2) * mult
	var won := att > dfn
	var start_size := a.size
	if won:
		a.size = maxi(1, a.size - int(ceil(dfn * 0.5)))
		if defender:
			data.armies.erase(defender)
	else:
		a.size = maxi(1, int(a.size * 0.55))
		if defender:
			defender.size = maxi(1, defender.size - int(ceil(att * 0.35)))
	var e := {"turn": turn, "province": tp.id, "attacker": a.owner, "defender": tp.owner, "won": won}
	battle_log.append(e)
	if a.owner == player_id and won:
		missions.battles_won += 1
		add_xp("battle_won")
	if a.owner == player_id or tp.owner == player_id:
		message.emit(Loc.t("battle", [Loc.country(data.countries.get(a.owner)), tp.name, Loc.country(data.countries.get(tp.owner)),
			start_size, int(dfn), Loc.t("victory") if won else Loc.t("defeat")]))
	battle_fought.emit(e)
	return won


## So'nggi N yurishdagi jang bo'lgan hududlar (ziddiyat nuqtalari).
func conflicts() -> Dictionary:
	var n := int(data.rule("conflict_turns", 3))
	var out := {}
	for e in battle_log:
		if turn - int(e.turn) < n:
			out[e.province] = e
	return out
