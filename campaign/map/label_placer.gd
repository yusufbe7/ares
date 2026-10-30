## Yozuv joylash uchun hisob-kitoblar (statik): chamfer masofa, eng yaxshi nuqta, ekrandagi to'rtburchak.
class_name LabelPlacer
extends RefCounted


## Davlat kataklari ichida chegaragacha masofa (2 o'tishli chamfer). box ichida, w*h massiv.
static func distance(cell: PackedInt32Array, lw: int, box: Rect2i, cid: int) -> PackedFloat32Array:
	var w := box.size.x
	var h := box.size.y
	var dt := PackedFloat32Array()
	dt.resize(w * h)
	for y in h:
		var row := (box.position.y + y) * lw + box.position.x
		for x in w:
			dt[y * w + x] = 1e6 if cell[row + x] == cid else 0.0
	for y in h:
		for x in w:
			var k := y * w + x
			if dt[k] == 0.0:
				continue
			var v := dt[k]
			v = minf(v, (dt[k - 1] if x > 0 else 0.0) + 1.0)
			v = minf(v, (dt[k - w] if y > 0 else 0.0) + 1.0)
			v = minf(v, (dt[k - w - 1] if x > 0 and y > 0 else 0.0) + 1.414)
			v = minf(v, (dt[k - w + 1] if x < w - 1 and y > 0 else 0.0) + 1.414)
			dt[k] = v
	for y in range(h - 1, -1, -1):
		for x in range(w - 1, -1, -1):
			var k := y * w + x
			if dt[k] == 0.0:
				continue
			var v := dt[k]
			v = minf(v, (dt[k + 1] if x < w - 1 else 0.0) + 1.0)
			v = minf(v, (dt[k + w] if y < h - 1 else 0.0) + 1.0)
			v = minf(v, (dt[k + w + 1] if x < w - 1 and y < h - 1 else 0.0) + 1.414)
			v = minf(v, (dt[k + w - 1] if x > 0 and y < h - 1 else 0.0) + 1.414)
			dt[k] = v
	return dt


## Eng keng nuqta (markazga biroz yaqinroq bo'lgani afzal).
static func best(dt: PackedFloat32Array, box: Rect2i, cen: Vector2) -> int:
	var w := box.size.x
	var b := 0
	var bs := -1e9
	for k in dt.size():
		if dt[k] <= 0.0:
			continue
		var s := dt[k] - 0.04 * Vector2(box.position.x + k % w, box.position.y + k / w).distance_to(cen)
		if s > bs:
			bs = s
			b = k
	return b


## Yerga yotqizilgan yozuvning ekrandagi to'rtburchagi.
static func flat_rect(l: Label3D, cam: Camera3D) -> Rect2:
	var ts: Vector2 = l.get_meta("ts", Vector2.ONE)
	var r := Rect2()
	var first := true
	for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var q := l.position + Vector3(s.x * ts.x * 0.5, 0, s.y * ts.y * 0.5)
		if cam.is_position_behind(q):
			return Rect2()
		var sp := cam.unproject_position(q)
		if first:
			r = Rect2(sp, Vector2.ZERO)
			first = false
		else:
			r = r.expand(sp)
	return r


## Ekranda doimiy o'lchamli (fixed_size) billboard yozuv; matn nuqtadan pastga osilgan.
static func bill_rect(l: Label3D, cam: Camera3D, vp_h: float) -> Rect2:
	var ts: Vector2 = l.get_meta("ts", Vector2.ONE)
	var k := vp_h / (2.0 * tan(deg_to_rad(cam.fov) * 0.5))
	var sz := ts * k
	var a := cam.unproject_position(l.position)
	return Rect2(a.x - sz.x * 0.5, a.y + 4.0, sz.x, sz.y * 0.8)
