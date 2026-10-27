extends SceneTree
# Source-backed, synthetic T510 predicate/action contracts. Not campaign proof.
# Evidence: research_t510_predicate_{00_16,17_32,33_46}_20261025.*
class TraceBattle extends "res://scripts/Battle.gd":
	var clear_trace:Array=[]
	func remove_slot(slot:int) -> void:
		super.remove_slot(slot)
		clear_trace.append({"slot":slot,"loot":battle_context.get("temporary_loot",{}).duplicate(),"guns":int(stats.get("kills_by_gun",0))})
var checks:=0
var failures:=0
var m4:Dictionary
var b
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("PREDICATE_FAIL "+label)
func fixture(idx:int):
	if b!=null:b.free()
	b=TraceBattle.new();root.add_child(b);b.fast_sim=true
	b.setup(m4.duplicate(true),m4.levels[idx].duplicate(true),load("res://assets/font/hzk16.fnt"),{"campaign_story":true})
	b.animations_enabled=false;b.sfx_enabled=false;b.set_process(false)
	for u in b.units:u.free()
	b.units.clear();b.player_units.clear();b.enemy_units.clear();b.mines.clear()
	b.terrain.fill(0);b.scenario.trigger_flags.clear();b.trigger_messages.clear()
	b.scenario.started=true;b.scenario.start_phase_pending=false;b.busy=false
	b.stats={"losses":0,"kills":0,"kills_by_mine":0,"kills_by_gun":0,"loot_count":0}
	b.clear_trace.clear()
	var hero=unit(0,0,Vector2i(1,1));b.scenario.protagonist=hero
	return hero
func unit(slot:int,faction:int,tile:Vector2i):
	var d:Dictionary=m4.levels[0].units[0].duplicate(true)
	d.merge({"slot":slot,"pid":slot,"name":"fixture%d"%slot,"side":"player" if faction==0 else "enemy","faction":faction,"x":tile.x,"y":tile.y,"hp":100,"max_hp":100,"level":5,"xp":0,"morale":100,"control":true,"item_slots":[0,0,0,0,0,0,0,0],"mine_slots":[0,0,0,0,0,0,0,0]},true)
	return b._spawn_unit(d)
func messages() -> Array:
	return b.trigger_messages.map(func(m):return str(m.addr))
func run() -> void:
	m4=JSON.parse_string(FileAccess.get_file_as_string("res://data/m4.json"))
	fixture(1);unit(1,0,Vector2i(2,1))
	for slot in range(40,48):unit(slot,1,Vector2i(slot-35,5))
	await b.scenario.on_tick()
	check(b.unit_by_slot(46).behavior==6,"L01 join includes original slot46")
	check(b.unit_by_slot(41).behavior==6 and b.unit_by_slot(45).behavior==6,"L01 join preserves41..45")
	check(b.unit_by_slot(40).behavior!=6 and b.unit_by_slot(47).behavior!=6,"L01 range excludes40/47")
	check(b.scenario._global_value("0x583f18")==1 and not b.finished_flag,"L01 join not premature victory")
	fixture(1);unit(1,0,Vector2i(10,10));b.scenario._set_global("0x583f18",2)
	await b.scenario.on_tick()
	check(b.last_result=="victory","L01 original win uses flag nonzero, not ==1")
	for tile in [Vector2i(6,5),Vector2i(6,11),Vector2i(5,8),Vector2i(9,12),Vector2i(10,12),Vector2i(9,13)]:
		fixture(7);unit(7,0,tile)
		for slot in range(40,48):unit(slot,1,Vector2i(slot-35,20))
		var inside:bool=tile.x>=5 and tile.x<10 and tile.y>=8 and tile.y<13
		await b.scenario.on_tick()
		check((b.scenario._global_value("0x583f18")==1)==inside,"L07 native rectangle %s"%tile)
		check((b.unit_by_slot(46).behavior==6 and b.unit_by_slot(46).target_slot==7)==inside,"L07 behavior/target follow native rectangle %s"%tile)
	check(b.unit_by_slot(47).behavior!=6,"L07 ambush excludes47")
	fixture(8);unit(40,1,Vector2i(10,10));await b.scenario.on_tick()
	check(b.last_result=="defeat" and messages()==["0x472984"],"L08 escort loss message precedes defeat")
	var hero=fixture(16);unit(19,1,Vector2i(2,1));unit(80,1,Vector2i(18,18))
	var enemy=unit(40,1,Vector2i(10,10));enemy.item_slots=[103,103,113,0,0,0,0,0]
	var ally=unit(41,0,Vector2i(11,10));ally.item_slots=[114,0,0,0,0,0,0,0]
	var third=unit(42,2,Vector2i(12,10));third.item_slots=[114,0,0,0,0,0,0,0]
	var inactive=unit(43,1,Vector2i(13,10));inactive.item_slots=[113,0,0,0,0,0,0,0];b.remove_slot(43)
	b.clear_trace.clear()
	var xp:int=hero.data.xp;var lv:int=hero.data.level
	await b.scenario.on_tick()
	check(not enemy.alive and not ally.alive and not third.alive,"L16 clears all active40..60 regardless side")
	check(b.battle_context.temporary_loot=={"102":2,"112":1,"113":1},"L16 current live People slots, repeated items, third faction; no friendly/inactive loot")
	check(enemy.item_slots==[103,103,113,0,0,0,0,0] and ally.item_slots[0]==114,"L16 helper does not erase People inventory")
	check(b.stats.kills==3 and b.stats.kills_by_gun==3 and b.stats.kills_by_mine==0,"L16 gun count for every active clear, even side0")
	check(b.stats.losses==0 and b.stats.loot_count==0 and hero.data.xp==xp and hero.data.level==lv,"L16 no ordinary death XP/penalty/loss/extra loot event")
	check(b.clear_trace.map(func(t):return t.slot)==[40,41,42],"L16 ascending, active-only range")
	check(b.clear_trace[0].guns==0 and b.clear_trace[0].loot.is_empty() and b.clear_trace[1].guns==1 and b.clear_trace[1].loot=={"102":2,"112":1} and b.clear_trace[2].guns==2,"L16 per-slot remove then loot then counter order")
	check(b.unit_by_slot(33)!=null and b.unit_by_slot(35)!=null and not b.finished_flag,"L16 keeps original reinforcements and ongoing result")
	await b.scenario.on_tick()
	check(b.stats.kills==3 and b.battle_context.temporary_loot=={"102":2,"112":1,"113":1},"L16 railway flag prevents repeated collection")
	fixture(16);enemy=unit(40,1,Vector2i(10,10));enemy.item_slots=[103,0,0,0,0,0,0,0]
	b.battle_context.temporary_loot={"102":65535};b.stats.kills=0xffffffff;b.stats.kills_by_gun=0xffffffff
	b.scripted_clear_slot(40)
	check(b.battle_context.temporary_loot["102"]==0 and b.stats.kills==0 and b.stats.kills_by_gun==0,"L16 original u16 loot and u32 gun wrap")
	b.scripted_clear_slot(40)
	check(b.stats.kills==0 and b.battle_context.temporary_loot["102"]==0,"L16 inactive slot cannot collect twice")
	for remaining in [false,true]:
		fixture(21)
		if remaining:unit(41,1,Vector2i(10,10))
		await b.scenario.on_tick()
		check(b.last_result=="victory" and messages()==(["0x4727D4","0x472ADC","0x472AE0"] if remaining else ["0x4727D4","0x472AE0"]),"L21 remaining-enemy conditional text %s"%remaining)
	for idx in [19,26]:
		hero=fixture(idx);unit(40,1,Vector2i(10,10));b.remove_slot(0)
		await b.scenario.on_tick()
		check(b.last_result=="defeat" and b.last_result_trigger.id=="any_player_death","L%d absent side0 fails on tick without death edge"%idx)
		fixture(idx);unit(40,1,Vector2i(10,10));unit(43,1,Vector2i(11,10));unit(58,0,Vector2i(12,10))
		b.scenario._last_dead_side="player";await b.scenario.on_tick()
		check(not b.finished_flag,"L%d last-dead is irrelevant while any side0 survives"%idx)
	for active in [false,true]:
		fixture(24);unit(40,1,Vector2i(10,10))
		var u26=unit(26,1,Vector2i(15,15))
		if not active:b.remove_slot(26)
		await b.scenario.on_tick()
		check(b.scenario.trigger_flags.has("cell_26")==active,"L24 cell marker requires active26 %s"%active)
		check(int(u26.data.faction)==0 and b.scenario._global_value("0x7d1cfc")==0,"L24 People.side writes are not guarded by stage26 %s"%active)
	for tile in [Vector2i(9,0),Vector2i(1,8),Vector2i(8,0),Vector2i(10,0),Vector2i(11,0)]:
		fixture(28);enemy=unit(40,1,tile);enemy.target_x=9
		await b.scenario.on_tick()
		check((enemy.target_x==0)==(tile.y==0 and tile.x>=8 and tile.x<11),"L28 native top-edge turn rectangle %s"%tile)
	fixture(28);var post_result:Array=[]
	b.story_event.connect(func(kind,payload):
		if kind=="trigger_message" and payload.addr=="0x4728D4":post_result.append([b.scenario.native_result,b.finished_flag]))
	await b.scenario.on_tick()
	check(post_result==[[1,false]],"L28 win written before post-win dialogue but not prematurely published")
	check(b.last_result=="victory" and b.scenario._global_value("0x7d1e88")==1 and messages()==["0x4728E4","0x4728D4"],"L28 post-win side write/action chain retained")
	fixture(36);b.remove_slot(0);await b.scenario.on_tick()
	check(b.last_result=="defeat" and messages().back()=="0x472C5C","L36 all-player failure includes native message")
	fixture(36);unit(58,0,Vector2i(10,10));b.remove_slot(0);await b.scenario.on_tick()
	check(not b.finished_flag,"L36 scans all128 side0, not just the named five")
	fixture(37);unit(40,0,Vector2i(10,10));unit(41,0,Vector2i(11,10));unit(58,1,Vector2i(12,10))
	check(b.scenario._unit_count({"from":40,"to":128,"faction":{"neq":0}})==1 and b.scenario._unit_count({"from":40,"to":128})==3,"L37 optional faction count does not change generic counting")
	await b.scenario.on_tick()
	check(b.scenario._global_value("0x583f34")==1 and b.unit_by_slot(95)!=null and b.unit_by_slot(104)!=null,"L37 allied40+ do not suppress reinforcement")
	check(b.unit_by_slot(44)!=null and b.unit_by_slot(48)!=null and b.unit_by_slot(49)!=null,"L37 secondary reinforcements preserved")
	check(range(95,105).all(func(s):return b.unit_by_slot(s).morale==80),"L37 unknown08 source store changes actual morale to80")
	fixture(37);unit(40,0,Vector2i(10,10));unit(58,1,Vector2i(12,10));unit(59,2,Vector2i(13,10))
	await b.scenario.on_tick()
	check(b.scenario._global_value("0x583f34")==0 and b.unit_by_slot(95)==null,"L37 faction2 counts as a second enemy")
	fixture(38);unit(40,1,Vector2i(11,10));unit(44,1,Vector2i(10,10));b.scenario._set_global("0x583f4c",99)
	await b.scenario.on_tick()
	check(messages().has("0x472D4C") and (b.scenario._global_value("0x583f1c")&0x2000)!=0,"L38 cue72 immediate before turn99")
	check(not messages().has("0x472D3C") and not messages().has("0x472D40") and not messages().has("0x472D48"),"L38 other delayed cues keep turn gate")
	b.scenario._set_global("0x583f4c",0xffffffff);b.turn=4
	check(b.scenario._cond({"turn_gt_flag":{"addr":"0x583f4c","add":4}}),"L38 flag+add unsigned wrap, synthetic edge only")
	fixture(17)
	var final_rule:Dictionary=b.scenario.trigger_rules.filter(func(r):return r.id=="all_five_win")[0]
	for i in range(5):b.scenario._set_global("0x%x"%(0x583f18+i*4),1)
	check(b.scenario._cond(final_rule.when),"L17 five normal flags sum5")
	b.scenario._set_global("0x583f18",2)
	check(not b.scenario._cond(final_rule.when),"L17 five nonzero flags are not sufficient when sum6 (synthetic)")
	b.scenario._set_global("0x583f1c",0xffffffff)
	check(b.scenario._cond(final_rule.when)==false,"L17 raw flag sum wraps u32 (synthetic)")
	b.queue_free();await process_frame;await create_timer(0.15).timeout
	print("ORIGINAL_TRIGGER_PREDICATE checks=",checks," failures=",failures)
	quit(1 if failures else 0)
