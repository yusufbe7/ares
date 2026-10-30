## Kampaniya <-> 3D jang ko'prigi.
##   start()         - hujum operatsiyasidan jang so'rovi: kampaniya avto-saqlanadi (slot 0), jang sahnasi ochiladi;
##   men_for()       - polklar -> askarlar (units_per_regiment; juda katta janglar masshtablanadi);
##   finish()        - jang natijasi (askarlar) -> polklar, kampaniyaga qaytish;
##   apply_pending() - kampaniya yuklangach natijani qo'llaydi (hudud egasi, qo'shinlar, jang log'i).
class_name BattleBridge
extends RefCounted

const MAX_MEN := 320                 ## bir tomonda eng ko'p askar (zaxira); ko'pi masshtablanadi


static func start(map: Node, op: Dictionary) -> void:
	var gs := _gs(map)
	var r: CampaignRules = map.rules
	var upr := int(map.data.factions.get("units_per_regiment", 10))
	var garrison := maxf(float(op.def_regiments), r.defence(op.to))
	var req := {"province": op.to, "province_name": map.data.provinces[op.to].name, "biome": op.biome, "seed": op.seed,
		"attacker": op.attacker, "defender": op.defender, "att_regiments": int(op.count),
		"def_regiments": int(ceil(garrison)), "player_defends": op.defender == r.player_id, "method": op.method,
		"army_id": op.army.id, "from": op.from, "to": op.to, "count": op.count, "upr": upr}
	var a: int = req.att_regiments * upr
	var d: int = req.def_regiments * upr
	req.scale = maxf(1.0, float(maxi(a, d)) / MAX_MEN)
	req.att_men = maxi(10, int(a / req.scale))
	req.def_men = maxi(10, int(d / req.scale))
	gs.battle_request = req
	gs.battle_result = {}
	var sm := map.get_tree().root.get_node("SaveManager")
	sm.save_campaign(0, CampaignSave.to_dict(r))
	gs.deploy = {"kind": "campaign", "battle_mode": "operation"}
	map.get_tree().root.get_node("ScreenManager").deploy_battle()


## Jang sahnasi uchun: [bizning askarlar, dushman askarlari] (o'yinchi hujumda yoki himoyada).
static func men_for(req: Dictionary) -> Array:
	if req.get("player_defends", false):
		return [int(req.def_men), int(req.att_men)]
	return [int(req.att_men), int(req.def_men)]


## Jang tugadi: player_won - o'yinchi tomoni yutdimi, left - [bizning qolgan askarlar, dushmanniki].
static func finish(tree: SceneTree, player_won: bool, left: Array) -> void:
	var gs := tree.root.get_node("GameSession")
	var req: Dictionary = gs.battle_request
	var k: float = float(req.get("scale", 1.0)) / float(req.get("upr", 10))
	var ours := int(ceil(left[0] * k))
	var theirs := int(ceil(left[1] * k))
	var defends: bool = req.get("player_defends", false)
	gs.battle_result = {"won": player_won != defends, "att_left": theirs if defends else ours, "def_left": ours if defends else theirs}
	tree.root.get_node("ScreenManager").open_campaign(0)


## Jang sahnasidan avto-hisoblash: natija kampaniyada odatdagi avto-jang bilan hisoblanadi.
static func finish_auto(tree: SceneTree) -> void:
	tree.root.get_node("GameSession").battle_result = {"auto": true}
	tree.root.get_node("ScreenManager").open_campaign(0)


## Kampaniya slot 0 dan yuklangandan keyin: kutilayotgan jang natijasini qo'llaydi.
static func apply_pending(map: Node) -> void:
	var gs := _gs(map)
	var req: Dictionary = gs.battle_request
	var res: Dictionary = gs.battle_result
	if req.is_empty() or res.is_empty():
		return
	gs.battle_request = {}
	gs.battle_result = {}
	var army: ArmyData = null
	for a in map.data.armies:
		if a.id == int(req.army_id):
			army = a
	if army == null:
		return
	var before := army.size
	var op := {"army": army, "from": int(req.from), "to": int(req.to), "method": str(req.method), "count": int(req.count),
		"attacker": int(req.attacker), "defender": int(req.defender)}
	op.biome = str(req.get("biome", "temperate"))
	if res.get("auto", false):
		res = {"won": map.ops.resolve_auto(op)}
	else:
		map.ops.apply_result(op, res)
	var player_won: bool = bool(res.won) == (int(req.attacker) == map.rules.player_id)
	map.get_tree().root.get_node("EventBus").campaign_message.emit(Loc.t("op.result", [str(req.province_name), Loc.t("victory") if player_won else Loc.t("defeat"),
		maxi(0, before - army.size), army.size]))
	map.cam.focus(map.province_world(int(req.to)))


static func _gs(n: Node) -> Node:
	return n.get_tree().root.get_node("GameSession")
