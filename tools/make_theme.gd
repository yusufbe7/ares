## Bitta umumiy Theme yasaydi: res://ui/theme/main_theme.tres
## Ishga tushirish: godot --headless --path . -s res://tools/make_theme.gd
## Uslub: to'q grafit yarim shaffof panellar (#14161A, 85%), ingichka chegara, amber urg'u (#E8A33A),
## sarlavhalar Oswald, tugmalar Barlow Condensed, matn Barlow (kirill uchun zaxira: Oswald).
extends SceneTree

const AMBER := Color("#E8A33A")
const BG := Color(0.078, 0.086, 0.102, 0.85)
const LINE := Color(0.24, 0.25, 0.27, 0.9)
const TEXT := Color(0.9, 0.9, 0.88)
const DIM := Color(0.58, 0.6, 0.62)
const F := "res://ui/theme/fonts/"


func sb(bg: Color, border := Color(0, 0, 0, 0), w := 0, r := 2, m := Vector4(10, 6, 10, 6)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(w)
	s.set_corner_radius_all(r)
	s.content_margin_left = m.x; s.content_margin_top = m.y; s.content_margin_right = m.z; s.content_margin_bottom = m.w
	s.anti_aliasing = true
	return s


func font(file: String, fallback: Font = null) -> Font:
	var f := FontVariation.new()             # import qilingan shriftga havola + kirill uchun zaxira
	f.base_font = load(F + file)
	if fallback:
		f.fallbacks = [fallback]
	return f


func check_icon(on: bool, radio := false) -> ImageTexture:
	var n := 18
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var edge := x < 2 or y < 2 or x >= n - 2 or y >= n - 2
			var c := Color(0, 0, 0, 0)
			if radio:
				var d := Vector2(x - n * 0.5 + 0.5, y - n * 0.5 + 0.5).length()
				if d < n * 0.5 - 0.5: c = Color(0.1, 0.11, 0.12)
				if d >= n * 0.5 - 2.5 and d < n * 0.5 - 0.5: c = AMBER if on else LINE
				if on and d < n * 0.5 - 5: c = AMBER
			else:
				c = (AMBER if on else Color(0.36, 0.37, 0.4)) if edge else (Color(0.1, 0.11, 0.12))
				if on and not edge:
					c = AMBER.darkened(0.15)
					# belgi (galochka)
					var u := float(x) / n; var v := float(y) / n
					if absf(v - (0.55 + (u - 0.42) * 0.9)) < 0.07 and u < 0.45 and u > 0.2: c = Color(0.08, 0.08, 0.08)
					if absf(v - (0.72 - (u - 0.42) * 1.1)) < 0.07 and u >= 0.4 and u < 0.8: c = Color(0.08, 0.08, 0.08)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _initialize() -> void:
	var oswald := font("Oswald.ttf")
	var body := font("Barlow-Regular.ttf", oswald)
	var body_b := font("Barlow-SemiBold.ttf", oswald)
	var cond := font("BarlowCondensed-SemiBold.ttf", oswald)
	var t := Theme.new()
	t.default_font = body
	t.default_font_size = 15
	# --- panellar
	t.set_stylebox("panel", "PanelContainer", sb(BG, LINE, 1, 2, Vector4(12, 10, 12, 10)))
	t.set_stylebox("panel", "Panel", sb(BG, LINE, 1))
	t.set_type_variation("CardPanel", "PanelContainer")
	t.set_stylebox("panel", "CardPanel", sb(Color(0.1, 0.11, 0.125, 0.92), LINE, 1, 2, Vector4(8, 8, 8, 8)))
	t.set_type_variation("SelectedCard", "PanelContainer")
	t.set_stylebox("panel", "SelectedCard", sb(Color(0.16, 0.13, 0.08, 0.95), AMBER, 2, 2, Vector4(8, 8, 8, 8)))
	t.set_type_variation("DarkPanel", "PanelContainer")
	t.set_stylebox("panel", "DarkPanel", sb(Color(0.03, 0.035, 0.04, 0.92), Color(0, 0, 0, 0), 0, 0, Vector4(0, 0, 0, 0)))
	# --- matn
	t.set_color("font_color", "Label", TEXT)
	for v in [["TitleLabel", oswald, 44, TEXT], ["HeaderLabel", oswald, 20, TEXT], ["PanelTitle", cond, 17, TEXT],
			["AmberLabel", cond, 16, AMBER], ["SmallLabel", body, 13, DIM], ["StatLabel", cond, 14, DIM], ["BigNumber", oswald, 22, TEXT]]:
		t.set_type_variation(v[0], "Label")
		t.set_font("font", v[0], v[1])
		t.set_font_size("font_size", v[0], v[2])
		t.set_color("font_color", v[0], v[3])
	t.set_font("normal_font", "RichTextLabel", body)
	t.set_font("bold_font", "RichTextLabel", body_b)
	t.set_color("default_color", "RichTextLabel", TEXT)
	# --- tugmalar
	t.set_font("font", "Button", cond)
	t.set_font_size("font_size", "Button", 16)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", AMBER)
	t.set_color("font_disabled_color", "Button", Color(0.45, 0.46, 0.48))
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_stylebox("normal", "Button", sb(Color(0.1, 0.11, 0.125, 0.9), LINE, 1))
	t.set_stylebox("hover", "Button", sb(Color(0.17, 0.16, 0.13, 0.95), AMBER.darkened(0.25), 1))
	t.set_stylebox("pressed", "Button", sb(Color(0.24, 0.18, 0.08, 0.95), AMBER, 1))
	t.set_stylebox("disabled", "Button", sb(Color(0.08, 0.085, 0.09, 0.7), Color(0.18, 0.18, 0.2), 1))
	t.set_stylebox("focus", "Button", sb(Color(0, 0, 0, 0), AMBER, 1))
	# chap menyu tugmasi va tanlangani
	t.set_type_variation("NavButton", "Button")
	t.set_font_size("font_size", "NavButton", 19)
	t.set_stylebox("normal", "NavButton", sb(Color(0.07, 0.075, 0.085, 0.86), LINE, 1, 2, Vector4(14, 10, 14, 10)))
	t.set_stylebox("hover", "NavButton", sb(Color(0.15, 0.13, 0.09, 0.95), AMBER.darkened(0.2), 1, 2, Vector4(14, 10, 14, 10)))
	t.set_stylebox("pressed", "NavButton", sb(Color(0.3, 0.2, 0.06, 0.95), AMBER, 2, 2, Vector4(14, 10, 14, 10)))
	t.set_type_variation("NavButtonActive", "NavButton")
	for st in ["normal", "hover", "pressed"]:
		t.set_stylebox(st, "NavButtonActive", sb(Color(0.33, 0.22, 0.07, 0.95), AMBER, 2, 2, Vector4(14, 10, 14, 10)))
	# katta amber tugma (DEPLOY, START MISSION)
	t.set_type_variation("AmberButton", "Button")
	t.set_font("font", "AmberButton", oswald)
	t.set_font_size("font_size", "AmberButton", 22)
	t.set_color("font_color", "AmberButton", AMBER.lightened(0.15))
	t.set_color("font_hover_color", "AmberButton", Color.WHITE)
	t.set_stylebox("normal", "AmberButton", sb(Color(0.2, 0.14, 0.05, 0.95), AMBER, 2, 2, Vector4(18, 10, 18, 10)))
	t.set_stylebox("hover", "AmberButton", sb(Color(0.36, 0.24, 0.07, 0.98), AMBER.lightened(0.2), 2, 2, Vector4(18, 10, 18, 10)))
	t.set_stylebox("pressed", "AmberButton", sb(AMBER.darkened(0.2), AMBER.lightened(0.3), 2, 2, Vector4(18, 10, 18, 10)))
	# tab tugmasi
	t.set_type_variation("TabButton", "Button")
	t.set_font_size("font_size", "TabButton", 15)
	t.set_stylebox("normal", "TabButton", sb(Color(0.08, 0.085, 0.095, 0.88), LINE, 1, 0, Vector4(18, 8, 18, 8)))
	t.set_stylebox("hover", "TabButton", sb(Color(0.15, 0.13, 0.09, 0.95), AMBER.darkened(0.3), 1, 0, Vector4(18, 8, 18, 8)))
	t.set_stylebox("pressed", "TabButton", sb(Color(0.3, 0.2, 0.06, 0.95), AMBER, 1, 0, Vector4(18, 8, 18, 8)))
	t.set_type_variation("TabButtonActive", "TabButton")
	for st in ["normal", "hover", "pressed"]:
		t.set_stylebox(st, "TabButtonActive", sb(Color(0.36, 0.25, 0.08, 0.96), AMBER, 1, 0, Vector4(18, 8, 18, 8)))
	t.set_color("font_color", "TabButtonActive", Color.WHITE)
	# kichik ikonka tugmasi
	t.set_type_variation("IconButton", "Button")
	t.set_stylebox("normal", "IconButton", sb(Color(0.1, 0.11, 0.125, 0.9), LINE, 1, 2, Vector4(8, 6, 8, 6)))
	# --- katakchalar, slayderlar, progress
	for ty in ["CheckBox", "CheckButton"]:
		t.set_icon("checked", ty, check_icon(true))
		t.set_icon("unchecked", ty, check_icon(false))
		t.set_icon("radio_checked", ty, check_icon(true, true))
		t.set_icon("radio_unchecked", ty, check_icon(false, true))
		t.set_font("font", ty, body)
		t.set_font_size("font_size", ty, 14)
		for st in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			t.set_stylebox(st, ty, sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, Vector4(2, 2, 2, 2)))
		t.set_color("font_color", ty, TEXT)
		t.set_color("font_hover_color", ty, Color.WHITE)
		t.set_color("font_pressed_color", ty, TEXT)
		t.set_color("font_hover_pressed_color", ty, Color.WHITE)
	t.set_stylebox("background", "ProgressBar", sb(Color(0.05, 0.05, 0.06, 0.9), LINE, 1, 1, Vector4(0, 0, 0, 0)))
	t.set_stylebox("fill", "ProgressBar", sb(AMBER, Color(0, 0, 0, 0), 0, 1, Vector4(0, 0, 0, 0)))
	t.set_stylebox("slider", "HSlider", sb(Color(0.2, 0.21, 0.23), Color(0, 0, 0, 0), 0, 2, Vector4(0, 3, 0, 3)))
	t.set_stylebox("grabber_area", "HSlider", sb(AMBER, Color(0, 0, 0, 0), 0, 2, Vector4(0, 3, 0, 3)))
	t.set_stylebox("grabber_area_highlight", "HSlider", sb(AMBER.lightened(0.2), Color(0, 0, 0, 0), 0, 2, Vector4(0, 3, 0, 3)))
	for ty in ["LineEdit", "OptionButton", "SpinBox"]:
		t.set_stylebox("normal", ty, sb(Color(0.06, 0.065, 0.075, 0.95), LINE, 1))
		t.set_stylebox("focus", ty, sb(Color(0, 0, 0, 0), AMBER, 1))
	t.set_stylebox("hover", "OptionButton", sb(Color(0.15, 0.13, 0.09, 0.95), AMBER.darkened(0.25), 1))
	t.set_stylebox("pressed", "OptionButton", sb(Color(0.15, 0.13, 0.09, 0.95), AMBER, 1))
	t.set_stylebox("panel", "PopupMenu", sb(Color(0.08, 0.085, 0.095, 0.98), LINE, 1, 2, Vector4(4, 4, 4, 4)))
	t.set_stylebox("hover", "PopupMenu", sb(Color(0.3, 0.2, 0.06, 0.95)))
	t.set_stylebox("panel", "TooltipPanel", sb(Color(0.05, 0.055, 0.06, 0.96), AMBER.darkened(0.3), 1, 2, Vector4(8, 5, 8, 5)))
	t.set_stylebox("scroll", "VScrollBar", sb(Color(0, 0, 0, 0.25), Color(0, 0, 0, 0), 0, 2, Vector4(3, 0, 3, 0)))
	t.set_stylebox("grabber", "VScrollBar", sb(Color(0.35, 0.36, 0.38), Color(0, 0, 0, 0), 0, 2, Vector4(3, 0, 3, 0)))
	t.set_stylebox("scroll", "HScrollBar", sb(Color(0, 0, 0, 0.25), Color(0, 0, 0, 0), 0, 2, Vector4(0, 3, 0, 3)))
	t.set_stylebox("grabber", "HScrollBar", sb(Color(0.35, 0.36, 0.38), Color(0, 0, 0, 0), 0, 2, Vector4(0, 3, 0, 3)))
	t.set_stylebox("separator", "HSeparator", sb(LINE, Color(0, 0, 0, 0), 0, 0, Vector4(0, 1, 0, 0)))
	var err := ResourceSaver.save(t, "res://ui/theme/main_theme.tres")
	print("theme saved: ", err)
	quit()
