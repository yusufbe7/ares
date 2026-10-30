## Speech bubble over a unit ("MORE DIRT...", "SPADE WORK"), readable at RTS distance.
##   RtsBubble.say(node, "MORE DIRT...", 2.5)
class_name RtsBubble
extends Node3D

static var _tex: Texture2D


static func _bubble_texture() -> Texture2D:
	if _tex:
		return _tex
	var w := 256; var h := 80
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := 26.0
	var body_h := 62
	for y in h:
		for x in w:
			var inside := false
			var edge := false
			if y < body_h:
				var cx := clampf(x, r, w - 1 - r)
				var cy := clampf(y, r, body_h - 1 - r)
				var d := Vector2(x - cx, y - cy).length()
				inside = d <= r
				edge = d > r - 3.0
			else:
				# little tail under the bubble
				var t := float(y - body_h) / (h - body_h)
				var half := 14.0 * (1.0 - t)
				inside = absf(x - w * 0.5) <= half
				edge = absf(x - w * 0.5) > half - 3.0
			if inside:
				img.set_pixel(x, y, Color(0.12, 0.13, 0.14, 0.95) if edge else Color(0.93, 0.93, 0.9, 0.96))
	_tex = ImageTexture.create_from_image(img)
	return _tex


static func say(target: Node3D, text: String, secs := 2.6, height := 2.3) -> RtsBubble:
	if target == null or not target.is_inside_tree():
		return null
	for c in target.get_children():
		if c is RtsBubble:
			c.queue_free()
	var b := RtsBubble.new()
	target.add_child(b)
	b.position = Vector3(0, height, 0)
	var spr := Sprite3D.new()
	spr.texture = _bubble_texture()
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.fixed_size = true
	spr.no_depth_test = true
	spr.shaded = false
	spr.pixel_size = 0.00042
	spr.render_priority = 10
	spr.centered = true
	spr.offset = Vector2(0, 40)
	var chars := maxf(6.0, text.length())
	spr.scale = Vector3(chars / 13.0, 1.0, 1.0)
	b.add_child(spr)
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.fixed_size = true
	l.no_depth_test = true
	l.pixel_size = 0.00042
	l.font_size = 30
	l.outline_size = 0
	l.modulate = Color(0.1, 0.1, 0.1)
	l.render_priority = 11
	l.offset = Vector2(0, 48)
	l.uppercase = true
	b.add_child(l)
	var tm := Timer.new()
	tm.wait_time = secs
	tm.one_shot = true
	tm.autostart = true
	tm.timeout.connect(b.queue_free)
	b.add_child(tm)
	return b
