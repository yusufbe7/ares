extends Node
## What the player is doing right now. The game is one thing — a battle — so
## this holds the last setup, the last result, and the screen switcher.

var last_setup: Dictionary = {}
## The global campaign: the bloc the player leads and the countries they have
## taken, kept so the world map survives leaving it for a battle.
var player_faction: String = "atlantic"
var conquests: Dictionary = {}
var last_conquest: String = ""
var last_battle_result: Dictionary = {}

func go(screen_id: String, payload: Dictionary = {}) -> void:
	EventBus.screen_requested.emit(screen_id, payload)

func notify(text: String, kind: String = "info") -> void:
	EventBus.notice.emit(text, kind)

## Remembers the last battle setup so "play again" does not make the player
## rebuild the whole thing.
func remember_setup(options: Dictionary) -> void:
	last_setup = options.duplicate(true)

func record_conquest(country_id: String, faction_id: String) -> void:
	conquests[country_id] = faction_id
	last_conquest = country_id
