class_name Diplomacy
extends RefCounted
## Relations, alliances, wars and peace treaties between nations.

const TRUCE_DAYS := 60

static func daily(world) -> void:
	for nid in world.nations.keys():
		var n = world.nations[nid]
		# Truces expire.
		for other in n.truce_until.keys().duplicate():
			if int(n.truce_until[other]) <= world.day:
				n.truce_until.erase(other)
		# Opinion drifts slowly toward where the relationship actually stands.
		for other in n.relations.keys():
			var target := 0
			if n.is_at_war_with(str(other)):
				target = -90
			elif n.alliance_id != "" and n.alliance_id == _alliance_of(world, str(other)):
				target = 75
			var cur := n.opinion_of(str(other))
			if cur < target:
				n.set_opinion(str(other), cur + 1)
			elif cur > target:
				n.set_opinion(str(other), cur - 1)

static func _alliance_of(world, nid: String) -> String:
	var n = world.nation(nid)
	return n.alliance_id if n != null else ""

# --- alliances --------------------------------------------------------------

static func create_alliance(world, founder: String, alliance_name: String) -> String:
	var n = world.nation(founder)
	if n == null:
		return ""
	if n.alliance_id != "":
		return n.alliance_id
	var aid := "alliance_%d" % (world.alliances.size() + 1)
	world.alliances[aid] = {
		"id": aid,
		"name": alliance_name if alliance_name != "" else "%s ittifoqi" % n.display_name,
		"members": [founder],
		"leader": founder,
		"founded": world.day,
	}
	n.alliance_id = aid
	world.push_log("%s ittifoqi tuzildi." % world.alliances[aid]["name"])
	EventBus.diplomacy_changed.emit(founder, "")
	return aid

## 3..10 members, as designed: small enough to still be a pact, big enough to
## redraw the map.
static func join_alliance(world, nid: String, aid: String) -> String:
	var n = world.nation(nid)
	if n == null or not world.alliances.has(aid):
		return "Ittifoq topilmadi."
	if n.alliance_id != "":
		return "Siz allaqachon ittifoqdasiz."
	var members: Array = world.alliances[aid]["members"]
	if members.size() >= 10:
		return "Ittifoq to'lgan (eng ko'pi 10 davlat)."
	for m in members:
		if n.is_at_war_with(str(m)):
			return "Ittifoq a'zosi bilan urushdasiz."
	members.append(nid)
	n.alliance_id = aid
	for m in members:
		var mn = world.nation(str(m))
		if mn != null and str(m) != nid:
			mn.shift_opinion(nid, 25)
			n.shift_opinion(str(m), 25)
	world.push_log("%s %s ittifoqiga qo'shildi." % [n.display_name, world.alliances[aid]["name"]])
	EventBus.diplomacy_changed.emit(nid, "")
	return ""

static func leave_alliance(world, nid: String) -> void:
	var n = world.nation(nid)
	if n == null or n.alliance_id == "":
		return
	var aid := n.alliance_id
	var pact: Dictionary = world.alliances.get(aid, {})
	var members: Array = pact.get("members", [])
	members.erase(nid)
	n.alliance_id = ""
	for m in members:
		var mn = world.nation(str(m))
		if mn != null:
			mn.shift_opinion(nid, -20)
	if members.size() <= 1:
		for m in members:
			var last = world.nation(str(m))
			if last != null:
				last.alliance_id = ""
		world.alliances.erase(aid)
	EventBus.diplomacy_changed.emit(nid, "")

static func alliance_members(world, nid: String) -> Array:
	var n = world.nation(nid)
	if n == null or n.alliance_id == "":
		return []
	return world.alliances.get(n.alliance_id, {}).get("members", [])

# --- war --------------------------------------------------------------------

## Returns "" when a war may legally be declared, otherwise the reason it may not.
static func can_declare_war(world, attacker: String, defender: String) -> String:
	var a = world.nation(attacker)
	var d = world.nation(defender)
	if a == null or d == null:
		return "Davlat topilmadi."
	if attacker == defender:
		return "O'zingizga urush ocholmaysiz."
	if a.is_at_war_with(defender):
		return "Siz allaqachon urushdasiz."
	if a.has_truce_with(defender, world.day):
		return "Sulh muddati tugamagan (%d kun qoldi)." % (int(a.truce_until[defender]) - world.day)
	if a.alliance_id != "" and a.alliance_id == d.alliance_id:
		return "Ittifoqdoshingizga hujum qila olmaysiz."
	if not _has_contact(world, attacker, defender):
		return "Bu davlat bilan umumiy chegara yoki ittifoqdosh orqali yo'l yo'q."
	return ""

static func _has_contact(world, a: String, b: String) -> bool:
	if world._shares_border(a, b):
		return true
	for m in alliance_members(world, a):
		if world._shares_border(str(m), b):
			return true
	return false

## Declares war and drags both alliances in. Called by WarCouncil once a vote
## passes, or directly by the AI.
static func declare_war(world, attacker: String, defender: String, reason: String = "") -> String:
	var blocked := can_declare_war(world, attacker, defender)
	if blocked != "":
		return blocked
	var involved_attackers: Array = [attacker]
	var involved_defenders: Array = [defender]
	for m in alliance_members(world, attacker):
		if str(m) != attacker:
			involved_attackers.append(str(m))
	for m in alliance_members(world, defender):
		if str(m) != defender:
			involved_defenders.append(str(m))
	for x in involved_attackers:
		for y in involved_defenders:
			_set_war(world, str(x), str(y))
	world.wars.append({
		"attacker": attacker, "defender": defender,
		"attackers": involved_attackers, "defenders": involved_defenders,
		"since": world.day, "reason": reason, "fronts": [],
	})
	world.push_log("URUSH: %s -> %s (%s)" % [attacker, defender, reason])
	EventBus.war_declared.emit(attacker, defender)
	return ""

static func _set_war(world, a: String, b: String) -> void:
	var na = world.nation(a)
	var nb = world.nation(b)
	if na == null or nb == null or a == b:
		return
	if not na.at_war_with.has(b):
		na.at_war_with.append(b)
	if not nb.at_war_with.has(a):
		nb.at_war_with.append(a)
	na.set_opinion(b, -90)
	nb.set_opinion(a, -90)

# --- peace ------------------------------------------------------------------

## Peace terms: {"provinces": [ids to hand to the winner], "reparations": money,
## "trade": bool, "winner": nation id}
static func make_peace(world, a: String, b: String, terms: Dictionary) -> String:
	var na = world.nation(a)
	var nb = world.nation(b)
	if na == null or nb == null:
		return "Davlat topilmadi."
	if not na.is_at_war_with(b):
		return "Siz urushda emassiz."
	na.at_war_with.erase(b)
	nb.at_war_with.erase(a)
	na.truce_until[b] = world.day + TRUCE_DAYS
	nb.truce_until[a] = world.day + TRUCE_DAYS
	na.set_opinion(b, -20)
	nb.set_opinion(a, -20)

	var winner := str(terms.get("winner", ""))
	if winner != "":
		for pid in terms.get("provinces", []):
			world.transfer_province(int(pid), winner)
		var reparations := float(terms.get("reparations", 0.0))
		if reparations > 0.0:
			var loser: String = b if winner == a else a
			var ln = world.nation(loser)
			var wn = world.nation(winner)
			var paid: float = minf(reparations, float(ln.resources.get("money", 0.0)))
			ln.resources["money"] = float(ln.resources["money"]) - paid
			wn.resources["money"] = float(wn.resources.get("money", 0.0)) + paid
	if bool(terms.get("trade", false)):
		na.shift_opinion(b, 15)
		nb.shift_opinion(a, 15)
	# Clean the war record.
	for i in range(world.wars.size() - 1, -1, -1):
		var w: Dictionary = world.wars[i]
		var pair_a: bool = str(w["attacker"]) == a and str(w["defender"]) == b
		var pair_b: bool = str(w["attacker"]) == b and str(w["defender"]) == a
		if pair_a or pair_b:
			world.wars.remove_at(i)
	world.push_log("TINCHLIK: %s va %s sulh tuzdi." % [a, b])
	EventBus.peace_signed.emit(a, b)
	return ""

## How likely the other side is to accept, 0..1. The UI shows this before the
## player sends an offer, and the AI uses the same number to answer.
static func peace_acceptance(world, asker: String, target: String, terms: Dictionary) -> float:
	var na = world.nation(asker)
	var nt = world.nation(target)
	if na == null or nt == null:
		return 0.0
	var score := 0.35
	score += nt.war_weariness * 0.5
	score -= float(terms.get("provinces", []).size()) * 0.12
	score -= float(terms.get("reparations", 0.0)) / 8000.0
	var ratio: float = na.total_strength() / maxf(nt.total_strength(), 1.0)
	score += clampf((ratio - 1.0) * 0.25, -0.3, 0.3)
	var lost_ground := 0
	for pid in world.provinces.keys():
		var p = world.province(int(pid))
		if p != null and p.unrest > 0.5 and p.owner_id == asker:
			lost_ground += 1
	score += float(lost_ground) * 0.02
	return clampf(score, 0.0, 1.0)
