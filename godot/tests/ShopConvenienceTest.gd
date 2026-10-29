extends SceneTree
## Isolated actual-input integration checks; fresh GameState, no save reads/writes.
## Production click/drag/quantity handlers are never called directly by a test.
const Confirm=preload("res://scripts/ui/OriginalConfirm.gd")
const Notice=preload("res://scripts/ui/OriginalNotice.gd")
const OUT="res://../out/evidence/shop_convenience295_20261029"
const GOODS=Vector2(48,84)
const PERSON=Vector2(48,330)
const SECOND_PERSON=Vector2(112,330)
const STORE=Vector2(566,230)
const SELL=Vector2(566,160)
const NOWHERE=Vector2(410,286)
var c
var checks:=0
var failures:=0
var rows:Array=[]
var input_events:=0
var transforms:Array=[]
var evidence_dir:String=OUT
var continuous_sell_cases:=0
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1;rows.append({"ok":ok,"label":label})
	if not ok:failures+=1;push_error("SHOP_CONVENIENCE "+label)
func settle(frames:=2) -> void:
	for i in range(frames):await process_frame
func pointer(at:Vector2,down:bool,button:=MOUSE_BUTTON_LEFT,double_click:=false) -> void:
	var e:=InputEventMouseButton.new()
	e.position=root.get_final_transform()*at;e.global_position=e.position
	e.button_index=button;e.pressed=down;e.double_click=double_click
	Input.parse_input_event(e);Input.flush_buffered_events();input_events+=1
func motion(at:Vector2,held:=false) -> void:
	var e:=InputEventMouseMotion.new()
	e.position=root.get_final_transform()*at;e.global_position=e.position
	e.button_mask=MOUSE_BUTTON_MASK_LEFT if held else 0
	Input.parse_input_event(e);Input.flush_buffered_events();input_events+=1
func click(at:Vector2,button:=MOUSE_BUTTON_LEFT,double_click:=false) -> void:
	motion(at);pointer(at,true,button,double_click);await settle()
	pointer(at,false,button);await settle()
func key(code:int,unicode:=0,ctrl:=false) -> void:
	for down in [true,false]:
		var e:=InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.unicode=unicode;e.pressed=down
		# macOS LineEdit uses Command+A; Control+A moves to the line start.
		e.ctrl_pressed=ctrl and not OS.has_feature("macos");e.meta_pressed=ctrl and OS.has_feature("macos")
		Input.parse_input_event(e);Input.flush_buffered_events();input_events+=1;await settle(1)
func wheel(at:Vector2,down:bool) -> void:
	await click(at,MOUSE_BUTTON_WHEEL_DOWN if down else MOUSE_BUTTON_WHEEL_UP)
func drag_to(from:Vector2,to:Vector2,with_motion:=true) -> void:
	motion(from);pointer(from,true);await settle()
	if with_motion:motion(from.lerp(to,.5),true);await settle();motion(to,true);await settle()
	pointer(to,false);await settle()
func bag_count(pid:int,iid:int) -> int:
	var member=c.state.deploy_member(pid);var count:=0
	if member!=null:
		for raw in member.item_slots:
			if int(raw)==iid+1:count+=1
	return count
func assets() -> Dictionary:
	return {"money":int(c.state.money),"items":c.state.items.duplicate(true),"materials":c.state.materials.duplicate(true),"bags":c._shop_roster().map(func(p):return {"pid":p.pid,"bag":p.item_slots.duplicate()})}
func pending_clear(label:String) -> void:
	check(c.shop_pending.is_empty() and c.service_screen.drag.is_empty(),label+" clears selection/drag")
func text_of(node:Node) -> String:
	var result:=str(node.text) if node is Label or node is Button else ""
	for child in node.get_children():result+=" "+text_of(child)
	return result
func notice_has(word:String,label:String) -> void:
	check(is_instance_valid(c.panel_root) and c.panel_root is Notice and text_of(c.panel_root).contains(word),label)
func close_notice() -> void:
	if is_instance_valid(c.panel_root):await click(Vector2(620,450),MOUSE_BUTTON_RIGHT)
func empty_bags() -> void:
	for slot in range(32):
		c.state.set_person_side(slot,0 if slot<22 else 1)
		var p:Dictionary=c.state.person(slot)
		p.item_slots=[0,0,0,0,0,0,0,0];p.bingzhong=1
func fixture(kind:="zahuo",warehouse:=false) -> void:
	if is_instance_valid(c.info_panel):c.info_panel.close();await settle()
	c._close_panel();c.state.money=10000;c.state.items.clear();c.state.materials.clear();empty_bags()
	c.selected_town=1;c._open_shop(kind,warehouse);await settle()
func first_item() -> int:return int(c._shop_stock()[0].id)
func select_source(label:String) -> int:
	var iid:=first_item();var before:=assets()
	await click(GOODS)
	check(not c.shop_pending.is_empty() and int(c.shop_pending.get("id",-1))==iid,label+" source click stays selected")
	check(assets()==before,label+" source click has no transaction")
	return iid
func material_dialog():
	await fixture("material");var iid:=first_item();var before:=assets()
	await click(GOODS)
	check(is_instance_valid(c.panel_root) and c.panel_root.get_script().resource_path=="res://scripts/ui/ShopQuantity.gd","material uses explicit ShopQuantity")
	check(assets()==before,"opening material quantity has no purchase")
	return iid
func find_line(node:Node) -> LineEdit:
	if node is LineEdit:return node
	for child in node.get_children():
		var found:=find_line(child)
		if found!=null:return found
	return null
func quantity(value:String) -> void:
	if not is_instance_valid(c.panel_root):check(false,"quantity dialog available");return
	var field:=find_line(c.panel_root)
	check(field!=null,"quantity has editable explicit number")
	if field==null:return
	await click(field.get_global_rect().get_center());await key(KEY_A,0,true)
	for character in value:await key(KEY_0+int(character),character.unicode_at(0))
	await settle()
	check(field.text==value and int(c.panel_root.quantity)==int(value),"real typing changes explicit quantity to "+value)
	rows.append({"quantity_input":field.text,"quantity_value":c.panel_root.quantity})
func test_clicks() -> void:
	await fixture()
	var iid:=first_item();var price:=int(c.state.item(iid).price);var hero:int=c.state.PROTAGONIST_PID
	check(c.state.item_compatible(c.state.deploy_member(hero),iid),"fixture grocery is compatible")
	var before:=assets()
	motion(GOODS);pointer(GOODS,true);await settle(3)
	check(assets()==before,"holding source over frames cannot transact")
	motion(GOODS+Vector2(3,2),true);await settle();pointer(GOODS+Vector2(3,2),false);await settle()
	check(not c.shop_pending.is_empty() and assets()==before,"micro-jitter click preserves selection without drop")
	await click(PERSON)
	check(c.state.money==int(before.money)-price and bag_count(hero,iid)==1 and c.state.item_count(iid)==0,"source then person click buys exactly one into bag")
	pending_clear("person purchase")
	await click(PERSON);check(bag_count(hero,iid)==1,"extra target click cannot repeat last purchase")
	before=assets();await select_source("store purchase");await click(STORE)
	check(c.state.money==int(before.money)-price and c.state.item_count(iid)==1 and bag_count(hero,iid)==1,"source then warehouse click buys one and conserves other bag")
	pending_clear("store purchase")
	before=assets();await drag_to(GOODS,STORE)
	check(c.state.money==int(before.money)-price and c.state.item_count(iid)==2,"legacy-style motion drag buys one")
	before=assets();await drag_to(GOODS,STORE,false)
	check(c.state.money==int(before.money)-price and c.state.item_count(iid)==3,"down/up at different cells without motion still drops once")
	before=assets();await drag_to(GOODS,NOWHERE,false)
	check(assets()==before,"illegal drop cannot change any assets");pending_clear("illegal drop")
	await drag_to(GOODS,SELL,false);check(assets()==before,"purchase mode cannot drop directly into sell region");pending_clear("illegal sell drop")
	# Two genuine press/release pairs: first selects, second DOWN buys, second UP must not reselect.
	before=assets();await click(GOODS);motion(GOODS);pointer(GOODS,true,MOUSE_BUTTON_LEFT,true);await settle(3)
	check(c.state.money==int(before.money)-price and c.state.item_count(iid)==4,"double-click second down quick-buys one, not two")
	pointer(GOODS,false);await settle();pending_clear("double-click final release")
	check(c.state.money==int(before.money)-price and c.state.item_count(iid)==4,"double-click release cannot duplicate purchase")
	await click(STORE);check(c.state.item_count(iid)==4,"target after double-click cannot replay its source")
	# Real scaled root final transform, including half-pixel logical positions.
	root.size=Vector2i(1600,1200);await settle(3)
	var transform:=root.get_final_transform();transforms.append(str(transform))
	check(transform.x.length()>1.0,"high-DPI fixture actually uses scaled final transform")
	before=assets();await click(GOODS+Vector2(.5,.5));await click(STORE+Vector2(.5,.5))
	check(c.state.money==int(before.money)-price and c.state.item_count(iid)==5,"scaled high-DPI half-pixel click maps to correct logical cells")
	root.size=Vector2i(1280,960);await settle(3)
func test_cancel_details_modes() -> void:
	await fixture();var before:=assets();await select_source("cancel")
	await key(KEY_ESCAPE);pending_clear("Escape")
	check(c.mode=="shop" and assets()==before,"Escape first cancels selection without leaving/transacting")
	await click(STORE);check(assets()==before,"target after Escape cannot use stale selection")
	await select_source("detail");await click(GOODS,MOUSE_BUTTON_RIGHT)
	check(is_instance_valid(c.info_panel),"right-click source opens detail")
	pending_clear("detail opening")
	await click(STORE);await settle(3)
	check(not is_instance_valid(c.info_panel) and assets()==before,"detail dismissal over warehouse does not buy through modal")
	await click(STORE);check(assets()==before,"detail close leaves no reusable pending purchase")
	await select_source("mode change");await click(Vector2(460,180))
	check(c.shop_mode==2,"grocery mode control enters warehouse");pending_clear("mode switch")
	check(assets()==before,"mode-switch press/release cannot commit old selected item")
	await click(Vector2(460,54));check(c.shop_mode==0,"actual control returns purchase mode")
	await select_source("leave");await click(Vector2(460,222))
	check(c.mode!="shop" and c.shop_pending.is_empty() and assets()==before,"leaving shop clears pending and cannot purchase")
	await fixture();before=assets();await click(STORE);check(assets()==before and c.shop_pending.is_empty(),"reopening shop starts with no held source")
func test_feedback_and_confirm() -> void:
	await fixture();var iid:=first_item();var price:=int(c.state.item(iid).price);var hero:int=c.state.PROTAGONIST_PID
	c.state.money=price-1;var before:=assets();await select_source("insufficient funds");await click(STORE)
	check(assets()==before,"insufficient funds purchase preserves all assets");notice_has("资金","insufficient funds produces explicit notice")
	await close_notice();pending_clear("funds notice close")
	await fixture();iid=first_item();c.state.deploy_member(hero).item_slots=[1,2,3,4,5,6,7,8];before=assets()
	await select_source("full bag");await click(PERSON)
	check(assets()==before,"full bag preserves money and all inventory");notice_has("满","full bag produces explicit notice")
	await close_notice();pending_clear("full bag notice")
	await fixture("junxie");iid=first_item();price=int(c.state.item(iid).price)
	var target=c.state.deploy_member(hero);var incompatible:=-1
	for bz in range(c.state.data.item_valid[iid].size()):
		if int(c.state.data.item_valid[iid][bz])==0:incompatible=bz;break
	check(incompatible>=0,"fixture has an incompatible class");target.bingzhong=incompatible
	before=assets();await select_source("incompatible cancel");await click(PERSON)
	check(is_instance_valid(c.panel_root) and c.panel_root is Confirm and text_of(c.panel_root).contains("不能用"),"incompatible item requests explicit keep confirmation")
	check(assets()==before,"incompatible dialog opens before purchase")
	await click(Vector2(382,267))
	check(assets()==before and not is_instance_valid(c.panel_root),"keep confirmation No cancels without changing assets");pending_clear("incompatible cancel")
	await select_source("incompatible yes");await click(PERSON)
	check(is_instance_valid(c.panel_root) and c.panel_root is Confirm,"second incompatible click opens fresh confirm")
	# Click at a background person while modal is open. It answers yes, but release must not retrigger a second transaction.
	await click(PERSON)
	check(c.state.money==int(before.money)-price and bag_count(hero,iid)==1 and c.state.item_count(iid)==0,"keep Yes buys exactly one; modal release does not pass through")
	pending_clear("incompatible yes")
	await click(PERSON);check(bag_count(hero,iid)==1,"post-confirm target cannot buy twice")
func incompatible_fixture(warehouse:=false) -> int:
	await fixture("junxie",warehouse)
	var iid:=81 if warehouse else first_item()
	if warehouse:c.state.add_item(iid,1);c._render_shop();await settle()
	var target=c.state.deploy_member(c.state.PROTAGONIST_PID)
	for bz in range(c.state.data.item_valid[iid].size()):
		if int(c.state.data.item_valid[iid][bz])==0:target.bingzhong=bz;break
	return iid
func test_modal_freshness() -> void:
	var iid:int=await incompatible_fixture();var price:=int(c.state.item(iid).price)
	await select_source("confirm funds race");await click(PERSON)
	c.state.money=price-1;var before:=assets()
	await click(Vector2(382,244))
	check(assets()==before,"keep Yes rechecks latest funds instead of trusting opening balance")
	notice_has("资金","latest funds rejection remains visible after confirm release");pending_clear("confirm funds rejection")
	await close_notice()
	iid=await incompatible_fixture();await select_source("confirm capacity race");await click(PERSON)
	c.state.deploy_member(c.state.PROTAGONIST_PID).item_slots=[1,2,3,4,5,6,7,8];before=assets()
	await click(Vector2(382,244))
	check(assets()==before,"keep Yes rechecks latest bag capacity before spending")
	notice_has("满","latest capacity rejection produces explicit notice");pending_clear("confirm capacity rejection")
	await close_notice()
	iid=await incompatible_fixture(true);await select_source("confirm stock race");await click(PERSON)
	c.state.add_item(iid,-1);before=assets();await click(Vector2(382,244))
	check(assets()==before,"keep Yes rechecks current warehouse source and cannot underflow vanished stock")
	pending_clear("confirm vanished stock");await close_notice()
	await fixture();before=assets()
	motion(GOODS);pointer(GOODS,true);await settle();motion(GOODS+Vector2(20,20),true);await settle()
	await key(KEY_ESCAPE);pointer(STORE,false);await settle()
	check(assets()==before and c.mode=="shop","Escape during held drag cancels eventual release over store");pending_clear("held-drag Escape")
	motion(GOODS);pointer(GOODS,true);await settle();motion(GOODS+Vector2(20,20),true);await settle()
	pointer(NOWHERE,true,MOUSE_BUTTON_RIGHT);await settle();pointer(NOWHERE,false,MOUSE_BUTTON_RIGHT);await settle()
	pointer(STORE,false);await settle()
	check(assets()==before and c.mode=="shop","right-click during held drag cancels eventual release over store");pending_clear("held-drag right-click")
	await fixture("material");before=assets();await click(GOODS)
	var dialog=c.panel_root
	await click(Vector2(460,54));await wheel(PERSON,true)
	check(c.panel_root==dialog and c.shop_mode==3 and c.shop_people_page==0 and assets()==before,"quantity modal blocks background mode and wheel input")
	await key(KEY_ESCAPE);pending_clear("quantity background gestures")
func test_exchange_and_sell() -> void:
	await fixture();var hero:int=c.state.PROTAGONIST_PID;var other:int=c._shop_roster()[1].pid
	c.state.deploy_member(hero).item_slots=[2,2,0,0,0,0,0,0];var iid:=1;var before:=assets()
	await click(Vector2(460,138));check(c.shop_mode==1,"exchange mode entered through actual input")
	await select_source("bag to person");await click(SECOND_PERSON)
	check(c.state.money==int(before.money) and bag_count(hero,iid)==1 and bag_count(other,iid)==1 and c.state.item_count(iid)==0,"bag-to-person moves exactly one without money/warehouse change")
	pending_clear("bag-to-person assignment")
	await select_source("bag to store");await click(STORE)
	check(c.state.money==int(before.money) and bag_count(hero,iid)==0 and bag_count(other,iid)==1 and c.state.item_count(iid)==1,"bag-to-store moves one and conserves total inventory")
	pending_clear("bag-to-store assignment")
	await click(Vector2(460,180));check(c.shop_mode==2,"warehouse mode after exchange")
	before=assets();await select_source("warehouse sell");await click(SELL)
	var sell_price:=int(c.state.item(iid).price)*(7-int(c.state.difficulty))/10
	check(c.state.money==int(before.money)+sell_price and c.state.item_count(iid)==0 and bag_count(other,iid)==1,"warehouse sell uses unchanged native sell-price formula for one unit")
	pending_clear("warehouse sell")
	await click(SELL);check(c.state.money==int(before.money)+sell_price,"extra sell click after sold-out source cannot duplicate income")
func unit_sell_price(iid:int) -> int:
	return int(c.state.item(iid).price)*(7-int(c.state.difficulty))/10
func select_cell(point:Vector2,iid:int,label:String) -> void:
	var before:=assets();await click(point)
	check(not c.shop_pending.is_empty() and int(c.shop_pending.get("id",-1))==iid,label+" selects expected item")
	check(assets()==before,label+" selection alone preserves assets")
func remaining_selected(iid:int,slot:int,label:String) -> void:
	check(not c.shop_pending.is_empty() and int(c.shop_pending.get("id",-1))==iid and int(c.shop_pending.get("slot",-999))==slot,label+" keeps same item and current source slot")
	check(c.service_screen.drag.is_empty() and not c.service_screen.shop_pointer_active,label+" resets held pointer without clearing next-sale selection")
func test_continuous_bag_sell() -> void:
	await fixture();var hero:int=c.state.PROTAGONIST_PID;var iid:=1
	# Three identical goods, deliberately interleaved with unrelated items.
	# Select the LAST identical item: native remove_id removes the first ID,
	# so the original selected slot becomes invalid after the first compact.
	c.state.deploy_member(hero).item_slots=[2,3,2,4,2,5,0,0]
	await click(Vector2(460,138));check(c.shop_mode==1,"continuous bag sale enters exchange through input")
	await select_cell(Vector2(48,204),iid,"last interleaved duplicate")
	check(int(c.shop_pending.get("slot",-1))==4,"last duplicate starts at actual slot four")
	var before:=assets();var price:=unit_sell_price(iid)
	var bags:Array=[[3,2,4,2,5,0,0,0],[3,4,2,5,0,0,0,0],[3,4,5,0,0,0,0,0]]
	for sold in range(1,4):
		var money:int=c.state.money;var count:=bag_count(hero,iid)
		motion(SELL);pointer(SELL,true,MOUSE_BUTTON_LEFT,sold==2);await settle(5)
		check(c.state.money==money and bag_count(hero,iid)==count,"bag sale %d holding DOWN does not auto-sell"%sold)
		pointer(SELL,false);await settle()
		check(c.state.money==int(before.money)+sold*price and bag_count(hero,iid)==3-sold,"bag sale %d release sells exactly one at unchanged per-item price"%sold)
		check(c.state.deploy_member(hero).item_slots==bags[sold-1] and c.state.items==before.items and c.state.materials==before.materials,"bag sale %d compacts duplicate ID only, preserving unrelated goods/warehouse/materials"%sold)
		if sold<3:remaining_selected(iid,1 if sold==1 else 2,"bag sale %d"%sold)
		else:pending_clear("final bag sale")
		await settle(6)
		check(c.state.money==int(before.money)+sold*price and bag_count(hero,iid)==3-sold,"bag sale %d has no timer/held-repeat batch"%sold)
	var after:=assets();await click(SELL);check(assets()==after,"sold-out bag extra click cannot sell the next different item")
	continuous_sell_cases+=1
func test_continuous_warehouse_sell() -> void:
	await fixture("zahuo",true);var iid:=1
	# Isolate a non-round price in a deep-copied in-memory table. Native per-
	# piece flooring yields 7+7+7=21, unlike flooring a three-item batch (23).
	var original_data:Dictionary=c.state.data
	var original_difficulty:int=c.state.difficulty
	c.state.data=original_data.duplicate(true)
	c.state.data.items[str(iid)]["price"]=11;c.state.difficulty=0
	c.state.add_item(iid,3);c.state.add_item(2,2);c._render_shop();await settle()
	await select_cell(GOODS,iid,"warehouse three-unit source")
	var before:=assets();var price:=unit_sell_price(iid)
	check(price==7 and 3*11*(7-int(c.state.difficulty))/10==23,"rounding fixture distinguishes per-piece sale price from a batched total")
	for sold in range(1,4):
		var money:int=c.state.money
		motion(SELL);pointer(SELL,true,MOUSE_BUTTON_LEFT,sold==2);await settle(5)
		check(c.state.money==money and c.state.item_count(iid)==4-sold,"warehouse sale %d holding DOWN cannot batch-sell"%sold)
		pointer(SELL,false);await settle()
		check(c.state.money==int(before.money)+sold*price and c.state.item_count(iid)==3-sold and c.state.item_count(2)==2,"warehouse sale %d sells one and preserves other inventory"%sold)
		check(assets().bags==before.bags and c.state.materials==before.materials,"warehouse sale %d preserves all bags/materials"%sold)
		if sold<3:remaining_selected(iid,-1,"warehouse sale %d"%sold)
		else:pending_clear("final warehouse sale")
		await settle(6)
		check(c.state.money==int(before.money)+sold*price,"warehouse sale %d cannot repeat during idle frames"%sold)
	check(int(c.service_screen.shop_stock_at(GOODS).id)==2,"sold-out warehouse cell now contains a different item")
	var after:=assets();await click(SELL);check(assets()==after,"sold-out warehouse extra click cannot sell the replacement grid entry")
	check(int(c.state.money)-int(before.money)==21,"three individual clicks credit exactly 21, not batched 23")
	c.state.data=original_data;c.state.difficulty=original_difficulty
	continuous_sell_cases+=1
func start_continuous_sale(source_mode:int) -> int:
	await fixture("zahuo",source_mode==2);var iid:=1
	if source_mode==1:
		c.state.deploy_member(c.state.PROTAGONIST_PID).item_slots=[2,3,2,4,2,0,0,0]
		await click(Vector2(460,138))
	else:
		c.state.add_item(iid,3)
		for other in range(2,14):c.state.add_item(other,1)
		c._render_shop();await settle()
	await select_cell(GOODS,iid,"continuous mode%d source"%source_mode);await click(SELL)
	remaining_selected(iid,1 if source_mode==1 else -1,"continuous mode%d after one sale"%source_mode)
	return iid
func test_continuous_source_changes() -> void:
	for source_mode in [1,2]:
		var iid:int=await start_continuous_sale(source_mode)
		if source_mode==1:
			# The bound next-sale slot contains another item now. Even when the
			# desired ID survives in a DIFFERENT slot, reject instead of selling it.
			c.state.deploy_member(c.state.PROTAGONIST_PID).item_slots=[2,3,4,5,0,0,0,0]
		else:c.state.add_item(iid,-c.state.item_count(iid))
		var before:=assets();await click(SELL)
		check(assets()==before,"mode%d changed source cannot sell another ID or underflow missing stock"%source_mode)
		pending_clear("mode%d changed source"%source_mode)
		check(is_instance_valid(c.panel_root) and c.panel_root is Notice,"mode%d changed source has visible rejection"%source_mode)
		await close_notice();await click(SELL)
		check(assets()==before,"mode%d source-rejection modal close cannot resume stale sale"%source_mode)
		continuous_sell_cases+=1
func test_continuous_cancel_boundaries() -> void:
	for source_mode in [1,2]:
		for action in ["Escape","right blank","page","mode","detail","modal","leave"]:
			await start_continuous_sale(source_mode)
			if action=="modal":
				var pid:int=c._shop_roster()[1].pid if source_mode==1 else c.state.PROTAGONIST_PID
				c.state.deploy_member(pid).item_slots=[1,2,3,4,5,6,7,8]
			var before:=assets()
			match action:
				"Escape":await key(KEY_ESCAPE)
				"right blank":await click(NOWHERE,MOUSE_BUTTON_RIGHT)
				"page":await wheel(PERSON if source_mode==1 else GOODS,true)
				"mode":await click(Vector2(460,54))
				"detail":
					await click(GOODS,MOUSE_BUTTON_RIGHT)
					check(is_instance_valid(c.info_panel),"continuous mode%d right-click opens detail"%source_mode)
					await key(KEY_SPACE)
					check(not is_instance_valid(c.info_panel),"continuous detail closes with a fresh key release")
				"modal":
					await click(SECOND_PERSON if source_mode==1 else PERSON)
					notice_has("满","continuous full-target modal is explicit")
					await close_notice()
				"leave":
					await click(Vector2(460,222))
					check(c.mode!="shop" and c.shop_pending.is_empty(),"continuous leave clears selected source")
					c._open_shop("zahuo",source_mode==2);await settle()
			pending_clear("continuous mode%d %s"%[source_mode,action])
			check(assets()==before,"continuous mode%d %s boundary itself cannot sell another unit"%[source_mode,action])
			await click(SELL)
			check(assets()==before,"continuous mode%d %s followed by sell cannot resume old source"%[source_mode,action])
			continuous_sell_cases+=1
func test_continuous_assignment_exit() -> void:
	for source_mode in [1,2]:
		var iid:int=await start_continuous_sale(source_mode)
		var hero:int=c.state.PROTAGONIST_PID;var other:int=c._shop_roster()[1].pid
		var before:=assets();await click(SECOND_PERSON if source_mode==1 else PERSON)
		check(c.state.money==int(before.money) and bag_count(other if source_mode==1 else hero,iid)==1,"continuous mode%d assignment transfers one without sale income"%source_mode)
		check(bag_count(hero,iid)==1 if source_mode==1 else c.state.item_count(iid)==1,"continuous mode%d assignment removes exactly one remaining source unit"%source_mode)
		pending_clear("continuous mode%d successful assignment"%source_mode)
		var after:=assets();await click(SELL)
		check(assets()==after,"continuous mode%d successful assignment ends repeated selling"%source_mode)
		continuous_sell_cases+=1
func test_paging() -> void:
	await fixture("zahuo",true)
	for iid in range(25):c.state.add_item(iid,1)
	c._render_shop();await settle();var before:=assets()
	await select_source("warehouse wheel");await wheel(GOODS,true)
	check(c.shop_item_page==1 and int(c.service_screen.shop_stock_at(GOODS).id)==12,"warehouse wheel advances twelve kinds");pending_clear("warehouse wheel")
	await click(SELL);check(assets()==before,"paging discards pending instead of selling old page item")
	await wheel(GOODS,true);check(c.shop_item_page==2 and int(c.service_screen.shop_stock_at(GOODS).id)==24,"warehouse wheel reaches final partial page")
	for i in range(4):await wheel(GOODS,true)
	check(c.shop_item_page==2,"warehouse wheel clamps at last page")
	for i in range(5):await wheel(GOODS,false)
	check(c.shop_item_page==0 and assets()==before,"warehouse wheel clamps at zero with assets unchanged")
	await wheel(PERSON,true)
	check(c.shop_people_page==1 and c.service_screen.shop_person_at(PERSON)==8,"people wheel scrolls eight people independently")
	for i in range(5):await wheel(PERSON,true)
	check(c.shop_people_page==2 and c.service_screen.shop_person_at(PERSON)==16,"people wheel clamps final row")
	for i in range(5):await wheel(PERSON,false)
	check(c.shop_people_page==0,"people wheel clamps at zero")
	await select_source("arrow paging");await click(Vector2(383,230))
	check(c.shop_item_page==1,"legacy stock arrow remains usable");pending_clear("stock arrow")
	await click(Vector2(590,400));check(c.shop_people_page==1,"legacy people arrow remains usable")
	check(assets()==before,"all paging preserves economic assets")
	await fixture("zahuo",true);before=assets();await wheel(GOODS,true)
	check(c.shop_item_page==0 and assets()==before,"empty warehouse wheel clamps at zero without phantom stock")
	for slot in range(4,32):c.state.set_person_side(slot,1)
	c._render_shop();await settle();await wheel(PERSON,true)
	check(c.shop_people_page==0,"short four-person roster cannot scroll to nonexistent row")
func test_materials() -> void:
	var iid:int=await material_dialog();var before:=assets();await quantity("3")
	if is_instance_valid(c.panel_root):check(text_of(c.panel_root).contains("总价") and text_of(c.panel_root).contains("余额"),"material dialog explicitly displays total and balance")
	await key(KEY_ESCAPE);check(not is_instance_valid(c.panel_root) and assets()==before,"quantity Escape cancels without buying")
	await click(STORE);check(assets()==before,"quantity cancellation does not leave pending source")
	iid=await material_dialog();before=assets();var price:=int(c.state.material(iid).price)
	await quantity("3");await key(KEY_ENTER)
	rows.append({"material_commit_money":c.state.money,"material_commit_count":c.state.material_count(iid),"material_commit_panel":is_instance_valid(c.panel_root)})
	check(not is_instance_valid(c.panel_root) and c.state.money==int(before.money)-3*price and c.state.material_count(iid)==3,"quantity Enter buys exact explicit count and total price")
	var after:=assets();await key(KEY_ENTER);await click(STORE)
	check(assets()==after,"extra Enter/release/target cannot repeat material purchase")
	iid=await material_dialog();await quantity("3");c.state.money=2*int(c.state.material(iid).price);before=assets()
	await key(KEY_ENTER)
	check(assets()==before,"material commit rechecks latest funds, no negative balance or stock credit")
	notice_has("资金","latest-funds rejection remains visible after Enter opening release")
	await key(KEY_ENTER)
	check(not is_instance_valid(c.panel_root) and assets()==before and c.mode=="shop","fresh Enter dismisses rejection notice without repeating transaction or leaving shop")
	await click(STORE);check(assets()==before,"rejection notice close leaves no stale material transaction")
	c._close_panel();await settle()
	await fixture("material");c.state.money=0;before=assets();await click(GOODS)
	check(assets()==before,"zero-money material attempt cannot change assets")
	check(is_instance_valid(c.panel_root) and c.panel_root.get_script().resource_path=="res://scripts/ui/ShopQuantity.gd" and c.panel_root.maximum==0 and c.panel_root.buy_button.disabled,"zero-money material attempt visibly shows maximum zero and purchase disabled")
	await close_notice();c._close_panel()
func run() -> void:
	var override_dir:=OS.get_environment("DLZ_SHOP_EVIDENCE_DIR")
	if not override_dir.is_empty():evidence_dir=override_dir
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(evidence_dir))
	root.size=Vector2i(1280,960);root.content_scale_size=Vector2i(640,480)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	c=load("res://scripts/m4/Campaign.gd").new();root.add_child(c);c.qa_mode=true
	c.setup(load("res://assets/font/hzk16.fnt"),{"name":"商店测试","face":103,"unit":1,"wuli":80,"difficulty":1})
	await settle(3)
	check("shop_convenience_enabled" in c and c.shop_convenience_enabled,"convenience input defaults enabled")
	if not "shop_convenience_enabled" in c:
		await finish();return
	await test_clicks()
	await test_cancel_details_modes()
	await test_feedback_and_confirm()
	await test_modal_freshness()
	await test_exchange_and_sell()
	await test_continuous_bag_sell()
	await test_continuous_warehouse_sell()
	await test_continuous_source_changes()
	await test_continuous_cancel_boundaries()
	await test_continuous_assignment_exit()
	await test_paging()
	await test_materials()
	await finish()
func finish() -> void:
	if is_instance_valid(c):c.queue_free()
	await settle(3)
	root.get_node("Music").release_playback();OriginalUI.release_native_sfx();await create_timer(.2).timeout
	var f=FileAccess.open(evidence_dir+"/shop_convenience_test.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures,"input_events":input_events,"continuous_sell_cases":continuous_sell_cases,"transforms":transforms,"rows":rows},"\t"));f.close()
	print("SHOP_CONVENIENCE checks=",checks," failures=",failures," input_events=",input_events)
	if failures==0:print("SHOP_CONVENIENCE_OK")
	quit(1 if failures else 0)
