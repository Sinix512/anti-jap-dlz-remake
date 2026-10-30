extends Node
## One touch -> one complete pointer transaction, in viewport coordinates.
## Native mouse emulation is disabled in project.godot to avoid duplicate taps.
## No gameplay state or player files are read or changed by this adapter.
signal touch_mode_changed(enabled: bool)

const SYNTHETIC_DEVICE := 1001
# Android sends a deferred GO_BACK_REQUEST for every native BACK DOWN,
# including echoes. Pair those notifications even across frame boundaries.
# A Java/gesture notification without native keys remains one local cancel.
class BackKeyGate extends Node:
	var bridge: WeakRef
	func _input(event: InputEvent) -> void:
		var adapter = bridge.get_ref()
		if adapter == null or not adapter.native_android_back or not adapter.is_touch_mode():return
		if event is InputEventKey and event.device != SYNTHETIC_DEVICE \
				and (event.keycode == KEY_BACK or event.physical_keycode == KEY_BACK):
			get_viewport().set_input_as_handled()
			adapter._queue_native_back(event.pressed, event.echo)

var native_android_back := OS.has_feature("Android") or OS.has_feature("android")
var _back_key_gate: Node
var _platform_back_queued := false
var _platform_back_presses := 0
var _platform_back_native := false
var _native_back_notification_credits := 0
var long_press_ms := 550
var drag_threshold := 12.0 # 640x480 logical pixels, independent of device density.
var dispatch_button_mask := 0
var _touch_mode := false
var _fingers: Dictionary = {}
var _pointer := -1
var _down := Vector2.ZERO
var _point := Vector2.ZERO
var _started := 0
var _dragged := false
var _blocked := false
var _target: WeakRef
var _scroll: WeakRef
var _scroll_origin := Vector2.ZERO

func _ready() -> void:
	get_tree().node_added.connect(_input_surface_changed)
	get_tree().node_removed.connect(_input_surface_changed)
	# Touch hardware does not change the desktop UI. Only mobile exports or an
	# explicit desktop test/debug flag opt in to the alternate interaction path.
	set_touch_mode(OS.has_feature("mobile") or native_android_back
		or OS.get_cmdline_user_args().has("--touch-ui"))
	if OS.is_debug_build() and OS.has_feature("mobile"):
		print("TOUCH_INPUT ready; native_android_back_filter=",native_android_back)
	call_deferred("_install_back_key_gate")

func _install_back_key_gate() -> void:
	if not is_inside_tree():return
	var gate := BackKeyGate.new()
	gate.name = "TouchBackKeyGate"
	gate.bridge = weakref(self)
	_back_key_gate = gate
	get_tree().root.add_child(gate)
	_keep_back_key_gate_last()

func _keep_back_key_gate_last() -> void:
	if not is_instance_valid(_back_key_gate) or not _back_key_gate.is_inside_tree():return
	var root := get_tree().root
	if _back_key_gate.get_index() != root.get_child_count()-1:
		root.move_child(_back_key_gate, root.get_child_count()-1)

func _process(_delta: float) -> void:
	# _input runs in reverse tree order. An early autoload alone cannot stop a
	# native BACK from dismissing a modal before the synthesized cancel arrives.
	_keep_back_key_gate_last()

func _exit_tree() -> void:
	if is_instance_valid(_back_key_gate):_back_key_gate.queue_free()

func _input_surface_changed(node: Node) -> void:
	if not is_inside_tree():return
	if node != _back_key_gate and node.get_parent() == get_tree().root:
		call_deferred("_keep_back_key_gate_last")
	# A delayed tap belongs to the UI present at finger-down, never a screen
	# which appeared (or was uncovered) while that finger was still held.
	if _pointer < 0 or not (node is Control or node is CanvasLayer):return
	_blocked = true
	_cancel_target()
	_pointer = -1
	_scroll = null

func is_touch_mode() -> bool:
	return _touch_mode

func set_touch_mode(enabled: bool) -> void:
	if _touch_mode == enabled:return
	cancel_gesture()
	_touch_mode = enabled
	touch_mode_changed.emit(enabled)

func is_pointer_down() -> bool:
	return _pointer >= 0 or dispatch_button_mask != 0

func is_dispatching_left_press() -> bool:
	return (dispatch_button_mask & MOUSE_BUTTON_MASK_LEFT) != 0

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		cancel_gesture()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST and is_touch_mode():
		_queue_platform_back(false)

func _queue_native_back(pressed: bool, echo: bool) -> void:
	# Godot AndroidInputHandler defers one window notification per pressed
	# native event. process_frame may flush the key before that notification
	# arrives; a credit, not a time debounce, prevents a second parent cancel.
	if pressed:_native_back_notification_credits += 1
	_queue_platform_back(pressed and not echo, true)

func _queue_platform_back(key_down: bool, native_key := false) -> void:
	if not native_key and _native_back_notification_credits > 0:
		_native_back_notification_credits -= 1
		return
	if key_down:_platform_back_presses += 1
	_platform_back_native = _platform_back_native or native_key
	if _platform_back_queued or not is_inside_tree():return
	_platform_back_queued = true
	get_tree().process_frame.connect(_flush_platform_back, CONNECT_ONE_SHOT)

func _flush_platform_back() -> void:
	# A held native key may echo and emit more notifications. Its echoes and
	# release are not new presses, and must not dismiss successive dialogs.
	var presses := _platform_back_presses if _platform_back_native else 1
	_platform_back_queued = false
	_platform_back_presses = 0
	_platform_back_native = false
	for _press in range(presses):request_back()

func request_back() -> void:
	cancel_gesture()
	# Only a local key-down is dispatched: mobile dialogs handle Esc on press.
	# A matching release after closing a dialog could dismiss its parent too.
	# push_input does not leave a global Input key held.
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	event.device = SYNTHETIC_DEVICE
	get_viewport().push_input(event, true)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if not is_touch_mode():return
		get_viewport().set_input_as_handled()
		if event.pressed:
			_fingers[event.index] = true
			if _fingers.size() > 1:
				_blocked = true
				_cancel_target()
				_pointer = -1
			elif not _blocked:
				_begin(event.index, event.position)
		else:
			_fingers.erase(event.index)
			if event.index == _pointer:
				_finish(event.position, event.canceled)
			if _fingers.is_empty():_blocked = false
	elif event is InputEventScreenDrag:
		if not is_touch_mode():return
		get_viewport().set_input_as_handled()
		if event.index != _pointer or _blocked:return
		_point = event.position
		if _point.distance_to(_down) >= drag_threshold:_dragged = true
		if _dragged:
			var target = _live_target()
			if target != null:target.touch_pan(_point - _down)
			else:_pan_scroll(_point - _down)

func _begin(index: int, point: Vector2) -> void:
	_pointer = index
	_down = point
	_point = point
	_started = Time.get_ticks_msec()
	_dragged = false
	_target = null
	_scroll = null
	for candidate in get_tree().get_nodes_in_group("touch_battle"):
		if is_instance_valid(candidate) and candidate.is_visible_in_tree() and candidate.touch_accepts(point):
			_target = weakref(candidate)
			candidate.touch_begin(point)
			break
	if _target == null:
		_dispatch_motion(point)
		var hovered := get_viewport().gui_get_hovered_control()
		while hovered != null:
			if hovered is ScrollContainer and hovered.is_visible_in_tree() and hovered.get_global_rect().has_point(point):
				_scroll = weakref(hovered)
				_scroll_origin = Vector2(hovered.scroll_horizontal, hovered.scroll_vertical)
				break
			hovered = hovered.get_parent_control()

func _pan_scroll(total: Vector2) -> void:
	var scroll = _scroll.get_ref() if _scroll != null else null
	if scroll == null or not scroll.is_visible_in_tree():return
	if scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		scroll.scroll_horizontal = roundi(_scroll_origin.x - total.x)
	if scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		scroll.scroll_vertical = roundi(_scroll_origin.y - total.y)

func _live_target():
	return _target.get_ref() if _target != null else null

func _finish(point: Vector2, canceled: bool) -> void:
	var target = _live_target()
	var dragged := _dragged or point.distance_to(_down) >= drag_threshold
	var held := Time.get_ticks_msec() - _started >= long_press_ms
	_pointer = -1
	_target = null
	if canceled or _blocked:
		if target != null:target.touch_cancel()
		_scroll = null
		return
	if target != null:
		if dragged:target.touch_pan(point - _down)
		elif target.touch_accepts(point):target.touch_tap(point, held)
		else:target.touch_cancel()
	elif dragged:_pan_scroll(point - _down)
	else:_dispatch_click(point, MOUSE_BUTTON_RIGHT if held else MOUSE_BUTTON_LEFT)
	_scroll = null

func _dispatch_motion(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	motion.device = SYNTHETIC_DEVICE
	get_viewport().push_input(motion, true)

func _dispatch_click(point: Vector2, button: int) -> void:
	_dispatch_motion(point)
	for down in [true, false]:
		dispatch_button_mask = (MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if down else 0
		var click := InputEventMouseButton.new()
		click.position = point
		click.global_position = point
		click.button_index = button
		click.button_mask = dispatch_button_mask
		click.pressed = down
		click.device = SYNTHETIC_DEVICE
		get_viewport().push_input(click, true)
	dispatch_button_mask = 0

func _cancel_target() -> void:
	var target = _live_target()
	if target != null:target.touch_cancel()
	_target = null
	_scroll = null

func cancel_gesture() -> void:
	_cancel_target()
	_fingers.clear()
	_pointer = -1
	_blocked = false
	_dragged = false
	dispatch_button_mask = 0
	# Also remove an already previewed aim after app suspension/back.
	if is_inside_tree():
		for target in get_tree().get_nodes_in_group("touch_battle"):
			if is_instance_valid(target):target.touch_cancel()
