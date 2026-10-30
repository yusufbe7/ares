extends Node
## Persistent user settings + rebindable input actions.

const PATH := "user://settings.cfg"

## Every action the game uses, with its default physical key.
## Battlefield actions are prefixed bf_, world map actions wm_.
const DEFAULT_KEYS := {
	"bf_select_mode": KEY_SPACE,
	"bf_reinforce": KEY_R,
	"bf_call_tank": KEY_Y,
	"bf_call_artillery": KEY_U,
	"bf_build_menu": KEY_B,
	"bf_dig_trench": KEY_V,
	"bf_grenade": KEY_G,
	"bf_rocket": KEY_T,
	"bf_halt": KEY_H,
	"bf_focus": KEY_F,
	"bf_prone": KEY_Z,
	"bf_crouch": KEY_X,
	"bf_stand": KEY_C,
	"bf_recon": KEY_N,
	"bf_cam_fwd": KEY_W,
	"bf_cam_back": KEY_S,
	"bf_cam_left": KEY_A,
	"bf_cam_right": KEY_D,
	"bf_cam_rot_l": KEY_Q,
	"bf_cam_rot_r": KEY_E,
	"wm_pan_up": KEY_W,
	"wm_pan_down": KEY_S,
	"wm_pan_left": KEY_A,
	"wm_pan_right": KEY_D,
	"wm_end_turn": KEY_ENTER,
	"ui_back": KEY_ESCAPE,
}

var keys: Dictionary = {}
var graphics_quality: int = 1          # 0 low, 1 medium, 2 high
var master_volume: float = 0.8
var music_volume: float = 0.5
var language: String = "uz"            # uz | en | ru
var camera_speed: float = 1.0
var ui_scale: float = 1.0
var ui_opacity: float = 0.92
var show_fps: bool = false
var player_name: String = "Commander"

func _ready() -> void:
	keys = DEFAULT_KEYS.duplicate()
	load_settings()
	apply_input_map()

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for action in DEFAULT_KEYS.keys():
		keys[action] = int(cfg.get_value("keys", action, DEFAULT_KEYS[action]))
	graphics_quality = int(cfg.get_value("video", "quality", graphics_quality))
	show_fps = bool(cfg.get_value("video", "show_fps", show_fps))
	master_volume = float(cfg.get_value("audio", "master", master_volume))
	music_volume = float(cfg.get_value("audio", "music", music_volume))
	language = str(cfg.get_value("game", "language", language))
	camera_speed = float(cfg.get_value("game", "camera_speed", camera_speed))
	ui_scale = float(cfg.get_value("game", "ui_scale", ui_scale))
	ui_opacity = float(cfg.get_value("game", "ui_opacity", ui_opacity))
	player_name = str(cfg.get_value("game", "player_name", player_name))

func save_settings() -> void:
	var cfg := ConfigFile.new()
	for action in keys.keys():
		cfg.set_value("keys", action, keys[action])
	cfg.set_value("video", "quality", graphics_quality)
	cfg.set_value("video", "show_fps", show_fps)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("game", "language", language)
	cfg.set_value("game", "camera_speed", camera_speed)
	cfg.set_value("game", "ui_scale", ui_scale)
	cfg.set_value("game", "ui_opacity", ui_opacity)
	cfg.set_value("game", "player_name", player_name)
	cfg.save(PATH)

## Registers every action in the engine InputMap. Safe to call again after a
## rebind: the action is cleared and rebuilt.
func apply_input_map() -> void:
	for action in keys.keys():
		var action_name := StringName(action)
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		InputMap.action_erase_events(action_name)
		var ev := InputEventKey.new()
		ev.physical_keycode = int(keys[action])
		InputMap.action_add_event(action_name, ev)

func rebind(action: String, physical_keycode: int) -> void:
	if not keys.has(action):
		return
	keys[action] = physical_keycode
	apply_input_map()
	save_settings()

func key_name(action: String) -> String:
	if not keys.has(action):
		return "-"
	return OS.get_keycode_string(int(keys[action]))
