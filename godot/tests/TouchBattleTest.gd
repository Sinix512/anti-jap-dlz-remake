extends SceneTree
# Isolated real ScreenTouch/Drag transactions; no user saves or campaign runs.
const State=preload("res://scripts/m2/GameState.gd")
const Builder=preload("res://scripts/m4/LevelBuilder.gd")
class Observer extends RefCounted:
	var status_text:=""
	func on_tick() -> void:pass
	func on_unit_moved(_u) -> void:pass
	func on_unit_died(_u) -> void:pass
	func check_end() -> bool:return false
class Probe extends Control:
	var left:=0
	var right:=0
	var releases:=0
	var backs:=0
	var raw_backs:=0
	var last:=Vector2.ZERO
	func _input(event:InputEvent) -> void:
		if event is InputEventMouseButton:
			last=event.position
			if event.pressed:
				if event.button_index==MOUSE_BUTTON_LEFT:left+=1
				else:right+=1
			else:releases+=1
			get_viewport().set_input_as_handled()
		elif event is InputEventKey:
			if event.keycode==KEY_ESCAPE and event.pressed:backs+=1
			if event.keycode==KEY_BACK:raw_backs+=1
			get_viewport().set_input_as_handled()
var checks:=0
var failures:=0
var bridge
var b
var hero
var enemy
var capture_dir:=""
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:
		failures+=1;push_error("TOUCH_BATTLE_FAIL "+label)
func screen(point:Vector2,down:bool,index:=0,canceled:=false,physical:=false) -> void:
	var e:=InputEventScreenTouch.new();e.position=point;e.pressed=down;e.index=index;e.canceled=canceled
	root.push_input(e,not physical)
func drag(from:Vector2,to:Vector2,index:=0) -> void:
	var e:=InputEventScreenDrag.new();e.position=to;e.relative=to-from;e.index=index
	root.push_input(e,true)
func tap(point:Vector2,physical:=false) -> void:
	screen(point,true,0,false,physical);screen(point,false,0,false,physical)
	await process_frame
func tile_point(tile:Vector2i) -> Vector2:
	return Vector2(tile*48+Vector2i(24,24))-b.camera.position+Vector2(320,240)
func settle() -> void:
	for _i in range(160):
		await process_frame
		if not b.busy and not b.progress_fx_active and b.action_resolution_depth==0:return
func answer_confirm(accepted:bool) -> void:
	var dialog=b.action_panel
	check(is_instance_valid(dialog) and dialog.get_script().resource_path.ends_with("OriginalConfirm.gd"),"action-ending choice opens a visible confirmation")
	if not is_instance_valid(dialog):return
	await tap(dialog.origin+Vector2(64,32+dialog.row_height*(0 if accepted else 1)+dialog.row_height/2.0))
	await settle()
func reset_actor() -> void:
	b._close_context_menu();b._close_action_panel();b.busy=false;b.finished_flag=false;b.phase="player"
	hero.set_tile(10,10);hero.alive=true;hero.acted=false;hero.moved=false;hero.control=true;hero.auto=false
	hero.bingzhong=1;hero.select=int(b.data.unit_types[1].select);hero.data.faction=0;hero.side="player"
	hero.data.level=99;hero.data.wuli=100;hero.data.zhili=100;hero.data.xp=0;hero.attack_count=0
	hero.hp=10000;hero.max_hp=10000;hero.morale=100;hero.integrity=100
	enemy.set_tile(10,9);enemy.hp=10000;enemy.max_hp=10000;enemy.alive=true
	enemy.data.faction=1;enemy.side="enemy";enemy.data.zhili=1;enemy.data.level=1
	b.terrain.fill(0);b._clear_selection()
	b.camera.position=b._focus_position(hero.position);b._clamp_camera();b.camera_follow=false
func capture(name:String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name()=="headless":return
	for _i in range(2):await process_frame
	RenderingServer.force_sync();RenderingServer.force_draw()
	DirAccess.make_dir_recursive_absolute(capture_dir)
	var image:=root.get_texture().get_image()
	check(image!=null and image.save_png(capture_dir.path_join(name+".png"))==OK,"capture "+name)

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-touch="):capture_dir=arg.trim_prefix("--capture-touch=")
	bridge=root.get_node_or_null("TouchInput")
	if bridge==null:
		bridge=load("res://scripts/ui/TouchInput.gd").new();bridge.name="TouchInput";root.add_child(bridge)
	bridge.set_touch_mode(true)
	check(bridge.is_touch_mode(),"touch mode enabled")
	var probe:=Probe.new();probe.mouse_filter=Control.MOUSE_FILTER_IGNORE;root.add_child(probe)
	var p:=Vector2(200,150)
	screen(p,true);check(probe.left==0,"finger down never clicks or trades")
	screen(p,false);check(probe.left==1 and probe.releases==1 and probe.last==p,"tap emits one paired transaction at same viewport position")
	screen(p,true);drag(p,p+Vector2(60,0));screen(p+Vector2(60,0),false)
	check(probe.left==1 and probe.releases==1,"drag does not generate accidental click")
	bridge.long_press_ms=0;await tap(p);bridge.long_press_ms=550
	check(probe.left==1 and probe.right==1 and probe.releases==2,"long press emits right transaction only")
	screen(p,true);screen(p,false,0,true)
	check(probe.left==1 and probe.right==1,"canceled touch has no transaction")
	screen(p,true);screen(p+Vector2(40,0),true,1);screen(p,false);screen(p+Vector2(40,0),false,1)
	check(probe.left==1 and not bridge.is_pointer_down(),"second finger cancels gesture through both releases")
	screen(p,true);bridge.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT);screen(p,false)
	check(probe.left==1 and not bridge.is_pointer_down(),"background suspension cannot leave a held pointer")
	bridge.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	check(probe.backs==1 and not Input.is_key_pressed(KEY_ESCAPE),"Android back is one local cancel, no held key")
	# Real Android trace: notification -> native DOWN/UP -> notification.
	# Coalesce backend duplicates, not separate physical key presses.
	bridge.native_android_back=true
	await process_frame
	bridge.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	var native_back:=InputEventKey.new();native_back.keycode=KEY_BACK;native_back.physical_keycode=KEY_BACK;native_back.pressed=true
	root.push_input(native_back,true)
	native_back=InputEventKey.new();native_back.keycode=KEY_BACK;native_back.physical_keycode=KEY_BACK;native_back.pressed=false
	root.push_input(native_back,true)
	bridge.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	check(probe.raw_backs==0 and probe.backs==2,"native Android DOWN/UP plus two notifications produces one cancel only")
	native_back=InputEventKey.new();native_back.keycode=KEY_BACK;native_back.pressed=true;native_back.echo=true
	root.push_input(native_back,true)
	bridge.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	check(probe.backs==2,"held native Back echo and its notification cannot close another layer")
	for _press in range(2):
		native_back=InputEventKey.new();native_back.keycode=KEY_BACK;native_back.pressed=true
		root.push_input(native_back,true)
		bridge.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
		native_back=InputEventKey.new();native_back.keycode=KEY_BACK;native_back.pressed=false
		root.push_input(native_back,true)
	await process_frame
	check(probe.backs==4,"two physical Back presses in one frame remain two cancels")
	bridge.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	check(probe.backs==5,"gesture-only notification still cancels without a native key")
	var hardware_escape:=InputEventKey.new();hardware_escape.keycode=KEY_ESCAPE;hardware_escape.pressed=true
	root.push_input(hardware_escape,true)
	check(probe.backs==6,"Android physical Escape remains usable; only native BACK is filtered")
	# Android defers the notification from process_key_event. It may arrive
	# after process_frame already flushed the native key's one cancel (MuMu).
	var back_baseline:int=probe.backs
	native_back=InputEventKey.new();native_back.keycode=KEY_BACK;native_back.pressed=true
	root.push_input(native_back,true)
	native_back=InputEventKey.new();native_back.keycode=KEY_BACK;native_back.pressed=false
	root.push_input(native_back,true)
	await process_frame
	check(probe.backs==back_baseline+1,"native Back is responsive before its deferred notification")
	bridge.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	check(probe.backs==back_baseline+1,"deferred native Back notification after flush cannot dismiss its parent")
	back_baseline=probe.backs
	native_back=InputEventKey.new();native_back.keycode=KEY_BACK;native_back.pressed=true;native_back.echo=true
	root.push_input(native_back,true)
	await process_frame
	bridge.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	check(probe.backs==back_baseline,"deferred echo notification is paired without a second cancel")
	bridge.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST) # Java onBackPressed first.
	native_back=InputEventKey.new();native_back.keycode=KEY_BACK;native_back.pressed=true
	root.push_input(native_back,true)
	native_back=InputEventKey.new();native_back.keycode=KEY_BACK;native_back.pressed=false
	root.push_input(native_back,true)
	await process_frame
	bridge.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST) # Deferred native notification.
	await process_frame
	check(probe.backs==back_baseline+1,"Java plus deferred native notification across frames stays one cancel")
	back_baseline=probe.backs
	for _press in range(2):
		native_back=InputEventKey.new();native_back.keycode=KEY_BACK;native_back.pressed=true
		root.push_input(native_back,true)
		native_back=InputEventKey.new();native_back.keycode=KEY_BACK;native_back.pressed=false
		root.push_input(native_back,true)
	await process_frame
	for _press in range(2):bridge.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	check(probe.backs==back_baseline+2,"two rapid physical Back presses retain two independent deferred notification pairs")
	bridge.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	check(probe.backs==back_baseline+3,"gesture-only Back after native pairs still cancels immediately")
	bridge.native_android_back=false
	# Root stretch must be applied exactly once, including a high-density display.
	root.size=Vector2i(1280,960);root.content_scale_size=Vector2i(640,480)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	await process_frame
	var physical:Vector2=root.get_final_transform()*p
	await tap(physical,true)
	check(probe.last.distance_to(p)<0.1 and probe.left==2,"2x viewport transform preserves touch hit coordinates")
	probe.free()
	# Real GUI scroll capture: swiping a bag/list must not activate its rows.
	var scroll:=ScrollContainer.new();scroll.position=Vector2(500,100);scroll.size=Vector2(120,200)
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;root.add_child(scroll)
	var list:=VBoxContainer.new();list.custom_minimum_size=Vector2(100,700);scroll.add_child(list)
	var row_clicks:={"count":0}
	for i in range(20):
		var button:=Button.new();button.text=str(i);button.custom_minimum_size=Vector2(100,40)
		button.pressed.connect(func():row_clicks.count+=1);list.add_child(button)
	for _i in range(3):await process_frame
	var scroll_point:=Vector2(540,164)
	screen(scroll_point,true);drag(scroll_point,scroll_point-Vector2(0,80));screen(scroll_point-Vector2(0,80),false)
	await process_frame
	check(scroll.scroll_vertical>0 and row_clicks.count==0,"list swipe scrolls without activating inventory row")
	await tap(scroll_point)
	check(row_clicks.count==1,"list row remains tappable after swipe")
	scroll.free()
	var m2:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/m2.json"))
	var m4:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/m4.json"))
	var gs=State.new();gs.new_game(m2);gs.setup_m4(m4)
	b=load("res://scripts/Battle.gd").new();root.add_child(b);b.fast_sim=true
	b.setup(m4,Builder.build(m4,m2,0,[gs.protagonist_member()]),load("res://assets/font/hzk16.fnt"),gs.battle_context())
	b.set_process(false);b.animations_enabled=false;b.sfx_enabled=false;b.scenario=Observer.new()
	b.mines.clear();b.chests.clear()
	hero=b.unit_by_slot(0)
	for u in b.units:
		if u!=hero:u.alive=false;u.visible=false
	var enemy_record:Dictionary=m4.levels[0].units[0].duplicate(true)
	enemy_record.merge({"slot":40,"pid":40,"hero":false,"name":"触控敌军","bingzhong":1,"side":"enemy","faction":1,"x":10,"y":9,"hp":10000,"max_hp":10000,"level":1,"wuli":10,"zhili":1,"control":false},true)
	enemy=b._spawn_unit(enemy_record)
	# Movement is reversible navigation, not an action commit. One tap on a
	# destination must stage the move, while a drag must never stage one.
	reset_actor();await tap(tile_point(Vector2i(10,10)))
	var destination:=Vector2i(11,10)
	var destination_point:=tile_point(destination)
	screen(destination_point,true)
	check(Vector2i(hero.x,hero.y)==Vector2i(10,10) and not hero.moved,"movement finger-down does not preempt a possible drag")
	drag(destination_point,destination_point+Vector2(70,0));screen(destination_point+Vector2(70,0),false)
	await settle()
	check(Vector2i(hero.x,hero.y)==Vector2i(10,10) and not hero.moved and not hero.acted,"drag in movement mode pans only, never moves or spends action")
	reset_actor();await tap(tile_point(Vector2i(10,10)))
	await tap(tile_point(destination));await settle()
	check(Vector2i(hero.x,hero.y)==destination and hero.moved and not hero.acted,"one destination tap immediately stages a move without ending action")
	check(is_instance_valid(b.context_menu) and b.native_range_phase=="menu","one destination tap reaches the action menu without a second confirm")
	check(b._touch_aim.x<0 and b.touch_confirm.disabled,"movement never leaves an aim or requests a confirm")
	await capture("single_tap_move_action_menu")
	bridge.request_back();await process_frame
	check(b.selected==null and Vector2i(hero.x,hero.y)==Vector2i(10,10) and not hero.moved and not hero.acted,"cancel after one-tap movement restores the original square and unspent action")
	reset_actor();await tap(tile_point(Vector2i(10,10)));await tap(tile_point(Vector2i(10,10)));await settle()
	check(Vector2i(hero.x,hero.y)==Vector2i(10,10) and is_instance_valid(b.context_menu) and not hero.acted,"one tap on selected actor's own square opens the action menu without spending action")
	reset_actor()
	await tap(tile_point(Vector2i(10,10)))
	check(b.selected==hero and b.mode=="move","tap selects controllable unit")
	b._on_attack()
	var point:=tile_point(Vector2i(10,9));var old_hp:int=enemy.hp;var old_count:int=hero.attack_count
	await tap(point)
	check(enemy.hp==old_hp and hero.attack_count==old_count and not hero.acted,"first attack tap is preview only")
	check(b.hover_tile==Vector2i(10,9) and not b.attack_preview_cells().is_empty() and not b.touch_confirm.disabled,"tap retains actual attack area and enables confirm")
	check(b.touch_cancel_button.is_visible_in_tree() and not b.touch_cancel_button.disabled and b.touch_cancel_button.text=="取消攻击","attack aim has an explicit enabled visible cancel button")
	for button in b.touch_layer.get_child(0).get_children():
		if not button is Button:continue
		check(Rect2(Vector2.ZERO,Vector2(640,480)).encloses(button.get_global_rect()) and not b.map_rect().intersects(button.get_global_rect()),"top button %s stays inside viewport and outside actionable map: button=%s map=%s"%[button.text,button.get_global_rect(),b.map_rect()])
	b._process(0.01)
	check(b.hover_tile==Vector2i(10,9),"idle mouse position cannot erase touchscreen aim")
	await capture("normal_attack_preview")
	await tap(b.touch_confirm.get_global_rect().get_center());await settle()
	check(enemy.hp<old_hp and hero.attack_count==old_count+1 and hero.acted,"explicit confirm resolves one attack only")
	await tap(b.touch_confirm.get_global_rect().get_center());await settle()
	check(hero.attack_count==old_count+1,"stale confirm cannot duplicate action")
	reset_actor();b._select_unit(hero);b._on_attack();await tap(tile_point(Vector2i(10,9)))
	await tap(b.touch_cancel_button.get_global_rect().get_center())
	check(b.selected==hero and b.mode=="idle" and is_instance_valid(b.context_menu) and not hero.acted and enemy.hp==10000,"visible attack cancel returns to actor menu without resolving or spending action")
	check(b._touch_aim.x<0 and b.touch_confirm.disabled,"visible cancel clears the old attack confirmation")
	reset_actor();b._select_unit(hero);b._on_attack();point=tile_point(Vector2i(10,9))
	var disappearing_modal:=Control.new();b.hud_root.add_child(disappearing_modal);b.action_panel=disappearing_modal
	screen(point,true)
	b.action_panel=null;disappearing_modal.free()
	screen(point,false);await process_frame
	check(enemy.hp==10000 and not hero.acted and b._touch_aim.x<0,"UI modal disappearing under held finger cannot fall through as map command")
	reset_actor();b._select_unit(hero);b._on_attack();point=tile_point(Vector2i(10,9))
	await tap(point);await tap(point);await settle()
	check(hero.acted and hero.attack_count==1,"second tap same target confirms exactly once")
	reset_actor();b._select_unit(hero);b._on_attack();point=tile_point(Vector2i(10,9))
	await tap(point)
	var camera_before:Vector2=b.camera.position
	screen(point,true);drag(point,point+Vector2(70,0));screen(point+Vector2(70,0),false)
	await process_frame
	check(b.camera.position!=camera_before and not hero.acted and enemy.hp==10000,"single-finger pan changes camera but never orders an action")
	check(b._touch_aim.x<0 and b.touch_confirm.disabled,"pan clears stale target confirmation")
	reset_actor();b._select_unit(hero);b._on_attack();await tap(tile_point(Vector2i(10,9)))
	bridge.request_back();await process_frame
	check(not hero.acted and b.mode=="idle" and is_instance_valid(b.context_menu),"one Android back cancels aim but preserves selected actor menu")
	bridge.request_back();await process_frame
	check(b.selected==null,"next Android back cancels only the remaining actor selection")
	reset_actor();bridge.long_press_ms=0;await tap(tile_point(Vector2i(10,9)));bridge.long_press_ms=550
	check(b.busy and b.selected==null and enemy.hp==10000,"long press inspects enemy, never attacks")
	bridge.request_back();await process_frame
	check(not b.busy and b.selected==null,"Android back closes info without map fallthrough")
	# Inspecting during a reversible move must not silently commit the move.
	reset_actor();b._select_unit(hero)
	var moved_tile:=Vector2i(11,10)
	await tap(tile_point(moved_tile));await settle()
	check(Vector2i(hero.x,hero.y)==moved_tile and hero.moved,"touch move stages original reversible movement")
	b._on_attack()
	var origin:Dictionary=b._selection_origin.duplicate(true)
	bridge.long_press_ms=0;await tap(tile_point(Vector2i(10,9)));bridge.long_press_ms=550
	check(b.busy and b.selected==hero and b._selection_origin==origin and Vector2i(hero.x,hero.y)==moved_tile,"inspection preserves actor, staged location and original move witness")
	bridge.request_back();await process_frame
	check(not b.busy and b.selected==hero and b.mode=="attack" and b._selection_origin==origin,"closing inspected unit restores original aim context")
	bridge.request_back();await process_frame
	bridge.request_back();await process_frame
	check(b.selected==null and Vector2i(hero.x,hero.y)==Vector2i(10,10) and not hero.moved,"cancel after inspection still restores original coordinates")
	reset_actor();b._select_unit(hero);await tap(tile_point(moved_tile));await settle()
	enemy.set_tile(11,9);b._on_attack();await tap(tile_point(Vector2i(11,9)))
	var moved_origin:Dictionary=b._selection_origin.duplicate(true)
	await tap(b.touch_cancel_button.get_global_rect().get_center())
	check(b.selected==hero and Vector2i(hero.x,hero.y)==moved_tile and b._selection_origin==moved_origin and not hero.acted and enemy.hp==10000,"visible attack cancel preserves the reversible movement witness and staged square")
	await tap(b.touch_cancel_button.get_global_rect().get_center())
	check(b.selected==null and Vector2i(hero.x,hero.y)==Vector2i(10,10) and not hero.moved and not hero.acted,"next visible cancel rolls staged movement back without spending action")
	reset_actor();b._select_unit(hero);b._close_context_menu();b.active_skill=b.data.skills[3];b.active_skill_id=3;b.mode="skill"
	b._target_native_range(hero,int(b.active_skill.select_fw),false,"skill-target")
	b.attack_tiles.clear()
	for tile in b.RangeMask.cells(b.native_dark_mask,b.map_w,b.map_h):b.attack_tiles[tile]=b._unit_at(tile)
	await tap(tile_point(Vector2i(10,9)))
	var cells:Array=b.skill_preview_cells()
	check(not cells.is_empty() and enemy.hp==10000 and not hero.acted,"strategy first tap only previews")
	var has_effect:=false;var has_ineffective:=false
	for cell in cells:
		check(cell.has_all(["chance","effective","pct","tile"]),"strategy uses real per-cell probability schema")
		if cell.effective:has_effect=true
		else:has_ineffective=true
	check(has_effect and has_ineffective,"strategy preview distinguishes effective and empty/ineffective cells")
	await capture("normal_strategy_probabilities")
	screen(tile_point(Vector2i(10,9)),true);bridge.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT);screen(tile_point(Vector2i(10,9)),false)
	check(b._touch_aim.x<0 and not hero.acted,"focus loss clears already-previewed aim and suppresses release")
	await tap(b.touch_cancel_button.get_global_rect().get_center())
	check(b.mode=="idle" and not hero.acted and is_instance_valid(b.context_menu),"visible strategy cancel is also usable before an action is committed")
	reset_actor();b._select_unit(hero);b._close_context_menu();b.active_skill=b.data.skills[3];b.active_skill_id=3;b.mode="skill"
	b._target_native_range(hero,int(b.active_skill.select_fw),false,"skill-target")
	var skill_count:int=hero.skill_counts[b.SKILL_KEYS[3]]
	await tap(tile_point(Vector2i(10,9)))
	check(not hero.acted and hero.skill_counts[b.SKILL_KEYS[3]]==skill_count,"strategy first target tap never spends action or practice")
	await tap(b.touch_confirm.get_global_rect().get_center());await settle()
	check(hero.acted and hero.skill_counts[b.SKILL_KEYS[3]]>skill_count,"strategy confirm commits its resolver and ends action")
	skill_count=hero.skill_counts[b.SKILL_KEYS[3]]
	await tap(b.touch_confirm.get_global_rect().get_center());await settle()
	check(hero.skill_counts[b.SKILL_KEYS[3]]==skill_count,"stale strategy confirm cannot cast a second time")
	# The action menu's wait row ends an action, unlike moving into that menu.
	reset_actor();await tap(tile_point(Vector2i(10,10)));await tap(tile_point(Vector2i(10,10)));await settle()
	await tap(b.context_menu.row_rect(0).get_center())
	check(not hero.acted and is_instance_valid(b.action_panel),"one tap on wait requests confirmation, not an action commit")
	await answer_confirm(false)
	check(b.selected==hero and not hero.acted and is_instance_valid(b.context_menu),"declining wait keeps actor selected and action unspent")
	await tap(b.context_menu.row_rect(0).get_center());await answer_confirm(true)
	check(hero.acted and b.selected==null,"accepting visible wait confirmation commits once")
	# Discard is another action-ending menu choice; cancellation must not take
	# inventory or act, but acceptance must preserve original one-item removal.
	reset_actor();hero.item_slots=[2,2,0,0,0,0,0,0];b._select_unit(hero);b._item_options(1)
	await tap(b.action_panel.row_rect(2).get_center())
	check(hero.item_slots.count(2)==2 and not hero.acted,"discard row tap does not consume stock before confirmation")
	await answer_confirm(false)
	check(hero.item_slots.count(2)==2 and not hero.acted and b.selected==hero,"declining discard preserves both inventory and action")
	b._item_options(1);await tap(b.action_panel.row_rect(2).get_center());await answer_confirm(true)
	check(hero.item_slots.count(2)==1 and hero.acted,"accepting discard removes only one carried item and ends action")
	# Item and mine transfers end an action only at the actual destination,
	# never on picker/navigation taps or the first target preview.
	reset_actor();hero.item_slots=[2,0,0,0,0,0,0,0];enemy.item_slots=[0,0,0,0,0,0,0,0]
	b._select_unit(hero);b._item_option(1,1);await tap(tile_point(Vector2i(10,9)))
	check(not hero.acted and hero.item_slots.has(2) and not enemy.item_slots.has(2) and not b.touch_confirm.disabled,"item transfer first target tap is preview only")
	await tap(b.touch_confirm.get_global_rect().get_center());await settle()
	check(hero.acted and not hero.item_slots.has(2) and enemy.item_slots.count(2)==1,"confirmed item transfer commits exactly one carried item")
	reset_actor();hero.mine_slots=[1,0,0,0,0,0,0,0];enemy.mine_slots=[0,0,0,0,0,0,0,0]
	b._select_unit(hero);b._choose_mine_transfer(0);await tap(tile_point(Vector2i(10,9)))
	check(not hero.acted and hero.mine_slots.has(1) and not enemy.mine_slots.has(1) and not b.touch_confirm.disabled,"mine transfer first target tap is preview only")
	await tap(b.touch_confirm.get_global_rect().get_center());await settle()
	check(hero.acted and not hero.mine_slots.has(1) and enemy.mine_slots.count(1)==1,"confirmed mine transfer commits exactly one carried mine")
	reset_actor();hero.item_slots=[2,0,0,0,0,0,0,0];hero.hp=5000
	b._select_unit(hero);b._choose_item(1);await tap(tile_point(Vector2i(10,10)))
	check(not hero.acted and hero.item_slots.has(2) and hero.hp==5000,"ordinary item target tap previews without consuming item or action")
	await tap(b.touch_confirm.get_global_rect().get_center());await settle()
	check(hero.acted and not hero.item_slots.has(2) and hero.hp>=5000,"item confirm consumes one item and completes the original action")
	reset_actor();hero.mine_slots=[1,0,0,0,0,0,0,0];b.data.mine_terrain[0].fill(1)
	b._select_unit(hero);b._choose_mine(0);await tap(tile_point(Vector2i(9,10)))
	check(not hero.acted and hero.mine_slots.has(1) and b._mine_at(Vector2i(9,10))<0,"ordinary mine first target tap only previews placement")
	await tap(b.touch_confirm.get_global_rect().get_center());await settle()
	check(hero.acted and not hero.mine_slots.has(1) and b._mine_at(Vector2i(9,10))>=0,"ordinary mine confirm commits stock, placement and action once")
	# For a timed mine, choosing a target merely opens the rounds chooser.
	# Only choosing a round is the committing confirmation; no extra target
	# confirmation should precede this non-ending navigation step.
	reset_actor();hero.mine_slots=[21,0,0,0,0,0,0,0];b.data.mine_terrain[5].fill(1)
	b._select_unit(hero);b._choose_mine(20);await tap(tile_point(Vector2i(11,10)))
	check(is_instance_valid(b.action_panel) and b.action_panel.entries.size()==10 and b._touch_aim.x<0 and hero.mine_slots.has(21) and not hero.acted,"timed-mine target opens rounds on one tap without placing or target confirm")
	if is_instance_valid(b.action_panel):await tap(b.action_panel.get_node("TouchBack").get_global_rect().get_center())
	check(not is_instance_valid(b.action_panel) and b.mode=="mine_place" and hero.mine_slots.has(21) and not hero.acted,"rounds cancel keeps timed-mine target context, stock and action")
	await tap(tile_point(Vector2i(11,10)))
	if is_instance_valid(b.action_panel):await tap(b.action_panel.row_rect(0).get_center())
	await settle()
	check(b._mine_at(Vector2i(11,10))>=0 and not hero.mine_slots.has(21) and hero.acted,"round choice itself confirms one timed-mine placement")
	# Promotion manuals retain their original inner semantics, but entering
	# that action-ending flow on touch must be explicitly confirmed first.
	reset_actor();hero.item_slots=[62,0,0,0,0,0,0,0];b._select_unit(hero);b._choose_item(61)
	check(not hero.acted and hero.item_slots.has(62),"manual use does not enter original action-ending flow before confirmation")
	await answer_confirm(false)
	check(not hero.acted and hero.item_slots.has(62) and b.selected==hero,"declining outer manual confirmation protects action and stock")
	reset_actor();hero.bingzhong=4;hero.data.bingzhong=4;hero.data.level=1;hero.item_slots=[64,0,0,0,0,0,0,0]
	b._select_unit(hero);b._choose_item(63);await answer_confirm(true)
	check(b.busy and not hero.acted and is_instance_valid(b.action_panel),"accepting outer manual warning enters, but does not skip, original class-change choice")
	await answer_confirm(false)
	check(hero.acted and hero.bingzhong==4 and hero.item_slots.has(64),"after outer acceptance, original inner manual NO still ends action without consuming book")
	reset_actor();hero.bingzhong=4;hero.data.bingzhong=4;hero.data.level=1;hero.item_slots=[62,0,0,0,0,0,0,0]
	b._select_unit(hero);b._choose_item(61)
	check(not hero.acted and is_instance_valid(b.action_panel),"incompatible manual also waits for explicit outer confirmation")
	await answer_confirm(true)
	check(hero.acted and hero.item_slots.has(62) and not b.busy,"after acceptance, incompatible manual preserves original action cost without consuming book")
	reset_actor();b._toggle_map_mode()
	check(b.map_rect().position.y>=32 and b.map_rect().end.y<=464,"full map reserves touch controls without covering actionable cells")
	await capture("fullscreen_touch_chrome")
	await tap(Vector2(468,16));await process_frame
	check(is_instance_valid(b.context_menu),"touch menu remains accessible in fullscreen")
	await capture("fullscreen_system_menu")
	var menu=b.context_menu
	if is_instance_valid(menu):
		for row in range(menu.entries.size()):
			check(Rect2(0,0,640,480).encloses(menu.row_rect(row)),"system row %d is within touch viewport"%row)
		await tap(menu.row_rect(12).get_center())
		check(not b.fullscreen_map and not is_instance_valid(b.context_menu),"last system-menu row is tappable and exits full map")
	b.free();await process_frame
	# A non-battle screen can also change while the finger is held. Neither
	# a new modal nor its uncovered parent may receive that old gesture.
	var parent_probe:=Probe.new();root.add_child(parent_probe)
	screen(p,true)
	var modal_probe:=Probe.new();root.add_child(modal_probe)
	screen(p,false)
	check(modal_probe.left==0 and parent_probe.left==0,"new UI suppresses a tap begun on its parent")
	await tap(p)
	check(modal_probe.left==1,"new UI accepts its next independent tap")
	screen(p,true);modal_probe.free();screen(p,false)
	check(parent_probe.left==0,"removed UI cannot release-click its uncovered parent")
	await tap(p)
	check(parent_probe.left==1,"parent accepts a fresh tap after modal dismissal")
	parent_probe.free()
	print("TOUCH_BATTLE ","PASS" if failures==0 else "FAIL"," checks=",checks," failures=",failures)
	quit(1 if failures else 0)
