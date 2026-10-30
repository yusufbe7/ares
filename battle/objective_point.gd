class_name ObjectivePoint
extends RefCounted
## A capture point. Holding more of them than the enemy bleeds their reserve —
## that is the clock the whole battle runs on.

var id: String = "A"
var display_name: String = "Point"
var position: Vector3 = Vector3.ZERO
var radius: float = 26.0
var owner_team: int = -1          # -1 neutral
var progress: float = 0.0         # -1..1, sign is the team pulling it
var contested: bool = false
var marker: Node3D = null

func update(delta: float, units: Array) -> bool:
	var count := [0, 0]
	for u in units:
		if not u.is_alive() or u.is_air():
			continue
		if u.global_position.distance_to(position) <= radius:
			count[u.team] += u.men_count()
	contested = count[0] > 0 and count[1] > 0
	if contested or (count[0] == 0 and count[1] == 0):
		return false
	var pulling: int = 0 if count[0] > 0 else 1
	var strength: float = float(count[pulling])
	var rate: float = clampf(0.04 + strength * 0.012, 0.0, 0.2) * delta * 10.0
	var dir: float = -1.0 if pulling == 0 else 1.0
	progress = clampf(progress + dir * rate, -1.0, 1.0)
	var new_owner := owner_team
	if progress <= -1.0:
		new_owner = 0
	elif progress >= 1.0:
		new_owner = 1
	if new_owner != owner_team:
		owner_team = new_owner
		return true
	return false

func color_for_owner(team_colors: Array) -> Color:
	if owner_team < 0:
		return Color(0.8, 0.8, 0.8)
	return team_colors[owner_team]
