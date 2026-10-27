extends SceneTree
# Synthetic public-outcome fixtures, NOT campaign evidence.
const Forecast=preload("res://tests/helpers/PublicRoundForecast.gd")
const Outcomes=preload("res://tests/helpers/PublicOutcomeTree.gd")
const Unit=preload("res://scripts/BattleUnit.gd")
const Rules=preload("res://scripts/battle/CombatRules.gd")
class NumericBattle extends "res://scripts/Battle.gd":
	var fixture_rolls:Array=[]
	var roll_calls:=0
	func _rand100() -> int:
		roll_calls+=1
		return int(fixture_rolls.pop_front()) if not fixture_rolls.is_empty() else 99
	func _complete_unit_death(_u:Node2D) -> void:pass
	func _check_end() -> bool:return false
	func _log(_text:String) -> void:pass
	func _spawn_float(_text:String,_pos:Vector2,_color:Color=Color.WHITE) -> void:pass
	func _after_completed_action(_u) -> void:pass
var checks:=0
var failures:=0
var data:Dictionary
var boards:Array=[]
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("PUBLIC_OUTCOME_TREE_FAIL "+label)
func fixture():
	var b=NumericBattle.new();root.add_child(b);boards.append(b)
	b.data=data.duplicate(true);b.map_w=12;b.map_h=12;b.terrain.resize(144);b.terrain.fill(0)
	b.level={"index":0,"difficulty_setting":1};b.turn=1
	b.fast_sim=true;b.animations_enabled=false;b.sfx_enabled=false;b.set_process(false)
	b.stats={"losses":0,"kills":0,"xp":0};b.rng_state=987654
	for mods in b.data.terrain_modifiers:mods[3]=0;mods[4]=0
	return b
func unit(b,slot:int,faction:int,tile:Vector2i):
	var u=Unit.new();u.slot=slot;u.pid=slot;u.x=tile.x;u.y=tile.y
	u.side="player" if faction==0 else "enemy";u.data={"faction":faction,"level":4,"xp":0,"wuli":70,"zhili":10}
	u.hp=100;u.max_hp=100;u.morale=100;u.bingzhong=1;u.select=1;u.move=4;u.control=true;u.behavior=11
	u.item_slots=[0,0,0,0,0,0,0,0];u.mine_slots=[0,0,0,0,0,0,0,0]
	for key in b.SKILL_KEYS:u.skill_counts[key]=1
	b.add_child(u);b.units.append(u)
	if faction==0:b.player_units.append(u)
	else:b.enemy_units.append(u)
	return u
func shadow(b,known:Array=[]):
	var s=Forecast.clone_public_board(b,known);boards.append(s);return s
func action(sid:int,tile:Vector2i,extra:Dictionary={}) -> Dictionary:
	var a:Dictionary={"kind":"skill","skill":sid,"tile":tile};a.merge(extra);return a
func two_cell_mask(b,sid:int) -> void:
	var matrix:Array=[]
	for row in range(7):matrix.append([0,0,0,0,0,0,0])
	matrix[3][3]=100;matrix[3][4]=100
	b.data.apply_ranges[str(Rules.skill_apply(int(b.data.skills[sid].apply_fw),1))]=matrix
func numbers(u,v,label:String) -> void:
	for field in ["hp","max_hp","morale","alive","acted","moved","integrity","defense_integrity","attack_count","item_slots","skill_counts","gained_xp","direction"]:
		check(u.get(field)==v.get(field),label+" "+field)
	check(u.data.get("level")==v.data.get("level") and u.data.get("xp")==v.data.get("xp"),label+" XP/level")
func mapping(inspection:Dictionary,passed:bool) -> Dictionary:
	var out:Dictionary={}
	for op in inspection.opportunities:
		if op.requires_outcome:out[op.key]=passed
	return out
func run() -> void:
	data=JSON.parse_string(FileAccess.get_file_as_string("res://data/m4.json"))
	var b=fixture();var hero=unit(b,0,0,Vector2i(5,5));var v=unit(b,40,1,Vector2i(5,4))
	var s=shadow(b);var a:=action(11,Vector2i(5,4));var before:=Forecast.snapshot(s)
	var inspected:=Forecast.inspect_action_outcomes(s,s.unit_by_slot(0),a)
	check(inspected.status=="needs_outcomes" and inspected.opportunities.size()==1 and inspected.opportunities[0].chance==30,"one uncertain target identified without RNG")
	check(Forecast.snapshot(s)==before and b.rng_state==987654 and b.roll_calls==0,"discovery is read-only for shadow and live RNG")
	for invalid in [{},{"stale":true},{inspected.opportunities[0].key:1}]:
		var failed:=Forecast.apply_action_with_outcomes(s,s.unit_by_slot(0),a,invalid)
		check(failed.status=="invalid" and Forecast.snapshot(s)==before,"missing/extra/nonbool outcome fully atomic")
	var single:=Outcomes.action_variants(s,0,a)
	check(single.complete and single.branches.size()==2,"one target gives exactly two outcomes")
	for branch in single.branches:
		var passed:bool=branch.trace[-1].outcomes.values()[0]
		check(branch.board.unit_by_slot(40).acted==passed,"one bool controls only its named target")
		check(branch.board.unit_by_slot(0).acted and branch.board.unit_by_slot(0).skill_counts.yibing==(2 if passed else 1),"failed roll spends action but no usage")
	Outcomes.dispose(single.branches)
	# Opposite slot/tile ordering. All four AOE assignments have independent
	# usage, XP and growth; native _rand100 is replaced only in THIS fixture.
	for mask in range(4):
		b=fixture();hero=unit(b,0,0,Vector2i(5,5));hero.data.xp=93
		var first=unit(b,41,1,Vector2i(5,4));var second=unit(b,40,1,Vector2i(6,4));two_cell_mask(b,11)
		s=shadow(b);inspected=Forecast.inspect_action_outcomes(s,s.unit_by_slot(0),a)
		check(inspected.opportunities.map(func(op):return int(op.target_slot))==[41,40],"AOE rolls use row-major cells not slots")
		var outcomes:Dictionary={}
		for i in range(2):outcomes[inspected.opportunities[i].key]=(mask&(1<<i))!=0
		var applied:=Forecast.apply_action_with_outcomes(s,s.unit_by_slot(0),a,outcomes)
		b.fixture_rolls=[0 if mask&1 else 99,0 if mask&2 else 99];b.selected=hero;b.active_skill_id=11;b.active_skill=b.data.skills[11]
		await b._execute_skill_at(Vector2i(5,4))
		check(applied.complete and b.roll_calls==2,"each AOE target rolls independently")
		numbers(hero,s.unit_by_slot(0),"caster mask%d"%mask);numbers(first,s.unit_by_slot(41),"first mask%d"%mask);numbers(second,s.unit_by_slot(40),"second mask%d"%mask)
	# Enumeration/caps preserve the source exactly. No partial-success result.
	var all:=Outcomes.action_variants(s,0,a) # actor already acted -> invalid, not silently skipped
	check(not all.complete and all.status=="invalid" and all.branches.is_empty(),"used actor cannot be replayed as complete")
	s=shadow(b);s.unit_by_slot(0).acted=false;s.unit_by_slot(41).acted=false;s.unit_by_slot(40).acted=false
	all=Outcomes.action_variants(s,0,a,{"branches":4,"actions":4})
	check(all.complete and all.branches.size()==4 and all.budget.actions_expanded==4,"two targets gives four, exact budget complete")
	Outcomes.dispose(all.branches)
	for cap in [{"branches":3},{"actions":3},{"branches":0}]:
		all=Outcomes.action_variants(s,0,a,cap)
		check(not all.complete and all.status=="incomplete" and all.branches.is_empty(),"every unexpanded outcome rejects cap")
	# Every supported random skill, every two-target assignment. This changes
	# only fixture rolls in a stripped numerical production resolver, not the
	# live game, its RNG or any campaign state. Death objects kept for comparison.
	for sid in [3,4,5,6,7,8,10,11,12,13,14]:
		for mask in range(4):
			b=fixture();hero=unit(b,0,0,Vector2i(5,5));hero.data.xp=93;hero.skill_counts[b.SKILL_KEYS[sid]]=9
			var first=unit(b,41,0 if sid==12 else 1,Vector2i(5,4));var second=unit(b,40,0 if sid==12 else 1,Vector2i(6,4))
			for target in [first,second]:target.hp=40;target.max_hp=150;target.morale=40;target.integrity=50;target.defense_integrity=20;target.acted=true;target.moved=true
			two_cell_mask(b,sid);s=shadow(b);a=action(sid,Vector2i(5,4));var su=s.unit_by_slot(0);var sv1=s.unit_by_slot(41);var sv2=s.unit_by_slot(40)
			inspected=Forecast.inspect_action_outcomes(s,su,a);var outcomes:Dictionary={}
			for i in range(2):outcomes[inspected.opportunities[i].key]=(mask&(1<<i))!=0
			var applied:=Forecast.apply_action_with_outcomes(s,su,a,outcomes)
			b.fixture_rolls=[0 if mask&1 else 99,0 if mask&2 else 99];b.selected=hero;b.active_skill_id=sid;b.active_skill=b.data.skills[sid]
			await b._execute_skill_at(Vector2i(5,4))
			check(applied.complete and b.roll_calls==2,"random skill independent rolls sid%d mask%d"%[sid,mask])
			numbers(hero,su,"random caster sid%d mask%d"%[sid,mask]);numbers(first,sv1,"random victim1 sid%d mask%d"%[sid,mask]);numbers(second,sv2,"random victim2 sid%d mask%d"%[sid,mask])
			check(s.stats==b.stats,"random skill XP/death/classification stats sid%d mask%d"%[sid,mask])
	# Missing second key cannot leave first effect, movement or facing behind.
	b=fixture();hero=unit(b,0,0,Vector2i(5,6));unit(b,41,1,Vector2i(5,4));unit(b,40,1,Vector2i(6,4));two_cell_mask(b,11)
	s=shadow(b);a=action(11,Vector2i(5,4),{"station":Vector2i(5,5)})
	inspected=Forecast.inspect_action_outcomes(s,s.unit_by_slot(0),a);before=Forecast.snapshot(s)
	var partial:Dictionary={inspected.opportunities[0].key:true}
	check(Forecast.apply_action_with_outcomes(s,s.unit_by_slot(0),a,partial).status=="invalid" and Forecast.snapshot(s)==before,"invalid second result cannot commit movement or partial AOE")
	var stale:=mapping(inspected,true);s.unit_by_slot(41).data.zhili=11;before=Forecast.snapshot(s)
	check(Forecast.apply_action_with_outcomes(s,s.unit_by_slot(0),a,stale).status=="invalid" and Forecast.snapshot(s)==before,"changed target INT invalidates old outcome key")
	# Immunity still records native roll-before-class45, without splitting two
	# equivalent states or shifting later targets' semantic keys.
	b=fixture();hero=unit(b,0,0,Vector2i(5,5));var immune=unit(b,41,0,Vector2i(5,4));immune.bingzhong=45;immune.acted=true
	v=unit(b,40,0,Vector2i(6,4));v.acted=true;two_cell_mask(b,12);s=shadow(b);a=action(12,Vector2i(5,4))
	inspected=Forecast.inspect_action_outcomes(s,s.unit_by_slot(0),a)
	check(inspected.opportunities.size()==2 and inspected.opportunities[0].immune_after_roll and inspected.opportunities[0].roll_before_immunity and not inspected.opportunities[0].requires_outcome,"immune target logs native roll before immunity")
	all=Outcomes.action_variants(s,0,a)
	check(all.complete and all.branches.size()==2,"immune adds no spurious public branches")
	for branch in all.branches:
		check(branch.board.unit_by_slot(41).acted,"immune remains spent in both branches")
		check(branch.trace[-1].applied.opportunities[0].roll_passed=="elided-immune","immune roll elision is explicit, not RNG prediction")
	Outcomes.dispose(all.branches)
	# Two unknown targets with chance0/100 targets in between. Unknown keys do
	# not depend on skipping deterministic rolls in a flat boolean stream.
	b=fixture();hero=unit(b,0,0,Vector2i(5,5));hero.data.zhili=50
	var matrix:Array=[]
	for row in range(7):matrix.append([0,0,0,0,0,0,0])
	for x in range(2,6):matrix[3][x]=100
	b.data.apply_ranges[str(Rules.skill_apply(int(b.data.skills[11].apply_fw),1))]=matrix
	for i in range(4):
		v=unit(b,43-i,1,Vector2i(4+i,4));v.data.zhili=[50,100,0,50][i]
	s=shadow(b);a=action(11,Vector2i(5,4));inspected=Forecast.inspect_action_outcomes(s,s.unit_by_slot(0),a)
	check(inspected.opportunities.map(func(op):return int(op.chance))==[30,0,130,30],"mixed chance records preserve actual row-major opportunities")
	all=Outcomes.action_variants(s,0,a)
	check(all.complete and all.branches.size()==4,"only two nonimmune unknowns branch among four targets")
	for branch in all.branches:
		check(not branch.board.unit_by_slot(42).acted and branch.board.unit_by_slot(41).acted,"deterministic failure/success unaffected by adjacent unknowns")
	Outcomes.dispose(all.branches)
	# Known chance boundaries have roll records but accept no arbitrary boolean.
	for intelligence in [-100,100]:
		b=fixture();hero=unit(b,0,0,Vector2i(5,5));hero.data.zhili=intelligence;unit(b,40,1,Vector2i(5,4));s=shadow(b);a=action(11,Vector2i(5,4))
		inspected=Forecast.inspect_action_outcomes(s,s.unit_by_slot(0),a)
		check(inspected.complete and inspected.opportunities[0].deterministic,"0/100 chance requires no outcome")
		before=Forecast.snapshot(s)
		check(Forecast.apply_action_with_outcomes(s,s.unit_by_slot(0),a,{inspected.opportunities[0].key:intelligence<0}).status=="invalid" and Forecast.snapshot(s)==before,"contradictory deterministic outcome rejected atomically")
		all=Outcomes.action_variants(s,0,a);check(all.complete and all.branches.size()==1,"deterministic chance has only one public result");Outcomes.dispose(all.branches)
	# Ordinary contact mine interrupts before cast, even if actor survives.
	b=fixture();hero=unit(b,0,0,Vector2i(5,6));unit(b,40,1,Vector2i(5,4));var mine:Dictionary=b.data.mines[0].duplicate(true);mine.weili=1
	b.mines=[{"tile":Vector2i(5,5),"mine":mine,"mine_id":0,"code":0,"low":1,"owner_side":"enemy"}]
	s=shadow(b,[Vector2i(5,5)]);a=action(11,Vector2i(5,4),{"station":Vector2i(5,5)})
	inspected=Forecast.inspect_action_outcomes(s,s.unit_by_slot(0),a)
	check(inspected.complete and inspected.event.interrupted and inspected.opportunities.is_empty() and inspected.event.cast==0,"movement mine has zero cast/roll opportunities")
	before=Forecast.snapshot(s)
	check(Forecast.apply_action_with_outcomes(s,s.unit_by_slot(0),a,{"unconsumed-cast":true}).status=="invalid" and Forecast.snapshot(s)==before,"pre-supplied interrupted cast key is not consumed")
	all=Outcomes.action_variants(s,0,a)
	check(all.complete and all.branches.size()==1 and all.branches[0].board.mines.is_empty() and all.branches[0].board.unit_by_slot(0).acted,"mine interruption completes exactly one real branch")
	var child=Forecast.clone_branch(all.branches[0].board)
	check(child.mine_events.size()==1 and child.mines.is_empty() and child.unit_by_slot(0).skill_counts.yibing==1,"removed mine/event and unspent skill survive subclone")
	child.free();Outcomes.dispose(all.branches)
	# Dynamic supervisor split: 8 waits, 9 may reopen 8 before 40. A flat list
	# cannot represent both traces. Reopened cast identities are distinct.
	b=fixture();hero=unit(b,0,0,Vector2i(1,1));var ally=unit(b,8,0,Vector2i(5,4));ally.auto=true
	var supervisor=unit(b,9,0,Vector2i(5,5));supervisor.auto=true;supervisor.behavior=0
	for key in supervisor.skill_counts:supervisor.skill_counts[key]=0
	supervisor.skill_counts.duzhan=1;unit(b,40,1,Vector2i(10,10));s=shadow(b)
	all=Outcomes.drain_ai_variants(s,{"branches":2,"actions":6,"phase_steps":4})
	check(all.complete and all.branches.size()==2,"supervisor dynamic phase exhausts both outcomes")
	check(all.budget.actions_expanded==6,"exact shared dispatch-result budget counted across both branches")
	var traces:Array=[]
	for branch in all.branches:traces.append(branch.trace.map(func(t):return int(t.slot)))
	check(traces.has([8,9,40]) and traces.has([8,9,8,40]),"renewal changes actual lowest-slot dispatch order")
	Outcomes.dispose(all.branches)
	all=Outcomes.drain_ai_variants(s,{"branches":2,"actions":5,"phase_steps":4})
	check(not all.complete and all.status=="incomplete" and all.branches.is_empty(),"one missing action-result budget invalidates whole phase")
	all=Outcomes.drain_ai_variants(s,{"phase_steps":3})
	check(not all.complete and all.status=="incomplete" and all.branches.is_empty(),"one longer supervisor branch hitting cap invalidates whole phase")
	all=Outcomes.drain_ai_variants(s,{"branches":1})
	check(not all.complete and all.status=="incomplete","AI branch cap cannot hide renewal branch")
	# Same caster, same skill/target in one turn after a legal supervisor
	# reopening still has a different dispatch/cast ID. Never reuse old bools.
	b=fixture();hero=unit(b,0,0,Vector2i(5,5));ally=unit(b,8,0,Vector2i(5,4));ally.acted=true
	supervisor=unit(b,9,0,Vector2i(6,5))
	matrix=[]
	for row in range(7):matrix.append([0,0,0,0,0,0,0])
	matrix[3][3]=100;b.data.apply_ranges[str(Rules.skill_apply(int(b.data.skills[12].apply_fw),1))]=matrix
	s=shadow(b);a=action(12,Vector2i(5,4));inspected=Forecast.inspect_action_outcomes(s,s.unit_by_slot(0),a);stale=mapping(inspected,true)
	check(Forecast.apply_action_with_outcomes(s,s.unit_by_slot(0),a,stale).complete,"first supervisor cast committed")
	var reopen:=action(12,Vector2i(5,5));var reopen_inspection:=Forecast.inspect_action_outcomes(s,s.unit_by_slot(9),reopen)
	check(Forecast.apply_action_with_outcomes(s,s.unit_by_slot(9),reopen,mapping(reopen_inspection,true)).complete and not s.unit_by_slot(0).acted,"another legal caster reopens original caster")
	var later:=Forecast.inspect_action_outcomes(s,s.unit_by_slot(0),a)
	check(later.event.dispatch==3 and later.event.cast==2 and later.opportunities[0].key!=inspected.opportunities[0].key,"repeated same-cast identity is unique")
	before=Forecast.snapshot(s)
	check(Forecast.apply_action_with_outcomes(s,s.unit_by_slot(0),a,stale).status=="invalid" and Forecast.snapshot(s)==before,"prior cast mapping cannot replay after renewal")
	# One critical-death result poisons universal survival, even when all
	# conditional outcomes are completely enumerated.
	b=fixture();hero=unit(b,0,0,Vector2i(5,4));hero.hp=1;v=unit(b,40,1,Vector2i(5,5));v.data.zhili=15;v.behavior=12
	for key in v.skill_counts:v.skill_counts[key]=0
	v.skill_counts.ansha=1
	var two:=Outcomes.evaluate_two_phases_fixed(b,[],[],[],{"branches":16})
	check(two.complete and not two.conditional_survival and not two.all_critical_alive,"covered lethal branch cannot become universal survival")
	check(two.leaves.any(func(leaf):return leaf.terminal) and two.leaves.any(func(leaf):return not leaf.terminal),"both lethal and surviving critical outcomes retained")
	var lethal:Dictionary=two.leaves.filter(func(leaf):return leaf.terminal)[0]
	check(not lethal.state.units[0].alive,"critical casualty tombstone retained in final snapshot")
	check(lethal.phases.size()<=2 and lethal.trace.filter(func(t):return t.slot==0).is_empty(),"terminal branch does not invent a new player action")
	var tombstone=Forecast.clone_branch(s);Forecast.record_death(tombstone,tombstone.unit_by_slot(0));var tombstone_child=Forecast.clone_branch(tombstone)
	check(Forecast.critical_lost(tombstone_child) and tombstone_child.units.any(func(actor):return actor.slot==0 and not actor.alive),"subclone preserves dead critical identity")
	tombstone.free();tombstone_child.free()
	# Food/throw are spent once BEFORE stochastic AI. Both phases keep all
	# consumption, XP and admitted enemy mines, while source resources stay put.
	b=fixture();hero=unit(b,0,0,Vector2i(1,1));hero.hp=20;hero.item_slots=[2,0,0,0,0,0,0,0]
	var thrower=unit(b,1,0,Vector2i(8,8));thrower.item_slots=[42,0,0,0,0,0,0,0];thrower.data.xp=98
	v=unit(b,40,1,Vector2i(8,7));v.hp=1
	ally=unit(b,8,0,Vector2i(5,4));ally.auto=true;supervisor=unit(b,9,0,Vector2i(5,5));supervisor.auto=true;supervisor.behavior=0
	for key in supervisor.skill_counts:supervisor.skill_counts[key]=0
	supervisor.skill_counts.duzhan=1
	b.data["levels"]=[{"future":"private"}];b.level["triggers"]={"future":"private"};b.battle_context={"hidden_stock":12345}
	b.mines=[{"tile":Vector2i(10,10),"mine":b.data.mines[0],"mine_id":0,"code":20,"low":3,"owner_side":"enemy"},
		{"tile":Vector2i(10,9),"mine":b.data.mines[0],"mine_id":0,"code":20,"low":3,"owner_side":"player"}]
	var live_before:Dictionary={"data":b.data.duplicate(true),"level":b.level.duplicate(true),"context":b.battle_context.duplicate(true),"mines":b.mines.duplicate(true),"stats":b.stats.duplicate(true),"units":b.units.map(func(actor):return actor.state_record())}
	var first_plan:Array=[{"slot":0,"action":{"kind":"item","item":1,"tile":Vector2i(1,1)}},
		{"slot":1,"action":{"kind":"item","item":41,"tile":Vector2i(8,7)}}]
	two=Outcomes.evaluate_two_phases_fixed(b,first_plan,[],[Vector2i(10,10)],{"branches":16})
	check(two.complete and two.conditional_survival and two.leaves.size()==4,"two phases enumerate every supervisor combination after consumption")
	for leaf in two.leaves:
		check(not leaf.state.units[0].item_slots.has(2) and not leaf.state.units[1].item_slots.has(42),"food and throw stay consumed in every grandchild")
		check(leaf.state.units[1].gained_xp>0 and leaf.state.stats.kills==1,"XP/death persists instead of recloning live origin")
		check(leaf.state.mines.size()==2 and leaf.state.mines.all(func(rec):return rec.low==2),"known enemy and own timer stay in every subclone exactly one maintenance")
		check(leaf.phases[0].turn==1 and leaf.phases[1].turn==2 and leaf.boundaries.size()==1,"each result has one real maintenance between two phases")
	check(b.data==live_before.data and b.level==live_before.level and b.battle_context==live_before.context and b.mines==live_before.mines and b.stats==live_before.stats and b.rng_state==987654 and b.roll_calls==0,"whole live public/hidden payload and RNG unchanged")
	check(b.units.map(func(actor):return actor.state_record())==live_before.units,"all live unit state remains byte-value equivalent after complete tree")
	two=Outcomes.evaluate_two_phases_fixed(b,first_plan,[first_plan[0]],[Vector2i(10,10)])
	check(not two.complete and two.status=="invalid" and not two.conditional_survival,"fixed second plan cannot reuse food in ANY branch")
	# Death at the maintenance boundary, including an objective-protected NPC,
	# also ends the branch before an invented second-phase safety claim.
	b=fixture();hero=unit(b,0,0,Vector2i(1,1));ally=unit(b,7,0,Vector2i(5,5));ally.protected=true;ally.hp=1
	b.mines=[{"tile":Vector2i(5,5),"mine":b.data.mines[0],"mine_id":0,"code":20,"low":2,"owner_side":"player"}]
	two=Outcomes.evaluate_two_phases_fixed(b,[],[])
	check(two.complete and not two.conditional_survival and two.leaves.size()==1 and two.leaves[0].terminal,"protected death in maintenance retained as terminal outcome")
	check(two.leaves[0].phases.size()==1 and two.leaves[0].boundaries.size()==1 and not two.leaves[0].state.units[7].alive,"no fictitious second phase after maintenance terminal")
	b.finished_flag=true;two=Outcomes.evaluate_two_phases_fixed(b,[],[])
	check(not two.complete and two.status=="terminal","source terminal boundary still refuses planning")
	# Adaptive quantifier: different finite second witnesses may be selected
	# for each first result. The callback cannot mutate search-owned state.
	b=fixture();hero=unit(b,0,0,Vector2i(5,5));v=unit(b,40,1,Vector2i(5,4))
	first_plan=[{"slot":0,"action":action(8,Vector2i(5,4))}]
	var adaptive_calls:Array=[]
	var generator:=func(public):
		var integrity:int=public.unit_by_slot(40).integrity;adaptive_calls.append(integrity)
		var invalid:Array=[{"slot":0,"action":{"kind":"remote"}}]
		var wait:Array=[{"slot":0,"action":{"kind":"wait"}}]
		var attack:Array=[{"slot":0,"action":{"kind":"attack","tile":Vector2i(5,4)}}]
		public.unit_by_slot(0).hp=0;public.stats.losses=123;public.data.skills[0].para1=999 # disposable callback clone only
		return [invalid,attack] if integrity<100 else [wait,invalid]
	var adaptive:=Outcomes.evaluate_two_phases_adaptive(b,first_plan,generator)
	check(adaptive.complete and adaptive.conditional_survival and adaptive.witnesses.size()==2 and adaptive_calls.size()==2,"forall first results each obtains a finite second witness")
	check(adaptive_calls.has(70) and adaptive_calls.has(100),"next candidate generation reads each actual post-maintenance branch")
	check(adaptive.witnesses.map(func(witness):return int(witness.candidate)).has(1) and adaptive.witnesses.map(func(witness):return int(witness.candidate)).has(0),"candidate existential choice is local to first outcome")
	for witness in adaptive.witnesses:
		check(witness.second_leaves.all(func(leaf):return leaf.state.units[0].alive and leaf.state.stats.losses==0),"callback mutation never reaches search-owned witness")
		check(witness.boundary.turn==2 and witness.first_state.turn==1,"adaptive witness advances once, not duplicate H1")
	check(hero.hp==100 and b.stats.losses==0 and b.data.skills[0].para1!=999 and b.roll_calls==0 and b.rng_state==987654,"adaptive generation leaves source including RNG unchanged")
	adaptive=Outcomes.evaluate_two_phases_adaptive(b,first_plan,func(_public):return [[]],[],{"candidates":0})
	check(not adaptive.complete and adaptive.status=="incomplete" and not adaptive.conditional_survival,"unexpanded second candidate is never a witness")
	adaptive=Outcomes.evaluate_two_phases_adaptive(b,first_plan,func(_public):return [[]],[],{"candidates":1})
	check(not adaptive.complete and adaptive.status=="incomplete" and adaptive.budget.candidates_expanded==1,"candidate budget is global, not reset per first outcome")
	adaptive=Outcomes.evaluate_two_phases_adaptive(b,first_plan,func(_public):return [[]],[],{"candidates":2})
	check(adaptive.complete and adaptive.witnesses.size()==2 and adaptive.budget.candidates_expanded==2,"exact shared candidate budget admits both first outcomes")
	adaptive=Outcomes.evaluate_two_phases_adaptive(b,first_plan,func(_public):return [])
	check(not adaptive.complete and adaptive.status=="infeasible" and adaptive.reason.contains("supplied finite"),"no candidates refutes only supplied finite search")
	adaptive=Outcomes.evaluate_two_phases_adaptive(b,first_plan,func(_public):return [[123]])
	check(not adaptive.complete and adaptive.status=="infeasible","malformed player command cannot crash or create witness")
	# First deterministic feint keeps enemy silent until second phase. Every
	# supplied second candidate then has both lethal and surviving roll results;
	# existence of a favorable second leaf must not satisfy universal survival.
	b=fixture();hero=unit(b,0,0,Vector2i(5,4));hero.hp=1
	var controller=unit(b,1,0,Vector2i(6,5));controller.data.zhili=100
	v=unit(b,40,1,Vector2i(5,5));v.data.zhili=15;v.behavior=12
	for key in v.skill_counts:v.skill_counts[key]=0
	v.skill_counts.ansha=1
	first_plan=[{"slot":1,"action":action(11,Vector2i(5,5))}]
	generator=func(_public):return [[],[{"slot":0,"action":{"kind":"wait"}}]]
	adaptive=Outcomes.evaluate_two_phases_adaptive(b,first_plan,generator,[],{"branches":16})
	check(not adaptive.complete and adaptive.status=="infeasible" and not adaptive.conditional_survival and adaptive.rejected.size()==2,"one surviving second outcome cannot satisfy forall second results")
	check(adaptive.rejected.all(func(rejected):return rejected.status=="critical-casualty" and rejected.terminal_leaves==1),"each rejected candidate retains its lethal branch count")
	adaptive=Outcomes.evaluate_two_phases_adaptive(b,first_plan,generator,[],{"branches":1})
	check(not adaptive.complete and adaptive.status=="incomplete" and not adaptive.conditional_survival,"adaptive branch exhaustion is unknown not bounded infeasibility")
	# Cleanup all source/shadow fixtures and all result-owned branches above.
	for board in boards:board.free()
	boards.clear();await process_frame
	print("PUBLIC_OUTCOME_TREE checks=",checks," failures=",failures)
	quit(1 if failures else 0)
