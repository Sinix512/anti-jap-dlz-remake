extends SceneTree
var checks:=0
var failures:=0
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("INPUT_FAIL "+label)
func _init() -> void:call_deferred("_run")
func pointer(point:Vector2,button:=MOUSE_BUTTON_LEFT,pressed:=true) -> void:
	var event=InputEventMouseButton.new()
	event.position=point;event.global_position=point
	event.button_index=button;event.pressed=pressed
	root.push_input(event,true)
func motion(point:Vector2) -> void:
	var event=InputEventMouseMotion.new();event.position=point;event.global_position=point
	root.push_input(event,true)
func key(code:int) -> void:
	var event=InputEventKey.new();event.keycode=code;event.pressed=true;root.push_input(event,true)
	event=event.duplicate();event.pressed=false;root.push_input(event,true)
func _run() -> void:
	var main=load("res://Main.tscn").instantiate();main.qa_mode=true
	root.add_child(main);await process_frame
	main._start_campaign()
	var camp=main.campaign;camp.qa_mode=true
	camp.state.data=camp.state.data.duplicate(true)
	camp.state.data.meta.save_prefix="dlz_qa_input_"
	camp._launch_level(0,false,[-100])
	for i in range(150):
		if is_instance_valid(camp.story_player):camp.story_player._finish()
		if is_instance_valid(camp.cutscene):camp.cutscene._finish()
		await process_frame
		if camp.battle_story_queue.is_empty() and not is_instance_valid(camp.story_player) and not is_instance_valid(camp.cutscene):break
	for i in range(10):await process_frame
	var b=camp.battle;b.set_process(false)
	var u=b.unit_by_slot(0)
	# 41B53C starts unselected. Begin with a real viewport click, not auto-select.
	b.camera.force_update_scroll();await process_frame
	var initial_point:Vector2=b.get_global_transform_with_canvas()*u.position
	motion(initial_point);await process_frame
	pointer(initial_point);pointer(initial_point,MOUSE_BUTTON_LEFT,false);await process_frame
	check(b.selected==u and b.native_range_phase=="move","initial real click selects native move mask")
	var origin:=Vector2i(u.x,u.y)
	var targets:Array=b.move_tiles.keys().duplicate()
	var tested:=0
	# Reset only the test fixture between clicks, not a campaign-play certificate.
	# Exercise every opening blue tile through viewport press/release, including
	# shifted camera positions (original fixed 1:1 scale); no direct _player_move calls.
	for camera_shift in [Vector2.ZERO,Vector2(48,0),Vector2(0,-48)]:
		for target in targets:
			if target==origin:continue
			await settle_dialogues(camp,b)
			u.set_tile(origin.x,origin.y);u.moved=false;u.acted=false
			b._close_context_menu();await process_frame
			b._select_unit(u);b.camera_follow=false
			b.camera.zoom=Vector2.ONE
			b.camera.position=b._focus_position(Vector2(target.x*48+24,target.y*48+24))+camera_shift
			b._clamp_camera();b.camera.force_update_scroll()
			await process_frame
			var screen:Vector2=b.get_global_transform_with_canvas()*Vector2(target.x*48+24,target.y*48+24)
			if not b.map_rect().grow(-2).has_point(screen):continue
			check(b.screen_to_tile(screen)==target,"coordinate roundtrip %s scale%s"%[target,camera_shift])
			# Camera/fixture resets move UI under a stationary synthetic pointer.
			# Let GUI hover routing consume that motion before the real press.
			motion(screen);await process_frame
			pointer(screen);pointer(screen,MOUSE_BUTTON_LEFT,false)
			for tick in range(300):
				await create_timer(0.01).timeout
				if is_instance_valid(camp.story_player):camp.story_player._finish()
				if is_instance_valid(camp.cutscene):camp.cutscene._finish()
				if not b.busy and u.moved:break
			if not (u.moved and Vector2i(u.x,u.y)==target):print("CLICK_DEBUG target=",target," screen=",screen," xy=",u.x,",",u.y," moved=",u.moved," mode=",b.mode," busy=",b.busy," blue=",b.move_tiles.has(target)," hover=",root.gui_get_hovered_control()," history=",b.input_history.slice(-3))
			check(u.moved and Vector2i(u.x,u.y)==target,"blue tile click %s scale%s"%[target,camera_shift])
			tested+=1
	check(tested>=20,"multiple blue cells tested, got %d"%tested)
	b._close_context_menu();await process_frame
	u.set_tile(origin.x,origin.y);u.moved=false;u.acted=false;b._select_unit(u)
	var before:Vector2=b.camera.position
	var point:=Vector2(220,220)
	pointer(point,MOUSE_BUTTON_RIGHT);motion(point+Vector2(60,0));pointer(point+Vector2(60,0),MOUSE_BUTTON_RIGHT,false)
	await process_frame
	check(b.camera.position!=before,"right drag pans camera")
	check(Vector2i(u.x,u.y)==origin and not u.moved,"pan never moves unit")
	pointer(Vector2(540,250));pointer(Vector2(540,250),MOUSE_BUTTON_LEFT,false);await process_frame
	check(Vector2i(u.x,u.y)==origin,"sidebar click never leaks into map")
	key(KEY_F);await process_frame
	check(b.fullscreen_map,"keyboard full-map opens")
	key(KEY_F);await process_frame
	check(not b.fullscreen_map,"keyboard full-map closes")
	pointer(Vector2(220,220),MOUSE_BUTTON_RIGHT);pointer(Vector2(220,220),MOUSE_BUTTON_RIGHT,false)
	await process_frame
	check(not b.busy and Vector2i(u.x,u.y)==origin,"right cancel leaves stable unit")
	# Exercise the native two-step cancellation through actual viewport events.
	await settle_dialogues(camp,b)
	b._clear_selection();u.set_tile(origin.x,origin.y);u.moved=false;u.acted=false
	u.direction=2;b.camera.position=b._focus_position(u.position);b._clamp_camera();b.camera.force_update_scroll()
	await process_frame
	var hero_point:Vector2=b.get_global_transform_with_canvas()*u.position
	motion(hero_point);await process_frame;pointer(hero_point);pointer(hero_point,MOUSE_BUTTON_LEFT,false);await process_frame
	check(b.selected==u and b.native_range_phase=="move","mouse reselect builds movement mask")
	var native_destination:Vector2i=b.move_tiles.keys()[0]
	var destination_point:Vector2=b.get_global_transform_with_canvas()*Vector2(native_destination*48+Vector2i(24,24))
	motion(destination_point);await process_frame;pointer(destination_point);pointer(destination_point,MOUSE_BUTTON_LEFT,false)
	for i in range(300):
		await create_timer(0.01).timeout
		if is_instance_valid(camp.story_player):camp.story_player._finish()
		if not b.busy and u.moved:break
	await settle_dialogues(camp,b)
	check(b.native_range_phase=="menu" and b.native_dark_mask.count(0)==b.map_w*b.map_h,"mouse move clears mask into action menu")
	# Original426A05 deliberately ignores keys; select attack via MOVE then DOWN.
	key(KEY_1);await process_frame
	check(b.mode=="idle" and is_instance_valid(b.context_menu),"native action menu ignores keyboard shortcuts")
	motion(Vector2(360,284));pointer(Vector2(360,284));pointer(Vector2(360,284),MOUSE_BUTTON_LEFT,false);await process_frame
	check(b.mode=="attack" and b.native_range_phase=="attack-target","native attack row opens target mask")
	var snapshot:PackedByteArray=b.native_dark_mask.duplicate()
	var dark_point:=Vector2(-1,-1)
	for y in range(50,440,48):
		for x in range(32,420,48):
			var cell:Vector2i=b.screen_to_tile(Vector2(x,y))
			if b._in_bounds(cell) and snapshot[cell.y*b.map_w+cell.x]!=0:dark_point=Vector2(x,y)
	check(dark_point.x>=0,"visible invalid target located")
	if dark_point.x>=0:
		motion(dark_point);await process_frame;pointer(dark_point);pointer(dark_point,MOUSE_BUTTON_LEFT,false);await process_frame
	check(b.mode=="attack" and b.native_dark_mask==snapshot,"mouse invalid target preserves range")
	pointer(Vector2(50,50),MOUSE_BUTTON_RIGHT);pointer(Vector2(50,50),MOUSE_BUTTON_RIGHT,false);await process_frame
	check(b.mode=="idle" and b.native_range_phase=="menu" and is_instance_valid(b.context_menu),"mouse target cancel reopens bright menu")
	check(b.native_dark_mask.count(0)==b.map_w*b.map_h and Vector2i(u.x,u.y)==native_destination,"target cancel keeps provisional destination, no move mask")
	pointer(Vector2(50,50),MOUSE_BUTTON_RIGHT);pointer(Vector2(50,50),MOUSE_BUTTON_RIGHT,false);await process_frame
	check(b.selected==null and Vector2i(u.x,u.y)==origin and u.direction==2 and not u.moved,"second mouse cancel restores pre-move position/direction")
	check(b.native_dark_mask.count(0)==b.map_w*b.map_h,"cancel leaves full world bright")
	main.queue_free();await process_frame;await create_timer(0.5).timeout
	print("INPUT_PROBE checks=",checks," failures=",failures," moves=",tested)
	print("INPUT_PROBE_OK" if failures==0 else "INPUT_PROBE_FAIL")
	quit(1 if failures else 0)

func settle_dialogues(camp,b) -> void:
	# Movement may enqueue a tutorial/story after its own coroutine returns.
	# A human waits for that modal; do not reset the fixture underneath it.
	var stable:=0
	for i in range(150):
		if is_instance_valid(camp.story_player):camp.story_player._finish()
		if is_instance_valid(camp.cutscene):camp.cutscene._finish()
		await process_frame
		if camp.battle_story_queue.is_empty() and not is_instance_valid(camp.story_player) and not is_instance_valid(camp.cutscene) and not b.busy and not b.progress_fx_active:
			stable+=1
			if stable>=3:return
		else:stable=0
	push_error("INPUT_FAIL modal/action did not settle before next fixture")
