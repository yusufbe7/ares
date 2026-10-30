## Yurish oxiri: iqtisod (oltin va supply), qo'shinlar o'sishi, botlar, missiyalar.
##   oltin daromadi  = income_per_province * hududlar + tax_rate * hududlar YaIMi (million $)
##   supply daromadi = sum(resource_supply[resurs] * miqdor)
##   supply xarajati = upkeep_supply_per_regiment * polklar
## Koeffitsiyentlar data/rules.json da.
class_name CampaignTurns
extends RefCounted


## Davlat iqtisodi: {gold_in, gold_out, supply_in, supply_out}
static func economy(r: CampaignRules, cid: int) -> Dictionary:
	var d := r.data
	var gold_in := 0.0
	var sup_in := 0
	var rs: Dictionary = d.rule("resource_supply", {})
	for p in d.provinces.values():
		if p.owner != cid:
			continue
		gold_in += (float(d.rule("income_per_province", 5)) + float(d.rule("tax_rate", 0.00004)) * p.gdp_musd) * r.occupation.income_mult(cid, p.id)
		sup_in += int(rs.get(p.resource, 2)) * p.resource_amount
	var regs := r.strength(cid).x
	return {"gold_in": int(gold_in), "gold_out": 0, "supply_in": sup_in,
		"supply_out": int(regs * int(d.rule("upkeep_supply_per_regiment", 1)))}


static func end_turn(r: CampaignRules) -> void:
	if r.phase != "play":
		return
	var d := r.data
	_due_attacks(r)
	_bots(r)
	r.occupation.end_turn()
	r.turn += 1
	var growth := int(d.rule("growth_cost_gold", 20))
	var max_size := int(d.rule("max_army_size", 30))
	var player_row := {}
	for c in d.countries.values():
		if c.province_count == 0:
			continue
		var e := economy(r, c.id)
		var spent := 0
		for a in d.armies:
			if a.owner != c.id:
				continue
			a.moved = false
			a.busy = maxi(0, a.busy - 1)
			var p: ProvinceData = d.provinces[a.province]
			if p.owner == a.owner and a.supplied and a.size < max_size and int(c.resources.get("gold", 0)) >= growth:
				a.size += 1
				c.resources.gold = int(c.resources.gold) - growth
				spent += growth
		c.resources["gold"] = int(c.resources.get("gold", 0)) + e.gold_in
		c.resources["supply"] = maxi(0, int(c.resources.get("supply", 0)) + e.supply_in - e.supply_out)
		if c.id == r.player_id:
			e.gold_out = spent
			player_row = e
	# qo'shini qolmagan bot davlat poytaxtida yangi qo'shin yollaydi
	var cost := int(d.rule("recruit_cost", 150))
	for c in d.countries.values():
		if c.id == r.player_id or c.province_count == 0 or r.strength(c.id).y > 0:
			continue
		if int(c.resources.get("gold", 0)) >= cost:
			var cap: int = c.capital if d.provinces.has(c.capital) and d.provinces[c.capital].owner == c.id else _any(d, c.id)
			if cap > 0 and r.army_in(cap) == null:
				c.resources.gold = int(c.resources.gold) - cost
				r.new_army(c.id, cap, 4)
	_bots_spend(r, cost)
	if r.player_id > 0 and d.countries.has(r.player_id):
		var pc: CountryData = d.countries[r.player_id]
		player_row["turn"] = r.turn
		player_row["gold"] = int(pc.resources.get("gold", 0))
		player_row["supply"] = int(pc.resources.get("supply", 0))
		r.history.append(player_row)
		if pc.province_count == 0:
			r.phase = "over"
			r.message.emit(Loc.t("game_over"))
	r.supply.update()
	r.missions.check()
	r.message.emit(Loc.t("turn_n", [r.turn]))
	r.armies_changed.emit()
	r.state_changed.emit()


## Bot oltinni to'plab o'tirmaydi: oltini yollash narxining 3 baravaridan ko'p va qo'shini kam bo'lsa
## (har 3 hududga bittadan kam), chegaradagi bo'sh hududda yangi qo'shin yollaydi (yurishiga bittadan).
## O'yinchi ham xuddi shu narxda yollay oladi - bot "aldamaydi".
static func _bots_spend(r: CampaignRules, cost: int) -> void:
	var d := r.data
	var own := {}
	for p in d.provinces.values():
		own.get_or_add(p.owner, []).append(p)
	for c in d.countries.values():
		if c.id == r.player_id or c.province_count == 0:
			continue
		var s: Vector2i = r.strength(c.id)
		if s.y == 0 or int(c.resources.get("gold", 0)) < cost * 3 or s.y >= maxi(1, c.province_count / 3):
			continue
		var best := 0
		for p in own.get(c.id, []):
			if r.army_in(p.id) != null:
				continue
			var border := false
			for n in p.neighbors:
				if d.provinces.has(n) and d.provinces[n].owner != c.id:
					border = true
					break
			if border or best == 0:
				best = p.id
				if border:
					break
		if best > 0:
			c.resources.gold = int(c.resources.gold) - cost
			r.new_army(c.id, best, int(d.rule("recruit_size", 3)) + 1)


static func _any(d: CampaignData, cid: int) -> int:
	for p in d.provinces.values():
		if p.owner == cid:
			return p.id
	return 0


## Botlar: o'yinchi bilan bir xil qoidalar.
##  1) Urush e'loni: zaif qo'shnisiga (kuchi 1.5 baravar kam) kichik ehtimol bilan.
##  2) Hujum: urushdagi qo'shni hududlardan eng zaifiga, kuch nisbati yetarli bo'lsa.
static func _bots(r: CampaignRules) -> void:
	var d := r.data
	var chance := float(d.rule("bot_declare_war_chance", 0.12))
	var ratio := float(d.rule("bot_declare_war_ratio", 1.5))
	var attack := float(d.rule("bot_attack_ratio", 1.35))
	var nb_countries := {}
	for p in d.provinces.values():
		for n in p.neighbors:
			var q: ProvinceData = d.provinces.get(n)
			if q and q.owner != p.owner:
				nb_countries.get_or_add(p.owner, {})[q.owner] = true
	for c in d.countries.values():
		if c.id == r.player_id or c.province_count == 0 or randf() > chance:
			continue
		var mine := r.strength(c.id).x
		var best := 0
		var bs := INF
		for o in nb_countries.get(c.id, {}):
			var s := r.strength(o).x
			if s * ratio < mine and s < bs and r.diplomacy.can_declare(c.id, o):
				bs = s
				best = o
		if best > 0:
			r.declare_war(c.id, best)
	for a in d.armies.duplicate():
		if not (a in d.armies) or a.owner == r.player_id or a.moved or a.busy > 0:
			continue
		var from: ProvinceData = d.provinces[a.province]
		var target := -1
		var best_score := 0.0
		for n in from.neighbors:
			var tp: ProvinceData = d.provinces.get(n)
			if tp == null or tp.owner == a.owner or not r.diplomacy.at_war(a.owner, tp.owner):
				continue
			var score: float = a.size * r.supply.factor(a) / r.defence(n)
			if score > attack and score > best_score:
				best_score = score
				target = n
		if target > 0 and d.provinces[target].owner == r.player_id:
			_announce(r, a, target)
		elif target > 0:
			r.order_move(a, target)


## Botning o'yinchiga hujumi bir yurish oldin e'lon qilinadi (qo'shin yo'lga chiqadi, o'yinchi tayyorlanadi).
static func _announce(r: CampaignRules, a: ArmyData, target: int) -> void:
	var c: CountryData = r.data.countries[a.owner]
	c.resources["supply"] = maxi(int(c.resources.get("supply", 0)), a.size)       # bot ta'minotsiz qolib ketmasin
	var op := r.ops.launch(a, target, "land", a.size)
	if op.is_empty():
		return
	r.incoming.append({"op": op, "due": r.turn + int((r.data.rule("operations", {}) as Dictionary).get("warning_turns", 1))})
	r.message.emit(Loc.t("op.incoming", [r.data.provinces[target].name, Loc.country(c), a.size]))


## Muddati kelgan hujumlar: UI ulangan bo'lsa (attack_due) o'yinchi tanlaydi, bo'lmasa avto-jang.
static func _due_attacks(r: CampaignRules) -> void:
	var keep: Array = []
	for e in r.incoming:
		var op: Dictionary = e.op
		if not (op.army in r.data.armies) or r.data.provinces[op.to].owner != r.player_id:
			continue
		if int(e.due) > r.turn:
			keep.append(e)
		elif r.attack_due.get_connections().is_empty():
			r.ops.resolve_auto(op)
		else:
			r.attack_due.emit(op)
	r.incoming = keep
