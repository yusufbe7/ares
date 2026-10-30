## Sozlamalar: user://settings.cfg (ConfigFile). O'yin boshida yuklanadi va qo'llanadi.
## Bo'limlar: graphics, audio, controls, gameplay, game (til), interface.
class_name Settings
extends RefCounted

const PATH := "user://settings.cfg"
const DEFAULTS := {
	"graphics": {"fullscreen": false, "vsync": true, "resolution": "1600x900", "quality": 2, "shadows": true, "msaa": 2},
	"audio": {"Master": 0.9, "Music": 0.7, "SFX": 0.9, "UI": 0.8, "Voice": 0.9},
	"controls": {},
	"gameplay": {"camera_speed": 1.0, "auto_pause": false, "order_hints": true},
	"game": {"language": "en"},
	"interface": {"ui_scale": 1.0, "panel_opacity": 0.85, "show_fps": false},
}
static var camera_speed := 1.0       ## kamera surish tezligi (RtsCamera, CampaignCamera)
static var show_fps := false
const RESOLUTIONS := ["1280x720", "1600x900", "1920x1080", "2560x1080", "2560x1440", "3440x1440", "3840x2160"]


static func load_all() -> Dictionary:
	var out := {}
	var cfg := ConfigFile.new()
	var ok := cfg.load(PATH) == OK
	for sec in DEFAULTS:
		out[sec] = {}
		for k in DEFAULTS[sec]:
			out[sec][k] = cfg.get_value(sec, k, DEFAULTS[sec][k]) if ok else DEFAULTS[sec][k]
		if ok and cfg.has_section(sec):
			for k in cfg.get_section_keys(sec):
				out[sec][k] = cfg.get_value(sec, k)
	return out


static func save_all(s: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	for sec in s:
		for k in s[sec]:
			cfg.set_value(sec, k, s[sec][k])
	cfg.save(PATH)


static func defaults() -> Dictionary:
	return DEFAULTS.duplicate(true)


## Sozlamalarni qo'llaydi. Headless rejimda oyna sozlamalari o'tkazib yuboriladi.
static func apply(s: Dictionary, root: Window) -> void:
	var g: Dictionary = s.get("graphics", {})
	if DisplayServer.get_name() != "headless" and root:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if g.get("vsync", true) else DisplayServer.VSYNC_DISABLED)
		if g.get("fullscreen", false):
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var r: PackedStringArray = str(g.get("resolution", "1600x900")).split("x")
			if r.size() == 2:
				var want := Vector2i(int(r[0]), int(r[1]))
				var scr := DisplayServer.screen_get_size()
				DisplayServer.window_set_size(Vector2i(mini(want.x, scr.x), mini(want.y, scr.y)))
	if root:
		root.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X][clampi(int(g.get("msaa", 2)) / 2, 0, 3)]
		root.positional_shadow_atlas_size = 4096 if g.get("shadows", true) else 0
		var ui: Dictionary = s.get("interface", {})
		root.content_scale_factor = clampf(float(ui.get("ui_scale", 1.0)), 0.75, 1.5)
	RenderingServer.directional_shadow_atlas_set_size(8192 if int(g.get("quality", 2)) >= 2 else 2048, true)
	var a: Dictionary = s.get("audio", {})
	for bus in ["Master", "Music", "SFX", "UI", "Voice"]:
		var i := AudioServer.get_bus_index(bus)
		if i >= 0:
			AudioServer.set_bus_volume_db(i, linear_to_db(maxf(float(a.get(bus, 1.0)), 0.0001)))
	camera_speed = clampf(float(s.get("gameplay", {}).get("camera_speed", 1.0)), 0.3, 3.0)
	show_fps = bool(s.get("interface", {}).get("show_fps", false))
	Keys.load_from(s.get("controls", {}))
	_panel_opacity(clampf(float(s.get("interface", {}).get("panel_opacity", 0.85)), 0.4, 1.0))
	var lang := str(s.get("game", {}).get("language", Loc.DEFAULT))
	if lang != Loc.lang:
		Loc.set_lang(lang, false)


## Panellar shaffofligi: Theme dagi panel fonlarining alfa qiymati (bitta Theme, hamma ekranga ta'sir qiladi).
static func _panel_opacity(a: float) -> void:
	var th := UiKit.theme()
	if th == null:
		return
	for t in th.get_type_list():
		for n in th.get_stylebox_list(t):
			var sb := th.get_stylebox(n, t) as StyleBoxFlat
			if sb == null:
				continue
			if not sb.has_meta("base_a"):
				sb.set_meta("base_a", sb.bg_color.a)
			var base: float = sb.get_meta("base_a")
			if base >= 0.6 and base < 0.99:       # faqat yarim shaffof panellar (tugmalar emas)
				sb.bg_color.a = a * base / 0.85
