class_name AircraftUnit
extends BattleUnit
## Helicopters and drones. They ignore the ground, see much further than anybody
## else, and are the reason an AA vehicle is worth its upkeep.

var _rotor: Node3D
var _spin: float = 0.0
var _orbit: float = 0.0

func _build_visual() -> void:
	var color := battle.team_color(team) if battle != null else Color.GRAY
	var role := str(data.get("role", "gunship"))
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.6, 1.2, 5.0) if role == "gunship" else Vector3(0.8, 0.3, 0.8)
	body.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color.darkened(0.3)
	body.material_override = mat
	add_child(body)

	_rotor = Node3D.new()
	_rotor.position = Vector3(0, 0.9, 0)
	add_child(_rotor)
	var blade_count := 2 if role == "gunship" else 4
	for i in range(blade_count):
		var blade := MeshInstance3D.new()
		var blm := BoxMesh.new()
		blm.size = Vector3(6.0 if role == "gunship" else 1.6, 0.06, 0.25)
		blade.mesh = blm
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(0.15, 0.15, 0.15)
		blade.material_override = bmat
		blade.rotation.y = TAU * float(i) / float(blade_count)
		_rotor.add_child(blade)

func _think(delta: float) -> void:
	_spin += delta * 28.0
	if _rotor != null:
		_rotor.rotation.y = _spin
	var role := str(data.get("role", "gunship"))
	if role == "kamikaze":
		_fpv_run(delta)
		return
	if role == "recon":
		_recon_sweep(delta)
		return
	# Gunship: stand off from the target and circle it.
	if attack_target != null and attack_target.is_alive():
		_orbit += delta * 0.4
		var center := attack_target.global_position
		var want := center + Vector3(cos(_orbit), 0, sin(_orbit)) * (_range * 0.7)
		move_target = want
		path = [want]
		path_index = 0
		has_move_target = true
	_move_step(delta)
	_stick_to_ground()

func _recon_sweep(delta: float) -> void:
	# Drones fly a lane across the enemy half and light it up for everyone.
	if not has_move_target:
		var half: float = battle.terrain.map_size * 0.4
		var side: float = -1.0 if team == 0 else 1.0
		order_move(Vector3(randf_range(-half, half), 0, side * -randf_range(0.1, 0.9) * half))
	_move_step(delta)
	_stick_to_ground()
	battle.reveal_area(global_position, float(data.get("vision", 150)), team, 3.0)

func _fpv_run(delta: float) -> void:
	if attack_target == null or not attack_target.is_alive():
		_acquire_target()
		if attack_target == null:
			_move_step(delta)
			return
	var to := attack_target.global_position - global_position
	var dir := to.normalized()
	global_position += dir * float(data.get("speed", 24.0)) * delta
	look_at_direction(dir)
	if to.length() < 2.5:
		battle.spawn_explosion(global_position, 6.0, float(data.get("damage", 200)), team, true)
		die()

func _move_step(delta: float) -> void:
	super._move_step(delta)
	_stick_to_ground()

func armor_multiplier(_from_dir: Vector3, attacker_at: float) -> float:
	# Only weapons that can track a moving air target hurt much.
	return 1.0 if attacker_at > 0.1 else 0.25

func _on_death_visual() -> void:
	if battle != null and is_instance_valid(battle):
		battle.spawn_explosion(global_position, 5.0, 25.0, team, false)
	queue_free()
