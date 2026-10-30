## O'yin nomi / logotip (data/game.json). res://ui/logo.png bo'lsa rasm chiqadi.
class_name GameLogo
extends VBoxContainer


static func make(subtitle_key := "subtitle", big := 54) -> GameLogo:
	var g := GameLogo.new()
	var j: Dictionary = CampaignData._json("res://data/game.json", {})
	g.add_theme_constant_override("separation", -6)
	var path := str(j.get("logo", ""))
	if path != "" and ResourceLoader.exists(path):
		var tr := TextureRect.new()
		tr.texture = load(path)
		tr.custom_minimum_size = Vector2(360, 110)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		g.add_child(tr)
		return g
	var t := UiKit.label(str(j.get("title", "EUROPE FRONT")), "TitleLabel")
	t.add_theme_font_size_override("font_size", big)
	t.add_theme_color_override("font_color", Color(0.86, 0.86, 0.84))
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	t.add_theme_constant_override("outline_size", 6)
	g.add_child(t)
	var s := UiKit.label(_spaced(str(j.get(subtitle_key, ""))), "AmberLabel")
	s.add_theme_font_size_override("font_size", int(big * 0.4))
	g.add_child(s)
	return g


static func _spaced(t: String) -> String:
	var out := ""
	for ch in t:
		out += ch + " "
	return out.strip_edges()
