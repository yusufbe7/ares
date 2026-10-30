## Hujum operatsiyasining xaritadagi ko'rinishi va oqimi:
##   1) himoyachi ogohlantiriladi (xabar), kamera yo'lga uchadi;
##   2) qo'shin belgisi (tank / kema / samolyot + polklar soni) yo'l bo'ylab yuradi: quruqlikda to'g'ri,
##      dengizda yoy, havoda baland yoy; "Tez" rejimda qisqa;
##   3) yetib borgach: avto-jang (natija xabari) yoki 3D jang (GameSession.battle_request -> jang sahnasi).
class_name OpsRunner
extends Control

const ICON := {"land": "tank", "sea": "ship", "air": "aircraft"}
const SAMPLES := 28

var map: Node
var _op := {}
var _t := 0.0
var _pts: Array = []                 ## dunyo nuqtalari (Vector3)
var _icon: UiIcon
var _count: Label
var _busy := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon = UiIcon.make("tank", 30, UiKit.AMBER)
	_icon.visible = false
	add_child(_icon)
	_count = UiKit.label("", "AmberLabel")
	_count.add_theme_color_override("font_outline_color", Color.BLACK)
	_count.add_theme_constant_override("outline_size", 5)
	_count.visible = false
	add_child(_count)


func busy() -> bool:
	return _busy


func run(op: Dictionary, fast: bool, in_3d: bool) -> void:
	_op = op
	_busy = true
	var d: CampaignData = map.data
	var tp: ProvinceData = d.provinces[op.to]
	var att: CountryData = d.countries.get(op.attacker)
	get_tree().root.get_node("EventBus").campaign_message.emit(Loc.t("op.warned", [Loc.country(att), tp.name]))
	var a: Vector3 = map.province_world(op.from)
	var b: Vector3 = map.province_world(op.to)
	var lift := 0.0
	match op.method:
		"sea": lift = 0.0
		"air": lift = a.distance_to(b) * 0.25
	_pts.clear()
	var side := (b - a).cross(Vector3.UP).normalized() * (a.distance_to(b) * 0.18 if op.method == "sea" else 0.0)
	for k in SAMPLES + 1:
		var t := float(k) / SAMPLES
		var p := a.lerp(b, t) + side * sin(t * PI)
		p.y = maxf(p.y, map.ground_y(p.x, p.z)) + 0.15 + lift * sin(t * PI)
		_pts.append(p)
	_icon.icon = ICON.get(op.method, "tank")
	_icon.queue_redraw()
	_icon.visible = true
	_count.text = "x%d" % int(op.count)
	_count.visible = true
	map.cam.fly_to((a + b) * 0.5, clampf(a.distance_to(b) * 2.2, 8.0, 40.0))
	_t = 0.0
	var dur := 0.9 if fast else 3.2
	var tw := create_tween()
	tw.tween_property(self, "_t", 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(_arrived.bind(in_3d))


func _process(_d: float) -> void:
	if not _busy:
		return
	var cam: Camera3D = map.cam.get_viewport().get_camera_3d()
	if cam == null:
		return
	var f := _t * SAMPLES
	var k := mini(int(f), SAMPLES - 1)
	var p: Vector3 = (_pts[k] as Vector3).lerp(_pts[k + 1], f - k)
	if not cam.is_position_behind(p):
		var s := cam.unproject_position(p)
		_icon.position = s - _icon.size * 0.5
		_count.position = s + Vector2(14, -8)
	queue_redraw()


func _draw() -> void:
	if not _busy or _pts.is_empty():
		return
	var cam: Camera3D = map.cam.get_viewport().get_camera_3d()
	if cam == null:
		return
	var pl := PackedVector2Array()
	for p in _pts:
		if not cam.is_position_behind(p):
			pl.append(cam.unproject_position(p))
	var col: Color = Color(0.95, 0.35, 0.25) if _op.attacker != map.rules.player_id else UiKit.AMBER
	for k in range(1, pl.size()):
		if k % 2 == 1:
			draw_line(pl[k - 1], pl[k], col, 3.0, true)
	if pl.size() > 1:
		var tip := pl[pl.size() - 1]
		var dir := (tip - pl[pl.size() - 2]).normalized()
		draw_colored_polygon(PackedVector2Array([tip + dir * 10, tip - dir * 6 + dir.orthogonal() * 8, tip - dir * 6 - dir.orthogonal() * 8]), col)


func _arrived(in_3d: bool) -> void:
	var op := _op
	if in_3d:
		_busy = false
		BattleBridge.start(map, op)
		return
	var a: ArmyData = op.army
	var before := a.size
	var won: bool = map.ops.resolve_auto(op)
	get_tree().root.get_node("EventBus").campaign_message.emit(Loc.t("op.result", [map.data.provinces[op.to].name, Loc.t("victory") if won else Loc.t("defeat"),
		before - a.size, a.size]))
	_busy = false
	_icon.visible = false
	_count.visible = false
	queue_redraw()
	if a in map.data.armies:
		map.select_province(a.province)
