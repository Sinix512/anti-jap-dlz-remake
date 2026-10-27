extends RefCounted
# Isolated planning tool, NOT a production resolver or an original-runtime oracle.
# Two public conditional phases; no RNG reads, Scenario, future scripts or loot.
# Strict calls reject unknown RNG. Explicit calls consume named conditional
# outcomes only; neither mode reads or advances the original random stream.
const Base=preload("res://tests/helpers/TacticalForecast.gd")
const Rules=preload("res://scripts/battle/CombatRules.gd")
const Slots=preload("res://scripts/battle/InventorySlots.gd")
const Unit=preload("res://scripts/BattleUnit.gd")

class PublicBoard extends Base.ShadowBoard:
	# Only observed public actors; no predicted spawns/slot reuse in this model.
	var forecast_meta:Dictionary={"phase":"player","generation":0,"dispatch":0,"casts":{}}

static func result(status:String,reason:="") -> Dictionary:
	return {"status":status,"reason":reason,"complete":status=="complete"}

static func clone_public_board(source,known_mine_tiles:Array=[]):
	var b=PublicBoard.new()
	# No shared mutable dictionaries, terrain buffers, context or scenario.
	for field in ["unit_types","terrain_modifiers","items","mines","skills","select_ranges","apply_ranges","unit_move","item_valid","mine_terrain"]:
		var value=source.data.get(field)
		if value!=null:b.data[field]=value.duplicate(true) if value is Dictionary or value is Array else value
	b.level={"index":source.level.get("index",-1),"difficulty_setting":source.level.get("difficulty_setting",1)}
	b.terrain=source.terrain.duplicate();b.map_w=source.map_w;b.map_h=source.map_h
	b.turn=source.turn;b.stats=source.stats.duplicate(true)
	b.battle_context={} # never copy campaign/global/hidden resource state
	for record in source.mines:
		if record.get("owner_side","")=="player" or known_mine_tiles.has(record.tile):
			b.mines.append(record.duplicate(true))
	for live in source.units:
		var u=Unit.new();u.data=live.data.duplicate(true)
		for field in Unit.STATE_FIELDS:
			var value=live.get(field)
			u.set(field,value.duplicate(true) if value is Dictionary or value is Array else value)
		u.protected=source._bot_is_protected(live)
		b.add_child(u);b.units.append(u)
		if u.side=="player":b.player_units.append(u)
		else:b.enemy_units.append(u)
	b.refresh_occupancy()
	return b

# Branch clones are deliberately a separate API: never re-filter mines that
# were already admitted at the public boundary, never drop casualty tombstones.
static func clone_branch(source):
	assert(source is PublicBoard, "branch source must already be a public shadow")
	var known:Array=[]
	for record in source.mines:known.append(record.tile)
	var b=clone_public_board(source,known)
	b.forecast_meta=source.forecast_meta.duplicate(true)
	b.mine_events=source.mine_events.duplicate(true)
	return b

static func _action_result(status:String,event:Dictionary,opportunities:Array=[],reason:="") -> Dictionary:
	var out:=result(status,reason)
	out["event"]=event;out["opportunities"]=opportunities
	return out

static func _check_outcomes(opportunities:Array,outcomes:Dictionary,mode:String) -> Dictionary:
	var required:Dictionary={}
	for opportunity in opportunities:
		if opportunity.requires_outcome:required[opportunity.key]=true
	for key in outcomes:
		if not (key is String) or not required.has(key) or not (outcomes[key] is bool):
			return result("invalid","extra, stale, deterministic, immune or non-boolean outcome")
	if required.size()!=outcomes.size():
		return result("needs_outcomes" if mode=="discover" else ("unsupported" if mode=="strict" else "invalid"),"explicit skill outcomes required")
	return result("complete")

# The discovery and preflight run ONLY on disposable private branches. Even a
# bad mapping discovered after movement cannot partially alter the caller.
static func inspect_action_outcomes(b,u,a:Dictionary) -> Dictionary:
	if not (b is PublicBoard) or u==null or not b.units.has(u):return result("invalid","not an owned public actor")
	var probe=clone_branch(b)
	var out:=_apply_action(probe,probe.unit_by_slot(u.slot),a,{},"discover")
	probe.free();return out

static func _transaction_action(b,u,a:Dictionary,outcomes:Dictionary,mode:String) -> Dictionary:
	if not (b is PublicBoard) or u==null or not b.units.has(u):return result("invalid","not an owned public actor")
	var probe=clone_branch(b)
	var preflight:=_apply_action(probe,probe.unit_by_slot(u.slot),a,outcomes,mode)
	probe.free()
	if not preflight.complete:return preflight
	return _apply_action(b,u,a,outcomes,mode)

static func apply_action_with_outcomes(b,u,a:Dictionary,outcomes:Dictionary) -> Dictionary:
	return _transaction_action(b,u,a,outcomes,"explicit")

static func resize_hp(b,u) -> void:
	var cls:Dictionary=b.unit_class(u)
	u.max_hp=maxi(1,int(cls.get("tili",50))+(int(u.data.get("level",1))-1)*int(cls.get("tili_plus",0)))
	u.hp=mini(u.hp,u.max_hp)

static func gain_xp(b,u,amount:int) -> void:
	if amount<=0:return
	u.gained_xp+=amount
	if u.side=="player":b.stats["xp"]=int(b.stats.get("xp",0))+amount
	var xp:int=int(u.data.get("xp",0))+amount
	u.data.xp=xp%100;u.data.level=mini(99,int(u.data.get("level",1))+xp/100)
	resize_hp(b,u)

static func loss_penalty(b,u,item_order:bool) -> void:
	if u.side!="player" or u.slot>=32 or (u.slot==0 and not item_order):return
	var difficulty:int=int(b.level.get("difficulty_setting",1))
	if difficulty!=2 and not (difficulty==1 and int(b.stats.get("losses",0))<3):return
	for hero in b.units:
		if hero.slot==0:
			hero.data.level=maxi(1,int(hero.data.get("level",1))-1);resize_hp(b,hero)

static func record_death(b,u,item_order:=false) -> void:
	u.alive=false
	if item_order:loss_penalty(b,u,true)
	var key:String="losses" if u.side=="player" else "kills"
	b.stats[key]=int(b.stats.get(key,0))+1
	if u.side!="player":
		var kill_kind:String="kills_by_mine" if u.last_damage_kind=="mine" else "kills_by_gun"
		b.stats[kill_kind]=int(b.stats.get(kill_kind,0))+1
	if not item_order:loss_penalty(b,u,false)
	b.refresh_occupancy()

static func validate_action(b,u,a:Dictionary) -> Dictionary:
	if u==null or not u.alive or not u.placed or u.acted:return result("invalid","actor unavailable")
	var kind:String=str(a.get("kind",""))
	if kind not in ["wait","move","attack","skill","item","mine"]:return result("unsupported","action "+kind)
	var origin:=Vector2i(u.x,u.y);var station:Vector2i=a.get("station",origin)
	if station!=origin and (u.moved or not b.compute_reachable(u).has(station)):
		return result("invalid","movement budget/range")
	# Validate landing range at proposed endpoint, then restore before real path.
	u.x=station.x;u.y=station.y;b.refresh_occupancy()
	var valid:=true;var unsupported:=""
	var target=b.unit_by_slot(int(a.get("target",-1)))
	var tile:Vector2i=a.get("tile",Vector2i(target.x,target.y) if target!=null else station)
	match kind:
		"attack":valid=b._select_tiles(u,u.select).has(tile)
		"skill":
			var sid:int=int(a.get("skill",-1))
			valid=sid>=0 and sid<16 and b._skill_count(u,sid)>0
			if sid==9:unsupported="plunder inventory branches"
			if valid:valid=b._skill_targets(u,b.data.skills[sid]).has(tile)
		"item":
			var iid:int=int(a.get("item",-1))
			valid=u.item_slots.has(iid+1) and b.data.items.has(str(iid))
			if iid<0 or (iid>=31 and iid not in range(41,57)):unsupported="item channel"
			if valid:valid=b._item_targets(u,b.data.items[str(iid)],"food" if iid<31 else "throw").has(tile)
		"mine":
			var code:int=int(a.get("mine",-1))
			if code<0 or code>=10:unsupported="non-contact mine placement"
			valid=u.mine_slots.has(code+1) and b._mine_place_tiles(u,code).has(tile)
	u.x=origin.x;u.y=origin.y;b.refresh_occupancy()
	if unsupported!="":return result("unsupported",unsupported)
	return result("complete") if valid else result("invalid","action target/inventory")

static func apply_action(b,u,a:Dictionary) -> Dictionary:
	return _transaction_action(b,u,a,{},"strict")

static func _apply_action(b,u,a:Dictionary,outcomes:Dictionary,mode:String) -> Dictionary:
	var valid:Dictionary=validate_action(b,u,a)
	if not valid.complete:return valid
	var event:Dictionary={"turn":b.turn,"phase":b.forecast_meta.phase,"generation":b.forecast_meta.generation,
		"dispatch":int(b.forecast_meta.dispatch)+1,"actor_slot":u.slot,"actor_incarnation":0,"cast":0,"interrupted":false}
	b.forecast_meta.dispatch=event.dispatch
	var origin:=Vector2i(u.x,u.y);var station:Vector2i=a.get("station",origin)
	if station!=origin:
		b.compute_reachable(u)
		for step in b._path_to(station,origin):
			u.direction=b._facing(Vector2i(u.x,u.y),step);u.x=step.x;u.y=step.y;u.moved=true;b.refresh_occupancy()
			var idx:int=b._mine_at(step)
			if idx<0:continue
			if int(u.bingzhong)==46:b.mines.remove_at(idx);continue
			if int(b.mines[idx].get("code",0))/10!=0:continue
			detonate(b,step,u.slot);u.acted=true;event.interrupted=true
			if not outcomes.is_empty():return _action_result("invalid",event,[],"interrupted before cast; unconsumed outcomes")
			return _action_result("complete",event)
	var kind:String=str(a.kind)
	if kind in ["wait","move"]:
		if not outcomes.is_empty():return _action_result("invalid",event,[],"no roll opportunities")
		u.acted=true;return _action_result("complete",event)
	var target=b.unit_by_slot(int(a.get("target",-1)))
	var tile:Vector2i=a.get("tile",Vector2i(target.x,target.y) if target!=null else station)
	if kind=="mine":
		if not outcomes.is_empty():return _action_result("invalid",event,[],"no roll opportunities")
		var code:int=int(a.mine);Slots.remove_id(u.mine_slots,code+1)
		b.mines.append({"tile":tile,"mine":b.data.mines[code],"mine_id":code,"code":code,"low":1,"owner_side":u.side})
		u.acted=true;return _action_result("complete",event)
	var sid:int=int(a.get("skill",-1));var iid:int=int(a.get("item",-1))
	var count:int=b._skill_count(u,sid);var definition:Dictionary={}
	var apply:=0;var e1:=0;var e2:=0
	var facing:int=b._facing(station,tile)
	if kind=="attack":apply=Rules.attack_apply(int(b.unit_class(u).get("apply",0)),u.attack_count)
	elif kind=="skill":
		definition=b.data.skills[sid];apply=Rules.skill_apply(int(definition.apply_fw),count)
		e1=Rules.skill_effect(int(u.data.get("zhili",0)),int(definition.para1),count)
		e2=Rules.skill_effect(int(u.data.get("zhili",0)),int(definition.para2),count)
	else:
		definition=b.data.items[str(iid)];apply=int(definition.apply_fw)
		e1=int(definition.para1);e2=int(definition.para2);facing=u.direction
	if kind in ["attack","skill"]:u.direction=facing
	var support:bool=(kind=="skill" and sid in [0,1,2,12]) or (kind=="item" and iid<31)
	var cells:Array=b._apply_tiles(tile,apply,facing)
	# Native target processing is map-row order after rotation, not slot order.
	cells.sort_custom(func(c,d):return c.tile.y<d.tile.y or (c.tile.y==d.tile.y and c.tile.x<d.tile.x))
	var opportunities:Array=[];var rolls:Dictionary={}
	if kind=="skill":
		event.cast=int(b.forecast_meta.casts.get(u.slot,0))+1
		b.forecast_meta.casts[u.slot]=event.cast
	if kind=="skill" and sid not in [0,1,2,15]:
		for ordinal in range(cells.size()):
			var cell:Dictionary=cells[ordinal];var v=b._unit_at(cell.tile)
			if v==null or support!=b.same_faction(u,v):continue
			var chance:int=maxi(0,30+2*(int(u.data.get("zhili",0))-int(v.data.get("zhili",0))))
			var immune:bool=sid==12 and v.bingzhong==45
			# Semantic IDs are branch-local opportunity names, NOT PRNG positions.
			var key:String="t%d/%s/g%d/d%d/a%d:i0/s%d/c%d/l%d,%d/v%d:i0@%d,%d/o%d/q%d/i%d,%d"%[
				b.turn,event.phase,event.generation,event.dispatch,u.slot,sid,event.cast,tile.x,tile.y,v.slot,v.x,v.y,ordinal,chance,int(u.data.get("zhili",0)),int(v.data.get("zhili",0))]
			var op:Dictionary={"key":key,"target_slot":v.slot,"target_tile":cell.tile,"cell_ordinal":ordinal,
				"chance":chance,"actor_int":int(u.data.get("zhili",0)),"target_int":int(v.data.get("zhili",0)),
				"immune_after_roll":immune,"requires_outcome":chance>0 and chance<100 and not immune,
				"deterministic":chance<=0 or chance>=100,"roll_before_immunity":true}
			opportunities.append(op);rolls[cell.tile]=op
	var mapping:=_check_outcomes(opportunities,outcomes,mode)
	if not mapping.complete:return _action_result(mapping.status,event,opportunities,mapping.reason)
	var attack:int=b._effective_attack(u);var base_xp:=0;var kill_xp:=0;var affected:=0;var deaths:Array=[]
	for cell in cells:
		var v=b._unit_at(cell.tile)
		if v==null or support!=b.same_faction(u,v):continue
		if rolls.has(cell.tile):
			var op:Dictionary=rolls[cell.tile]
			# Class45 still had a native roll; its two results are publicly
			# equivalent, so no RNG is invented and no successor key shifts.
			if op.immune_after_roll:op["roll_passed"]="elided-immune";continue
			var passed:bool=outcomes[op.key] if op.requires_outcome else op.chance>=100
			op["roll_passed"]=passed
			if not passed:continue
		var hp_before:int=v.hp;var morale_before:int=v.morale
		var hp:int=e1*int(cell.pct)/100;var morale:int=e2*int(cell.pct)/100
		var xp:=8 if u.side=="player" else 2;var effective:=true;var dmg:=0
		if kind=="attack":
			dmg=mini(v.hp,maxi(1,maxi(v.hp/20,Rules.damage(attack,b._effective_defense(v),int(cell.pct)))))
			base_xp+=Rules.hit_experience(int(u.data.get("level",1)),int(v.data.get("level",1)))>>(0 if u.side=="player" else 2)
			u.attack_count+=1;v.hp-=dmg;v.morale=maxi(0,v.morale-b._morale_loss(dmg,v.max_hp));v.last_damage_kind="gun"
		elif kind=="item":
			if support:
				if iid<21:v.hp=mini(v.max_hp,v.hp+maxi(0,hp));v.morale=mini(100,v.morale+maxi(0,morale))
			else:
				dmg=mini(v.hp,maxi(0,hp));v.hp-=dmg;v.morale=maxi(0,v.morale-morale);v.last_damage_kind="throw"
		else:
			match sid:
				0,1,2:
					if sid!=1:v.hp+=mini(hp,v.max_hp-v.hp)
					if sid!=0:v.morale+=mini(morale,100-v.morale)
					effective=v.hp>hp_before or v.morale>morale_before
					if sid==0:xp=maxi(4 if u.side=="player" else 2,(v.hp-hp_before)*(12 if u.side=="player" else 4)/maxi(1,e1))
					elif sid==1:xp=maxi(4 if u.side=="player" else 1,(v.morale-morale_before)*(12 if u.side=="player" else 4)/maxi(1,e2))
				3,4,5,13,14,15:
					var modifier:int=int(b.data.terrain_modifiers[b._terrain_at(cell.tile)][0 if sid==3 else 1]) if sid in [3,4,5] else 0
					dmg=mini(v.hp,maxi(0,hp*(100+modifier)/100));v.hp-=dmg;v.last_damage_kind="skill"
					if sid==14:v.morale=maxi(0,v.morale-morale)
					effective=v.hp<hp_before or v.morale<morale_before
					if sid in [3,4,5]:xp=maxi(4 if u.side=="player" else 2,dmg*(8 if u.side=="player" else 4)/maxi(1,e1))
				6:
					var loss:int=mini(v.morale,morale);v.morale-=loss;v.last_damage_kind="skill";effective=loss>0
					xp=maxi(4 if u.side=="player" else 2,loss*(8 if u.side=="player" else 4)/maxi(1,e2))
				7:v.defense_integrity=maxi(20,v.defense_integrity*7/10)
				8:v.integrity=maxi(50,v.integrity*7/10)
				10:v.data.level=maxi(1,int(v.data.get("level",1))-1);resize_hp(b,v)
				11:v.acted=true;v.moved=true
				12:
					if v.bingzhong==45:continue
					v.acted=false;v.moved=false;v.integrity=mini(100,v.integrity+20);v.defense_integrity=mini(100,v.defense_integrity+20)
			if effective:affected+=1;base_xp+=xp
		if kind=="attack" or (kind=="item" and not support) or (kind=="skill" and sid>=3 and effective):v.data.last_attacker_slot=u.slot
		if (v.hp<=0 or v.morale<=0) and (kind!="item" or dmg>0) and (kind!="skill" or effective):deaths.append(v)
	if kind=="skill":u.skill_counts[b.SKILL_KEYS[sid]]=count+affected
	u.acted=true
	for v in deaths:
		v.alive=false
		if kind=="item":
			gain_xp(b,u,Rules.kill_experience(int(u.data.get("level",1)),int(v.data.get("level",1)))>>1)
			record_death(b,v,true)
		else:
			kill_xp+=Rules.kill_experience(int(u.data.get("level",1)),int(v.data.get("level",1)));record_death(b,v)
	if kind=="attack":gain_xp(b,u,mini(48,base_xp)+kill_xp)
	elif kind=="skill":gain_xp(b,u,mini(16,base_xp)+kill_xp)
	elif kind=="item":Slots.remove_id(u.item_slots,iid+1);b._refresh_equipment(u)
	b.refresh_occupancy();return _action_result("complete",event,opportunities)

static func detonate(b,tile:Vector2i,walker:=-1) -> void:
	var queue:Array=[tile];var seen:Dictionary={}
	while not queue.is_empty():
		var at:Vector2i=queue.pop_front()
		if seen.has(at):continue
		seen[at]=true
		var idx:int=b._mine_at(at)
		if idx<0:continue
		var record:Dictionary=b.mines[idx];var definition:Dictionary=record.get("mine",b.data.mines[int(record.get("mine_id",0))%10])
		b.mines.remove_at(idx);var deaths:Array=[];var victims:Array=[]
		for cell in b._mine_area(at,int(definition.apply_fw)):
			if b._mine_at(cell.tile)>=0 and not seen.has(cell.tile):queue.append(cell.tile)
			var v=b._unit_at(cell.tile)
			if v==null:continue
			var amount:int=maxi(0,int(definition.weili)*int(cell.pct)/100);v.last_damage_kind="mine"
			if int(definition.shiqi_or_tili)==0:amount=mini(amount,v.hp);v.hp-=amount
			else:amount=mini(amount,v.morale);v.morale-=amount
			if amount>0 and (v.hp<=0 or v.morale<=0):deaths.append(v)
			victims.append({"slot":v.slot,"amount":amount,"alive":v.hp>0 and v.morale>0})
		for v in deaths:
			v.alive=false
			if v.side!="player":
				var count:=0
				for ally in b.units:
					if ally.alive and ally.side=="player" and ally.slot>=0 and ally.slot<40:count+=1
				if count>0:
					var raw:int=maxi(4,(int(v.data.get("level",1))-int(b.level.get("index",0)))*8+12)
					var award:int=mini(12,maxi(1,raw/count)+8);var ordered:Array=b.units.duplicate()
					ordered.sort_custom(func(a,c):return a.slot<c.slot)
					for ally in ordered:
						if ally.alive and ally.side=="player" and ally.slot>=0 and ally.slot<60:gain_xp(b,ally,award)
			record_death(b,v)
		b.mine_events.append({"walker":walker,"tile":at,"code":record.get("code",0),"victims":victims});b.refresh_occupancy()

static func next_ai(b):
	var next=null
	for u in b.units:
		if u.alive and u.placed and not u.acted and (next==null or u.slot<next.slot):next=u
	return next

static func drain_public_ai_phase(b,limit:=256) -> Dictionary:
	b.forecast_meta.phase="ai"
	for u in b.player_units:
		if u.alive and u.control and not u.auto:u.acted=true
	var plans:Array=[]
	for step in range(limit):
		var u=next_ai(b)
		if u==null:return {"status":"complete","complete":true,"plans":plans}
		var choice:Dictionary=Base.plan(b,u)
		var applied:Dictionary=apply_action(b,u,choice)
		plans.append({"slot":u.slot,"choice":choice,"status":applied.status})
		if not applied.complete:applied["plans"]=plans;return applied
	if next_ai(b)==null:return {"status":"complete","complete":true,"plans":plans}
	return {"status":"incomplete","complete":false,"reason":"AI step cap","plans":plans}

static func advance_public_round(b) -> Dictionary:
	if next_ai(b)!=null:return result("invalid","AI queue not drained")
	b.turn+=1;b.forecast_meta.generation+=1;b.forecast_meta.phase="player"
	for u in b.units:
		if not u.alive:continue
		u.acted=false;u.moved=false;u.status_stun=0
		var mods:Array=b.data.terrain_modifiers[b._terrain_at(Vector2i(u.x,u.y))]
		u.hp=mini(u.max_hp,u.hp+u.max_hp*int(mods[3])/100);u.morale=mini(100,u.morale+int(mods[4]))
		if b.unit_faction(u)==0:
			for raw in u.item_slots:
				if int(raw)==32:u.hp=mini(u.max_hp,u.hp+u.max_hp/4);u.morale=mini(100,u.morale+10)
				elif int(raw)==33:u.hp=mini(u.max_hp,u.hp+u.max_hp*15/100)
	var ordered:Array=[]
	for rec in b.mines:ordered.append(rec.tile)
	ordered.sort_custom(func(a,c):return a.y<c.y or (a.y==c.y and a.x<c.x))
	for tile in ordered:
		var idx:int=b._mine_at(tile)
		if idx<0:continue
		var low:int=int(b.mines[idx].get("low",1))
		if low>2:b.mines[idx].low=low-1
		elif low==2:detonate(b,tile)
	return result("complete","assuming-no-future-script-change")

static func apply_player_sequence(b,actions:Array) -> Dictionary:
	for entry in actions:
		var u=b.unit_by_slot(int(entry.slot))
		if u==null or u.side!="player" or not u.control or u.auto:return result("invalid","player permissions")
		var applied:Dictionary=apply_action(b,u,entry.action)
		if not applied.complete:return applied
	return result("complete")

static func snapshot(b) -> Dictionary:
	var units:Dictionary={}
	for u in b.units:units[u.slot]=u.state_record()
	return {"turn":b.turn,"units":units,"stats":b.stats.duplicate(true),"mines":b.mines.duplicate(true),"mine_events":b.mine_events.duplicate(true),"forecast_meta":b.forecast_meta.duplicate(true)}

static func critical_lost(b) -> bool:
	for u in b.units:
		if (u.slot==0 or u.protected) and not u.alive:return true
	return false

static func validate_public_source(source) -> Dictionary:
	var out:=result("invalid")
	if source.finished_flag:out["status"]="terminal";out["reason"]="source already finished";return out
	if source.phase!="player" or source.busy or source.action_resolution_depth!=0:
		out["reason"]="not a stable player decision boundary";return out
	var has_hero:=false
	for live in source.units:
		if live.slot==0:has_hero=true
		if live.alive and not live.placed:
			out["status"]="unsupported";out["reason"]="unplaced public actor";return out
		if live.slot==0 or source._bot_is_protected(live):
			if not live.alive:out["status"]="terminal";out["reason"]="source critical casualty";return out
			if not live.placed:out["status"]="unsupported";out["reason"]="unplaced critical actor";return out
	if not has_hero:out["reason"]="no public hero";return out
	return result("complete")

static func evaluate_two_phases(source,first:Array,second:Array,known_mine_tiles:Array=[],limit:=256) -> Dictionary:
	var out:Dictionary={"complete":false,"status":"invalid","conditional":true,"assumption":"no-future-script-change; supplied-public-mines-only; no-loot-or-relationship-lookahead","phases":[],"boundaries":[]}
	var entry:=validate_public_source(source)
	if not entry.complete:out.merge(entry,true);return out
	var b=clone_public_board(source,known_mine_tiles)
	for actions in [first,second]:
		var applied:Dictionary=apply_player_sequence(b,actions)
		if not applied.complete:out.merge(applied,true);b.free();return out
		if critical_lost(b):out.status="terminal";out["reason"]="critical casualty";b.free();return out
		var drained:Dictionary=drain_public_ai_phase(b,limit)
		out.phases.append({"ai":drained,"state":snapshot(b)})
		if not drained.complete:out.merge(drained,true);b.free();return out
		if critical_lost(b):out.status="terminal";out["reason"]="critical casualty";b.free();return out
		if out.phases.size()==1:
			var advanced:Dictionary=advance_public_round(b)
			if not advanced.complete:out.merge(advanced,true);b.free();return out
			out.boundaries.append(snapshot(b))
			if critical_lost(b):out.status="terminal";out["reason"]="critical boundary casualty";b.free();return out
	out.status="complete";out.complete=true;b.free();return out
