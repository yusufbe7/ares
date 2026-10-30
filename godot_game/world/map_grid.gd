class_name MapGrid
extends RefCounted
## Offset ("odd-r") hex grid used by the global map. Provinces are cells, so
## adjacency, fronts, borders and supply range all fall out of the grid for
## free and every client rebuilds the same map from the same seed.

const WIDTH := 48
const HEIGHT := 32

static func index(col: int, row: int) -> int:
	return row * WIDTH + col

static func col_of(idx: int) -> int:
	return idx % WIDTH

static func row_of(idx: int) -> int:
	return idx / WIDTH

static func in_bounds(col: int, row: int) -> bool:
	return col >= 0 and col < WIDTH and row >= 0 and row < HEIGHT

## Six neighbours of a cell, in odd-r offset layout.
static func neighbors(idx: int) -> Array[int]:
	var col := col_of(idx)
	var row := row_of(idx)
	var odd := row % 2 == 1
	var deltas: Array = []
	if odd:
		deltas = [[1, 0], [0, -1], [1, -1], [1, 1], [0, 1], [-1, 0]]
	else:
		deltas = [[1, 0], [-1, -1], [0, -1], [0, 1], [-1, 1], [-1, 0]]
	var out: Array[int] = []
	for d in deltas:
		var c: int = col + int(d[0])
		var r: int = row + int(d[1])
		if in_bounds(c, r):
			out.append(index(c, r))
	return out

## Pixel centre of a cell for the 2D map view.
static func to_pixel(idx: int, radius: float) -> Vector2:
	var col := col_of(idx)
	var row := row_of(idx)
	var w := sqrt(3.0) * radius
	var h := 1.5 * radius
	var x := w * (float(col) + (0.5 if row % 2 == 1 else 0.0))
	var y := h * float(row)
	return Vector2(x, y)

static func corners(center: Vector2, radius: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(6):
		var ang := deg_to_rad(60.0 * float(i) - 30.0)
		pts.append(center + Vector2(cos(ang), sin(ang)) * radius)
	return pts

## Grid distance between two cells (cube distance through axial conversion).
static func distance(a: int, b: int) -> int:
	var ac := _to_cube(a)
	var bc := _to_cube(b)
	return int((abs(ac.x - bc.x) + abs(ac.y - bc.y) + abs(ac.z - bc.z)) / 2.0)

static func _to_cube(idx: int) -> Vector3:
	var col := col_of(idx)
	var row := row_of(idx)
	var x := float(col) - float(row - (row & 1)) / 2.0
	var z := float(row)
	return Vector3(x, -x - z, z)
