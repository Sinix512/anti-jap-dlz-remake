extends SceneTree
const Picker=preload("res://scripts/ui/OriginalSavePicker.gd")
const Palette=preload("res://scripts/ui/OriginalPalette.gd")
const Confirm=preload("res://scripts/ui/OriginalConfirm.gd")
const Slots=preload("res://scripts/ui/OriginalSaveSlots.gd")
var checks:=0
var failures:=0
var answers:Array=[]
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("SAVE_PICKER_FAIL "+label)
func mouse(point:Vector2,down:=true,button:=MOUSE_BUTTON_LEFT) -> void:
	var e:=InputEventMouseButton.new();e.position=point;e.global_position=point;e.pressed=down;e.button_index=button;root.push_input(e,true)
func move(point:Vector2) -> void:
	var e:=InputEventMouseMotion.new();e.position=point;e.global_position=point;root.push_input(e,true)
func key() -> void:
	var e:=InputEventKey.new();e.keycode=KEY_ENTER;e.pressed=true;root.push_input(e,true)
func picker(loading:=true):
	var p=Picker.new();root.add_child(p);p.setup(load("res://assets/font/hzk16.fnt"),Palette.colors("BG01"),[{}, {"mode":150,"level":9,"difficulty":1,"turn":3,"intro":"虎口救亲人"},{},{"mode":57,"level":4,"difficulty":2,"turn":8,"intro":"高家庄"},{}],loading)
	p.chosen.connect(func(slot):answers.append(slot));return p
func run() -> void:
	var p=picker()
	check(p.choice==-1 and not p.highlight.visible,"no default selected or cursor warp")
	check(p.background.get_size()==Vector2(456,227) and p.find_children("*","BaseButton",true,false).is_empty(),"raw MENU09 overlay without modern manager controls")
	check(p.entries(0)==[{"x":36,"text":"进度"},{"x":68,"text":"一"}],"empty row only original progress and ordinal")
	check(p.entries(1).any(func(e):return e.x==132 and e.text=="10") and p.entries(1).any(func(e):return e.x==302 and e.text==" 3"),"native fixed-width2 level and turn strings")
	check(p.entries(3).any(func(e):return e.x==286 and e.text=="休息关") and not p.entries(3).any(func(e):return e.x==302),"strategic preview has no battle turn")
	key();mouse(Vector2(100,160),false);mouse(Vector2(1,1),true,MOUSE_BUTTON_RIGHT)
	check(answers.is_empty(),"keyboard/left-UP/right-DOWN ignored")
	move(Vector2(639,194));check(p.choice==1 and p.highlight.position==Vector2(92,194) and p.highlight.size==Vector2(400,18),"full-screen x MOVE selects 400x18 original strip")
	move(Vector2(200,400));check(p.choice==1,"out-of-range MOVE retains prior selection")
	mouse(Vector2(10,10));check(answers==[1],"DOWN confirms previous hover, not click position")
	mouse(Vector2(10,10));check(answers==[1],"completion gate blocks duplicate selection");p.free()
	answers.clear();p=picker();mouse(Vector2(320,200));check(answers==[-1],"DOWN without MOVE cancels, no recomputed row");p.free()
	answers.clear();p=picker();move(Vector2(0,158));mouse(Vector2(1,1));check(answers==[-1],"load empty row returns cancel, no reprompt");p.free()
	answers.clear();p=picker(false);move(Vector2(0,337));mouse(Vector2(1,1));check(answers==[4],"save accepts original fifth empty slot");p.free()
	answers.clear();p=picker(false);move(Vector2(640,158));check(p.choice==-1,"full-screen right edge exclusive")
	move(Vector2(639,338));check(p.choice==-1,"bottom338 exclusive")
	mouse(Vector2(1,1),false,MOUSE_BUTTON_RIGHT);check(answers==[-1],"right-UP cancels");p.free()
	var camp=load("res://tests/helpers/LegalProbeCampaign.gd").new();root.add_child(camp);camp.setup(load("res://assets/font/hzk16.fnt"));camp.qa_mode=true
	var state=camp.state;state.data=state.data.duplicate(true);state.data.meta.save_prefix="dlz_qa_native_picker_"
	for i in range(5):state.delete_slot(i);DirAccess.remove_absolute(ProjectSettings.globalize_path(Slots.native_path(state,i)))
	check(state.meta().save_slots==5 and Slots.previews(state)==[{},{},{},{},{}],"five real isolated standard slots")
	state.money=321;camp._show_town(4);camp._open_save_impl(false)
	var native=camp.panel_root
	check(native.palette==Palette.colors("PLACE04") and native.choice==-1,"town picker uses caller PLACE palette")
	move(Vector2(1,302));mouse(Vector2(10,10));await process_frame
	check(not is_instance_valid(camp.panel_root) and int(state.slot_info(4).money)==321,"actual fifth-slot mouse save is one-shot")
	check(FileAccess.get_file_as_bytes(Slots.native_path(state,4)).size()==85072,"strategic save also emits real native28-block format")
	state.money=11;check(camp.load_campaign_slot(4) and state.money==321,"actual saved strategic slot loads")
	state.delete_slot(4);state.money=22;check(camp.load_campaign_slot(4) and state.money==321,"native57 fallback loads without pretending mode150 compatibility")
	var raw:=FileAccess.get_file_as_bytes(Slots.native_path(state,4));raw.encode_u32(0,150)
	var f:=FileAccess.open(Slots.native_path(state,4),FileAccess.WRITE);f.store_buffer(raw);f.close()
	state.money=99;check(not camp.load_campaign_slot(4) and state.money==99,"native150 rejected without mutating live state")
	camp._launch_level(0,false,[-100]);await camp.drain_story();var b=camp.battle;b.set_process(false)
	camp._battle_toolbar("save");check(camp.panel_root.palette==Palette.colors("KUANG04") and b.busy,"battle modal retains live battle palette and blocks input")
	mouse(Vector2(1,1),false,MOUSE_BUTTON_RIGHT);await process_frame;check(not b.busy and camp.panel_root==null,"save cancel restores battle busy state")
	camp._battle_toolbar("exit");check(camp.panel_root is Confirm and camp.panel_root.origin==Vector2(300,200),"battle exit uses original confirmation origin")
	var prompt=camp.panel_root.get_child(2);check(prompt.text=="退出吗？" and prompt.position==Vector2(332,204),"battle prompt native fullwidth question and byte centering")
	var exits:Array=[];camp.exit_requested.connect(func():exits.append(true))
	mouse(Vector2(1,1),true,MOUSE_BUTTON_RIGHT);await process_frame;check(exits.is_empty() and camp.battle==b and not b.busy,"battle exit cancel stays in same battle")
	camp._battle_toolbar("restart");check(camp.panel_root.get_child(2).text=="重来吗？","restart original literal")
	mouse(Vector2(1,1),true,MOUSE_BUTTON_RIGHT);await process_frame;check(camp.battle==b and b.turn==1,"restart cancel leaves live battle untouched")
	camp._battle_toolbar("exit");mouse(Vector2(1,1));await process_frame;check(exits.size()==1,"battle default yes requests title, not app quit")
	for i in range(5):state.delete_slot(i);DirAccess.remove_absolute(ProjectSettings.globalize_path(Slots.native_path(state,i)))
	camp.queue_free();await process_frame;root.get_node("Music").release_playback();OriginalUI.release_native_sfx();await create_timer(0.3).timeout
	print("ORIGINAL_SAVE_PICKER checks=",checks," failures=",failures);quit(1 if failures else 0)
