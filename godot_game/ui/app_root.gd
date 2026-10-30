extends Node
## Screen manager. Everything the player sees is a child of this node, swapped
## in response to EventBus.screen_requested.

var current: Node = null
var current_id: String = ""
var _toast_layer: CanvasLayer
var _toast_box: VBoxContainer
var _history: Array = []

func _ready() -> void:
	EventBus.screen_requested.connect(_on_screen_requested)
	EventBus.notice.connect(_on_notice)
	EventBus.battle_requested.connect(_on_battle_requested)
	_build_toasts()
	Net.start_offline()
	show_screen("main_menu", {})

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
	if current_id != "" and current_id != screen_id:
		_history.append(current_id)
	current_id = screen_id
	var node: Node = null
	match screen_id:
		"main_menu": node = preload("res://ui/main_menu.gd").new()
		"lobby": node = preload("res://ui/lobby_screen.gd").new()
		"nation_select": node = preload("res://ui/nation_select.gd").new()
		"world": node = preload("res://ui/world_screen.gd").new()
		"battle": node = preload("res://ui/battle_screen.gd").new()
		"settings": node = preload("res://ui/settings_screen.gd").new()
		"result": node = preload("res://ui/result_screen.gd").new()
		_: node = preload("res://ui/main_menu.gd").new()
	current = node
	add_child(node)
	if node.has_method("open"):
		node.call("open", payload)

func back() -> void:
	if _history.is_empty():
		show_screen("main_menu", {})
		return
	var prev: String = str(_history.pop_back())
	current_id = ""
	show_screen(prev, {})

func _on_battle_requested(config: Dictionary) -> void:
	show_screen("battle", config)

func _on_notice(text: String, kind: String) -> void:
	var p := UIKit.make_panel(UIKit.PANEL)
	var l := UIKit.label(text, 15, UIKit.color_for_kind(kind))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(380, 0)
	p.add_child(l)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.add_child(p)
	while _toast_box.get_child_count() > 6:
		var oldest := _toast_box.get_child(0)
		_toast_box.remove_child(oldest)
		oldest.queue_free()
	var t := get_tree().create_timer(5.0)
	t.timeout.connect(func():
		if is_instance_valid(p):
			p.queue_free())

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_back") and current_id != "main_menu":
		if current != null and current.has_method("on_back"):
			if bool(current.call("on_back")):
				return
		back()
