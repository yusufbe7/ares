## Ekranlar boshqaruvi: bosh menyu ichidagi ekranlar (stack, Esc bilan orqaga) va katta sahnalarga o'tish
## (dunyo xaritasi, jang) yuklash ekrani bilan.
extends Node

const MAIN := "res://ui/main.tscn"
const CAMPAIGN := "res://campaign/campaign_map.tscn"
const BATTLE := "res://demo/demo.tscn"
const SCREENS := {"main": "res://ui/screens/main_menu.tscn", "campaign": "res://ui/screens/campaign_hub.tscn",
	"operations": "res://ui/screens/operations.tscn", "armory": "res://ui/screens/armory.tscn",
	"garage": "res://ui/screens/garage.tscn", "customization": "res://ui/screens/customization.tscn",
	"settings": "res://ui/screens/settings.tscn", "vehicles": "res://ui/screens/vehicle_list.tscn",
	"country": "res://ui/screens/country_select.tscn"}

signal screen_changed(id: String)

var stack: Array[String] = []
var _pending := ""
var _loading: CanvasLayer
var _bar: ProgressBar
var _load_path := ""


## Bosh menyu ichidagi ekranni ochadi (kerak bo'lsa avval main.tscn ga qaytadi).
func open(id: String, push := true) -> void:
	if not SCREENS.has(id):
		EventBus.toast.emit(Loc.t("coming_soon"))
		return
	var root := _main_root()
	if root == null:
		_pending = id
		goto_scene(MAIN)
		return
	if push and (stack.is_empty() or stack.back() != id):
		if id == "main":
			stack.clear()
		stack.append(id)
	root.show_screen(id, SCREENS[id])
	screen_changed.emit(id)


func back() -> void:
	if stack.size() > 1:
		stack.pop_back()
		open(stack.back(), false)
	elif _main_root():
		ExitDialog.ask(get_tree().current_scene)


func current() -> String:
	return stack.back() if not stack.is_empty() else ""


func _main_root() -> Node:
	var s := get_tree().current_scene
	return s if s and s.has_method("show_screen") else null


## Main sahna tayyor bo'lganda kutilayotgan ekranni ochadi.
func main_ready() -> void:
	var id := _pending if _pending != "" else "main"
	_pending = ""
	stack.clear()
	# o'yin ochilganda avval davlat tanlash ekrani (bir marta), START dan keyin bosh menyu
	if id == "main" and not GameSession.setup_shown:
		GameSession.setup_shown = true
		id = "country"
	if id != "main":
		stack.append("main")
	open(id)


func open_campaign(slot := -1) -> void:
	GameSession.campaign_slot = slot
	goto_scene(CAMPAIGN)


func deploy_battle() -> void:
	GameSession.in_battle = true
	goto_scene(BATTLE)


## Katta sahnaga o'tish: fonda yuklanadi, progress chizig'i bilan.
func goto_scene(path: String) -> void:
	if not ResourceLoader.exists(path):
		EventBus.toast.emit("Missing: " + path)
		return
	_show_loading()
	_load_path = path
	ResourceLoader.load_threaded_request(path)
	set_process(true)


func _process(_d: float) -> void:
	if _load_path == "":
		set_process(false)
		return
	var prog := []
	var st := ResourceLoader.load_threaded_get_status(_load_path, prog)
	if _bar and not prog.is_empty():
		_bar.value = prog[0] * 100.0
	if st == ResourceLoader.THREAD_LOAD_LOADED:
		var ps := ResourceLoader.load_threaded_get(_load_path) as PackedScene
		_load_path = ""
		get_tree().change_scene_to_packed(ps)
		_hide_loading.call_deferred()
	elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		EventBus.toast.emit("Load failed: " + _load_path)
		_load_path = ""
		_hide_loading()


func _show_loading() -> void:
	if _loading:
		return
	_loading = CanvasLayer.new()
	_loading.layer = 100
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.035, 0.04)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(bg)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.custom_minimum_size = Vector2(420, 0)
	v.position = Vector2(-210, -20)
	bg.add_child(v)
	var l := Label.new()
	l.text = Loc.t("loading")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(420, 10)
	_bar.show_percentage = false
	v.add_child(_bar)
	add_child(_loading)


func _hide_loading() -> void:
	if _loading:
		_loading.queue_free()
		_loading = null
		_bar = null


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel") and _main_root():
		get_viewport().set_input_as_handled()
		back()
