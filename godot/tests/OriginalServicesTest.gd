extends SceneTree
const Confirm=preload("res://scripts/ui/OriginalConfirm.gd")
const Quantity=preload("res://scripts/ui/OriginalQuantity.gd")
var checks:=0
var failures:=0
var c
var s
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("SERVICE_FAIL "+label)
func mouse(point:Vector2,down:bool,button:=MOUSE_BUTTON_LEFT,double:=false) -> void:
	var e:=InputEventMouseButton.new();e.position=point;e.global_position=point;e.button_index=button;e.pressed=down;e.double_click=double;root.push_input(e,true)
func motion(point:Vector2) -> void:
	var e:=InputEventMouseMotion.new();e.position=point;e.global_position=point;root.push_input(e,true)
func click(point:Vector2) -> void:
	motion(point);mouse(point,true);mouse(point,false)
func run() -> void:
	var fade=preload("res://scripts/ui/OriginalPaletteFade.gd")
	check(fade.colors_at([0,1,4,128,252],1,false)==[0,0,0,124,248],"native fade out saturates4 per component")
	check(fade.colors_at([0,1,4,128,252],32,true)==[0,1,4,128,128],"native fade in approaches target4 per component")
	check(fade.colors_at([252,128,0],63,false)==[0,0,0] and fade.colors_at([252,128,0],64,false)==[0,0,0],"native63 black64 redundant write")
	c=load("res://scripts/m4/Campaign.gd").new();root.add_child(c);c.setup(load("res://assets/font/hzk16.fnt"));c.qa_mode=true;s=c.state
	# This fixture retains the native input contract; modern defaults have their
	# own real-input coverage in ShopConvenienceTest/ShopQuantityTest.
	c.shop_convenience_enabled=false
	for i in range(22):s.set_person_side(i,0)
	s.money=10000;c.selected_town=1;c._open_shop("junxie");await process_frame
	check(c.shop_person==-100 and c.shop_people_page==0 and c.shop_mode==0,"K01 enter first original roster person")
	c.shop_people_page=1;c.shop_person=2
	mouse(Vector2(465,120),true)
	check(c.shop_mode==1 and c.shop_people_page==0 and c.shop_person==-100,"mode changes immediately on DOWN and resets people")
	mouse(Vector2(620,460),false);check(c.shop_mode==1,"mode DOWN not rolled back on outside UP")
	c.shop_people_page=1;c.shop_person=2;mouse(Vector2(465,120),true);mouse(Vector2(620,460),false)
	check(c.shop_people_page==1 and c.shop_person==2,"already selected mode preserves source/page")
	mouse(Vector2(465,170),true);check(c.shop_mode==2 and c.shop_people_page==0 and c.shop_item_page==0,"warehouse mode resets pages on DOWN");mouse(Vector2(620,460),false)
	c._shop_mode(0)
	var item:Dictionary=c._shop_stock()[0];var iid:=int(item.id);var money:int=s.money
	check(not c.service_screen.shop_stock_at(Vector2(79,151)).is_empty(),"K01 full56x120 cell includes gap/right/bottom")
	mouse(Vector2(79,151),true);check(not c.shop_pending.is_empty() and s.money==money,"source DOWN grabs but never charges")
	motion(Vector2(140.75,170.5));check(c.service_screen.drag_point==Vector2(116,146),"high-DPI fractional motion uses native integer pixels, no half-pixel icon sampling")
	motion(Vector2(-500,900));check(c.service_screen.drag_point==Vector2(0,431),"drag half-icon clamp0..591/431")
	mouse(Vector2(620,460),false);check(c.shop_pending.is_empty() and c.service_screen.drag.is_empty() and s.money==money,"invalid UP clears source silently")
	click(Vector2(48,330));check(c.shop_pending.is_empty() and s.money==money and c.shop_person==-100,"two-click convenience is gone")
	mouse(Vector2(48,85),true);mouse(Vector2(566,230),false)
	check(s.money==money-int(item.record.price) and s.item_count(iid)==1,"DOWN-UP buys into warehouse once")
	mouse(Vector2(48.75,85.5),true);check(c.service_screen.drag_point==Vector2(24,61),"source grab also snaps to integer original half-icon offset");mouse(Vector2(620,460),false)
	c._shop_mode(2);s.protagonist.item_slots=[1,1,1,1,1,1,1,1];money=s.money
	mouse(Vector2(48,85),true);mouse(Vector2(48,330),false)
	check(s.money==money and s.item_count(iid)==1 and c.shop_pending.is_empty() and not is_instance_valid(c.panel_root),"full bag drop silent and cancelled")
	c._shop_mode(1);mouse(Vector2(100,330),true)
	check(c.shop_person==1,"person source selects on DOWN in exchange mode");mouse(Vector2(620,460),false)
	c._shop_mode(0);mouse(Vector2(164,330),true);mouse(Vector2(164,330),false)
	check(c.shop_person==-100,"buy mode empty person click does not change source")
	c._shop_mode(2);s.add_item(81,3);var batch_count:int=s.item_count(81);c._render_shop();mouse(Vector2(560,150),true,MOUSE_BUTTON_RIGHT,true)
	check(c.panel_root is Confirm,"right-double warehouse sale opens native MENU03")
	mouse(Vector2(0,0),true,MOUSE_BUTTON_RIGHT);check(not is_instance_valid(c.panel_root) and s.item_count(81)==batch_count,"native NO/cancel restores service with no sale")
	c._open_shop("material");await process_frame
	mouse(Vector2(30,40),false)
	check(c.panel_root is Quantity,"material LEFT-UP opens quantity without DOWN")
	var q=c.panel_root;var maximum:int=q.maximum
	check(q.quantity==0 and maximum==mini(1000/int(s.material(0).price),s.money/int(s.material(0).price)),"quantity initial zero/original money1000 cap")
	motion(Vector2(320,450));check(q.quantity==maximum/2,"quantity MOVE ignores y")
	mouse(Vector2(320,450),true);check(c.panel_root==q,"quantity DOWN never accepts")
	motion(Vector2(383,-50));check(q.quantity==maximum,"quantity x383 saturates max")
	money=s.money;mouse(Vector2(-100,900),false,MOUSE_BUTTON_RIGHT)
	check(not is_instance_valid(c.panel_root) and s.money==money,"right-UP anywhere cancels quantity")
	mouse(Vector2(30,40),false);q=c.panel_root;motion(Vector2(255,450));check(q.quantity==0,"quantity x<256 is zero")
	mouse(Vector2(0,470),false);check(s.money==money,"left-UP accepts current zero anywhere")
	mouse(Vector2(30,40),false);q=c.panel_root;maximum=q.maximum;motion(Vector2(320,450));var before:int=s.material_count(0);mouse(Vector2(10,470),false)
	check(s.material_count(0)==before+maximum/2 and s.money==money-maximum/2*int(s.material(0).price),"quantity actual purchase exact and closes")
	for i in range(4):s.script_globals["0x%x"%(0x95eaf8+i*4)]=1
	for i in range(10):s.script_globals["0x%x"%(0x95eb08+i*4)]=1;s.add_material(i,20000)
	c.native_service_timer_count=77
	s.money=100000;c.forge_fuse=3;c.forge_kind=8;c.forge_quantity=12;c._open_forge()
	check(c.forge_fuse==0 and c.forge_kind==0 and c.forge_quantity==0,"K03 new entry resets all selections")
	check(c.service_screen.timer_count==77,"K03 new entry preserves global timer113 count")
	c.service_screen.timer_count=0
	s.add_mine(0,65535)
	check(c._forge_max()==mini(9999,s.material_count(6)/15),"K03 native9999/resource maximum ignores existing65535-stock")
	s.add_mine(0,-s.mine_count(0))
	c._forge_adjust(2);var screen=c.service_screen
	mouse(Vector2(30,60),false);check(c.forge_quantity==2,"same selected mine UP preserves quantity")
	mouse(Vector2(40,140),false);check(c.forge_quantity==2,"same selected fuse UP preserves quantity")
	mouse(Vector2(141,60),false);check(c.forge_kind==1 and c.forge_quantity==0 and c.service_screen==screen,"K03 UP icon gap selects and redraw preserves screen")
	mouse(Vector2(200,16),false);check(c.forge_kind==1,"name outside icon row does not select")
	s.script_globals["0x95eb10"]=0;mouse(Vector2(150,60),false);check(c.forge_kind==1,"locked mine cannot be selected")
	mouse(Vector2(120,230),false);check(c.forge_fuse==3 and c.forge_quantity==0,"fuse graphic UP selects independently of DOWN")
	c._set_forge_fuse(0);c._set_forge_kind(0);c._forge_adjust(2);screen.set_process(false);screen.timer_count=100
	mouse(Vector2(500,160),true);check(screen.timer_count==100 and c.forge_quantity==2,"plus DOWN arms without reset/single step")
	screen.timer113();check(c.forge_quantity==2,"odd timer no repeat");screen.timer113();check(c.forge_quantity==3,"idle global count yields next even repeat")
	mouse(Vector2(620,460),false);check(screen.timer_count==0 and c.forge_quantity==3 and screen.pressed.is_empty(),"outside UP resets timer/arm without extra step")
	mouse(Vector2(500,160),true)
	for i in range(31):screen.timer113()
	check(c.forge_quantity==3,"repeat waits count>30")
	screen.timer113();check(c.forge_quantity==4,"timer32 repeats once");mouse(Vector2(500,160),false)
	check(c.forge_quantity==5 and screen.timer_count==0,"matched plus UP adds single step and resets timer")
	var stock_before:int=s.mine_count(0);c._forge_reset();click(Vector2(560,200))
	check(s.mine_count(0)==stock_before and c.forge_quantity==0,"q0 make remains ordinary button/no transaction")
	c._forge_adjust(2);click(Vector2(560,200));check(s.mine_count(0)==stock_before+2 and c.forge_quantity==0,"manufacture adds exact quantity and clears")
	c._set_forge_fuse(3);c._forge_adjust(2);click(Vector2(450,245));check(not screen.enabled and c.service_screen==screen,"K03 equip waits native200ms before leaving")
	await create_timer(0.25).timeout;await process_frame
	check(c.mode=="mines" and c.k04_person==-999 and c.k04_page==0 and c.k04_source==-1,"K04 true entry resets independent page/source")
	click(Vector2(48,140));check(c.k04_person==-999,"warehouse empty person click no action")
	mouse(Vector2(48,140),false,MOUSE_BUTTON_RIGHT);check(not is_instance_valid(c.info_panel),"K04 has no person right-info")
	c._k04_fuse(-1);check(c.k04_page==0,"previous fuse clamps0")
	for i in range(5):c._k04_fuse(1)
	check(c.k04_page==3,"next fuse clamps3 not circular")
	click(Vector2(550,190));check(c.k04_person==-100 and c.k04_page==0,"mode switch first roster person and zero page")
	c._k04_fuse(1);check(c.k04_page==0,"person mode arrows cannot page")
	mouse(Vector2(110,140),false);check(c.k04_person==1,"person source selected on UP without DOWN")
	click(Vector2(550,190));check(c.k04_person==-999 and c.k04_page==0,"switch back restores warehouse0")
	s.add_mine(0,2);s.protagonist.mine_slots=[0,0,0,0,0,0,0,0]
	check(not c.service_screen.mine_at(Vector2(77,81)).is_empty() and c.service_screen.mine_at(Vector2(30,16)).is_empty(),"K04 full56px icon cell only")
	var mines:int=s.mine_count(0);mouse(Vector2(77,81),true);check(s.mine_count(0)==mines and c.k04_held==0,"K04 DOWN no inventory change")
	mouse(Vector2(48,140),false);check(s.mine_count(0)==mines-1 and s.protagonist.mine_slots.has(1) and c.k04_held==-1,"K04 actual drop transfer/cancel source")
	mouse(Vector2(30,50),true);mouse(Vector2(620,460),false);check(s.mine_count(0)==mines-1 and c.k04_held==-1,"invalid K04 drop cancelled silently")
	click(Vector2(550,190));mouse(Vector2(30,50),true);mouse(Vector2(48,140),false)
	check(s.protagonist.mine_slots.has(1) and c.k04_held==-1,"person cannot transfer to self")
	click(Vector2(550,230));check(c.mode=="forge" and c.forge_kind==0 and c.forge_fuse==0 and c.forge_quantity==0,"K04 back truly reenters K03 defaults")
	c.queue_free();c=null;s=null;await process_frame;await process_frame
	OriginalUI.release_native_sfx();root.get_node("Music").release_playback();await create_timer(0.2).timeout
	print("ORIGINAL_SERVICES checks=",checks," failures=",failures);quit(1 if failures else 0)
