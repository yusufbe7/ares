## A trench segment drawn by the player (like the trench-building dev log):
## a green wire box marks it, soldiers line up along it and dig, the ground really sinks
## (terrain heightmap + collision), dirt walls and spoil banks grow, and when it is deep
## enough it becomes cover that protects from every side.
class_name RtsTrench
extends Node3D

signal completed(t: RtsTrench)

const HALF_W := 1.25          # half width of the cut
const DEPTH := 1.7            # finished depth (a man stands with his head at the parapet)
const WORK_PER_M := 4.0       # worker-seconds per metre
const LINES := ["MORE DIRT...", "SPADE WORK", "NEARLY DEEP ENOUGH", "DEEPER...", "KEEP DIGGING!", "HEAVE!"]

var team := 0
var a := Vector3.ZERO
var b := Vector3.ZERO
var map: Node3D
var built := false
var dead := false
var progress := 0.0
var work := 10.0
var workers: Array = []
var open_start := false        # joined to another trench: no end wall there
var open_end := false
var links: Array = []          # joined trenches: our banks and walls are cut away inside them
var _lining: MeshInstance3D
var _wire: MeshInstance3D
var _label: Label3D
var _tick := 0.0
var _bubble_t := 2.0
var _last_depth := -1.0
var _covers: Array = []
var _vcells := PackedInt32Array()

static var _dirt_mat: StandardMaterial3D
static var _spoil_mat: StandardMaterial3D


static func create(parent: Node, p_map: Node3D, p_a: Vector3, p_b: Vector3, p_team := 0) -> RtsTrench:
	var t := RtsTrench.new()
	t.team = p_team
	t.map = p_map
	t.a = Vector3(p_a.x, 0, p_a.z)
	t.b = Vector3(p_b.x, 0, p_b.z)
	parent.add_child(t)
	t.global_position = Vector3((t.a.x + t.b.x) * 0.5, p_map.ground_original((t.a.x + t.b.x) * 0.5, (t.a.z + t.b.z) * 0.5), (t.a.z + t.b.z) * 0.5)
	t.work = maxf(8.0, t.length() * WORK_PER_M)
	# no tree may stand in the cut or on the spoil
	if p_map.has_method("clear_trees"):
		var n := int(t.length() / 2.5) + 1
		for i in n + 1:
			p_map.clear_trees(t.a.lerp(t.b, float(i) / n), HALF_W + 3.5)
	t._setup()
	# tanks and trucks can't cross a trench
	var d := t.b - t.a
	t._vcells = RtsNav.add_vehicle_obstacle(Transform3D(Basis(Vector3.UP, atan2(d.x, d.z)), t.global_position), Vector2(HALF_W * 2.0 + 1.0, t.length()))
	return t


func length() -> float:
	return Vector2(b.x - a.x, b.z - a.z).length()


func display_name() -> String:
	return "Trench"


func work_fraction() -> float:
	return clampf(progress / work, 0.0, 1.0)


func _dir() -> Vector3:
	var d := b - a
	d.y = 0
	return d.normalized()


func _setup() -> void:
	add_to_group("trenches")
	add_to_group("trenches_%d" % team)
	_lining = MeshInstance3D.new()
	_lining.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_lining)
	_lining.top_level = true
	_lining.global_transform = Transform3D.IDENTITY
	_wire = MeshInstance3D.new()
	_wire.top_level = true
	_wire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_wire)
	_wire.global_transform = Transform3D.IDENTITY
	_wire.mesh = wire_box(map, a, b, HALF_W + 0.25, 1.4, Color(0.35, 1.0, 0.4))
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.fixed_size = true
	_label.no_depth_test = true
	_label.pixel_size = 0.0005
	_label.font_size = 24
	_label.outline_size = 8
	_label.modulate = Color(0.6, 1.0, 0.6)
	_label.position.y = 3.0
	add_child(_label)
	_update(true)


## Green / blue line box hugging the ground from p to q (the trench blueprint).
static func wire_box(p_map: Node3D, p: Vector3, q: Vector3, hw: float, h: float, col: Color) -> ImmediateMesh:
	var im := ImmediateMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.no_depth_test = true
	var d := q - p
	d.y = 0
	if d.length() < 0.1:
		d = Vector3.FORWARD * 0.1
	var n := d.normalized().cross(Vector3.UP) * hw
	var steps := maxi(1, int(d.length() / 3.0))
	im.surface_begin(Mesh.PRIMITIVE_LINES, m)
	for side in [-1.0, 1.0]:
		for lvl in [0.08, h]:
			for k in steps:
				var u0: Vector3 = p + d * (float(k) / steps) + n * side
				var u1: Vector3 = p + d * (float(k + 1) / steps) + n * side
				im.surface_add_vertex(Vector3(u0.x, p_map.ground_original(u0.x, u0.z) + lvl, u0.z))
				im.surface_add_vertex(Vector3(u1.x, p_map.ground_original(u1.x, u1.z) + lvl, u1.z))
	for e in [p, p + d]:
		var g1: Vector3 = e + n; var g2: Vector3 = e - n
		var y1: float = p_map.ground_original(g1.x, g1.z); var y2: float = p_map.ground_original(g2.x, g2.z)
		for lvl in [0.08, h]:
			im.surface_add_vertex(Vector3(g1.x, y1 + lvl, g1.z)); im.surface_add_vertex(Vector3(g2.x, y2 + lvl, g2.z))
		im.surface_add_vertex(Vector3(g1.x, y1 + 0.08, g1.z)); im.surface_add_vertex(Vector3(g1.x, y1 + h, g1.z))
		im.surface_add_vertex(Vector3(g2.x, y2 + 0.08, g2.z)); im.surface_add_vertex(Vector3(g2.x, y2 + h, g2.z))
	im.surface_end()
	return im


static func materials() -> void:
	if _dirt_mat:
		return
	_dirt_mat = StandardMaterial3D.new()
	_dirt_mat.albedo_texture = load("res://assets/textures/dirt_ground.jpg")
	_dirt_mat.normal_enabled = true
	_dirt_mat.normal_texture = load("res://assets/textures/dirt_ground_nrm.jpg")
	_dirt_mat.albedo_color = Color(0.78, 0.68, 0.58)
	_dirt_mat.roughness = 1.0
	_dirt_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_spoil_mat = _dirt_mat.duplicate()
	_spoil_mat.albedo_color = Color(0.92, 0.82, 0.68)


# ------------------------------------------------------------------ workers
func assign(soldiers: Array) -> int:
	if built or dead:
		return 0
	var n := 0
	for s in soldiers:
		if not is_instance_valid(s) or s.team != team or not s.is_commandable():
			continue
		if not workers.has(s):
			if workers.size() >= maxi(2, int(length() / 2.5)):
				break
			workers.append(s)
		n += 1
	for i in workers.size():
		var w: RtsSoldier = workers[i]
		if soldiers.has(w):
			w.work_on(self, slot(i, workers.size()))
	return n


## Digger i of n stands on the edge of the cut, alternating sides, spread along the trench.
func slot(i: int, n: int) -> Vector3:
	var t := (float(i / 2) + 0.5) / maxf(1.0, ceil(n / 2.0))
	var side := -1.0 if i % 2 == 0 else 1.0
	var p := a + (b - a) * t + _dir().cross(Vector3.UP) * side * (HALF_W + 0.7)
	return Vector3(p.x, map.ground_original(p.x, p.z), p.z)


## Diggers face the middle of the cut, not the centre of the whole trench.
func face_point(from: Vector3) -> Vector3:
	var ab := b - a
	var t := clampf((from - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return a + ab * t


func distance_to(p: Vector3) -> float:
	var q := face_point(p)
	return Vector2(p.x - q.x, p.z - q.z).length()


func _process(delta: float) -> void:
	if built or dead:
		return
	var digging := 0
	for w in workers:
		if is_instance_valid(w) and w.work_site == self and w.is_digging():
			digging += 1
	if digging > 0:
		progress += delta * digging * (1.0 / (1.0 + 0.1 * (digging - 1)))
	if progress >= work:
		_complete()
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.6
		_update(false)
		workers = workers.filter(func(w): return is_instance_valid(w) and w.state != RtsSoldier.State.DEAD and w.work_site == self)
		for i in workers.size():
			var w: RtsSoldier = workers[i]
			if not w.is_digging() and w.state in [RtsSoldier.State.IDLE, RtsSoldier.State.COVER] and w._nearest_enemy(70.0) == null:
				w.work_on(self, slot(i, workers.size()))
	_bubble_t -= delta
	if _bubble_t <= 0.0 and digging > 0:
		_bubble_t = randf_range(3.0, 6.0)
		var ws := workers.filter(func(w): return is_instance_valid(w) and w.is_digging())
		if not ws.is_empty():
			var txt: String = LINES[randi() % LINES.size()]
			if work_fraction() > 0.8: txt = "NEARLY DEEP ENOUGH"
			RtsBubble.say(ws[randi() % ws.size()], txt, 2.6)


func _update(force: bool) -> void:
	var f := work_fraction()
	var depth := DEPTH * f
	if force or absf(depth - _last_depth) > 0.06:
		_last_depth = depth
		if depth > 0.02:
			map.dig_segment(a, b, HALF_W, depth)
		_lining.mesh = _build_lining(depth, f)
	if _label:
		_label.text = "TRENCH  %d%%" % int(f * 100.0)


func _complete() -> void:
	built = true
	progress = work
	_update(true)
	if _wire: _wire.queue_free(); _wire = null
	if _label: _label.queue_free(); _label = null
	for w in workers:
		if is_instance_valid(w) and w.work_site == self:
			w.stop_work()
	workers.clear()
	# fighting positions inside, every 2.6 m
	var n := maxi(1, int(length() / 2.6))
	for k in n:
		var p := a + (b - a) * ((k + 0.5) / n)
		var c := Marker3D.new()
		add_child(c)
		c.top_level = true
		c.global_position = Vector3(p.x, map.get_height(p.x, p.z), p.z)
		c.set_meta("omni", true)
		c.add_to_group("cover")
		_covers.append(c)
	completed.emit(self)


## Positions to man the trench (soldiers stand inside, at the floor).
func fighting_positions() -> Array:
	var out: Array = []
	for c in _covers:
		out.append(c.global_position)
	return out


# ------------------------------------------------------------------ geometry
## Dirt walls + floor of the cut and two spoil banks on the lips.
func _build_lining(depth: float, f: float) -> ArrayMesh:
	materials()
	var d := b - a
	var L := d.length()
	var dir := d / maxf(L, 0.001)
	var nrm := dir.cross(Vector3.UP)
	var ext0 := HALF_W * 0.9 if open_start else 0.0
	var ext1 := HALF_W * 0.9 if open_end else 0.0
	var steps := maxi(2, int((L + ext0 + ext1) / 0.8))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# --- the cut: two leaning walls and the floor --------------------------------
	var rows: Array = []
	for k in steps + 1:
		var t := -ext0 + (L + ext0 + ext1) * k / steps
		var c := a + dir * t
		var gl: float = map.ground_original(c.x - nrm.x * HALF_W, c.z - nrm.z * HALF_W)
		var gr: float = map.ground_original(c.x + nrm.x * HALF_W, c.z + nrm.z * HALF_W)
		var fl := minf(gl, gr) - depth
		var wob := _n2(c.x * 1.7, c.z * 1.7) * 0.07
		var lipL := Vector3(c.x, gl + _lip_h(f), c.z) - nrm * (HALF_W + wob)
		var lipR := Vector3(c.x, gr + _lip_h(f), c.z) + nrm * (HALF_W - wob)
		var floorL := Vector3(c.x, fl, c.z) - nrm * (HALF_W - 0.2 + wob)
		var floorR := Vector3(c.x, fl, c.z) + nrm * (HALF_W - 0.2 - wob)
		rows.append([lipL, floorL, floorR, lipR, t])
	for k in steps:
		var r0: Array = rows[k]; var r1: Array = rows[k + 1]
		var u0: float = r0[4] / 2.0; var u1: float = r1[4] / 2.0
		if not _in_link((r0[0] + r1[0]) * 0.5, HALF_W - 0.1):
			_quad(st, r0[0], r1[0], r1[1], r0[1], u0, u1, 0.0, depth * 0.5)
		_quad(st, r0[1], r1[1], r1[2], r0[2], u0, u1, 0.0, HALF_W)
		if not _in_link((r0[3] + r1[3]) * 0.5, HALF_W - 0.1):
			_quad(st, r0[2], r1[2], r1[3], r0[3], u0, u1, depth * 0.5, 0.0)
	for e in [[0, open_start], [steps, open_end]]:
		if e[1]:
			continue
		var r: Array = rows[e[0]]
		_quad(st, r[0], r[3], r[2], r[1], 0.0, HALF_W, 0.0, depth * 0.5)
	st.generate_normals()
	var mesh := st.commit()
	mesh.surface_set_material(0, _dirt_mat)
	# --- spoil: an uneven earth parapet thrown up on both sides, wrapping round closed ends.
	# Swept along offset rings of the trench outline; its outer edge sinks under the grass
	# so the line where dirt meets ground is ragged like a real dug bank.
	var sp := SurfaceTool.new()
	sp.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring: Array = []           # [centre, outward dir, inner point, break_before]
	for k in steps + 1:
		var t := -ext0 + (L + ext0 + ext1) * k / steps
		var c := a + dir * t
		ring.append([c, nrm, c + nrm * HALF_W, false])
	for q in range(1, 8):
		var th := PI * q / 8.0
		var o := nrm * cos(th) + dir * sin(th)
		ring.append([b + dir * ext1, o, b + dir * ext1 + nrm * (HALF_W * cos(th)), false])
	for k in range(steps, -1, -1):
		var t := -ext0 + (L + ext0 + ext1) * k / steps
		var c := a + dir * t
		ring.append([c, -nrm, c - nrm * HALF_W, false])
	for q in range(1, 8):
		var th := PI * q / 8.0
		var o := -nrm * cos(th) - dir * sin(th)
		ring.append([a - dir * ext0, o, a - dir * ext0 - nrm * (HALF_W * cos(th)), false])
	ring.append(ring[0].duplicate())
	var offs := [0.0, 0.3, 0.7, 1.2, 1.75, 1.0]      # last = reach (filled per sample)
	var prof: Array = []
	for r in ring:
		var c: Vector3 = r[0]; var o: Vector3 = r[1]; var ip: Vector3 = r[2]
		var nz := _n2(c.x * 0.45 + o.x * 3.0, c.z * 0.45 + o.z * 3.0)
		var reach := 2.6 + 0.45 * nz
		var hgt := (0.12 + 0.5 * f) * (0.8 + 0.35 * _n2(c.x * 0.9 + o.x, c.z * 0.9 + o.z))
		var pts: Array = []
		for m in offs.size():
			var s: float = offs[m] if m < offs.size() - 1 else reach
			var p: Vector3 = ip + o * s
			var g: float = map.ground_original(p.x, p.z)
			var h: float
			if m == 0:
				h = g + _lip_h(f)
			elif m == offs.size() - 1:
				h = g - 0.14
			else:
				var x := s / reach
				h = g + hgt * sin(clampf(x * 1.25, 0.0, 1.0) * PI * 0.5 + 0.35) * (1.0 - x * x) + 0.05 * _n2(p.x * 3.1, p.z * 3.1) * f
			pts.append(Vector3(p.x, h, p.z))
		prof.append([pts, r[3]])
	var run := 0.0
	for k in prof.size() - 1:
		if prof[k + 1][1]:
			continue
		var p0: Array = prof[k][0]; var p1: Array = prof[k + 1][0]
		var du: float = (p0[0] as Vector3).distance_to(p1[0]) * 0.5
		for m in p0.size() - 1:
			if not links.is_empty() and (_in_link(p0[m], HALF_W + 0.1) or _in_link(p1[m], HALF_W + 0.1) or _in_link(p0[m + 1], HALF_W + 0.1) or _in_link(p1[m + 1], HALF_W + 0.1)):
				continue
			_quad(sp, p0[m], p1[m], p1[m + 1], p0[m + 1], run, run + du, m * 0.35, (m + 1) * 0.35)
		run += du
	sp.generate_normals()
	sp.commit(mesh)
	mesh.surface_set_material(1, _spoil_mat)
	return mesh


func _in_link(p: Vector3, r: float) -> bool:
	for o in links:
		if not is_instance_valid(o):
			continue
		var a2 := Vector2(o.a.x, o.a.z); var b2 := Vector2(o.b.x, o.b.z)
		var ab := b2 - a2
		var q := Vector2(p.x, p.z)
		var t := clampf((q - a2).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		if q.distance_to(a2 + ab * t) < r:
			return true
	return false


func _lip_h(f: float) -> float:
	return 0.04 + 0.12 * f


## cheap smooth value noise in -1..1 (deterministic per world position)
static func _n2(x: float, y: float) -> float:
	var ix := floorf(x); var iy := floorf(y)
	var fx := x - ix; var fy := y - iy
	fx = fx * fx * (3.0 - 2.0 * fx); fy = fy * fy * (3.0 - 2.0 * fy)
	var v00 := _h2(ix, iy); var v10 := _h2(ix + 1.0, iy)
	var v01 := _h2(ix, iy + 1.0); var v11 := _h2(ix + 1.0, iy + 1.0)
	return lerpf(lerpf(v00, v10, fx), lerpf(v01, v11, fx), fy) * 2.0 - 1.0


static func _h2(x: float, y: float) -> float:
	var v := sin(x * 127.1 + y * 311.7) * 43758.5453
	return v - floorf(v)


static func _quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, u0: float, u1: float, v0: float, v1: float) -> void:
	st.set_uv(Vector2(u0, v0)); st.add_vertex(p0)
	st.set_uv(Vector2(u1, v0)); st.add_vertex(p1)
	st.set_uv(Vector2(u1, v1)); st.add_vertex(p2)
	st.set_uv(Vector2(u0, v0)); st.add_vertex(p0)
	st.set_uv(Vector2(u1, v1)); st.add_vertex(p2)
	st.set_uv(Vector2(u0, v1)); st.add_vertex(p3)
