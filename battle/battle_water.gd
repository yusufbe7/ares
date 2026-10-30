## Qirg'oq biomidagi dengiz: g'arbdagi suv tasmasi (x < coast + 45). Suv ostidagi joy relyefda allaqachon past.
class_name BattleWater
extends MeshInstance3D

const SHADER := "res://battle/battle_water.gdshader"


static func create(map: Node3D, coast: float) -> BattleWater:
	var w := BattleWater.new()
	w.name = "Sea"
	var half: float = map.HALF
	var x1 := coast + 60.0
	var pm := PlaneMesh.new()
	pm.size = Vector2(x1 + half + 400.0, half * 2.0 + 400.0)   # chetidan tashqariga ham (ufq)
	pm.subdivide_width = 220
	pm.subdivide_depth = 260
	w.mesh = pm
	w.position = Vector3((x1 - half - 400.0) * 0.5, 0.0, 0.0)
	w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := ShaderMaterial.new()
	m.shader = load(SHADER)
	var res: int = map.RES
	var img := Image.create_from_data(res, res, false, Image.FORMAT_RF, map.heights.to_byte_array())
	m.set_shader_parameter("ground", ImageTexture.create_from_image(img))
	m.set_shader_parameter("half_size", half)
	m.set_shader_parameter("ocean_tile", 50.0)
	var j: Dictionary = {}
	if FileAccess.file_exists("res://data/ocean.json"):
		j = JSON.parse_string(FileAccess.get_file_as_string("res://data/ocean.json"))
	for t in [["ocean_disp", "res://map/ocean_disp.png"], ["ocean_nrm", "res://map/ocean_normal.png"], ["ocean_col", "res://map/ocean_color.jpg"]]:
		if ResourceLoader.exists(t[1]):
			m.set_shader_parameter(t[0], load(t[1]))
	if not j.is_empty():
		for k in ["frames", "cols", "grid"]:
			m.set_shader_parameter("ocean_" + k, int(j[k]))
		m.set_shader_parameter("ocean_fps", float(j.fps))
		m.set_shader_parameter("disp_min", Vector3(j.disp_min[0], j.disp_min[1], j.disp_min[2]))
		m.set_shader_parameter("disp_max", Vector3(j.disp_max[0], j.disp_max[1], j.disp_max[2]))
	w.material_override = m
	map.add_child(w)
	return w
