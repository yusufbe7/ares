## Kampaniya jangi boshlanishi (yuklash ekrani o'rniga): o'yin pauzada, kamera maydonni tepadan aylanib
## ko'rsatadi, samolyotlar uchib o'tadi, vertolyot qo'nadi, tank va transport kirib keladi; vazifa yozuvi
## (Hududni egallang / Bazani himoya qiling / Dushman qo'shinlarini to'xtating) va kuchlar soni chiqadi.
## So'ng: JANGNI BOSHLASH (pauza yechiladi) yoki AVTO-HISOBLASH (natija kampaniyada hisoblanadi).
## Jang paytida tepada kichik panel: kuch nisbati, ta'minot, nuqtalar nazorati.
class_name BattleIntro
extends CanvasLayer

const DUR := 9.0
const A := "res://assets/"

var demo: Node3D
var req: Dictionary
var _cam: Camera3D
var _t := 0.0
var _props: Array = []               ## [node, from, to, t0, t1]
var _panel: PanelContainer
var _hud: Label
var _done := false
var _center := Vector3.ZERO


static func make(p_demo: Node3D, p_req: Dictionary) -> BattleIntro:
	var b := BattleIntro.new()
	b.demo = p_demo
	b.req = p_req
	p_demo.add_child(b)
	return b


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	var mode: OperationMode = demo.mode_node
	for z in mode.zones:
		_center += z.pos / mode.zones.size()
	_cam = Camera3D.new()
	_cam.fov = 50
	_cam.far = 3000
	demo.add_child(_cam)
	_cam.make_current()
	var e0: Vector3 = mode.ENTRY[0]
	var ee: Vector3 = mode.ENEMY_ENTRY[0]
	var dir := (ee - e0).normalized()
	# samolyotlar: bizning tomondan dushman tomonga, baland
	for k in 2:
		var off := dir.cross(Vector3.UP) * (k * 22.0 - 11.0)
		_prop("f117.glb", e0 - dir * 260 + off + Vector3(0, 70 + k * 6, 0), ee + dir * 260 + off + Vector3(0, 75, 0), 1.0 + k * 0.5, 6.5 + k * 0.5)
	# vertolyot: ikkinchi kirish nuqtasiga qo'nadi
	var lz: Vector3 = mode.ENTRY[1] + Vector3(12, 0, -10)
	lz.y = demo.ground_height(lz.x, lz.z)
	_prop("mi24.glb", lz - dir * 120 + Vector3(0, 55, 0), lz + Vector3(0, 0.2, 0), 1.5, 8.0)
	# tank va transport chetdan kirib keladi
	for k in 2:
		var to: Vector3 = e0 + Vector3(-14 - k * 10, 0, 10 + k * 6)
		var from := to - dir * 70
		for p in [to, from]:
			p.y = demo.ground_height(p.x, p.z)
		_prop("t72.glb" if k == 0 else "humvee.glb", from, to, 0.0, DUR - 1.0)
	get_tree().paused = true
	_banner()


func _prop(file: String, from: Vector3, to: Vector3, t0: float, t1: float) -> void:
	if not ResourceLoader.exists(A + file):
		return
	var n: Node3D = load(A + file).instantiate()
	n.process_mode = Node.PROCESS_MODE_ALWAYS
	demo.add_child(n)
	n.position = from
	var flat := Vector3(to.x - from.x, 0, to.z - from.z)
	if flat.length() > 0.1:
		n.look_at(n.position + flat, Vector3.UP)
		n.rotate_object_local(Vector3.UP, PI)          # modellar +Z ga qaragan
	for ap in n.find_children("*", "AnimationPlayer", true, false):
		var l: PackedStringArray = (ap as AnimationPlayer).get_animation_list()
		if not l.is_empty():
			(ap as AnimationPlayer).play(l[0])
	_props.append([n, from, to, t0, t1])


## Vazifa yozuvi va kuchlar (ekran markazida, pastda tugmalar).
func _banner() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiKit.theme()
	add_child(root)
	# panel pastda markazda, jang HUD tugmalaridan yuqorida
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_bottom = -150
	box.alignment = BoxContainer.ALIGNMENT_END
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	_panel = UiKit.panel()
	_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_panel.custom_minimum_size = Vector2(700, 0)
	box.add_child(_panel)
	var v := UiKit.vbox(8)
	_panel.add_child(v)
	var defends: bool = req.get("player_defends", false)
	var place := "%s (%s)" % [req.get("province_name", "?"), Loc.t("biome." + str(req.get("biome", "temperate")))]
	v.add_child(UiKit.label((Loc.t("obj.defend", [place]) if defends else Loc.t("obj.capture", [place])).to_upper(), "HeaderLabel", HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UiKit.label(Loc.t("obj.stop") + "   ·   " + Loc.t("obj.points"), "SmallLabel", HORIZONTAL_ALIGNMENT_CENTER))
	var men: Array = BattleBridge.men_for(req)
	v.add_child(UiKit.label("%s      %s" % [Loc.t("intro.ours", [men[0]]), Loc.t("intro.enemy", [men[1]])], "AmberLabel", HORIZONTAL_ALIGNMENT_CENTER))
	var h := UiKit.hbox(12)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(UiKit.label(Loc.t("intro.skip"), "SmallLabel"))
	h.add_child(UiKit.button(Loc.t("op.auto").to_upper(), "", _auto))
	h.add_child(UiKit.button("▶  " + Loc.t("intro.start").to_upper(), "AmberButton", _start))
	v.add_child(h)
	UiKit.slide_in(_panel)
	_hud = UiKit.label("", "AmberLabel")
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 5)
	UiKit.pin_top_center(_hud, 8)
	_hud.visible = false
	root.add_child(_hud)


func _process(d: float) -> void:
	if _done:
		_update_hud()
		return
	_t += d
	# kamera: maydon markazi atrofida baland aylanish, asta pastlaydi
	var a := -2.3 + _t * 0.09
	var h := lerpf(230.0, 140.0, clampf(_t / DUR, 0, 1))
	_cam.position = _center + Vector3(cos(a), 0, sin(a)) * 260.0 + Vector3(0, h, 0)
	_cam.look_at(_center + Vector3(0, 5, 0))
	for p in _props:
		var n: Node3D = p[0]
		if not is_instance_valid(n):
			continue
		var k := clampf((_t - p[3]) / (p[4] - p[3]), 0.0, 1.0)
		var s := k * k * (3.0 - 2.0 * k) if n.name.begins_with("mi24") or str(n.scene_file_path).contains("mi24") else k
		n.position = (p[1] as Vector3).lerp(p[2], s)
		n.visible = _t >= p[3] - 0.01


func _unhandled_input(e: InputEvent) -> void:
	if _done:
		return
	if e is InputEventKey and e.pressed and e.keycode == KEY_SPACE:
		_t = DUR
		get_viewport().set_input_as_handled()


func _start() -> void:
	_done = true
	for p in _props:
		if is_instance_valid(p[0]):
			p[0].queue_free()
	_props.clear()
	_cam.queue_free()
	demo.cam.camera.make_current()
	_panel.queue_free()
	_hud.visible = true
	get_tree().paused = false


func _auto() -> void:
	get_tree().paused = false
	BattleBridge.finish_auto(get_tree())


## Jang paytidagi ko'rsatkichlar: kuch (bizning / dushman askarlar), ta'minot, nuqtalar nazorati.
func _update_hud() -> void:
	if Engine.get_process_frames() % 20 != 0:
		return
	var m: OperationMode = demo.mode_node
	var ours: int = m.reserve[0] + m._field(0)
	var theirs: int = m.reserve[1] + m._field(1)
	var held := m.zones.filter(func(z): return z.owner == 0).size()
	_hud.text = "%s     %s     %s" % [Loc.t("hud.strength", [ours, theirs]), Loc.t("hud.supply", [int(m.supply)]), Loc.t("hud.control", [held, m.zones.size()])]
