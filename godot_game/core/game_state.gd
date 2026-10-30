extends Node
## The single place that knows what the local player is doing right now.

enum Mode { NONE, GLOBAL_WAR, BATTLE_ARENA }

## Authority a player holds inside their own nation. Several players share one
## nation, so each one carries a role and the role gates what they may spend.
enum Role { OBSERVER, OFFICER, COMMANDER, HEAD_OF_STATE }

var mode: int = Mode.NONE
var world: WorldState = null
var local_nation: String = ""
var local_role: int = Role.COMMANDER
var local_player_id: int = 1
var last_battle_result: Dictionary = {}
var rng_seed: int = 0
## Campaign progress: the ids of missions already won, kept in the profile.
var completed_missions: Array = []

const PROFILE_PATH := "user://profile.cfg"

func _ready() -> void:
	randomize()
	load_profile()

func load_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PROFILE_PATH) != OK:
		return
	completed_missions = cfg.get_value("campaign", "completed", [])

func save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("campaign", "completed", completed_missions)
	cfg.save(PROFILE_PATH)

func complete_mission(mission_id: String) -> void:
	if mission_id == "" or completed_missions.has(mission_id):
		return
	completed_missions.append(mission_id)
	save_profile()

## A mission is open once the one before it is done; the first is always open.
func mission_unlocked(mission_id: String) -> bool:
	var list: Array = DB.missions
	for i in range(list.size()):
		if str(list[i].get("id", "")) != mission_id:
			continue
		if i == 0:
			return true
		return completed_missions.has(str(list[i - 1].get("id", "")))
	return false

func role_name(role: int) -> String:
	match role:
		Role.OBSERVER: return "Kuzatuvchi"
		Role.OFFICER: return "Ofitser"
		Role.COMMANDER: return "Qo'mondon"
		Role.HEAD_OF_STATE: return "Davlat rahbari"
	return "?"

## Spending limits by role, as a share of the national treasury that one
## player may commit without a council vote. This is the rule that stops a
## single player from emptying the nation on their own.
func spend_share(role: int) -> float:
	match role:
		Role.OBSERVER: return 0.0
		Role.OFFICER: return 0.15
		Role.COMMANDER: return 0.35
		Role.HEAD_OF_STATE: return 0.60
	return 0.0

func can_vote(role: int) -> bool:
	return role >= Role.OFFICER

func start_new_world(seed_value: int = 0) -> WorldState:
	rng_seed = seed_value if seed_value != 0 else randi()
	world = WorldState.new()
	world.generate(rng_seed)
	EventBus.world_loaded.emit()
	return world

func set_world(state: WorldState) -> void:
	world = state
	EventBus.world_loaded.emit()

func my_nation() -> Nation:
	if world == null:
		return null
	return world.nation(local_nation)

func go(screen_id: String, payload: Dictionary = {}) -> void:
	EventBus.screen_requested.emit(screen_id, payload)

func notify(text: String, kind: String = "info") -> void:
	EventBus.notice.emit(text, kind)

# --- save / load ------------------------------------------------------------

const SAVE_PATH := "user://world.save"

func save_world() -> bool:
	if world == null:
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(world.to_dict()))
	f.close()
	return true

func load_world() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var txt := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var st := WorldState.new()
	st.from_dict(parsed)
	set_world(st)
	return true
