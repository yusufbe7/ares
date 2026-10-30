## Qo'shin belgilari (ekran ustida 2D chiziladi, shuning uchun har doim aniq va o'qiladigan).
##  - Rang = davlatning o'z rangi, qalin to'q chet (outline).
##  - O'zingizniki doira, dushmanniki qalqon shaklida.
##  - O'lcham ichidagi raqamga (polklar soniga) qarab biroz kattalashadi.
##  - Ekranda bir-biriga yaqin turgan bir davlat qo'shinlari bitta belgiga birlashadi ("x3" belgisi bilan).
##    Kamera uzoqda bo'lsa, tig'iz joydagi turli dushman davlatlar qo'shinlari ham bitta "x5" belgisiga
##    birlashadi (orqasida ularning ranglari ustma-ust ko'rinadi). O'yinchi qo'shinlari begonalar bilan
##    hech qachon birlashmaydi. Kamera yaqinlashganda belgilar ekranda uzoqlashadi va o'zi ajraladi.
##  - Belgi hudud nuqtasidan yuqorida, ingichka ustun ustida turadi. Ostidagi nom yopilib qolmaydi:
##    yozuv bilan to'qnashsa, belgi yozuvdan yuqoriga ko'tariladi.
class_name ArmyOverlay
extends Control

const OUTLINE := Color(0.06, 0.05, 0.04)
const SELECT := Color(1.0, 0.86, 0.35)
const STEM := 12.0          ## ustun uzunligi (piksel)
const MERGE_PX := 40.0      ## shu masofadan yaqin bo'lsa birlashadi

var map: CampaignMap
var clusters: Array = []    ## [{armies, owner, size, anchor, center, r}]
var avoid_rects: Array = [] ## yozuvlar egallagan joylar (map beradi)
var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


## Polklar soniga qarab radius (piksel).
static func radius(size: int) -> float:
	return clampf(9.0 + 2.6 * sqrt(float(size)), 12.0, 28.0)


## Har kadrda: qo'shinlarni ekranga proyeksiya qilib, yaqinlarini birlashtiramiz.
func rebuild() -> void:
	clusters.clear()
	if map == null or map.phase == "choose":
		queue_redraw()
		return
	var cam := map.cam.camera
	var vr := get_viewport_rect().grow(80)
	# uzoqda belgilar biroz kichikroq va kengroq radiusda birlashadi
	var zt := clampf(inverse_lerp(40.0, 150.0, map.cam.distance), 0.0, 1.0)
	var merge_px := lerpf(MERGE_PX, MERGE_PX * 1.9, zt)
	var zs := lerpf(1.0, 0.8, zt)
	var mix_far := zt > 0.12         # uzoqda turli dushmanlar ham birlashadi
	var blocked: Array = map.blocked_rects() if map.has_method("blocked_rects") else []
	var items := []
	for a in map.data.armies:
		var w := map.province_world(a.province)
		if cam.is_position_behind(w):
			continue
		var sp := cam.unproject_position(w)
		if vr.has_point(sp):
			items.append({"a": a, "p": sp})
	# katta qo'shin birinchi: klaster markazi eng katta qo'shin turgan joyda bo'ladi
	items.sort_custom(func(x, y): return x.a.size > y.a.size)
	var used := {}
	for i in items.size():
		if used.has(i):
			continue
		var it: Dictionary = items[i]
		var cl := {"armies": [it.a], "owner": it.a.owner, "size": it.a.size, "anchor": it.p}
		used[i] = true
		for j in range(i + 1, items.size()):
			if used.has(j):
				continue
			var o: Dictionary = items[j]
			# tanlangan qo'shin doim alohida; o'yinchiniki faqat o'ziniki bilan
			if o.a == map.selected_army or it.a == map.selected_army:
				continue
			var same: bool = o.a.owner == it.a.owner
			if not same and (not mix_far or o.a.owner == map.player_id or it.a.owner == map.player_id):
				continue
			if o.p.distance_to(it.p) < merge_px:
				cl.armies.append(o.a)
				cl.size += o.a.size
				used[j] = true
		var owners := {}
		for a in cl.armies:
			owners[a.owner] = owners.get(a.owner, 0) + a.size
		var ol: Array = owners.keys()
		ol.sort_custom(func(x, y): return owners[x] > owners[y])
		cl.owners = ol                  # birinchisi eng kuchlisi
		cl.owner = ol[0]
		if ol.size() > 1:
			cl.r = clampf(15.0 + 1.6 * cl.armies.size(), 16.0, 26.0) * zs
		else:
			cl.r = radius(cl.size) * zs + (2.0 if cl.armies.size() > 1 else 0.0)
		clusters.append(cl)
	_place()
	# UI paneli ostiga tushgan belgi chizilmaydi (va bosilmaydi)
	clusters = clusters.filter(func(cl):
		var box := Rect2(cl.center - Vector2(cl.r, cl.r), Vector2(cl.r, cl.r) * 2.0)
		for b in blocked:
			if b.intersects(box) or b.has_point(cl.anchor):
				return false
		return true)
	queue_redraw()


## Belgini ustun ustiga qo'yamiz va yozuvlar / boshqa belgilar bilan to'qnashmasligini ta'minlaymiz.
func _place() -> void:
	var placed: Array = []
	for cl in clusters:
		var r: float = cl.r
		var c: Vector2 = cl.anchor - Vector2(0, STEM + r)
		for _k in 4:
			var moved := false
			var box := Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)
			for lr in avoid_rects:
				if box.intersects(lr):
					c.y = lr.position.y - r - 3.0      # yozuvdan yuqoriga ko'taramiz
					moved = true
					break
			for o in placed:
				var d: Vector2 = c - o.center
				var need: float = r + o.r + 3.0
				if d.length() < need:
					c.x = o.center.x + (need if d.x >= 0.0 else -need)   # boshqa belgi bilan yonma-yon
					moved = true
			if not moved:
				break
		cl.center = c
		placed.append(cl)


## Ekrandagi nuqtada qaysi belgi bor (yo'q bo'lsa bo'sh lug'at).
func hit(pos: Vector2) -> Dictionary:
	for i in range(clusters.size() - 1, -1, -1):
		var cl: Dictionary = clusters[i]
		if pos.distance_to(cl.center) <= cl.r + 4.0:
			return cl
	return {}


static func shield(c: Vector2, r: float) -> PackedVector2Array:
	var w := r * 0.95
	var top := c.y - r * 0.92
	var mid := c.y + r * 0.2
	var pts := PackedVector2Array([Vector2(c.x - w, top), Vector2(c.x + w, top), Vector2(c.x + w, mid)])
	for k in range(1, 8):          # pastki qismi uchli yoy
		var t := k / 8.0
		pts.append(Vector2(c.x + w * (1.0 - t), mid + (r * 1.12 - r * 0.2) * sin(t * PI * 0.5)))
	for k in range(0, 8):
		var t := k / 8.0
		pts.append(Vector2(c.x - w * t, mid + (r * 1.12 - r * 0.2) * cos(t * PI * 0.5)))
	pts.append(Vector2(c.x - w, mid))
	return pts


func _draw() -> void:
	for cl in clusters:
		var a0: ArmyData = cl.armies[0]
		var col: Color = map.data.countries[cl.owner].color if map.data.countries.has(cl.owner) else Color.GRAY
		var mine: bool = cl.owner == map.player_id
		var sel: bool = map.selected_army in cl.armies
		var c: Vector2 = cl.center
		var r: float = cl.r
		var ow := 4.0 if sel else 3.0
		var oc := SELECT if sel else OUTLINE
		# ustun va hududdagi nuqta
		var foot: Vector2 = cl.anchor
		draw_line(foot, c + Vector2(0, r * (0.9 if not mine else 0.95)), OUTLINE, 3.0, true)
		draw_circle(foot, 3.5, OUTLINE)
		draw_circle(foot, 2.0, col)
		# shakl: o'zimizniki doira, dushman qalqon
		if mine:
			draw_circle(c, r + ow, oc, true, -1.0, true)
			draw_circle(c, r, col, true, -1.0, true)
			draw_arc(c, r - 2.5, 0, TAU, 40, Color(1, 1, 1, 0.55), 1.5, true)
		else:
			# turli davlatlar: orqada ularning ranglari ustma-ust (eng ko'pi bilan 3 ta)
			var ol: Array = cl.owners
			for k in range(mini(ol.size(), 3) - 1, 0, -1):
				var bc2: Color = map.data.countries[ol[k]].color if map.data.countries.has(ol[k]) else Color.GRAY
				var off := Vector2(5.0 * k, -5.0 * k)
				draw_colored_polygon(shield(c + off, r + ow), oc)
				draw_colored_polygon(shield(c + off, r), bc2)
			draw_colored_polygon(shield(c, r + ow), oc)
			draw_colored_polygon(shield(c, r), col)
		var mixed: bool = cl.owners.size() > 1
		# raqam: polklar soni; turli davlatlar aralash bo'lsa - qo'shinlar soni ("x5")
		var fs := int(clampf(r * (0.8 if mixed else 0.95), 13.0, 26.0))
		var txt := ("x%d" % cl.armies.size()) if mixed else str(cl.size)
		var tw := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var bp := c + Vector2(-tw * 0.5, fs * 0.36 - (2.0 if not mine else 0.0))
		draw_string_outline(_font, bp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.9))
		draw_string(_font, bp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 0.8) if sel else Color.WHITE)
		# birlashgan bo'lsa: "x3" belgisi
		var n: int = cl.armies.size()
		if n > 1 and not mixed:
			var bc := c + Vector2(r * 0.85, -r * 0.85)
			var bt := "x%d" % n
			var bw := _font.get_string_size(bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_rect(Rect2(bc - Vector2(bw * 0.5 + 4, 9), Vector2(bw + 8, 17)), OUTLINE)
			draw_rect(Rect2(bc - Vector2(bw * 0.5 + 3, 8), Vector2(bw + 6, 15)), Color(0.95, 0.85, 0.5))
			draw_string(_font, bc + Vector2(-bw * 0.5, 4.5), bt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, OUTLINE)
		if a0.moved and mine:
			draw_circle(c + Vector2(-r * 0.8, -r * 0.8), 4.0, Color(0.6, 0.6, 0.6))   # bu yurishda yurgan
