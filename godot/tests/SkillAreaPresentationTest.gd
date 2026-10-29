extends SceneTree
# Synthetic, isolated selection/resolver regression. Never loads or writes saves.
# Geometry oracle inverse-rotates raw data; outcome checks exercise the resolver,
# not the production preview/chance/utility helpers as their own oracle.
const State=preload("res://scripts/m2/GameState.gd")
const Builder=preload("res://scripts/m4/LevelBuilder.gd")
class Observer extends RefCounted:
	var status_text:=""
	var ticks:=0
	func on_tick() -> void:ticks+=1
	func on_unit_moved(_u) -> void:pass
	func on_unit_died(_u) -> void:pass
	func check_end() -> bool:return false
var checks:=0
var failures:=0
var geometry_cases:=0
var probability_cases:=0
var resolver_cases:=0
var b
var hero
var target
var victims:Array=[]
func _initialize() -> void:call_deferred("run")
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		if failures<=30:push_error("SKILL_AREA_FAIL "+label)
func rank_for(count:int) -> int:
	var rank:=0
	for threshold in [1,10,25,45,70,100,135,175,225,300]:
		if count>=threshold:rank+=1
	return rank
func direction_between(from:Vector2i,to:Vector2i) -> int:
	var dx:=to.x-from.x;var dy:=to.y-from.y
	if dx==0 and dy==0:return -1
	if absi(dx)>absi(dy):return 3 if dx>0 else 2
	return 1 if dy>0 else 0
func landing_offset(sid:int,d:int,furthest:=false) -> Vector2i:
	var matrix:Array=b.data.select_ranges[str(b.data.skills[sid].select_fw)]
	var best:=Vector2i.ZERO;var score:=-1 if furthest else 999
	for y in range(9):
		for x in range(9):
			var offset:=Vector2i(x-4,y-4)
			if int(matrix[y][x])!=1 or direction_between(Vector2i.ZERO,offset)!=d:continue
			# Prefer a cardinal aim so an edge fixture keeps its caster in bounds.
			var distance:=absi(offset.x)+absi(offset.y)
			if not furthest and offset.x!=0 and offset.y!=0:distance+=20
			if (furthest and distance>score) or (not furthest and distance<score):best=offset;score=distance
	return best
func oracle(sid:int,count:int,center:Vector2i,d:int) -> Dictionary:
	var index:int=int(b.data.skills[sid].apply_fw)+ceili(float(rank_for(count))/3.0)-1
	var matrix:Array=b.data.apply_ranges[str(index)]
	var result:Dictionary={}
	for y in range(maxi(0,center.y-3),mini(b.map_h,center.y+4)):
		for x in range(maxi(0,center.x-3),mini(b.map_w,center.x+4)):
			var dx:=x-center.x;var dy:=y-center.y;var sx:=dx;var sy:=dy
			match d:
				1:sx=-dx;sy=-dy
				2:sx=-dy;sy=dx
				3:sx=dy;sy=-dx
			var pct:int=int(matrix[sy+3][sx+3])
			if pct>0:result[Vector2i(x,y)]=pct
	return result
func geometry(cells:Array) -> Dictionary:
	var result:Dictionary={};var previous:=Vector2i(-1,-1)
	for cell in cells:
		check(cell.has_all(["tile","pct","chance","effective"]),"preview schema")
		check(cell.tile.y>previous.y or (cell.tile.y==previous.y and cell.tile.x>previous.x),"row-major unique cells")
		check(cell.chance is int and int(cell.chance)>=0 and int(cell.chance)<=100,"integer probability 0..100")
		check(cell.effective is bool and cell.effective==(cell.chance>0),"effective iff probability positive")
		result[cell.tile]=int(cell.pct);previous=cell.tile
	return result
func cell_at(tile:Vector2i) -> Dictionary:
	for cell in b.skill_preview_cells():
		if cell.tile==tile:return cell
	return {}
func chance(expected:int,label:String) -> void:
	var cell:=cell_at(b.hover_tile)
	check(not cell.is_empty(),label+" has landing cell")
	if not cell.is_empty():check(cell.chance==expected and cell.effective==(expected>0),label+" probability="+str(expected))
	probability_cases+=1
func reset_actor(pos:=Vector2i(10,10)) -> void:
	b._close_context_menu();b._close_action_panel()
	b.busy=false;b.finished_flag=false;b._finishing=false;b.phase="player";b.mode="idle"
	b.progress_fx_active=false;b.action_resolution_depth=0;b.active_skill={};b.active_skill_id=-1
	hero.set_tile(pos.x,pos.y);hero.alive=true;hero.placed=true;hero.acted=false;hero.moved=false
	hero.data.faction=0;hero.side="player";hero.control=true;hero.auto=false;hero.data.zhili=100
	hero.data.level=99;hero.data.xp=0;hero.direction=3;hero.display_action_lock=false
	hero.hp=10000;hero.max_hp=10000;hero.morale=100;hero.integrity=100;hero.defense_integrity=100
	hero.item_slots=[0,0,0,0,0,0,0,0]
	b.selected=hero
	for victim in victims:victim.alive=false;victim.placed=true
func reset_target(sid:int,tile:Vector2i) -> void:
	target.set_tile(tile.x,tile.y);target.alive=true;target.placed=true;target.bingzhong=1
	target.data.faction=0 if sid in [0,1,2,12] else 1
	target.side="enemy" # Exact faction, deliberately NOT the presentation side.
	target.data.zhili=100;target.data.level=10;target.hp=10000;target.max_hp=20000
	target.morale=50;target.integrity=80;target.defense_integrity=80
	target.acted=sid==12;target.moved=sid==12;target.item_slots=[2,3,0,0,0,0,0,0]
	target.data.erase("last_attacker_slot")
func aim_at_target(sid:int,count:=1) -> void:
	reset_actor()
	var tile:=Vector2i(hero.x,hero.y)+landing_offset(sid,0)
	reset_target(sid,tile);hero.skill_counts[b.SKILL_KEYS[sid]]=count
	b._choose_skill(sid);b.hover_tile=tile
func state(u) -> Array:
	return [u.hp,u.max_hp,u.morale,u.integrity,u.defense_integrity,u.acted,u.moved,int(u.data.get("level",1)),u.item_slots.duplicate()]
func run() -> void:
	var m2:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/m2.json"))
	var m4:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/m4.json"))
	var gs=State.new();gs.new_game(m2);gs.setup_m4(m4)
	b=load("res://scripts/Battle.gd").new();root.add_child(b)
	b.setup(m4,Builder.build(m4,m2,0,[gs.protagonist_member()]),load("res://assets/font/hzk16.fnt"),gs.battle_context())
	b.set_process(false);b.fast_sim=true;b.animations_enabled=false;b.sfx_enabled=false
	b.scenario=Observer.new();b.mines.clear();b.chests.clear()
	hero=b.unit_by_slot(0)
	for unit in b.units:
		if unit!=hero:unit.alive=false;unit.visible=false
	for i in range(81):
		victims.append(b._spawn_unit({"slot":40+i,"name":"策略测试","bingzhong":1,"side":"enemy","faction":1,"x":0,"y":0,"hp":10000,"max_hp":20000,"level":10,"zhili":100,"control":false}))
	target=victims[0]
	# All sixteen raw A masks, all rank boundaries, all facings, edge clipping.
	# No attack_apply (+1) anticipation is permitted for strategy practice.
	for sid in range(16):
		for count in [1,9,10,24,25,44,45,69,70,99,100,134,135,174,175,224,225,299,300]:
			for d in range(4):
				for clipped in [false,true]:
					var center:=Vector2i(10,10)
					if clipped:center=Vector2i(0 if d in [0,2] else b.map_w-1,0 if d in [0,2] else b.map_h-1)
					reset_actor(center-landing_offset(sid,d));hero.skill_counts[b.SKILL_KEYS[sid]]=count
					b._choose_skill(sid);b.hover_tile=center
					check(geometry(b.skill_preview_cells())==oracle(sid,count,center,d),"geometry %d/%d/%d/clip%s"%[sid,count,d,clipped])
					geometry_cases+=1
	for sid in [0,1,2]:
		reset_actor();hero.skill_counts[b.SKILL_KEYS[sid]]=300;b._choose_skill(sid);b.hover_tile=Vector2i(hero.x,hero.y)
		check(geometry(b.skill_preview_cells())==oracle(sid,300,b.hover_tile,-1),"support self landing is unrotated")
	# Probabilities are hit chances, NOT the A-template damage percentages.
	for sid in range(16):
		aim_at_target(sid);chance(100 if sid in [0,1,2,15] else (31 if sid==9 else 30),"equal intelligence sid%d"%sid)
		target.data.zhili=0;chance(100,"upper cap sid%d"%sid)
		target.data.zhili=200;chance(100 if sid in [0,1,2,15] else (1 if sid==9 else 0),"lower cap sid%d"%sid)
	for count in [1,9,10,24,25,44,45,134,135,299,300]:
		aim_at_target(9,count);chance(30+rank_for(count),"plunder practice %d"%count)
		target.data.zhili=200;chance(rank_for(count),"plunder adds rank AFTER lower clamp %d"%count)
	reset_actor(Vector2i(10,12));hero.skill_counts[b.SKILL_KEYS[3]]=300
	grid_targets(3,Vector2i(10,10))
	for v in victims:v.data.zhili=100
	b._choose_skill(3);b.hover_tile=Vector2i(10,10)
	var has_partial:=false
	for cell in b.skill_preview_cells():
		var occupant=b._unit_at(cell.tile)
		if occupant!=null and int(occupant.data.faction)!=0:
			check(cell.chance==30,"partial intensity never scales success probability")
			if int(cell.pct)<100:has_partial=true
	check(has_partial,"partial intensity probability fixture is meaningful")
	# Target eligibility: wrong/exact/third faction, holes and nonoccupants.
	for sid in range(16):
		aim_at_target(sid);target.data.zhili=0
		for faction in [0,1,2]:
			target.data.faction=faction
			chance(100 if (faction==0)==(sid in [0,1,2,12]) else 0,"faction %d sid%d"%[faction,sid])
		target.alive=false;chance(0,"dead not target sid%d"%sid)
		target.alive=true;target.placed=false;chance(0,"unplaced not target sid%d"%sid)
		target.placed=true;target.set_tile(0,0);chance(0,"empty not target sid%d"%sid)
	await utility_cases()
	await gating_cases()
	await resolver_checks()
	b.queue_free();await process_frame;await create_timer(0.15).timeout
	print("SKILL_AREA_PRESENTATION checks=",checks," failures=",failures," geometry_cases=",geometry_cases," probability_cases=",probability_cases," resolver_cases=",resolver_cases)
	if failures==0:print("SKILL_AREA_PRESENTATION_OK")
	quit(1 if failures else 0)
func utility_cases() -> void:
	for sid in [0,1,2]:
		aim_at_target(sid);target.hp=target.max_hp;target.morale=100;chance(0,"full support sid%d"%sid)
		target.hp-=100;chance(0 if sid==1 else 100,"only HP missing sid%d"%sid)
		target.hp=target.max_hp;target.morale=50;chance(0 if sid==0 else 100,"only morale missing sid%d"%sid)
	for sid in [3,4,5,6,13,14,15]:
		aim_at_target(sid);hero.data.zhili=0;target.data.zhili=0;chance(0,"rounded zero effect sid%d"%sid)
	for sid in [3,4,5]:
		aim_at_target(sid);target.data.zhili=0
		var terrain_id:int=b.terrain[b.hover_tile.y*b.map_w+b.hover_tile.x]
		var column:=0 if sid==3 else 1;var old:int=b.data.terrain_modifiers[terrain_id][column]
		b.data.terrain_modifiers[terrain_id][column]=-100;chance(0,"terrain cancels damage sid%d"%sid)
		b.data.terrain_modifiers[terrain_id][column]=old
	aim_at_target(6);target.morale=0;chance(0,"intimidate no morale")
	aim_at_target(7);target.defense_integrity=20;chance(0,"harass at floor");target.defense_integrity=21;chance(30,"harass above floor")
	aim_at_target(8);target.integrity=50;chance(0,"sabotage at floor");target.integrity=51;chance(30,"sabotage above floor")
	aim_at_target(9);target.item_slots.fill(0);chance(0,"plunder empty inventory")
	target.item_slots[7]=3;hero.item_slots.fill(2);chance(31,"plunder full caster still produces loot")
	aim_at_target(10);target.data.level=1;target.max_hp=int(b.data.unit_types[1].tili);target.hp=target.max_hp;chance(0,"counterintelligence level1 unchanged")
	target.max_hp+=1;chance(30,"counterintelligence recalculates inconsistent HP cap")
	aim_at_target(11);target.acted=true;target.moved=true;chance(0,"feint already fully spent")
	target.moved=false;chance(30,"feint still consumes movement")
	for acted in [false,true]:
		for moved in [false,true]:
			aim_at_target(12);target.acted=acted;target.moved=moved;target.integrity=100;target.defense_integrity=100
			chance(30 if acted or moved else 0,"supervise action flags %s/%s"%[acted,moved])
	aim_at_target(12);target.acted=false;target.moved=false;target.integrity=100;target.defense_integrity=80;chance(30,"supervise repairs only")
	target.data.zhili=0;target.bingzhong=45;chance(0,"supervise unit45 immune even guaranteed roll")
func gating_cases() -> void:
	aim_at_target(3,134)
	var saved_rng:int=b.rng_state;var saved_direction:int=hero.direction;var saved_counts:Dictionary=hero.skill_counts.duplicate(true)
	var saved_hero:Array=state(hero);var saved_target:Array=state(target)
	for i in range(30):b.skill_preview_cells()
	check(b.rng_state==saved_rng and hero.direction==saved_direction and hero.skill_counts==saved_counts,"hover consumes no RNG/facing/practice")
	check(state(hero)==saved_hero and state(target)==saved_target,"hover mutates no actor/victim state")
	var legal:Vector2i=b.hover_tile
	var input_mask:PackedByteArray=b.native_dark_mask.duplicate()
	b._on_map_click(Vector2i(0,0))
	check(b.mode=="skill" and not hero.acted and b.native_dark_mask==input_mask and b.rng_state==saved_rng,"illegal dark click preserves strategy mode/range/action/RNG")
	b.hover_tile=Vector2i(-1,0);check(b.skill_preview_cells().is_empty(),"out-of-bounds hover")
	b.hover_tile=Vector2i(hero.x,hero.y);check(b.skill_preview_cells().is_empty(),"non-support blind self cell")
	b.hover_tile=legal;var mask:PackedByteArray=b.native_dark_mask.duplicate();b.native_dark_mask[legal.y*b.map_w+legal.x]=1
	check(b.skill_preview_cells().is_empty(),"native mask gate, not only attack_tiles membership");b.native_dark_mask=mask
	b.attack_tiles.erase(legal);check(b.skill_preview_cells().is_empty(),"legal landing dictionary gate");b.attack_tiles[legal]=target
	b.busy=true;check(b.skill_preview_cells().is_empty(),"busy gate");b.busy=false
	b.phase="enemy";check(b.skill_preview_cells().is_empty(),"phase gate");b.phase="player"
	b.finished_flag=true;check(b.skill_preview_cells().is_empty(),"finished gate");b.finished_flag=false
	b.progress_fx_active=true;check(b.skill_preview_cells().is_empty(),"progress FX gate");b.progress_fx_active=false
	hero.acted=true;check(b.skill_preview_cells().is_empty(),"spent actor gate");hero.acted=false
	hero.alive=false;check(b.skill_preview_cells().is_empty(),"dead actor gate");hero.alive=true
	b.action_panel=Control.new();b.add_child(b.action_panel);check(b.skill_preview_cells().is_empty(),"action panel modal gate");b._close_action_panel()
	b.context_menu=Control.new();b.add_child(b.context_menu);check(b.skill_preview_cells().is_empty(),"context menu modal gate");b._close_context_menu()
	b.mode="attack";check(b.skill_preview_cells().is_empty(),"attack mode has no stale strategy preview");b.mode="skill"
	b.active_skill={};check(b.skill_preview_cells().is_empty(),"missing active strategy gate");b.active_skill=b.data.skills[3]
	b.active_skill_id=-1;check(b.skill_preview_cells().is_empty(),"missing strategy id gate");b.active_skill_id=3
	b.selected=null;check(b.skill_preview_cells().is_empty(),"no actor gate");b.selected=hero
	check(not b.skill_preview_cells().is_empty(),"fixture remains valid after gates")
	b._choose_skill(0);b.hover_tile=legal;check(geometry(b.skill_preview_cells())==oracle(0,int(hero.skill_counts.buji),legal,0),"switch replaces old strategy A mask")
	b._cancel();check(b.skill_preview_cells().is_empty() and b.active_skill_id==-1,"cancel clears preview and strategy")
	b._close_context_menu()
	# Empty landing remains a legal native action, not an enemy-only selector.
	reset_actor();hero.skill_counts[b.SKILL_KEYS[3]]=134;b._choose_skill(3)
	b.hover_tile=Vector2i(10,9)
	check(not b.skill_preview_cells().is_empty(),"legal empty landing still exposes A mask")
	for cell in b.skill_preview_cells():check(cell.chance==0,"empty/friendly offensive area is ineffective")
	b._on_map_click(b.hover_tile)
	while b.busy or b.action_resolution_depth>0:await process_frame
	check(hero.acted and b.selected==null and hero.skill_counts[b.SKILL_KEYS[3]]==134,"legal empty map click resolves action without imaginary practice")
func grid_targets(sid:int,center:Vector2i) -> void:
	for i in range(victims.size()):
		var v=victims[i];var tile:=center+Vector2i(i%9-4,i/9-4)
		v.set_tile(tile.x,tile.y);v.alive=b._in_bounds(tile) and tile!=Vector2i(hero.x,hero.y);v.placed=true
		v.data.faction=(0 if sid in [0,1,2,12] else 1) if i==40 else i%3
		v.side="enemy";v.control=false;v.bingzhong=1;v.data.zhili=0;v.data.level=10
		v.hp=200000;v.max_hp=400000;v.morale=50;v.integrity=80;v.defense_integrity=80
		v.acted=sid==12;v.moved=sid==12;v.item_slots=[2,3,0,0,0,0,0,0]
		v.data.erase("last_attacker_slot")
func expected_state(v,sid:int,count:int,pct:int) -> Array:
	var out:Array=state(v)
	# Independent arithmetic from shipped skill parameters and explicit rank.
	var p1:int=int(b.data.skills[sid].para1);var p2:int=int(b.data.skills[sid].para2)
	var intelligence:int=int(hero.data.zhili)
	var effect1:int=((p1*intelligence/100)*(rank_for(count)+7))>>3
	var effect2:int=((p2*intelligence/100)*(rank_for(count)+7))>>3
	var e1:int=effect1*pct/100;var e2:int=effect2*pct/100
	match sid:
		0:out[0]=mini(int(out[1]),int(out[0])+e1)
		1:out[2]=mini(100,int(out[2])+e2)
		2:out[0]=mini(int(out[1]),int(out[0])+e1);out[2]=mini(100,int(out[2])+e2)
		3,4,5,13,14,15:
			var modifier:=0
			if sid in [3,4,5]:modifier=int(b.data.terrain_modifiers[b.terrain[v.y*b.map_w+v.x]][0 if sid==3 else 1])
			out[0]=maxi(0,int(out[0])-maxi(0,e1*(100+modifier)/100))
			if sid==14:out[2]=maxi(0,int(out[2])-e2)
		6:out[2]=maxi(0,int(out[2])-e2)
		7:out[4]=maxi(20,int(out[4])*7/10)
		8:out[3]=maxi(50,int(out[3])*7/10)
		9:
			for i in range(out[8].size()):
				if int(out[8][i])>0:out[8][i]=0;break
		10:
			out[7]=maxi(1,int(out[7])-1)
			out[1]=maxi(1,int(b.data.unit_types[v.bingzhong].tili)+(int(out[7])-1)*int(b.data.unit_types[v.bingzhong].tili_plus))
			out[0]=mini(int(out[0]),int(out[1]))
		11:out[5]=true;out[6]=true
		12:out[5]=false;out[6]=false;out[3]=mini(100,int(out[3])+20);out[4]=mini(100,int(out[4])+20)
	return out
func resolver_checks() -> void:
	# Every strategy exercises real _execute_skill_at at 100% success. Sparse
	# factions 0/1/2, occupied/outside A, and practice expansions are all checked.
	var cases:Array=[]
	for sid in range(16):
		for count in [1,300]:cases.append([sid,count,0])
	for sid in [0,2,3,4,5,12,14,15]:
		for count in [44,134,299]:
			for d in range(4):cases.append([sid,count,d])
	for row in cases:
		var sid:int=row[0];var count:int=row[1];var d:int=row[2];var center:=Vector2i(10,10)
		reset_actor(center-landing_offset(sid,d,true));hero.skill_counts[b.SKILL_KEYS[sid]]=count
		grid_targets(sid,center);b._choose_skill(sid);b.hover_tile=center
		var area:=oracle(sid,count,center,d)
		check(geometry(b.skill_preview_cells())==area,"resolver starts with independent area")
		var expected:Array=[];var changed:=0
		for v in victims:
			var tile:=Vector2i(v.x,v.y);var before:Array=state(v);var after:Array=before
			var valid:bool=v.alive and area.has(tile) and ((int(v.data.faction)==0)==(sid in [0,1,2,12]))
			if valid:after=expected_state(v,sid,count,int(area[tile]))
			expected.append(after)
			if valid and before!=after:changed+=1
			if area.has(tile) and v.alive:
				var cell:=cell_at(tile)
				check(not cell.is_empty() and int(cell.chance)==(100 if valid and before!=after else 0),"predicted deterministic victim %d sid%d"%[v.slot,sid])
		check(changed>0,"resolver fixture has meaningful target sid%d"%sid)
		var tick_before:int=b.scenario.ticks
		await b._execute_skill_at(center)
		for i in range(victims.size()):check(state(victims[i])==expected[i],"actual outcome sid%d/count%d/dir%d/victim%d"%[sid,count,d,i])
		check(hero.acted and not b.busy and b.action_resolution_depth==0,"resolved skill releases lock and consumes action")
		check(b.scenario.ticks==tick_before+1,"resolved skill calls synchronous scenario hook")
		check(b.skill_preview_cells().is_empty(),"completed action clears preview")
		resolver_cases+=1
	# Zero hit chance must really fail, regardless of random seed. Keep caster
	# intelligence nonzero so these are genuine failed rolls, not zero damage.
	for sid in [3,4,5,6,7,8,10,11,12,13,14]:
		for seed in [1,2147483647,4294967295]:
			aim_at_target(sid);hero.data.zhili=50;target.data.zhili=100;b.rng_state=seed
			chance(0,"real zero-percent fixture sid%d"%sid)
			var before:Array=state(target);var count_before:int=hero.skill_counts[b.SKILL_KEYS[sid]]
			await b._execute_skill_at(b.hover_tile)
			check(state(target)==before and hero.skill_counts[b.SKILL_KEYS[sid]]==count_before,"real zero percent never affects sid%d"%sid)
			check(b.rng_state==((seed*214013+2531011)&0xffffffff),"failed random branch retains one legacy roll")
			resolver_cases+=1
	# Intermediate probability oracle uses an independently advanced CRT state
	# and actual morale outcomes: both successful and failed 30% branches occur.
	var successes:=0;var misses:=0
	for seed in [1,2,3,4,5,6,7,8,9,10,20,30,40,50,60,70]:
		aim_at_target(6);b.rng_state=seed;chance(30,"real 30-percent fixture")
		var next_seed:int=(seed*214013+2531011)&0xffffffff
		var succeeds:bool=(((next_seed>>16)&0x7fff)%100)<30
		await b._execute_skill_at(b.hover_tile)
		check(target.morale==(30 if succeeds else 50),"30%% preview agrees with actual seeded roll %d"%seed)
		check(b.rng_state==next_seed,"30% resolver consumes exactly one random roll")
		if succeeds:successes+=1
		else:misses+=1
		resolver_cases+=1
	check(successes>0 and misses>0,"intermediate chance exercises both branches")
	# Plunder's rank uplift survives an unfavorable intelligence difference in
	# both the preview and actual seeded branches, rather than being clamped out.
	for seed in [1,20,50]:
		aim_at_target(9,300);target.data.zhili=200;b.rng_state=seed;chance(10,"real plunder rank-only hit chance")
		var next_seed:int=(seed*214013+2531011)&0xffffffff
		var succeeds:bool=(((next_seed>>16)&0x7fff)%100)<10
		await b._execute_skill_at(b.hover_tile)
		check(target.item_slots[0]==(0 if succeeds else 2),"plunder rank probability agrees with actual item transfer")
		check(hero.item_slots[0]==(2 if succeeds else 0),"plunder caster receives item only on success")
		check(b.rng_state==next_seed,"plunder preserves one legacy random roll")
		resolver_cases+=1
	# A fully repaired support and immune troop must show 0% and remain inert.
	for sid in [0,1,2,12]:
		aim_at_target(sid);target.data.zhili=0
		if sid==12:target.bingzhong=45
		else:target.hp=target.max_hp;target.morale=100
		chance(0,"real no-effect/immune fixture sid%d"%sid)
		var before:Array=state(target)
		await b._execute_skill_at(b.hover_tile)
		check(state(target)==before,"zero effective probability is genuinely unchanged sid%d"%sid)
		resolver_cases+=1
