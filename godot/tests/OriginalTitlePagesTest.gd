extends SceneTree
const Page=preload("res://scripts/ui/OriginalTitlePages.gd")
const Scores=preload("res://scripts/ui/OriginalHighScores.gd")
var checks:=0
var failures:=0
var closed:=0
var load_events:=0
var exits:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("TITLE_PAGE_FAIL "+label)
func mouse(down:bool,button:int=MOUSE_BUTTON_LEFT) -> void:
	var e:=InputEventMouseButton.new();e.position=Vector2(20,20);e.global_position=e.position;e.pressed=down;e.button_index=button;root.push_input(e,true)
func key(down:bool) -> void:
	var e:=InputEventKey.new();e.keycode=KEY_SPACE;e.pressed=down;root.push_input(e,true)
func page(mode:String):
	var p=Page.new();root.add_child(p);p.setup(load("res://assets/font/hzk16.fnt"),mode);p.set_process(false)
	p.closed.connect(func():closed+=1);p.exit_confirmed.connect(func():exits+=1);p.load_ready.connect(func():load_events+=1)
	return p
func run() -> void:
	var rows:=Scores.defaults()
	check(rows.size()==10 and rows[0]=={"name":"英  雄","score":3600} and rows[9].score==3150,"ten source defaults, ASCII double spaces")
	check(Scores.insert_result(rows,"阿勇",-1)[0].score==-1,"unsigned32 FFFFFFFF ranks first, but signed decimal remains -1")
	var raw:=Scores.encode_table(rows)
	check(raw.size()==200 and raw.slice(0,7).hex_encode()=="d3a22020d0db00" and raw.decode_s32(16)==3600 and raw.decode_s32(196)==3150,"native 20-byte interleaved LE records")
	var inserted:=Scores.insert_result(rows,"阿勇",3550)
	check(inserted[1].name=="英  雄" and inserted[2].name=="阿勇" and inserted[3].score==3500,"strict greater inserts after equal score")
	check(Scores.insert_result(rows,"阿勇",0)[9].score==0,"below all scores still overwrites tenth row")
	check(Scores.insert_result(rows,"阿勇",4000)[0].name=="阿勇" and rows[0].name=="英  雄","top insert leaves source table unchanged")
	var path:="res://../out/test_title_hiscore.dat"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(Scores.read_table(path)==rows,"missing file gives original defaults")
	check(Scores.record_result("阿勇",3550,path) and FileAccess.get_file_as_bytes(path).size()==200,"real isolated persistence writes 200 bytes")
	check(Scores.read_table(path)==inserted,"native GBK persistent table round trips")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var p=page("scores")
	check(p.background.get_size()==Vector2(640,480) and p.rows.size()==10,"score page has BG01 and ten native rows")
	check(p.find_children("*","BaseButton",true,false).is_empty(),"score page has no invented close button")
	mouse(true);key(false);mouse(false,MOUSE_BUTTON_RIGHT)
	check(closed==0,"score DOWN/key-UP/right-UP do not close")
	mouse(false);check(closed==1 and p.done,"score LEFT-UP closes once");key(true);check(closed==1,"score done gate")
	p.free();p=page("scores");key(true);check(closed==2,"score any KEYDOWN closes");p.free()
	p=page("supporters")
	check(p.counter==0 and p.credits.get_size()==Vector2(640,7562),"ZYB starts with its first480 rows")
	p._process(0.499);check(p.counter==0 and p.entry_hold>0.0,"ZYB source500ms entry wait holds first frame")
	p._process(0.056);check(p.counter==1 and p.entry_hold==0.0,"ZYB first55ms shift begins after entry500ms")
	for i in range(3540):p.tick()
	check(p.counter==3541 and not p.done and closed==2,"3541 native two-row shifts, no automatic timeout")
	for i in range(5):p.tick()
	check(p.counter==3541,"ZYB stops on exact last frame")
	key(false);mouse(false,MOUSE_BUTTON_RIGHT);check(not p.done,"ZYB key-UP/right-UP ignored")
	key(true);check(closed==3,"ZYB KEYDOWN returns");p.free()
	p=page("exit")
	for i in range(10):p.tick()
	check(p.counter==10 and p.confirm==null,"exit waits through ten timer messages")
	mouse(false);key(true);check(exits==0 and closed==3,"exit transition does not use title UP or keyboard shortcuts")
	p.tick();check(p.waiting and p.confirm!=null and p.confirm.origin==Vector2(320,200),"eleventh message opens original MENU03 at320,200")
	check(not p.done and exits==0,"rest does not immediately quit")
	mouse(true,MOUSE_BUTTON_RIGHT);check(closed==4 and exits==0,"original cancel returns to title, not process exit");p.free()
	p=page("exit");for i in range(11):p.tick()
	mouse(true);check(exits==1 and p.done,"yes row default confirms via LEFT-DOWN");p.free()
	p=page("load");for i in range(10):p.tick()
	check(load_events==0,"read transition waits ten ticks on BG01")
	p.tick();p.tick();check(load_events==1 and p.waiting,"read selector requested once after tick11");p.free()
	var main=load("res://Main.tscn").instantiate();main.qa_mode=true;root.add_child(main);await process_frame
	main.title_screen.set_process(false)
	var e:=InputEventMouseButton.new();e.position=Vector2(320,210);e.global_position=e.position;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=false;root.push_input(e,true);await process_frame
	check(main.menu_root is Page and main.menu_root.mode=="scores" and not main.menu_root.done,"actual title battle-hero row enters scores, not drill or immediate close")
	mouse(false);await process_frame;check(main.title_screen!=null and main.menu_root==null,"actual score release returns to original title")
	main._show_supporters();await process_frame
	check(main.menu_root.mode=="supporters" and main.bgm.current_scene==38,"actual support row uses ZYB and scene38")
	key(true);await process_frame;check(main.title_screen!=null and main.bgm.current_scene==53,"support return restores title scene53")
	main._confirm_exit();main.menu_root.set_process(false);for i in range(11):main.menu_root.tick()
	mouse(true,MOUSE_BUTTON_RIGHT);await process_frame;check(main.title_screen!=null,"actual exit cancel returns without quitting")
	main.free_state.data=main.free_state.data.duplicate(true);main.free_state.data.meta.save_prefix="dlz_qa_title_read_"
	main.free_state.money=456;main.free_state.save_slot(4)
	main._continue_campaign();main.menu_root.set_process(false)
	for i in range(10):main.menu_root.tick()
	check(main.campaign==null and main.menu_root.get_child_count()==0,"title read wrapper does not create campaign during delay")
	main.menu_root.tick();await process_frame
	var picker=main.menu_root.get_child(0)
	check(picker.choice==-1 and picker.load_mode and not picker.previews[4].is_empty(),"title opens shared five slots, not latest save auto-continue")
	var move:=InputEventMouseMotion.new();move.position=Vector2(10,302);move.global_position=move.position;root.push_input(move,true)
	mouse(true);await process_frame
	check(main.campaign!=null and main.campaign.state.money==456 and main.menu_root==null,"title fifth-slot MOVE/DOWN loads real chosen state")
	main.free_state.delete_slot(4)
	main.queue_free();await process_frame;root.get_node("Music").release_playback();OriginalUI.release_native_sfx();await create_timer(0.3).timeout
	print("ORIGINAL_TITLE_PAGES checks=",checks," failures=",failures);quit(1 if failures else 0)
