extends SceneTree
const Confirm=preload("res://scripts/ui/OriginalConfirm.gd")
const SavePicker=preload("res://scripts/ui/OriginalSavePicker.gd")
var checks:=0
var failures:=0
var camp
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("UI_INPUT_FAIL "+label)
func button_event(point:Vector2,button:int,pressed:bool,double:=false) -> void:
	var e=InputEventMouseButton.new();e.position=point;e.global_position=point;e.button_index=button;e.pressed=pressed;e.double_click=double
	root.push_input(e,true)
func motion(point:Vector2,mask:=0,relative:=Vector2.ZERO) -> void:
	var e=InputEventMouseMotion.new();e.position=point;e.global_position=point;e.button_mask=mask;e.relative=relative
	root.push_input(e,true)
func click(point:Vector2,button:=MOUSE_BUTTON_LEFT,double:=false) -> void:
	motion(point);button_event(point,button,true,double);button_event(point,button,false)
	await process_frame;await process_frame
func drag(from:Vector2,to:Vector2) -> void:
	motion(from);button_event(from,MOUSE_BUTTON_LEFT,true);await process_frame
	motion(from+Vector2(24,0),MOUSE_BUTTON_MASK_LEFT,Vector2(24,0));await process_frame
	motion(to,MOUSE_BUTTON_MASK_LEFT,to-from-Vector2(24,0));await process_frame
	button_event(to,MOUSE_BUTTON_LEFT,false);await process_frame;await process_frame
func find_button(node:Node,label:String):
	if node is Button and node.text==label:return node
	for child in node.get_children():
		var found=find_button(child,label)
		if found!=null:return found
	return null
func press_named(label:String) -> void:
	var dialog=camp.panel_root
	check(dialog is Confirm,"native yes/no confirmation for "+label)
	if dialog is Confirm:
		await click(Vector2(384,268 if label=="取消" else 244))
func run() -> void:
	camp=load("res://scripts/m4/Campaign.gd").new();root.add_child(camp);camp.setup(load("res://assets/font/hzk16.fnt"));camp.qa_mode=true
	var state=camp.state;state.money=10000
	state.data=state.data.duplicate(true);state.data.meta.save_prefix="dlz_qa_ui_input_"
	camp.selected_town=1;camp._open_shop("junxie");await process_frame;await process_frame
	var stock:Array=camp._shop_stock();var iid:=int(stock[0].id);var price:=int(stock[0].record.price)
	var before:int=state.money
	await click(Vector2(48,85),MOUSE_BUTTON_RIGHT)
	check(camp.info_panel!=null,"right-release opens item information")
	check(state.money==before and camp.shop_pending.is_empty(),"information has no purchase side effects")
	await process_frame;await process_frame
	await click(Vector2(48,85),MOUSE_BUTTON_RIGHT)
	check(camp.info_panel==null and camp.shop_pending.is_empty(),"closing info consumes release, no reopen/selection")
	await drag(Vector2(48,85),Vector2(566,230))
	check(state.money==before-price and state.item_count(iid)==1,"real drag shop item to warehouse buys exactly once")
	await click(Vector2(465,170))
	check(camp.shop_mode==2,"warehouse distribution via mouse")
	state.protagonist.item_slots=[0,0,0,0,0,0,0,0]
	await drag(Vector2(48,85),Vector2(48,330))
	if is_instance_valid(camp.panel_root):await press_named("保留")
	check(state.item_count(iid)==0 and state.protagonist.item_slots.has(iid+1),"real drag warehouse to protagonist conserves ownership")
	state.add_item(81,3);camp._render_shop();await process_frame
	before=state.money
	await click(Vector2(566,160),MOUSE_BUTTON_RIGHT,true)
	check(is_instance_valid(camp.panel_root),"right-double sale asks confirmation")
	await press_named("取消")
	check(state.item_count(81)==3 and state.money==before,"cancel bulk sale is nondestructive")
	await click(Vector2(566,160),MOUSE_BUTTON_RIGHT,true)
	await press_named("确定")
	check(state.item_count(81)==0 and state.money==before+int(state.item(81).price)*3*(7-state.difficulty)/10,"confirmed bulk sale original total rounding")
	before=state.money
	var count:int=state.item_count(iid)
	await drag(Vector2(48,85),Vector2(620,460))
	check(state.money==before and state.item_count(iid)==count and camp.shop_pending.is_empty(),"cancelled shop drag restores selection without mutation")
	state.protagonist.mine_slots=[0,0,0,0,0,0,0,0]
	state.add_mine(0,2)
	camp.k04_person=-999;camp.k04_source=-1;camp.k04_held=-1;camp.forge_fuse=0;camp._show_k04_status();await process_frame;await process_frame
	await click(Vector2(48,140),MOUSE_BUTTON_RIGHT)
	check(camp.info_panel==null,"K04 original handler has no person-grid right-click information")
	var mine_count:int=state.mine_count(0)
	await drag(Vector2(48,50),Vector2(620,460))
	check(state.mine_count(0)==mine_count and camp.k04_held==-1 and camp.k04_source==-1,"cancelled K04 drag is nondestructive")
	await drag(Vector2(48,50),Vector2(48,140))
	check(state.mine_count(0)==mine_count-1 and state.protagonist.mine_slots.count(1)==1,"K04 real drag warehouse to protagonist")
	await drag(Vector2(48,50),Vector2(48,140))
	check(state.mine_count(0)==mine_count-2 and state.protagonist.mine_slots.count(1)==2,"K04 repeated drag transfers once per drop")
	await click(Vector2(555,190)) # Native switch enters person-source mode.
	await click(Vector2(48,140))
	check(camp.k04_person==state.PROTAGONIST_PID,"K04 mouse opens protagonist carrying view")
	await drag(Vector2(48,50),Vector2(555,400))
	check(state.mine_count(0)==mine_count-1 and state.protagonist.mine_slots.count(1)==1,"K04 real drag carrying mine back to warehouse")
	before=state.money
	await drag(Vector2(48,50),Vector2(555,335))
	check(state.protagonist.mine_slots.count(1)==0 and state.money==before+int(state.mine(0).price),"K04 real drag to recycling uses original person price")
	for slot in range(32):state.set_person_side(slot,0)
	camp.deploy_selected=[-100];camp._show_deployment(34);await process_frame
	await click(Vector2(270,367));check(camp.deploy_pages==[1,0],"left deployment page is independent")
	await click(Vector2(420,367));check(camp.deploy_pages==[1,1],"right deployment page is independent")
	await click(Vector2(270,367));check(camp.deploy_pages==[0,1],"left previous page preserves right")
	camp._launch_level(0,false,[-100])
	for i in range(150):
		if is_instance_valid(camp.story_player):camp.story_player._finish()
		if is_instance_valid(camp.cutscene):camp.cutscene._finish()
		await process_frame
		if camp.battle_story_queue.is_empty() and not is_instance_valid(camp.story_player):break
	for i in range(5):await process_frame
	var b=camp.battle
	await click(Vector2(220,220),MOUSE_BUTTON_RIGHT)
	var hero=b.unit_by_slot(0)
	var saved_tile:=Vector2i(hero.x,hero.y)
	await click(Vector2(158,16)) # Original toolbar save button.
	check(is_instance_valid(camp.panel_root) and b.busy,"toolbar mouse save opens blocking modal")
	check(camp.panel_root is SavePicker and camp.panel_root.choice==-1,"original save picker starts with no selected slot")
	await click(Vector2(20,170)) # Full-screen hover row0; left-DOWN accepts stored row.
	check(not state.slot_info(0).get("battle_resume",{}).is_empty(),"mouse save writes battle snapshot")
	check(not is_instance_valid(camp.panel_root),"native save closes/restores caller without a modern Close button")
	check(not b.busy,"closing save restores battle input")
	b.camera.force_update_scroll();await process_frame
	await click(b.get_global_transform_with_canvas()*hero.position)
	var destination:Vector2i=b.move_tiles.keys()[0]
	await click(b.get_global_transform_with_canvas()*Vector2(destination.x*48+24,destination.y*48+24))
	for i in range(300):
		await create_timer(0.01).timeout
		if is_instance_valid(camp.story_player):camp.story_player._finish()
		if not b.busy and hero.moved:break
	check(Vector2i(hero.x,hero.y)==destination and destination!=saved_tile,"real mouse move changes saved position")
	await click(Vector2(220,220),MOUSE_BUTTON_RIGHT)
	await click(Vector2(186,16)) # Original toolbar load button.
	check(camp.panel_root is SavePicker and camp.panel_root.load_mode,"native toolbar read mode, not combined manager")
	await click(Vector2(20,170))
	for i in range(10):await process_frame
	b=camp.battle;hero=b.unit_by_slot(0)
	check(Vector2i(hero.x,hero.y)==saved_tile and not hero.moved and not hero.acted,"mouse load restores position and action flags")
	b.camera.force_update_scroll();await process_frame
	await click(b.get_global_transform_with_canvas()*hero.position)
	check(not b.move_tiles.is_empty() and b.move_tiles==b.compute_reachable(hero),"loaded battle mouse selection rebuilds blue range")
	state.delete_slot(0)
	camp.queue_free();await process_frame;await create_timer(0.3).timeout
	print("ORIGINAL_UI_INPUT checks=",checks," failures=",failures)
	quit(1 if failures else 0)
