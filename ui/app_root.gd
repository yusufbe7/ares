extends Node
## Screen manager. The game is a battle, a screen to set it up, a screen to
## read the result, and options — nothing else.

var current: Node = null
var current_id: String = ""
var _toast_layer: CanvasLayer
var _toast_box: VBoxContainer

func _ready() -> void:
	EventBus.screen_requested.connect(_on_screen_requested)
	EventBus.notice.connect(_on_notice)
	_build_toasts()
	show_screen("setup", {})

func _build_toasts() -> void:
	_toast_layer = CanvasLayer.new()
	_toast_layer.layer = 100
	add_child(_toast_layer)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	margin.offset_left = -420
	margin.offset_right = -16
	margin.offset_top = 16
	margin.offset_bottom = 400
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_layer.add_child(margin)
	_toast_box = UIKit.vbox(6)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_toast_box)

func _on_screen_requested(screen_id: String, payload: Dictionary) -> void:
	show_screen(screen_id, payload)

func show_screen(screen_id: String, payload: Dictionary) -> void:
	if current != null:
		current.queue_free()
		current = null
	current_id = screen_id
	var node: Node
	match screen_id:
		"battle": node = preload("res://ui/battle_screen.gd").new()
		"result": node = preload("res://ui/result_screen.gd").new()
		"settings": node = preload("res://ui/settings_screen.gd").new()
		_: node = preload("res://ui/setup_screen.gd").new()
	current = node
	add_child(node)
	if node.has_method("open"):
		node.call("open", payload)

func _on_notice(text: String, kind: String) -> void:
	var p := UIKit.make_panel(UIKit.PANEL)
	var l := UIKit.label(text, 15, UIKit.color_for_kind(kind))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(380, 0)
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.add_child(p)
	while _toast_box.get_child_count() > 5:
		var oldest := _toast_box.get_child(0)
		_toast_box.remove_child(oldest)
		oldest.queue_free()
	get_tree().create_timer(4.5).timeout.connect(p.queue_free)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_back") and current_id != "setup":
		if current != null and current.has_method("on_back"):
			if bool(current.call("on_back")):
				return
		show_screen("setup", {})
