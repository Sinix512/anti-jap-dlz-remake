extends SceneTree
## Default desktop stays on native mouse/keyboard even if touch events arrive.
## --touch-ui is separately exercised as the explicit test/debug opt-in.
const State=preload("res://scripts/m2/GameState.gd")
const Builder=preload("res://scripts/m4/LevelBuilder.gd")
class Observer extends RefCounted:
	var status_text:=""
	func on_tick() -> void:pass
	func on_unit_moved(_u) -> void:pass
	func on_unit_died(_u) -> void:pass
	func check_end() -> bool:return false
class Probe extends Node:
	var synthetic_presses:=0
	var native_presses:=0
	var native_releases:=0
	var escapes:=0
	func _input(event:InputEvent) -> void:
		if event is InputEventMouseButton:
			if event.device==1001 and event.pressed:synthetic_presses+=1
			elif event.device!=1001:
				if event.pressed:native_presses+=1
				else:native_releases+=1
		elif event is InputEventKey and event.keycode==KEY_ESCAPE and event.pressed:escapes+=1
var checks:=0
var failures:=0
var bridge
var b
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("DESKTOP_TOUCH_OPT_IN_FAIL "+label)
func screen(point:Vector2,down:bool) -> void:
	var e:=InputEventScreenTouch.new();e.position=point;e.pressed=down;e.index=0
	root.push_input(e,true)
func touch_tap(point:Vector2) -> void:
	screen(point,true);screen(point,false)
	await process_frame
func touch_drag(point:Vector2) -> void:
	screen(point,true)
	var e:=InputEventScreenDrag.new();e.position=point+Vector2(60,0);e.relative=Vector2(60,0);e.index=0
	root.push_input(e,true);screen(e.position,false)
	await process_frame
func mouse_click(point:Vector2) -> void:
	var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point
	root.push_input(motion,true)
	for down in [true,false]:
		var e:=InputEventMouseButton.new();e.position=point;e.global_position=point
		e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down
		root.push_input(e,true)
	await process_frame
func tile_point(tile:Vector2i) -> Vector2:
	return Vector2(tile*48+Vector2i(24,24))-b.camera.position+Vector2(320,240)
func menu_row(index:int) -> void:
	check(is_instance_valid(b.context_menu),"desktop action menu is available before row %d"%index)
	if not is_instance_valid(b.context_menu):return
	await mouse_click(b.context_menu.row_rect(index).get_center())
func desktop_target_cancel(hero) -> void:
	# Grant one real strategy in this isolated fixture, then enter each target
	# mode through the real native action/strategy menu mouse routes.
	hero.skill_counts[b.SKILL_KEYS[3]]=1
	var position_before:=Vector2i(hero.x,hero.y)
	var attacks_before:int=hero.attack_count
	var hp_before:int=hero.hp
	var rng_before:int=b.rng_state
	var staged_origin:Dictionary=b._selection_origin.duplicate(true)
	for fullscreen in [false,true]:
		var label:="fullscreen" if fullscreen else "normal"
		if b.fullscreen_map!=fullscreen:
			b._close_context_menu();b._toggle_map_mode();b._open_context_menu()
			await process_frame
		await menu_row(1)
		await process_frame
		check(b.mode=="attack" and not is_instance_valid(b.context_menu),label+" real attack menu click enters targeting")
		check(b.btn_cancel.is_visible_in_tree() and not b.btn_cancel.disabled and b.btn_cancel.text=="取消攻击",label+" attack has a visible named ordinary HUD cancel")
		check(b.btn_cancel.get_global_rect()==Rect2(8,2,80,28) and b.btn_cancel.get_combined_minimum_size().y<=28,label+" attack button layout and themed minimum fit the 32px top strip")
		check(not b.btn_cancel.get_global_rect().intersects(b.map_rect()),label+" attack cancel does not cover actionable map cells")
		check(b.touch_layer==null and not bridge.is_touch_mode(),label+" desktop attack creates no touch chrome")
		if fullscreen:
			check(b.desktop_cancel_header.is_visible_in_tree() and b.map_rect().position.y>=32,"fullscreen attack reserves a separate non-map cancel strip")
		await mouse_click(b.btn_cancel.get_global_rect().get_center())
		check(b.mode=="idle" and b.selected==hero and is_instance_valid(b.context_menu),label+" cancel attack click returns to actor action menu")
		check(not hero.acted and hero.moved and hero.attack_count==attacks_before and hero.hp==hp_before and b.rng_state==rng_before,label+" cancel attack never consumes action, attacks, HP or RNG")
		check(Vector2i(hero.x,hero.y)==position_before and b._selection_origin==staged_origin,label+" cancel attack preserves reversible staged movement")
		check(not b.btn_cancel.is_visible_in_tree() and b.touch_layer==null,label+" cancel hides outside targeting without enabling touch UI")
		if fullscreen:
			check(not b.desktop_cancel_header.is_visible_in_tree() and b.map_rect().position.y==0,"fullscreen actor menu restores the full map outside targeting")
		await menu_row(2)
		check(is_instance_valid(b.action_panel),label+" native strategy menu opens from mouse click")
		if not is_instance_valid(b.action_panel):continue
		var skill_ids:Array=b.available_skills(hero)
		var skill_row:int=skill_ids.find(3)
		check(skill_row>=0,label+" strategy fixture exposes an actual available strategy")
		if skill_row<0:continue
		await mouse_click(b.action_panel.row_rect(skill_row).get_center())
		await process_frame
		check(b.mode=="skill" and b.active_skill_id==3,label+" real strategy row click enters target selection")
		check(b.btn_cancel.is_visible_in_tree() and not b.btn_cancel.disabled and b.btn_cancel.text=="取消策略",label+" strategy has a visible named ordinary HUD cancel")
		check(b.btn_cancel.get_global_rect()==Rect2(8,2,80,28) and b.btn_cancel.get_combined_minimum_size().y<=28,label+" strategy button layout and themed minimum fit the 32px top strip")
		check(not b.btn_cancel.get_global_rect().intersects(b.map_rect()),label+" strategy cancel does not cover actionable map cells")
		if fullscreen:
			check(b.desktop_cancel_header.is_visible_in_tree() and b.map_rect().position.y>=32,"fullscreen strategy reserves a separate non-map cancel strip")
		await mouse_click(b.btn_cancel.get_global_rect().get_center())
		check(b.mode=="idle" and b.selected==hero and is_instance_valid(b.context_menu) and b.active_skill_id==-1,label+" cancel strategy click returns to actor menu and clears targeting")
		check(not hero.acted and hero.moved and hero.attack_count==attacks_before and hero.hp==hp_before and b.rng_state==rng_before,label+" cancel strategy does not resolve effects or consume action")
		check(Vector2i(hero.x,hero.y)==position_before and b._selection_origin==staged_origin and b.touch_layer==null,label+" cancel strategy retains staged movement without touch adaptation")
func run() -> void:
	check(not OS.has_feature("mobile"),"this fixture runs against the desktop export")
	bridge=root.get_node_or_null("TouchInput")
	check(bridge!=null,"real TouchInput autoload exists")
	if bridge==null:quit(1);return
	var explicit_opt_in:=OS.get_cmdline_user_args().has("--touch-ui")
	check(bridge.is_touch_mode()==explicit_opt_in,"startup opts in only with explicit --touch-ui, never by touch hardware")
	var probe:=Probe.new();root.add_child(probe)
	await touch_tap(Vector2(200,150))
	check(bridge.is_touch_mode()==explicit_opt_in,"receiving real ScreenTouch cannot change startup policy")
	check(probe.synthetic_presses==(1 if explicit_opt_in else 0),"touch synthesis occurs only after explicit opt-in")
	await touch_drag(Vector2(200,150))
	check(probe.synthetic_presses==(1 if explicit_opt_in else 0),"drag never adds a synthetic click")
	bridge.set_touch_mode(false)
	await touch_tap(Vector2(200,150));await touch_drag(Vector2(200,150))
	check(not bridge.is_touch_mode() and not bridge.is_pointer_down() and bridge._fingers.is_empty(),"disabled desktop adapter ignores ScreenTouch and ScreenDrag without retained gesture state")
	check(probe.synthetic_presses==(1 if explicit_opt_in else 0),"desktop touch never silently re-enables or emits extra mouse events")
	await mouse_click(Vector2(200,150))
	check(probe.native_presses==1 and probe.native_releases==1,"ordinary native mouse pair passes unchanged")
	var escape:=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=true
	root.push_input(escape,true)
	check(probe.escapes==1,"ordinary desktop Escape passes unchanged")
	probe.free()
	var m2:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/m2.json"))
	var m4:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/m4.json"))
	var state=State.new();state.new_game(m2);state.setup_m4(m4)
	b=load("res://scripts/Battle.gd").new();root.add_child(b);b.fast_sim=true
	b.setup(m4,Builder.build(m4,m2,0,[state.protagonist_member()]),load("res://assets/font/hzk16.fnt"),state.battle_context())
	b.set_process(false);b.animations_enabled=false;b.sfx_enabled=false;b.scenario=Observer.new()
	b.mines.clear();b.chests.clear();b.terrain.fill(0);b.busy=false;b.finished_flag=false;b.phase="player"
	var hero=b.unit_by_slot(0)
	for u in b.units:
		if u!=hero:u.alive=false;u.visible=false
	hero.set_tile(10,10);hero.acted=false;hero.moved=false;hero.control=true;hero.auto=false
	b._clear_selection();b.camera.position=b._focus_position(hero.position);b._clamp_camera();b.camera_follow=false
	check(b.touch_layer==null and not b._touch_mode(),"desktop battle builds no touch chrome")
	await touch_tap(tile_point(Vector2i(10,10)))
	check(b.selected==null and b.touch_layer==null,"touch input cannot activate alternate battle UI or issue a command")
	await mouse_click(tile_point(Vector2i(10,10)))
	check(b.selected==hero and b.mode=="move" and b.touch_layer==null,"desktop native click still selects actor through normal map route")
	await mouse_click(tile_point(Vector2i(11,10)))
	for _i in range(160):
		await process_frame
		if not b.busy and not b.progress_fx_active:break
	check(Vector2i(hero.x,hero.y)==Vector2i(11,10) and hero.moved and not hero.acted,"desktop movement stays one-click reversible, without touch confirmation")
	check(not bridge.is_touch_mode() and b.touch_layer==null,"mouse play never activates touch adaptation")
	if not explicit_opt_in:await desktop_target_cancel(hero)
	b.free();await process_frame
	print("DESKTOP_TOUCH_OPT_IN PASS checks=%d failures=%d explicit=%s"%[checks,failures,explicit_opt_in])
	quit(0 if failures==0 else 1)
