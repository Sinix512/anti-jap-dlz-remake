extends SceneTree
const Codec=preload("res://scripts/battle/StateCodec.gd")
var failures:=0
var checks:=0
var camp
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error("RESUME_FAIL "+message)
func _initialize() -> void:call_deferred("run")
func settle() -> void:
	for i in range(200):
		if is_instance_valid(camp.story_player):camp.story_player._finish()
		if is_instance_valid(camp.cutscene):camp.cutscene._finish()
		await process_frame
		if camp.battle_story_queue.is_empty() and not is_instance_valid(camp.story_player) and not is_instance_valid(camp.cutscene):break
func run() -> void:
	var roundtrip: Dictionary=Codec.unpack(JSON.parse_string(JSON.stringify(Codec.pack({3:Vector2i(7,8),"a":[Vector2(4,9)]}))))
	check(roundtrip.has(3) and roundtrip[3]==Vector2i(7,8),"JSON typed keys and vectors")
	camp=load("res://scripts/m4/Campaign.gd").new();root.add_child(camp);camp.setup(load("res://assets/font/hzk16.fnt"));camp.qa_mode=true
	camp.state.data=camp.state.data.duplicate(true)
	camp.state.data.meta.save_prefix="dlz_qa_resume_"
	camp.state.next_battle_overrides={"hp":{"1":1},"behavior":{"1":13}}
	camp._launch_level(1,false,[-100]);await settle()
	var b=camp.battle
	var captive=b.unit_by_slot(1)
	check(captive!=null and captive.hp==1,"captive baseline HP1")
	b.turn=7
	var hero=b.unit_by_slot(0)
	hero.hp=13;hero.acted=true;hero.moved=true;hero.data.xp=52
	var enemy=b.unit_by_slot(40)
	if enemy!=null:enemy.acted=true;enemy.defense_integrity=35;enemy.skill_counts.buji=19
	b.chests[0].opened=true
	b.scenario.trigger_flags["0x583f54"]=1
	b.scenario.trigger_done["qa_once"]=true
	b.scenario.reached[2]=true
	b.mines.append({"tile":Vector2i(4,4),"mine":b.data.mines[0],"mine_id":0,"code":20,"low":3,"owner_side":"player","apply_fw":0})
	b.stats.kills_by_gun=9
	b._clear_selection()
	check(b.can_save(),"idle permits save")
	b.mode="skill";check(not b.can_save(),"target selection rejects save");b.mode="idle"
	camp.pending_save_snapshot=b.snapshot()
	camp._save_slot(91)
	check(camp.panel_root.is_visible_in_tree(),"battle save modal actually visible")
	check(camp.state.slot_info(91).battle_resume.snapshot.turn==7,"battle slot has snapshot")
	camp._close_panel()
	check(camp.load_campaign_slot(91),"battle slot loads")
	await process_frame
	b=camp.battle;hero=b.unit_by_slot(0)
	check(b.turn==7 and hero.hp==13,"resume keeps round and HP")
	check(hero.acted and hero.moved and int(hero.data.xp)==52,"resume keeps action and XP")
	check(b.mines.size()==1 and int(b.mines[0].low)==3 and b.mines[0].tile==Vector2i(4,4),"resume timer not advanced")
	check(b.chests[0].opened and b.scenario.trigger_done.has("qa_once") and b.scenario.reached.has(2),"resume chest and once flags")
	check(b.selected==null and b.mode=="idle" and not b.busy,"resume clean UI mode")
	check(int(b.stats.kills_by_gun)==9 and camp.battle_story_queue.is_empty(),"resume no opening replay")
	check(b.unit_by_slot(1).hp==1,"resume captive HP1")
	camp.state.money=1234
	camp.state.script_globals["0x7d06d4"]=47
	camp.state.difficulty=0
	hero.data.level=3;hero.data.xp=66;hero.attack_count=47
	camp._restart_current_battle();await settle()
	b=camp.battle;hero=b.unit_by_slot(0)
	check(b.turn==1 and b.mines.is_empty(),"retry clears turn and mines")
	check(b.unit_by_slot(1).hp==1,"retry does not heal captive")
	check(camp.state.money==1234 and int(camp.state.script_globals["0x7d06d4"])==47,"retry preserves warehouse and global relations")
	check(int(hero.data.level)==3 and int(hero.data.xp)==66 and hero.attack_count==47,"easy retry retains practice")
	check(b.stats.kills_by_gun==0,"retry resets current kills")
	check(not Codec.unpack(camp.battle_baseline).scenario.started,"baseline stays before opening")
	# Independent normal-difficulty retry fixture: only already-learned skill
	# practice carries, never the easy-mode level/XP/ordinary attack practice.
	var base:Dictionary=Codec.unpack(camp.battle_baseline)
	var base_hero:Dictionary={}
	for record in base.level.units:
		if int(record.slot)==0:base_hero=record
	camp.state.difficulty=1
	hero.data.level=8;hero.data.xp=71;hero.attack_count=90
	hero.skill_counts.buji=41;hero.skill_counts.kongxi=55
	camp._restart_current_battle();await settle()
	b=camp.battle;hero=b.unit_by_slot(0)
	check(int(hero.data.level)==int(base_hero.level) and int(hero.data.xp)==int(base_hero.xp),"normal retry restores baseline level and XP")
	check(hero.attack_count==int(base_hero.attack_count),"normal retry restores baseline ordinary practice")
	check(int(hero.skill_counts.buji)==41 and int(hero.skill_counts.kongxi)==0,"normal retry carries learned skill practice only")
	check(b.turn==1 and b.unit_by_slot(1).hp==1 and not b.busy,"normal retry runs opening and restores legal playable phase")
	camp.state.delete_slot(91)
	camp.state.new_game(camp.m2)
	check(camp.state.checkpoint_data.is_empty() and camp.state.battle_resume.is_empty(),"new game discards stale checkpoint/resume")
	camp.queue_free();camp=null;await process_frame;await process_frame
	print("RESUME_RETRY checks=",checks," failures=",failures)
	quit(1 if failures else 0)
