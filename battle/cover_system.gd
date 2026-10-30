class_name CoverSystem
extends Node
## Every piece of hard geometry on the map publishes cover slots here: wall
## faces and corners, tree trunks, rocks, fallen logs, shell craters, trenches,
## sandbags and burnt-out hulls. Infantry then asks this system for the best
## place to be, instead of each soldier doing its own geometry test.
##
## Slot score = protection − distance + facing the enemy − a penalty if taken.

class Slot extends RefCounted:
	var position: Vector3
	var facing: Vector3          # the direction this slot protects FROM
	var quality: float = 0.5     # 0..1, how much damage it stops
	var kind: String = "wall"
	var occupant: int = 0        # instance id of the soldier holding it, 0 = free
	var alive: bool = true

var slots: Array = []
var _grid: Dictionary = {}       # Vector2i cell -> Array[Slot]
var cell_size: float = 24.0

func _cell(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(pos.x / cell_size)), int(floor(pos.z / cell_size)))

func add_slot(pos: Vector3, facing: Vector3, quality: float, kind: String) -> Slot:
	var s := Slot.new()
	s.position = pos
	s.facing = facing.normalized() if facing.length() > 0.01 else Vector3.FORWARD
	s.quality = clampf(quality, 0.0, 1.0)
	s.kind = kind
	slots.append(s)
	var c := _cell(pos)
	if not _grid.has(c):
		_grid[c] = []
	_grid[c].append(s)
	return s

func slot_count() -> int:
	var n := 0
	for s: Slot in slots:
		if s.alive:
			n += 1
	return n

## Wall faces of a rectangular building: one slot per face segment, plus the
## four corners, which are the good ones — they cover two directions.
func add_building(center: Vector3, size: Vector3, rotation_y: float) -> Array:
	var made: Array = []
	var basis := Basis(Vector3.UP, rotation_y)
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var faces := [
		{"n": Vector3(0, 0, -1), "o": Vector3(0, 0, -hz), "len": size.x},
		{"n": Vector3(0, 0, 1), "o": Vector3(0, 0, hz), "len": size.x},
		{"n": Vector3(-1, 0, 0), "o": Vector3(-hx, 0, 0), "len": size.z},
		{"n": Vector3(1, 0, 0), "o": Vector3(hx, 0, 0), "len": size.z},
	]
	for f in faces:
		var normal: Vector3 = basis * (f["n"] as Vector3)
		var steps: int = maxi(1, int(float(f["len"]) / 3.0))
		for i in range(steps):
			var t: float = (float(i) + 0.5) / float(steps) - 0.5
			var along: Vector3 = Vector3(-normal.z, 0, normal.x) * float(f["len"]) * t
			var pos: Vector3 = center + basis * (f["o"] as Vector3) + normal * 0.9 + along
			made.append(add_slot(pos, normal, 0.82, "wall"))
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			var corner: Vector3 = center + basis * Vector3(cx * (hx + 1.0), 0, cz * (hz + 1.0))
			var dir: Vector3 = (corner - center).normalized()
			made.append(add_slot(corner, dir, 0.9, "corner"))
	return made

func add_tree(pos: Vector3) -> void:
	for i in range(3):
		var ang := TAU * float(i) / 3.0
		var dir := Vector3(cos(ang), 0, sin(ang))
		add_slot(pos + dir * 1.1, dir, 0.45, "tree")

func add_rock(pos: Vector3, radius: float) -> void:
	for i in range(4):
		var ang := TAU * float(i) / 4.0
		var dir := Vector3(cos(ang), 0, sin(ang))
		add_slot(pos + dir * (radius + 0.6), dir, 0.6, "rock")

func add_log(pos: Vector3, direction: Vector3) -> void:
	var side := Vector3(-direction.z, 0, direction.x).normalized()
	add_slot(pos + side * 1.0, side, 0.55, "log")
	add_slot(pos - side * 1.0, -side, 0.55, "log")

func add_crater(pos: Vector3, radius: float) -> void:
	for i in range(4):
		var ang := TAU * float(i) / 4.0
		var dir := Vector3(cos(ang), 0, sin(ang))
		add_slot(pos + dir * radius * 0.5, dir, 0.58, "crater")

func add_trench(a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	var dir := (b - a).normalized()
	var steps := maxi(1, int(length / 2.5))
	for i in range(steps):
		var t := (float(i) + 0.5) / float(steps)
		var pos := a.lerp(b, t)
		var side := Vector3(-dir.z, 0, dir.x)
		add_slot(pos, side, 0.78, "trench")

func add_sandbags(pos: Vector3, facing: Vector3) -> void:
	add_slot(pos, facing, 0.62, "sandbag")

func add_wreck(pos: Vector3) -> void:
	for i in range(3):
		var ang := TAU * float(i) / 3.0
		var dir := Vector3(cos(ang), 0, sin(ang))
		add_slot(pos + dir * 2.6, dir, 0.72, "wreck")

## Removes cover that has been blown away, so soldiers stop trusting a wall
## that is no longer there.
func invalidate_near(pos: Vector3, radius: float) -> void:
	var r2 := radius * radius
	for s: Slot in slots:
		if s.alive and s.position.distance_squared_to(pos) < r2:
			s.alive = false
			s.occupant = 0

func _candidates(pos: Vector3, radius: float) -> Array:
	var out: Array = []
	var reach := int(ceil(radius / cell_size))
	var c := _cell(pos)
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			var key := Vector2i(c.x + dx, c.y + dz)
			if _grid.has(key):
				out.append_array(_grid[key])
	return out

## The pick a soldier makes. threat_dir is the direction the shooting is coming
## from; a slot that faces the wrong way is worse than no slot at all.
func best_slot(from: Vector3, threat_dir: Vector3, max_distance: float, seeker_id: int) -> Slot:
	var best: Slot = null
	var best_score := -INF
	var threat := threat_dir.normalized()
	for s: Slot in _candidates(from, max_distance):
		if not s.alive:
			continue
		if s.occupant != 0 and s.occupant != seeker_id:
			continue
		var d := from.distance_to(s.position)
		if d > max_distance:
			continue
		var facing_bonus: float = s.facing.dot(threat) * 28.0
		var score: float = s.quality * 40.0 - d * 0.9 + facing_bonus
		if s.occupant == seeker_id:
			score += 6.0      # stickiness: do not thrash between two equal slots
		if score > best_score:
			best_score = score
			best = s
	return best

func take(slot: Slot, seeker_id: int) -> void:
	if slot != null and slot.alive:
		slot.occupant = seeker_id

func release(slot: Slot, seeker_id: int) -> void:
	if slot != null and slot.occupant == seeker_id:
		slot.occupant = 0

## How much of a hit this position stops, used by the damage model.
func protection_at(pos: Vector3, from_dir: Vector3) -> float:
	var best := 0.0
	for s: Slot in _candidates(pos, 3.0):
		if not s.alive:
			continue
		if s.position.distance_to(pos) > 2.0:
			continue
		var align: float = s.facing.dot(-from_dir.normalized())
		if align <= 0.0:
			continue
		best = maxf(best, s.quality * align)
	return best
