class_name VehicleUnit
extends BattleUnit
## Tanks, APCs, self-propelled guns and AA. The thing that makes them read as
## armour rather than big infantry is the facing: front plate thick, sides
## thinner, rear thin enough that a flanking AT team is a real answer to them.

var turret: Node3D
var _turret_angle: float = 0.0
var _hull: MeshInstance3D
var _passengers: Array = []
var _barrel_len: float = 3.4
var _crush_timer: float = 0.0

func ground_offset() -> float:
	return 1.0

func _build_visual() -> void:
	var color := battle.team_color(team) if battle != null else Color.GRAY
	var role := str(data.get("role", "armor"))
	_hull = MeshInstance3D.new()
	var hull_mesh := BoxMesh.new()
	match role:
		"transport": hull_mesh.size = Vector3(2.8, 1.5, 6.0)
		"artillery": hull_mesh.size = Vector3(3.0, 1.6, 6.6)
		"anti_air": hull_mesh.size = Vector3(2.8, 1.5, 5.6)
		_: hull_mesh.size = Vector3(3.4, 1.5, 7.0)
	_hull.mesh = hull_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color.darkened(0.35)
	mat.roughness = 0.85
	_hull.material_override = mat
	_hull.position = Vector3(0, 0.8, 0)
	add_child(_hull)

	turret = Node3D.new()
	turret.position = Vector3(0, 1.6, -0.3)
	add_child(turret)

	var t_mesh := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(2.2, 0.9, 2.8) if role != "transport" else Vector3(1.4, 0.6, 1.6)
	t_mesh.mesh = tb
	t_mesh.material_override = mat
	turret.add_child(t_mesh)

	var barrel := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.13
	bm.bottom_radius = 0.15
	_barrel_len = 4.6 if role == "artillery" else 3.4
	bm.height = _barrel_len
	barrel.mesh = bm
	barrel.material_override = mat
	barrel.rotation.x = PI * 0.5
	barrel.position = Vector3(0, 0.1, -_barrel_len * 0.5 - 1.0)
	turret.add_child(barrel)

	var tracks := MeshInstance3D.new()
	var trb := BoxMesh.new()
	trb.size = Vector3(hull_mesh.size.x + 0.5, 0.55, hull_mesh.size.z)
	tracks.mesh = trb
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.12, 0.12, 0.12)
	tracks.material_override = tmat
	tracks.position = Vector3(0, 0.3, 0)
	add_child(tracks)

func _think(delta: float) -> void:
	# Keep the standoff: armour fights at its own range, not in the street.
	if attack_target != null and attack_target.is_alive() and not has_move_target:
		var d := global_position.distance_to(attack_target.global_position)
		if d < _range * 0.45 and not hold_position:
			var away := (global_position - attack_target.global_position).normalized()
			order_move(battle.terrain.clamp_to_map(global_position + away * 18.0))
	_move_step(delta)
	_aim_turret(delta)
	_crush_timer -= delta
	if _crush_timer <= 0.0:
		_crush_timer = 0.4
		_crush_things()

func _aim_turret(delta: float) -> void:
	if turret == null:
		return
	var want := _turret_angle
	if attack_target != null and attack_target.is_alive():
		var to := attack_target.global_position - global_position
		want = atan2(to.x, to.z) - rotation.y
	_turret_angle = lerp_angle(_turret_angle, want, clampf(delta * 1.6, 0.0, 1.0))
	turret.rotation.y = _turret_angle

## Tanks flatten what they drive through — and a felled tree becomes cover.
func _crush_things() -> void:
	if unit_class() != "vehicle" or str(data.get("role", "")) == "artillery":
		return
	battle.crush_at(global_position, 3.2, self)

func armor_multiplier(from_dir: Vector3, attacker_at: float) -> float:
	var sides: Dictionary = data.get("armor_sides", {})
	var base_armor := float(data.get("armor", 0))
	var plate := base_armor
	if not sides.is_empty():
		var forward := Vector3(sin(rotation.y), 0, cos(rotation.y))
		var dot: float = forward.dot(-from_dir.normalized())
		if dot > 0.55:
			plate = float(sides.get("front", base_armor))
		elif dot < -0.55:
			plate = float(sides.get("rear", base_armor))
		else:
			plate = float(sides.get("side", base_armor))
	# Small arms do almost nothing to armour; AT weapons cut through it.
	var penetration: float = clampf(attacker_at, 0.0, 1.0)
	var stopped: float = plate * (1.0 - penetration)
	return clampf(1.0 / (1.0 + stopped), 0.03, 1.0)

func fire_at(target: BattleUnit, distance: float) -> void:
	var role := str(data.get("role", "armor"))
	if role == "artillery":
		battle.call_artillery_strike(global_position, target.global_position, team, self)
		return
	if role == "armor":
		battle.spawn_shell(muzzle_position(), target.global_position, team,
			float(data.get("damage", 100)), float(data.get("at", 1.0)))
		return
	super.fire_at(target, distance)

func muzzle_position() -> Vector3:
	if turret == null:
		return global_position + Vector3(0, 1.8, 0)
	var dir := Vector3(sin(rotation.y + _turret_angle), 0, cos(rotation.y + _turret_angle))
	return global_position + Vector3(0, 1.8, 0) + dir * (_barrel_len * 0.5 + 1.2)

## APCs carry infantry: they get there alive, then get out.
func load_passenger(u: BattleUnit) -> bool:
	if _passengers.size() >= int(data.get("capacity", 0)):
		return false
	_passengers.append(u)
	u.visible = false
	return true

func unload() -> void:
	for u in _passengers:
		if is_instance_valid(u) and u.is_alive():
			u.visible = true
			u.global_position = global_position + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
	_passengers.clear()

func _on_death_visual() -> void:
	unload()
	var wreck := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.4, 1.4, 7.0)
	wreck.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.09, 0.08)
	wreck.material_override = mat
	wreck.position = global_position + Vector3(0, 0.7, 0)
	wreck.rotation.y = rotation.y
	if battle != null and is_instance_valid(battle):
		battle.add_child(wreck)
		battle.cover.add_wreck(global_position)
		battle.spawn_explosion(global_position, 6.0, 40.0, team, false)
	queue_free()
