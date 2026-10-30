extends Node
## Graphics, audio, language, camera, UI and full key rebinding.

var _listening_action: String = ""
var _key_buttons: Dictionary = {}

func open(_payload: Dictionary) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	UIKit.fullscreen(bg)
	bg.color = UIKit.BG
	layer.add_child(bg)

	var margin := MarginContainer.new()
	UIKit.fullscreen(margin)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	layer.add_child(margin)

	var cols := UIKit.hbox(24)
	margin.add_child(cols)

	var left := UIKit.vbox(10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	left.add_child(UIKit.title(Loc.t("menu.settings")))

	left.add_child(UIKit.label("O'yinchi nomi", 14))
	var name_edit := LineEdit.new()
	name_edit.text = Settings.player_name
	name_edit.text_changed.connect(func(t):
		Settings.player_name = t
		Settings.save_settings())
	left.add_child(name_edit)

	left.add_child(_slider("Kamera tezligi", 0.3, 3.0, Settings.camera_speed, func(v):
		Settings.camera_speed = v))
	left.add_child(_slider("Umumiy ovoz", 0.0, 1.0, Settings.master_volume, func(v):
		Settings.master_volume = v
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.0001)))))
	left.add_child(_slider("Musiqa", 0.0, 1.0, Settings.music_volume, func(v):
		Settings.music_volume = v))
	left.add_child(_slider("UI o'lchami", 0.8, 1.5, Settings.ui_scale, func(v):
		Settings.ui_scale = v))
	left.add_child(_slider("UI shaffofligi", 0.4, 1.0, Settings.ui_opacity, func(v):
		Settings.ui_opacity = v))

	left.add_child(UIKit.label("Grafika", 14))
	var quality := OptionButton.new()
	quality.add_item("Past", 0)
	quality.add_item("O'rta", 1)
	quality.add_item("Yuqori", 2)
	quality.selected = Settings.graphics_quality
	quality.item_selected.connect(func(i):
		Settings.graphics_quality = i
		Settings.save_settings())
	left.add_child(quality)

	left.add_child(UIKit.label("Til / Language / Язык", 14))
	var lang := OptionButton.new()
	lang.add_item("O'zbekcha", 0)
	lang.add_item("English", 1)
	lang.add_item("Русский", 2)
	lang.selected = ["uz", "en", "ru"].find(Settings.language)
	lang.item_selected.connect(func(i):
		Settings.language = ["uz", "en", "ru"][i]
		Settings.save_settings()
		GameState.notify("Til o'zgardi.", "good"))
	left.add_child(lang)

	var fps := CheckBox.new()
	fps.text = "FPS ko'rsatish"
	fps.button_pressed = Settings.show_fps
	fps.toggled.connect(func(v):
		Settings.show_fps = v
		Settings.save_settings())
	left.add_child(fps)

	var right := UIKit.vbox(6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	right.add_child(UIKit.label("Tugmalar", 20, UIKit.ACCENT))
	right.add_child(UIKit.label("Tugmani bosing, so'ng yangi tugmani bosing.", 12, UIKit.MUTED))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)
	var keys := UIKit.vbox(3)
	keys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(keys)
	for action in Settings.DEFAULT_KEYS.keys():
		var row := UIKit.hbox()
		var l := UIKit.label(_action_label(str(action)), 13)
		l.custom_minimum_size = Vector2(190, 0)
		row.add_child(l)
		var b := UIKit.button(Settings.key_name(str(action)), 13)
		b.custom_minimum_size = Vector2(110, 30)
		b.pressed.connect(_begin_listen.bind(str(action)))
		_key_buttons[str(action)] = b
		row.add_child(b)
		keys.add_child(row)

	var back := UIKit.button(Loc.t("common.back"), 15)
	back.pressed.connect(func():
		Settings.save_settings()
		GameState.go("setup", {}))
	right.add_child(back)

func _slider(text: String, lo: float, hi: float, value: float, on_change: Callable) -> Control:
	var box := UIKit.vbox(2)
	var l := UIKit.label("%s: %.2f" % [text, value], 13)
	box.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.05
	s.value = value
	s.value_changed.connect(func(v):
		l.text = "%s: %.2f" % [text, v]
		on_change.call(v)
		Settings.save_settings())
	box.add_child(s)
	return box

func _action_label(action: String) -> String:
	var pretty := action.replace("bf_", "Jang: ").replace("wm_", "Xarita: ").replace("_", " ")
	return pretty.capitalize()

func _begin_listen(action: String) -> void:
	_listening_action = action
	if _key_buttons.has(action):
		_key_buttons[action].text = "..."

func _input(event: InputEvent) -> void:
	if _listening_action == "":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		Settings.rebind(_listening_action, event.physical_keycode)
		if _key_buttons.has(_listening_action):
			_key_buttons[_listening_action].text = Settings.key_name(_listening_action)
		_listening_action = ""
		get_viewport().set_input_as_handled()
