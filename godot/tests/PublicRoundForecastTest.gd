extends SceneTree
# Synthetic, deterministic and differential fixtures only. Not campaign proof.
const Forecast=preload("res://tests/helpers/PublicRoundForecast.gd")
const Rules=preload("res://scripts/battle/CombatRules.gd")
const Unit=preload("res://scripts/BattleUnit.gd")
class NumericBattle extends "res://scripts/Battle.gd":
	# Strip presentation and Scenario/end hooks, never numerical transactions.
	func _complete_unit_death(_u:Node2D) -> void:pass
	func _check_end() -> bool:return false
	func _log(_text:String) -> void:pass
	func _after_completed_action(_u) -> void:pass
var checks:=0
var failures:=0
var data:Dictionary
var boards:Array=[]
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:failures+=1;push_error("PUBLIC_ROUND_FORECAST_FAIL "+label)
func fixture():
	var b=NumericBattle.new();root.add_child(b);boards.append(b)
	b.data=data.duplicate(true);b.map_w=12;b.map_h=12;b.terrain.resize(144);b.terrain.fill(0)
	b.level={"index":0,"difficulty_setting":1};b.turn=1
	b.fast_sim=true;b.animations_enabled=false;b.sfx_enabled=false;b.set_process(false)
	b.stats={"losses":0,"kills":0,"xp":0};b.rng_state=123456
	for mods in b.data.terrain_modifiers:mods[3]=0;mods[4]=0
	return b
func unit(b,slot:int,faction:int,tile:Vector2i):
	var u=Unit.new();u.slot=slot;u.pid=slot;u.x=tile.x;u.y=tile.y
	u.side="player" if faction==0 else "enemy";u.data={"faction":faction,"level":4,"xp":0,"wuli":70,"zhili":100}
	u.hp=100;u.max_hp=100;u.morale=100;u.bingzhong=1;u.select=1;u.move=4;u.control=true;u.behavior=11
	u.item_slots=[0,0,0,0,0,0,0,0];u.mine_slots=[0,0,0,0,0,0,0,0]
	for key in b.SKILL_KEYS:u.skill_counts[key]=1
	b.add_child(u);b.units.append(u)
	if faction==0:b.player_units.append(u)
	else:b.enemy_units.append(u)
	return u
func shadow(b,known:Array=[]):
	var s=Forecast.clone_public_board(b,known);boards.append(s);return s
func action(kind:String,tile:Vector2i,extra:Dictionary={}) -> Dictionary:
	var a:Dictionary={"kind":kind,"tile":tile};a.merge(extra);return a
func same_numbers(a,b,label:String) -> void:
	for field in ["hp","max_hp","morale","alive","acted","moved","integrity","defense_integrity","attack_count","item_slots","skill_counts","gained_xp","direction"]:
		check(a.get(field)==b.get(field),label+" "+field)
	check(a.data.get("level")==b.data.get("level") and a.data.get("xp")==b.data.get("xp"),label+" level/XP")
func run() -> void:
	data=JSON.parse_string(FileAccess.get_file_as_string("res://data/m4.json"))
	var b=fixture();var hero=unit(b,0,0,Vector2i(2,2));var enemy=unit(b,40,1,Vector2i(8,8))
	b.data["levels"]=[{"secret":true}];b.level["triggers"]={"secret":true};b.battle_context={"secret":true}
	b.mines=[{"tile":Vector2i(1,1),"owner_side":"enemy","code":0,"low":1,"mine":b.data.mines[0]},
		{"tile":Vector2i(3,3),"owner_side":"player","code":20,"low":3,"mine":b.data.mines[0]}]
	var s=shadow(b);var u=s.unit_by_slot(0)
	check(not s.data.has("levels") and not s.level.has("triggers") and s.scenario==null and s.battle_context.is_empty(),"no future/Scenario/context payload")
	check(s.mines.size()==1 and s.mines[0].tile==Vector2i(3,3),"only own or explicitly revealed mines")
	var revealed=shadow(b,[Vector2i(1,1)]);check(revealed.mines.size()==2,"explicit known enemy mine copied")
	s.data.skills[0].para1=999;s.terrain[0]=15;s.mines[0].low=2;u.data.level=50;u.item_slots[0]=1
	check(b.data.skills[0].para1!=999 and b.terrain[0]==0 and b.mines[1].low==3 and hero.data.level==4 and hero.item_slots[0]==0,"all mutable buffers isolated")
	check(b.rng_state==123456 and s.rng_state!=b.rng_state,"live RNG not copied or consumed")
	# Movement budget is local to a phase; integrity/behavior survive a boundary.
	b=fixture();hero=unit(b,0,0,Vector2i(2,2));enemy=unit(b,40,1,Vector2i(10,10));s=shadow(b);u=s.unit_by_slot(0)
	var moved:Dictionary=Forecast.apply_action(s,u,action("wait",Vector2i(3,2),{"station":Vector2i(3,2)}))
	check(moved.complete and u.moved and u.acted and u.x==3,"legal movement plus wait commits one action")
	check(Forecast.apply_action(s,u,action("wait",Vector2i(3,2))).status=="invalid","no second submission in same phase")
	check(Forecast.advance_public_round(s).status=="invalid","cannot skip a pending AI queue")
	check(Forecast.drain_public_ai_phase(s).complete,"first AI phase drains")
	u.integrity=50;u.defense_integrity=60;u.status_stun=1;u.behavior=8;u.target_x=7
	check(Forecast.advance_public_round(s).complete and s.turn==2,"one genuine public round increment")
	check(not u.acted and not u.moved and u.status_stun==0 and u.integrity==50 and u.defense_integrity==60 and u.behavior==8 and u.target_x==7,"only action budgets reset, no full battle initialization")
	check(Forecast.apply_action(s,u,action("wait",Vector2i(4,2),{"station":Vector2i(4,2)})).complete and u.x==4,"second phase has exactly renewed movement")
	# Consumption compacts once. A single food cannot be reused in phase two.
	b=fixture();hero=unit(b,0,0,Vector2i(2,2));hero.hp=20;hero.item_slots=[2,33,0,0,0,0,0,0];s=shadow(b);u=s.unit_by_slot(0)
	check(Forecast.apply_action(s,u,action("item",Vector2i(2,2),{"item":1})).complete and u.item_slots==[33,0,0,0,0,0,0,0],"one food removed with original bag compaction")
	var before:int=u.hp;Forecast.drain_public_ai_phase(s);Forecast.advance_public_round(s)
	check(u.hp==mini(u.max_hp,before+u.max_hp*15/100) and u.item_slots[0]==33,"auto book recovers once, not consumed")
	check(Forecast.apply_action(s,u,action("item",Vector2i(2,2),{"item":1})).status=="invalid","cannot reuse consumed food")
	check(hero.item_slots==[2,33,0,0,0,0,0,0] and hero.hp==20,"consumption/recovery never writes source")
	# Effective supply crosses count9->10. Full-health supply gives no XP/practice.
	b=fixture();hero=unit(b,0,0,Vector2i(2,2));hero.hp=10;hero.skill_counts.buji=9;s=shadow(b);u=s.unit_by_slot(0)
	check(Forecast.apply_action(s,u,action("skill",Vector2i(2,2),{"skill":0})).complete and u.skill_counts.buji==10 and u.gained_xp>0,"effective supply crosses usage threshold")
	Forecast.drain_public_ai_phase(s);Forecast.advance_public_round(s);u.hp=u.max_hp
	var xp:int=u.gained_xp
	check(Forecast.apply_action(s,u,action("skill",Vector2i(2,2),{"skill":0})).complete and u.skill_counts.buji==10 and u.gained_xp==xp,"full-health supply consumes action without usage/XP")
	# Deterministic production/forecast skill transactions match, including
	# zero numerical change still counting for harass/sabotage/feint/supervise.
	for sid in [0,1,2,3,4,5,6,7,8,10,11,12,13,14,15]:
		b=fixture();hero=unit(b,0,0,Vector2i(5,5));var v=unit(b,1 if sid in [0,1,2,12] else 40,0 if sid in [0,1,2,12] else 1,Vector2i(5,1 if sid==15 else 4))
		hero.data.xp=93;hero.skill_counts[b.SKILL_KEYS[sid]]=9
		v.data.zhili=0;v.hp=40;v.max_hp=150;v.morale=40;v.integrity=50;v.defense_integrity=20;v.acted=true;v.moved=true
		s=shadow(b);var su=s.unit_by_slot(0);var sv=s.unit_by_slot(v.slot)
		var applied:Dictionary=Forecast.apply_action(s,su,action("skill",Vector2i(v.x,v.y),{"skill":sid}))
		b.selected=hero;b.active_skill_id=sid;b.active_skill=b.data.skills[sid]
		await b._execute_skill_at(Vector2i(v.x,v.y))
		check(applied.complete,"deterministic skill accepted %d"%sid)
		same_numbers(hero,su,"caster sid%d"%sid);same_numbers(v,sv,"target sid%d"%sid)
	# Supervisor renews moved and both integrity values; feint does not persist.
	b=fixture();hero=unit(b,0,0,Vector2i(5,5));var ally=unit(b,8,0,Vector2i(5,4));ally.data.zhili=0;ally.acted=true;ally.moved=true;ally.integrity=50;ally.defense_integrity=60
	s=shadow(b);u=s.unit_by_slot(8)
	check(Forecast.apply_action(s,s.unit_by_slot(0),action("skill",Vector2i(5,4),{"skill":12})).complete and not u.acted and not u.moved and u.integrity==70 and u.defense_integrity==80,"supervise action+move+repair")
	check(Forecast.drain_public_ai_phase(s).complete,"renewed controlled unit closed only at player-end")
	Forecast.advance_public_round(s);check(u.integrity==70 and u.defense_integrity==80,"repaired integrity persists across normal round")
	# Unknown controls and unsupported inventory channels fail closed.
	b=fixture();hero=unit(b,0,0,Vector2i(5,5));enemy=unit(b,40,1,Vector2i(5,4));hero.data.zhili=10;enemy.data.zhili=10;s=shadow(b)
	check(Forecast.apply_action(s,s.unit_by_slot(0),action("skill",Vector2i(5,4),{"skill":11})).status=="unsupported" and not s.unit_by_slot(40).acted,"uncertain player feint is not assumed to save anyone")
	check(Forecast.apply_action(s,s.unit_by_slot(40),action("skill",Vector2i(5,5),{"skill":11})).status=="unsupported","uncertain enemy skill also explicit incomplete")
	check(Forecast.apply_action(s,s.unit_by_slot(0),action("skill",Vector2i(5,4),{"skill":9})).status=="unsupported","plunder not silently approximated")
	check(Forecast.apply_action(s,s.unit_by_slot(0),{"kind":"remote"}).status=="unsupported","non-contact operation unsupported")
	s.unit_by_slot(40).data.zhili=100
	check(Forecast.apply_action(s,s.unit_by_slot(0),action("skill",Vector2i(5,4),{"skill":11})).complete and not s.unit_by_slot(40).acted and s.unit_by_slot(0).gained_xp==0,"zero-chance skill is deterministic failure, no XP")
	b=fixture();hero=unit(b,0,0,Vector2i(5,5));ally=unit(b,8,0,Vector2i(5,4));hero.data.zhili=10;ally.data.zhili=10;ally.bingzhong=45;ally.acted=true;ally.moved=true;s=shadow(b)
	check(Forecast.apply_action(s,s.unit_by_slot(0),action("skill",Vector2i(5,4),{"skill":12})).complete and s.unit_by_slot(8).acted and s.unit_by_slot(0).gained_xp==0,"class45 supervisor immunity independent of unknown roll")
	# Two true AI phases, not evaluate_sequence twice with stale acted flags.
	b=fixture();hero=unit(b,0,0,Vector2i(1,1));enemy=unit(b,40,1,Vector2i(10,10))
	var two:Dictionary=Forecast.evaluate_two_phases(b,[],[])
	check(two.complete and two.conditional and two.phases.size()==2 and two.phases[0].ai.plans.size()==1 and two.phases[1].ai.plans.size()==1,"two independently drained AI phases")
	check(two.phases[0].state.turn==1 and two.phases[1].state.turn==2 and b.turn==1 and not enemy.acted,"public turn boundary never touches source")
	two=Forecast.evaluate_two_phases(b,[],[],[],0)
	check(not two.complete and two.status=="incomplete","AI step cap cannot report zero-risk complete")
	two=Forecast.evaluate_two_phases(b,[],[],[],1)
	check(two.complete,"exact AI limit with empty queue is complete, not truncated")
	# Genuine dynamic low-slot rescheduling after slot9 supervisor. slot8 first
	# waits;9 renews it;8 then acts before40 (not fixed faction block order).
	b=fixture();hero=unit(b,0,0,Vector2i(1,1));ally=unit(b,8,0,Vector2i(5,4));ally.auto=true;ally.data.zhili=0
	var supervisor=unit(b,9,0,Vector2i(5,5));supervisor.auto=true;supervisor.behavior=0
	for key in supervisor.skill_counts:supervisor.skill_counts[key]=0
	supervisor.skill_counts.duzhan=1
	enemy=unit(b,40,1,Vector2i(10,10));s=shadow(b)
	var drained:Dictionary=Forecast.drain_public_ai_phase(s,8)
	check(drained.complete and drained.plans.map(func(p):return int(p.slot))==[8,9,8,40],"dynamic slot queue reinserts renewed lower slot")
	# Row-major timers: low3 does not explode immediately upon becoming2.
	b=fixture();hero=unit(b,0,0,Vector2i(1,1));b.mines=[{"tile":Vector2i(8,8),"mine":b.data.mines[0],"mine_id":0,"code":20,"low":3,"owner_side":"player"}];s=shadow(b)
	Forecast.drain_public_ai_phase(s);Forecast.advance_public_round(s)
	check(s.mines.size()==1 and s.mines[0].low==2 and s.mine_events.is_empty(),"low3 decreases to2 without same-scan detonation")
	Forecast.drain_public_ai_phase(s);Forecast.advance_public_round(s)
	check(s.mines.is_empty() and s.mine_events.size()==1,"low2 detonates exactly next scan")
	# First two ordinary friendly losses reduce hero, third does not. Throw
	# uses the original preincrement loss check, i.e. also the third casualty.
	for item_order in [false,true]:
		b=fixture();hero=unit(b,0,0,Vector2i(1,1));hero.data.level=6;s=shadow(b)
		for i in range(1,4):
			ally=unit(s,i,0,Vector2i(i+1,1));Forecast.record_death(s,ally,item_order)
		check(s.stats.losses==3 and s.unit_by_slot(0).data.level==(3 if item_order else 4),"original pre/postincrement penalty "+str(item_order))
	# Mine death differential includes shared XP, correct denominator and no loot.
	b=fixture();hero=unit(b,0,0,Vector2i(1,1));hero.data.xp=95;ally=unit(b,7,0,Vector2i(2,1));enemy=unit(b,40,1,Vector2i(8,8));enemy.hp=1
	b.mines=[{"tile":Vector2i(8,8),"mine":b.data.mines[0],"mine_id":0,"code":20,"low":2,"owner_side":"player"}];s=shadow(b)
	Forecast.detonate(s,Vector2i(8,8));await b._detonate_mines(Vector2i(8,8))
	same_numbers(hero,s.unit_by_slot(0),"mine XP hero");same_numbers(ally,s.unit_by_slot(7),"mine XP ally")
	check(s.stats.losses==b.stats.losses and s.stats.kills==b.stats.kills and s.mines.is_empty(),"mine deaths and removal match production")
	check(s.stats.get("kills_by_mine",0)==b.stats.get("kills_by_mine",0) and s.stats.xp==b.stats.xp,"mine subtype/XP stats match production")
	# Attack and thrown-item multi-target differential: frozen attack/range,
	# per-victim XP and retirement, followed by original single consumption.
	for kind in ["attack","item"]:
		b=fixture();hero=unit(b,0,0,Vector2i(5,5));hero.data.xp=98;hero.direction=0
		var v1=unit(b,40,1,Vector2i(6,5));var v2=unit(b,41,2,Vector2i(7,5));v1.hp=1;v2.hp=1
		var mask:Array=[]
		for row in range(7):mask.append([0,0,0,0,0,0,0])
		mask[3][3]=100
		# Attack turns east, but throw retains north. Both fixtures must really
		# hit BOTH victims, not compare the untouched second one and pass.
		if kind=="attack":mask[2][3]=100
		else:mask[3][4]=100
		var apply:int=Rules.attack_apply(int(b.unit_class(hero).apply),hero.attack_count) if kind=="attack" else int(b.data.items["41"].apply_fw)
		b.data.apply_ranges[str(apply)]=mask;hero.item_slots=[42,33,0,0,0,0,0,0]
		s=shadow(b);var su=s.unit_by_slot(0);var sv1=s.unit_by_slot(40);var sv2=s.unit_by_slot(41)
		var applied:Dictionary=Forecast.apply_action(s,su,action(kind,Vector2i(6,5),{"item":41}))
		if kind=="attack":
			await b._resolve_attack_at(hero,Vector2i(6,5),b._face_target(hero,Vector2i(6,5)))
		else:
			b.selected=hero;b.active_item_id=41;await b._execute_item_at(Vector2i(6,5))
		check(applied.complete,"multi-target "+kind+" accepted")
		check(not v1.alive and not v2.alive and not sv1.alive and not sv2.alive,"both targets really retired "+kind)
		same_numbers(hero,su,kind+" actor");same_numbers(v1,sv1,kind+" victim1");same_numbers(v2,sv2,kind+" victim2")
		check(s.stats.kills==b.stats.kills,"multi-target "+kind+" kill stats")
		check(s.stats.get("kills_by_gun",0)==b.stats.get("kills_by_gun",0) and s.stats.xp==b.stats.xp,"multi-target "+kind+" subtype/XP stats")
	# Recovery happens before timed blast; adjacent chained low3 is removed,
	# not counted down again or resurrected during the row-major scan.
	b=fixture();hero=unit(b,0,0,Vector2i(5,5));hero.hp=1
	b.data.terrain_modifiers[0][3]=50
	var mine:Dictionary=b.data.mines[0].duplicate(true);mine.weili=40;mine.apply_fw=999;mine.shiqi_or_tili=0
	var area:Array=[]
	for row in range(7):area.append([0,0,0,0,0,0,0])
	area[3][3]=100;area[3][4]=100;b.data.apply_ranges["999"]=area
	b.mines=[{"tile":Vector2i(5,5),"mine":mine,"mine_id":0,"code":20,"low":2,"owner_side":"player"},
		{"tile":Vector2i(6,5),"mine":mine,"mine_id":0,"code":20,"low":3,"owner_side":"player"}]
	s=shadow(b);Forecast.drain_public_ai_phase(s);Forecast.advance_public_round(s)
	await b._round_maintenance()
	check(s.unit_by_slot(0).hp==11 and hero.hp==11,"public recovery before timed blast matches production")
	check(s.mines.is_empty() and b.mines.is_empty() and s.mine_events.size()==2,"row-major chain removes later low3 exactly once")
	# Dead critical actors cannot be brought through another round by reset.
	b=fixture();hero=unit(b,0,0,Vector2i(5,5));hero.hp=1;enemy=unit(b,40,1,Vector2i(5,4));enemy.behavior=1
	two=Forecast.evaluate_two_phases(b,[],[])
	check(not two.complete and two.status=="terminal" and two.phases.size()==1,"critical death stops at first phase, never resurrects")
	for boundary in ["dead_hero","dead_protected","finished","enemy_phase","busy","action_pending","unplaced_hero"]:
		b=fixture();hero=unit(b,0,0,Vector2i(1,1));ally=unit(b,7,0,Vector2i(2,1));ally.protected=true
		match boundary:
			"dead_hero":hero.alive=false
			"dead_protected":ally.alive=false
			"finished":b.finished_flag=true
			"enemy_phase":b.phase="enemy"
			"busy":b.busy=true
			"action_pending":b.action_resolution_depth=1
			"unplaced_hero":hero.placed=false
		two=Forecast.evaluate_two_phases(b,[],[])
		check(not two.complete and two.status in ["terminal","invalid","unsupported"],"source entry rejects "+boundary)
	b=fixture();hero=unit(b,0,0,Vector2i(1,1));ally=unit(b,7,0,Vector2i(2,1));ally.unit_name="public-protect";ally.protected=false;b.level["protect"]=["public-protect"]
	s=shadow(b);check(s.unit_by_slot(7).protected,"public objective protection copied without future scripts")
	ally.alive=false;two=Forecast.evaluate_two_phases(b,[],[])
	check(not two.complete and two.status=="terminal","dead mission-named protected actor not omitted as safe")
	# Clean disposable nodes, including all exited shadows; never owned live game.
	for board in boards:board.free()
	boards.clear();await process_frame
	print("PUBLIC_ROUND_FORECAST checks=",checks," failures=",failures)
	quit(1 if failures else 0)
