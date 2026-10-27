extends SceneTree
const Slots=preload("res://scripts/battle/InventorySlots.gd")
const Builder=preload("res://scripts/m4/LevelBuilder.gd")
class Observer extends RefCounted:
	var ticks:=0
	var status_text:=""
	func on_tick() -> void:ticks+=1
	func on_unit_moved(_u) -> void:pass
	func check_end() -> bool:return false
var checks:=0
var failures:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("INVENTORY_FAIL "+label)
func click(point:Vector2,button:=MOUSE_BUTTON_LEFT) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion,true)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=button;event.pressed=pressed
		root.push_input(event,true)
	await process_frame;await process_frame
func run() -> void:
	var camp=load("res://scripts/m4/Campaign.gd").new();root.add_child(camp)
	camp.setup(load("res://assets/font/hzk16.fnt"));camp.qa_mode=true
	var gs=camp.state;gs.set_person_side(1,0)
	var a:Dictionary=gs.protagonist_member();var z:Dictionary=gs.person(1)
	for kind in ["item_slots","mine_slots"]:
		a[kind]=[2,7,2,0,0,0,0,0]
		var before:int=gs.item_count(1) if kind=="item_slots" else gs.mine_count(1)
		var result:Dictionary=gs.return_item(a,2) if kind=="item_slots" else gs.return_mine(a,2)
		var after:int=gs.item_count(1) if kind=="item_slots" else gs.mine_count(1)
		check(result.ok and a[kind]==[7,2,0,0,0,0,0,0] and after==before+1,kind+" return later duplicate removes first matching ID")
		a[kind]=[2,7,2,0,0,0,0,0];z[kind]=[22,0,32,0,0,0,0,0]
		result=gs.transfer_item(a,2,z) if kind=="item_slots" else gs.transfer_mine(a,z,2)
		check(result.ok and a[kind]==[7,2,0,0,0,0,0,0] and z[kind]==[22,2,32,0,0,0,0,0],kind+" transfer first ID and destination fill-then-compact")
		a[kind]=[2,0,12,0,0,0,0,0];z[kind]=[1,1,1,1,1,1,1,1]
		result=gs.transfer_item(a,0,z) if kind=="item_slots" else gs.transfer_mine(a,z,0)
		check(not result.ok and a[kind]==[2,0,12,0,0,0,0,0],kind+" full target never normalizes or consumes source")
		result=gs.return_item(a,1) if kind=="item_slots" else gs.return_mine(a,1)
		check(not result.ok and a[kind]==[2,0,12,0,0,0,0,0],kind+" empty return keeps source holes")
		if kind=="item_slots":gs.add_item(6,1)
		else:gs.add_mine(6,1)
		result=gs.give_item(a,6) if kind=="item_slots" else gs.give_mine(a,6)
		check(result.ok and a[kind]==[2,7,12,0,0,0,0,0],kind+" give fills first hole before stable normalization")
	a.mine_slots=[12,7,12,0,0,0,0,0]
	var money:int=gs.money
	gs.recycle_mine(11,a,2)
	check(a.mine_slots==[7,12,0,0,0,0,0,0] and gs.money==money+int(gs.mine(1).price),"person recycle preserves fuse-price oddity and first-ID removal")
	var holes:Array=[2,0,12,0,0,0,0,0]
	check(not Slots.remove_id(holes,7) and holes==[2,0,12,0,0,0,0,0],"missing helper removal does not normalize")
	camp.selected_town=1;camp._open_shop("zahuo");camp.shop_mode=1;camp.shop_person=-100
	a.item_slots=[2,7,2,0,0,0,0,0];camp.shop_pending={"id":1,"slot":2}
	var count:int=gs.item_count(1);camp._shop_commit("store",-1,true)
	check(a.item_slots==[7,2,0,0,0,0,0,0] and gs.item_count(1)==count+1,"K01 clicked duplicate store uses original first-ID helper")
	a.item_slots=[2,7,2,0,0,0,0,0];z.item_slots=[22,0,32,0,0,0,0,0]
	camp.shop_pending={"id":1,"slot":2};camp._shop_commit("person",1,true)
	check(a.item_slots==[7,2,0,0,0,0,0,0] and z.item_slots==[22,2,32,0,0,0,0,0],"K01 clicked duplicate transfer preserves exact source and target order")
	a.item_slots=[2,7,2,0,0,0,0,0];z.item_slots=[0,0,0,0,0,0,0,0]
	camp._do_transfer(-100,1,"items",2)
	check(a.item_slots==[7,2,0,0,0,0,0,0] and z.item_slots==[2,0,0,0,0,0,0,0],"legacy management transfer passes slot before target")
	a.item_slots=[82,0,91,0,0,0,0,0];a.mine_slots=[2,0,12,0,0,0,0,0]
	camp._open_original_info("person",-100)
	check(a.item_slots==[82,91,0,0,0,0,0,0] and a.mine_slots==[2,12,0,0,0,0,0,0],"strategic person info normalizes owned state not a display clone")
	camp.info_panel.close();await process_frame
	a.item_slots=[2,0,7,0,0,0,0,0];a.mine_slots=[2,0,7,0,0,0,0,0]
	gs.person(32).item_slots=[2,0,7,0,0,0,0,0];gs.person(32).mine_slots=[2,0,7,0,0,0,0,0]
	camp._open_shop("zahuo")
	check(a.item_slots==[2,7,0,0,0,0,0,0] and a.mine_slots==[2,0,7,0,0,0,0,0] and gs.person(32).item_slots[1]==0,"K01 entry normalizes only side0 slots0..31 items")
	camp._show_k04_status()
	check(a.mine_slots==[2,7,0,0,0,0,0,0] and gs.person(32).mine_slots[1]==0,"K04 entry normalizes only side0 slots0..31 mines")
	var world=load("res://scripts/Battle.gd").new();root.add_child(world)
	world.setup(camp.m4,Builder.build(camp.m4,camp.m2,0,[a]),camp.font,{})
	world.fast_sim=true;world.sfx_enabled=false;world.animations_enabled=false;world.set_process(false)
	var hero=world.unit_by_slot(0);world.selected=hero;world.busy=false
	for kind in ["items","mines"]:
		if kind=="items":hero.item_slots=[2,7,2,12,0,0,0,0]
		else:hero.mine_slots=[2,7,2,12,0,0,0,0]
		var consumed:bool=world._consume_inventory(kind,1)
		var bag:Array=hero.item_slots if kind=="items" else hero.mine_slots
		check(consumed and bag==[7,2,12,0,0,0,0,0],"battle "+kind+" consumption removes first match then compacts")
	hero.item_slots=[82,0,91,0,0,0,0,0];hero.mine_slots=[2,0,12,0,0,0,0,0]
	world._open_unit_info()
	check(hero.item_slots==[82,91,0,0,0,0,0,0] and hero.mine_slots==[2,12,0,0,0,0,0,0],"battle person info normalizes actual unit not state_record snapshot")
	# Closing the inspected overlay restores ownership before mouse-driven tests.
	for child in world.get_children():
		if child.get_script()!=null and child.get_script().resource_path.ends_with("OriginalInfo.gd"):child.close()
	await process_frame
	var observer:=Observer.new();world.scenario=observer
	world.busy=false;world.phase="player";hero.acted=false;world.selected=hero
	hero.item_slots=[2,0,82,2,32,94,0,6]
	world._open_item_menu();await process_frame;await process_frame
	var picker=world.action_panel
	var icons:Array=picker.get_children().filter(func(child):return child is TextureRect and child.position.y in [144.0,244.0])
	check(icons.size()==6 and icons.all(func(icon):return icon.texture!=null and icon.texture.get_width()==48),"MENU08 resolves m4 goods fallback and loads all six carried icons")
	check(picker.slots==hero.item_slots and hero.item_slots[1]==0,"MENU08 preserves all eight positions including holes/passive/equipment/duplicates")
	await click(Vector2(270,160))
	check(world.action_panel==picker,"empty item icon cell does not select")
	await click(Vector2(200,200));await click(Vector2(250,160));await click(Vector2(100,100))
	check(world.action_panel==picker,"item text, gap and outside do not select")
	var key:=InputEventKey.new();key.keycode=KEY_SPACE;key.pressed=true;root.push_input(key,true)
	check(world.action_panel==picker,"space is not item-picker confirmation")
	await click(Vector2(350,160))
	check(world.action_panel.entries==["使 用","交 给","丢 弃","察 看"],"equipment is selectable and opens original four actions")
	await click(Vector2(400,300))
	check(world.action_panel==null and world.context_menu!=null and not hero.acted and hero.item_slots[2]==82,"equipment use returns to six actions without consumption")
	world._open_item_menu();await process_frame;await process_frame
	await click(Vector2(200,160));await click(Vector2(400,370))
	check(world.busy and not hero.acted,"view opens original item info without action cost")
	for child in world.get_children():
		if child.get_script()!=null and child.get_script().resource_path.ends_with("OriginalInfo.gd"):child.close()
	check(not world.busy and world.context_menu!=null,"item info close returns six-action menu")
	world._open_item_menu();await process_frame;await process_frame
	await click(Vector2(620,460),MOUSE_BUTTON_RIGHT)
	check(world.action_panel==null and world.context_menu!=null and not hero.acted,"anywhere right-release cancels MENU08 to action menu")
	world._close_context_menu();world.selected=hero;hero.acted=false;hero.set_tile(5,5)
	var enemy=world.unit_by_slot(40);enemy.set_tile(5,4);enemy.item_slots=[22,0,32,0,0,0,0,0]
	hero.item_slots=[2,7,2,0,0,0,0,0]
	world._item_option(1,1)
	check(world.mode=="item_give" and world.native_dark_mask.count(0)==8 and world.native_dark_mask[5*world.map_w+5]!=0,"item give has exactly eight-neighbour mask excluding self")
	await world._execute_item_transfer(Vector2i(4,5))
	check(not hero.acted and hero.item_slots==[2,7,2,0,0,0,0,0],"empty give target preserves inventory and selection")
	await world._execute_item_transfer(Vector2i(5,4))
	check(hero.acted and hero.item_slots==[7,2,0,0,0,0,0,0] and enemy.item_slots==[22,2,32,0,0,0,0,0] and observer.ticks==1,"battle transfer to enemy removes first ID, fills then compacts, consumes one action")
	world.selected=hero;hero.acted=false;hero.item_slots=[2,7,0,0,0,0,0,0];enemy.item_slots=[1,1,1,1,1,1,1,1]
	world._item_option(1,1);await world._execute_item_transfer(Vector2i(5,4))
	check(hero.acted and hero.item_slots==[7,0,0,0,0,0,0,0] and enemy.item_slots==[1,1,1,1,1,1,1,1] and observer.ticks==2,"original full-target battle transfer loses item and still consumes action")
	world.selected=hero;hero.acted=false;hero.item_slots=[2,7,2,0,0,0,0,0]
	await world._discard_item(1)
	check(hero.acted and hero.item_slots==[7,2,0,0,0,0,0,0] and observer.ticks==3,"discard immediately removes first ID and consumes action without confirmation")
	world.selected=hero;hero.acted=false;hero.mine_slots=[12,0,2,12,0,0,0,0]
	world._open_mine_menu()
	var expected:Array=[str(world.data.mines[1].name)+"引",str(world.data.mines[1].name)+"普",str(world.data.mines[1].name)+"引"]
	check(world.action_panel.entries==expected and world.action_panel.frame==Rect2(276,200,88,88),"mine picker preserves original slot order, duplicates and name+suffix with exact frame")
	await click(Vector2(300,268))
	check(world.mine_kind==11 and world.mode=="mine_place" and hero.mine_slots==[12,0,2,12,0,0,0,0],"mine LMB-down selects third duplicate without spending stock")
	world._cancel();world.selected=hero;hero.mine_slots=[2,0,0,0,0,0,0,0]
	world._open_mine_menu()
	check(world.action_panel.frame==Rect2(276,224,88,32) and not world.action_panel.selected_row.visible,"single mine uses original last32 frame without highlight LUT")
	await click(Vector2(300,236),MOUSE_BUTTON_RIGHT)
	check(world.action_panel==null and world.context_menu!=null and not hero.acted,"mine RMB-down cancels without spending action")
	world._close_context_menu();world.selected=hero;hero.acted=false;hero.bingzhong=4;hero.data.bingzhong=4;hero.data.level=1;hero.item_slots=[62,0,0,0,0,0,0,0]
	await world._use_manual_item(61)
	check(hero.acted and hero.item_slots[0]==62 and observer.ticks==4 and world.action_panel==null,"incompatible manual silently costs action, never item")
	world.selected=hero;hero.acted=false;hero.item_slots=[69,0,0,0,0,0,0,0]
	world._use_manual_item(68);await process_frame;await process_frame
	check(world.busy and not hero.acted and world.action_panel.skip_left,"low-level manual shows acknowledgement notice, not automatic defeat notice")
	await click(Vector2(200,330))
	check(world.busy and not hero.acted and world.action_panel!=null,"43D56B ignores first left release")
	await click(Vector2(200,330))
	check(hero.acted and hero.item_slots[0]==69 and observer.ticks==5,"low-level notice acknowledgement ends action without consuming book")
	world.selected=hero;hero.acted=false;hero.item_slots=[64,0,0,0,0,0,0,0]
	world._use_manual_item(63);await process_frame;await process_frame
	await click(Vector2(400,268))
	check(hero.acted and hero.bingzhong==4 and hero.item_slots[0]==64 and observer.ticks==6,"manual confirmation no consumes action but not item/class")
	world.selected=hero;hero.acted=false;hero.hp=1000;hero.item_slots=[64,7,64,0,0,0,0,0];hero.skill_counts.gunmu=45
	world._use_manual_item(63);await process_frame;await process_frame
	await click(Vector2(400,244))
	check(world.busy and not hero.acted and hero.bingzhong==1 and hero.hp==hero.max_hp and hero.item_slots==[7,64,0,0,0,0,0,0] and hero.skill_counts.gunmu==45,"successful direct class change clamps HP, preserves practice and consumes first book")
	var release:=InputEventKey.new();release.keycode=KEY_ENTER;release.pressed=false;root.push_input(release,true);await process_frame
	check(hero.acted and not world.busy and observer.ticks==7,"success notification waits for any key release before finishing action")
	world.selected=hero;hero.acted=false;hero.bingzhong=4;hero.data.bingzhong=4;hero.data.level=15;hero.hp=1000;hero.item_slots=[69,7,69,0,0,0,0,0]
	world._use_manual_item(68);await process_frame;await process_frame
	await click(Vector2(400,244))
	check(world.busy and hero.bingzhong==5 and hero.hp==1000 and hero.hp>hero.max_hp and hero.item_slots==[7,69,0,0,0,0,0,0],"promotion branch deliberately preserves over-max HP and first-ID book order")
	await click(Vector2(200,330),MOUSE_BUTTON_RIGHT)
	check(hero.acted and not world.busy and observer.ticks==8,"right release acknowledges class-change notification")
	a.bingzhong=4;a.level=15;a.hp=1000;a.item_slots=[69,7,69,0,0,0,0,0]
	var promoted:Dictionary=gs.promote(a,68)
	check(promoted.ok and a.bingzhong==5 and a.hp==1000 and a.item_slots==[7,69,0,0,0,0,0,0],"strategic promotion shares no-clamp branch and stable first-ID consumption")
	world.queue_free();camp.queue_free();await process_frame;await process_frame
	var music=root.get_node_or_null("Music")
	if music!=null:music.stop();music.stream=null
	await create_timer(0.2).timeout
	print("ORIGINAL_INVENTORY checks=",checks," failures=",failures)
	quit(1 if failures else 0)
