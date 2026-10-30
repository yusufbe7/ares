## Texnika kartasi: rasm / 3D miniatyura, nom, tur, FIREPOWER / ARMOR / MOBILITY, narx, BUY va SELECT.
## BUY: credits yetsa sotib oladi (garajga qo'shiladi, tugma OWNED). Yetmasa tugma o'chirilgan, narx qizil.
## SELECT: texnikani jangga olish uchun tanlaydi.
class_name VehicleCard
extends PanelContainer

var v: VehicleData
var compact := true
var _buy: Button
var _sel: Button
var _price: Label


static func make(data: VehicleData, p_compact := true) -> VehicleCard:
	var c := VehicleCard.new()
	c.v = data
	c.compact = p_compact
	return c


func _ready() -> void:
	theme_type_variation = "CardPanel"
	var h := UiKit.hbox(10)
	add_child(h)
	# rasm: VehicleData.image -> ui/thumbs/<id>.png (tools/render_thumbs.gd) -> jonli 3D -> "NO IMAGE"
	var tex := VehicleCard.thumb(v)
	var img: Control = UiKit.image_slot(tex, Vector2(150, 92)) if tex else ModelThumb.make(v.model, Vector2(150, 92), false, v.model_scale)
	h.add_child(img)
	var col := UiKit.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(col)
	col.add_child(UiKit.label(v.name, "PanelTitle"))
	col.add_child(UiKit.label(Loc.t("vtype." + v.type).to_upper(), "SmallLabel"))
	var st := Shop.vehicle_stats(v)
	for k in ["firepower", "armor", "mobility"]:
		var b := StatBar.make(Loc.t("stat." + k), st[k])
		b.get_child(0).custom_minimum_size = Vector2(70, 0)
		col.add_child(b)
	var row := UiKit.hbox(6)
	col.add_child(row)
	row.add_child(UiIcon.make("coins", 16, UiKit.AMBER))
	_price = UiKit.label(UiKit.num(v.price), "PanelTitle")
	_price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_price)
	_buy = UiKit.button(Loc.t("buy"), "", func(): Shop.buy_vehicle(v.id))
	_sel = UiKit.button(Loc.t("select"), "", func(): Shop.select_vehicle(v.id))
	row.add_child(_buy)
	row.add_child(_sel)
	for s in [EventBus.credits_changed, EventBus.vehicle_bought, EventBus.vehicle_selected]:
		s.connect(func(_a = null, _b = null): refresh())
	refresh()


func refresh() -> void:
	var p: PlayerProfile = GameSession.profile
	var owned := v.id in p.owned_vehicles
	_buy.text = Loc.t("owned") if owned else Loc.t("buy")
	_buy.disabled = owned or not v.available or p.credits < v.price or p.level() < v.required_level
	_price.add_theme_color_override("font_color", UiKit.RED if not owned and p.credits < v.price else Color(0.9, 0.9, 0.88))
	if not v.available:
		_buy.text = Loc.t("soon_short")
		_buy.tooltip_text = Loc.t("no_model")
	elif p.level() < v.required_level and not owned:
		_buy.tooltip_text = Loc.t("need_level", [v.required_level])
	_sel.disabled = not owned
	_sel.text = Loc.t("selected") if v.id in p.selected_vehicles else Loc.t("select")
	_sel.theme_type_variation = "TabButtonActive" if v.id in p.selected_vehicles else ""


## Texnika rasmi: o'zingiz bergan rasm yoki modeldan render qilingan miniatyura.
static func thumb(v: VehicleData) -> Texture2D:
	if v.image:
		return v.image
	var p := "res://ui/thumbs/%s.png" % v.id
	return load(p) if ResourceLoader.exists(p) else null
