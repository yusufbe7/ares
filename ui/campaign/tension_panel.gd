## GLOBAL TENSION: bloklar ulushi (logic/tension.gd dagi haqiqiy hisob), ikki eng katta blok kuch chizig'i.
## Har yurish va har hudud bosib olinganda yangilanadi.
class_name TensionPanel
extends PanelContainer

var map: Node
var _bar: Control
var _rows: VBoxContainer
var _data: Array = []


static func make(p_map: Node) -> TensionPanel:
	var t := TensionPanel.new()
	t.map = p_map
	return t


func _ready() -> void:
	custom_minimum_size = Vector2(250, 0)
	var v := UiKit.vbox(6)
	add_child(v)
	var h := UiKit.hbox(8)
	h.add_child(UiIcon.make("globe", 24))
	h.add_child(UiKit.label(Loc.t("global_tension").to_upper(), "PanelTitle"))
	v.add_child(h)
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(0, 8)
	_bar.draw.connect(_draw_bar)
	v.add_child(_bar)
	_rows = UiKit.vbox(3)
	v.add_child(_rows)
	EventBus.campaign_changed.connect(refresh)
	EventBus.turn_ended.connect(func(_t): refresh())
	refresh()


func refresh() -> void:
	_data = CampaignTension.compute(map.data)
	UiKit.clear(_rows)
	for r in _data:
		var h := UiKit.hbox(8)
		var sw := ColorRect.new()
		sw.color = r.color
		sw.custom_minimum_size = Vector2(12, 12)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(sw)
		var n := UiKit.label(str(r.name).to_upper())
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.tooltip_text = Loc.t("tension_row", [r.provinces, r.regiments])
		n.mouse_filter = Control.MOUSE_FILTER_PASS
		h.add_child(n)
		h.add_child(UiKit.label("%d%%" % roundi(r.share * 100.0), "PanelTitle"))
		_rows.add_child(h)
	_bar.queue_redraw()


## Ko'k-qizil chiziq: bloklar ulushi ketma-ket (rangi bilan).
func _draw_bar() -> void:
	var x := 0.0
	var w := _bar.size.x
	_bar.draw_rect(Rect2(Vector2.ZERO, _bar.size), Color(0.1, 0.1, 0.11))
	for r in _data:
		var sw: float = r.share * w
		_bar.draw_rect(Rect2(x, 0, sw, _bar.size.y), r.color)
		x += sw
