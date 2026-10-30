## Yuqori markaz tablari: WORLD MAP, TACTICAL VIEW, ECONOMY, DIPLOMACY, FACTIONS.
## WORLD MAP va ECONOMY ishlaydi; DIPLOMACY - eng kichik poydevor (urush/tinchlik jadvali);
## TACTICAL VIEW va FACTIONS ochiladi, lekin "Tez orada".
class_name TabsBar
extends HBoxContainer

const TABS := [["world_map", "tab.world_map"], ["tactical", "tab.tactical"], ["economy", "tab.economy"],
	["diplomacy", "tab.diplomacy"], ["factions", "tab.factions"]]

var active := "world_map"
var _btn := {}


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	for t in TABS:
		var b := UiKit.button(Loc.t(t[1]).to_upper(), "TabButtonActive" if t[0] == active else "TabButton")
		b.custom_minimum_size = Vector2(150, 34)
		var id: String = t[0]
		b.pressed.connect(func(): select(id))
		add_child(b)
		_btn[id] = b
	EventBus.tab_changed.connect(func(id: String): _mark(id))


func select(id: String) -> void:
	EventBus.tab_changed.emit(id)


func _mark(id: String) -> void:
	active = id
	for k in _btn:
		_btn[k].theme_type_variation = "TabButtonActive" if k == id else "TabButton"
