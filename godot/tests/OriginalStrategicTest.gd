extends SceneTree
const Screen=preload("res://scripts/ui/OriginalStrategicScreen.gd")
const Deployment=preload("res://scripts/ui/OriginalDeployment.gd")
const Builder=preload("res://scripts/m4/LevelBuilder.gd")
const SavePicker=preload("res://scripts/ui/OriginalSavePicker.gd")
const Confirm=preload("res://scripts/ui/OriginalConfirm.gd")
const Scores=preload("res://scripts/ui/OriginalHighScores.gd")
const Rules=preload("res://scripts/m4/TownRules.gd")
class ProbeCampaign extends "res://scripts/m4/Campaign.gd":
	var launched:Array=[]
	var ending_count:=0
	func _play_media(_idx:int,cb:Callable) -> void:cb.call()
	func _launch_level(idx:int,standalone:bool,slots:Array=[]) -> void:
		launched.append({"idx":idx,"standalone":standalone,"slots":slots.duplicate()})
	func _show_ending(_forced:=-1) -> void:ending_count+=1
var checks:=0
var failures:=0
var c
var entered:Array=[]
var systems:Array=[]
var commands:Array=[]
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("STRATEGIC_FAIL "+label)
func mouse(point:Vector2,down:bool,button:=MOUSE_BUTTON_LEFT,double:=false) -> void:
	var e:=InputEventMouseButton.new();e.position=point;e.global_position=point;e.button_index=button;e.pressed=down;e.double_click=double;root.push_input(e,true)
func move(point:Vector2) -> void:
	var e:=InputEventMouseMotion.new();e.position=point;e.global_position=point;root.push_input(e,true)
func key(code:int) -> void:
	var e:=InputEventKey.new();e.keycode=code;e.pressed=true;root.push_input(e,true)
func settle() -> void:await process_frame
func run() -> void:
	c=ProbeCampaign.new();root.add_child(c);c.qa_mode=true;c.setup(load("res://assets/font/hzk16.fnt"));c.m5={}
	c.state.data=c.state.data.duplicate(true);c.state.data.meta.save_prefix="dlz_qa_strategic_"
	for slot in range(5):
		c.state.delete_slot(slot);DirAccess.remove_absolute(ProjectSettings.globalize_path(preload("res://scripts/ui/OriginalSaveSlots.gd").native_path(c.state,slot)))
	var s=c.strategic_screen
	check(c.mode=="world" and s is Screen and s.find_children("*","BaseButton",true,false).is_empty(),"actual BIGMAP has no modern buttons/cards")
	s.town_enter.connect(func(i:int):entered.append(i));s.system_requested.connect(func(p:Vector2):systems.append(p))
	for town in s.contract.world.towns:
		var r:Array=town.rect;var p:=Vector2(r[0],r[1])
		check(s.town_at(p)==int(town.index) and s.town_at(p+Vector2(47,15))==int(town.index),"19 original world rect boundary "+str(town.index))
	mouse(Vector2(495,348),true);check(c.mode=="world","world DOWN does not enter town")
	key(KEY_ENTER);check(c.mode=="world","no invented keyboard world selection")
	mouse(Vector2(120,188),false);check(c.mode=="world" and entered.is_empty(),"locked town UP silent")
	move(Vector2(550,21));check(s.mine_hover,"BIGMINE original hover")
	mouse(Vector2(550,21),false);check(c.panel_root==null,"system UP alone ignored")
	mouse(Vector2(550,21),true);check(c.panel_root.entries==["退  出","音  乐","音  效","读  档","存  档"] and systems.size()==1,"system DOWN original five rows")
	check(c.panel_root.frame==Rect2(550,21,88,136),"original system origin from DOWN")
	mouse(Vector2.ZERO,true,MOUSE_BUTTON_RIGHT);await settle();check(c.panel_root==null and c.mode=="world","system right-DOWN cancel restores world")
	mouse(Vector2(495,348),false);await settle()
	check(c.mode=="town" and c.selected_town==0 and entered==[0],"world UP directly enters unlocked town")
	for t in range(19):
		c._show_town(t);s=c.strategic_screen
		check(s.find_children("*","BaseButton",true,false).is_empty() and s.palette.size()==768,"town no extra shortcuts and actual PLACE palette "+str(t))
		for b in s.contract.towns[t].buildings:
			if not b.enabled:continue
			var r:Array=b.rect;var point:=Vector2(r[0]+r[2]/2,r[1]+r[3]/2)
			var expected:=-1
			for slot in [0,2,5,3,4,1]:
				var q:Array=s.contract.towns[t].buildings[slot].rect
				if q[2]>0 and Rect2(q[0],q[1],q[2],q[3]).has_point(point):expected=slot;break
			check(s.building_at(point)==expected,"native six building priority "+str(t)+"/"+str(b.slot))
	c._show_world();c._show_town(4);c._show_room("resident");s=c.strategic_screen
	check(c.mode=="resident" and s.palette==preload("res://scripts/ui/OriginalPalette.gd").colors("BIGMAP"),"BG02 final 96A790 BIGMAP palette, not PLACE")
	mouse(Vector2(550,50),true);check(c.mode=="resident","room exit DOWN ignored")
	mouse(Vector2(539,50),false);check(c.mode=="resident","room exit outside exact rect ignored")
	mouse(Vector2(550,50),false);await settle();check(c.mode=="town","resident exit LEFT-UP returns PLACE")
	c._show_room("command");check(c.strategic_palette_key=="BACK19","command loads BACK19 palette")
	mouse(Vector2(460,1),false);await settle();c._show_room("resident")
	check(c.strategic_screen.palette==preload("res://scripts/ui/OriginalPalette.gd").colors("BACK19"),"later BG02 inherits last full IMG target palette")
	c._show_town(0);c._open_command();check(c.mode=="command" and c.panel_root==null,"town0 commander empty, not resident redirect")
	Rules.set_flag(c.state,0,0);c._service_heal()
	check(c.mode=="resident" and Rules.get_flag(c.state,0)==1 and c.panel_root.origin==Vector2(320,200),"first resident phase1 before original confirm")
	mouse(Vector2.ZERO,true,MOUSE_BUTTON_RIGHT);await settle()
	check(c.mode=="resident" and Rules.get_flag(c.state,0)==1 and c.launched.is_empty(),"first departure cancel stays room/phase1")
	c._show_first_departure();move(Vector2(1,263));mouse(Vector2.ZERO,true);await settle()
	check(c.mode=="resident" and Rules.get_flag(c.state,0)==1,"first departure no also preserves phase1")
	c._show_first_departure();mouse(Vector2.ZERO,true);await settle()
	check(c.mode=="deployment" and Rules.get_flag(c.state,0)==2 and c.deployment_screen.count()==1,"first departure yes enters fresh K00")
	c._show_town(1);Rules.set_flag(c.state,6,0);c._open_mission()
	check(c.mode=="command" and Rules.get_flag(c.state,6)==1 and c.panel_root.origin==Vector2(320,200),"ordinary commander prechoice phase preserved")
	mouse(Vector2.ZERO,true,MOUSE_BUTTON_RIGHT);await settle();check(c.mode=="command" and Rules.get_flag(c.state,6)==1,"ordinary cancel stays BACK19/phase1")
	c._show_town(15);Rules.set_flag(c.state,75,1);Rules.set_flag(c.state,76,0);c._open_mission()
	check(c.panel_root.entries==["肖  飞","李霜泗"] and c.panel_root.frame==Rect2(320,200,88,64),"solo direct original two rows, no extra brief/confirmation")
	mouse(Vector2.ZERO,true,MOUSE_BUTTON_RIGHT);await settle();check(c.mode=="command" and Rules.get_flag(c.state,76)==1 and c.launched.is_empty(),"solo cancel no battle, stays phase1")
	for choice in range(2):
		Rules.set_flag(c.state,76,1);c._open_mission()
		if choice==1:move(Vector2(1,238))
		mouse(Vector2.ZERO,true);await settle()
		check(c.launched[-1].slots==[8+choice] and Rules.get_flag(c.state,2)==choice and Rules.get_flag(c.state,76)==2,"solo choice original slot "+str(choice))
	for slot in range(32):c.state.set_person_side(slot,0)
	c._show_deployment(34);var d=c.deployment_screen
	check(d.count()==1 and d.member(1,0).pid==-100 and d.pages==[0,0],"K00 fresh entry only forced, no auto optional/reuse")
	check(d.FORCED==Color("#fc0000") and d.find_children("*","BaseButton",true,false).is_empty(),"forced red and no modern buttons")
	mouse(Vector2(361,75),true);check(d.drag.is_empty(),"forced cannot drag")
	mouse(Vector2(361,75),true,MOUSE_BUTTON_LEFT,true);mouse(Vector2(33,75),false);check(d.count()==1,"forced cannot doubleclick remove")
	check(d.hit_member(Vector2(80,75),0)==-1 and d.hit_member(Vector2(79,137),0)==0,"48x64 hit and 24px gutter")
	mouse(Vector2(33,75),true);check(d.count()==1 and not d.drag.is_empty(),"K00 DOWN only takes drag, no transfer")
	mouse(Vector2(33,75),false);check(d.count()==1 and d.drag.is_empty(),"source DOWN-UP does not toggle")
	mouse(Vector2(33,75),true);move(Vector2(900,800));check(d.drag_point==Vector2(591,431),"drag48 clamp exact native")
	mouse(Vector2(350,100),false);check(d.count()==1,"invalid drop no transfer")
	mouse(Vector2(33,75),true);mouse(Vector2(610,340),false)
	check(d.count()==2 and not d.left[0].active and d.right[1].value==0,"opposite-column blank drop moves to right first hole")
	mouse(Vector2(105,75),true,MOUSE_BUTTON_LEFT,true)
	check(d.count()==3 and d.right[2].value==1,"native doubleclick transfers second optional")
	mouse(Vector2(433,75),true);mouse(Vector2(21,73),false)
	check(d.count()==2 and d.right[1].status==0 and d.left[0].active and d.member(1,2).pid==2,"removal restores original left hole, later right slot2 preserved")
	var slots:Array=d.selected_slots();var roster:Array=[]
	for i in range(40):roster.append(c.state.person(i))
	var level:Dictionary=Builder.build(c.m4,c.m2,34,roster,false,-1,slots)
	var found:Array=level.units.filter(func(u):return int(u.slot)==2)
	check(found.size()==1 and [found[0].x,found[0].y]==c.state.m4_level(34).deploy[2] and int(found[0].direction)==int(c.state.m4_level(34).specials[2].direction),"real builder preserves right-slot2 Intro.special after removing slot1")
	mouse(Vector2(33,75),true,MOUSE_BUTTON_LEFT,true);check(d.right[1].status==1 and d.member(1,2).pid==2,"next add fills first right hole without shifting others")
	for i in range(2,16):d.transfer(0,i)
	check(d.count()==17 and d.pages==[0,1],"seventeenth right entry auto pages right only")
	mouse(Vector2(246,356),false);check(d.pages==[1,1],"left pagination on UP only, right independent")
	key(KEY_ESCAPE);mouse(Vector2.ZERO,true,MOUSE_BUTTON_RIGHT);check(c.mode=="deployment","K00 no right/key/back exit")
	c._show_deployment(34);d=c.deployment_screen;check(d.count()==1 and d.pages==[0,0],"genuine reentry resets pages/free selections")
	# Empty confirm is enabled but silently remains K00, not a disabled Button.
	d.right[0].status=0
	var launches:int=c.launched.size();mouse(Vector2(525,391),true);check(d.button_pressed,"native BUTTON1 DOWN")
	mouse(Vector2(525,391),false);check(c.launched.size()==launches and not d.done and not d.button_pressed,"empty confirm no battle/no dialog")
	d.transfer(0,0);mouse(Vector2(525,391),true);mouse(Vector2(1,1),false);check(c.launched.size()==launches,"confirm release outside ignored")
	mouse(Vector2(525,391),false);check(c.launched.size()==launches,"confirm UP alone ignored")
	mouse(Vector2(525,391),true);mouse(Vector2(525,391),false)
	check(c.launched.size()==launches+1 and c.launched[-1].slots.size()==32,"native DOWN-UP emits actual32 deployment slots")
	# Actual world MENU -> picker -> confirmation, isolated JSON/native paths.
	c._show_world();c.state.money=123
	c._world_system(Vector2(618,50));check(c.panel_root.frame.position==Vector2(551,50),"world MENU clamps x551")
	move(Vector2(1,154));mouse(Vector2.ZERO,true);await settle()
	check(c.panel_root is SavePicker and not c.panel_root.load_mode,"world save chooses slot before confirmation")
	move(Vector2(1,159));mouse(Vector2.ZERO,true);await settle()
	check(c.panel_root is Confirm and c.panel_root.origin==Vector2(300,200),"save even empty slot always original confirmation")
	mouse(Vector2.ZERO,true,MOUSE_BUTTON_RIGHT);await settle()
	check(c.panel_root==null and c.state.slot_info(0).is_empty() and c.mode=="world","save confirmation cancel no write/no picker reopen")
	c._world_save_picker(false);move(Vector2(1,159));mouse(Vector2.ZERO,true);await settle();mouse(Vector2.ZERO,true);await settle()
	check(c.state.slot_info(0).get("money",0)==123 and c.panel_root==null,"world save YES writes actual isolated slot and returns world")
	c.state.money=987;c._world_save_picker(true);move(Vector2(1,195));mouse(Vector2.ZERO,true);await settle()
	check(c.panel_root==null and c.state.money==987,"world empty load cancels directly, no confirm")
	c._world_save_picker(true);move(Vector2(1,159));mouse(Vector2.ZERO,true);await settle()
	check(c.panel_root is Confirm,"nonempty load prompts after chosen slot")
	mouse(Vector2.ZERO,true);await settle()
	check(c.mode=="world" and c.state.money==123 and c.panel_root==null,"world load YES restores actual state to world, not PLACE")
	c._world_system_chosen(0);var exits:Array=[];c.exit_requested.connect(func():exits.append(true))
	mouse(Vector2.ZERO,true);await settle();check(exits.size()==1,"world exit YES returns title signal, never quits process")
	# Isolated native score gate. Synthetic fixture, not a real campaign completion.
	c.highscore_path="res://../out/test_strategic_hiscore.dat";DirAccess.remove_absolute(ProjectSettings.globalize_path(c.highscore_path))
	c._show_ending();check(not FileAccess.file_exists(c.highscore_path),"ending preview never records score")
	c.state.main_score_snapshot=0;c.state.player_name="阿勇";c._after_victory(35)
	check(Scores.read_table(c.highscore_path)[9]=={"name":"阿勇","score":0} and c.ending_count==2,"L35 victory writes even below2800 then ending")
	var before:=FileAccess.get_file_as_bytes(c.highscore_path);c._after_victory(0)
	check(FileAccess.get_file_as_bytes(c.highscore_path)==before,"ordinary victory never records scores")
	c._after_victory(44)
	check(FileAccess.get_file_as_bytes(c.highscore_path)==before,"hidden/easter completion never writes score again")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(c.highscore_path))
	for slot in range(5):
		c.state.delete_slot(slot);DirAccess.remove_absolute(ProjectSettings.globalize_path(preload("res://scripts/ui/OriginalSaveSlots.gd").native_path(c.state,slot)))
	c.queue_free();await process_frame;root.get_node("Music").release_playback();OriginalUI.release_native_sfx();await create_timer(0.3).timeout
	print("ORIGINAL_STRATEGIC checks=",checks," failures=",failures)
	if failures==0:print("ORIGINAL_STRATEGIC PASS")
	quit(1 if failures else 0)
