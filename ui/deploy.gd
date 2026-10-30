## DEPLOY TO BATTLEFIELD: tanlangan operatsiya, loadout, qurol va texnikani GameSession ga yozadi va jang
## sahnasini (demo.tscn) yuklash ekrani bilan ochadi. Jang sahnasi rejimni GameSession.deploy dan o'qiydi.
class_name Deploy
extends RefCounted


static func start(op: OperationData) -> void:
	var p: PlayerProfile = GameSession.profile
	GameSession.deploy = {"kind": "operation", "id": op.id, "battle_mode": op.battle_mode,
		"vehicles": Array(p.selected_vehicles), "weapon": p.equipped_weapon, "loadout": p.active_loadout}
	p.last_mission = op.id
	Shop.track("deploys")
	GameSession.save()
	ScreenManager.deploy_battle()
