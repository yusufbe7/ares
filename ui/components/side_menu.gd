## Chap vertikal menyu: ikonka, nom, ">" belgisi. Tanlangani amber chegara va fon.
## Bo'lim yasalmagan bo'lsa tugma o'chirilgan va "Tez orada" belgili (ishlayotgandek ko'rinmaydi).
class_name SideMenu
extends VBoxContainer

signal chosen(id: String)

var _buttons := {}
var active := ""


## items: [[id, tarjima kaliti, ikonka, yoqilganmi], ...]
static func make(items: Array, act: String) -> SideMenu:
	var m := SideMenu.new()
	m.active = act
	m.add_theme_constant_override("separation", 6)
	for it in items:
		var b := Button.new()
		b.theme_type_variation = "NavButtonActive" if it[0] == act else "NavButton"
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(250, 46)
		b.text = "       " + Loc.t(it[1]).to_upper()
		var ic := UiIcon.make(it[2], 22, UiKit.AMBER if it[0] == act else Color(0.85, 0.85, 0.83))
		ic.position = Vector2(14, 12)
		b.add_child(ic)
		var arrow := UiKit.label(">" if it[3] else Loc.t("soon_short"), "SmallLabel")
		arrow.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		arrow.position = Vector2(-18 if it[3] else -64, -10)
		b.add_child(arrow)
		b.disabled = not it[3]
		if not it[3]:
			b.tooltip_text = Loc.t("coming_soon")
		var id: String = it[0]
		b.pressed.connect(func(): m.chosen.emit(id))
		UiKit._hover_fx(b)
		m.add_child(b)
		m._buttons[id] = b
	return m


func button(id: String) -> Button:
	return _buttons.get(id)
