extends Node
## Global signal bus. Every system talks through here so that the world map,
## the battlefield and the UI never need direct references to each other.

# --- application flow -------------------------------------------------------
signal screen_requested(screen_id: String, payload: Dictionary)
signal notice(text: String, kind: String)      # kind: info | good | warn | bad

# --- networking -------------------------------------------------------------
signal net_state_changed(state: int)           # Net.State
signal lobby_updated(players: Array)
signal chat_received(sender: String, text: String, channel: String)

# --- world / global map -----------------------------------------------------
signal world_loaded()
signal world_tick(day: int)
signal nation_changed(nation_id: String)
signal province_changed(province_id: int)
signal treasury_changed(nation_id: String, resources: Dictionary)
signal diplomacy_changed(a: String, b: String)
signal war_declared(attacker: String, defender: String)
signal peace_signed(a: String, b: String)
signal vote_opened(vote: Dictionary)
signal vote_updated(vote: Dictionary)
signal vote_closed(vote: Dictionary, passed: bool)

# --- battlefield ------------------------------------------------------------
signal battle_requested(config: Dictionary)
signal battle_started(config: Dictionary)
signal battle_ended(result: Dictionary)
signal objective_captured(point_id: String, team: int)
signal tickets_changed(team: int, tickets: int)
signal unit_spawned(unit: Node)
signal unit_died(unit: Node)
signal selection_changed(units: Array)
signal supply_changed(team: int, supply: float)
signal weather_changed(season: String, weather: String)
