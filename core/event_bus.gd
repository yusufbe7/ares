extends Node
## Global signal bus. The battlefield, the HUD and the menus talk through here
## so none of them needs a direct reference to the others.

signal screen_requested(screen_id: String, payload: Dictionary)
signal notice(text: String, kind: String)      # kind: info | good | warn | bad

signal battle_started(config: Dictionary)
signal battle_ended(result: Dictionary)
signal objective_captured(point_id: String, team: int)
signal tickets_changed(team: int, tickets: int)
signal unit_spawned(unit: Node)
signal unit_died(unit: Node)
signal selection_changed(units: Array)
signal supply_changed(team: int, supply: float)
signal support_changed(team: int, kind: String, ready: bool)
