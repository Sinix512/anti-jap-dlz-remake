extends SceneTree
# Static source contract: 40497D T750 -> 42A395 -> 41F2E2 -> T510.
# These synthetic rule fixtures are NOT campaign play/completion evidence.
var checks:=0
var failures:=0
var m4:Dictionary
var b
var signals:Array=[]
var mine_states:Array=[]
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("ROUND_TAIL_FAIL "+label)
func fixture(idx:int) -> void:
	if b!=null:b.free()
	b=load("res://scripts/Battle.gd").new();root.add_child(b)
	b.setup(m4.duplicate(true),m4.levels[idx].duplicate(true),load("res://assets/font/hzk16.fnt"),{"campaign_story":true})
	b.fast_sim=true;b.animations_enabled=false;b.sfx_enabled=false;b.set_process(false)
	for u in b.units:u.free()
	b.units.clear();b.player_units.clear();b.enemy_units.clear();b.mines.clear()
	for row in b.data.terrain_modifiers:row[3]=0;row[4]=0
	for i in range(b.terrain.size()):b.terrain[i]=0
	b.scenario.trigger_flags.clear();b.trigger_messages.clear()
	b.scenario.start_phase_pending=false;b.busy=false
	b.stats={"losses":0,"kills":0,"kills_by_mine":0,"kills_by_gun":0,"loot_count":0,"loot_items":[35]}
	signals.clear();mine_states.clear()
	b.finished.connect(func(result,message):
		var hero=b.unit_by_slot(0)
		signals.append({"result":result,"message":message,"hp":hero.hp if hero!=null else 0,"xp":int(hero.data.xp) if hero!=null else -1,"mines":b.mines.size(),"kills":int(b.stats.kills)}))
	b.presentation_step.connect(func(kind,_payload):
		if kind=="numbers_start":mine_states.append({"native":b.scenario.native_result,"finished":b.finished_flag,"signals":signals.size(),"busy":b.busy,"can_save":b.can_save()}))
func unit(slot:int,side:int,tile:Vector2i,hp:=100,lv:=1):
	var d:Dictionary=m4.levels[0].units[0].duplicate(true)
	d.merge({"slot":slot,"pid":slot,"name":"fixture%d"%slot,"side":"player" if side==0 else "enemy","faction":side,"x":tile.x,"y":tile.y,"hp":hp,"max_hp":hp,"morale":60,"level":lv,"xp":0,"item_slots":[0,0,0,0,0,0,0,0],"mine_slots":[0,0,0,0,0,0,0,0],"control":true,"bingzhong":1},true)
	return b._spawn_unit(d)
func mine(tile:Vector2i,low:int) -> void:
	b.mines.append({"tile":tile,"mine":b.data.mines[0],"mine_id":0,"code":20,"low":low,"owner_side":"player"})
func base(idx:int):
	fixture(idx)
	var hero=unit(0,0,Vector2i(1,1))
	unit(7,0,Vector2i(2,1))
	unit(40,1,Vector2i(5,5),1,idx)
	b.scenario.protagonist=hero
	return hero
func run() -> void:
	m4=JSON.parse_string(FileAccess.get_file_as_string("res://data/m4.json"))
	var mapped:=0;var guarded:=0
	for lv in m4.levels:
		for r in lv.triggers.rules:
			if r.has("source_order"):
				mapped+=1
				if r.requires_result_zero:guarded+=1
	check(mapped==261 and guarded==109,"all47 T510 rule gate/return metadata and two omitted fragments generated")
	var hero=base(6)
	hero.hp=10;hero.item_slots=[33,0,0,0,0,0,0,0]
	b.terrain[b.map_w+1]=9;b.data.terrain_modifiers[9][3]=20;b.data.terrain_modifiers[9][4]=10
	mine(Vector2i(10,10),3)
	await b.scenario.on_turn_start(20)
	check(hero.hp==45 and hero.morale==70,"normal round terrain then book recovery")
	check(b.mines[0].low==2 and not b.finished_flag and signals.is_empty(),"normal round countdown no finish")
	await b.scenario.on_turn_start(20)
	check(hero.hp==45 and hero.morale==70 and b.mines[0].low==2,"repeated hook cannot recover or count down twice")
	hero=base(6);hero.hp=10;hero.item_slots=[33,0,0,0,0,0,0,0]
	b.terrain[b.map_w+1]=9;b.data.terrain_modifiers[9][3]=20;b.data.terrain_modifiers[9][4]=10
	mine(Vector2i(10,10),3)
	await b.scenario.on_turn_start(21)
	check(b.last_result=="defeat" and signals.size()==1 and signals[0].hp==45,"timeout finish observes recovered HP exactly once")
	check(hero.morale==70 and hero.item_slots[0]==33 and b.mines[0].low==2,"timeout keeps book and processes countdown")
	check(b.last_result_trigger.id=="t750_timeout" and b.trigger_messages.is_empty(),"L06 timeout suppresses guarded T510 dialogue")
	await b.scenario.on_turn_start(22)
	check(signals.size()==1 and hero.hp==45 and b.mines[0].low==2,"already finished round cannot maintain again")
	for idx in [5,6]:
		hero=base(idx);hero.data.xp=95
		# idx-level enemy, two live allies: raw12/count2 +8 is capped to12.
		var carried:Array=hero.mine_slots.duplicate();var items:Array=hero.item_slots.duplicate()
		b.unit_by_slot(40).item_slots=[45,0,0,0,0,0,0,0]
		mine(Vector2i(5,5),2);mine(Vector2i(10,10),3)
		await b.scenario.on_turn_start(31 if idx==5 else 21)
		check(b.last_result==("victory" if idx==5 else "defeat") and signals.size()==1,"L%d source-specific timeout overwrite"%idx)
		check(not b.unit_by_slot(40) and b.mines.size()==1 and b.mines[0].low==2,"L%d complete mine death and later countdown before finish"%idx)
		check(int(hero.data.level)==2 and int(hero.data.xp)==7 and signals[0].xp==7,"L%d timed-mine XP upgrade before finish"%idx)
		check(b.stats.kills==1 and b.stats.kills_by_mine==1 and signals[0].kills==1,"L%d timed-mine kill before finish"%idx)
		check(hero.item_slots==items and hero.mine_slots==carried and b.stats.loot_count==0 and b.stats.loot_items==[35],"L%d no mine equipment loot or second inventory debit"%idx)
		check(mine_states.size()==1 and mine_states[0].native==-1 and not mine_states[0].finished and mine_states[0].signals==0 and mine_states[0].busy and not mine_states[0].can_save,"L%d timeout remains pending and input/save locked throughout mine resolution"%idx)
		check(b.scenario.result_writes.size()==(2 if idx==5 else 1) and b.last_result_trigger.id==("win" if idx==5 else "t750_timeout"),"L%d final result provenance"%idx)
		if idx==6:check(b.trigger_messages.is_empty(),"L06 no victory or hero-lost text after timeout")
	# Native L05 permits the unguarded win even if the same timer killed hero.
	hero=base(5);hero.set_tile(5,4);hero.hp=1;mine(Vector2i(5,5),2)
	b.mines[0].mine=b.data.mines[1];b.mines[0].mine_id=1;b.mines[0].code=21
	await b.scenario.on_turn_start(31)
	check(not hero.alive and b.last_result=="victory" and signals.size()==1,"L05 simultaneous hero loss does not invent a new guard")
	hero=base(5);b.remove_slot(0);b.remove_slot(40)
	await b.scenario.on_tick()
	check(b.last_result=="defeat" and b.last_result_trigger.id=="hero_lost" and b.scenario.result_writes.size()==1,"normal L05 hero failure returns before unguarded win")
	hero=base(45);b.unit_by_slot(40).set_tile(0,0);unit(41,1,Vector2i(0,0))
	await b.scenario.on_tick()
	check(b.last_result=="defeat" and signals.size()==1 and b.last_result_trigger.id=="rival_reach" and b.scenario.result_writes.size()==2,"normal L45 win continues and rival failure overrides before one finish")
	hero=base(3);unit(4,0,Vector2i(2,1));b.remove_slot(40)
	await b.scenario.on_tick()
	check(b.last_result=="victory" and b.scenario._global_value("0x583f18")==1,"L03 meet cue still executes after win write")
	hero=base(17)
	await b.scenario.on_tick()
	check(b.level.success=="在物资中找到5箱机枪" and b.scenario.status_text==b.level.success,"L17 original success GBK digit starts5")
	for i in range(5):
		var tile:Array=[[25,6],[32,6],[39,6],[44,7],[43,5]][i]
		hero.set_tile(tile[0],tile[1]);await b.scenario.on_tick()
		check(b.level.success=="在物资中找到%d箱机枪"%(4-i),"L17 original success countdown %d"%(4-i))
	check(b.last_result=="victory" and b.scenario.status_text=="在物资中找到0箱机枪","L17 zero digit written before final finish")
	hero=base(18);unit(21,1,Vector2i(10,10));b.remove_slot(21)
	await b.scenario.on_tick()
	check(b.last_result=="victory" and not b.unit_by_slot(40) and b.last_result_trigger.id=="unrecruited_21_lost_win","L18 killing unrecruited21 clears40..76 and wins")
	check(b.trigger_messages.any(func(m):return int(m.record)==311) and b.trigger_messages.any(func(m):return int(m.record)==312),"L18 original retreat texts311/312")
	hero=base(18);unit(21,1,Vector2i(2,1))
	await b.scenario.on_tick()
	check(b.scenario._global_value("0x7d19e4")==0 and b.unit_by_slot(21).control,"L18 meeting21 changes actual People faction and control")
	b.remove_slot(21);await b.scenario.on_tick()
	check(not b.finished_flag and b.unit_by_slot(40)!=null,"L18 recruited21 loss does not invent unrecruited victory")
	hero=base(22);b.fast_sim=false
	await b.scenario.on_tick()
	check(not b.scenario.pending_choice.is_empty() and signals.is_empty(),"L22 async choice pauses before publishing result")
	await b.scenario.resolve_choice(2)
	check(b.last_result=="victory" and signals.size()==1 and b.last_result_trigger.id=="unit_24_lost" and b.scenario._global_value("0x583f18")==0,"L22 choice resumes original source then returns before25 cue")
	hero=base(6);b.scenario._finish("defeat","AI already decided")
	hero.hp=10;mine(Vector2i(10,10),3)
	await b.scenario.on_turn_start(21)
	check(hero.hp==10 and b.mines[0].low==3 and signals.size()==1,"AI-decided result skips the whole next-round block")
	b.queue_free();await process_frame
	print("ORIGINAL_ROUND_TAIL checks=",checks," failures=",failures)
	quit(1 if failures else 0)
