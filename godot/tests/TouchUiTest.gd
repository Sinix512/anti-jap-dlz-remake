extends SceneTree
## Synthetic touch-only UI integration. No player-save access or campaign play.
const OUT="res://../out/evidence/android_touch_20261030"
const Choice=preload("res://scripts/ui/OriginalChoice.gd")
const Confirm=preload("res://scripts/ui/OriginalConfirm.gd")
const Notice=preload("res://scripts/ui/OriginalNotice.gd")
const Story=preload("res://scripts/ui/OriginalStoryPage.gd")
const Deployment=preload("res://scripts/ui/OriginalDeployment.gd")
var bridge
var font:Font
var c
var checks:=0
var failures:=0
var input_events:=0
var rows:Array=[]
var shots:Array=[]
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1;rows.append({"ok":ok,"label":label})
	if not ok:failures+=1;push_error("TOUCH_UI_FAIL "+label)
func settle(frames:=2) -> void:
	for _i in range(frames):await process_frame
func screen(point:Vector2,down:bool,index:=0,canceled:=false) -> void:
	var event:=InputEventScreenTouch.new();event.position=root.get_final_transform()*point;event.pressed=down;event.index=index;event.canceled=canceled
	root.push_input(event,false);input_events+=1
func tap(point:Vector2) -> void:
	screen(point,true);await settle(1);screen(point,false);await settle()
func long_press(point:Vector2) -> void:
	bridge.long_press_ms=0;await tap(point);bridge.long_press_ms=550
func swipe(from:Vector2,to:Vector2) -> void:
	screen(from,true)
	var event:=InputEventScreenDrag.new();event.index=0;event.position=root.get_final_transform()*to;event.relative=root.get_final_transform().basis_xform(to-from)
	root.push_input(event,false);input_events+=1;screen(to,false);await settle()
func shot(name:String) -> void:
	if not OS.get_cmdline_user_args().has("--screenshots") or DisplayServer.get_name()=="headless":return
	await settle(2);await RenderingServer.frame_post_draw
	var path:=OUT+"/touch_ui_"+name+".png"
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path));shots.append(path)
func assets() -> Dictionary:
	return {"money":c.state.money,"items":c.state.items.duplicate(true),"materials":c.state.materials.duplicate(true),"mines":c.state.mines.duplicate(true),"bags":c._shop_roster().map(func(p):return {"pid":p.pid,"bag":p.item_slots.duplicate(),"mines":p.mine_slots.duplicate()})}
func close_modal() -> void:
	await tap(Vector2(598,456));await settle()
func test_menus() -> void:
	var choice=Choice.new();root.add_child(choice);choice.setup(font,["第一项","第二项"],Vector2(320,200))
	var chosen:Array=[];choice.chosen.connect(func(i:int):chosen.append(i))
	check(choice.row_height==40 and choice.row_rect(0).size==Vector2(120,40),"touch choices have40px-high nonoverlapping rows")
	await shot("choice");await tap(Vector2(10,10));check(chosen.is_empty() and not choice.done,"blank tap cannot accept stale hover/default choice")
	await tap(choice.row_rect(1).get_center());check(chosen==[1],"touch position chooses actual second row without mouse hover")
	choice.free();await settle()
	choice=Choice.new();root.add_child(choice)
	var long_entries:Array=[]
	for index in range(13):long_entries.append("选项"+str(index+1))
	choice.setup(font,long_entries,Vector2(551,343));chosen.clear();choice.chosen.connect(func(i:int):chosen.append(i))
	check(choice.frame.position.y>=8 and choice.frame.end.y<=428 and choice.row_rect(12).end.x<=632,"13-row touch system menu fits viewport in two columns")
	await shot("long_choice");await tap(choice.row_rect(12).get_center());check(chosen==[12],"last of13 touch choices remains reachable")
	choice.free();await settle()
	var confirm=Confirm.new();root.add_child(confirm);confirm.setup(font,"确认购买？")
	var answers:Array=[];confirm.answered.connect(func(yes:bool):answers.append(yes))
	await tap(Vector2(10,10));check(answers.is_empty(),"blank tap never accepts yes/no default")
	await shot("confirm");bridge.request_back();await settle();check(answers==[false],"one Android back conservatively cancels confirmation")
	confirm.free();await settle()
	var picker=preload("res://scripts/ui/OriginalSavePicker.gd").new();root.add_child(picker)
	var previews:Array=[]
	for _i in range(5):previews.append({"mode":150,"turn":3,"level":0,"intro":"触控测试","difficulty":1})
	picker.setup(font,preload("res://scripts/ui/OriginalPalette.gd").colors("BIGMAP"),previews,true)
	var slots:Array=[];picker.chosen.connect(func(slot:int):slots.append(slot))
	await tap(Vector2(20,20));check(slots.is_empty(),"save picker blank tap cannot load remembered slot")
	await tap(Vector2(240,248));check(slots==[2],"save picker touch selects exact slot without reading player saves")
	picker.free();await settle()
	# Child created by the synthetic mouse-DOWN must survive that tap's UP.
	choice=Choice.new();root.add_child(choice);choice.setup(font,["显示提示"],Vector2(320,200))
	var children:Array=[]
	choice.chosen.connect(func(_i:int):
		choice.hide();choice.set_process_input(false)
		var notice=Notice.new();root.add_child(notice);notice.setup(font,"一条手指操作，不重复确认")
		children.append(notice))
	await tap(choice.row_rect(0).get_center())
	check(children.size()==1 and not children[0].done,"opening touch release cannot dismiss its child notice")
	await tap(Vector2(260,344));check(children[0].done,"one fresh tap dismisses notice without an extra legacy click")
	children[0].free();choice.free();await settle()
	var story=Story.new();root.add_child(story)
	var pages:Array=preload("res://scripts/ui/OriginalStoryLayout.gd").pages("触控剧情继续测试","",46)
	story.setup(font,pages[0],-1,"KUANG04",46);story.set_process(false)
	for _i in range(14):story._advance(0.048)
	await settle();var confirms:Array=[];story.confirmed.connect(func():confirms.append(true))
	OriginalUI.native_wait_left_blocked=true
	await tap(Vector2(260,344));check(story.stage=="tail","fresh touch advances ready story without keyboard/right mouse")
	story._advance(.2);check(confirms.size()==1,"story emits one continuation only")
	story.free();await settle()
func test_shop() -> void:
	c=load("res://scripts/m4/Campaign.gd").new();root.add_child(c);c.qa_mode=true
	c.setup(font,{"name":"触控测试","face":103,"unit":1,"wuli":80,"difficulty":1})
	c.state.data=c.state.data.duplicate(true);c.state.data.meta.save_prefix="dlz_qa_touch_ui_"
	for slot in range(32):
		c.state.set_person_side(slot,0 if slot<22 else 1)
		var person:Dictionary=c.state.person(slot);person.item_slots=[0,0,0,0,0,0,0,0];person.mine_slots=[0,0,0,0,0,0,0,0]
	c.state.money=10000;c.state.items.clear();c.state.materials.clear();c.state.mines.clear()
	c.selected_town=1;c._open_shop("zahuo");await settle()
	var iid:int=c._shop_stock()[0].id;var price:int=c.state.item(iid).price
	var before:=assets();screen(Vector2(48,84),true);await settle(3)
	check(assets()==before and c.shop_pending.is_empty(),"finger DOWN/hold has no selection or transaction")
	screen(Vector2(48,84),false);await settle();check(not c.shop_pending.is_empty() and assets()==before,"finger UP selects goods without buying")
	await tap(Vector2(566,230));check(c.state.item_count(iid)==1 and c.state.money==int(before.money)-price,"two touch taps buy exactly one to warehouse")
	await shot("shop")
	before=assets();await swipe(Vector2(48,84),Vector2(180,84));check(assets()==before and c.shop_pending.is_empty(),"swipe over goods never buys or selects")
	before=assets();await long_press(Vector2(48,84))
	check(is_instance_valid(c.info_panel) and assets()==before and c.shop_pending.is_empty(),"long press opens item detail with zero left-click transaction")
	await shot("detail");await close_modal();check(not is_instance_valid(c.info_panel) and assets()==before,"touch close detail cannot fall through and buy")
	await long_press(Vector2(48,330));check(is_instance_valid(c.info_panel) and assets()==before,"long press person opens detail without transferring goods")
	bridge.request_back();await settle();check(not is_instance_valid(c.info_panel),"Android back immediately closes top person detail")
	c.state.items.clear();c.state.add_item(iid,3);c._shop_mode(2);await settle();before=assets()
	await tap(Vector2(48,84));var sale:int=price*(7-c.state.difficulty)/10
	for n in range(3):
		await tap(Vector2(566,160))
		check(c.state.item_count(iid)==2-n and c.state.money==int(before.money)+(n+1)*sale,"repeat touch sale exactly one item and credit, index="+str(n))
	check(c.shop_pending.is_empty(),"sold-out touch sale clears stale source")
	before=assets();await tap(Vector2(566,160));check(assets()==before,"extra touch on sell after sold-out has no duplicate credit")
	c._open_shop("material");await settle();var material:int=c._shop_stock()[0].id;before=assets()
	await tap(Vector2(48,84));var dialog=c.panel_root
	check(is_instance_valid(dialog) and dialog.get_script().resource_path=="res://scripts/ui/ShopQuantity.gd","material tap opens quantity modal, no purchase")
	check(assets()==before and not dialog.quantity_input.has_focus(),"quantity opening neither transacts nor automatically opens phone keyboard")
	await tap(Vector2(384,214));check(dialog.quantity==2,"touch plus increases explicit quantity once")
	await shot("quantity");await tap(Vector2(380,303));check(not is_instance_valid(c.panel_root) and assets()==before,"touch cancel quantity preserves money/materials")
	await tap(Vector2(48,84));dialog=c.panel_root;await tap(Vector2(384,214))
	var material_price:int=c.state.material(material).price
	await tap(Vector2(260,303));check(c.state.material_count(material)==2 and c.state.money==int(before.money)-2*material_price,"touch purchase commits exactly the displayed quantity")
	before=assets();await tap(Vector2(260,303));check(assets()==before,"quantity closing release cannot repeat purchase")
	# Every overlapping old19px arrow is replaced with a separate40px target.
	c._shop_mode(2);await settle();var controls:Dictionary=c.service_screen._controls()
	for name in controls:
		check(int(controls[name][3])>=36,"touch service target height at least36: "+str(name))
	check(not Rect2(controls.people_up[0],controls.people_up[1],controls.people_up[2],controls.people_up[3]).intersects(Rect2(controls.people_down[0],controls.people_down[1],controls.people_down[2],controls.people_down[3])),"people page targets do not overlap")
	await tap(Vector2(598,406));check(c.shop_people_page==1,"touch page arrow changes people page without wheel")
	await tap(Vector2(598,360));check(c.shop_people_page==0,"touch page-up returns without keyboard")
	c.hide()
	var inventory=preload("res://scripts/ui/InventoryPanel.gd").new();root.add_child(inventory)
	var item_fixture:Dictionary={}
	for item_id in range(60):item_fixture[str(item_id)]=1
	inventory.setup(font,c.m2,item_fixture)
	await settle();var scroll:ScrollContainer=inventory.get_children().filter(func(node):return node is ScrollContainer)[0]
	var detail_before:String=inventory.detail.text
	await swipe(Vector2(180,340),Vector2(180,160))
	check(scroll.scroll_vertical>0,"actual inventory list scrolls with finger swipe, no wheel")
	check(inventory.detail.text==detail_before,"inventory swipe does not activate a row")
	await shot("inventory");var closed:Array=[];inventory.closed.connect(func():closed.append(true))
	bridge.request_back();await settle();check(closed.size()==1,"inventory Android back closes only top modal")
	inventory.free();c.show();await settle()
	c._show_k04_status();c.state.add_mine(0,2);await settle();before=assets()
	await tap(Vector2(46,58));check(c.k04_held==0 and assets()==before,"mine first tap selects source without drag/transfer")
	await tap(Vector2(46,137));check(c.k04_held==-1 and c.state.mine_count(0)==1,"mine second tap transfers exactly one to person")
	await shot("mines")
	var state=c.state;c.free();await settle()
	var deployment=Deployment.new();root.add_child(deployment);deployment.setup(font,state,34)
	var original_count:int=deployment.count();await tap(Vector2(46,90))
	check(deployment.count()==original_count+1 and deployment.drag.is_empty(),"deployment one tap transfers optional unit, no drag-only requirement")
	await tap(Vector2(382,90));check(deployment.count()==original_count+1,"forced deployment member cannot be removed")
	await long_press(Vector2(454,90));check(is_instance_valid(deployment.info),"deployment long press inspects person without toggling")
	bridge.request_back();await settle();check(not is_instance_valid(deployment.info) and deployment.count()==original_count+1,"deployment detail back preserves roster")
	await shot("deployment");deployment.free();await settle()
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	OriginalUI.sfx_enabled=false;font=load("res://assets/font/hzk16.fnt")
	bridge=root.get_node_or_null("TouchInput")
	if bridge==null:
		bridge=load("res://scripts/ui/TouchInput.gd").new();bridge.name="TouchInput";root.add_child(bridge)
	bridge.set_touch_mode(true)
	root.size=Vector2i(1280,960);root.content_scale_size=Vector2i(640,480);root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	await settle(3);check(root.get_final_transform().x.x==2,"real ScreenTouch coordinates exercised through2x viewport stretch")
	await test_menus();await test_shop()
	var file=FileAccess.open(OUT+"/touch_ui_test.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"input_events":input_events,"rows":rows,"screenshots":shots},"\t"));file.close()
	root.get_node("Music").release_playback();OriginalUI.release_native_sfx();await settle()
	print("TOUCH_UI ","PASS" if failures==0 else "FAIL"," checks=",checks," failures=",failures," screen_events=",input_events)
	quit(1 if failures else 0)
