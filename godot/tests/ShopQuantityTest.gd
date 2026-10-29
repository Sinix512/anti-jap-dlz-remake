extends SceneTree

## Shop-only editor: pure UI, no campaign, saves, transactions, or OS input.
const Quantity = preload("res://scripts/ui/ShopQuantity.gd")
const OUTPUT := "res://../out/evidence/shop_convenience295_20261029/shop_quantity_test.json"
var checks := 0
var failures := 0
var rows: Array = []
var dialog: Control
var results: Dictionary = {}
var font: Font


func _initialize() -> void:
	call_deferred("run")


func check(ok: bool, label: String) -> void:
	checks += 1
	rows.append({"ok": ok, "label": label})
	if not ok:
		failures += 1
		push_error("SHOP_QUANTITY " + label)


func fixture(limit := 10, price := 10, funds := 1000) -> void:
	if is_instance_valid(dialog):
		dialog.free()
	results = {"chosen": [], "cancelled": 0}
	dialog = Quantity.new()
	root.add_child(dialog)
	dialog.setup(font, "炸药", "份", price, limit, funds)
	dialog.chosen.connect(func(count: int): results.chosen.append(count))
	dialog.cancelled.connect(func(): results.cancelled += 1)


func pointer(point: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = root.get_final_transform() * point
	event.global_position = event.position
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func key(code: Key, unicode := 0) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.unicode = unicode
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	event = event.duplicate() as InputEventKey
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func click(point: Vector2) -> void:
	pointer(point, true)
	await process_frame
	pointer(point, false)
	await process_frame


func run() -> void:
	OriginalUI.sfx_enabled = false
	font = load("res://assets/font/hzk16.fnt")
	fixture()
	await process_frame
	await process_frame
	check(dialog.quantity == 1 and dialog.quantity_input.text == "1", "default is one with editable number")
	check(dialog.total_label.text == "总价：10元" and dialog.balance_label.text == "购买后余额：990元", "unit price drives live total and resulting balance")
	check(not dialog.buy_button.disabled and not dialog.maximum_button.disabled, "valid default is purchasable")
	check(dialog.size == Vector2(640, 480) and dialog.get_child(0).size == Vector2(640, 480), "modal and dimmer cover logical screen even in zero-sized campaign host")
	dialog.quantity_input.text = ""
	dialog._quantity_changed("")
	check(dialog.quantity == 0 and dialog.quantity_input.text.is_empty() and dialog.buy_button.disabled, "empty edit stays visually empty while zero and unbuyable")
	for value in ["-1", "abc", "1.5", " 2", "１２", "999999999999999999999x"]:
		dialog._quantity_changed(value)
		check(dialog.quantity == 0 and dialog.quantity_input.text == "0" and dialog.buy_button.disabled, "invalid input safely becomes zero: " + value)
	dialog._quantity_changed("0003")
	check(dialog.quantity == 3 and dialog.quantity_input.text == "3", "leading zeroes normalize to integer")
	dialog._quantity_changed("99999999999999999999999999999999999")
	check(dialog.quantity == 10 and dialog.quantity_input.text == "10", "oversized pasted integer saturates at maximum without overflow")
	dialog._adjust(1)
	check(dialog.quantity == 10 and dialog.plus_button.disabled, "plus clamps at original maximum")
	dialog._quantity_changed("0")
	dialog._adjust(-1)
	check(dialog.quantity == 0 and dialog.minus_button.disabled, "minus clamps at zero")
	dialog._adjust(1)
	check(dialog.quantity == 1, "plus increments exactly one")
	dialog._set_maximum()
	check(dialog.quantity == 10 and dialog.maximum_button.disabled, "maximum selects supplied limit")
	var motion := InputEventMouseMotion.new()
	motion.position = root.get_final_transform() * Vector2(250, 214)
	motion.global_position = motion.position
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	check(dialog.quantity == 10 and results.chosen.is_empty(), "hover and mouse movement never change or accept quantity")

	fixture(0)
	check(dialog.quantity == 0 and dialog.buy_button.disabled and dialog.plus_button.disabled and dialog.maximum_button.disabled, "zero maximum has zero default and cannot purchase")
	fixture(0, 10, 0)
	check(dialog.balance_label.text.contains("资金不足") and dialog.buy_button.disabled, "unaffordable first unit explains disabled purchase")
	dialog._confirm()
	check(results.chosen.is_empty() and not dialog.done, "confirming zero is a no-op")

	fixture(10, 10, 15)
	dialog._set_maximum()
	check(dialog.maximum == 10 and dialog.quantity == 10, "maximum is never silently replaced with an affordability limit")
	check(dialog.buy_button.disabled and dialog.balance_label.text == "购买后余额：资金不足", "unaffordable total disables purchase and explains balance")
	dialog._confirm()
	check(results.chosen.is_empty() and not dialog.done, "unaffordable Enter path cannot emit chosen")
	dialog._quantity_changed("1")
	dialog._confirm()
	dialog._confirm()
	dialog._cancel()
	check(results.chosen == [1] and results.cancelled == 0 and dialog.done, "valid confirmation is emitted once and cancellation cannot follow")

	fixture(Quantity.MAX_INT64, Quantity.MAX_INT64, Quantity.MAX_INT64)
	dialog._quantity_changed("9223372036854775807")
	check(dialog.quantity == Quantity.MAX_INT64, "largest int64 quantity parses exactly")
	check(dialog.buy_button.disabled and dialog.total_label.text == "总价：超出可购买金额", "multiplication overflow never wraps into an affordable purchase")
	dialog._quantity_changed("9223372036854775808")
	check(dialog.quantity == Quantity.MAX_INT64, "integer above int64 safely saturates")
	dialog._adjust(1)
	check(dialog.quantity == Quantity.MAX_INT64, "plus at int64 maximum never wraps")

	fixture()
	await process_frame
	await process_frame
	key(KEY_3, 51)
	await process_frame
	check(dialog.quantity == 3, "focused selected numeric input supports actual keyboard typing")
	key(KEY_ENTER)
	key(KEY_ENTER)
	key(KEY_ESCAPE)
	check(results.chosen == [3] and results.cancelled == 0, "Enter buys once; later keyboard events cannot re-emit")

	fixture()
	await process_frame
	key(KEY_4, 52)
	key(KEY_ENTER)
	check(results.chosen == [4], "same-frame typing and Enter purchase visible text rather than stale quantity")

	fixture(1000, 1, 100000)
	await process_frame
	await process_frame
	key(KEY_BACKSPACE)
	await process_frame
	check(dialog.quantity_input.text.is_empty() and dialog.quantity == 0 and dialog.buy_button.disabled, "actual select-all then Backspace leaves an empty disabled editor")
	key(KEY_5, 53)
	await process_frame
	key(KEY_6, 54)
	await process_frame
	check(dialog.quantity_input.text == "56" and dialog.quantity == 56, "typing two digits after clearing neither prefixes nor appends a synthetic zero")
	key(KEY_ENTER)
	check(results.chosen == [56], "cleared then retyped quantity submits exactly the visible two-digit value")

	fixture()
	await process_frame
	await process_frame
	key(KEY_BACKSPACE)
	await process_frame
	dialog.quantity_input.release_focus()
	await process_frame
	check(dialog.quantity == 0 and dialog.quantity_input.text == "0" and dialog.buy_button.disabled, "empty field normalizes to zero on focus loss without permitting purchase")

	fixture()
	await process_frame
	await process_frame
	key(KEY_BACKSPACE)
	key(KEY_ENTER)
	check(dialog.quantity_input.text == "0" and dialog.quantity == 0 and results.chosen.is_empty(), "confirming an empty edit normalizes safely without purchasing the old quantity")

	fixture()
	await process_frame
	await click(Vector2(384, 214))
	check(dialog.quantity == 2, "actual plus button increments numeric entry")
	await click(Vector2(224, 214))
	check(dialog.quantity == 1, "actual minus button decrements numeric entry")
	await click(Vector2(446, 214))
	check(dialog.quantity == 10, "actual maximum button uses complete passed limit")
	await click(Vector2(384, 303))
	check(results.cancelled == 1 and results.chosen.is_empty(), "actual cancel button emits cancellation only")

	fixture()
	await process_frame
	key(KEY_ESCAPE)
	key(KEY_ESCAPE)
	dialog._confirm()
	check(results.cancelled == 1 and results.chosen.is_empty(), "Escape cancels once and cannot later purchase")

	fixture()
	await process_frame
	pointer(Vector2(300, 214), true, MOUSE_BUTTON_RIGHT)
	pointer(Vector2(300, 214), false, MOUSE_BUTTON_RIGHT)
	check(results.cancelled == 1 and results.chosen.is_empty(), "right mouse button cancels without opening an edit context menu")

	fixture()
	await process_frame
	pointer(Vector2(260, 300), false)
	await process_frame
	check(not dialog.done and results.chosen.is_empty(), "orphan opening release over purchase button cannot buy")
	pointer(Vector2(260, 300), true)
	await process_frame
	pointer(Vector2(260, 300), false)
	await process_frame
	check(results.chosen == [1], "fresh purchase-button click works after opening-release barrier")

	# Capture a held opening gesture before constructing the new modal.
	dialog.free()
	pointer(Vector2(260, 300), true)
	fixture()
	await process_frame
	pointer(Vector2(260, 300), false)
	await process_frame
	check(results.chosen.is_empty() and not dialog.done, "held opening gesture release is consumed rather than purchasing")
	key(KEY_ENTER)
	check(results.chosen == [1], "opening-release guard does not block a deliberate Enter")

	fixture(1000, 1, 100000)
	await process_frame
	var contents_fit := true
	for child in dialog.get_children():
		if child is Label or child is Button or child is LineEdit:
			contents_fit = contents_fit and Quantity.CARD_RECT.encloses(child.get_rect())
			if child is Label:
				contents_fit = contents_fit and child.get_minimum_size().x <= child.size.x
	check(contents_fit, "actual material labels and controls fit the centered pixel-font card")
	dialog.free()
	OriginalUI.release_native_sfx()
	var output := ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "rows": rows}, "\t") + "\n")
	file.close()
	print("SHOP_QUANTITY checks=", checks, " failures=", failures)
	if failures == 0:
		print("SHOP_QUANTITY PASS")
	quit(1 if failures else 0)
