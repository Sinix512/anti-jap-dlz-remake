extends RefCounted
# Godot input-queue adapter, not a claim about Win32 timing. A menu chooses on
# DOWN; the UP belonging to that same held gesture must not dismiss its child.
var pending_mouse_mask:=0
func capture() -> void:
	pending_mouse_mask=(Input.get_mouse_button_mask() | OriginalUI.touch_dispatch_mask()) & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT)
func consumes(event:InputEvent) -> bool:
	if not event is InputEventMouseButton or event.pressed:return false
	var bit:int=1 << (event.button_index-1)
	if (pending_mouse_mask & bit)==0:return false
	pending_mouse_mask &= ~bit
	# One physical left-UP satisfies both barriers, rather than requiring
	# another entire click just because an inherited native flag was set.
	if event.button_index==MOUSE_BUTTON_LEFT:OriginalUI.native_wait_left_blocked=false
	return true
