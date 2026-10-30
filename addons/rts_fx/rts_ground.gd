## Ground height lookup shared by all units.
## A map sets RtsGround.height_func = func(x, z): return <height>
## Units call RtsGround.height(x, z) so they follow hills, river banks and bridges.
class_name RtsGround
extends RefCounted

## Render layer bit of the terrain; decals (scorch, blood, footprints, build zones) only paint this layer
const DECAL_LAYER := 1 << 9

static var height_func: Callable = func(_x: float, _z: float) -> float: return 0.0

static func height(x: float, z: float) -> float:
	return height_func.call(x, z)
