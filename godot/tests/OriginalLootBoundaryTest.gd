extends "res://tests/OriginalActionOrderTest.gd"
# Synthetic original-byte boundary vectors, not campaign progression evidence.
const State=preload("res://scripts/m2/GameState.gd")
const Page=preload("res://scripts/ui/OriginalStoryPage.gd")
const Report=preload("res://scripts/ui/OriginalVictoryReport.gd")

func run() -> void:
	m2=Codec.integers(JSON.parse_string(FileAccess.get_file_as_string("res://data/m2.json")))
	m4=Codec.integers(JSON.parse_string(FileAccess.get_file_as_string("res://data/m4.json")))
	var gs=State.new();gs.new_game(m2);gs.setup_m4(m4)
	for entry in [{"kind":"item","bits":16},{"kind":"mine","bits":16},{"kind":"material","bits":32}]:
		var add:String="add_"+entry.kind
		var count:String=entry.kind+"_count"
		var mask:int=(1<<int(entry.bits))-1
		gs.call(add,0,mask)
		check(gs.call(count,0)==mask,str(entry.kind)+" native all-ones value")
		gs.call(add,0,1)
		check(gs.call(count,0)==0,str(entry.kind)+" addition wraps, never saturates")
		gs.call(add,0,-1)
		check(gs.call(count,0)==mask,str(entry.kind)+" raw subtraction truncates to storage width")
		gs.call(add,0,1)
	gs.items={"81":65535};gs.money=10000
	var before:int=gs.money
	check(gs.buy_item(81).ok and gs.item_count(81)==0 and gs.money==before-int(gs.item(81).price),"purchase charges normally at65535 and wraps item stock")
	var member:Dictionary=gs.protagonist_member();member.item_slots=[82,0,0,0,0,0,0,0];gs.items={"81":65535}
	check(gs.return_item(member,0).ok and gs.item_count(81)==0 and not member.item_slots.has(82),"return wraps full warehouse and still removes source")
	member.mine_slots=[1,0,0,0,0,0,0,0];gs.mines={"0":65535}
	check(gs.return_mine(member,0).ok and gs.mine_count(0)==0 and not member.mine_slots.has(1),"mine return also wraps without retaining source")
	gs.materials={"0":4294967295};before=gs.money
	check(gs.buy_material(0).ok and gs.material_count(0)==0 and gs.money==before-int(gs.material(0).price),"material purchase is DWORD wrap, not WORD wrap")
	gs.materials.clear()
	for mid in range(gs.mine(0).recipe.size()):gs.add_material(mid,int(gs.mine(0).recipe[mid]))
	gs.script_globals["0x95eaf8"]=1;gs.script_globals["0x95eb08"]=1;gs.mines={"0":65535}
	check(gs.craft_mine(0).ok and gs.mine_count(0)==0,"forge checks finite recipe but not warehouse residual capacity")
	#42AFD2 itself only checks faction: it neither retires nor clears source.
	for side in [0,1,2]:
		fixture();var victim=unit(40,side,Vector2i(5,5),50)
		victim.item_slots=[82,0,82,0,132,2,0,156];victim.mine_slots=[1,0,0,0,0,0,0,0]
		b.battle_context["temporary_loot"]={"81":65535}
		var source:Array=victim.item_slots.duplicate();var old_count:int=int(b.stats.get("loot_count",0))
		b._collect_native_casualty_loot(victim)
		var loot:Dictionary=b.battle_context.temporary_loot
		check(loot.get("81",0)==(65535 if side==0 else 1),"collector faction gate and repeated item WORD wrap side%d"%side)
		check(victim.item_slots==source and victim.alive and int(b.stats.get("loot_count",0))==old_count,"collector leaves source/lifecycle/loot_count untouched side%d"%side)
		check(not loot.has("0") and int(loot.get("131",0))==(0 if side==0 else 1),"collector ignores mine slots, keeps high item ID side%d"%side)
	# Resolver caller coverage: ordinary HP and morale deaths collect; mines do not.
	for kind in ["attack","skill","item","morale","mine"]:
		fixture();var h=unit(0,0,Vector2i(5,7),500)
		var victim=unit(40,1,Vector2i(5,5),1)
		victim.item_slots=[82,0,0,0,0,0,0,0]
		if kind=="attack":await b._perform_attack(h,victim)
		elif kind in ["skill","morale"]:
			var sid:=15 if kind=="skill" else 6
			if kind=="morale":victim.hp=500;victim.max_hp=500;victim.morale=1;h.set_tile(5,6)
			h.skill_counts.kongxi=45;h.skill_counts.weishe=45;victim.data.zhili=1
			b.selected=h;b.active_skill_id=sid;b.active_skill=b.data.skills[sid];await b._execute_skill_at(Vector2i(5,5))
		elif kind=="item":
			h.item_slots[0]=45;b.selected=h;b.active_item_id=44;await b._execute_item_at(Vector2i(5,5))
		else:
			b.mines.append({"tile":Vector2i(5,5),"mine":b.data.mines[0],"mine_id":0,"code":0,"low":1});await b._detonate_mines(Vector2i(5,5))
		check(not victim.alive,kind+" test actually retires target")
		check(int(b.battle_context.get("temporary_loot",{}).get("81",0))==(0 if kind=="mine" else 1),kind+" has original distinct loot caller")
	fixture();var victim=unit(40,1,Vector2i(5,5),500);victim.item_slots=[82,0,0,0,0,0,0,0]
	b.scripted_clear_slot(40);b.scripted_clear_slot(40)
	check(int(b.battle_context.temporary_loot["81"])==1 and victim.item_slots[0]==82,"scripted clear collects active slot exactly once, not a death callback")
	b.battle_context.temporary_loot={"81":65535};b._battle_loot(81,false)
	check(int(b.battle_context.temporary_loot["81"])==0,"full-pack steal temporary stock wraps too")
	# Real result UI boundary: a victory preview must not commit early.
	var camp=preload("res://tests/helpers/LegalProbeCampaign.gd").new();root.add_child(camp);camp.setup(load("res://assets/font/hzk16.fnt"));camp.qa_mode=true
	camp._launch_level(0,false,[-100]);await camp.drain_story();camp.battle.set_process(false)
	camp.state.items={"81":65535};camp.battle.battle_context.temporary_loot={"81":2,"1":3}
	camp._settle_battle("victory","fixture")
	check(camp.state.item_count(81)==65535 and int(camp.battle.battle_context.temporary_loot["81"])==2,"victory notice leaves temporary and permanent stock separate")
	var notice=camp.result_canvas.get_child(0);notice.set_process(false)
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=false;event.position=Vector2(600,440);root.push_input(event,true)
	notice._advance(.006);await process_frame;await process_frame
	event=event.duplicate();event.button_index=MOUSE_BUTTON_RIGHT;root.push_input(event,true);notice._advance(.201);await process_frame
	var report=camp.result_canvas.get_child(-1)
	check(report is Report and report.values[4]==5 and camp.state.item_count(81)==65535,"MENU10 counts temporary loot without early deposit")
	# Advance only synthetic counter time here; integration test uses wall time.
	report.set_process(false);report._advance(100);await process_frame;await process_frame
	root.push_input(event.duplicate(),true);await process_frame
	check(camp.state.item_count(81)==1 and camp.state.item_count(1)==3 and bool(camp._last_report.loot_committed),"fresh report release commits warehouse WORD addition")
	camp._commit_victory_loot()
	check(camp.state.item_count(81)==1 and camp.state.item_count(1)==3,"completed report cannot deposit twice")
	camp.queue_free();await process_frame;await process_frame
	fixture();b.battle_context.temporary_loot={"81":2}
	camp=load("res://scripts/m4/Campaign.gd").new();root.add_child(camp);camp.battle=b;camp.state=gs;camp._last_report={"victory":false}
	var old:int=gs.item_count(81);camp._commit_victory_loot()
	check(gs.item_count(81)==old and b.battle_context.temporary_loot["81"]==2,"defeat never deposits temporary stock")
	camp.battle=null;camp.queue_free();b.queue_free();b=null;await process_frame;await process_frame
	root.get_node("Music").release_playback();OriginalUI.release_native_sfx();await create_timer(.2).timeout
	print("ORIGINAL_LOOT_BOUNDARY checks=",checks," failures=",failures)
	quit(1 if failures else 0)
