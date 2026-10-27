extends SceneTree
const Title=preload("res://scripts/ui/TitleScreen.gd")
var checks:=0
var failures:=0
var emitted:Array=[]
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("TITLE_FAIL "+label)
func mouse(point:Vector2,down:=false,button:=MOUSE_BUTTON_LEFT) -> void:
	var e:=InputEventMouseButton.new();e.position=point;e.global_position=point;e.button_index=button;e.pressed=down;root.push_input(e,true)
func move(point:Vector2) -> void:
	var e:=InputEventMouseMotion.new();e.position=point;e.global_position=point;root.push_input(e,true)
func key(code:int,down:=true) -> void:
	var e:=InputEventKey.new();e.keycode=code;e.pressed=down;root.push_input(e,true)
func make_title():
	var t=Title.new();root.add_child(t);t.setup(load("res://assets/font/hzk16.fnt"));t.set_process(false)
	t.new_game.connect(func():emitted.append(4));t.continue_game.connect(func():emitted.append(5));t.high_scores.connect(func():emitted.append(2));t.supporters.connect(func():emitted.append(6));t.quit_game.connect(func():emitted.append(3))
	return t
func run() -> void:
	var t=make_title()
	check(t.selected==0 and t.counter==0,"original row0/frame0 initialization")
	check(t.background.get_size()==Vector2(640,480) and t.indicator.get_size()==Vector2(56,1440),"original full background and 30 indicator frames")
	check(t.highlights.size()==5 and t.highlights.all(func(p):return p.get_size()==Vector2(232,56)),"five native opaque highlights")
	check(t.find_children("*","BaseButton",true,false).is_empty() and t.find_children("*","Label",true,false).is_empty(),"no modern buttons or invented text overlays")
	for sample in [[Vector2(315,60),0],[Vector2(546,115),0],[Vector2(547,60),-1],[Vector2(315,116),-1],[Vector2(315,132),1],[Vector2(315,204),2],[Vector2(315,270),3],[Vector2(315,336),4],[Vector2(315,392),-1]]:
		check(t.row_at(sample[0])==sample[1],"native half-open hit rectangle "+str(sample[0]))
	move(Vector2(320,210));check(t.selected==2,"MOVE selects exact hovered row")
	for i in range(29):t.tick()
	check(t.counter==29,"timer reaches frame29")
	move(Vector2(320,340));check(t.counter==29 and t.selected==4,"hover does not reset animation phase")
	move(Vector2(20,20));check(t.selected==4,"outside MOVE retains current row")
	t.tick();check(t.counter==0,"timer wraps modulo30")
	for code in [KEY_UP,KEY_DOWN,KEY_W,KEY_S,KEY_ENTER,KEY_ESCAPE]:key(code);key(code,false)
	check(t.selected==4 and emitted.is_empty(),"keyboard has no selection or accept shortcut")
	mouse(Vector2(320,60),true);check(emitted.is_empty(),"DOWN alone ignored")
	mouse(Vector2(320,60),false,MOUSE_BUTTON_RIGHT);check(emitted.is_empty(),"right-UP ignored")
	mouse(Vector2(20,20));check(emitted.is_empty() and not t.done,"outside UP has no destination")
	mouse(Vector2(320,140));check(emitted==[5],"DOWN row0 to UP row1 executes release hit not current")
	mouse(Vector2(320,60));check(emitted==[5],"done gate blocks duplicate dispatch")
	t.free()
	for row in range(5):
		t=make_title();emitted.clear()
		mouse(Vector2(1,1),true);mouse(Vector2(316,Title.ROW_Y[row]+1))
		check(emitted==[Title.DESTINATIONS[row]],"outside DOWN to valid UP original destination %d"%row)
		t.free()
	OriginalUI.release_native_sfx();root.get_node("Music").release_playback();await create_timer(0.3).timeout
	print("ORIGINAL_TITLE checks=",checks," failures=",failures)
	quit(1 if failures else 0)
