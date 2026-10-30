## VIEW ALL: hamma texnika to'r (grid) ko'rinishida. Yuqorida tur bo'yicha filtr (hammasi, tank, BTR,
## yuk mashinasi, jip, vertolyot) va tartiblash (narx, otish kuchi, zirh, harakatchanlik, daraja).
## Kartalardagi BUY / SELECT bosh menyudagi bilan bir xil (VehicleCard, Shop).
extends Control

const FILTERS := [["all", "view_all"], ["tank", "vtab.tanks"], ["apc", "vtab.apc"], ["truck", "vtab.trucks"],
	["jeep", "vtab.jeeps"], ["heli", "vtab.heli"]]
const SORTS := [["price", "sort.price"], ["firepower", "stat.firepower"], ["armor", "stat.armor"],
	["mobility", "stat.mobility"], ["required_level", "sort.level"]]

var _filter := "all"
var _sort := "price"
var _grid: GridContainer
var _tabs: HBoxContainer


func _ready() -> void:
	var body := ScreenFrame.build(self, "vehicle_market", "tank", Color("#5DBE5A"))
	var v := UiKit.vbox(12)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.add_child(v)
	var top := UiKit.hbox(12)
	v.add_child(top)
	_tabs = ScreenFrame.tabs(FILTERS.map(func(f): return [f[0], Loc.t(f[1]), true]), _filter, func(id: String):
		_filter = id
		ScreenFrame.mark_tabs(_tabs, FILTERS, _filter)
		_refresh())
	top.add_child(_tabs)
	top.add_child(UiKit.spacer())
	top.add_child(UiKit.label(Loc.t("sort.by"), "SmallLabel"))
	var o := OptionButton.new()
	for k in SORTS.size():
		o.add_item(Loc.t(SORTS[k][1]))
	o.item_selected.connect(func(k: int): _sort = SORTS[k][0]; _refresh())
	top.add_child(o)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	sc.add_child(_grid)
	_refresh()
	EventBus.vehicle_bought.connect(func(_id): _refresh())
	EventBus.vehicle_selected.connect(func(_id): _refresh())


func _refresh() -> void:
	UiKit.clear(_grid)
	var list: Array = GameSession.items("vehicles").filter(func(x): return _filter == "all" or x.type == _filter)
	list.sort_custom(func(a, b): return a.get(_sort) > b.get(_sort) if _sort != "required_level" else a.get(_sort) < b.get(_sort))
	if list.is_empty():
		_grid.add_child(UiKit.label(Loc.t("coming_soon"), "SmallLabel"))
		return
	for x in list:
		var c := VehicleCard.make(x)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid.add_child(c)
