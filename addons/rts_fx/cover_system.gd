## AI COVER SYSTEM: every place a soldier can hide is a cover SLOT, created automatically when the map
## is built and while the battle goes on (house walls, rocks, tree trunks, fallen trees, craters,
## trenches, sandbags, wrecks, ruins). Each slot knows which way it protects, how much (full / half)
## and who is using it. Soldiers pick the best slot:
##     score = protection - distance + facing the enemy - taken
## Danger zones (artillery warning circles) are avoided and soldiers run out of them.
class_name CoverSystem
extends RefCounted

class Slot extends RefCounted:
	var pos := Vector3.ZERO
	var dir := Vector3.ZERO        # direction the cover protects against (towards the obstacle); ZERO = all sides
	var prot := 0.5                # 1 = full cover (wall, trench), 0.5 = half (tree, low wall)
	var kind := ""
	var src: Object = null         # owner, slot dies with it
	var occupant: Node = null
	var alive := true

	func omni() -> bool:
		return dir == Vector3.ZERO


const CELL := 6.0
static var slots: Array = []
static var _grid := {}                 # Vector2i -> Array[Slot]
static var _nodes := {}                # instance id of a "cover" group node -> Slot
static var _sync_t := 0.0
static var dangers: Array = []         # [{pos, r, until}]


static func reset() -> void:
	slots.clear()
	_grid.clear()
	_nodes.clear()
	dangers.clear()


static func _cell(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / CELL)), int(floor(p.z / CELL)))


static func add(pos: Vector3, dir: Vector3, prot: float, kind: String, src: Object = null) -> Slot:
	var s := Slot.new()
	s.pos = pos
	s.dir = Vector3(dir.x, 0, dir.z).normalized() if dir.length() > 0.01 else Vector3.ZERO
	s.prot = prot
	s.kind = kind
	s.src = src
	slots.append(s)
	var c := _cell(pos)
	if not _grid.has(c):
		_grid[c] = []
	_grid[c].append(s)
	return s


static func remove(s: Slot) -> void:
	if s == null or not s.alive:
		return
	s.alive = false
	s.occupant = null
	var c := _cell(s.pos)
	if _grid.has(c):
		(_grid[c] as Array).erase(s)
	slots.erase(s)


static func query(p: Vector3, r: float) -> Array:
	var out: Array = []
	var c0 := _cell(p - Vector3(r, 0, r))
	var c1 := _cell(p + Vector3(r, 0, r))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			for s in _grid.get(Vector2i(cx, cz), []):
				if s.alive and Vector2(s.pos.x - p.x, s.pos.z - p.z).length() <= r:
					out.append(s)
	return out


static func count() -> int:
	return slots.size()


static func in_use() -> int:
	var n := 0
	for s in slots:
		if s.occupant != null and is_instance_valid(s.occupant):
			n += 1
	return n


static func is_free(s: Slot, unit: Node) -> bool:
	return s.occupant == null or s.occupant == unit or not is_instance_valid(s.occupant) or not s.occupant.call("is_alive")


## How much the slot shields a man in it from a shot / blast coming from `from` (0..1).
static func protection(s: Slot, from: Vector3) -> float:
	if s == null or not s.alive:
		return 0.0
	if s.omni():
		return s.prot
	var to := from - s.pos
	to.y = 0
	if to.length() < 0.5:
		return 0.0
	var f: float = s.dir.dot(to.normalized())
	return s.prot * clampf((f + 0.15) / 0.6, 0.0, 1.0)


## Best free slot for `unit` within max_d. threat = enemy position (or null).
static func best(unit: Node3D, threat: Variant, max_d: float, toward: Variant = null) -> Slot:
	var p := unit.global_position
	var best_s: Slot = null
	var bs := -INF
	for s in query(p, max_d):
		if not is_free(s, unit):
			continue
		var d := Vector2(s.pos.x - p.x, s.pos.z - p.z).length()
		var score: float = s.prot * 10.0 - d * 0.45
		if threat != null:
			var tv: Vector3 = threat
			var f: float = 1.0 if s.omni() else s.dir.dot((tv - s.pos).normalized())
			score += f * 6.0
			# don't run towards the enemy to hide (unless ordered forward)
			var closer: float = Vector2(tv.x - p.x, tv.z - p.z).length() - Vector2(tv.x - s.pos.x, tv.z - s.pos.z).length()
			if toward == null and closer > 6.0:
				score -= closer * 0.4
		if toward != null:
			var gv: Vector3 = toward
			score -= Vector2(gv.x - s.pos.x, gv.z - s.pos.z).length() * 0.3
		if in_danger(s.pos):
			score -= 60.0
		if score > bs:
			bs = score
			best_s = s
	return best_s


static func claim(s: Slot, unit: Node) -> void:
	if s:
		s.occupant = unit


static func release(s: Slot, unit: Node) -> void:
	if s and s.occupant == unit:
		s.occupant = null


# ------------------------------------------------------------------ danger zones (artillery warning)
static func add_danger(p: Vector3, r: float, secs: float) -> void:
	dangers.append({"pos": p, "r": r, "until": Time.get_ticks_msec() / 1000.0 + secs})


static func in_danger(p: Vector3) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	for d in dangers:
		if d.until > now and Vector2(p.x - d.pos.x, p.z - d.pos.z).length() < d.r:
			return true
	return false


static func danger_at(p: Vector3) -> Variant:
	var now := Time.get_ticks_msec() / 1000.0
	for d in dangers:
		if d.until > now and Vector2(p.x - d.pos.x, p.z - d.pos.z).length() < d.r:
			return d
	return null


# ------------------------------------------------------------------ "cover" group nodes (trenches, sandbags, wrecks)
## Called every frame or so by the game; turns new "cover" nodes into slots, drops dead ones.
static func sync(tree: SceneTree, delta: float) -> void:
	_sync_t -= delta
	if _sync_t > 0.0:
		return
	_sync_t = 1.0
	var now := Time.get_ticks_msec() / 1000.0
	dangers = dangers.filter(func(d): return d.until > now)
	var seen := {}
	for n in tree.get_nodes_in_group("cover"):
		var id := (n as Object).get_instance_id()
		seen[id] = true
		if _nodes.has(id):
			continue
		var p: Vector3 = (n as Node3D).global_position
		var kind := "trench" if n.has_meta("omni") else "obstacle"
		var prot := 0.85 if kind == "trench" else 0.8
		var dir := Vector3.ZERO
		if n.has_meta("dir"):
			dir = n.get_meta("dir")
		_nodes[id] = add(p, dir, prot, kind, n)
	for id in _nodes.keys():
		if not seen.has(id):
			remove(_nodes[id])
			_nodes.erase(id)
