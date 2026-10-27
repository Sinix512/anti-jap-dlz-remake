extends SceneTree
# Real press/hold/release transitions, unlike same-frame synthetic clicks.
const Codec=preload("res://scripts/battle/StateCodec.gd")
const Info=preload("res://scripts/ui/OriginalInfo.gd")
var checks:=0
var failures:=0
var rows:Array=[]
var camp
var world
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1;rows.append({"ok":ok,"label":label})
	if not ok:failures+=1;push_error("MODAL_ENTRY "+label)
func pointer(point:Vector2,button:int,pressed:bool) -> void:
	var e:=InputEventMouseButton.new();e.position=root.get_final_transform()*point;e.global_position=e.position;e.button_index=button;e.pressed=pressed
	Input.parse_input_event(e);Input.flush_buffered_events()
func motion(point:Vector2) -> void:
	var e:=InputEventMouseMotion.new();e.position=root.get_final_transform()*point;e.global_position=e.position
	Input.parse_input_event(e);Input.flush_buffered_events()
func held_click(point:Vector2,button:=MOUSE_BUTTON_LEFT) -> void:
	motion(point);pointer(point,button,true)
	await create_timer(0.15).timeout
	pointer(point,button,false);await process_frame;await process_frame
func info_child():
	for child in world.get_children():
		if child is Info and not child._closed:return child
	return null
func close_info() -> void:
	var info=info_child()
	if info!=null:info.close()
	await process_frame;await process_frame
func run() -> void:
	camp=load("res://scripts/m4/Campaign.gd").new();root.add_child(camp);camp.setup(load("res://assets/font/hzk16.fnt"));camp.qa_mode=true
	camp.ui_root.hide()
	var hero_data:Dictionary=camp.state.protagonist_member()
	world=load("res://scripts/Battle.gd").new();root.add_child(world)
	world.setup(camp.m4,preload("res://scripts/m4/LevelBuilder.gd").build(camp.m4,camp.m2,0,[hero_data]),camp.font,{})
	world.set_process(false);world.animations_enabled=false;world.sfx_enabled=false
	var hero=world.unit_by_slot(0);hero.item_slots=[2,0,0,0,0,0,0,0];world.selected=hero;world.busy=false;world.phase="player"
	world._item_options(1)
	await process_frame;await process_frame
	var before:Dictionary=hero.state_record()
	await held_click(Vector2(400,370))
	check(info_child()!=null and world.busy,"held item Examine click survives its own left release")
	await create_timer(0.2).timeout
	check(info_child()!=null,"item information stays open while idle")
	await held_click(Vector2(620,450),MOUSE_BUTTON_RIGHT)
	check(info_child()==null and not world.busy and world.context_menu!=null,"fresh right click closes once and restores six-action menu")
	check(hero.state_record()==before,"examine and close never spend action, items or growth")
	await close_info();world._close_context_menu()
	# The common information component must protect every kind, and consume
	# opening releases even after several frames, not by an arbitrary timer.
	for kind in ["item","mine","person"]:
		var choice=load("res://scripts/ui/OriginalChoice.gd").new();root.add_child(choice)
		var opened:Array=[]
		choice.chosen.connect(func(_index):
			choice.queue_free()
			var info=Info.new();root.add_child(info);opened.append(info)
			info.setup(camp.font,camp.m2,kind,0,hero_data)
		)
		choice.setup(camp.font,["view"],Vector2(360,280))
		await held_click(Vector2(400,295))
		check(opened.size()==1 and is_instance_valid(opened[0]) and not opened[0]._closed,"shared %s info survives originating held press/release"%kind)
		await held_click(Vector2(620,450))
		check(opened.size()==1 and not is_instance_valid(opened[0]),"shared %s info closes on next independent left click"%kind)
		if opened.size()==1 and is_instance_valid(opened[0]):opened[0].close()
		await process_frame
	# A release-based item picker can otherwise use its opening click to pick.
	var chooser=load("res://scripts/ui/OriginalChoice.gd").new();root.add_child(chooser)
	var picked:Array=[];var pickers:Array=[]
	chooser.chosen.connect(func(_index):
		chooser.queue_free()
		var picker=load("res://scripts/ui/OriginalItemPicker.gd").new();root.add_child(picker);pickers.append(picker)
		picker.chosen.connect(func(id):picked.append(id);picker.queue_free())
		picker.setup(camp.font,camp.m4,[2,0,0,0,0,0,0,0])
	)
	chooser.setup(camp.font,["items"],Vector2(180,150))
	await held_click(Vector2(210,160))
	check(picked.is_empty() and pickers.size()==1 and is_instance_valid(pickers[0]),"item picker ignores release belonging to its opening menu click")
	await held_click(Vector2(210,160))
	check(picked==[1] and not is_instance_valid(pickers[0]),"item picker accepts next independent click exactly once")
	# Preserve inherited native flag separately from the opening gesture gate.
	OriginalUI.native_wait_left_blocked=true
	var inherited=Info.new();root.add_child(inherited);inherited.setup(camp.font,camp.m2,"item",0)
	await process_frame;await process_frame
	await held_click(Vector2(620,450))
	check(is_instance_valid(inherited) and not OriginalUI.native_wait_left_blocked,"inherited native flag consumes exactly one left-UP")
	await held_click(Vector2(620,450))
	check(not is_instance_valid(inherited),"native wait closes on following left-UP")
	OriginalUI.native_wait_left_blocked=true
	inherited=Info.new();root.add_child(inherited);inherited.setup(camp.font,camp.m2,"item",0)
	await process_frame;await process_frame
	await held_click(Vector2(620,450),MOUSE_BUTTON_RIGHT)
	check(not is_instance_valid(inherited) and OriginalUI.native_wait_left_blocked,"right-UP closes without erasing inherited left flag")
	OriginalUI.native_wait_left_blocked=false
	# Right-UP shop entry must not swallow an extra subsequent right click.
	world.queue_free();camp.queue_free();await process_frame;await process_frame
	camp=load("res://scripts/m4/Campaign.gd").new();root.add_child(camp);camp.setup(load("res://assets/font/hzk16.fnt"));camp.qa_mode=true
	camp.selected_town=1;camp._open_shop("junxie");await process_frame;await process_frame
	var stock_before:Dictionary=camp.state.items.duplicate(true);var money:int=camp.state.money
	await held_click(Vector2(48,85),MOUSE_BUTTON_RIGHT)
	check(is_instance_valid(camp.info_panel),"shop right-release information remains open")
	await create_timer(0.2).timeout
	check(is_instance_valid(camp.info_panel),"shop information remains open while idle")
	await held_click(Vector2(48,85),MOUSE_BUTTON_RIGHT)
	check(not is_instance_valid(camp.info_panel),"next right-release closes shop info without reopening it")
	check(stock_before==camp.state.items and money==camp.state.money and camp.shop_pending.is_empty(),"shop inspect has no trade or selection side effects")
	camp.queue_free();await process_frame;await process_frame
	root.get_node("Music").release_playback();OriginalUI.release_native_sfx();await create_timer(.2).timeout
	var f=FileAccess.open("res://../out/modal_entry_input_test.json",FileAccess.WRITE);f.store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"\t"));f.close()
	print("MODAL_ENTRY_INPUT checks=",checks," failures=",failures)
	if failures==0:print("MODAL_ENTRY_INPUT PASS")
	quit(1 if failures else 0)
