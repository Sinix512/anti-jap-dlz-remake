extends Control

## M3 原味标题界面：BG01 + 战报式金框菜单。

signal new_game
signal continue_game
signal battle_select
signal story_archive
signal settings
signal quit_game

var font: Font
var _menu: VBoxContainer
var _selected := 0
var _buttons: Array[Button] = []
var _bg: TextureRect
var _glow: TextureRect


func setup(f: Font) -> void:
	font = f
	theme = OriginalUI.make_theme(font)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()


func _build() -> void:
	_bg = TextureRect.new()
	_bg.texture = load("res://assets/ui/title_bg.png") if ResourceLoader.exists(
			"res://assets/ui/title_bg.png") else null
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_SCALE
	_bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_bg.modulate = Color(0.92, 0.90, 0.82, 1.0)
	add_child(_bg)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.01, 0.30)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_glow = TextureRect.new()
	_glow.texture = OriginalUI.glow_texture()
	_glow.position = Vector2(250, 50)
	_glow.size = Vector2(300, 140)
	_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_glow.stretch_mode = TextureRect.STRETCH_SCALE
	_glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_glow.modulate = Color(1, 0.8, 0.4, 0.32)
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glow)
	var tw := create_tween().set_loops()
	tw.tween_property(_glow, "modulate:a", 0.10, 1.6)
	tw.tween_property(_glow, "modulate:a", 0.38, 1.6)

	var title := OriginalUI.title("抗日：地雷战", font, 40, OriginalUI.GOLD)
	title.position = Vector2(0, 66)
	title.size = Vector2(640, 52)
	add_child(title)
	var sub := OriginalUI.label("冀中一九四二　平阳游击队", font, 16,
			Color("#e7c98d"))
	sub.position = Vector2(0, 120)
	sub.size = Vector2(640, 22)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)

	# 左侧原版金框菜单
	var panel := OriginalUI.nine_patch(OriginalUI.PANEL_RED,
			Rect2(40, 170, 270, 276), 12)
	add_child(panel)
	var head := OriginalUI.header("军 令", font, Rect2(46, 176, 258, 28))
	add_child(head)
	_menu = VBoxContainer.new()
	_menu.position = Vector2(58, 216)
	_menu.size = Vector2(234, 216)
	_menu.add_theme_constant_override("separation", 7)
	add_child(_menu)
	_add_button("新的战役", func(): new_game.emit())
	_add_button("读取存档", func(): continue_game.emit())
	_add_button("战斗演练", func(): battle_select.emit())
	_add_button("剧情回顾", func(): story_archive.emit())
	_add_button("设置", func(): settings.emit())
	_add_button("退出", func(): quit_game.emit())
	_select(0)

	# 右侧题记：背景龙纹太花，加一层暗底保证 16px 点阵字能读。
	var quote_bg := ColorRect.new()
	quote_bg.color = Color(0.02, 0.01, 0.01, 0.46)
	quote_bg.position = Vector2(332, 226)
	quote_bg.size = Vector2(278, 94)
	quote_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(quote_bg)
	var quote := OriginalUI.label(
		"“地雷战，是群众创造的战法。\n"
		+ "  每一颗雷，都埋在自己的土地上。”", font, 16,
		Color("#f0dfb8"))
	quote.position = Vector2(340, 232)
	quote.size = Vector2(270, 90)
	quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(quote)
	var line := ColorRect.new()
	line.color = Color(0.78, 0.56, 0.20, 0.7)
	line.position = Vector2(340, 326)
	line.size = Vector2(230, 2)
	add_child(line)
	var tip := OriginalUI.label("↑↓ 选择    Enter 确认", font, 16,
			Color("#d8c39a"))
	tip.position = Vector2(340, 342)
	tip.size = Vector2(250, 22)
	add_child(tip)

	var foot := OriginalUI.label("西山居 1998　复刻版", font, 14,
			Color("#b7a17c"))
	foot.position = Vector2(0, 456)
	foot.size = Vector2(640, 20)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(foot)


func _add_button(text: String, cb: Callable) -> void:
	var b := OriginalUI.button(text, font, Vector2(234, 32), cb, 16)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_menu.add_child(b)
	_buttons.append(b)


func _select(i: int) -> void:
	if _buttons.is_empty():
		return
	_selected = wrapi(i, 0, _buttons.size())
	for j in range(_buttons.size()):
		_buttons[j].modulate = Color(1.18, 1.05, 0.72) if j == _selected else Color.WHITE


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_UP or event.keycode == KEY_W:
			_select(_selected - 1)
			OriginalUI.play_sfx("click")
		elif event.keycode == KEY_DOWN or event.keycode == KEY_S:
			_select(_selected + 1)
			OriginalUI.play_sfx("click")
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_buttons[_selected].pressed.emit()
			get_viewport().set_input_as_handled()
