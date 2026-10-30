## Sichqoncha ostidagi yer nuqtasi: kamera nuri bo'ylab qadamlab yurib, relyef ostiga tushgan joyni topamiz.
class_name MapPicker
extends RefCounted


static func pick(map: CampaignMap, screen: Vector2) -> Variant:
	var cam := map.cam.camera
	var o := cam.project_ray_origin(screen)
	var d := cam.project_ray_normal(screen)
	if d.y >= 0.0:
		return null
	var t := maxf(0.0, (o.y - 4.0) / -d.y)                 # eng baland tog'dan biroz yuqoridan boshlaymiz
	var prev := o + d * t
	for k in 1500:
		t += 0.08 + t * 0.002
		var p := o + d * t
		var g := maxf(map.terrain.ground_y(p.x, p.z), 0.0)
		if p.y <= g:
			var a := prev
			var b := p
			for _i in 6:                                     # oxirgi qadamni ikkiga bo'lib aniqlashtiramiz
				var m := (a + b) * 0.5
				if m.y <= maxf(map.terrain.ground_y(m.x, m.z), 0.0): b = m
				else: a = m
			return b
		prev = p
		if p.y < -3.0:
			break
	return null
