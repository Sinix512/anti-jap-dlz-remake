extends Control

## Shop-only quantity editor. OriginalQuantity remains available to native fixtures.
## This control previews a transaction; the campaign validates and mutates assets.
signal chosen(quantity: int)
signal cancelled

const UI = preload("res://scripts/ui/OriginalUI.gd")
const ReleaseGuard = preload("res://scripts/ui/OpeningReleaseGuard.gd")
const MAX_INT64: int = 9223372036854775807
const CARD_RECT := Rect2(140, 112, 360, 256)

var font: Font
var material_name := ""
var unit := ""
var unit_price := 0
var maximum := 0
var money := 0
var quantity := 0
var done := false
var quantity_input: LineEdit
var minus_button: Button
var plus_button: Button
var maximum_button: Button
var buy_button: Button
var cancel_button: Button
var total_label: Label
var balance_label: Label
var _release_guard = ReleaseGuard.new()
var _left_down := false


func setup(f: Font, item_name: String, measure: String, price: int,
		limit: int, funds: int) -> void:
	font = f
	material_name = item_name.replace("\\u3000", "").replace("　", "").strip_edges()
	unit = measure.replace("\\u3000", "").replace("　", "").strip_edges()
	unit_price = maxi(0, price)
	maximum = maxi(0, limit)
	money = maxi(0, funds)
	quantity = mini(1, maximum)
	# Campaign uses fixed logical 640x480 drawing on a zero-sized Control.
	# Explicit bounds keep the modal/dimmer full-screen in that host as well as
	# standalone tests; viewport scaling still handles high-DPI windows.
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	size = Vector2(640, 480)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	theme = UI.make_theme(font)
	_release_guard.capture()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UI.nine_patch(UI.PANEL_RED, CARD_RECT, 10))
	_label("购买材料", Rect2(156, 124, 328, 20), UI.GOLD_LIGHT)
	_label("材料：%s（%s）" % [material_name, unit], Rect2(156, 150, 328, 20))
	_label("单价：%d元  上限：%d%s" % [unit_price, maximum, unit],
			Rect2(156, 174, 328, 20), UI.MUTED)
	_label("数量", Rect2(156, 204, 48, 24))
	minus_button = _button("-", Rect2(204, 200, 40, 28), _adjust.bind(-1))
	quantity_input = LineEdit.new()
	quantity_input.position = Vector2(248, 200)
	quantity_input.size = Vector2(112, 28)
	quantity_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	quantity_input.context_menu_enabled = false
	quantity_input.max_length = 20
	quantity_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	quantity_input.add_theme_font_override("font", font)
	quantity_input.add_theme_font_size_override("font_size", 16)
	quantity_input.add_theme_color_override("font_color", UI.INK)
	quantity_input.add_theme_color_override("caret_color", UI.GOLD_LIGHT)
	quantity_input.add_theme_color_override("selection_color", Color("#6e4c24"))
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color("#211811")
	input_style.border_color = UI.GOLD_DARK
	input_style.set_border_width_all(1)
	input_style.content_margin_left = 5
	input_style.content_margin_right = 5
	input_style.content_margin_top = 4
	input_style.content_margin_bottom = 3
	quantity_input.add_theme_stylebox_override("normal", input_style)
	var focus_style := input_style.duplicate() as StyleBoxFlat
	focus_style.border_color = UI.GOLD_LIGHT
	quantity_input.add_theme_stylebox_override("focus", focus_style)
	quantity_input.text_changed.connect(_quantity_changed)
	quantity_input.focus_exited.connect(_normalize_quantity)
	add_child(quantity_input)
	plus_button = _button("+", Rect2(364, 200, 40, 28), _adjust.bind(1))
	maximum_button = _button("最大", Rect2(408, 200, 76, 28), _set_maximum)
	total_label = _label("", Rect2(156, 236, 328, 20), UI.GOLD_LIGHT)
	balance_label = _label("", Rect2(156, 258, 328, 20))
	buy_button = _button("购买", Rect2(204, 288, 112, 30), _confirm)
	cancel_button = _button("取消", Rect2(328, 288, 112, 30), _cancel)
	_label("回车购买 / Esc或右键取消", Rect2(156, 334, 328, 20), UI.MUTED)
	_refresh()
	call_deferred("_focus_quantity")


func _label(value: String, rect: Rect2, ink := UI.INK) -> Label:
	var label := UI.label(value, font, 16, ink)
	label.position = rect.position
	label.size = rect.size
	add_child(label)
	return label


func _button(value: String, rect: Rect2, action: Callable) -> Button:
	var button := UI.button(value, font, rect.size, action)
	button.position = rect.position
	add_child(button)
	return button


func _focus_quantity() -> void:
	if done or not is_inside_tree():
		return
	quantity_input.grab_focus()
	quantity_input.select_all()


func _parse_quantity(value: String) -> int:
	# Saturate without converting an arbitrarily large pasted integer to int64.
	# Invalid/empty/negative text is zero rather than a partial numeric purchase.
	if value.is_empty():
		return 0
	var number := 0
	var exceeds_maximum := false
	for character in value:
		var digit: int = character.unicode_at(0) - 48
		if digit < 0 or digit > 9:
			return 0
		if exceeds_maximum:
			continue
		if number > maximum / 10 or (number == maximum / 10 and digit > maximum % 10):
			exceeds_maximum = true
		else:
			number = number * 10 + digit
	return maximum if exceeds_maximum else number


func _quantity_changed(value: String) -> void:
	if done:
		return
	quantity = _parse_quantity(value)
	# Empty is a useful intermediate edit (select-all, Backspace, then type).
	# Keep the visible field empty while the model is safely zero/unbuyable.
	_refresh(value.is_empty())


func _normalize_quantity() -> void:
	if done:
		return
	quantity = _parse_quantity(quantity_input.text)
	_refresh()


func _adjust(step: int) -> void:
	if done:
		return
	quantity = _parse_quantity(quantity_input.text)
	if step > 0:
		quantity = maximum if quantity >= maximum - step else quantity + step
	else:
		quantity = maxi(0, quantity + step)
	_refresh()


func _set_maximum() -> void:
	if done:
		return
	quantity = maximum
	_refresh()


func _cost_overflows() -> bool:
	return unit_price > 0 and quantity > MAX_INT64 / unit_price


func _can_buy() -> bool:
	return quantity > 0 and not _cost_overflows() and quantity * unit_price <= money


func _refresh(preserve_empty := false) -> void:
	var normalized := str(quantity)
	if not preserve_empty and quantity_input.text != normalized:
		var caret := quantity_input.caret_column
		quantity_input.text = normalized
		quantity_input.caret_column = mini(caret, normalized.length())
	var affordable := not _cost_overflows() and quantity * unit_price <= money
	var total := "超出可购买金额" if _cost_overflows() else "%d元" % (quantity * unit_price)
	total_label.text = "总价：" + total
	balance_label.text = "购买后余额：%d元" % (money - quantity * unit_price) if affordable else "购买后余额：资金不足"
	if maximum == 0 and unit_price > money:
		balance_label.text = "资金不足，无法购买。"
	balance_label.add_theme_color_override("font_color", UI.INK if affordable else UI.GOLD)
	buy_button.disabled = not _can_buy()
	minus_button.disabled = quantity <= 0
	plus_button.disabled = quantity >= maximum
	maximum_button.disabled = maximum <= 0 or quantity == maximum


func _confirm() -> void:
	if done:
		return
	# LineEdit can defer text_changed to the end of the input frame. Enter
	# must purchase what is visible now, not the previous keystroke's value.
	quantity = _parse_quantity(quantity_input.text)
	_refresh()
	if not _can_buy():
		return
	done = true
	chosen.emit(quantity)


func _cancel() -> void:
	if done:
		return
	done = true
	cancelled.emit()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if _release_guard.consumes(event):
		if event.button_index == MOUSE_BUTTON_LEFT:
			_left_down = false
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
			get_viewport().set_input_as_handled()
			if event.pressed and not event.echo:
				if event.keycode == KEY_ESCAPE:
					_cancel()
				else:
					_confirm()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			get_viewport().set_input_as_handled()
			if event.pressed:
				_cancel()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_left_down = true
			elif not _left_down:
				# A child opened on DOWN or UP must never inherit that gesture.
				get_viewport().set_input_as_handled()
			else:
				_left_down = false


func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and (event is InputEventKey or event is InputEventMouse):
		get_viewport().set_input_as_handled()
