## Bosh menyu sahnasi ildizi (res://ui/main.tscn): orqada 3D askarlar (SoldierPreview), ustida ekranlar.
## ScreenManager ekranlarni shu yerda almashtiradi (silliq fade).
extends Control

var preview: SoldierPreview
var holder: Control
var _current: Control
var _vignette: TextureRect


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview = SoldierPreview.new()
	add_child(preview)
	_vignette = TextureRect.new()
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.45)
	g.fill_to = Vector2(1.15, 1.1)
	var gr := Gradient.new()
	gr.set_color(0, Color(0, 0, 0, 0))
	gr.set_color(1, Color(0, 0, 0, 0.75))
	g.gradient = gr
	_vignette.texture = g
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vignette)
	holder = Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	var toasts := Toasts.new()
	UiKit.pin_top_center(toasts, 90)
	add_child(toasts)
	GameSession.in_battle = false
	if SaveManager.last_error != "":
		EventBus.toast.emit(SaveManager.last_error)
		SaveManager.last_error = ""
	ScreenManager.main_ready.call_deferred()


## Ekranni almashtirish: eskisi so'nib ketadi, yangisi silliq kiradi.
func show_screen(id: String, path: String) -> void:
	if _current:
		var old := _current
		var tw := old.create_tween()
		tw.tween_property(old, "modulate:a", 0.0, 0.15)
		tw.tween_callback(old.queue_free)
	if not ResourceLoader.exists(path):
		EventBus.toast.emit(Loc.t("coming_soon"))
		return
	_current = (load(path) as PackedScene).instantiate()
	holder.add_child(_current)
	_current.modulate.a = 0.0
	_current.create_tween().tween_property(_current, "modulate:a", 1.0, 0.3)
	preview.set_mode("custom" if id == "customization" else "menu")
	preview.visible = id in ["main", "customization", "campaign", "operations", "settings"]
	_vignette.modulate.a = 1.0 if id == "main" else 0.6
