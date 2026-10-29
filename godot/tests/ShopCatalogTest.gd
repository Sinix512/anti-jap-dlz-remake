extends SceneTree
# Actual viewport press/hold/release, not direct paging-method calls.
const Quantity=preload("res://scripts/ui/OriginalQuantity.gd")
var checks:=0
var failures:=0
var rows:Array=[]
var c
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1;rows.append({"ok":ok,"label":label})
	if not ok:failures+=1;push_error("SHOP_CATALOG "+label)
func pointer(point:Vector2,down:bool,button:=MOUSE_BUTTON_LEFT) -> void:
	var e:=InputEventMouseButton.new();e.position=root.get_final_transform()*point;e.global_position=e.position;e.button_index=button;e.pressed=down
	Input.parse_input_event(e);Input.flush_buffered_events()
func motion(point:Vector2) -> void:
	var e:=InputEventMouseMotion.new();e.position=root.get_final_transform()*point;e.global_position=e.position
	Input.parse_input_event(e);Input.flush_buffered_events()
func click(point:Vector2,button:=MOUSE_BUTTON_LEFT) -> void:
	motion(point);pointer(point,true,button);await process_frame;await process_frame
	pointer(point,false,button);await process_frame;await process_frame
func ids(stock:Array) -> Array:
	return stock.map(func(entry):return int(entry.id))
func run() -> void:
	c=load("res://scripts/m4/Campaign.gd").new();root.add_child(c);c.setup(load("res://assets/font/hzk16.fnt"));c.qa_mode=true
	# Legacy quantity gestures are deliberate here; default modern transactions
	# and quantity confirmation are covered by ShopConvenienceTest.
	c.shop_convenience_enabled=false
	var raw:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../data/town.json"))
	c.state.money=100000
	# Every actual catalog entry fits the two original rows; duplicates in the
	# original grocery lists (e.g. town6 wine24) must not be deduplicated.
	for town in range(19):
		c.selected_town=town;c._open_shop("zahuo");await process_frame
		var expected:Array=raw.towns[town].goods_zahuo.filter(func(id):return int(id)>=0).map(func(id):return int(id))
		var stock:Array=c._shop_stock()
		check(ids(stock)==expected and stock.size()<=12,"town%d grocery catalog exact and <=12"%town)
		var visible:=true
		for i in range(stock.size()):
			var cell:Dictionary=c.service_screen.shop_stock_at(Vector2(48+56*(i%6),88+120*(i/6)))
			visible=visible and not cell.is_empty() and int(cell.id)==int(expected[i])
		check(visible,"town%d every grocery slot is in visible 6x2 input grid"%town)
		if stock.size()==12:
			var item:int=expected[11];var money:int=c.state.money;var before:int=c.state.item_count(item)
			motion(Vector2(328,208));pointer(Vector2(328,208),true);await process_frame;await process_frame
			check(not c.shop_pending.is_empty() and int(c.shop_pending.get("id",-1))==item,"town%d actual bottom-right press selects twelfth item"%town)
			motion(Vector2(566,230));pointer(Vector2(566,230),false);await process_frame;await process_frame
			check(c.state.item_count(item)==before+1 and c.state.money==money-int(c.state.item(item).price),"town%d twelfth grocery item can actually be bought"%town)
		c._shop_mode(3);await process_frame
		expected=raw.towns[town].goods_material.slice(0,10).filter(func(id):return int(id)>=0).map(func(id):return int(id))
		stock=c._shop_stock()
		check(ids(stock)==expected and stock.size()<=10,"town%d materials contain only the ten native catalog fields"%town)
		var no_phantom:=true
		for i in range(expected.size(),10):
			no_phantom=no_phantom and c.service_screen.shop_stock_at(Vector2(48+64*(i%5),88+120*(i/5))).is_empty()
		check(no_phantom,"town%d empty material slots are not extra clay purchase targets"%town)
	# The last material of a full 5x2 catalog remains operable.
	c.selected_town=15;c._open_shop("material");await process_frame
	var money:int=c.state.money;var materials:Dictionary=c.state.materials.duplicate(true)
	await click(Vector2(304,208))
	check(c.panel_root is Quantity and c.panel_root.material_name==c.state.material(9).name,"tenth material opens the correct quantity dialog")
	await click(Vector2(620,450),MOUSE_BUTTON_RIGHT)
	check(c.state.money==money and c.state.materials==materials,"cancelled material dialog leaves assets unchanged")
	# Stock arrows are warehouse pages, not extra shop-catalog rows.
	c.selected_town=1;c.state.items.clear()
	for i in range(25):c.state.add_item(i,1)
	c._open_shop("zahuo");c._shop_mode(2);await process_frame
	money=c.state.money;var items:Dictionary=c.state.items.duplicate(true)
	await click(Vector2(383,230))
	check(c.shop_item_page==1 and int(c.service_screen.shop_stock_at(Vector2(48,84)).id)==12,"warehouse down reaches the next twelve kinds through actual input")
	await click(Vector2(383,230))
	check(c.shop_item_page==2 and int(c.service_screen.shop_stock_at(Vector2(48,84)).id)==24,"warehouse final page is reachable")
	await click(Vector2(383,230));check(c.shop_item_page==2,"warehouse down clamps at last page")
	await click(Vector2(383,210));await click(Vector2(383,210));await click(Vector2(383,210))
	check(c.shop_item_page==0 and c.state.money==money and c.state.items==items,"warehouse up clamps at first page without transactions")
	for i in range(32):c.state.set_person_side(i,0 if i<4 else 1)
	c._open_shop("zahuo");await process_frame
	await click(Vector2(590,400));check(c.shop_people_page==0,"four-person roster has no next row")
	for i in range(22):c.state.set_person_side(i,0)
	c._render_shop();await click(Vector2(590,400))
	check(c.shop_people_page==1 and c.service_screen.shop_person_at(Vector2(48,330))==8,"roster down scrolls eight people, not merchandise")
	await click(Vector2(590,380));check(c.shop_people_page==0,"roster up returns to first row")
	c.queue_free();await process_frame;await process_frame
	root.get_node("Music").release_playback();OriginalUI.release_native_sfx();await create_timer(.2).timeout
	var file=FileAccess.open("res://../out/shop_catalog_test.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"));file.close()
	print("SHOP_CATALOG checks=",checks," failures=",failures)
	if failures==0:print("SHOP_CATALOG PASS")
	quit(1 if failures else 0)
