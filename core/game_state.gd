extends Node
## What the player is doing right now. The game is one thing — a battle — so
## this holds the last setup, the last result, and the screen switcher.

var last_setup: Dictionary = {}
var last_battle_result: Dictionary = {}

func go(screen_id: String, payload: Dictionary = {}) -> void:
	EventBus.screen_requested.emit(screen_id, payload)

func notify(text: String, kind: String = "info") -> void:
	EventBus.notice.emit(text, kind)

## Remembers the last battle setup so "play again" does not make the player
## rebuild the whole thing.
func remember_setup(options: Dictionary) -> void:
	last_setup = options.duplicate(true)
