extends SceneTree
const Movie=preload("res://scripts/m5/CutscenePlayer.gd")
var checks:=0
var failures:=0
class Underlay extends Control:
	var events:=0
	func _unhandled_input(_event:InputEvent) -> void:events+=1
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("CUTSCENE_FAIL "+label)
func key(code:int,down:bool,echo:=false) -> void:
	var e:=InputEventKey.new();e.keycode=code;e.pressed=down;e.echo=echo;root.push_input(e,true)
func mouse(button:int,down:bool) -> void:
	var e:=InputEventMouseButton.new();e.button_index=button;e.pressed=down;e.position=Vector2(500,450);e.global_position=e.position;root.push_input(e,true)
func fixture():
	# Input/signal fixture without a decoder or autoplay. Actual decoded
	# video controls/absence of overlay are also checked by OriginalUIQA.
	var p=Movie.new();root.add_child(p)
	p._video=VideoStreamPlayer.new();p.add_child(p._video);p._video.finished.connect(p._finish)
	return p
func run() -> void:
	var under=Underlay.new();under.mouse_filter=Control.MOUSE_FILTER_IGNORE;root.add_child(under)
	var p=fixture();var done:Array=[];p.finished.connect(func():done.append("signal"));p._on_done=func():done.append("callback")
	for button in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE,MOUSE_BUTTON_WHEEL_UP]:
		for down in [true,false]:mouse(button,down)
	check(not p._finished and done.is_empty(),"all mouse buttons DOWN/UP are not skip")
	for code in [KEY_SPACE,KEY_ENTER,KEY_A]:key(code,true);key(code,false)
	key(KEY_ESCAPE,false)
	check(not p._finished and done.is_empty(),"non-Esc and Esc-UP are not skip")
	check(under.events==0,"modal movie consumes ignored input before underlying battle")
	key(KEY_ESCAPE,true)
	check(p._finished and done==["callback","signal"],"Esc-DOWN runs callback then finished exactly once")
	p._finish();p._video.finished.emit();key(KEY_ESCAPE,true)
	check(done==["callback","signal"],"duplicate native end/skip cannot dispatch twice")
	await process_frame;await process_frame
	p=fixture();done.clear();p.finished.connect(func():done.append("signal"));p._on_done=func():done.append("callback")
	p._video.finished.emit()
	check(p._finished and done==["callback","signal"],"natural decoder finished retains same immediate one-shot flow")
	await process_frame;await process_frame
	p=fixture();key(KEY_ESCAPE,true,true)
	check(p._finished,"native WM_KEYDOWN includes repeated Esc, no invented release gate")
	await process_frame;await process_frame
	p=Movie.new();root.add_child(p);done.clear();p.finished.connect(func():done.append("signal"))
	p.setup("",load("res://assets/font/hzk16.fnt"),func():done.append("callback"))
	check(p._finished and done==["callback","signal"],"missing media preserves existing fail-through rather than softlock")
	check(p.find_children("*","Label",true,false).is_empty(),"fallback never creates modern skip overlay")
	await process_frame;under.queue_free();await process_frame
	print("ORIGINAL_CUTSCENE checks=",checks," failures=",failures)
	if failures==0:print("ORIGINAL_CUTSCENE PASS")
	quit(1 if failures else 0)
