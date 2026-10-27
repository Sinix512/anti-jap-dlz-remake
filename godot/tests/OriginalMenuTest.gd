extends SceneTree
# Bounded native-menu/UI fixtures; never campaign completion evidence.
const Choice=preload("res://scripts/ui/OriginalChoice.gd")
const Confirm=preload("res://scripts/ui/OriginalConfirm.gd")
const Rules=preload("res://scripts/battle/CombatRules.gd")
var checks:=0
var failures:=0
var m4:Dictionary
var font:Font
var b
var answers:Array=[]
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("MENU_FAIL "+label)
func motion(point:Vector2) -> void:
	var event:=InputEventMouseMotion.new();event.position=point;event.global_position=point;root.push_input(event,true)
func mouse(point:Vector2,button:int,pressed:bool) -> void:
	var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=button;event.pressed=pressed;root.push_input(event,true)
func key(code:int,pressed:bool) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.pressed=pressed;root.push_input(event,true)
func make_choice(lines:Array,at:=Vector2(276,196),cancellable:=true):
	answers.clear()
	var c=Choice.new();root.add_child(c);c.setup(font,lines,at,cancellable,[],cancellable)
	c.chosen.connect(func(index:int):answers.append(index))
	c.cancelled.connect(func():answers.append(-1))
	return c
func fixture() -> void:
	if b!=null:b.free()
	b=load("res://scripts/Battle.gd").new();root.add_child(b)
	b.setup(m4.duplicate(true),m4.levels[22].duplicate(true),font,{"campaign_story":true})
	b.set_process(false);b.animations_enabled=false;b.sfx_enabled=false;b.fast_sim=false;b.busy=false
	for u in b.units:u.free()
	b.units.clear();b.player_units.clear();b.enemy_units.clear();b.scenario.start_phase_pending=false
	for slot in [0,25,40]:
		var d:Dictionary=m4.levels[0].units[0].duplicate(true)
		d.merge({"slot":slot,"pid":slot,"name":"fixture%d"%slot,"side":"player" if slot==0 else "enemy","faction":0 if slot==0 else 1,"x":2+slot%7,"y":2+slot/7,"hp":100,"max_hp":100,"morale":100,"level":3,"xp":0,"item_slots":[0,0,0,0,0,0,0,0],"mine_slots":[0,0,0,0,0,0,0,0],"control":slot==0,"bingzhong":1},true)
		b._spawn_unit(d)
func run() -> void:
	m4=JSON.parse_string(FileAccess.get_file_as_string("res://data/m4.json"));font=load("res://assets/font/hzk16.fnt")
	for count in [1,2,3,6,8,13,16]:
		var c=make_choice(range(count).map(func(i):return str(i)),Vector2(276,236-12*count))
		check(c.frame==Rect2(276,236-12*count,88,32 if count==1 else 24*count+16),"native frame n%d"%count)
		check(c.choice==0 and not c.done and c.selected_row.visible==(count>1),"native initial row/no auto execution n%d"%count)
		check(c.labels[0].position==Vector2(288,(228 if count==1 else 248-12*count)),"native text origin n%d"%count)
		if count>1:check(c.selected_row.texture.get_size()==Vector2(80,24) and c.selected_row.position==c.frame.position+Vector2(4,8),"literal LUT strip n%d"%count)
		c.free()
	var c=make_choice(["枪  毙","放  逐","收  编"],Vector2(276,196),false)
	check(c.frame==Rect2(276,196,88,88) and c.labels[0].text=="枪  毙" and c.get_child_count()==1 and c.get_child(0)==c.raster_root and c.raster_root.get_child_count()==5 and c.raster_root.clip_contents and c.raster_root.size==Vector2(640,284) and not c.roll_open and c.drawn_heights.is_empty(),"426E7D paints complete H immediately with only original frame/strip/labels, no title or dim")
	mouse(Vector2(300,264),MOUSE_BUTTON_LEFT,false);key(KEY_ENTER,false);key(KEY_ESCAPE,true)
	mouse(Vector2(20,20),MOUSE_BUTTON_RIGHT,true);mouse(Vector2(20,20),MOUSE_BUTTON_RIGHT,false)
	check(answers.is_empty() and c.choice==0 and not c.done,"426E7D ignores key/right/DOWN-UP and left-UP")
	motion(Vector2(0,252));check(c.choice==2,"426E7D hover accepts left screen edge")
	motion(Vector2(640,208));motion(Vector2(20,276));motion(Vector2(20,203))
	check(c.choice==2,"native hover right/bottom/top exclusive bounds retain row")
	mouse(Vector2(20,20),MOUSE_BUTTON_LEFT,true)
	check(answers==[2] and c.done,"426E7D arbitrary left-DOWN confirms existing row, not click y")
	mouse(Vector2(300,208),MOUSE_BUTTON_LEFT,false);mouse(Vector2(300,208),MOUSE_BUTTON_LEFT,true)
	check(answers==[2],"one physical decision cannot dispatch twice")
	c.free()
	c=make_choice(["补给  1"],Vector2(276,224))
	motion(Vector2(20,470));key(KEY_SPACE,false)
	check(answers.is_empty() and c.choice==0,"426844 no hover/key or automatic selection")
	mouse(Vector2(20,20),MOUSE_BUTTON_RIGHT,false);check(answers.is_empty(),"426844 ignores right-UP")
	mouse(Vector2(20,20),MOUSE_BUTTON_RIGHT,true);check(answers==[-1],"426844 right-DOWN cancels anywhere");c.free()
	answers.clear()
	var confirm=Confirm.new();root.add_child(confirm);confirm.setup(font,"升级吗？")
	confirm.answered.connect(func(yes:bool):answers.append(yes))
	check(confirm.choice==0 and confirm.options[0].position==Vector2(376,236),"42738A original default/geometry")
	motion(Vector2(639,260));check(confirm.choice==1,"42738A full screen x hover no")
	key(KEY_ENTER,false);mouse(Vector2(20,20),MOUSE_BUTTON_LEFT,false)
	check(answers.is_empty(),"42738A ignores keys and left-UP")
	mouse(Vector2(360,240),MOUSE_BUTTON_LEFT,true)
	check(answers==[false],"42738A left-DOWN confirms prior no despite yes-row click coordinates")
	confirm.free()
	for pick in range(3):
		fixture()
		var hero=b.unit_by_slot(0)
		await b.scenario.on_tick()
		var choice=b._choice_layer.get_child(0)
		check(not b.scenario.pending_choice.is_empty() and b.busy and not b.can_save() and not b.finished_flag,"real L22 blocks result/save before choice%d"%pick)
		check(choice.entries==["枪  毙","放  逐","收  编"] and int(b.scenario.pending_choice.default)==0 and not choice.roll_open and choice.drawn_heights.is_empty() and choice.raster_root.size.y==choice.frame.end.y,"generated L22 exact labels/default0 and direct full-height native426E7D")
		motion(Vector2(20,208+24*pick));mouse(Vector2(600,450),MOUSE_BUTTON_LEFT,true)
		for step in range(3):await process_frame
		check(b.finished_flag and b.last_result=="victory" and b.scenario.pending_choice.is_empty() and b._choice_layer==null,"real L22 choice%d resumes and closes exactly once"%pick)
		if pick==0:check(int(hero.data.level)==5 and int(b.stats.get("money_bonus",0))==0,"L22 first/default row grants real levels, not exile money")
		elif pick==1:check(int(hero.data.level)==3 and int(b.stats.money_bonus)==5000,"L22 exile grants original money branch")
		else:check(int(b.get_slot_field(25,"faction"))==0 and not b.unit_by_slot(25).control,"L22 recruit changes side only, not control")
	fixture()
	var hero=b.unit_by_slot(0);b.selected=hero;hero.attack_count=70
	for sid in range(16):hero.skill_counts[b.SKILL_KEYS[sid]]=0
	b._open_context_menu()
	check(b.context_menu.entries==["休  息","攻  击 5","策  略","地  雷","物  品","情  报"] and b.context_menu.frame==Rect2(320,240,88,160) and b.native_dark_mask.count(1)==0 and not b.native_range_layer.visible,"six original labels/attack level; range canvas synchronously cleared before saved MENU background")
	var timer:int=b.display_timer_count;b._advance_display_timer(0.6)
	check(b.display_timer_count==timer,"blocking native menu pauses shared idle timer")
	b._open_skill_menu();check(b.action_panel==null and b.context_menu!=null and not hero.acted,"no skills immediately returns six actions")
	for sid in [0,7,15]:hero.skill_counts[b.SKILL_KEYS[sid]]=1 if sid!=7 else 300
	b._open_skill_menu()
	check(b.action_panel.entries==["补给  1","骚扰 10","空袭  1"] and b.action_panel.frame==Rect2(276,200,88,88),"skills sparse sid order and literal width2 level labels")
	motion(Vector2(639,232));mouse(Vector2(20,20),MOUSE_BUTTON_LEFT,true);await process_frame
	check(b.mode=="skill" and b.active_skill_id==7 and not hero.acted,"skill row1 maps to actual sid7, no cast/action spent")
	b._cancel();b._open_skill_menu();mouse(Vector2(20,20),MOUSE_BUTTON_RIGHT,true);await process_frame
	check(b.action_panel==null and b.context_menu!=null and b.selected==hero and not hero.acted,"skill picker cancel reopens six menu without cancelling actor")
	b._close_context_menu();b._open_system_menu(Vector2(620,450))
	check(b.context_menu.frame==Rect2(551,151,88,328) and b.context_menu.entries[0]=="退 出" and b.context_menu.entries[12]=="分 屏","system thirteen native frame/clamp/spacing")
	b._close_context_menu();b.selected=hero;hero.acted=false;hero.mine_slots=[0,0,0,0,0,0,0,0];b.mines.clear()
	check(b.can_mine(hero),"five operations have no carried/map mine gate")
	b._on_mine()
	check(b.action_panel.frame==Rect2(300,280,88,136) and b.action_panel.entries==["埋 设","起 出","定 时","遥 控","交 给"],"five operation original geometry/spacing/order")
	motion(Vector2(639,316));mouse(Vector2(20,20),MOUSE_BUTTON_LEFT,true);await process_frame
	check(b.mode=="mine_recover" and b.action_panel==null and b.native_dark_mask.count(0)==8 and not hero.acted,"empty bag can enter geometric recover without spending action")
	b._cancel();b._on_mine();mouse(Vector2(20,20),MOUSE_BUTTON_RIGHT,true);await process_frame
	check(b.action_panel==null and b.context_menu!=null and b.selected==hero,"five-operation cancel returns six menu, not deselect")
	b._close_context_menu();b.selected=hero;b._on_mine();mouse(Vector2(20,20),MOUSE_BUTTON_LEFT,true);await process_frame
	check(b.action_panel==null and b.context_menu!=null and not hero.acted,"empty carried-mine picker returns six actions")
	b._close_context_menu();b.selected=hero;hero.mine_slots=[23,0,0,0,0,0,0,0];b.mine_kind=22;b._place_mine()
	var tile:Vector2i=b._mine_place_tiles(hero,22).keys()[0]
	var mask:PackedByteArray=b.native_dark_mask.duplicate();var before_mode:String=b.mode
	b._choose_timer(tile,true)
	check(b.action_panel.frame==Rect2(276,112,88,256) and b.action_panel.entries[0]=="一回合" and b.action_panel.entries[9]=="十回合","timer uses original ten-row native list")
	mouse(Vector2(20,20),MOUSE_BUTTON_RIGHT,true);mouse(Vector2(20,20),MOUSE_BUTTON_RIGHT,false);await process_frame
	check(b.action_panel==null and b.mode==before_mode and b.native_dark_mask==mask and hero.mine_slots[0]==23 and not hero.acted,"timer place cancel preserves target/mask/stock/action including paired UP")
	b._choose_timer(tile,true);motion(Vector2(20,340));mouse(Vector2(600,450),MOUSE_BUTTON_LEFT,true);await process_frame
	check(b._mine_at(tile)>=0 and int(b.mines[b._mine_at(tile)].low)==11 and hero.acted and not hero.mine_slots.has(23),"native tenth timer choice writes low11 and spends one mine/action")
	hero.acted=false;b.selected=hero;b._mine_command("timer");mask=b.native_dark_mask.duplicate()
	b._choose_timer(tile,false);mouse(Vector2(20,20),MOUSE_BUTTON_RIGHT,true);mouse(Vector2(20,20),MOUSE_BUTTON_RIGHT,false);await process_frame
	check(b.mode=="mine_timer" and b.native_dark_mask==mask and int(b.mines[b._mine_at(tile)].low)==11 and not hero.acted,"existing timer cancel preserves low and target mode")
	b.queue_free();b=null;await process_frame
	print("ORIGINAL_MENU checks=",checks," failures=",failures)
	quit(1 if failures else 0)
