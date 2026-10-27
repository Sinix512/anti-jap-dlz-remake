extends SceneTree
var failures:=0
var checks:=0
var camp
func _initialize() -> void:call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("ECONOMY_FAIL "+message)
func run() -> void:
	camp=load("res://scripts/m4/Campaign.gd").new();root.add_child(camp);camp.setup(load("res://assets/font/hzk16.fnt"));camp.qa_mode=true
	var state=camp.state
	state.money=10000;state.set_person_side(1,0)
	camp.selected_town=1
	camp._open_shop("junxie")
	var stock:Array=camp._shop_stock()
	check(not stock.is_empty(),"actual town merchandise")
	var item:Dictionary=stock[0]
	var iid:=int(item.id)
	var price:=int(item.record.price)
	var before:int=state.money
	camp._shop_pick(item);camp._shop_commit("store",-1,false)
	check(state.money==before-price and state.item_count(iid)==1,"buy directly into warehouse")
	camp._shop_pick(item)
	var slots_before:Array=state.protagonist.item_slots.duplicate()
	camp._shop_commit("person",-100,false)
	if not state.item_compatible(state.protagonist,iid):
		check(state.money==before-price and state.protagonist.item_slots==slots_before,"incompatible prompt no side effects")
		camp._close_panel();camp._shop_commit("person",-100,true)
	check(state.money==before-price*2 and state.protagonist.item_slots.has(iid+1),"buy into person after confirmation")
	camp._shop_mode(1);camp.shop_person=-100
	var source:Array=camp._shop_stock()
	var found:Dictionary={}
	for record in source:
		if int(record.id)==iid:found=record
	camp._shop_pick(found);camp._shop_commit("person",1,true)
	check(not state.protagonist.item_slots.has(iid+1) and state.person(1).item_slots.has(iid+1),"person exchange conserves ownership")
	camp.shop_person=1
	for record in camp._shop_stock():
		if int(record.id)==iid:camp._shop_pick(record);break
	var money_before:int=state.money
	camp._shop_commit("sell",-1,false)
	check(state.money==money_before+price*(7-state.difficulty)/10 and not state.person(1).item_slots.has(iid+1),"person sale original difficulty price")
	camp._shop_mode(2)
	for record in camp._shop_stock():
		if int(record.id)==iid:camp._shop_pick(record);break
	camp._shop_commit("person",-100,true)
	check(state.item_count(iid)==0 and state.protagonist.item_slots.has(iid+1),"warehouse distribution not copy")
	state.protagonist.item_slots=[1,2,3,4,5,6,7,8]
	camp._shop_mode(0);camp._shop_pick(item)
	money_before=state.money;camp._shop_commit("person",-100,true)
	check(state.money==money_before,"full bag rejects without charging")
	for code in [0,10,20,30]:state.add_mine(code,1)
	camp.k04_person=-999;camp._show_k04_status();camp._k04_pick(2,20);camp._k04_target(-100)
	check(state.mine_count(20)==0 and state.protagonist.mine_slots.has(21),"K04 packed timed fuse to bag")
	camp.k04_person=-100
	var index:int=state.protagonist.mine_slots.find(21)
	camp._k04_pick(index,20);camp._k04_target(1)
	check(not state.protagonist.mine_slots.has(21) and state.person(1).mine_slots.has(21),"K04 person transfer conserves fuse")
	camp.k04_person=1;index=state.person(1).mine_slots.find(21)
	camp._k04_pick(index,20);camp._k04_store()
	check(state.mine_count(20)==1 and not state.person(1).mine_slots.has(21),"K04 return to warehouse")
	camp._show_deployment(0)
	check(camp.deploy_selected==[-100],"K00 forced hero retained")
	camp._toggle_deploy(-100,0)
	check(camp.deploy_selected==[-100],"K00 forced hero cannot remove")
	# JSON-loaded zero slots must remain integer-searchable and usable.
	state.person(1).item_slots=[0,0,0,0,0,0,0,0]
	state.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	state.add_item(1,1)
	check(state.give_item(state.person(1),1).ok and state.person(1).item_slots.has(2),"JSON empty bag accepts distribution")
	check(state.m4_level(0).deployment.forced_slots.has(0),"setup_m4 integer IDs")
	# Batch sale rounds the total per kind, and preserves the original ID80 split.
	camp.shop_kind="junxie";camp.shop_mode=2
	state.add_item(81,3);state.add_item(80,2)
	var count:int=state.item_count(81)
	money_before=state.money
	camp._shop_bulk_sell()
	check(state.item_count(81)==0 and state.item_count(80)==2 and state.money==money_before+int(state.item(81).price)*count*(7-state.difficulty)/10,"bulk military 81..155 and per-kind rounding")
	camp.shop_kind="zahuo";camp._shop_bulk_sell()
	check(state.item_count(80)==0,"bulk grocery includes ID80")
	camp._open_original_info("item",1)
	var info=camp.info_panel
	await process_frame;await process_frame
	info.close()
	check(camp.info_panel==null,"info close clears reference synchronously")
	camp._open_original_info("person",-100)
	check(camp.info_panel!=null and camp.info_panel!=info,"info may reopen same frame safely")
	camp.info_panel.close();await process_frame
	for slot in range(32):state.set_person_side(slot,0)
	camp._show_deployment(34)
	for pid in [20,3,2]:camp._toggle_deploy(pid,34)
	camp.deployment_screen.queue_redraw()
	check(camp.deploy_selected==[-100,20,3,2],"K00 redraw preserves right-list order")
	camp._deploy_page(0,34);camp._deploy_page(1,34)
	check(camp.deploy_pages==[1,1],"K00 independent two-page controls")
	var members:Array=[]
	for slot in range(40):members.append(state.person(slot))
	var level:Dictionary=load("res://scripts/m4/LevelBuilder.gd").build(camp.m4,camp.m2,40,members,false,-1,[-100,2,1])
	var deployed:Dictionary={}
	for unit in level.units:
		if int(unit.slot)<3:deployed[int(unit.slot)]=unit
	check(deployed[2].x==4 and deployed[2].y==59 and deployed[1].x==4 and deployed[1].y==58,"L40 selection order and own-special collision offsets")
	check(deployed[0].direction==0 and deployed[1].direction==0,"original Special deployment facing")
	camp.queue_free();camp=null;state=null
	await process_frame;await process_frame
	var music=root.get_node_or_null("Music")
	if music!=null:music.stop();music.stream=null
	await create_timer(0.2).timeout
	print("NATIVE_ECONOMY checks=",checks," failures=",failures)
	quit(1 if failures else 0)
