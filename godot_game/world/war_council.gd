class_name WarCouncil
extends RefCounted
## The national council: how several players sharing one nation agree on the
## decisions that bind everybody — declaring war, signing peace, joining an
## alliance, and any spending beyond one player's own authority.
##
## The design rule that drives all of this: a nation must stay playable when
## half of its players are offline. So every vote carries a deadline, absent
## players abstain instead of blocking, and each role has a standing spending
## limit it may use without asking anyone.

const DEFAULT_DEADLINE_DAYS := 2

static func vote_weight(role: int) -> int:
	match role:
		GameState.Role.HEAD_OF_STATE: return 2
		GameState.Role.COMMANDER: return 1
		GameState.Role.OFFICER: return 1
	return 0

## Opens a vote. Returns the vote dictionary, or {} with an "error" key set.
static func open_vote(world, nation_id: String, kind: String, payload: Dictionary,
		proposer_peer: int, deadline_days: int = DEFAULT_DEADLINE_DAYS) -> Dictionary:
	var n = world.nation(nation_id)
	if n == null:
		return {"error": "Davlat topilmadi."}
	var role: int = n.player_role(proposer_peer)
	if not GameState.can_vote(role):
		return {"error": "Sizda bunday taklif kiritish huquqi yo'q."}
	for vid in world.votes.keys():
		var existing: Dictionary = world.votes[vid]
		if str(existing.get("nation", "")) == nation_id and str(existing.get("kind", "")) == kind \
				and str(existing.get("status", "")) == "open" \
				and existing.get("payload", {}) == payload:
			return {"error": "Xuddi shunday ovoz berish allaqachon ochiq."}

	var eligible: Array = []
	var total_weight := 0
	for p in n.players:
		var w := vote_weight(int(p.get("role", GameState.Role.OBSERVER)))
		if w > 0:
			eligible.append({"peer": int(p.get("peer", -1)), "name": str(p.get("name", "?")), "weight": w})
			total_weight += w

	var vote := {
		"id": world.next_vote_id(),
		"nation": nation_id,
		"kind": kind,
		"payload": payload,
		"title": describe(world, kind, payload),
		"proposer": proposer_peer,
		"proposer_role": role,
		"opened_day": world.day,
		"deadline_day": world.day + maxi(1, deadline_days),
		"eligible": eligible,
		"total_weight": total_weight,
		"ballots": {},            # String(peer) -> bool
		"status": "open",
	}
	# The proposer always votes yes for their own motion.
	vote["ballots"][str(proposer_peer)] = true
	world.votes[vote["id"]] = vote
	world.push_log("%s: ovoz berish ochildi — %s" % [nation_id, vote["title"]])
	EventBus.vote_opened.emit(vote)
	_check_immediate(world, vote)
	return vote

static func cast_vote(world, vote_id: String, peer: int, approve: bool) -> String:
	if not world.votes.has(vote_id):
		return "Ovoz berish topilmadi."
	var vote: Dictionary = world.votes[vote_id]
	if str(vote["status"]) != "open":
		return "Ovoz berish yopilgan."
	var n = world.nation(str(vote["nation"]))
	if n == null:
		return "Davlat topilmadi."
	if not GameState.can_vote(n.player_role(peer)):
		return "Sizda ovoz berish huquqi yo'q."
	vote["ballots"][str(peer)] = approve
	EventBus.vote_updated.emit(vote)
	_check_immediate(world, vote)
	return ""

static func tally(vote: Dictionary) -> Dictionary:
	var yes := 0
	var no := 0
	var cast := 0
	var cast_by_others := 0
	var proposer := str(vote.get("proposer", -1))
	for row in vote.get("eligible", []):
		var key := str(row["peer"])
		if not vote["ballots"].has(key):
			continue
		cast += 1
		if key != proposer:
			cast_by_others += 1
		if bool(vote["ballots"][key]):
			yes += int(row["weight"])
		else:
			no += int(row["weight"])
	return {"yes": yes, "no": no, "cast": cast, "others": cast_by_others,
		"total": int(vote.get("total_weight", 0))}

## Closes the vote early once the result can no longer change.
static func _check_immediate(world, vote: Dictionary) -> void:
	var t: Dictionary = tally(vote)
	var total: int = int(t["total"])
	if total <= 0:
		return
	if int(t["yes"]) * 2 > total:
		_close(world, vote, true)
	elif int(t["no"]) * 2 >= total:
		_close(world, vote, false)

static func daily(world) -> void:
	for vid in world.votes.keys().duplicate():
		var vote: Dictionary = world.votes[vid]
		if str(vote["status"]) != "open":
			continue
		if world.day < int(vote["deadline_day"]):
			continue
		var t: Dictionary = tally(vote)
		var passed: bool
		if int(t["others"]) == 0:
			# Nobody else showed up before the deadline. A commander or head of
			# state may still act alone — that is the rule that keeps a nation
			# playable when its other players are offline — but an officer's
			# motion simply lapses.
			passed = int(vote["proposer_role"]) >= GameState.Role.COMMANDER
		else:
			passed = int(t["yes"]) > int(t["no"])
		_close(world, vote, passed)

static func _close(world, vote: Dictionary, passed: bool) -> void:
	vote["status"] = "passed" if passed else "failed"
	if passed:
		var err := execute(world, vote)
		if err != "":
			vote["status"] = "failed"
			vote["error"] = err
			world.push_log("%s: qaror bajarilmadi — %s" % [vote["nation"], err])
	world.push_log("%s: %s — %s" % [vote["nation"], vote["title"],
		"qabul qilindi" if str(vote["status"]) == "passed" else "rad etildi"])
	EventBus.vote_closed.emit(vote, str(vote["status"]) == "passed")

static func execute(world, vote: Dictionary) -> String:
	var nid := str(vote["nation"])
	var payload: Dictionary = vote.get("payload", {})
	match str(vote["kind"]):
		"declare_war":
			return Diplomacy.declare_war(world, nid, str(payload.get("target", "")),
				str(payload.get("reason", "Kengash qarori")))
		"peace":
			return Diplomacy.make_peace(world, nid, str(payload.get("target", "")),
				payload.get("terms", {}))
		"join_alliance":
			return Diplomacy.join_alliance(world, nid, str(payload.get("alliance", "")))
		"create_alliance":
			Diplomacy.create_alliance(world, nid, str(payload.get("name", "")))
			return ""
		"leave_alliance":
			Diplomacy.leave_alliance(world, nid)
			return ""
		"spend":
			return _execute_spend(world, nid, payload)
	return "Noma'lum qaror turi."

static func _execute_spend(world, nid: String, payload: Dictionary) -> String:
	match str(payload.get("action", "")):
		"build":
			return Economy.start_construction(world, nid,
				int(payload.get("province", -1)), str(payload.get("building", "")))
		"recruit":
			return Economy.recruit(world, nid, int(payload.get("army", -1)),
				str(payload.get("unit", "")), int(payload.get("count", 1)))
	return "Noma'lum xarajat."

# ---------------------------------------------------------------------------
# Spending authority
# ---------------------------------------------------------------------------

## True when this player may commit the cost on their own. Anything bigger has
## to go to the council, which is what keeps one player from emptying the
## treasury while the rest of the team is asleep.
static func within_authority(world, nid: String, peer: int, cost: Dictionary) -> bool:
	var n = world.nation(nid)
	if n == null:
		return false
	var share := GameState.spend_share(n.player_role(peer))
	if share <= 0.0:
		return false
	# A nation with a single human player is not a committee.
	if n.human_players().size() <= 1:
		return true
	for k in cost.keys():
		var have: float = float(n.resources.get(str(k), 0.0))
		if float(cost[k]) > have * share:
			return false
	return true

## The one entry point the UI uses for any spending action: it either performs
## the action immediately or opens a council vote and says so.
## Returns {"ok": bool, "vote": Dictionary, "error": String}
static func request_spend(world, nid: String, peer: int, action: String,
		payload: Dictionary, cost: Dictionary) -> Dictionary:
	var full: Dictionary = payload.duplicate()
	full["action"] = action
	if within_authority(world, nid, peer, cost):
		var err := _execute_spend(world, nid, full)
		return {"ok": err == "", "error": err, "vote": {}}
	var vote := open_vote(world, nid, "spend", full, peer)
	if vote.has("error"):
		return {"ok": false, "error": str(vote["error"]), "vote": {}}
	return {"ok": false, "error": "", "vote": vote}

static func describe(world, kind: String, payload: Dictionary) -> String:
	match kind:
		"declare_war":
			return "%s ga urush e'lon qilish" % str(payload.get("target", "?"))
		"peace":
			return "%s bilan tinchlik shartnomasi" % str(payload.get("target", "?"))
		"join_alliance":
			return "Ittifoqqa qo'shilish"
		"create_alliance":
			return "Yangi ittifoq tuzish"
		"leave_alliance":
			return "Ittifoqdan chiqish"
		"spend":
			match str(payload.get("action", "")):
				"build":
					return "Qurilish: %s" % str(payload.get("building", "?"))
				"recruit":
					return "Safarbarlik: %s x%d" % [str(payload.get("unit", "?")), int(payload.get("count", 1))]
	return kind

static func open_votes_for(world, nid: String) -> Array:
	var out: Array = []
	for vid in world.votes.keys():
		var v: Dictionary = world.votes[vid]
		if str(v.get("nation", "")) == nid and str(v.get("status", "")) == "open":
			out.append(v)
	return out
