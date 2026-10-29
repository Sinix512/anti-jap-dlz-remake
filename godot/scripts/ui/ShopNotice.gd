extends "res://scripts/ui/OriginalNotice.gd"

## A shop quantity can confirm on Enter-DOWN. Its error notice must survive
## that same key's eventual UP, without changing native story/service waits.
var _opening_accept_keys: Array[int] = []


func setup(font: Font, value: String, palette: Array = []) -> void:
	super.setup(font, value, palette)
	for code in [KEY_ENTER, KEY_KP_ENTER]:
		if Input.is_key_pressed(code):
			_opening_accept_keys.append(code)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode in _opening_accept_keys:
		if not event.pressed:
			_opening_accept_keys.erase(event.keycode)
			get_viewport().set_input_as_handled()
			return
		if not event.echo:
			# A fresh DOWN also retires a stale barrier if the OS lost the UP.
			_opening_accept_keys.erase(event.keycode)
	super._input(event)
