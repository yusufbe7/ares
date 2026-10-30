## MAP OPTIONS: katakchalar (har biri darhol xaritani o'zgartiradi) va MAP VIEW: Political / Terrain / Resource.
class_name MapOptionsPanel
extends PanelContainer

const OPTIONS := [["borders", "opt.borders", true], ["resources", "opt.resources", false], ["bases", "opt.bases", true],
	["supply", "opt.supply", true], ["conflicts", "opt.conflicts", true], ["allies", "opt.allies", false], ["sea", "opt.sea", true]]
const VIEWS := [[0, "view.political"], [1, "view.terrain"], [2, "view.resource"]]

var _views := {}


func _ready() -> void:
	custom_minimum_size = Vector2(220, 0)
	var v := UiKit.vbox(4)
	add_child(v)
	v.add_child(UiKit.label(Loc.t("map_options").to_upper(), "PanelTitle"))
	for o in OPTIONS:
		var cb := CheckBox.new()
		cb.text = Loc.t(o[1])
		cb.button_pressed = o[2]
		cb.focus_mode = Control.FOCUS_NONE
		var key: String = o[0]
		cb.toggled.connect(func(on: bool): EventBus.map_option_changed.emit(key, on))
		v.add_child(cb)
		EventBus.map_option_changed.emit.call_deferred(key, o[2])
	v.add_child(HSeparator.new())
	v.add_child(UiKit.label(Loc.t("map_view").to_upper(), "StatLabel"))
	var h := UiKit.hbox(4)
	v.add_child(h)
	for vw in VIEWS:
		var b := UiKit.button(Loc.t(vw[1]), "TabButtonActive" if vw[0] == 0 else "TabButton")
		b.custom_minimum_size = Vector2(66, 30)
		b.add_theme_font_size_override("font_size", 13)
		var mode: int = vw[0]
		b.pressed.connect(func(): EventBus.map_view_changed.emit(mode))
		h.add_child(b)
		_views[mode] = b
	EventBus.map_view_changed.connect(func(m: int):
		for k in _views:
			_views[k].theme_type_variation = "TabButtonActive" if k == m else "TabButton")
