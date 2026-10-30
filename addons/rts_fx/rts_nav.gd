## Ground navigation for every land unit: rivers, the lake and the canal are blocked,
## bridges are open. A map calls RtsNav.setup(mask_png, origin, cell_size) once.
##   RtsNav.find_path(from, to) -> PackedVector3Array of waypoints (last one is the goal)
##   RtsNav.walkable(p) -> bool
##   RtsNav.add_obstacle(xform, size) -> cells   /   RtsNav.remove_obstacle(cells)
##     buildings, wrecks, bunkers... units walk around them instead of over the roof
class_name RtsNav
extends RefCounted

static var grid: AStarGrid2D = null
static var vgrid: AStarGrid2D = null          # vehicles: same as grid + trenches (tanks can't cross them)
static var _solid := PackedByteArray()
static var _obst := PackedByteArray()        # obstacle reference count per cell
static var _vobst := PackedByteArray()       # vehicle-only obstacles (trenches)
static var _n := 0
static var _origin := Vector2.ZERO
static var _cell := 4.0


static func setup(mask_path: String, origin: Vector2, cell := 2.0) -> void:
	if not ResourceLoader.exists(mask_path):
		grid = null
		return
	setup_image((load(mask_path) as Texture2D).get_image(), origin, cell)


## Xotiradagi niqob rasmidan (jang maydoni generatori): qiymat > 127 = o'tib bo'lmaydi.
static func setup_image(src: Image, origin: Vector2, cell := 2.0) -> void:
	var img := src.duplicate() as Image
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_L8)
	_n = img.get_width()
	_origin = origin
	_cell = cell
	_solid = img.get_data()
	_obst = PackedByteArray()
	_obst.resize(_n * _n)
	_vobst = PackedByteArray()
	_vobst.resize(_n * _n)
	vgrid = _new_grid(cell)
	grid = AStarGrid2D.new()
	grid.region = Rect2i(0, 0, _n, _n)
	grid.cell_size = Vector2(cell, cell)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.jumping_enabled = true
	grid.update()
	for j in _n:
		var row := j * _n
		var i := 0
		while i < _n:
			if _solid[row + i] > 127:
				var s := i
				while i < _n and _solid[row + i] > 127:
					i += 1
				grid.fill_solid_region(Rect2i(s, j, i - s, 1), true)
				vgrid.fill_solid_region(Rect2i(s, j, i - s, 1), true)
			else:
				i += 1


static func _new_grid(cell: float) -> AStarGrid2D:
	var g := AStarGrid2D.new()
	g.region = Rect2i(0, 0, _n, _n)
	g.cell_size = Vector2(cell, cell)
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	g.jumping_enabled = true
	g.update()
	return g


static func _id(p: Vector3) -> Vector2i:
	return Vector2i(clampi(int((p.x - _origin.x) / _cell), 0, _n - 1), clampi(int((p.z - _origin.y) / _cell), 0, _n - 1))


static func _pos(id: Vector2i) -> Vector3:
	return Vector3(_origin.x + (id.x + 0.5) * _cell, 0.0, _origin.y + (id.y + 0.5) * _cell)


static func _solid_at(id: Vector2i, vehicle := false) -> bool:
	var k := id.y * _n + id.x
	return _solid[k] > 127 or _obst[k] > 0 or (vehicle and _vobst[k] > 0)


## Blocks the cells under a rotated rectangle (size = x / z extent in metres, centred on xform.origin).
static func add_obstacle(xf: Transform3D, size: Vector2, margin := 0.3) -> PackedInt32Array:
	var cells := PackedInt32Array()
	if grid == null:
		return cells
	var hx := size.x * 0.5 + margin
	var hz := size.y * 0.5 + margin
	var r := Vector2(hx, hz).length()
	var c := _id(xf.origin)
	var rc := int(ceil(r / _cell)) + 1
	var inv := xf.affine_inverse()
	for dy in range(-rc, rc + 1):
		for dx in range(-rc, rc + 1):
			var q := c + Vector2i(dx, dy)
			if q.x < 0 or q.y < 0 or q.x >= _n or q.y >= _n:
				continue
			var lp := inv * _pos(q)
			lp.y = 0.0
			if absf(lp.x) <= hx and absf(lp.z) <= hz:
				var k := q.y * _n + q.x
				if _obst[k] < 255:
					_obst[k] += 1
				cells.append(k)
				grid.set_point_solid(q, true)
				vgrid.set_point_solid(q, true)
	return cells


## Blocks cells for vehicles only (a trench: infantry walks in it, tanks can't cross).
static func add_vehicle_obstacle(xf: Transform3D, size: Vector2, margin := 0.5) -> PackedInt32Array:
	var cells := PackedInt32Array()
	if grid == null:
		return cells
	var hx := size.x * 0.5 + margin
	var hz := size.y * 0.5 + margin
	var c := _id(xf.origin)
	var rc := int(ceil(Vector2(hx, hz).length() / _cell)) + 1
	var inv := xf.affine_inverse()
	for dy in range(-rc, rc + 1):
		for dx in range(-rc, rc + 1):
			var q := c + Vector2i(dx, dy)
			if q.x < 0 or q.y < 0 or q.x >= _n or q.y >= _n:
				continue
			var lp := inv * _pos(q)
			if absf(lp.x) <= hx and absf(lp.z) <= hz:
				var k := q.y * _n + q.x
				if _vobst[k] < 255:
					_vobst[k] += 1
				cells.append(k)
				vgrid.set_point_solid(q, true)
	return cells


static func remove_vehicle_obstacle(cells: PackedInt32Array) -> void:
	if grid == null:
		return
	for k in cells:
		if _vobst[k] > 0:
			_vobst[k] -= 1
		if _vobst[k] == 0 and _obst[k] == 0 and _solid[k] <= 127:
			vgrid.set_point_solid(Vector2i(k % _n, k / _n), false)


## Blocks the footprint of a model already in the tree (its meshes' bounding box, turned like the node).
static func add_node_obstacle(n: Node3D, margin := 0.3, shrink := 1.0) -> PackedInt32Array:
	var inv := n.global_transform.affine_inverse()
	var acc := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		var a: AABB = (inv * mi.global_transform) * mi.mesh.get_aabb()
		acc = a if first else acc.merge(a)
		first = false
	if first:
		return PackedInt32Array()
	var sc := n.global_basis.get_scale()
	var c := n.global_transform * acc.get_center()
	var b := Basis(Vector3.UP, n.global_rotation.y)
	return add_obstacle(Transform3D(b, c), Vector2(acc.size.x * sc.x, acc.size.z * sc.z) * shrink, margin)


static func remove_obstacle(cells: PackedInt32Array) -> void:
	if grid == null:
		return
	for k in cells:
		if _obst[k] > 0:
			_obst[k] -= 1
		if _obst[k] == 0 and _solid[k] <= 127:
			grid.set_point_solid(Vector2i(k % _n, k / _n), false)
			if _vobst[k] == 0:
				vgrid.set_point_solid(Vector2i(k % _n, k / _n), false)


static func walkable(p: Vector3, vehicle := false) -> bool:
	if grid == null:
		return true
	return not _solid_at(_id(p), vehicle)


## Closest walkable point (for orders given onto water).
static func nearest_walkable(p: Vector3, vehicle := false) -> Vector3:
	if grid == null or walkable(p, vehicle):
		return p
	var c := _id(p)
	for r in range(1, 40):
		var best := Vector2i(-1, -1)
		var bd := INF
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var q := c + Vector2i(dx, dy)
				if q.x < 0 or q.y < 0 or q.x >= _n or q.y >= _n or _solid_at(q, vehicle):
					continue
				var d := float(dx * dx + dy * dy)
				if d < bd: bd = d; best = q
		if best.x >= 0:
			return _pos(best)
	return p


## True when the straight line a->b never touches water.
static func line_clear(a: Vector3, b: Vector3, vehicle := false) -> bool:
	if grid == null:
		return true
	var d := Vector2(b.x - a.x, b.z - a.z)
	var steps := int(d.length() / (_cell * 0.5)) + 1
	for k in steps + 1:
		var t := float(k) / steps
		if _solid_at(_id(Vector3(a.x + d.x * t, 0, a.z + d.y * t)), vehicle):
			return false
	return true


static func find_path(from: Vector3, to: Vector3, vehicle := false) -> PackedVector3Array:
	var out := PackedVector3Array()
	if grid == null:
		out.append(to)
		return out
	var goal := nearest_walkable(to, vehicle)
	if line_clear(from, goal, vehicle):
		out.append(goal)
		return out
	var a := _id(nearest_walkable(from, vehicle))
	var b := _id(goal)
	var ids: Array[Vector2i] = (vgrid if vehicle else grid).get_id_path(a, b, true)
	if ids.size() < 2:
		out.append(goal)
		return out
	var pts: Array[Vector3] = []
	for id in ids:
		pts.append(_pos(id))
	pts[pts.size() - 1] = goal
	# string pulling: jump to the farthest point we can see
	var cur := from
	var i := 0
	while i < pts.size():
		var j := mini(pts.size() - 1, i + 60)
		while j > i and not line_clear(cur, pts[j], vehicle):
			j -= 1
		cur = pts[j]
		out.append(cur)
		i = j + 1
	return out
