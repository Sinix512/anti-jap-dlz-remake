extends SceneTree
const Readout=preload("res://scripts/ui/OriginalReadout.gd")
var checks:=0
var failures:=0
var b
var m4:Dictionary
var font:Font
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("TOOLBAR_FAIL "+label)
func mouse(button:int,pressed:bool,point:=Vector2(20,450)) -> void:
	var event:=InputEventMouseButton.new();event.position=point;event.global_position=event.position;event.button_index=button;event.pressed=pressed;root.push_input(event,true)
func motion(point:Vector2) -> void:
	var event:=InputEventMouseMotion.new();event.position=point;event.global_position=point;root.push_input(event,true)
func key(pressed:bool) -> void:
	var event:=InputEventKey.new();event.keycode=KEY_ENTER;event.pressed=pressed;root.push_input(event,true)
func spawn(slot:int,faction:=0,controllable:=true):
	var unit:Dictionary=m4.levels[0].units[0].duplicate(true)
	unit.merge({"slot":slot,"pid":slot,"faction":faction,"name":"单位%d"%slot,"x":slot%10+2,"y":slot/10+2,"hp":90,"max_hp":90,"level":3,"morale":76,"control":controllable,"bingzhong":1,"behavior":1},true)
	b._spawn_unit(unit);return b.unit_by_slot(slot)
func fixture() -> void:
	if b!=null:b.free()
	b=load("res://tests/helpers/ToolbarBattleFixture.gd").new();root.add_child(b)
	b.setup(m4.duplicate(true),m4.levels[22].duplicate(true),font,{"campaign_story":true,"score_total":12345})
	b.set_process(false);b.busy=false;b.fast_sim=false;b.animations_enabled=false;b.sfx_enabled=false;b.scenario.start_phase_pending=false
	for u in b.units:u.free()
	b.units.clear();b.player_units.clear();b.enemy_units.clear()
	spawn(0);spawn(1);spawn(2,0,false);spawn(40,2)
func run() -> void:
	m4=JSON.parse_string(FileAccess.get_file_as_string("res://data/m4.json"));font=load("res://assets/font/hzk16.fnt")
	fixture();b.animation_speed=1;b._toolbar(8)
	check(b.action_panel.frame==Rect2(282,32,88,136),"normal speed original coordinates")
	check(b.action_panel.entries==["最 快","较 快 *","普 通","较 慢","最 慢"] and b.action_panel.choice==0,"speed current marker distinct from default row0")
	key(true);key(false);mouse(MOUSE_BUTTON_LEFT,false)
	check(b.animation_speed==1 and is_instance_valid(b.action_panel),"speed ignores key and UP")
	motion(Vector2(639,140));mouse(MOUSE_BUTTON_LEFT,true);mouse(MOUSE_BUTTON_LEFT,false)
	check(b.animation_speed==4 and b.action_panel==null and b.requested_end_turn.is_empty(),"speed DOWN confirms remembered row4 without turn advance")
	b._toolbar(8,true)
	check(b.action_panel.frame==Rect2(320,200,88,136) and b.action_panel.entries[4]=="最 慢 *" and b.action_panel.choice==0,"system speed fixed origin/current marker/default0")
	mouse(MOUSE_BUTTON_RIGHT,true);mouse(MOUSE_BUTTON_RIGHT,false)
	check(b.action_panel==null and b.animation_speed==4 and b.requested_end_turn.is_empty(),"speed right DOWN cancels without setting/turn")
	b._ask_end_turn()
	check(b.action_panel.frame==Rect2(500,32,88,88) and b.action_panel.entries==["原地待命","跟随主将","各自为战"],"normal end three original labels/geometry")
	mouse(MOUSE_BUTTON_RIGHT,true);mouse(MOUSE_BUTTON_RIGHT,false)
	check(b.action_panel==null and b.requested_end_turn.is_empty() and not b.unit_by_slot(1).acted,"end cancel no action changes")
	b._ask_end_turn(true)
	check(b.action_panel.frame==Rect2(320,200,88,88) and b.action_panel.choice==0,"system end geometry/default0")
	mouse(MOUSE_BUTTON_LEFT,true);mouse(MOUSE_BUTTON_LEFT,false)
	check(b.unit_by_slot(0).acted and b.unit_by_slot(1).acted and not b.unit_by_slot(2).acted and not b.unit_by_slot(40).acted,"policy0 affects only active side0 unacted controllable")
	check(b.requested_end_turn==[false],"policy0 dispatches central turn once without remaining AI")
	fixture();var hero=b.unit_by_slot(0);var ally=b.unit_by_slot(1);var npc=b.unit_by_slot(2);var enemy=b.unit_by_slot(40)
	b._end_turn_order(-1)
	check(b.requested_end_turn.is_empty() and not ally.acted,"negative menu result no turn advance")
	b._end_turn_order(1)
	check(ally.behavior==5 and ally.target_x==hero.x and ally.target_y==hero.y and not ally.acted,"policy1 follows hero destination and retains action for AI")
	check(npc.behavior==1 and enemy.behavior==1 and b.requested_end_turn==[true],"policy1 excludes NPC/nonzero sides and invokes remaining AI")
	fixture();hero=b.unit_by_slot(0);ally=b.unit_by_slot(1);npc=b.unit_by_slot(2)
	hero.behavior=7;ally.behavior=7;npc.behavior=7;ally.acted=true;b._end_turn_order(2)
	check(hero.behavior==1 and ally.behavior==7 and npc.behavior==7 and ally.acted and b.requested_end_turn==[true],"policy2 retains acted/NPC availability and enables free AI")
	fixture();hero=b.unit_by_slot(0);hero.alive=false;b._end_turn_order(1)
	check(b.unit_by_slot(1).acted and b.unit_by_slot(1).behavior==1 and b.requested_end_turn==[false],"absent hero forces policy0")
	fixture();b._show_task();var r=b.action_panel
	check(r.pages.size()==1 and r.labels.size()==10 and r.get_child_count()==11,"task contains only native backdrop and ten literal fields")
	check(r.labels[0].text=="第" and r.labels[1].text=="23" and r.labels[3].text==b.level.name,"task one-based number/name")
	check(r.labels[4].position==Vector2(100,120) and r.labels[5].position==Vector2(200,120) and r.labels[6].text=="失败条件：","task native condition coordinates")
	check(r.labels[8].text=="当前得分：" and r.labels[9].text=="12345" and r.labels[9].position==Vector2(500,400),"task native score preserved")
	mouse(MOUSE_BUTTON_LEFT,true);mouse(MOUSE_BUTTON_LEFT,false)
	check(b.action_panel==r and not r.skip_left and not r.done,"425A08 first left UP swallowed; DOWN does not close")
	key(true);mouse(MOUSE_BUTTON_RIGHT,true);motion(Vector2(10,10))
	check(b.action_panel==r and not r.done,"425A08 key/right DOWN and MOVE ignored")
	mouse(MOUSE_BUTTON_LEFT,false)
	check(b.action_panel==null,"425A08 subsequent left UP closes without a position hitbox")
	b.level.index=45;b._show_task();r=b.action_panel
	check(r.labels[0].text=="休闲关" and r.labels.size()==8,"task leisure prefix for45 and46")
	key(false);check(b.action_panel==null,"task arbitrary key UP closes")
	# Normal toolbar starts on201/DOWN, before its own202/UP is swallowed.
	mouse(MOUSE_BUTTON_LEFT,true,Vector2(540,16));r=b.action_panel
	check(r!=null and r.skip_left,"real normal toolbar task opens on left DOWN")
	mouse(MOUSE_BUTTON_LEFT,false,Vector2(540,16))
	check(b.action_panel==r and not r.skip_left,"opening toolbar UP is swallowed, not the next user click")
	key(false)
	for slot in range(41,65):spawn(slot,2)
	b.unit_by_slot(41).behavior=11;b.unit_by_slot(41).hp=20;b.unit_by_slot(42).hp=40;b.unit_by_slot(43).hp=70
	b.unit_by_slot(44).placed=false;b.unit_by_slot(45).alive=false
	b._show_roster("enemy");r=b.action_panel
	check(r.pages.size()==2 and r.labels[0].text=="单位40" and r.labels[11].text=="单位41","nonzero side2 roster sorted by slot, 12 rows/page, no header")
	check(r.labels[11].position==Vector2(92,126) and r.labels[12].position==Vector2(184,126),"native name/class columns and26px rows")
	check(r.pages[0][15].color==0xb7 and r.pages[0][27].color==0x8a and r.pages[0][38].color==0x48,"native HP thirds B7/8A/48")
	check(r.labels[22].text=="乱" and r.pages[0][22].color==0xb7,"behavior11 red state column")
	check(r.pages[0].any(func(e):return e.text=="单位44") and not r.pages[0].any(func(e):return e.text=="单位45"),"active unplaced included, stage0 excluded")
	mouse(MOUSE_BUTTON_RIGHT,true);check(r.page==0,"roster right DOWN does not advance")
	mouse(MOUSE_BUTTON_RIGHT,false)
	check(b.action_panel==r and r.page==1 and r.skip_left and r.labels[0].text=="单位53","right UP advances one page not entire roster; new left gate")
	mouse(MOUSE_BUTTON_LEFT,false);check(b.action_panel==r and not r.skip_left,"each page resets first left UP gate")
	key(false);check(b.action_panel==null,"last roster page key UP restores underlying scene")
	b._show_roster("player");r=b.action_panel
	check(r.pages.size()==1 and r.labels[0].text=="单位0" and r.labels.size()==33,"side0 roster includes uncontrolled ally")
	mouse(MOUSE_BUTTON_RIGHT,false)
	for u in b.units:u.alive=false
	b._show_roster("enemy");check(b.action_panel==null,"empty roster does not create wait/page")
	# Three-page event sequence, independent of static screenshot fixtures.
	b._open_readout([[{"text":"A","at":Vector2(92,100)}],[{"text":"B","at":Vector2(92,100)}],[{"text":"C","at":Vector2(92,100)}]])
	r=b.action_panel
	mouse(MOUSE_BUTTON_LEFT,false)
	check(r.page==0 and not r.skip_left and not r.done,"three-page first left-UP stays on first page")
	mouse(MOUSE_BUTTON_LEFT,false)
	check(r.page==1 and r.skip_left and not r.done,"second left-UP advances exactly one page and resets gate")
	mouse(MOUSE_BUTTON_LEFT,false)
	check(r.page==1 and not r.skip_left,"second page first left-UP swallowed again")
	mouse(MOUSE_BUTTON_RIGHT,false)
	check(r.page==2 and r.skip_left and not r.done,"right-UP without DOWN advances exactly one page")
	key(false)
	check(b.action_panel==null and r.done and preload("res://scripts/ui/OriginalUI.gd").native_wait_left_blocked,"key-UP closes last page without clearing shared gate")
	# Every palette color is independently expected through the original LUT.
	var source:=Image.create(256,1,false,Image.FORMAT_RGBA8)
	for index in range(256):source.set_pixel(index,0,Color8(int(m4.meta.battle_palette[index*3]),int(m4.meta.battle_palette[index*3+1]),int(m4.meta.battle_palette[index*3+2])))
	var dark:Image=Readout.darken(source,m4.meta.battle_palette,m4.meta.map_dark_lut);var wrong:=0
	for index in range(256):
		var to:int=int(m4.meta.map_dark_lut[index])*3
		if dark.get_pixel(index,0)!=Color8(int(m4.meta.battle_palette[to]),int(m4.meta.battle_palette[to+1]),int(m4.meta.battle_palette[to+2])):wrong+=1
	check(wrong==0 and source.get_pixel(72,0)!=dark.get_pixel(72,0),"6223B0 original256 palette colors exact remap, not alpha dim")
	b.free();b=null;await process_frame;await create_timer(0.5).timeout
	print("ORIGINAL_TOOLBAR checks=",checks," failures=",failures)
	quit(1 if failures else 0)
