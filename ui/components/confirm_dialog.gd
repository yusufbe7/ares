## Tasdiqlash oynasi (Yes / No). Klaviatura: Enter = Yes, Esc = No.
class_name ConfirmDialog
extends Control

signal answered(yes: bool)


static func ask(parent: Node, title: String, text: String, yes_text := "", no_text := "") -> ConfirmDialog:
	var d := ConfirmDialog.new()
	parent.add_child(d)
	d._build(title, text, yes_text if yes_text != "" else Loc.t("yes"), no_text if no_text != "" else Loc.t("no"))
	return d


func _build(title: String, text: String, yes_text: String, no_text: String) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	var p := UiKit.panel()
	p.custom_minimum_size = Vector2(440, 0)
	c.add_child(p)
	var v := UiKit.vbox(14)
	p.add_child(v)
	v.add_child(UiKit.label(title.to_upper(), "HeaderLabel"))
	var l := UiKit.label(text)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	var h := UiKit.hbox(10)
	h.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(h)
	var no := UiKit.button(no_text, "", func(): _done(false))
	var yes := UiKit.button(yes_text, "AmberButton", func(): _done(true))
	h.add_child(no)
	h.add_child(yes)
	yes.grab_focus.call_deferred()
	UiKit.slide_in(p)


func _done(yes: bool) -> void:
	answered.emit(yes)
	queue_free()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_done(false)
