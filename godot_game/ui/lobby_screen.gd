extends Node
## Multiplayer lobby: host or join, see who is in, which nation each player took
## and what role they hold inside it.

var _list_box: VBoxContainer
var _chat_log: RichTextLabel
var _chat_input: LineEdit
var _address: LineEdit
var _port: LineEdit
var _status: Label

func open(_payload: Dictionary) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	UIKit.fullscreen(bg)
	bg.color = UIKit.BG
	layer.add_child(bg)

	var margin := MarginContainer.new()
	UIKit.fullscreen(margin)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	layer.add_child(margin)

	var cols := UIKit.hbox(20)
	margin.add_child(cols)

	var left := UIKit.vbox(8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	left.add_child(UIKit.title(Loc.t("menu.multiplayer")))
	_status = UIKit.label("Oflayn", 14, UIKit.MUTED)
	left.add_child(_status)

	left.add_child(UIKit.label("Manzil", 13))
	_address = LineEdit.new()
	_address.text = "127.0.0.1"
	left.add_child(_address)
	left.add_child(UIKit.label("Port", 13))
	_port = LineEdit.new()
	_port.text = str(Net.DEFAULT_PORT)
	left.add_child(_port)

	var host_btn := UIKit.button("SERVER OCHISH", 16)
	host_btn.pressed.connect(_host)
	left.add_child(host_btn)
	var join_btn := UIKit.button("ULANISH", 16)
	join_btn.pressed.connect(_join)
	left.add_child(join_btn)
	var leave_btn := UIKit.button("UZISH", 13)
	leave_btn.pressed.connect(func():
		Net.leave()
		_refresh())
	left.add_child(leave_btn)

	left.add_child(UIKit.spacer(10))
	var explain := UIKit.label(
		"Bir davlatni bir nechta o'yinchi boshqarishi mumkin. Har biri o'z lavozimiga ega: "
		+ "davlat rahbari, qo'mondon yoki ofitser. Urush va katta xarajatlar kengash ovoziga qo'yiladi.",
		12, UIKit.MUTED)
	explain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explain.custom_minimum_size = Vector2(360, 0)
	left.add_child(explain)

	var start_btn := UIKit.button("DUNYONI BOSHLASH", 18)
	start_btn.pressed.connect(_start_world)
	left.add_child(start_btn)
	var back := UIKit.button(Loc.t("common.back"), 13)
	back.pressed.connect(func(): GameState.go("main_menu", {}))
	left.add_child(back)

	var right := UIKit.vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	right.add_child(UIKit.label("O'yinchilar", 20, UIKit.ACCENT))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 260)
	right.add_child(scroll)
	_list_box = UIKit.vbox(4)
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_box)

	right.add_child(UIKit.label("Chat", 16))
	_chat_log = RichTextLabel.new()
	_chat_log.bbcode_enabled = true
	_chat_log.scroll_following = true
	_chat_log.custom_minimum_size = Vector2(0, 180)
	right.add_child(_chat_log)
	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = "Xabar yozing va Enter bosing"
	_chat_input.text_submitted.connect(func(t):
		if t.strip_edges() != "":
			Net.say(t)
		_chat_input.text = "")
	right.add_child(_chat_input)

	EventBus.lobby_updated.connect(_on_lobby)
	EventBus.net_state_changed.connect(func(_s): _refresh())
	EventBus.chat_received.connect(_on_chat)
	_refresh()

func _host() -> void:
	var err := Net.host(int(_port.text))
	if err != "":
		GameState.notify(err, "bad")
		return
	GameState.notify("Server ochildi. Do'stlaringiz %s:%s orqali ulanadi."
		% ["<sizning IP>", _port.text], "good")
	if GameState.world == null:
		GameState.start_new_world(0)
	_refresh()

func _join() -> void:
	var err := Net.join(_address.text, int(_port.text))
	if err != "":
		GameState.notify(err, "bad")
	_refresh()

func _start_world() -> void:
	if not Net.is_authority():
		GameState.notify("Dunyoni faqat server boshlaydi.", "warn")
		return
	if GameState.world == null:
		GameState.start_new_world(0)
	Net.broadcast_world()
	GameState.mode = GameState.Mode.GLOBAL_WAR
	GameState.go("nation_select", {})

func _refresh() -> void:
	if _status == null:
		return
	match Net.state:
		Net.State.HOSTING: _status.text = "Server ishlamoqda (port %s)" % _port.text
		Net.State.CONNECTED: _status.text = "Serverga ulandi"
		Net.State.CONNECTING: _status.text = "Ulanmoqda..."
		_: _status.text = "Oflayn"
	_on_lobby(Net.player_list())

func _on_lobby(list: Array) -> void:
	if _list_box == null:
		return
	for c in _list_box.get_children():
		c.queue_free()
	if list.is_empty():
		_list_box.add_child(UIKit.label("Hech kim yo'q.", 13, UIKit.MUTED))
		return
	for p in list:
		var nid := str(p.get("nation", ""))
		var n: Nation = GameState.world.nation(nid) if GameState.world != null else null
		var text := "%s — %s %s" % [str(p.get("name", "?")),
			n.display_name if n != null else "davlat tanlanmagan",
			GameState.role_name(int(p.get("role", 0)))]
		var col: Color = n.color if n != null else UIKit.TEXT
		_list_box.add_child(UIKit.label(text, 14, col))

func _on_chat(sender: String, text: String, _channel: String) -> void:
	if _chat_log == null:
		return
	_chat_log.text += "[b]%s:[/b] %s\n" % [sender, text]
