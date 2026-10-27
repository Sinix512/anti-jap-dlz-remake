extends SceneTree
const Create=preload("res://scripts/ui/OriginalCharacterCreate.gd")
const History=preload("res://scripts/m5/HistorySlideshow.gd")
const GBK=preload("res://scripts/m2/GBK.gd")
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("CREATION_FAIL "+label)
func mouse(point:Vector2,down:bool) -> void:
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.position=point;event.global_position=point
	root.push_input(event,true)
func drag(point:Vector2,left:=true) -> void:
	var event:=InputEventMouseMotion.new();event.position=point;event.global_position=point;event.button_mask=MOUSE_BUTTON_MASK_LEFT if left else 0
	root.push_input(event,true)
func click(point:Vector2) -> void:mouse(point,true);mouse(point,false)
func key() -> void:
	var event:=InputEventKey.new();event.keycode=KEY_ENTER;event.pressed=false;root.push_input(event,true)
func run() -> void:
	var font=load("res://assets/font/hzk16.fnt")
	var m2:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/m2.json"))
	var cfg_path:="user://dlz_config.cfg"
	var config_before:=FileAccess.get_file_as_bytes(cfg_path)
	var c=Create.new();root.add_child(c);c.setup(font,m2.units);c.set_process(false)
	check(c.values()=={"name":"主　角","face":103,"unit":1,"wuli":80,"difficulty":1},"new original defaults independent of CFG")
	check(c.find_children("*","BaseButton",true,false).is_empty() and c.find_children("*","LineEdit",true,false).is_empty() and c.find_children("*","Slider",true,false).is_empty(),"no invented modern controls")
	check(c.faces.all(func(t):return t.get_size()==Vector2(80,100)) and c.armies.all(func(t):return t.get_size()==Vector2(48,48)),"native portraits and static first frames")
	mouse(Vector2(530,100),true);check(c.face_index==0,"portrait DOWN does not select")
	mouse(Vector2(530,100),false);check(c.face_index==5,"portrait UP selects sixth face")
	mouse(Vector2(620,100),false);check(c.face_index==5,"portrait right endpoint exclusive")
	mouse(Vector2(430,260),false);check(c.unit_index==0,"class label is not clickable")
	mouse(Vector2(430,210),false);check(c.unit_index==3,"class sprite UP selects cavalry")
	for v in [60,80,100]:
		var x:int=269+(v-60)*100/40
		mouse(Vector2(x,290),true);check(c.wuli==(80 if v==60 else v-20),"attribute DOWN alone unchanged %d"%v)
		mouse(Vector2(x,290),false);check(c.wuli==v and int(c.values().wuli)+(160-c.wuli)==160,"native attribute UP formula %d"%v)
		check(c.slider_position()==Vector2(261+(v-60)*100/40,283),"native marker formula %d"%v)
	drag(Vector2(319,286));check(c.wuli==100,"drag outside 16px bar does not update")
	drag(Vector2(319,290),false);check(c.wuli==100,"motion without MK_LBUTTON ignored")
	drag(Vector2(319,290));check(c.wuli==80,"left drag inside bar updates")
	drag(Vector2(255,290));check(c.wuli==60,"signed division clamped at left")
	for sample in [[249,0],[363,0],[364,1],[478,1],[479,2],[592,2]]:
		mouse(Vector2(sample[0],380),true);check(c.difficulty==sample[1],"native difficulty DOWN segment %d"%sample[0]);mouse(Vector2(sample[0],380),false)
	mouse(Vector2(593,380),true);check(c.difficulty==2,"difficulty right edge exclusive");mouse(Vector2(593,380),false)
	mouse(Vector2(150,435),true);check(c.pressed_button==0,"original BUTTON22 down state")
	mouse(Vector2(50,90),false);check(not c.name_mode and c.face_index==5 and c.pressed_button==-1,"outside release cancels and does not also select face")
	mouse(Vector2(150,435),false);check(not c.name_mode,"button release without matching down ignored")
	click(Vector2(150,435));check(c.name_mode and c.name_buffer.is_empty(),"change opens original empty name page")
	key();check(c.name_mode and c.name_buffer.is_empty(),"name page has no keyboard accept")
	mouse(Vector2(0,72),true);check(c.name_buffer.is_empty(),"name grid is UP-only")
	mouse(Vector2(0,72),false);check(c.flash_index==0 and c.name_buffer.is_empty(),"name choice holds original 100ms flash")
	c._advance(0.11);check(c.name_buffer==str(c.data.name_groups[0])[0],"native table first character appended")
	for i in range(4):mouse(Vector2(0,72),false);c._advance(0.11)
	check(c.name_buffer.length()==4,"eight GBK bytes means four Chinese characters")
	click(Vector2(490,20));check(c.name_buffer.length()==3,"backspace removes one GBK character")
	var expected:String=c.name_buffer
	click(Vector2(165,20));check(not c.name_mode and c.player_name==expected,"confirm name returns without resetting other choices")
	check(c.face_index==5 and c.unit_index==3 and c.wuli==60 and c.difficulty==2,"name return preserves creation state")
	click(Vector2(150,435));check(c.name_buffer.is_empty(),"reopening clears temporary name")
	click(Vector2(165,20));check(c.player_name==expected,"confirm empty name keeps previous name")
	click(Vector2(150,435));click(Vector2(594,55));check(c.section==22,"fullwidth letter Z selects original last section")
	check(str(c.data.name_groups[22]).length()==324 and str(c.data.name_groups[22]).ends_with("\ue000"),"raw D7FA table cell retained without shifting grid")
	click(Vector2(325,20));check(c.section==21,"previous section")
	click(Vector2(405,20));check(c.section==22,"next section")
	mouse(Vector2(0,72),false);c._advance(0.11);click(Vector2(245,20));check(c.player_name==expected and not c.name_mode,"return discards temporary selection")
	check(GBK.encode("\ue000",4).slice(0,2).hex_encode()=="d7fa" and GBK.decode(PackedByteArray([0xd7,0xfa,0]))=="\ue000","unassigned native cell round trips through save codec")
	var confirms:Array=[];var cancels:Array=[]
	c.confirmed.connect(func(v):confirms.append(v));c.cancelled.connect(func():cancels.append(true))
	click(Vector2(290,435));check(confirms.size()==1 and confirms[0]==c.values(),"matching confirm down/up emits exact original values once")
	click(Vector2(290,435));check(confirms.size()==1,"done gate prevents duplicate campaign creation")
	c.free()
	for i in range(4):
		var campaign=load("res://scripts/m4/Campaign.gd").new();campaign.qa_mode=true;root.add_child(campaign)
		campaign.setup(font,{"name":"阿勇","face":108,"unit":Create.CLASSES[i],"wuli":60,"difficulty":2})
		var h:Dictionary=campaign.state.protagonist
		check(h.name=="阿勇" and h.face==108 and h.bingzhong==Create.CLASSES[i] and h.wuli==60 and h.zhili==100 and campaign.state.difficulty==2,"real campaign creation choices %d"%i)
		check(h.level==1 and h.xp==0 and h.item_slots==[2,3,[100,82,109,82][i],0,0,0,0,0] and h.skill_counts.buji==1 and h.skill_counts.jili==1,"original starting inventory, level and skills %d"%i)
		campaign.queue_free();await process_frame
	var main=load("res://Main.tscn").instantiate();main.qa_mode=true;root.add_child(main);await process_frame
	main._show_character_create();await process_frame
	click(Vector2(420,435));await process_frame;check(main.title_screen!=null and main.campaign==null,"cancel returns to title without creating a campaign")
	main._show_character_create();await process_frame
	click(Vector2(290,435));await process_frame;check(main.menu_root is History and main.campaign==null,"confirm presents original history before committing People0")
	key();check(main.campaign==null,"creation history ignores keyboard shortcut")
	mouse(Vector2(300,200),true);await process_frame
	check(main.campaign!=null and main.campaign.battle!=null and int(main.campaign.battle.level.index)==0,"history left-DOWN submits and launches actual L00")
	check(main.campaign.state.protagonist.name=="主　角" and main.campaign.state.protagonist.bingzhong==1 and main.campaign.state.difficulty==1,"new creation does not inherit old CFG choices")
	check(FileAccess.get_file_as_bytes(cfg_path)==config_before,"creation/name UI never overwrites player CFG")
	main.queue_free();await process_frame;await create_timer(0.2).timeout
	root.get_node("Music").release_playback()
	OriginalUI.release_native_sfx()
	print("ORIGINAL_CREATION checks=",checks," failures=",failures)
	quit(1 if failures else 0)
