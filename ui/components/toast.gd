## Qisqa xabarlar (ekranning yuqori markazida, 4 soniya). EventBus.toast va campaign_message ni ko'rsatadi.
class_name Toasts
extends VBoxContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	EventBus.toast.connect(show_text)


func show_text(t: String) -> void:
	var p := UiKit.panel("CardPanel")
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UiKit.label(t)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(420, 0)
	p.add_child(l)
	add_child(p)
	while get_child_count() > 5:
		get_child(0).free()
	UiKit.slide_in(p)
	var tw := p.create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)
