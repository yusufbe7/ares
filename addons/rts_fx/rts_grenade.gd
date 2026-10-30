## Hand grenade: flies in an arc, bounces once, explodes after the fuse.
## RtsGrenade.throw(parent, from, to)
class_name RtsGrenade
extends Node3D

var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _t := 0.0
var _dur := 1.0
var _fuse := 1.1
var _landed := false


static func throw(parent: Node, from: Vector3, to: Vector3) -> RtsGrenade:
	var g := RtsGrenade.new()
	parent.add_child(g)
	g._from = from
	g._to = Vector3(to.x, RtsGround.height(to.x, to.z) + 0.08, to.z)
	g._dur = clampf(from.distance_to(to) / 16.0, 0.5, 1.8)
	g.global_position = from
	return g


func _ready() -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.06
	s.height = 0.13
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.18, 0.22, 0.12)
	m.roughness = 0.6
	s.material = m
	mi.mesh = s
	add_child(mi)


func _physics_process(delta: float) -> void:
	if not _landed:
		_t = minf(1.0, _t + delta / _dur)
		var p := _from.lerp(_to, _t)
		p.y += 4.0 * _t * (1.0 - _t) * maxf(2.5, _from.distance_to(_to) * 0.25)
		global_position = p
		rotate_x(delta * 12.0)
		if _t >= 1.0:
			_landed = true
			# people nearby dive for cover
			for u in get_tree().get_nodes_in_group("units"):
				if u is RtsSoldier and (u as Node3D).global_position.distance_to(_to) < 8.0:
					(u as RtsSoldier).suppress(1.2)
	else:
		_fuse -= delta
		if _fuse <= 0.0:
			RtsExplosion.spawn(get_parent(), global_position, 0.5)
			queue_free()
