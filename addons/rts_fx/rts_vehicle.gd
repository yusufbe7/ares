## Wheeled vehicle (Humvee, trucks). Put the .glb as a CHILD of a Node3D with this script.
##   move_to(world_pos) - turns like a car (needs speed to steer), spins wheels, kicks up dust
class_name RtsVehicle
extends Node3D

@export var model_forward := Vector3(1, 0, 0)   # Humvee nose points +X
@export var wheel_name_filter := ["wheel", "tire"]
@export var wheel_radius := 0.45
@export var max_speed := 13.0
@export var acceleration := 5.0
@export var turn_speed := 55.0                    # deg/s at full speed

var _target: Variant = null
var _speed := 0.0
var _wheels: Array[Node3D] = []
var _wheel_base: Array[Transform3D] = []
var _wheel_pivot: Array[Vector3] = []
var _axle := Vector3.RIGHT
var _wheel_angle := 0.0
var _dust: GPUParticles3D

func _ready() -> void:
	add_to_group("vehicles")
	var model := get_child(0)
	for n in model.find_children("*", "Node3D", true, false):
		var lname := String(n.name).to_lower()
		if n is MeshInstance3D:
			continue
		for f in wheel_name_filter:
			if lname.begins_with(f) and not lname.contains("spare"):
				_wheels.append(n)
				_wheel_base.append(n.transform)
				_wheel_pivot.append(_mesh_center_in_parent(n))
				break
	_axle = model_forward.cross(Vector3.UP).normalized()
	_dust = RtsTank._make_dust_static()
	add_child(_dust)
	_dust.position = -model_forward.normalized() * 2.6 + Vector3.UP * 0.2

func forward() -> Vector3:
	var f := global_basis * model_forward
	f.y = 0
	return f.normalized()

var _path := PackedVector3Array()

func move_to(p: Vector3) -> void:
	_path = RtsNav.find_path(global_position, p, true)
	_target = _path[0]
	_path.remove_at(0)

func _physics_process(delta: float) -> void:
	var want := 0.0
	if _target != null:
		var to: Vector3 = _target - global_position
		to.y = 0
		var dist := to.length()
		if not _path.is_empty() and dist < 5.0:
			_target = _path[0]
			_path.remove_at(0)
		elif dist < 2.0:
			_target = null
		else:
			var ang := forward().signed_angle_to(to.normalized(), Vector3.UP)
			want = max_speed * clampf(dist / 15.0, 0.3, 1.0) * (0.45 if abs(ang) > 1.0 else 1.0)
			var steer := deg_to_rad(turn_speed) * delta * clampf(abs(_speed) / 4.0, 0.15, 1.0)
			rotate_y(clampf(ang, -steer, steer))
	_speed = move_toward(_speed, want, acceleration * delta)
	var p := global_position + forward() * _speed * delta
	p.y = RtsGround.height(p.x, p.z)
	global_position = p
	_wheel_angle += _speed * delta / wheel_radius
	for i in _wheels.size():
		var w := _wheels[i]
		# rotate around the wheel's own axle, expressed in the wheel's parent space
		var parent_basis := (w.get_parent() as Node3D).global_basis.orthonormalized() if w.get_parent() is Node3D else Basis.IDENTITY
		var axle_local := (parent_basis.inverse() * (global_basis.orthonormalized() * _axle)).normalized()
		var pv := _wheel_pivot[i]
		w.transform = Transform3D(Basis(axle_local, _wheel_angle), pv) * Transform3D(Basis.IDENTITY, -pv) * _wheel_base[i]
	_dust.emitting = _speed > 3.0

## Center of all meshes under n, in n's parent space (wheels often have their origin elsewhere).
static func _mesh_center_in_parent(n: Node3D) -> Vector3:
	var acc := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := n.transform * _rel(n, mi)
		var a: AABB = xf * mi.mesh.get_aabb()
		acc = a if first else acc.merge(a)
		first = false
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var a2: AABB = n.transform * (n as MeshInstance3D).mesh.get_aabb()
		acc = a2 if first else acc.merge(a2)
		first = false
	return acc.get_center() if not first else n.position

static func _rel(root: Node3D, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c: Node = n
	while c != root and c != null:
		t = (c as Node3D).transform * t
		c = c.get_parent()
	return t
