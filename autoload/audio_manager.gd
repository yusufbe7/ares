## Ovoz shinalari: Master, Music, SFX, UI. Tovush fayllari hozircha yo'q: o'yin ularsiz ishlaydi,
## fayl qo'shilsa play_ui()/play_music() shu shinalar orqali chaladi.
extends Node

const BUSES := ["Music", "SFX", "UI", "Voice"]
var _ui_player: AudioStreamPlayer


func _ready() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	_ui_player = AudioStreamPlayer.new()
	_ui_player.bus = "UI"
	add_child(_ui_player)


## Ovoz balandligi 0..1.
func set_volume(bus: String, v: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(i, v <= 0.001)


func play_ui(path: String) -> void:
	if ResourceLoader.exists(path):
		_ui_player.stream = load(path)
		_ui_player.play()
